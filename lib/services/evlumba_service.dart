class EvlumbaService {
  static const String baseUrl = 'https://www.evlumba.com';

  static String getExploreUrl(String searchQuery) {
    return '$baseUrl/kesfet?q=${Uri.encodeComponent(searchQuery)}';
  }

  static String getCategoryUrl(String roomType) {
    final map = {
      'salon': 'Salon',
      'yatak_odasi': 'Yatak Odasi',
      'mutfak': 'Mutfak',
      'banyo': 'Banyo',
      'cocuk_odasi': 'Cocuk Odasi',
      'ofis': 'Ev Ofisi',
      'antre': 'Antre',
      'balkon': 'Balkon',
    };
    return '$baseUrl/kesfet?q=${Uri.encodeComponent(map[roomType] ?? roomType)}';
  }

  static String getDesignersUrl() => '$baseUrl/tasarimcilar';
  static String getGameUrl() => '$baseUrl/oyun';
}
