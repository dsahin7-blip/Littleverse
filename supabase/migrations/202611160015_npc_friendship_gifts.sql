create or replace function public.littleverse_npc_gift(p_npc_id text, p_item_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  uid uuid := auth.uid();
  v_today text := to_char(timezone('Europe/Istanbul', now()), 'YYYY-MM-DD');
  v_key text;
  v_created boolean := false;
  v_removed text;
  w public.economy_wallets%rowtype;
  v_inventory jsonb;
  v_history jsonb;
begin
  if uid is null then raise exception 'AUTH_REQUIRED' using errcode = '42501'; end if;
  if p_npc_id is null or p_npc_id not in ('aylin','findik','niva','aras','elya','soren','lalin','deniz','miray','ruya','cemre','toprak') then
    raise exception 'NPC_UNAVAILABLE' using errcode = '22023';
  end if;
  if p_item_id is null or length(p_item_id) > 120 then raise exception 'ITEM_NOT_OWNED' using errcode = '22023'; end if;

  -- Initialize/roll over the wallet using the same server-owned source used by the economy.
  perform public.littleverse_economy('snapshot', '{}'::jsonb);
  v_key := 'npc-gift:' || p_npc_id || ':' || v_today;
  insert into public.economy_event_keys(user_id, event_key, metric)
  values (uid, v_key, 'npcGift')
  on conflict (user_id, event_key) do nothing
  returning true into v_created;
  if not coalesce(v_created, false) then raise exception 'NPC_DAILY_GIFT_USED' using errcode = '23505'; end if;

  delete from public.economy_inventory
  where user_id = uid and item_id = p_item_id
  returning item_id into v_removed;
  if v_removed is null then raise exception 'ITEM_NOT_OWNED' using errcode = '42501'; end if;

  insert into public.economy_transactions(user_id, idempotency_key, kind, source, item_id, metadata)
  values (uid, v_key, 'spent', 'Hediye: ' || p_npc_id, p_item_id,
    jsonb_build_object('npc_id', p_npc_id, 'gifted_at_local_date', v_today));

  select * into w from public.economy_wallets where user_id = uid;
  select coalesce(jsonb_agg(item_id order by item_id), '[]'::jsonb)
    into v_inventory from public.economy_inventory where user_id = uid;
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', id, 'kind', kind, 'source', source, 'stars_delta', stars_delta,
      'crystals_delta', crystals_delta, 'seasonal_tokens_delta', seasonal_tokens_delta,
      'xp_delta', xp_delta, 'item_id', item_id, 'metadata', metadata, 'created_at', created_at
    ) order by id desc), '[]'::jsonb)
    into v_history
    from (select * from public.economy_transactions where user_id = uid order by id desc limit 500) t;

  return jsonb_build_object(
    'ok', true,
    'wallet', jsonb_build_object('stars', w.stars, 'crystals', w.crystals,
      'seasonal_tokens', w.seasonal_tokens, 'xp_total', w.xp_total,
      'level', public.littleverse_level_for_xp(w.xp_total)),
    'inventory', v_inventory,
    'history', v_history,
    'item_id', p_item_id
  );
end;
$function$;

revoke all on function public.littleverse_npc_gift(text, text) from public, anon;
grant execute on function public.littleverse_npc_gift(text, text) to authenticated;

