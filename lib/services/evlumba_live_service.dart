import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Evlumba DB'den gerçek tasarımcı, proje ve ürün çeken servis.
/// Koala'nın Supabase'inden AYRI — read-only bağlantı.
class EvlumbaLiveService {
  EvlumbaLiveService._();

  static SupabaseClient? _client;
  static String? _pendingUrl;
  static String? _pendingAnonKey;
  static bool _initializing = false;
  static int _retryCount = 0;
  static const int _maxRetries = 5;
  static final Completer<bool> _readyCompleter = Completer<bool>();

  /// main.dart'tan bir kere çağrılır
  static void initialize({required String url, required String anonKey}) {
    _pendingUrl = url;
    _pendingAnonKey = anonKey;
    _tryInit();
  }

  static void _tryInit() {
    if (_client != null || _initializing) return;
    if (_pendingUrl == null || _pendingAnonKey == null) return;
    _initializing = true;
    try {
      _client = SupabaseClient(_pendingUrl!, _pendingAnonKey!);
      debugPrint('EvlumbaLive: initialized → $_pendingUrl');
      if (!_readyCompleter.isCompleted) _readyCompleter.complete(true);
    } catch (e) {
      debugPrint('EvlumbaLive: init failed (attempt ${_retryCount + 1}/$_maxRetries) → $e');
      _initializing = false;
      if (_retryCount < _maxRetries) {
        _retryCount++;
        Future.delayed(const Duration(seconds: 3), _tryInit);
      } else {
        debugPrint('EvlumbaLive: giving up after $_maxRetries retries');
        if (!_readyCompleter.isCompleted) _readyCompleter.complete(false);
      }
    }
  }

  static SupabaseClient get client {
    if (_client == null) {
      // Auto-retry if pending config exists
      _tryInit();
      if (_client == null) throw StateError('EvlumbaLiveService not initialized');
    }
    return _client!;
  }

  static bool get isReady => _client != null;

  /// Bağlantı hazır olana kadar bekle (max 10 saniye)
  static Future<bool> waitForReady({Duration timeout = const Duration(seconds: 10)}) async {
    if (isReady) return true;
    if (_pendingUrl == null) return false; // config yok
    _tryInit();
    try {
      return await _readyCompleter.future.timeout(timeout, onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }

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

  /// Tek tasarımcı detay (role filtresi yok — proje sahibi zaten tasarımcı)
  static Future<Map<String, dynamic>?> getDesigner(String id) async {
    final data = await client
        .from('profiles')
        .select()
        .eq('id', id)
        .maybeSingle();
    return data;
  }

  /// Birden fazla tasarımcıyı tek sorguda getir (N+1 önleme)
  /// Batch sorgu başarısız olursa tek tek fallback yapar.
  static Future<List<Map<String, dynamic>>> getDesignersByIds(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return [];
    try {
      // Chunk: PostgREST URL uzunluğu aşılmasın (max 15 ID per chunk)
      final results = <Map<String, dynamic>>[];
      for (var i = 0; i < ids.length; i += 15) {
        final chunk = ids.sublist(i, (i + 15).clamp(0, ids.length));
        final data = await client
            .from('profiles')
            .select()
            .inFilter('id', chunk);
        results.addAll(List<Map<String, dynamic>>.from(data));
      }
      debugPrint('EvlumbaLive: getDesignersByIds batch OK → ${results.length}/${ids.length}');
      return results;
    } catch (e) {
      debugPrint('EvlumbaLive: getDesignersByIds batch failed ($e), falling back to individual queries');
      // Fallback: tek tek çek (N+1 ama en azından çalışır)
      final results = <Map<String, dynamic>>[];
      for (final id in ids) {
        try {
          final d = await getDesigner(id);
          if (d != null) results.add(d);
        } catch (_) {}
      }
      debugPrint('EvlumbaLive: getDesignersByIds fallback → ${results.length}/${ids.length}');
      return results;
    }
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
        .select('*, designer_project_images(image_url, sort_order), '
            'profiles:designer_id(id, full_name, avatar_url, city, profession)')
        .eq('is_published', true);

    if (designerId != null && designerId.isNotEmpty) {
      q = q.eq('designer_id', designerId);
    }

    if (projectType != null && projectType.isNotEmpty) {
      q = q.ilike('project_type', projectType);
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

  /// Tek proje bilgisi (detay ekranı için) — tasarımcı profili ile join'li
  static Future<Map<String, dynamic>?> getProjectById(String projectId) async {
    if (projectId.isEmpty) return null;
    try {
      final data = await client
          .from('designer_projects')
          .select('*, designer_project_images(image_url, sort_order), '
              'profiles:designer_id(id, full_name, avatar_url, city, profession)')
          .eq('id', projectId)
          .maybeSingle();
      return data == null ? null : Map<String, dynamic>.from(data);
    } catch (e) {
      debugPrint('EvlumbaLive: getProjectById($projectId) failed: $e');
      return null;
    }
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

  /// Tek tasarımcı bilgisi
  static Future<Map<String, dynamic>?> getDesignerById(String designerId) async {
    try {
      final data = await client
          .from('profiles')
          .select()
          .eq('id', designerId)
          .maybeSingle();
      return data;
    } catch (e) {
      debugPrint('EvlumbaLive: getDesignerById($designerId) failed: $e');
      return null;
    }
  }

  /// Tasarımcının tüm projeleri
  static Future<List<Map<String, dynamic>>> getDesignerProjects(
    String designerId, {
    int limit = 50,
  }) async {
    final data = await client
        .from('designer_projects')
        .select('*, designer_project_images(image_url, sort_order)')
        .eq('designer_id', designerId)
        .eq('is_published', true)
        .order('created_at', ascending: false)
        .limit(limit);
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

  /// AI'a verilecek hızlı özet (5 dk cache)
  static Map<String, dynamic>? _statsCache;
  static DateTime? _statsCachedAt;

  static Future<Map<String, dynamic>> getQuickStats() async {
    // Cache kontrolü — 5 dakika geçerli
    if (_statsCache != null &&
        _statsCachedAt != null &&
        DateTime.now().difference(_statsCachedAt!).inMinutes < 5) {
      return _statsCache!;
    }
    try {
      // Paralel sorgula
      final results = await Future.wait([
        client.from('profiles').select('id'),
        client.from('designer_projects').select('id').eq('is_published', true),
      ]);

      _statsCache = {
        'designer_count': (results[0] as List).length,
        'project_count': (results[1] as List).length,
      };
      _statsCachedAt = DateTime.now();
      return _statsCache!;
    } catch (e) {
      return {'designer_count': 0, 'project_count': 0};
    }
  }
}
