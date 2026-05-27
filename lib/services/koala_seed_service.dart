// KoalaSeedService — Evlumba Design "sentetik tasarımcı" havuzu.
//
// Bu pseudo-tasarımcının portfolyosu = `koala_cards` tablosunda
// source='gemini-seed' AND is_published=true rowları. style-discovery feed'i,
// conversation_detail portfolyo barı ve DesignerProfileSheet hep bu havuzu
// gösterir. Tek bir source of truth — paginate edilebilir.
//
// Cursor: `created_at` ISO string. Sıralama quality_score DESC, created_at DESC.
// quality_score nullable olduğu için cursor olarak created_at kullanılıyor
// (defansif — quality_score cursor'u NULL row geçince bozulur).

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef PagedResult<T> = ({List<T> items, bool hasMore, dynamic cursor});

class KoalaSeedService {
  KoalaSeedService._();

  /// Sentetik tasarımcı için sabit id — UI tarafında kullanılır.
  static const String evlumbaDesignerId = 'evlumba-design';

  /// Evlumba seed kartları — paginated. Cursor `String?` ISO created_at.
  /// İlk sayfada beforeCreatedAt=null → top quality.
  static Future<PagedResult<Map<String, dynamic>>> evlumbaCardsPaged({
    int limit = 18,
    String? beforeCreatedAt,
  }) async {
    try {
      final db = Supabase.instance.client;
      var q = db
          .from('koala_cards')
          .select('id, title, description, room_type, style, cdn_url, '
              'original_url, quality_score, created_at')
          .eq('source', 'gemini-seed')
          .eq('is_published', true);
      if (beforeCreatedAt != null && beforeCreatedAt.isNotEmpty) {
        q = q.lt('created_at', beforeCreatedAt);
      }
      final data = await q
          .order('quality_score', ascending: false, nullsFirst: false)
          .order('created_at', ascending: false)
          .limit(limit);
      final rows = List<Map<String, dynamic>>.from(data);
      // UI'ın beklediği şape (cover_image_url + id) — conversation_detail ve
      // unified_profile_view aynı normalizasyonu paylaşır.
      final normalized = rows.map<Map<String, dynamic>>((r) {
        final img = (r['cdn_url'] ?? r['original_url'] ?? '').toString();
        return {
          'id': r['id'],
          'title': (r['title'] ?? '').toString(),
          'description': (r['description'] ?? '').toString(),
          'room_type': (r['room_type'] ?? '').toString(),
          'category': (r['room_type'] ?? '').toString(),
          'cover_image_url': img,
          'image_url': img,
          'created_at': r['created_at'],
        };
      }).toList();
      String? nextCursor;
      if (normalized.isNotEmpty) {
        nextCursor = rows.last['created_at']?.toString();
      }
      return (
        items: normalized,
        hasMore: rows.length >= limit,
        cursor: nextCursor,
      );
    } catch (e) {
      debugPrint('KoalaSeedService.evlumbaCardsPaged failed: $e');
      return (items: <Map<String, dynamic>>[], hasMore: false, cursor: null);
    }
  }
}
