# Littleverse

**Littleverse — Sana ait küçük bir dünya** için Türkçe, mobil uyumlu ilk oyun prototipi.

## Neler var?

- Ana sayfa, seviye/XP, yıldızlar, kristaller ve günlük sürpriz
- Görev ilerlemesi ve ödül toplama
- Etkileşimli yatak odası, bahçe ve balkon düzenleyicisi; 40+ çizimli eşya, dokunarak yerleştirme ve sürükleyerek taşıma
- Yataklar, koltuklar, masalar, raflar, halılar, ışıklar, bitkiler, duvar sanatı, dekorasyon, bahçe/balkon parçaları, duvar rengi/kâğıdı ve zemin seçenekleri
- Oda eşyası mağazası, yıldız/kristal ile satın alma, görevle açılan özel parçalar, oda düzeni kaydetme ve geri yükleme
- Altı özgün fantastik dünya: iki başlangıç dünyası, XP/yıldız/başarımlarla açılan dört yeni kapı
- Her dünyada çizimli kapak, atmosfer, dünya seviyesi, keşif ilerlemesi, üç özel buluntu, gizli noktalar ve iki günlük görev
- 18 dünya hatırası ortak koleksiyona, keşif deneyimi mevcut seviye/XP sistemine eklenir
- Ayrıntılı karakter oluşturucu: yüz, ten, ifade, saç, göz, kıyafet ve beş aksesuar alanı; canlı çizimli ön izleme
- 66 görünüş parçası, dört nadirlik seviyesi, sahip olunan/kilitli gardırop, yıldız/kristal ile açma, rastgele görünüş ve kalıcı görünüş kaydı
- Koleksiyon, mağaza, satın alma ve oyun içi bakiye
- Ruh hâli ve günlük notları
- Yıldız Avcısı ve Ruhunun Rengi mini oyunları
- Başarım ilerlemesi, tema, oyuncu adı ve sıfırlama onayı
- Tarayıcıda otomatik kayıt; Supabase açıksa hesap ekranı olmadan özel bulut kaydı

Ay Işığı Bulmacası henüz oynanabilir değil; arayüzde yakında olarak gösterilir. Hesap kurtarma olmadığı için anonim oturum verileri tarayıcı verileri temizlenirse veya başka cihaza geçilirse taşınamaz.

## Supabase

`supabase-config.js`, tarayıcıda kullanılabilen proje URL'sini ve **publishable** anahtarını içerir. Gizli/service-role anahtarı içermez. Tablo ve RLS tanımları `supabase/migrations/202611160001_littleverse_player_saves.sql` dosyasındadır. Anonim oturum (e-posta/parola istemeyen) özelliği Supabase projesinde açıksa kayıtlar kullanıcıya özel `player_saves` tablosuna eşitlenir. Değilse uygulama otomatik olarak bu cihazdaki yerel kaydı kullanır.

## Çalıştırma

Uygulama bir derleme adımı gerektirmez. `index.html` statik bir web sunucusundan sunulduğunda bütün arayüz özellikleri çalışır. Yazı tipleri çevrim içi Google Fonts üzerinden yüklenir; bağlantı yoksa sistem yazı tipleri kullanılır.

## Smoke kontrolleri

Node.js bulunan bir geliştirme ortamında `node tests/smoke.mjs` komutu; gezinme, yıldızla dünya açma, keşif noktaları ve dünya günlük görev ödülleri, özel dünya hatıralarının envantere eklenmesi, oda/gardırop satın alımları, oda düzenleme ve geri yükleme, karakter görünüşü, günlük kaydı, sürpriz ödülü ve sıfırlama onayını kontrol eder.



