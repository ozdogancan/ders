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

const _q = '?auto=format&fit=crop&w=480&q=60';

// ─────────────────────────────────────────────────────────────────
// Unsplash foto ID'leri — tarz × oda matrisi.
// Yanlış ID → gradient fallback (_StyleImage errorBuilder yakalar).
// Bulamadığımız kombinasyonlar salon görselini kullanır.
// ─────────────────────────────────────────────────────────────────
const kThemes = <ThemeOption>[
  ThemeOption(
    'Minimalist',
    'Minimalist',
    'Temiz çizgi, az eşya',
    [0xFFF5F1EA, 0xFFE8DFCF, 0xFFCFC3AC],
    {
      kRoomKeyLiving: 'https://images.unsplash.com/photo-1586023492125-27b2c045efd7$_q',
      kRoomKeyKitchen: 'https://images.unsplash.com/photo-1556909114-f6e7ad7d3136$_q',
      kRoomKeyBedroom: 'https://images.unsplash.com/photo-1522771739844-6a9f6d5f14af$_q',
      kRoomKeyBathroom: 'https://images.unsplash.com/photo-1552321554-5fefe8c9ef14$_q',
      kRoomKeyDining: 'https://images.unsplash.com/photo-1583847268964-b28dc8f51f92$_q',
      kRoomKeyOffice: 'https://images.unsplash.com/photo-1593476550610-87baa860004a$_q',
    },
  ),
  ThemeOption(
    'Scandinavian',
    'Skandinav',
    'Açık ahşap, beyaz, sıcak',
    [0xFFFCF8F2, 0xFFE9D7B8, 0xFFB98B5D],
    {
      kRoomKeyLiving: 'https://images.unsplash.com/photo-1616486338812-3dadae4b4ace$_q',
      kRoomKeyKitchen: 'https://images.unsplash.com/photo-1565538810643-b5bdb714032a$_q',
      kRoomKeyBedroom: 'https://images.unsplash.com/photo-1560448204-e02f11c3d0e2$_q',
      kRoomKeyBathroom: 'https://images.unsplash.com/photo-1620626011761-996317b8d101$_q',
      kRoomKeyDining: 'https://images.unsplash.com/photo-1617806118233-18e1de247200$_q',
      kRoomKeyOffice: 'https://images.unsplash.com/photo-1497366216548-37526070297c$_q',
    },
  ),
  ThemeOption(
    'Japandi',
    'Japandi',
    'Wabi-sabi, sade huzur',
    [0xFFE7DFD0, 0xFF8C7B68, 0xFF2F2A24],
    {
      kRoomKeyLiving: 'https://images.unsplash.com/photo-1615874959474-d609969a20ed$_q',
      kRoomKeyKitchen: 'https://images.unsplash.com/photo-1556909172-54557c7e4fb7$_q',
      kRoomKeyBedroom: 'https://images.unsplash.com/photo-1540518614846-7eded433c457$_q',
      kRoomKeyBathroom: 'https://images.unsplash.com/photo-1584622650111-93e69d876a0c$_q',
      kRoomKeyDining: 'https://images.unsplash.com/photo-1595514535215-b58bd7ba70ab$_q',
      kRoomKeyOffice: 'https://images.unsplash.com/photo-1519710164239-da123dc03ef4$_q',
    },
  ),
  ThemeOption(
    'Modern',
    'Modern',
    'Düz çizgi, metal, cam',
    [0xFFDADFE4, 0xFF6B7280, 0xFF1F2937],
    {
      kRoomKeyLiving: 'https://images.unsplash.com/photo-1600121848594-d8644e57abab$_q',
      kRoomKeyKitchen: 'https://images.unsplash.com/photo-1556911220-e15b29be8c8f$_q',
      kRoomKeyBedroom: 'https://images.unsplash.com/photo-1505693416388-ac5ce068fe85$_q',
      kRoomKeyBathroom: 'https://images.unsplash.com/photo-1600566753190-17f0baa2a6c3$_q',
      kRoomKeyDining: 'https://images.unsplash.com/photo-1615529182904-14819c35db37$_q',
      kRoomKeyOffice: 'https://images.unsplash.com/photo-1486946255434-2466348c2166$_q',
    },
  ),
  ThemeOption(
    'Bohemian',
    'Bohem',
    'Desenli, bitki, renkli',
    [0xFFE8C9A5, 0xFFC56A47, 0xFF5E2C1F],
    {
      kRoomKeyLiving: 'https://images.unsplash.com/photo-1600210491892-03d54c0aaf87$_q',
      kRoomKeyKitchen: 'https://images.unsplash.com/photo-1584622781564-1d987f7333c1$_q',
      kRoomKeyBedroom: 'https://images.unsplash.com/photo-1616627561950-9f746e330187$_q',
      kRoomKeyBathroom: 'https://images.unsplash.com/photo-1570129477492-45c003edd2be$_q',
      kRoomKeyDining: 'https://images.unsplash.com/photo-1600585154526-990dced4db0d$_q',
      kRoomKeyOffice: 'https://images.unsplash.com/photo-1616137466211-f939a420be84$_q',
    },
  ),
  ThemeOption(
    'Industrial',
    'Endüstriyel',
    'Tuğla, beton, koyu',
    [0xFFB3A99E, 0xFF5A4F46, 0xFF2A211B],
    {
      kRoomKeyLiving: 'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c$_q',
      kRoomKeyKitchen: 'https://images.unsplash.com/photo-1556909195-8a9def3dd6aa$_q',
      kRoomKeyBedroom: 'https://images.unsplash.com/photo-1595526114035-0d45ed16cfbf$_q',
      kRoomKeyBathroom: 'https://images.unsplash.com/photo-1603825471027-a7fc7b3e2057$_q',
      kRoomKeyDining: 'https://images.unsplash.com/photo-1551298370-9d3d53740c72$_q',
      kRoomKeyOffice: 'https://images.unsplash.com/photo-1497366811353-6870744d04b2$_q',
    },
  ),
];
