// Oda tipleri — Türkçe görünen etiket, İngilizce prompt değeri.
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
  final List<int> swatch; // RGB 3-5 noktası — gradient için
  const ThemeOption(this.value, this.tr, this.tag, this.swatch);
}

// Her tarzın "hissi" gradient olarak — asset'e bağımlı değiliz.
const kThemes = <ThemeOption>[
  ThemeOption('Minimalist', 'Minimalist', 'Temiz çizgi, az eşya',
      [0xFFF5F1EA, 0xFFE8DFCF, 0xFFCFC3AC]),
  ThemeOption('Scandinavian', 'Skandinav', 'Açık ahşap, beyaz, sıcak',
      [0xFFFCF8F2, 0xFFE9D7B8, 0xFFB98B5D]),
  ThemeOption('Japandi', 'Japandi', 'Wabi-sabi, sade huzur',
      [0xFFE7DFD0, 0xFF8C7B68, 0xFF2F2A24]),
  ThemeOption('Modern', 'Modern', 'Düz çizgi, metal, cam',
      [0xFFDADFE4, 0xFF6B7280, 0xFF1F2937]),
  ThemeOption('Bohemian', 'Bohem', 'Desenli, bitki, renkli',
      [0xFFE8C9A5, 0xFFC56A47, 0xFF5E2C1F]),
  ThemeOption('Industrial', 'Endüstriyel', 'Tuğla, beton, koyu',
      [0xFFB3A99E, 0xFF5A4F46, 0xFF2A211B]),
  ThemeOption('Vintage', 'Vintage', 'Patina, zengin doku',
      [0xFFE8D5A8, 0xFFA67148, 0xFF4A2F1A]),
  ThemeOption('Rustic', 'Rustik', 'Doğal taş, kütük, toprak',
      [0xFFD6C2A2, 0xFF8B6A3E, 0xFF3C2A18]),
];
