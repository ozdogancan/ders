import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import 'cache_service.dart';

/// Pre-computed populer icerik servisi.
/// popular_content tablosundan okur (fn_compute_popular ile doldurulur).
/// Public veri — auth gereksiz.
class PopularContentService {
  PopularContentService._();

  static SupabaseClient get _db => Supabase.instance.client;

  /// Populer tasarimlar (haftalik)
  static Future<List<Map<String, dynamic>>> getPopularDesigns({int limit = 20}) async {
    return _getByType('design', limit: limit);
  }

  /// Populer tasarimcilar (haftalik)
  static Future<List<Map<String, dynamic>>> getPopularDesigners({int limit = 10}) async {
    return _getByType('designer', limit: limit);
  }

  /// Populer urunler (haftalik)
  static Future<List<Map<String, dynamic>>> getPopularProducts({int limit = 20}) async {
    return _getByType('product', limit: limit);
  }

  static Future<List<Map<String, dynamic>>> _getByType(String type, {int limit = 20}) async {
    if (!Env.hasSupabaseConfig) return [];

    // Cache kontrol (10 dakika)
    final cacheKey = 'popular_${type}_weekly';
    final cached = CacheService.get<List<Map<String, dynamic>>>(cacheKey);
    if (cached != null) return cached;

    try {
      final res = await _db
          .from('popular_content')
          .select('item_id, score')
          .eq('type', type)
          .eq('period', 'weekly')
          .order('score', ascending: false)
          .limit(limit);

      final data = List<Map<String, dynamic>>.from(res);
      CacheService.set(cacheKey, data, duration: const Duration(minutes: 10));
      return data;
    } catch (e) {
      debugPrint('PopularContentService.$type error: $e');
      return [];
    }
  }
}
