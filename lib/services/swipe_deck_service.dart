import 'dart:convert';
import 'dart:ui' show Color;

import 'package:http/http.dart' as http;

/// Tek bir swipe kartı — `/api/swipe-deck`'in atomik birimi.
///
/// pro-match'in tasarımcı/proje DTO'larından bilinçli olarak yalın: bu
/// ekranda kullanıcı sadece estetik karar verir, fiyat/şehir/similarity
/// gürültüsü yok.
class SwipeCard {
  final String id;
  final String coverUrl;
  final List<String> tags;
  final List<Color> colors;

  const SwipeCard({
    required this.id,
    required this.coverUrl,
    required this.tags,
    required this.colors,
  });

  factory SwipeCard.fromJson(Map<String, dynamic> j) {
    final tagsRaw = j['tags'];
    final colorsRaw = j['color_palette'];
    final tags = <String>[];
    if (tagsRaw is List) {
      for (final t in tagsRaw) {
        final s = t.toString().trim();
        if (s.isNotEmpty) tags.add(s);
      }
    }
    final colors = <Color>[];
    if (colorsRaw is List) {
      for (final c in colorsRaw) {
        final col = _hexToColor(c.toString());
        if (col != null) colors.add(col);
      }
    }
    return SwipeCard(
      id: (j['id'] ?? '').toString(),
      coverUrl: (j['cover_url'] ?? '').toString(),
      tags: tags,
      colors: colors,
    );
  }
}

/// Swipe akışından çıkan zevk özeti — caller (mekan_flow) restyle prompt'unu
/// zenginleştirmek için kullanır. Hiçbir alan kullanıcıya gösterilmez:
/// reveal kendi mood-board görsellerini ve tek satır özetini ayrıca üretir.
class SwipeResult {
  final List<String> lovedTags;
  final List<Color> lovedColors;
  final List<String> lovedProjectIds;

  const SwipeResult({
    required this.lovedTags,
    required this.lovedColors,
    required this.lovedProjectIds,
  });
}

/// Swipe deck için backend istemcisi.
///
/// Sözleşme: `GET /api/swipe-deck?room_type=...&limit=N` →
///   `{ cards: [{ id, cover_url, tags, color_palette }] }`
///
/// 4 saniyede dönmezse boş liste — caller skeleton/empty path'ine düşer.
class SwipeDeckService {
  static const String _baseUrl = String.fromEnvironment(
    'KOALA_API_URL',
    defaultValue: 'https://koala-api-olive.vercel.app',
  );

  /// Deck'i çek. `roomType` Türkçe etiket beklenir ("Yatak Odası" gibi);
  /// backend best-effort eşler, eşleşme yoksa rastgele örnek döner.
  Future<List<SwipeCard>> fetchDeck({
    String? roomType,
    int limit = 8,
  }) async {
    final qp = <String, String>{
      'limit': limit.toString(),
      if (roomType != null && roomType.trim().isNotEmpty)
        'room_type': roomType.trim(),
    };
    final uri = Uri.parse('$_baseUrl/api/swipe-deck').replace(
      queryParameters: qp,
    );
    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 4));
      if (resp.statusCode != 200) return const <SwipeCard>[];
      final body = jsonDecode(resp.body);
      if (body is! Map<String, dynamic>) return const <SwipeCard>[];
      final cards = body['cards'];
      if (cards is! List) return const <SwipeCard>[];
      final out = <SwipeCard>[];
      for (final c in cards) {
        if (c is Map<String, dynamic>) {
          final card = SwipeCard.fromJson(c);
          if (card.id.isNotEmpty && card.coverUrl.isNotEmpty) out.add(card);
        }
      }
      return out;
    } catch (_) {
      return const <SwipeCard>[];
    }
  }
}

// ─── helpers ───
Color? _hexToColor(String raw) {
  var s = raw.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 3) {
    s = s.split('').map((c) => '$c$c').join();
  }
  if (s.length != 6) return null;
  final v = int.tryParse(s, radix: 16);
  if (v == null) return null;
  return Color(0xFF000000 | v);
}
