-- Littleverse authoritative economy. Wallet mutations are only available through
-- the authenticated, atomic RPC below; the transaction ledger is append-only.
create table if not exists public.economy_wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  stars bigint not null default 240 check (stars >= 0),
  crystals bigint not null default 18 check (crystals >= 0),
  seasonal_tokens bigint not null default 0 check (seasonal_tokens >= 0),
  season_key text not null default '',
  xp_total bigint not null default 0 check (xp_total >= 0),
  legacy_imported boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.economy_catalog (
  item_id text primary key,
  name text not null,
  price bigint not null check (price >= 0),
  currency text not null check (currency in ('stars','crystals','seasonal_tokens')),
  active boolean not null default true
);

create table if not exists public.economy_inventory (
  user_id uuid not null references auth.users(id) on delete cascade,
  item_id text not null references public.economy_catalog(item_id),
  acquired_at timestamptz not null default now(),
  source text not null default 'purchase',
  primary key (user_id,item_id)
);

create table if not exists public.economy_transactions (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  idempotency_key text not null,
  kind text not null check (kind in ('earned','spent','reward','purchase','adjustment','milestone','seasonal')),
  source text not null,
  stars_delta bigint not null default 0,
  crystals_delta bigint not null default 0,
  seasonal_tokens_delta bigint not null default 0,
  xp_delta bigint not null default 0,
  item_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(user_id,idempotency_key)
);

create table if not exists public.economy_claims (
  user_id uuid not null references auth.users(id) on delete cascade,
  claim_key text not null,
  claimed_at timestamptz not null default now(),
  primary key(user_id,claim_key)
);

create table if not exists public.economy_metrics (
  user_id uuid not null references auth.users(id) on delete cascade,
  metric text not null,
  period text not null,
  period_key text not null,
  value bigint not null default 0 check(value >= 0),
  primary key(user_id,metric,period,period_key)
);

create table if not exists public.economy_rewards (
  reward_key text primary key,
  label text not null,
  stars bigint not null default 0 check(stars >= 0),
  crystals bigint not null default 0 check(crystals >= 0),
  seasonal_tokens bigint not null default 0 check(seasonal_tokens >= 0),
  xp bigint not null default 0 check(xp >= 0),
  item_id text references public.economy_catalog(item_id),
  metric text,
  target bigint,
  period text not null default 'once' check(period in ('once','daily','weekly','seasonal')),
  active boolean not null default true
);

alter table public.economy_wallets enable row level security;
alter table public.economy_catalog enable row level security;
alter table public.economy_inventory enable row level security;
alter table public.economy_transactions enable row level security;
alter table public.economy_claims enable row level security;
alter table public.economy_metrics enable row level security;
alter table public.economy_rewards enable row level security;

drop policy if exists "read own economy wallet" on public.economy_wallets;
create policy "read own economy wallet" on public.economy_wallets for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "read active economy catalog" on public.economy_catalog;
create policy "read active economy catalog" on public.economy_catalog for select to authenticated using (active);
drop policy if exists "read own economy inventory" on public.economy_inventory;
create policy "read own economy inventory" on public.economy_inventory for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "read own economy transactions" on public.economy_transactions;
create policy "read own economy transactions" on public.economy_transactions for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "read own economy claims" on public.economy_claims;
create policy "read own economy claims" on public.economy_claims for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "read own economy metrics" on public.economy_metrics;
create policy "read own economy metrics" on public.economy_metrics for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "read active economy rewards" on public.economy_rewards;
create policy "read active economy rewards" on public.economy_rewards for select to authenticated using (active);

revoke all on public.economy_wallets, public.economy_catalog, public.economy_inventory,
  public.economy_transactions, public.economy_claims, public.economy_metrics,
  public.economy_rewards from anon, authenticated;
grant select on public.economy_wallets, public.economy_inventory, public.economy_transactions,
  public.economy_claims, public.economy_metrics to authenticated;
grant select on public.economy_catalog, public.economy_rewards to authenticated;
grant usage,select on sequence public.economy_transactions_id_seq to authenticated;

create or replace function public.littleverse_xp_for_next(p_level integer)
returns bigint language sql immutable as $$
  select case when p_level >= 100 then 0 else 80 + (p_level::bigint * 18) + floor(power(p_level::numeric,1.35)*2)::bigint end;
$$;

create or replace function public.littleverse_level_for_xp(p_xp bigint)
returns integer language plpgsql immutable as $$
declare lv integer := 1; remaining bigint := greatest(0,p_xp); need bigint;
begin
  while lv < 100 loop
    need := public.littleverse_xp_for_next(lv);
    exit when remaining < need;
    remaining := remaining - need;
    lv := lv + 1;
  end loop;
  return lv;
end; $$;

create or replace function public.littleverse_economy(p_action text, p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  w public.economy_wallets%rowtype;
  v_key text;
  v_source text;
  v_item text;
  v_currency text;
  v_price bigint;
  v_stars bigint := 0;
  v_crystals bigint := 0;
  v_tokens bigint := 0;
  v_xp bigint := 0;
  v_metric text;
  v_period text;
  v_period_key text;
  v_target bigint;
  v_current bigint;
  v_cap bigint := 1000000;
  v_created boolean := false;
  v_unlock_id text;
  v_claim public.economy_rewards%rowtype;
  v_level integer;
  v_added integer;
  v_inventory jsonb;
  v_history jsonb;
  v_today text := to_char(timezone('utc',now()),'YYYY-MM-DD');
  v_week text := to_char(date_trunc('week',timezone('utc',now())),'YYYY-MM-DD');
  v_season text := to_char(timezone('utc',now()),'YYYY')||'-'||case when extract(month from timezone('utc',now())) between 3 and 5 then 'spring' when extract(month from timezone('utc',now())) between 6 and 8 then 'summer' when extract(month from timezone('utc',now())) between 9 and 11 then 'autumn' else 'winter' end;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;

  if p_action='initialize' then
    -- One-time compatibility import for the existing local-first prototype. The import
    -- is capped and recorded once; all subsequent wallet operations are server-only.
    insert into public.economy_wallets(user_id,stars,crystals,seasonal_tokens,xp_total,legacy_imported)
    values(uid,
      least(1000000,greatest(0,coalesce((p_payload->>'stars')::bigint,240))),
      least(100000,greatest(0,coalesce((p_payload->>'crystals')::bigint,18))),
      least(100000,greatest(0,coalesce((p_payload->>'seasonal_tokens')::bigint,0))),
      least(100000000,greatest(0,coalesce((p_payload->>'xp_total')::bigint,0))),true)
    on conflict(user_id) do nothing returning true into v_created;
    -- Import owned legacy item ids only if they exist in the server catalog; never
    -- accept a client price, balance delta or future ownership mutation.
    if coalesce(v_created,false) then
      insert into public.economy_inventory(user_id,item_id,source)
      select uid, c.item_id, 'legacy-import' from public.economy_catalog c
      where c.item_id in (select jsonb_array_elements_text(coalesce(p_payload->'owned','[]'::jsonb)))
      on conflict do nothing;
    end if;
  elsif p_action not in ('snapshot','history','purchase','reward','claim','event','equip') then
    raise exception 'INVALID_ACTION' using errcode='22023';
  end if;

  select * into w from public.economy_wallets where user_id=uid for update;
  if not found then
    insert into public.economy_wallets(user_id,season_key) values(uid,v_season) returning * into w;
  elsif w.season_key<>v_season then
    if w.seasonal_tokens>0 then
      insert into public.economy_transactions(user_id,idempotency_key,kind,source,seasonal_tokens_delta,metadata)
      values(uid,'season-expiry:'||w.season_key,'adjustment','Mevsim tokeni dönemi sona erdi',-w.seasonal_tokens,jsonb_build_object('expired_season',w.season_key));
    end if;
    update public.economy_wallets set seasonal_tokens=0,season_key=v_season,updated_at=now() where user_id=uid returning * into w;
  end if;

  if p_action='purchase' then
    v_item := p_payload->>'item_id';
    v_key := 'purchase:'||coalesce(p_payload->>'request_id',gen_random_uuid()::text);
    select price,currency into v_price,v_currency from public.economy_catalog where item_id=v_item and active;
    if not found then raise exception 'ITEM_UNAVAILABLE' using errcode='22023'; end if;
    if exists(select 1 from public.economy_inventory where user_id=uid and item_id=v_item) then raise exception 'ALREADY_OWNED' using errcode='23505'; end if;
    if v_currency='stars' and w.stars<v_price or v_currency='crystals' and w.crystals<v_price or v_currency='seasonal_tokens' and w.seasonal_tokens<v_price then raise exception 'INSUFFICIENT_FUNDS' using errcode='22003'; end if;
    v_stars := case when v_currency='stars' then -v_price else 0 end;
    v_crystals := case when v_currency='crystals' then -v_price else 0 end;
    v_tokens := case when v_currency='seasonal_tokens' then -v_price else 0 end;
    v_xp := 8;
    insert into public.economy_inventory(user_id,item_id,source) values(uid,v_item,'purchase');
    v_source := 'Mağaza satın alımı';
  elsif p_action='event' then
    v_metric := p_payload->>'metric';
    if v_metric not in ('starTaps','diaryEntries','worldVisits','discoveries','purchases','decorations','collectibles','quizzes','loginDays','perfectDays','memoryGames','matchGames','worldRelics','secrets')
      and not ((v_metric like 'point:%' or v_metric like 'visit:%') and exists(select 1 from public.economy_rewards where metric=v_metric)) then raise exception 'INVALID_METRIC' using errcode='22023'; end if;
    v_period := coalesce(p_payload->>'period','lifetime');
    if v_period not in ('daily','weekly','seasonal','lifetime') then raise exception 'INVALID_PERIOD' using errcode='22023'; end if;
    v_period_key := case v_period when 'daily' then v_today when 'weekly' then v_week when 'seasonal' then v_season else 'all' end;
    v_added := least(1,greatest(0,coalesce((p_payload->>'amount')::integer,1)));
    v_cap := case
      when v_metric='starTaps' and v_period='daily' then 3
      when v_metric='starTaps' and v_period='weekly' then 20
      when v_metric like 'point:%' then 1
      when v_metric like 'visit:%' then 1
      when v_metric='decorations' and v_period='daily' then 1
      when v_metric='decorations' and v_period='seasonal' then 5
      when v_metric='diaryEntries' and v_period='daily' then 1
      when v_metric='diaryEntries' and v_period='weekly' then 3
      when v_metric='diaryEntries' and v_period='seasonal' then 8
      when v_metric='worldVisits' and v_period='daily' then 1
      when v_metric='worldVisits' and v_period='seasonal' then 4
      when v_metric='discoveries' and v_period='weekly' then 5
      when v_metric='collectibles' and v_period='seasonal' then 8
      else 1000000 end;
    insert into public.economy_metrics(user_id,metric,period,period_key,value) values(uid,v_metric,v_period,v_period_key,v_added)
    on conflict(user_id,metric,period,period_key) do update set value=least(v_cap,economy_metrics.value+excluded.value);
  elsif p_action='equip' then
    v_item := p_payload->>'item_id';
    if not exists(select 1 from public.economy_inventory where user_id=uid and item_id=v_item) then raise exception 'ITEM_NOT_OWNED' using errcode='42501'; end if;
    return jsonb_build_object('ok',true,'equipped',v_item,'wallet',jsonb_build_object('stars',w.stars,'crystals',w.crystals,'seasonal_tokens',w.seasonal_tokens,'xp_total',w.xp_total,'level',public.littleverse_level_for_xp(w.xp_total)));
  elsif p_action='claim' or p_action='reward' then
    v_key := p_payload->>'claim_key';
    select * into v_claim from public.economy_rewards where reward_key=v_key and active;
    if not found then raise exception 'REWARD_UNAVAILABLE' using errcode='22023'; end if;
    v_period_key := case v_claim.period when 'daily' then v_today when 'weekly' then v_week when 'seasonal' then v_season else 'once' end;
    v_key := v_claim.reward_key||':'||v_period_key;
    if v_claim.metric='level' then
      v_current := public.littleverse_level_for_xp(w.xp_total);
      if coalesce(v_current,0)<coalesce(v_claim.target,1) then raise exception 'REQUIREMENT_NOT_MET' using errcode='22023'; end if;
    elsif v_claim.metric='collectibles' then
      select count(*) into v_current from public.economy_inventory where user_id=uid;
      if coalesce(v_current,0)<coalesce(v_claim.target,1) then raise exception 'REQUIREMENT_NOT_MET' using errcode='22023'; end if;
    elsif v_claim.metric='worldRelics' then
      select count(*) into v_current from public.economy_inventory i join public.economy_rewards r on r.item_id=i.item_id where i.user_id=uid and r.reward_key like 'world-point:%';
      if coalesce(v_current,0)<coalesce(v_claim.target,1) then raise exception 'REQUIREMENT_NOT_MET' using errcode='22023'; end if;
    elsif v_claim.metric='purchases' then
      select count(*) into v_current from public.economy_transactions t where t.user_id=uid and t.kind='purchase'
        and (v_claim.period='once' or v_claim.period='daily' and t.created_at>=date_trunc('day',now()) or v_claim.period='weekly' and t.created_at>=date_trunc('week',now()) or v_claim.period='seasonal' and t.created_at>=date_trunc('year',now()));
      if coalesce(v_current,0)<coalesce(v_claim.target,1) then raise exception 'REQUIREMENT_NOT_MET' using errcode='22023'; end if;
    elsif v_claim.metric='discoveries' then
      select count(*) into v_current from public.economy_claims c where c.user_id=uid and c.claim_key like 'world-point:%'
        and (v_claim.period='once' or v_claim.period='daily' and c.claimed_at>=date_trunc('day',now()) or v_claim.period='weekly' and c.claimed_at>=date_trunc('week',now()) or v_claim.period='seasonal' and c.claimed_at>=date_trunc('year',now()));
      if coalesce(v_current,0)<coalesce(v_claim.target,1) then raise exception 'REQUIREMENT_NOT_MET' using errcode='22023'; end if;
    elsif v_claim.metric='worldVisits' then
      if v_claim.period='once' then
        select count(*) into v_current from public.economy_claims c where c.user_id=uid and c.claim_key like 'world-first:%';
      else
        v_period := case v_claim.period when 'daily' then 'daily' when 'weekly' then 'weekly' else 'seasonal' end;
        select value into v_current from public.economy_metrics where user_id=uid and metric='worldVisits' and period=v_period and period_key=case v_period when 'daily' then v_today when 'weekly' then v_week else v_season end;
      end if;
      if coalesce(v_current,0)<coalesce(v_claim.target,1) then raise exception 'REQUIREMENT_NOT_MET' using errcode='22023'; end if;
    elsif v_claim.metric='earnedStars' then
      select coalesce(sum(greatest(stars_delta,0)),0) into v_current from public.economy_transactions where user_id=uid;
      if coalesce(v_current,0)<coalesce(v_claim.target,1) then raise exception 'REQUIREMENT_NOT_MET' using errcode='22023'; end if;
    elsif v_claim.metric='earnedCrystals' then
      select coalesce(sum(greatest(crystals_delta,0)),0) into v_current from public.economy_transactions where user_id=uid;
      if coalesce(v_current,0)<coalesce(v_claim.target,1) then raise exception 'REQUIREMENT_NOT_MET' using errcode='22023'; end if;
    elsif v_claim.metric='loginDays' then
      select count(*) into v_current from public.economy_claims where user_id=uid and claim_key like 'login:%';
      if coalesce(v_current,0)<coalesce(v_claim.target,1) then raise exception 'REQUIREMENT_NOT_MET' using errcode='22023'; end if;
    elsif v_claim.metric='questClaims' then
      select count(*) into v_current from public.economy_claims where user_id=uid and (claim_key like 'daily:%' or claim_key like 'weekly:%' or claim_key like 'season:%');
      if coalesce(v_current,0)<coalesce(v_claim.target,1) then raise exception 'REQUIREMENT_NOT_MET' using errcode='22023'; end if;
    elsif v_claim.metric='dailyClaims' then
      select count(*) into v_current from public.economy_claims where user_id=uid and claim_key like 'daily:%';
      if coalesce(v_current,0)<coalesce(v_claim.target,1) then raise exception 'REQUIREMENT_NOT_MET' using errcode='22023'; end if;
    elsif v_claim.metric='secrets' then
      select count(*) into v_current from public.economy_claims where user_id=uid and claim_key in ('world-point:moon-tree:once','world-point:moon-rooftop:once','world-point:glass-peak:once','world-point:sleeping-lighthouse:once','world-point:fallen-star-tower:once','world-point:warm-attic:once');
      if coalesce(v_current,0)<coalesce(v_claim.target,1) then raise exception 'REQUIREMENT_NOT_MET' using errcode='22023'; end if;
    elsif v_claim.metric is not null then
      v_period := case v_claim.period when 'daily' then 'daily' when 'weekly' then 'weekly' when 'seasonal' then 'seasonal' else 'lifetime' end;
      select value into v_current from public.economy_metrics where user_id=uid and metric=v_claim.metric and period=v_period and period_key=case v_period when 'daily' then v_today when 'weekly' then v_week when 'seasonal' then v_season else 'all' end;
      if coalesce(v_current,0)<coalesce(v_claim.target,1) then raise exception 'REQUIREMENT_NOT_MET' using errcode='22023'; end if;
    end if;
    if v_claim.reward_key like 'world-unlock:%' then
      v_unlock_id := split_part(v_claim.reward_key,':',2);
      if v_unlock_id in ('enchanted-forest','moonlight-city') then raise exception 'REWARD_UNAVAILABLE' using errcode='22023'; end if;
      if v_unlock_id='crystal-valley' and not (w.stars>=320 or w.xp_total>=520) then raise exception 'REQUIREMENT_NOT_MET' using errcode='22023'; end if;
      if v_unlock_id='dreamy-coast' then
        select count(*) into v_current from public.economy_claims where user_id=uid and claim_key like 'world-first:%';
        if coalesce(v_current,0)<3 then raise exception 'REQUIREMENT_NOT_MET' using errcode='22023'; end if;
      end if;
      if v_unlock_id='starfall-kingdom' then
        select count(*) into v_current from public.economy_claims where user_id=uid and claim_key in ('world-point:moon-tree:once','world-point:moon-rooftop:once','world-point:glass-peak:once','world-point:sleeping-lighthouse:once','world-point:fallen-star-tower:once','world-point:warm-attic:once');
        if w.stars<500 or coalesce(v_current,0)<2 then raise exception 'REQUIREMENT_NOT_MET' using errcode='22023'; end if;
      end if;
      if v_unlock_id='cozy-village' then
        select value into v_current from public.economy_metrics where user_id=uid and metric='worldRelics' and period='lifetime' and period_key='all';
        if public.littleverse_level_for_xp(w.xp_total)<5 or coalesce(v_current,0)<6 then raise exception 'REQUIREMENT_NOT_MET' using errcode='22023'; end if;
      end if;
    end if;
    if exists(select 1 from public.economy_claims where user_id=uid and claim_key=v_key) then raise exception 'ALREADY_CLAIMED' using errcode='23505'; end if;
    insert into public.economy_claims(user_id,claim_key) values(uid,v_key);
    v_stars:=v_claim.stars; v_crystals:=v_claim.crystals; v_tokens:=v_claim.seasonal_tokens; v_xp:=v_claim.xp; v_source:=v_claim.label;
    v_item := v_claim.item_id;
    if v_item is not null then insert into public.economy_inventory(user_id,item_id,source) values(uid,v_item,'reward') on conflict do nothing; end if;
  end if;

  if v_stars<>0 or v_crystals<>0 or v_tokens<>0 or v_xp<>0 then
    if w.stars+v_stars<0 or w.crystals+v_crystals<0 or w.seasonal_tokens+v_tokens<0 then raise exception 'INSUFFICIENT_FUNDS' using errcode='22003'; end if;
    update public.economy_wallets set stars=stars+v_stars,crystals=crystals+v_crystals,seasonal_tokens=seasonal_tokens+v_tokens,xp_total=xp_total+v_xp,updated_at=now() where user_id=uid returning * into w;
    insert into public.economy_transactions(user_id,idempotency_key,kind,source,stars_delta,crystals_delta,seasonal_tokens_delta,xp_delta,item_id,metadata)
    values(uid,coalesce(v_key,'event:'||gen_random_uuid()::text),case when v_item is not null then 'purchase' when v_stars<0 or v_crystals<0 or v_tokens<0 then 'spent' when p_action='claim' or p_action='reward' then 'reward' else 'earned' end,coalesce(v_source,p_payload->>'metric','Oyun içi hareket'),v_stars,v_crystals,v_tokens,v_xp,v_item,jsonb_build_object('action',p_action));
  elsif v_item is not null then
    insert into public.economy_transactions(user_id,idempotency_key,kind,source,item_id,metadata)
    values(uid,v_key,'purchase','Mağaza satın alımı',v_item,jsonb_build_object('currency',v_currency,'price',v_price));
  end if;

  -- Meaningful level milestones unlock a cosmetic item automatically. Each milestone
  -- uses a unique ledger key, so retries cannot duplicate either the item or its grant.
  v_level := public.littleverse_level_for_xp(w.xp_total);
  for v_claim in select * from public.economy_rewards where reward_key like 'milestone:%' and active and target<=v_level loop
    v_key := v_claim.reward_key||':once';
    if not exists(select 1 from public.economy_claims where user_id=uid and claim_key=v_key) then
      insert into public.economy_claims(user_id,claim_key) values(uid,v_key);
      if v_claim.item_id is not null then insert into public.economy_inventory(user_id,item_id,source) values(uid,v_claim.item_id,'milestone') on conflict do nothing; end if;
      insert into public.economy_transactions(user_id,idempotency_key,kind,source,item_id,metadata)
      values(uid,'milestone:'||v_claim.target,'milestone',v_claim.label,v_claim.item_id,jsonb_build_object('level',v_claim.target));
    end if;
  end loop;

  select coalesce(jsonb_agg(item_id order by item_id),'[]'::jsonb) into v_inventory from public.economy_inventory where user_id=uid;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'kind',kind,'source',source,'stars_delta',stars_delta,'crystals_delta',crystals_delta,'seasonal_tokens_delta',seasonal_tokens_delta,'xp_delta',xp_delta,'item_id',item_id,'metadata',metadata,'created_at',created_at) order by id desc),'[]'::jsonb)
    into v_history from (select * from public.economy_transactions where user_id=uid order by id desc limit 500) t;
  return jsonb_build_object('ok',true,'wallet',jsonb_build_object('stars',w.stars,'crystals',w.crystals,'seasonal_tokens',w.seasonal_tokens,'xp_total',w.xp_total,'level',public.littleverse_level_for_xp(w.xp_total)),'inventory',v_inventory,'history',v_history,'item_id',v_item);
end; $$;

revoke all on function public.littleverse_economy(text,jsonb) from public,anon;
grant execute on function public.littleverse_economy(text,jsonb) to authenticated;

create or replace function public.reject_economy_transaction_mutation()
returns trigger language plpgsql set search_path = '' as $$
begin raise exception 'ECONOMY_LEDGER_IMMUTABLE'; end; $$;
drop trigger if exists economy_transaction_immutable on public.economy_transactions;
create trigger economy_transaction_immutable before update or delete on public.economy_transactions
for each row execute function public.reject_economy_transaction_mutation();

insert into public.economy_rewards(reward_key,label,stars,crystals,xp,metric,target,period) values
 ('daily:stars','Günlük görev: Üç yıldız yakala',30,0,25,'starTaps',3,'daily'),
 ('daily:diary','Günlük görev: Kendine küçük bir not bırak',25,0,20,'diaryEntries',1,'daily'),
 ('daily:world','Günlük görev: Bir dünyayı ziyaret et',35,0,30,'worldVisits',1,'daily'),
 ('daily:shop','Günlük görev: Koleksiyonuna yeni bir parça ekle',20,1,18,'purchases',1,'daily'),
 ('daily:decorate','Günlük görev: Sığınağına dokunuş kat',25,0,22,'decorations',1,'daily'),
 ('weekly:weekly-explorer','Haftalık: İz sürücüsü',100,3,80,'discoveries',5,'weekly'),
 ('weekly:weekly-starweaver','Haftalık: Yıldız dokuyucusu',120,2,90,'starTaps',20,'weekly'),
 ('weekly:weekly-journal','Haftalık: Anı biriktiren',80,4,70,'diaryEntries',3,'weekly'),
 ('season:season-visitor','Mevsimlik: Mevsimin gezgini',180,8,150,'worldVisits',4,'seasonal'),
 ('season:season-collector','Mevsimlik: Mevsim hatıraları',160,10,140,'collectibles',8,'seasonal'),
 ('season:season-caretaker','Mevsimlik: Sığınağın bahçıvanı',140,7,120,'decorations',5,'seasonal'),
 ('login','Günlük giriş armağanı',10,1,5,null,null,'daily'),
 ('surprise','Günlük Gizem Kutusu',25,2,15,null,null,'daily'),
 ('memory','Hafıza Kartları tamamlandı',15,0,12,null,null,'daily'),
 ('match','Büyülü Eşleştirme tamamlandı',18,0,15,null,null,'daily'),
 ('quiz','Günlük Ruh Testi tamamlandı',0,2,12,null,null,'daily'),
 ('world-first','İlk dünya ziyareti',8,0,8,null,null,'once'),
 ('world-unlock','Dünya açılışı',8,0,12,null,null,'once'),
 ('world-discovery','Dünya keşfi',0,0,0,null,null,'once'),
 ('diary-entry','Günlük notu',0,0,12,null,null,'daily'),
 ('purchase-xp','Mağaza alışveriş deneyimi',0,0,8,null,null,'once')
 ,('world-quest-forest-well-daily','Dünya görevi: Kuyunun fısıltısını dinle',18,0,18,null,null,'daily')
 ,('world-quest-forest-secret-daily','Dünya görevi: Ay Ağacının sırrını bul',28,0,26,null,null,'daily')
 ,('world-quest-city-lantern-daily','Dünya görevi: Fener Sokağında bir ışık yak',18,0,18,null,null,'daily')
 ,('world-quest-city-roof-daily','Dünya görevi: Çatıdaki hilali ziyaret et',28,0,26,null,null,'daily')
 ,('world-quest-valley-stream-daily','Dünya görevi: Derenin ezgisini bul',20,0,20,null,null,'daily')
 ,('world-quest-valley-peak-daily','Dünya görevi: Cam Zirveye ulaş',30,0,28,null,null,'daily')
 ,('world-quest-coast-tide-daily','Dünya görevi: Gelgit havuzuna göz at',20,0,20,null,null,'daily')
 ,('world-quest-coast-lighthouse-daily','Dünya görevi: Uyuyan fenerin sırrını bul',30,0,28,null,null,'daily')
 ,('world-quest-kingdom-garden-daily','Dünya görevi: Kraliyet bahçesinin çiçeğini bul',24,0,22,null,null,'daily')
 ,('world-quest-kingdom-tower-daily','Dünya görevi: Yıldız Kulesinin tepesine çık',34,0,30,null,null,'daily')
 ,('world-quest-village-bakery-daily','Dünya görevi: Fırından sıcak bir anı al',20,0,20,null,null,'daily')
 ,('world-quest-village-attic-daily','Dünya görevi: Çatı arasındaki sırrı aç',30,0,28,null,null,'daily')
 ,('star-tap-1','Yıldız Avcısı · ilk günlük yıldız',5,0,2,null,null,'daily')
 ,('star-tap-2','Yıldız Avcısı · ikinci günlük yıldız',5,0,2,null,null,'daily')
 ,('star-tap-3','Yıldız Avcısı · üçüncü günlük yıldız',5,0,2,null,null,'daily')
on conflict(reward_key) do update set label=excluded.label,stars=excluded.stars,crystals=excluded.crystals,xp=excluded.xp,metric=excluded.metric,target=excluded.target,period=excluded.period;



-- Prices and ownership IDs copied from the audited game catalog. Quest/world rewards are not purchasable.
insert into public.economy_catalog(item_id,name,price,currency,active) values
('soft-sofa','Bulut Koltuk',85,'stars',true),
('moon-lamp','Ay Işığı Lambası',65,'stars',true),
('fern-pot','Orman Eğreltisi',45,'stars',true),
('dream-cushion','Düş Bulutu Minderi',35,'stars',true),
('lilac-chair','Leylak Berjer',115,'stars',true),
('mushroom-stool','Mantar Tabure',3,'crystals',true),
('starlight-dress','Yıldız Tozu Elbise',120,'stars',true),
('lavender-cape','Lavanta Pelerini',95,'stars',true),
('moon-crown','Hilal Tacı',4,'crystals',true),
('pearl-earrings','İnci Küpeler',70,'stars',true),
('butterfly-pin','Kelebek Broş',40,'stars',true),
('blue-teacup','Bulut Çayı Fincanı',2,'crystals',true),
('moon-mint-tonic','Ay Nanesi İksiri',45,'stars',true),
('dream-bloom-elixir','Düş Çiçeği Özütü',2,'crystals',true),
('starlight-phial','Yıldız Işığı Şişesi',3,'crystals',true),
('rainbow-dew-vial','Gökkuşağı Çiyi',5,'crystals',true),
('tiny-moon-moth','Minik Ay Güvesi',85,'stars',true),
('moon-bed','Ay Işığı Karyolası',0,'stars',false),
('rose-bed','Gül Bahçesi Yatağı',145,'stars',true),
('cloud-bed','Bulut Yatağı',4,'crystals',true),
('moss-bed','Yosun Örgülü Karyola',110,'stars',true),
('twilight-sofa','Alacakaranlık Kanepesi',120,'stars',true),
('mushroom-chair','Mantar Evi Berjeri',0,'stars',false),
('cloud-seat','Bulut Pufu',55,'stars',true),
('rose-loveseat','Gül Kurusu İkili Koltuk',3,'crystals',true),
('writing-desk','Masal Yazarı Masası',90,'stars',true),
('star-desk','Takımyıldız Çalışma Masası',135,'stars',true),
('teacup-desk','Çay Saati Sekreteri',3,'crystals',true),
('little-bookcase','Minik Hikâye Rafı',75,'stars',true),
('moon-shelf','Hilal Duvar Rafı',100,'stars',true),
('secret-library','Gizli Kütüphane Rafı',3,'crystals',true),
('lilac-rug','Leylak Tüyü Halı',60,'stars',true),
('stardust-rug','Yıldız Tozu Kilimi',90,'stars',true),
('rose-rug','Gül Yaprağı Halısı',2,'crystals',true),
('moon-lantern','Ay Feneri',50,'stars',true),
('star-chandelier','Yıldız Damlası Avize',3,'crystals',true),
('dream-lamp','Düş Bahçesi Lambası',85,'stars',true),
('firefly-lamp','Ateş Böceği Kavanozu',0,'stars',false),
('moonflower-pot','Ay Çiçeği Saksısı',80,'stars',true),
('fairy-orchid','Peri Orkidesi',2,'crystals',true),
('hanging-vines','Sarkan Sarmaşıklar',65,'stars',true),
('moon-print','Ay Bahçesi Baskısı',40,'stars',true),
('constellation-frame','Takımyıldız Çerçevesi',75,'stars',true),
('secret-garden-painting','Gizli Bahçe Tablosu',3,'crystals',true),
('moon-mirror','Hilal Aynası',5,'crystals',true),
('tea-tray','Çiçekli Çay Tepsisi',40,'stars',true),
('crystal-mobile','Kristal Rüya Süsü',2,'crystals',true),
('moon-clock','Ay Fazları Saati',70,'stars',true),
('garden-arch','Sarmaşıklı Bahçe Kemeri',110,'stars',true),
('garden-fountain','Fısıltı Çeşmesi',3,'crystals',true),
('starlight-bench','Yıldız Seyri Bankı',80,'stars',true),
('balcony-planter','Bulut Saksılığı',55,'stars',true),
('rose-balcony-planter','Gül Işığı Balkonluğu',0,'stars',false),
('balcony-swing','Hilal Balkon Salıncağı',4,'crystals',true),
('balcony-lanterns','Balkon Işık Dizisi',90,'stars',true),
('autumn-moon-lantern','Hasat Ayı Feneri',95,'stars',true),
('winter-sugar-pine','Şeker Kış Çamı',3,'crystals',true),
('spring-petal-mobile','Bahar Yaprağı Düş Kapanı',75,'stars',true),
('summer-seashell-vase','Yaz Sedefi Vazo',2,'crystals',true),
('solstice-star-frame','Gündönümü Yıldız Çerçevesi',6,'crystals',true),
('harvest-berry-wreath','Kızıl Meyve Çelengi',60,'stars',true),
('face-round','Ay yuvarlağı',0,'stars',false),
('face-oval','Yumuşak oval',0,'stars',false),
('face-heart','Kalp çizgisi',55,'stars',true),
('face-petal','Çiçek yaprağı',3,'crystals',true),
('skin-porcelain','Porselen',0,'stars',false),
('skin-peach','Şeftali',0,'stars',false),
('skin-honey','Bal köpüğü',0,'stars',false),
('skin-olive','Zeytin güneşi',45,'stars',true),
('skin-cocoa','Kakao',65,'stars',true),
('skin-deep','Gece çiçeği',2,'crystals',true),
('expr-gentle','Yumuşacık gülümseme',0,'stars',false),
('expr-dreamy','Düşlere dalmış',0,'stars',false),
('expr-curious','Meraklı bakış',35,'stars',true),
('expr-laugh','Neşeli kahkaha',55,'stars',true),
('expr-serene','Sakinlik',2,'crystals',true),
('hair-long','Ay ışığı dalgaları',0,'stars',false),
('hair-bob','Leylak küt',0,'stars',false),
('hair-braids','Çifte örgü',45,'stars',true),
('hair-curls','Bulut bukleleri',70,'stars',true),
('hair-ponytail','Yıldızlı at kuyruğu',80,'stars',true),
('hair-halfup','Yarım toplu',95,'stars',true),
('hair-crownbraid','Taç örgüsü',3,'crystals',true),
('hair-moonpixie','Ay perisi kısa saç',5,'crystals',true),
('haircolor-chestnut','Kestane',0,'stars',false),
('haircolor-honey','Bal sarısı',0,'stars',false),
('haircolor-midnight','Gece moru',0,'stars',false),
('haircolor-rose','Gül pembesi',45,'stars',true),
('haircolor-silver','Ay gümüşü',65,'stars',true),
('haircolor-teal','Deniz camı',2,'crystals',true),
('haircolor-starlight','Yıldız tozu',5,'crystals',true),
('eyes-violet','Menekşe',0,'stars',false),
('eyes-hazel','Fındık',0,'stars',false),
('eyes-ocean','Okyanus',40,'stars',true),
('eyes-emerald','Zümrüt',55,'stars',true),
('eyes-rose','Pembe kuvars',2,'crystals',true),
('eyes-starlit','Yıldızlı gece',5,'crystals',true),
('outfit-twilight','Alacakaranlık elbisesi',0,'stars',false),
('outfit-cardigan','Sıcak çay hırkası',0,'stars',false),
('outfit-cloud','Bulut tülü',85,'stars',true),
('outfit-rose','Gül bahçesi elbisesi',95,'stars',true),
('outfit-stargazer','Yıldız gözlemcisi',120,'stars',true),
('outfit-forest','Orman perisi pelerini',3,'crystals',true),
('outfit-lavender','Lavanta rüyası',150,'stars',true),
('outfit-moonqueen','Ay kraliçesi',6,'crystals',true),
('outfit-mushroom','Mantar evi tulumu',105,'stars',true),
('outfit-snow','Kar tanesi örgüsü',3,'crystals',true),
('headwear-ribbon','Gül kurdelesi',0,'stars',false),
('headwear-flower','Çiçek tacı',35,'stars',true),
('headwear-moon','Gümüş Hilal Tacı',75,'stars',true),
('headwear-witch','Yıldızlı cadı şapkası',3,'crystals',true),
('headwear-halo','Işık halesi',6,'crystals',true),
('earrings-pearl','İnci damlaları',0,'stars',false),
('earrings-moon','Minik hilaller',45,'stars',true),
('earrings-crystal','Kristal yıldızlar',2,'crystals',true),
('earrings-rose','Gül kuvarsı',60,'stars',true),
('earrings-night','Gece parıltısı',5,'crystals',true),
('wings-none','Kanatsız',0,'stars',false),
('wings-moth','Güve kanatları',0,'stars',false),
('wings-butterfly','Kelebek kanatları',95,'stars',true),
('wings-moon','Ay ışığı tülleri',3,'crystals',true),
('wings-starlight','Yıldız tozu kanatları',6,'crystals',true),
('necklace-moon','Ay taşı kolye',0,'stars',false),
('necklace-star','Kutup yıldızı',55,'stars',true),
('necklace-heart','Pembe kuvars kalp',35,'stars',true),
('necklace-crystal','Kristal damla',2,'crystals',true),
('necklace-constellation','Takımyıldız zinciri',5,'crystals',true),
('autumn-firefly-gown','Ateş Böceği Hasat Elbisesi',3,'crystals',true),
('winter-moon-cloak','Kış Ayı Kadife Pelerini',4,'crystals',true),
('spring-blossom-crown','Bahar Dalı Tacı',85,'stars',true),
('summer-seaglass-pendant','Deniz Camı Kolye',3,'crystals',true),
('solstice-gold-wings','Gündönümü Altın Kanatları',7,'crystals',true),
('forest-dew','Ay Çiyi Damlası',0,'stars',false),
('forest-acorn','Yıldızlı Meşe Palamudu',0,'stars',false),
('forest-moonseed','Ay Ağacı Tohumu',0,'stars',false),
('city-clockwork','Gümüş Saat Dişlisi',0,'stars',false),
('city-lantern','Gümüş Sokak Feneri',0,'stars',false),
('city-mooncharm','Hilal Muska',0,'stars',false),
('valley-geode','Mavi Kristal Jeot',0,'stars',false),
('valley-waterbell','Su Çanı',0,'stars',false),
('valley-prism','Gökkuşağı Prizması',0,'stars',false),
('coast-shell','Sedefli Deniz Kabuğu',0,'stars',false),
('coast-tideglass','Gelgit Camı',0,'stars',false),
('coast-lighthouse','Düş Feneri',0,'stars',false),
('kingdom-starglass','Yıldız Camı',0,'stars',false),
('kingdom-nightrose','Gece Gülü',0,'stars',false),
('kingdom-starcore','Düşmüş Yıldız Çekirdeği',0,'stars',false),
('village-cookie','Tarçınlı Kurabiye',0,'stars',false),
('village-letter','Köyden Bir Mektup',0,'stars',false),
('village-thimble','Büyülü Yüksük',0,'stars',false)
on conflict(item_id) do update set name=excluded.name,price=excluded.price,currency=excluded.currency,active=excluded.active;


-- World rewards, level milestones and every achievement reward are server-allowlisted.
insert into public.economy_rewards(reward_key,label,stars,crystals,xp,metric,target,period,item_id) values
('world-point:forest-well','Keşif: Büyülü Orman · Fısıltı Kuyusu',12,0,14,'point:forest-well',1,'once','forest-dew'),
('world-point:moss-bridge','Keşif: Büyülü Orman · Yosunlu Köprü',16,0,17,'point:moss-bridge',1,'once','forest-acorn'),
('world-point:moon-tree','Keşif: Büyülü Orman · Ay Ağacının Kalbi',22,0,24,'point:moon-tree',1,'once','forest-moonseed'),
('world-quest:forest-well-daily','Dünya görevi: Kuyunun fısıltısını dinle',18,0,18,'point:forest-well',1,'daily',null),
('world-quest:forest-secret-daily','Dünya görevi: Ay Ağacının sırrını bul',28,0,26,'point:moon-tree',1,'daily',null),
('world-point:silver-square','Keşif: Ay Işığı Şehri · Gümüş Meydan',12,0,14,'point:silver-square',1,'once','city-clockwork'),
('world-point:lantern-alley','Keşif: Ay Işığı Şehri · Fener Sokağı',16,0,17,'point:lantern-alley',1,'once','city-lantern'),
('world-point:moon-rooftop','Keşif: Ay Işığı Şehri · Hilal Çatısı',22,0,24,'point:moon-rooftop',1,'once','city-mooncharm'),
('world-quest:city-lantern-daily','Dünya görevi: Fener Sokağında bir ışık yak',18,0,18,'point:lantern-alley',1,'daily',null),
('world-quest:city-roof-daily','Dünya görevi: Çatıdaki hilali ziyaret et',28,0,26,'point:moon-rooftop',1,'daily',null),
('world-point:blue-geode','Keşif: Kristal Vadisi · Mavi Jeot Mağarası',14,0,16,'point:blue-geode',1,'once','valley-geode'),
('world-point:singing-stream','Keşif: Kristal Vadisi · Şarkı Söyleyen Dere',18,0,19,'point:singing-stream',1,'once','valley-waterbell'),
('world-point:glass-peak','Keşif: Kristal Vadisi · Cam Zirve',24,0,27,'point:glass-peak',1,'once','valley-prism'),
('world-quest:valley-stream-daily','Dünya görevi: Derenin ezgisini bul',20,0,20,'point:singing-stream',1,'daily',null),
('world-quest:valley-peak-daily','Dünya görevi: Cam Zirveye ulaş',30,0,28,'point:glass-peak',1,'daily',null),
('world-point:shell-cove','Keşif: Düş Kıyısı · Sedef Koyu',14,0,16,'point:shell-cove',1,'once','coast-shell'),
('world-point:tide-pool','Keşif: Düş Kıyısı · Gelgit Havuzu',18,0,19,'point:tide-pool',1,'once','coast-tideglass'),
('world-point:sleeping-lighthouse','Keşif: Düş Kıyısı · Uyuyan Fener',24,0,27,'point:sleeping-lighthouse',1,'once','coast-lighthouse'),
('world-quest:coast-tide-daily','Dünya görevi: Gelgit havuzuna göz at',20,0,20,'point:tide-pool',1,'daily',null),
('world-quest:coast-lighthouse-daily','Dünya görevi: Uyuyan fenerin sırrını bul',30,0,28,'point:sleeping-lighthouse',1,'daily',null),
('world-point:star-gate','Keşif: Yıldız Yağmuru Krallığı · Yıldız Kapısı',16,0,18,'point:star-gate',1,'once','kingdom-starglass'),
('world-point:royal-garden','Keşif: Yıldız Yağmuru Krallığı · Uyuyan Kraliyet Bahçesi',20,0,22,'point:royal-garden',1,'once','kingdom-nightrose'),
('world-point:fallen-star-tower','Keşif: Yıldız Yağmuru Krallığı · Düşen Yıldız Kulesi',28,0,30,'point:fallen-star-tower',1,'once','kingdom-starcore'),
('world-quest:kingdom-garden-daily','Dünya görevi: Kraliyet bahçesinin çiçeğini bul',24,0,22,'point:royal-garden',1,'daily',null),
('world-quest:kingdom-tower-daily','Dünya görevi: Yıldız Kulesinin tepesine çık',34,0,30,'point:fallen-star-tower',1,'daily',null),
('world-point:cinnamon-bakery','Keşif: Sıcacık Köy · Tarçın Fırını',14,0,16,'point:cinnamon-bakery',1,'once','village-cookie'),
('world-point:postbox-lane','Keşif: Sıcacık Köy · Mektup Sokağı',18,0,19,'point:postbox-lane',1,'once','village-letter'),
('world-point:warm-attic','Keşif: Sıcacık Köy · Çatı Arası',24,0,27,'point:warm-attic',1,'once','village-thimble'),
('world-quest:village-bakery-daily','Dünya görevi: Fırından sıcak bir anı al',20,0,20,'point:cinnamon-bakery',1,'daily',null),
('world-quest:village-attic-daily','Dünya görevi: Çatı arasındaki sırrı aç',30,0,28,'point:warm-attic',1,'daily',null),
('achievement:starTaps-1','Başarım rozeti: Yıldız avcısı',10,0,10,'starTaps',1,'once',null),
('achievement:starTaps-5','Başarım rozeti: Yıldız avcısı 2',10,0,10,'starTaps',5,'once',null),
('achievement:starTaps-10','Başarım rozeti: Yıldız avcısı 3',20,1,20,'starTaps',10,'once',null),
('achievement:starTaps-25','Başarım rozeti: Yıldız avcısı 4',20,1,20,'starTaps',25,'once',null),
('achievement:starTaps-50','Başarım rozeti: Yıldız avcısı 5',35,2,35,'starTaps',50,'once',null),
('achievement:starTaps-100','Başarım rozeti: Yıldız avcısı 6',35,2,35,'starTaps',100,'once',null),
('achievement:starTaps-250','Başarım rozeti: Yıldız avcısı 7',60,4,60,'starTaps',250,'once',null),
('achievement:starTaps-500','Başarım rozeti: Yıldız avcısı 8',60,4,60,'starTaps',500,'once',null),
('achievement:diaryEntries-1','Başarım rozeti: Düş günlüğü',10,0,10,'diaryEntries',1,'once',null),
('achievement:diaryEntries-3','Başarım rozeti: Düş günlüğü 2',10,0,10,'diaryEntries',3,'once',null),
('achievement:diaryEntries-5','Başarım rozeti: Düş günlüğü 3',20,1,20,'diaryEntries',5,'once',null),
('achievement:diaryEntries-10','Başarım rozeti: Düş günlüğü 4',20,1,20,'diaryEntries',10,'once',null),
('achievement:diaryEntries-20','Başarım rozeti: Düş günlüğü 5',35,2,35,'diaryEntries',20,'once',null),
('achievement:diaryEntries-35','Başarım rozeti: Düş günlüğü 6',35,2,35,'diaryEntries',35,'once',null),
('achievement:diaryEntries-60','Başarım rozeti: Düş günlüğü 7',60,4,60,'diaryEntries',60,'once',null),
('achievement:diaryEntries-100','Başarım rozeti: Düş günlüğü 8',60,4,60,'diaryEntries',100,'once',null),
('achievement:worldVisits-1','Başarım rozeti: Gezgin ruh',10,0,10,'worldVisits',1,'once',null),
('achievement:worldVisits-2','Başarım rozeti: Gezgin ruh 2',10,0,10,'worldVisits',2,'once',null),
('achievement:worldVisits-3','Başarım rozeti: Gezgin ruh 3',20,1,20,'worldVisits',3,'once',null),
('achievement:worldVisits-4','Başarım rozeti: Gezgin ruh 4',20,1,20,'worldVisits',4,'once',null),
('achievement:worldVisits-5','Başarım rozeti: Gezgin ruh 5',35,2,35,'worldVisits',5,'once',null),
('achievement:worldVisits-6','Başarım rozeti: Gezgin ruh 6',35,2,35,'worldVisits',6,'once',null),
('achievement:discoveries-1','Başarım rozeti: Sırların izinde',10,0,10,'discoveries',1,'once',null),
('achievement:discoveries-3','Başarım rozeti: Sırların izinde 2',10,0,10,'discoveries',3,'once',null),
('achievement:discoveries-6','Başarım rozeti: Sırların izinde 3',20,1,20,'discoveries',6,'once',null),
('achievement:discoveries-10','Başarım rozeti: Sırların izinde 4',20,1,20,'discoveries',10,'once',null),
('achievement:discoveries-15','Başarım rozeti: Sırların izinde 5',35,2,35,'discoveries',15,'once',null),
('achievement:discoveries-18','Başarım rozeti: Sırların izinde 6',35,2,35,'discoveries',18,'once',null),
('achievement:purchases-1','Başarım rozeti: Küçük koleksiyoncu',10,0,10,'purchases',1,'once',null),
('achievement:purchases-3','Başarım rozeti: Küçük koleksiyoncu 2',10,0,10,'purchases',3,'once',null),
('achievement:purchases-5','Başarım rozeti: Küçük koleksiyoncu 3',20,1,20,'purchases',5,'once',null),
('achievement:purchases-10','Başarım rozeti: Küçük koleksiyoncu 4',20,1,20,'purchases',10,'once',null),
('achievement:purchases-20','Başarım rozeti: Küçük koleksiyoncu 5',35,2,35,'purchases',20,'once',null),
('achievement:purchases-35','Başarım rozeti: Küçük koleksiyoncu 6',35,2,35,'purchases',35,'once',null),
('achievement:decorations-1','Başarım rozeti: Yuva kuran',10,0,10,'decorations',1,'once',null),
('achievement:decorations-3','Başarım rozeti: Yuva kuran 2',10,0,10,'decorations',3,'once',null),
('achievement:decorations-5','Başarım rozeti: Yuva kuran 3',20,1,20,'decorations',5,'once',null),
('achievement:decorations-10','Başarım rozeti: Yuva kuran 4',20,1,20,'decorations',10,'once',null),
('achievement:decorations-20','Başarım rozeti: Yuva kuran 5',35,2,35,'decorations',20,'once',null),
('achievement:decorations-40','Başarım rozeti: Yuva kuran 6',35,2,35,'decorations',40,'once',null),
('achievement:earnedStars-50','Başarım rozeti: Yıldız biriktiren',10,0,10,'earnedStars',50,'once',null),
('achievement:earnedStars-200','Başarım rozeti: Yıldız biriktiren 2',10,0,10,'earnedStars',200,'once',null),
('achievement:earnedStars-500','Başarım rozeti: Yıldız biriktiren 3',20,1,20,'earnedStars',500,'once',null),
('achievement:earnedStars-1000','Başarım rozeti: Yıldız biriktiren 4',20,1,20,'earnedStars',1000,'once',null),
('achievement:earnedStars-2500','Başarım rozeti: Yıldız biriktiren 5',35,2,35,'earnedStars',2500,'once',null),
('achievement:earnedStars-5000','Başarım rozeti: Yıldız biriktiren 6',35,2,35,'earnedStars',5000,'once',null),
('achievement:earnedCrystals-1','Başarım rozeti: Kristal koruyucusu',10,0,10,'earnedCrystals',1,'once',null),
('achievement:earnedCrystals-5','Başarım rozeti: Kristal koruyucusu 2',10,0,10,'earnedCrystals',5,'once',null),
('achievement:earnedCrystals-15','Başarım rozeti: Kristal koruyucusu 3',20,1,20,'earnedCrystals',15,'once',null),
('achievement:earnedCrystals-30','Başarım rozeti: Kristal koruyucusu 4',20,1,20,'earnedCrystals',30,'once',null),
('achievement:earnedCrystals-75','Başarım rozeti: Kristal koruyucusu 5',35,2,35,'earnedCrystals',75,'once',null),
('achievement:earnedCrystals-150','Başarım rozeti: Kristal koruyucusu 6',35,2,35,'earnedCrystals',150,'once',null),
('achievement:first-note','Başarım rozeti: İlk satır',10,0,10,'diaryEntries',1,'once',null),
('achievement:world-trio','Başarım rozeti: Üç dünyanın kapısı',20,1,20,'worldVisits',3,'once',null),
('achievement:atlas-complete','Başarım rozeti: Atlasın tamam',60,4,60,'worldVisits',6,'once',null),
('achievement:secret-keeper','Başarım rozeti: Sırların bekçisi',35,2,35,'secrets',2,'once',null),
('achievement:keepsake-collector','Başarım rozeti: Dünya koleksiyoncusu',35,2,35,'worldRelics',6,'once',null),
('achievement:home-sweet-home','Başarım rozeti: Ev gibi ev',10,0,10,'decorations',1,'once',null),
('achievement:well-traveled','Başarım rozeti: Her yol bir masal',35,2,35,'discoveries',10,'once',null),
('achievement:level-five','Başarım rozeti: Yükselen yıldız',20,1,20,'level',5,'once',null),
('achievement:level-ten','Başarım rozeti: Gümüş yolcu',35,2,35,'level',10,'once',null),
('achievement:level-twentyfive','Başarım rozeti: Göksel yolcu',60,4,60,'level',25,'once',null),
('achievement:level-fifty','Başarım rozeti: Littleverse efsanesi',60,4,60,'level',50,'once',null),
('achievement:daily-claim','Başarım rozeti: Günün armağanı',10,0,10,'dailyClaims',1,'once',null),
('achievement:quest-ten','Başarım rozeti: İstikrarlı yolcu',20,1,20,'questClaims',10,'once',null),
('achievement:quest-fifty','Başarım rozeti: Görev ustası',35,2,35,'questClaims',50,'once',null),
('achievement:quiz-first','Başarım rozeti: Ruhunun rengi',10,0,10,'quizzes',1,'once',null),
('achievement:visitor-seven','Başarım rozeti: Bir haftalık merak',20,1,20,'loginDays',7,'once',null),
('achievement:perfect-day','Başarım rozeti: Pırıl pırıl gün',35,2,35,'perfectDays',1,'once',null),
('milestone:5','5. seviye · Gümüş Hilal Tacı',0,0,0,'level',5,'once','headwear-moon'),
('milestone:10','10. seviye · Kelebek Kanatları',0,0,0,'level',10,'once','wings-butterfly'),
('milestone:15','15. seviye · Gül Bahçesi Yatağı',0,0,0,'level',15,'once','rose-bed'),
('milestone:20','20. seviye · Orman Perisi Pelerini',0,0,0,'level',20,'once','outfit-forest'),
('milestone:30','30. seviye · Taç Örgüsü',0,0,0,'level',30,'once','hair-crownbraid'),
('milestone:50','50. seviye · Yıldız Tozu Kanatları',0,0,0,'level',50,'once','wings-starlight'),
('milestone:75','75. seviye · Ay Kraliçesi',0,0,0,'level',75,'once','outfit-moonqueen'),
('milestone:100','100. seviye · Gündönümü Altın Kanatları',0,0,0,'level',100,'once','solstice-gold-wings')
on conflict(reward_key) do update set label=excluded.label,stars=excluded.stars,crystals=excluded.crystals,xp=excluded.xp,metric=excluded.metric,target=excluded.target,period=excluded.period,item_id=excluded.item_id;


-- Per-world first-visit and unlock rewards remain individually claimable.
insert into public.economy_rewards(reward_key,label,stars,crystals,xp,period) values
('world-first:enchanted-forest','İlk ziyaret: Büyülü Orman',8,0,8,'once'),
('world-first:moonlight-city','İlk ziyaret: Ay Işığı Şehri',8,0,8,'once'),
('world-first:crystal-valley','İlk ziyaret: Kristal Vadisi',8,0,8,'once'),
('world-first:dreamy-coast','İlk ziyaret: Düş Kıyısı',8,0,8,'once'),
('world-first:starfall-kingdom','İlk ziyaret: Yıldız Yağmuru Krallığı',8,0,8,'once'),
('world-first:cozy-village','İlk ziyaret: Sıcacık Köy',8,0,8,'once'),
('world-unlock:enchanted-forest','Büyülü Orman dünyası açılışı',8,0,12,'once'),
('world-unlock:moonlight-city','Ay Işığı Şehri dünyası açılışı',8,0,12,'once'),
('world-unlock:crystal-valley','Kristal Vadisi dünyası açılışı',8,0,12,'once'),
('world-unlock:dreamy-coast','Düş Kıyısı dünyası açılışı',8,0,12,'once'),
('world-unlock:starfall-kingdom','Yıldız Yağmuru Krallığı dünyası açılışı',8,0,12,'once'),
('world-unlock:cozy-village','Sıcacık Köy dünyası açılışı',8,0,12,'once')
on conflict(reward_key) do update set label=excluded.label,stars=excluded.stars,crystals=excluded.crystals,xp=excluded.xp,period=excluded.period;
update public.economy_rewards set seasonal_tokens=case reward_key when 'season:season-visitor' then 5 when 'season:season-collector' then 8 when 'season:season-caretaker' then 4 else seasonal_tokens end where reward_key in ('season:season-visitor','season:season-collector','season:season-caretaker');
update public.economy_rewards set metric='diaryEntries',target=1 where reward_key='diary-entry';
update public.economy_rewards set metric='memoryGames',target=1 where reward_key='memory';
update public.economy_rewards set metric='matchGames',target=1 where reward_key='match';
update public.economy_rewards set metric='quizzes',target=1 where reward_key='quiz';
update public.economy_rewards set metric='starTaps',target=1 where reward_key='star-tap-1';
update public.economy_rewards set metric='starTaps',target=2 where reward_key='star-tap-2';
update public.economy_rewards set metric='starTaps',target=3 where reward_key='star-tap-3';
update public.economy_catalog set price=5,currency='seasonal_tokens' where item_id in ('winter-sugar-pine','summer-seashell-vase');
update public.economy_catalog set price=10,currency='seasonal_tokens' where item_id in ('solstice-star-frame','autumn-firefly-gown','winter-moon-cloak');
update public.economy_catalog set price=6,currency='seasonal_tokens' where item_id in ('spring-blossom-crown','summer-seaglass-pendant');
update public.economy_catalog set price=15,currency='seasonal_tokens' where item_id='solstice-gold-wings';
insert into public.economy_catalog(item_id,name,price,currency,active) values
 ('collection-moon-map','Ay Atlası Duvar Panosu',0,'stars',false),
 ('collection-star-lantern','Takımyıldızlı Fener',0,'stars',false)
on conflict(item_id) do update set name=excluded.name,price=excluded.price,currency=excluded.currency,active=false;
insert into public.economy_rewards(reward_key,label,stars,crystals,xp,metric,target,period,item_id) values
 ('achievement:collection-25','Küçük bir atlas · Ay Atlası Duvar Panosu',0,2,35,'collectibles',25,'once','collection-moon-map'),
 ('achievement:collection-50','Yıldızlı küratör · Takımyıldızlı Fener',0,4,60,'collectibles',50,'once','collection-star-lantern')
on conflict(reward_key) do update set label=excluded.label,stars=excluded.stars,crystals=excluded.crystals,xp=excluded.xp,metric=excluded.metric,target=excluded.target,period=excluded.period,item_id=excluded.item_id;
update public.economy_rewards set active=false where reward_key in ('world-first','world-unlock');
update public.economy_rewards set metric='visit:'||split_part(reward_key,':',2),target=1 where reward_key like 'world-first:%';
