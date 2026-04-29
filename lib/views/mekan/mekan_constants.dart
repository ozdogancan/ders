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

/// Standart oda anahtarları — analyze servisi bu değerleri üretir,
/// mekan_constants bu değerlere göre görsel döner.
const kRoomKeyLiving = 'living_room';
const kRoomKeyBedroom = 'bedroom';
const kRoomKeyKitchen = 'kitchen';
const kRoomKeyBathroom = 'bathroom';
const kRoomKeyDining = 'dining_room';
const kRoomKeyOffice = 'office';

class ThemeOption {
  final String value;
  final String tr;
  final String tag;

  /// Gradient swatch — network görseli yüklenemezse fallback.
  final List<int> swatch;

  /// Oda-özel görseller. Anahtar yoksa living_room'a, o da yoksa boşa düşer
  /// (kart gradient fallback'e kalır — _StyleImage buna hazır).
  final Map<String, String> images;

  const ThemeOption(
    this.value,
    this.tr,
    this.tag,
    this.swatch,
    this.images,
  );

  /// Kart için görsel seç. Oda bazlı eşleşme yoksa salonu, o da yoksa
  /// boş string döner → _StyleImage gradient'a düşer.
  String imageFor(String roomKey) {
    return images[roomKey] ??
        images[kRoomKeyLiving] ??
        images.values.firstOrNull ??
        '';
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

// ─────────────────────────────────────────────────────────────────
// Stil × Oda görsel matrisi — Gemini ile tek seferlik üretildi (2026-04-27),
// Supabase Storage `style-previews` bucket'ında public olarak host ediliyor.
// Üretim scripti: koala-api/scripts/generate-style-previews.mjs
// ─────────────────────────────────────────────────────────────────
const _sb = 'https://xgefjepaqnghaotqybpi.supabase.co/storage/v1/object/public/style-previews';

const kThemes = <ThemeOption>[
  ThemeOption(
    'Minimalist',
    'Minimalist',
    'Temiz çizgi, az eşya',
    [0xFFF5F1EA, 0xFFE8DFCF, 0xFFCFC3AC],
    {
      kRoomKeyLiving: '$_sb/minimalist-living_room.png',
      kRoomKeyBedroom: '$_sb/minimalist-bedroom.png',
      kRoomKeyKitchen: '$_sb/minimalist-kitchen.png',
      kRoomKeyBathroom: '$_sb/minimalist-bathroom.png',
      kRoomKeyDining: '$_sb/minimalist-dining_room.png',
      kRoomKeyOffice: '$_sb/minimalist-office.png',
    },
  ),
  ThemeOption(
    'Scandinavian',
    'Skandinav',
    'Açık ahşap, beyaz, sıcak',
    [0xFFFCF8F2, 0xFFE9D7B8, 0xFFB98B5D],
    {
      kRoomKeyLiving: '$_sb/scandinavian-living_room.png',
      kRoomKeyBedroom: '$_sb/scandinavian-bedroom.png',
      kRoomKeyKitchen: '$_sb/scandinavian-kitchen.png',
      kRoomKeyBathroom: '$_sb/scandinavian-bathroom.png',
      kRoomKeyDining: '$_sb/scandinavian-dining_room.png',
      kRoomKeyOffice: '$_sb/scandinavian-office.png',
    },
  ),
  ThemeOption(
    'Japandi',
    'Japandi',
    'Wabi-sabi, sade huzur',
    [0xFFE7DFD0, 0xFF8C7B68, 0xFF2F2A24],
    {
      kRoomKeyLiving: '$_sb/japandi-living_room.png',
      kRoomKeyBedroom: '$_sb/japandi-bedroom.png',
      kRoomKeyKitchen: '$_sb/japandi-kitchen.png',
      kRoomKeyBathroom: '$_sb/japandi-bathroom.png',
      kRoomKeyDining: '$_sb/japandi-dining_room.png',
      kRoomKeyOffice: '$_sb/japandi-office.png',
    },
  ),
  ThemeOption(
    'Modern',
    'Modern',
    'Düz çizgi, metal, cam',
    [0xFFDADFE4, 0xFF6B7280, 0xFF1F2937],
    {
      kRoomKeyLiving: '$_sb/modern-living_room.png',
      kRoomKeyBedroom: '$_sb/modern-bedroom.png',
      kRoomKeyKitchen: '$_sb/modern-kitchen.png',
      kRoomKeyBathroom: '$_sb/modern-bathroom.png',
      kRoomKeyDining: '$_sb/modern-dining_room.png',
      kRoomKeyOffice: '$_sb/modern-office.png',
    },
  ),
  ThemeOption(
    'Bohemian',
    'Bohem',
    'Desenli, bitki, renkli',
    [0xFFE8C9A5, 0xFFC56A47, 0xFF5E2C1F],
    {
      kRoomKeyLiving: '$_sb/bohemian-living_room.png',
      kRoomKeyBedroom: '$_sb/bohemian-bedroom.png',
      kRoomKeyKitchen: '$_sb/bohemian-kitchen.png',
      kRoomKeyBathroom: '$_sb/bohemian-bathroom.png',
      kRoomKeyDining: '$_sb/bohemian-dining_room.png',
      kRoomKeyOffice: '$_sb/bohemian-office.png',
    },
  ),
  ThemeOption(
    'Industrial',
    'Endüstriyel',
    'Tuğla, beton, koyu',
    [0xFFB3A99E, 0xFF5A4F46, 0xFF2A211B],
    {
      kRoomKeyLiving: '$_sb/industrial-living_room.png',
      kRoomKeyBedroom: '$_sb/industrial-bedroom.png',
      kRoomKeyKitchen: '$_sb/industrial-kitchen.png',
      kRoomKeyBathroom: '$_sb/industrial-bathroom.png',
      kRoomKeyDining: '$_sb/industrial-dining_room.png',
      kRoomKeyOffice: '$_sb/industrial-office.png',
    },
  ),
];
