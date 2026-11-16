alter function public.littleverse_xp_for_next(integer) set search_path = '';
alter function public.littleverse_level_for_xp(bigint) set search_path = '';
create index if not exists economy_inventory_item_id_idx on public.economy_inventory(item_id);
create index if not exists economy_rewards_item_id_idx on public.economy_rewards(item_id);
