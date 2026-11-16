-- Server-validated, one-time rewards for complete character wardrobe themes.

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
  v_event_key text;
  v_event_cap integer;
  v_world text;
  v_point text;
  v_first_stars bigint;
  v_first_crystals bigint;
  v_first_xp bigint;
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
      least(10000,greatest(0,coalesce((p_payload->>'stars')::bigint,240))),
      least(500,greatest(0,coalesce((p_payload->>'crystals')::bigint,18))),
      least(500,greatest(0,coalesce((p_payload->>'seasonal_tokens')::bigint,0))),
      least(35487,greatest(0,coalesce((p_payload->>'xp_total')::bigint,0))),true)
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
    if v_metric is null or (v_metric not in ('starTaps','diaryEntries','worldVisits','discoveries','purchases','decorations','collectibles','quizzes','loginDays','perfectDays','memoryGames','matchGames','worldRelics','secrets')
      and not ((v_metric like 'point:%' or v_metric like 'visit:%') and exists(select 1 from public.economy_rewards where metric=v_metric))) then raise exception 'INVALID_METRIC' using errcode='22023'; end if;
    v_event_key := p_payload->>'event_id';
    if v_event_key is null or length(v_event_key)<12 or length(v_event_key)>100 then raise exception 'INVALID_EVENT' using errcode='22023'; end if;
    v_event_cap := case
      when v_metric='starTaps' then 3
      when v_metric in ('diaryEntries','worldVisits','quizzes','loginDays','perfectDays','memoryGames','matchGames') then 1
      when v_metric in ('discoveries','secrets','decorations') or v_metric like 'point:%' or v_metric like 'visit:%' then 3
      when v_metric in ('collectibles','purchases') then 5
      else 100 end;
    v_period_key := v_today;
    select value into v_current from public.economy_metrics where user_id=uid and metric=v_metric and period='daily' and period_key=v_period_key;
    if coalesce(v_current,0)>=v_event_cap then raise exception 'DAILY_CAP_REACHED' using errcode='22023'; end if;
    v_created := false;
    insert into public.economy_event_keys(user_id,event_key,metric) values(uid,v_event_key,v_metric)
    on conflict(user_id,event_key) do nothing returning true into v_created;
    if not coalesce(v_created,false) then raise exception 'DUPLICATE_EVENT' using errcode='23505'; end if;
    v_added := 1;
    for v_period in select unnest(array['daily','weekly','seasonal','lifetime']) loop
      v_period_key := case v_period when 'daily' then v_today when 'weekly' then v_week when 'seasonal' then v_season else 'all' end;
      v_cap := case
        when v_period='daily' then v_event_cap
        when v_metric='starTaps' and v_period='weekly' then 20
        when v_metric='discoveries' and v_period='weekly' then 5
        when v_metric='diaryEntries' and v_period='weekly' then 3
        when v_metric='diaryEntries' and v_period='seasonal' then 8
        when v_metric='worldVisits' and v_period='seasonal' then 4
        when v_metric='decorations' and v_period='seasonal' then 5
        when v_metric='collectibles' and v_period='seasonal' then 8
        else 1000000 end;
      insert into public.economy_metrics(user_id,metric,period,period_key,value) values(uid,v_metric,v_period,v_period_key,v_added)
      on conflict(user_id,metric,period,period_key) do update set value=least(v_cap,economy_metrics.value+excluded.value);
    end loop;
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
    if exists(select 1 from public.economy_claims where user_id=uid and claim_key=v_key) then raise exception 'ALREADY_CLAIMED' using errcode='23505'; end if;
    if v_claim.reward_key like 'world-point:%' or v_claim.reward_key like 'world-quest:%' then
      v_point := case when v_claim.reward_key like 'world-quest:%' then split_part(v_claim.metric,':',2) else split_part(v_claim.reward_key,':',2) end;
      v_world := case
        when v_point in ('forest-well','moss-bridge','moon-tree') then 'enchanted-forest'
        when v_point in ('silver-square','lantern-alley','moon-rooftop') then 'moonlight-city'
        when v_point in ('geode-cave','singing-stream','glass-peak') then 'crystal-valley'
        when v_point in ('tide-pool','shell-grotto','sleeping-lighthouse') then 'dreamy-coast'
        when v_point in ('star-gate','royal-garden','fallen-star-tower') then 'starfall-kingdom'
        when v_point in ('cinnamon-bakery','postbox-lane','warm-attic') then 'cozy-village'
        else null end;
      if v_world is null then raise exception 'REWARD_UNAVAILABLE' using errcode='22023'; end if;
      if v_world not in ('enchanted-forest','moonlight-city') and not exists(select 1 from public.economy_claims where user_id=uid and claim_key='world-unlock:'||v_world||':once') then raise exception 'WORLD_LOCKED' using errcode='42501'; end if;
      if not exists(select 1 from public.economy_claims where user_id=uid and claim_key='world-first:'||v_world||':once') then raise exception 'REQUIREMENT_NOT_MET' using errcode='22023'; end if;
      if v_point in ('moon-tree','moon-rooftop','glass-peak','sleeping-lighthouse','fallen-star-tower','warm-attic') and not exists(select 1 from public.economy_claims c join public.economy_rewards r on r.reward_key=split_part(c.claim_key,':',1)||':'||split_part(c.claim_key,':',2) where c.user_id=uid and c.claim_key like 'world-point:%:once' and c.claim_key<>'world-point:'||v_point||':once' and r.reward_key like 'world-point:%' and ((v_world='enchanted-forest' and r.label like 'Keşif: Büyülü Orman%') or (v_world='moonlight-city' and r.label like 'Keşif: Ay Işığı Şehri%') or (v_world='crystal-valley' and r.label like 'Keşif: Kristal Vadisi%') or (v_world='dreamy-coast' and r.label like 'Keşif: Düş Kıyısı%') or (v_world='starfall-kingdom' and r.label like 'Keşif: Yıldız Yağmuru Krallığı%') or (v_world='cozy-village' and r.label like 'Keşif: Sıcacık Köy%'))) then raise exception 'REQUIREMENT_NOT_MET' using errcode='22023'; end if;
      if v_claim.reward_key like 'world-quest:%' and not exists(select 1 from public.economy_claims where user_id=uid and claim_key='world-point:'||v_point||':once') then raise exception 'REQUIREMENT_NOT_MET' using errcode='22023'; end if;
    elsif v_claim.reward_key like 'world-first:%' then
      v_world := split_part(v_claim.reward_key,':',2);
      if v_world not in ('enchanted-forest','moonlight-city') and not exists(select 1 from public.economy_claims where user_id=uid and claim_key='world-unlock:'||v_world||':once') then raise exception 'WORLD_LOCKED' using errcode='42501'; end if;
    end if;
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
    elsif v_claim.metric='discoveries' then
      select count(*) into v_current from public.economy_claims c where c.user_id=uid and c.claim_key like 'world-point:%:once'
        and (v_claim.period='once' or v_claim.period='daily' and c.claimed_at>=date_trunc('day',now()) or v_claim.period='weekly' and c.claimed_at>=date_trunc('week',now()) or v_claim.period='seasonal' and c.claimed_at>=date_trunc('year',now()));    elsif v_claim.metric='worldVisits' then
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
    elsif v_claim.metric like 'character-set:%' then
      select count(*) into v_current from public.economy_inventory where user_id=uid and (
        (v_claim.metric='character-set:moon' and item_id in ('outfit-moonqueen','headwear-moon','necklace-moon')) or
        (v_claim.metric='character-set:rose' and item_id in ('outfit-rose','headwear-flower','earrings-rose')) or
        (v_claim.metric='character-set:forest' and item_id in ('outfit-forest','headwear-flower','wings-butterfly')) or
        (v_claim.metric='character-set:stargazer' and item_id in ('outfit-stargazer','headwear-halo','necklace-star'))
      );
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
      if not exists(select 1 from public.economy_claims where user_id=uid and claim_key='world-first:'||v_unlock_id||':once') then
        select stars,crystals,xp into v_first_stars,v_first_crystals,v_first_xp from public.economy_rewards where reward_key='world-first:'||v_unlock_id and active;
        insert into public.economy_claims(user_id,claim_key) values(uid,'world-first:'||v_unlock_id||':once');
        v_claim.stars:=v_claim.stars+coalesce(v_first_stars,0);
        v_claim.crystals:=v_claim.crystals+coalesce(v_first_crystals,0);
        v_claim.xp:=v_claim.xp+coalesce(v_first_xp,0);
        v_claim.label:=v_claim.label||' · ilk ziyaret armağanı';
      end if;
    end if;
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

insert into public.economy_rewards(reward_key,label,stars,metric,target,period,active) values
  ('character-set:moon','Ay Işığı Masalı set ödülü',45,'character-set:moon',3,'once',true),
  ('character-set:rose','Gül Bahçesi set ödülü',45,'character-set:rose',3,'once',true),
  ('character-set:forest','Orman Yolcusu set ödülü',45,'character-set:forest',3,'once',true),
  ('character-set:stargazer','Yıldız Gözlemcisi set ödülü',45,'character-set:stargazer',3,'once',true)
on conflict (reward_key) do update set label=excluded.label,stars=excluded.stars,metric=excluded.metric,target=excluded.target,period=excluded.period,active=excluded.active;
