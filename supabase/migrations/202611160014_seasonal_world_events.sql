-- Seasonal event mission rewards use the existing server-validated economy.
-- Claims are scoped to the server's seasonal period and cannot be duplicated.
insert into public.economy_catalog(item_id,name,price,currency,active) values
('spring-petal-mobile','Bahar Yaprağı Düş Kapanı',75,'stars',true),
('spring-blossom-crown','Bahar Dalı Tacı',6,'seasonal_tokens',true),
('room-spring-rose-garland','Bahar Gülü Çelengi',6,'seasonal_tokens',true),
('summer-seashell-vase','Yaz Kabuğu Vazosu',95,'stars',true),
('summer-seaglass-pendant','Deniz Camı Kolye',6,'seasonal_tokens',true),
('solstice-gold-wings','Gündönümü Altın Kanatları',15,'seasonal_tokens',true),
('autumn-moon-lantern','Hasat Ayı Feneri',95,'stars',true),
('autumn-firefly-gown','Ateş Böceği Hasat Elbisesi',10,'seasonal_tokens',true),
('harvest-berry-wreath','Hasat Böğürtlenli Çelenk',110,'stars',true),
('winter-sugar-pine','Şeker Kış Çamı',5,'seasonal_tokens',true),
('winter-moon-cloak','Kış Ayı Kadife Pelerini',10,'seasonal_tokens',true),
('room-winter-star-tree','Kış Yıldızı Ağacı',8,'seasonal_tokens',true)
on conflict(item_id) do update set name=excluded.name,price=excluded.price,currency=excluded.currency,active=true;

insert into public.economy_rewards(reward_key,label,stars,crystals,seasonal_tokens,xp,item_id,metric,target,period,active) values
('event:spring-blossom:journal','Bahar Çiçekleri Festivali · Bahar dileği',12,0,2,15,'spring-petal-mobile','diaryEntries',1,'seasonal',true),
('event:spring-blossom:wander','Bahar Çiçekleri Festivali · Çiçekli patika',12,0,2,15,'spring-blossom-crown','discoveries',1,'seasonal',true),
('event:spring-blossom:decorate','Bahar Çiçekleri Festivali · Bahar sığınağı',12,0,2,15,'room-spring-rose-garland','decorations',1,'seasonal',true),
('event:summer-starlight:shore','Yaz Yıldızları Şenliği · Kıyı ziyareti',12,0,2,15,'summer-seashell-vase','worldVisits',1,'seasonal',true),
('event:summer-starlight:memory','Yaz Yıldızları Şenliği · Yıldız çiftleri',12,0,2,15,'summer-seaglass-pendant','memoryGames',1,'seasonal',true),
('event:summer-starlight:keepsake','Yaz Yıldızları Şenliği · Yaz hatırası',12,0,2,15,'solstice-gold-wings','collectibles',1,'seasonal',true),
('event:autumn-harvest:memory','Sonbahar Hasat Kutlaması · Hasat anısı',12,0,2,15,'autumn-moon-lantern','diaryEntries',1,'seasonal',true),
('event:autumn-harvest:keepsake','Sonbahar Hasat Kutlaması · Hasat hatırası',12,0,2,15,'autumn-firefly-gown','collectibles',1,'seasonal',true),
('event:autumn-harvest:lantern','Sonbahar Hasat Kutlaması · Fenerli sokak',12,0,2,15,'harvest-berry-wreath','discoveries',1,'seasonal',true),
('event:winter-crystal:wish','Kış Kristali Festivali · Kış dileği',12,0,2,15,'winter-sugar-pine','diaryEntries',1,'seasonal',true),
('event:winter-crystal:memory','Kış Kristali Festivali · Kristal çiftleri',12,0,2,15,'winter-moon-cloak','memoryGames',1,'seasonal',true),
('event:winter-crystal:visit','Kış Kristali Festivali · Kristal vadi ziyareti',12,0,2,15,'room-winter-star-tree','worldVisits',1,'seasonal',true)
on conflict(reward_key) do update set label=excluded.label,stars=excluded.stars,crystals=excluded.crystals,seasonal_tokens=excluded.seasonal_tokens,xp=excluded.xp,item_id=excluded.item_id,metric=excluded.metric,target=excluded.target,period=excluded.period,active=excluded.active;

