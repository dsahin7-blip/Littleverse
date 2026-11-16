-- Add wearable layer pieces to the same authoritative catalog used by purchases and equips.
insert into public.economy_catalog(item_id, name, price, currency, active) values
  ('top-lavender-knit', 'Lavanta Örgü Hırka', 38, 'stars', true),
  ('top-starlight-blouse', 'Yıldız Tozu Bluz', 72, 'stars', true),
  ('bottom-cloud-skirt', 'Bulut Katlı Etek', 42, 'stars', true),
  ('bottom-forest-trousers', 'Orman Gezgin Pantolonu', 78, 'stars', true),
  ('shoes-petal-flats', 'Papatya Babetler', 35, 'stars', true),
  ('shoes-moon-boots', 'Hilal Gece Çizmeleri', 65, 'stars', true)
on conflict (item_id) do update set
  name = excluded.name,
  price = excluded.price,
  currency = excluded.currency,
  active = excluded.active;

