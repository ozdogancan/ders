import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Evlumba DB'den gerçek tasarımcı, proje ve ürün çeken servis.
/// Koala'nın Supabase'inden AYRI — read-only bağlantı.
class EvlumbaLiveService {
  EvlumbaLiveService._();

  static SupabaseClient? _client;

  /// main.dart'tan bir kere çağrılır
  static void initialize({required String url, required String anonKey}) {
    _client = SupabaseClient(url, anonKey);
    debugPrint('EvlumbaLive: initialized → $url');
  }

  static SupabaseClient get client {
    if (_client == null) throw StateError('EvlumbaLiveService not initialized');
    return _client!;
  }

  static bool get isReady => _client != null;

  // ═══════════════════════════════════════
  // TASARIMCILAR (profiles tablosu)
  // ═══════════════════════════════════════

  /// Tüm tasarımcıları getir (role = 'designer')
  static Future<List<Map<String, dynamic>>> getDesigners({
    int limit = 20,
    int offset = 0,
    String? city,
    String? specialty,
  }) async {
    var query = client.from('profiles').select().eq('role', 'designer');

    if (city != null && city.isNotEmpty) {
      query = query.eq('city', city);
    }

    final data = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    debugPrint('EvlumbaLive: ${data.length} designers fetched');
    return List<Map<String, dynamic>>.from(data);
  }

  /// Tek tasarımcı detay
  static Future<Map<String, dynamic>?> getDesigner(String id) async {
    final data = await client
        .from('profiles')
        .select()
        .eq('id', id)
        .eq('role', 'designer')
        .maybeSingle();
    return data;
  }

  /// Tasarımcı ara (isim veya uzmanlık)
  static Future<List<Map<String, dynamic>>> searchDesigners(
    String query,
  ) async {
    final data = await client
        .from('profiles')
        .select()
        .eq('role', 'designer')
        .or(
          'full_name.ilike.%$query%,specialty.ilike.%$query%,business_name.ilike.%$query%',
        )
        .order('created_at', ascending: false)
        .limit(20);
    return List<Map<String, dynamic>>.from(data);
  }

  // ═══════════════════════════════════════
  // PROJELER (designer_projects tablosu)
  // ═══════════════════════════════════════

  /// Yayınlanmış projeleri getir (feed / keşfet)
  static Future<List<Map<String, dynamic>>> getProjects({
    int limit = 20,
    int offset = 0,
    String? projectType,
    String? tag,
    String? query,
    String? designerId,
  }) async {
    var q = client
        .from('designer_projects')
        .select('*, designer_project_images(image_url, sort_order)')
        .eq('is_published', true);

    if (designerId != null && designerId.isNotEmpty) {
      q = q.eq('designer_id', designerId);
    }

    if (projectType != null && projectType.isNotEmpty) {
      q = q.eq('project_type', projectType);
    }

    if (query != null && query.isNotEmpty) {
      q = q.or('title.ilike.%$query%,description.ilike.%$query%');
    }

    final data = await q
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    debugPrint('EvlumbaLive: ${data.length} projects fetched');
    return List<Map<String, dynamic>>.from(data);
  }

  /// Bir projenin tüm görselleri
  static Future<List<Map<String, dynamic>>> getProjectImages(
    String projectId,
  ) async {
    final data = await client
        .from('designer_project_images')
        .select()
        .eq('project_id', projectId)
        .order('sort_order');
    return List<Map<String, dynamic>>.from(data);
  }

  /// Bir projenin shop links'leri (ürünler)
  static Future<List<Map<String, dynamic>>> getProjectShopLinks(
    String projectId,
  ) async {
    final data = await client
        .from('designer_project_shop_links')
        .select()
        .eq('project_id', projectId);
    return List<Map<String, dynamic>>.from(data);
  }

  /// Tasarımcının tüm projeleri
  static Future<List<Map<String, dynamic>>> getDesignerProjects(
    String designerId,
  ) async {
    final data = await client
        .from('designer_projects')
        .select('*, designer_project_images(image_url, sort_order)')
        .eq('designer_id', designerId)
        .eq('is_published', true)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  // ═══════════════════════════════════════
  // REVIEWS
  // ═══════════════════════════════════════

  /// Tasarımcının yorumları
  static Future<List<Map<String, dynamic>>> getDesignerReviews(
    String designerId,
  ) async {
    final data = await client
        .from('designer_reviews')
        .select('*, profiles!homeowner_id(full_name, avatar_url)')
        .eq('designer_id', designerId)
        .order('created_at', ascending: false)
        .limit(20);
    return List<Map<String, dynamic>>.from(data);
  }

  // ═══════════════════════════════════════
  // LISTINGS (iş ilanları)
  // ═══════════════════════════════════════

  /// Aktif ilanlar
  static Future<List<Map<String, dynamic>>> getListings({
    int limit = 20,
    String? city,
  }) async {
    var query = client
        .from('listings')
        .select('*, profiles!owner_id(full_name, avatar_url)')
        .eq('status', 'active');

    if (city != null) {
      query = query.eq('city', city);
    }

    final data = await query.order('created_at', ascending: false).limit(limit);
    return List<Map<String, dynamic>>.from(data);
  }

  // ═══════════════════════════════════════
  // BLOG
  // ═══════════════════════════════════════

  /// Yayınlanmış blog yazıları
  static Future<List<Map<String, dynamic>>> getBlogPosts({
    int limit = 10,
  }) async {
    final data = await client
        .from('blog_posts')
        .select('*, profiles!author_id(full_name, avatar_url)')
        .eq('status', 'published')
        .order('published_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(data);
  }

  // ═══════════════════════════════════════
  // İSTATİSTİKLER (AI context için)
  // ═══════════════════════════════════════

  /// AI'a verilecek hızlı özet
  static Future<Map<String, dynamic>> getQuickStats() async {
    try {
      final designers = await client
          .from('profiles')
          .select('id')
          .eq('role', 'designer');
      final projects = await client
          .from('designer_projects')
          .select('id')
          .eq('is_published', true);

      return {
        'designer_count': (designers as List).length,
        'project_count': (projects as List).length,
      };
    } catch (e) {
      return {'designer_count': 0, 'project_count': 0};
    }
  }
}
