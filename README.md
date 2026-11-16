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
- Sunucu tarafında doğrulanan yıldız, kristal, XP ve mevsim pulu ekonomisi; 1–100 seviye eğrisi ve seviye dönüm noktaları
- Görev/başarım ödüllerinde yinelenen hak talebini önleyen kayıtlar, atomik mağaza alışverişleri ve salt eklemeli işlem defteri
- Filtrelenebilir işlem geçmişi; yalnızca yerel geliştirme adresinde açılan, gerçek oyun kaydına dokunmayan ekonomi simülatörü
- Tarayıcıda otomatik kayıt; Supabase açıksa hesap ekranı olmadan özel bulut kaydı

Ay Işığı Bulmacası henüz oynanabilir değil; arayüzde yakında olarak gösterilir. Hesap kurtarma olmadığı için anonim oturum verileri tarayıcı verileri temizlenirse veya başka cihaza geçilirse taşınamaz.

## Supabase

`supabase-config.js`, tarayıcıda kullanılabilen proje URL'sini ve **publishable** anahtarını içerir. Gizli/service-role anahtarı içermez. Şema/RLS tanımları sırasıyla `supabase/migrations/202611160001_littleverse_player_saves.sql`, `202611160002_littleverse_economy.sql`, `202611160003_littleverse_economy_hardening.sql`, `202611160004_littleverse_xp_function_search_path.sql`, `202611160005_littleverse_idempotent_economy_events.sql` ve `202611160006_littleverse_reward_validation_hardening.sql` dosyalarındadır. `supabase/functions/economy/index.ts` kimliği doğrulanmış Edge Function'dır. Anonim oturum (e-posta/parola istemeyen) özelliği Supabase projesinde açıksa oyun kaydı kullanıcıya özel `player_saves` tablosuna eşitlenir; cüzdan, sahiplik, ödül ve işlem defteri ise yalnızca ekonomi RPC'sinden değiştirilir. Bağlantı yoksa oyun ekranları ve yerel notlar açılır; ekonomi eylemleri sunucuya ulaşana dek bekletilir. Eski tarayıcı kayıtları ilk güvenli oturumda bir defa içe alınır, ekonomi alanları daha sonra istemciden bulut kayıtlarına yazılmaz. Günlük içerikleri buluta aktarılmaz.

## Çalıştırma

Uygulama bir derleme adımı gerektirmez. `index.html` statik bir web sunucusundan sunulduğunda bütün arayüz özellikleri çalışır. Yazı tipleri çevrim içi Google Fonts üzerinden yüklenir; bağlantı yoksa sistem yazı tipleri kullanılır.

## Smoke kontrolleri

Node.js bulunan bir geliştirme ortamında `node --check app.js` ve `node tests/smoke.mjs` komutları söz dizimini, bütün ana ekranların açılmasını, işlem geçmişi filtrelerini ve ekonomi istemci sözleşmesinin güvenlik özelliklerini kontrol eder. Veritabanında ayrıca yinelenen olay/ödül/alışveriş, günlük olay sınırı, kilitli dünya buluntusu, yetersiz bakiye, sahip olunmayan eşyayı kuşanma, sıfırın altına düşen bakiye ve değiştirilemez defter senaryoları işlemi geri alan bir SQL denemesiyle doğrulanmıştır.


