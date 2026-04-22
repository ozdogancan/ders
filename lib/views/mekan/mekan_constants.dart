// Oda tipleri — Türkçe görünen etiket, İngilizce prompt değeri.
// NOT: UI artık oda seçtirmiyor (otomatik tespit). Geriye dönük uyumluluk
// için tip ve liste duruyor.
class RoomOption {
  final String value; // prompt'a giden
  final String tr;    // UI'da görünen
  const RoomOption(this.value, this.tr);
}

const kRooms = <RoomOption>[
  RoomOption('Living Room', 'Salon'),
  RoomOption('Bedroom', 'Yatak'),
  RoomOption('Kitchen', 'Mutfak'),
  RoomOption('Bathroom', 'Banyo'),
  RoomOption('Dining Room', 'Yemek'),
  RoomOption('Office', 'Çalışma'),
];

class ThemeOption {
  final String value;
  final String tr;
  final String tag;
  /// Gradient swatch — network görseli yüklenemezse fallback.
  final List<int> swatch;
  /// Unsplash direct URL — küçük boyutta, hızlı yüklenir.
  final String image;
  const ThemeOption(
    this.value,
    this.tr,
    this.tag,
    this.swatch,
    this.image,
  );
}

const _q = '?auto=format&fit=crop&w=480&q=60';

// Her tarzın "hissi" — gerçek oda fotoğrafı (Unsplash) + gradient fallback.
const kThemes = <ThemeOption>[
  ThemeOption(
    'Minimalist',
    'Minimalist',
    'Temiz çizgi, az eşya',
    [0xFFF5F1EA, 0xFFE8DFCF, 0xFFCFC3AC],
    'https://images.unsplash.com/photo-1586023492125-27b2c045efd7$_q',
  ),
  ThemeOption(
    'Scandinavian',
    'Skandinav',
    'Açık ahşap, beyaz, sıcak',
    [0xFFFCF8F2, 0xFFE9D7B8, 0xFFB98B5D],
    'https://images.unsplash.com/photo-1616486338812-3dadae4b4ace$_q',
  ),
  ThemeOption(
    'Japandi',
    'Japandi',
    'Wabi-sabi, sade huzur',
    [0xFFE7DFD0, 0xFF8C7B68, 0xFF2F2A24],
    'https://images.unsplash.com/photo-1615874959474-d609969a20ed$_q',
  ),
  ThemeOption(
    'Modern',
    'Modern',
    'Düz çizgi, metal, cam',
    [0xFFDADFE4, 0xFF6B7280, 0xFF1F2937],
    'https://images.unsplash.com/photo-1600121848594-d8644e57abab$_q',
  ),
  ThemeOption(
    'Bohemian',
    'Bohem',
    'Desenli, bitki, renkli',
    [0xFFE8C9A5, 0xFFC56A47, 0xFF5E2C1F],
    'https://images.unsplash.com/photo-1600210491892-03d54c0aaf87$_q',
  ),
  ThemeOption(
    'Industrial',
    'Endüstriyel',
    'Tuğla, beton, koyu',
    [0xFFB3A99E, 0xFF5A4F46, 0xFF2A211B],
    'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c$_q',
  ),
];
