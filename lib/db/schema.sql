-- ═══════════════════════════════════════════════════════════
-- KOALA DB SCHEMA — Supabase SQL
-- Run this in SQL Editor to create tables + seed dummy data
-- ═══════════════════════════════════════════════════════════

-- 1. Styles (iç mekan stilleri)
CREATE TABLE IF NOT EXISTS koala_styles (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  name_tr TEXT NOT NULL,
  description TEXT,
  description_tr TEXT,
  image_url TEXT,
  color_primary TEXT, -- hex
  color_secondary TEXT,
  tags TEXT[] DEFAULT '{}',
  popularity INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Products (ürünler — mobilya, dekorasyon)
CREATE TABLE IF NOT EXISTS koala_products (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  category TEXT NOT NULL, -- mobilya, aydinlatma, tekstil, dekorasyon, organizasyon
  style_id UUID REFERENCES koala_styles(id),
  price_min INT, -- TL
  price_max INT,
  image_url TEXT,
  brand TEXT,
  description TEXT,
  room_types TEXT[] DEFAULT '{}', -- salon, yatak_odasi, mutfak, banyo, etc.
  tags TEXT[] DEFAULT '{}',
  evlumba_url TEXT,
  rating FLOAT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Designers (tasarımcılar)
CREATE TABLE IF NOT EXISTS koala_designers (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  title TEXT, -- "İç Mimar", "Dekorasyon Uzmanı"
  avatar_url TEXT,
  portfolio_url TEXT,
  specialties TEXT[] DEFAULT '{}', -- minimalist, bohem, etc.
  city TEXT DEFAULT 'İstanbul',
  min_budget INT, -- minimum proje bütçesi TL
  rating FLOAT DEFAULT 4.5,
  project_count INT DEFAULT 0,
  bio TEXT,
  evlumba_url TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 4. Inspirations (ilham görselleri)
CREATE TABLE IF NOT EXISTS koala_inspirations (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  title TEXT NOT NULL,
  image_url TEXT NOT NULL,
  style_id UUID REFERENCES koala_styles(id),
  room_type TEXT, -- salon, yatak_odasi, mutfak, etc.
  tags TEXT[] DEFAULT '{}',
  like_count INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 5. Tips (biliyor muydun, dekorasyon ipuçları)
CREATE TABLE IF NOT EXISTS koala_tips (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  content TEXT NOT NULL,
  emoji TEXT DEFAULT '✨',
  category TEXT, -- renk, aydinlatma, mekan, bitki, organizasyon
  source TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 6. User preferences (kullanıcı tercihleri — kişiselleştirme)
CREATE TABLE IF NOT EXISTS koala_user_prefs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id TEXT NOT NULL,
  favorite_styles TEXT[] DEFAULT '{}',
  budget_range TEXT, -- 'low', 'mid', 'high'
  room_types TEXT[] DEFAULT '{}', -- hangi odalarla ilgileniyor
  onboarding_done BOOLEAN DEFAULT false,
  last_active TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id)
);

-- 7. Chat sessions
CREATE TABLE IF NOT EXISTS koala_chats (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id TEXT NOT NULL,
  title TEXT,
  last_message TEXT,
  message_count INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 8. Chat messages
CREATE TABLE IF NOT EXISTS koala_messages (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  chat_id UUID REFERENCES koala_chats(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  role TEXT NOT NULL, -- 'user' or 'koala'
  content TEXT,
  image_url TEXT,
  response_type TEXT DEFAULT 'text', -- 'text', 'style_card', 'product_grid', 'color_palette', 'designer_card', 'mood_board', 'budget_plan'
  response_data JSONB, -- structured card data
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ═══════════════════════════════════════════════════════════
-- SEED DATA
-- ═══════════════════════════════════════════════════════════

-- Styles
INSERT INTO koala_styles (name, name_tr, description_tr, image_url, color_primary, color_secondary, tags, popularity) VALUES
('japandi', 'Japandi', 'Japon sadeliği ve İskandinav sıcaklığının buluşması. Doğal malzemeler, nötr tonlar, minimal detaylar.', 'https://images.unsplash.com/photo-1586023492125-27b2c045efd7?auto=format&fit=crop&w=800&q=80', '#C4A882', '#F5F0EB', '{minimal,dogal,sicak,huzurlu}', 95),
('scandinavian', 'Skandinav', 'Ferah, aydınlık ve fonksiyonel. Beyaz tonlar, ahşap detaylar, sade çizgiler.', 'https://images.unsplash.com/photo-1505691938895-1758d7feb511?auto=format&fit=crop&w=800&q=80', '#FFFFFF', '#E8DFD3', '{ferah,aydinlik,minimal,fonksiyonel}', 90),
('modern', 'Modern Minimalist', 'Temiz çizgiler, açık alanlar, az ama öz. Fonksiyon güzelliğin önünde.', 'https://images.unsplash.com/photo-1556909114-f6e7ad7d3136?auto=format&fit=crop&w=800&q=80', '#2C2C2C', '#FFFFFF', '{temiz,sade,cizgisel,profesyonel}', 88),
('bohemian', 'Bohem', 'Renkli, katmanlı, özgür ruhlu. Desenler, dokular, seyahat esintileri.', 'https://images.unsplash.com/photo-1540518614846-7eded433c457?auto=format&fit=crop&w=800&q=80', '#C17F5E', '#8B5E3C', '{renkli,katmanli,ozgur,sicak}', 82),
('industrial', 'Endüstriyel', 'Ham tuğla, metal, beton. Fabrika estetiği ev konforunda.', 'https://images.unsplash.com/photo-1618221195710-dd6b41faaea6?auto=format&fit=crop&w=800&q=80', '#4A4A4A', '#8B7355', '{ham,guclu,karakter,urban}', 75),
('rustic', 'Rustik', 'Doğallık ve sıcaklık. Ahşap, taş, toprak tonları, kırsal esinti.', 'https://images.unsplash.com/photo-1556909172-54557c7e4fb7?auto=format&fit=crop&w=800&q=80', '#8B7355', '#D4A574', '{dogal,sicak,ahsap,kirsal}', 70),
('art_deco', 'Art Deco', 'Gösterişli geometrik desenler, altın detaylar, lüks dokular.', 'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=800&q=80', '#C4A265', '#1A1A2E', '{luks,geometrik,gosterisli,sofistike}', 65),
('coastal', 'Coastal', 'Deniz esintisi, beyaz-mavi tonlar, doğal dokular, yaz hissi.', 'https://images.unsplash.com/photo-1552321554-5fefe8c9ef14?auto=format&fit=crop&w=800&q=80', '#5B9BD5', '#F5F5DC', '{deniz,ferah,yaz,rahat}', 60);

-- Products
INSERT INTO koala_products (name, category, price_min, price_max, image_url, brand, description, room_types, tags) VALUES
('Doğal Ahşap Sehpa', 'mobilya', 2500, 4500, 'https://images.unsplash.com/photo-1555041469-a586c61ea9bc?auto=format&fit=crop&w=400&q=80', 'Kelebek', 'Masif meşe ahşap orta sehpa, doğal yağ kaplama', '{salon}', '{ahsap,dogal,sehpa}'),
('Keten Koltuk Örtüsü', 'tekstil', 800, 1500, 'https://images.unsplash.com/photo-1567016432779-094069958ea5?auto=format&fit=crop&w=400&q=80', 'English Home', '%100 doğal keten, nefes alan doku', '{salon,yatak_odasi}', '{keten,dogal,tekstil}'),
('Bambu Dolap Organizer', 'organizasyon', 350, 750, 'https://images.unsplash.com/photo-1558618666-fcd25c85f82e?auto=format&fit=crop&w=400&q=80', 'IKEA', 'Çekmece içi bambu düzenleyici set', '{yatak_odasi,banyo,mutfak}', '{bambu,organizer,duzenleme}'),
('Minimalist Masa Lambası', 'aydinlatma', 1200, 2800, 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=400&q=80', 'Lumica', 'Siyah metal gövde, sıcak beyaz LED', '{salon,yatak_odasi,ofis}', '{lamba,minimalist,aydinlatma}'),
('Makrome Duvar Süsü', 'dekorasyon', 400, 900, 'https://images.unsplash.com/photo-1524758631624-e2822e304c36?auto=format&fit=crop&w=400&q=80', 'El Yapımı', 'Pamuk iplik, el örgüsü makrome pano', '{salon,yatak_odasi}', '{makrome,duvar,bohem}'),
('Seramik Saksı Seti', 'dekorasyon', 250, 600, 'https://images.unsplash.com/photo-1485955900006-10f4d324d411?auto=format&fit=crop&w=400&q=80', 'Terracotta', '3lü mat seramik saksı, farklı boyutlar', '{salon,balkon,mutfak}', '{saksi,bitki,seramik}'),
('Kadife Yastık Kılıfı', 'tekstil', 150, 350, 'https://images.unsplash.com/photo-1586105251261-72a756497a11?auto=format&fit=crop&w=400&q=80', 'Zara Home', 'Premium kadife, fermuarlı, 45x45cm', '{salon,yatak_odasi}', '{yastik,kadife,tekstil}'),
('Rattan Ayna', 'dekorasyon', 1800, 3500, 'https://images.unsplash.com/photo-1618220179428-22790b461013?auto=format&fit=crop&w=400&q=80', 'Koçtaş', 'El örgüsü rattan çerçeveli yuvarlak ayna', '{antre,yatak_odasi,banyo}', '{ayna,rattan,bohem}');

-- Designers
INSERT INTO koala_designers (name, title, avatar_url, specialties, city, min_budget, rating, project_count, bio) VALUES
('Aylin Tanrıverdi', 'İç Mimar', 'https://images.unsplash.com/photo-1494790108755-2616b612b786?auto=format&fit=crop&w=200&q=80', '{minimalist,japandi,skandinav}', 'İstanbul', 25000, 4.9, 47, 'Minimal ve fonksiyonel tasarımların uzmanı. 10 yıllık deneyim.'),
('Mehmet Kaya', 'Dekorasyon Uzmanı', 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=200&q=80', '{modern,endustriyel,loft}', 'İstanbul', 15000, 4.7, 63, 'Endüstriyel ve modern tasarımları seven, cesur çözümler üreten tasarımcı.'),
('Zeynep Arslan', 'İç Mimar & Stilist', 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?auto=format&fit=crop&w=200&q=80', '{bohem,rustik,eklektik}', 'Ankara', 20000, 4.8, 35, 'Renk ve doku uzmanı. Her mekana karakter katan tasarımlar.'),
('Can Demir', 'Mimar', 'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?auto=format&fit=crop&w=200&q=80', '{modern,minimalist,art_deco}', 'İzmir', 35000, 4.9, 28, 'Mimari bakış açısıyla iç mekan. Lüks ve fonksiyonellik bir arada.'),
('Elif Yılmaz', 'Ev Stilisti', 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=200&q=80', '{skandinav,coastal,minimal}', 'İstanbul', 10000, 4.6, 82, 'Küçük bütçe, büyük dönüşüm. Herkesin ulaşabileceği tasarım.');

-- Tips
INSERT INTO koala_tips (content, emoji, category) VALUES
('Açık renkli perdeler odayı %30 daha geniş gösterir', '✨', 'renk'),
('Bitkiler bulunduğu odadaki stresi %37 azaltıyor', '🌿', 'bitki'),
('Doğru aydınlatma odanın havasını tamamen değiştirir', '💡', 'aydinlatma'),
('Ayna kullanımı küçük mekanlarda derinlik hissi yaratır', '🪞', 'mekan'),
('3lü kural: Dekorasyon objelerini tek sayılarla grupla', '🎯', 'dekorasyon'),
('Yastık değiştirmek odayı yenilemenin en ucuz yolu', '🛋️', 'tekstil'),
('Duvar rengini değiştirmek mekanı baştan yaratır', '🎨', 'renk'),
('Açık raflar mutfağı daha ferah ve erişilebilir yapar', '📚', 'organizasyon'),
('Sıcak ve soğuk aydınlatmayı aynı odada karıştırma', '⚡', 'aydinlatma'),
('Halı boyutu mobilyadan büyük olmalı, küçük halı odayı daraltır', '📐', 'mekan'),
('Yeşilin 50 tonu: Her odaya uygun bir yeşil tonu vardır', '🌱', 'renk'),
('Banyo aynasının iki yanına simetrik aydınlatma koy', '💎', 'banyo');

-- Enable RLS
ALTER TABLE koala_styles ENABLE ROW LEVEL SECURITY;
ALTER TABLE koala_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE koala_designers ENABLE ROW LEVEL SECURITY;
ALTER TABLE koala_inspirations ENABLE ROW LEVEL SECURITY;
ALTER TABLE koala_tips ENABLE ROW LEVEL SECURITY;
ALTER TABLE koala_user_prefs ENABLE ROW LEVEL SECURITY;
ALTER TABLE koala_chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE koala_messages ENABLE ROW LEVEL SECURITY;

-- Public read for content tables
CREATE POLICY "Public read styles" ON koala_styles FOR SELECT USING (true);
CREATE POLICY "Public read products" ON koala_products FOR SELECT USING (true);
CREATE POLICY "Public read designers" ON koala_designers FOR SELECT USING (true);
CREATE POLICY "Public read inspirations" ON koala_inspirations FOR SELECT USING (true);
CREATE POLICY "Public read tips" ON koala_tips FOR SELECT USING (true);

-- User-specific policies
CREATE POLICY "Users manage own prefs" ON koala_user_prefs FOR ALL USING (true);
CREATE POLICY "Users manage own chats" ON koala_chats FOR ALL USING (true);
CREATE POLICY "Users manage own messages" ON koala_messages FOR ALL USING (true);
