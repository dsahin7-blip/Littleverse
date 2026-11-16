-- Progress-event audit keys are visible only to their owner; no client can write them.
drop policy if exists "read own economy event keys" on public.economy_event_keys;
create policy "read own economy event keys" on public.economy_event_keys
  for select to authenticated using ((select auth.uid()) = user_id);
grant select on public.economy_event_keys to authenticated;

-- XP helpers are internal to the authoritative RPC; they are not public APIs.
revoke all on function public.littleverse_xp_for_next(integer) from public, anon, authenticated;
revoke all on function public.littleverse_level_for_xp(bigint) from public, anon, authenticated;
