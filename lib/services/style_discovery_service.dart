import 'dart:async';

/// Tek bir swipe kartı — discovery deck'inin atomik birimi.
///
/// Pro match'taki ağır designer/proje DTO'larından kasten ayrı tutulmuştur:
/// burada tasarımcı kim, fiyat ne, similarity kaç gibi alanlar yok. Sadece
/// görsel + Türkçe başlık + serbest tag listesi + dominant renkler. UX niyeti:
/// kullanıcı sadece "estetik" karar versin.
class DiscoveryCard {
  final String id;
  final String imageUrl;
  final String title;
  final List<String> tags;
  final List<String> dominantColors; // hex strings, e.g. "#E8DCC8"

  const DiscoveryCard({
    required this.id,
    required this.imageUrl,
    required this.title,
    required this.tags,
    required this.dominantColors,
  });
}

/// Kullanıcının swipe sonrası çıkardığımız "tarz hint'leri".
///
/// Lokal olarak tutuyoruz — `mekan_analyze_service.dart` içinde aynı isimde
/// public bir tip yok, ileride entegrasyon olduğunda re-export edilebilir.
/// Shape: top-3 tag, top-3 renk, mood etiketi, hero görsel (en sevilen kart).
class StyleHints {
  final List<String> topTags;
  final List<String> topColors;
  final String mood;
  final String? heroImageUrl;
  final List<String> lovedCardIds;

  const StyleHints({
    required this.topTags,
    required this.topColors,
    required this.mood,
    required this.heroImageUrl,
    required this.lovedCardIds,
  });
}

/// Discovery deck — şu an lokal mock. Backend `/api/discovery-deck` hayata
/// geçince bu sınıf gerçek HTTP çağrısına döner. UI tarafı bu noktada
/// dokunulmamalıdır — sözleşme `fetchDeck` + `buildHintsFromLikes`.
class StyleDiscoveryService {
  /// 8 kartlık deck. `roomTypeGuess` ileride filtreleme için backend'e
  /// gidecek — şu an mock data tüm odalar için aynı.
  ///
  /// TODO: replace with `/api/discovery-deck` once backend lands.
  /// Backend kontratı: POST { room_type_guess: "bedroom" | ... } →
  /// { cards: [{ id, image_url, title, tags[], dominant_colors[] }] }
  /// Implementasyon evlumba.designer_projects'ten `room_type_guess`
  /// filtreli rastgele 8 satır okuyacak (RLS anon read-only).
  Future<List<DiscoveryCard>> fetchDeck({required String roomTypeGuess}) async {
    // Hafif simulated latency — UI skeleton path'ini doğal bekletmek için
    // ama "instant feel" hedefiyle <300ms.
    await Future<void>.delayed(const Duration(milliseconds: 180));
    return _mockDeck;
  }

  /// Liked kartlardan StyleHints inşa eder. Saf client-side; ağa girmez.
  ///
  /// - top-3 tag: frekansa göre, eşitlikte ilk gelen kazanır.
  /// - top-3 renk: aynı kural.
  /// - mood: tag → mood lookup; ilk eşleşen tag'in mood'u alınır,
  ///   bulunamazsa "doğal" fallback.
  /// - hero: en çok eşleşen tag'lere sahip kartın görseli (yani "tipik"
  ///   sevdiği). Tek bir oy varsa direkt o kart.
  StyleHints buildHintsFromLikes(List<DiscoveryCard> liked) {
    if (liked.isEmpty) {
      return const StyleHints(
        topTags: <String>[],
        topColors: <String>[],
        mood: 'doğal',
        heroImageUrl: null,
        lovedCardIds: <String>[],
      );
    }

    // Tag frekansı (lowercase normalize).
    final tagCounts = <String, int>{};
    final tagOrder = <String>[];
    for (final c in liked) {
      for (final raw in c.tags) {
        final t = raw.trim().toLowerCase();
        if (t.isEmpty) continue;
        if (!tagCounts.containsKey(t)) tagOrder.add(t);
        tagCounts[t] = (tagCounts[t] ?? 0) + 1;
      }
    }

    // Renk frekansı (#XXXXXX uppercase normalize).
    final colorCounts = <String, int>{};
    final colorOrder = <String>[];
    for (final c in liked) {
      for (final raw in c.dominantColors) {
        final hex = _normalizeHex(raw);
        if (hex == null) continue;
        if (!colorCounts.containsKey(hex)) colorOrder.add(hex);
        colorCounts[hex] = (colorCounts[hex] ?? 0) + 1;
      }
    }

    final topTags = _topByFreq(tagCounts, tagOrder, 3);
    final topColors = _topByFreq(colorCounts, colorOrder, 3);
    final mood = _moodFromTags(topTags);
    final hero = _pickHero(liked, tagCounts);

    return StyleHints(
      topTags: topTags,
      topColors: topColors,
      mood: mood,
      heroImageUrl: hero?.imageUrl,
      lovedCardIds: liked.map((c) => c.id).toList(),
    );
  }

  // ─── helpers ───

  static List<String> _topByFreq(
    Map<String, int> counts,
    List<String> insertionOrder,
    int n,
  ) {
    final keys = insertionOrder.toList()
      ..sort((a, b) {
        final cmp = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
        if (cmp != 0) return cmp;
        // Eşitlikte: insertion order'ı koru (stable).
        return insertionOrder.indexOf(a).compareTo(insertionOrder.indexOf(b));
      });
    return keys.take(n).toList();
  }

  static String _moodFromTags(List<String> tags) {
    // Tag → mood lookup. İlk eşleşen kazanır; yoksa "doğal" (en güvenli
    // Türkçe nötr mood).
    const lookup = <String, String>{
      'sıcak': 'samimi',
      'samimi': 'samimi',
      'minimalist': 'dingin',
      'sade': 'dingin',
      'modern': 'dingin',
      'doğal': 'doğal',
      'pastel': 'yumuşak',
      'yumuşak': 'yumuşak',
      'bohem': 'özgür',
      'rustik': 'sıcak',
      'endüstriyel': 'güçlü',
      'lüks': 'zarif',
      'klasik': 'zarif',
      'iskandinav': 'dingin',
      'japon': 'dingin',
    };
    for (final t in tags) {
      final hit = lookup[t.toLowerCase()];
      if (hit != null) return hit;
    }
    return 'doğal';
  }

  static DiscoveryCard? _pickHero(
    List<DiscoveryCard> liked,
    Map<String, int> tagCounts,
  ) {
    if (liked.isEmpty) return null;
    if (liked.length == 1) return liked.first;
    DiscoveryCard? best;
    int bestScore = -1;
    for (final c in liked) {
      var score = 0;
      for (final t in c.tags) {
        score += tagCounts[t.trim().toLowerCase()] ?? 0;
      }
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return best ?? liked.first;
  }

  static String? _normalizeHex(String raw) {
    var s = raw.trim().replaceFirst('#', '');
    if (s.length == 3) {
      s = s.split('').map((c) => '$c$c').join();
    }
    if (s.length != 6) return null;
    final v = int.tryParse(s, radix: 16);
    if (v == null) return null;
    return '#${s.toUpperCase()}';
  }

  // ─── mock data ───
  // 8 kart — Türkçe başlıklar, gerçekçi tag setleri ve hex paletleri.
  // picsum.photos seed'li URL'ler stabil — deterministic preview için.
  static final List<DiscoveryCard> _mockDeck = const [
    DiscoveryCard(
      id: 'mock_1',
      imageUrl: 'https://picsum.photos/seed/koala_disc_1/1200/675',
      title: 'Pastel Yatak Odası',
      tags: ['pastel', 'sıcak', 'minimalist'],
      dominantColors: ['#F5E6D3', '#E8C4A0', '#D9A88A'],
    ),
    DiscoveryCard(
      id: 'mock_2',
      imageUrl: 'https://picsum.photos/seed/koala_disc_2/1200/675',
      title: 'Doğal Tonlar',
      tags: ['doğal', 'rustik', 'sıcak'],
      dominantColors: ['#C4A27B', '#8B6F47', '#5C4A2E'],
    ),
    DiscoveryCard(
      id: 'mock_3',
      imageUrl: 'https://picsum.photos/seed/koala_disc_3/1200/675',
      title: 'İskandinav Sadelik',
      tags: ['iskandinav', 'minimalist', 'sade'],
      dominantColors: ['#FAFAFA', '#E5E5E5', '#A8A8A8'],
    ),
    DiscoveryCard(
      id: 'mock_4',
      imageUrl: 'https://picsum.photos/seed/koala_disc_4/1200/675',
      title: 'Bohem Salon',
      tags: ['bohem', 'sıcak', 'doğal'],
      dominantColors: ['#B8625A', '#D9A66E', '#6B4226'],
    ),
    DiscoveryCard(
      id: 'mock_5',
      imageUrl: 'https://picsum.photos/seed/koala_disc_5/1200/675',
      title: 'Modern Mutfak',
      tags: ['modern', 'minimalist', 'sade'],
      dominantColors: ['#1A1A1A', '#7A7A7A', '#F0F0F0'],
    ),
    DiscoveryCard(
      id: 'mock_6',
      imageUrl: 'https://picsum.photos/seed/koala_disc_6/1200/675',
      title: 'Endüstriyel Loft',
      tags: ['endüstriyel', 'modern'],
      dominantColors: ['#3A3A3A', '#8B7355', '#C4B5A0'],
    ),
    DiscoveryCard(
      id: 'mock_7',
      imageUrl: 'https://picsum.photos/seed/koala_disc_7/1200/675',
      title: 'Klasik Zarafet',
      tags: ['klasik', 'lüks'],
      dominantColors: ['#7A5C3F', '#D4B896', '#F0E4D0'],
    ),
    DiscoveryCard(
      id: 'mock_8',
      imageUrl: 'https://picsum.photos/seed/koala_disc_8/1200/675',
      title: 'Japon Esintisi',
      tags: ['japon', 'minimalist', 'doğal'],
      dominantColors: ['#F5F1EA', '#A89878', '#3D3525'],
    ),
  ];
}
