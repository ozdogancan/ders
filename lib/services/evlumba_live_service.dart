import 'dart:async';
import 'dart:math';

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
  // Completer final değil — fail durumunda reset edilir, böylece
  // kullanıcı uçak modundan çıktığında waitForReady() yeniden denemeyi
  // tetikleyebilir (sonsuz "false" sıkışmasına son).
  static Completer<bool> _readyCompleter = Completer<bool>();
  // En son reinit denemesi — pasif retry için cooldown.
  static DateTime? _lastFailAt;
  // Reinit cooldown'u: min 60 sn'lik bir fail geçmişi varsa yeniden dene.
  static const Duration _reinitCooldown = Duration(seconds: 60);

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
      _lastFailAt = null;
      _initializing = false;
      if (!_readyCompleter.isCompleted) _readyCompleter.complete(true);
    } catch (e) {
      debugPrint('EvlumbaLive: init failed (attempt ${_retryCount + 1}/$_maxRetries) → $e');
      _initializing = false;
      if (_retryCount < _maxRetries) {
        _retryCount++;
        Future.delayed(const Duration(seconds: 3), _tryInit);
      } else {
        debugPrint('EvlumbaLive: giving up after $_maxRetries retries (will retry passively on next waitForReady)');
        _lastFailAt = DateTime.now();
        if (!_readyCompleter.isCompleted) _readyCompleter.complete(false);
      }
    }
  }

  /// Başarısız olduysa ve cooldown dolduysa yeniden init denemesi tetikler.
  /// Pasif retry: kullanıcı waitForReady / client çağırdığında çalışır,
  /// ağ geri gelmiş olabilir.
  static void _maybeReinit() {
    if (_client != null || _initializing) return;
    if (_pendingUrl == null) return;
    final last = _lastFailAt;
    if (last == null) return;
    if (DateTime.now().difference(last) < _reinitCooldown) return;
    debugPrint('EvlumbaLive: reinit triggered (last fail: $last)');
    _retryCount = 0;
    _lastFailAt = null;
    // Complete(false) olmuş completer'ı sıfırla ki waitForReady bu sefer
    // yeni sonucu bekleyebilsin.
    if (_readyCompleter.isCompleted) {
      _readyCompleter = Completer<bool>();
    }
    _tryInit();
  }

  static SupabaseClient get client {
    if (_client == null) {
      // Auto-retry if pending config exists (fresh start veya pasif reinit)
      _maybeReinit();
      if (_client == null) _tryInit();
      if (_client == null) throw StateError('EvlumbaLiveService not initialized');
    }
    return _client!;
  }

  static bool get isReady => _client != null;

  /// Bağlantı hazır olana kadar bekle (max 10 saniye).
  /// Önceki girişim başarısız olup cooldown geçtiyse yeniden init denenir.
  static Future<bool> waitForReady({Duration timeout = const Duration(seconds: 10)}) async {
    if (isReady) return true;
    if (_pendingUrl == null) return false; // config yok
    _maybeReinit();
    // Halen completer tamamlanmış ve false ise (cooldown dolmadı) hızlıca false dön.
    if (_readyCompleter.isCompleted) {
      try {
        final val = await _readyCompleter.future;
        if (val) return true;
        // false — cooldown'u beklemek yerine kullanıcıya hızlı dönüş.
        return false;
      } catch (_) {
        return false;
      }
    }
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

  /// İç mimari / dekorasyon DIŞINDA kalan specialty anahtarları.
  /// Grafik tasarım, logo, web, UI/UX vs. oda önerilerine girmesin.
  static const List<String> _nonInteriorSpecialtyKeywords = [
    'grafik', 'graphic',
    'logo', 'brand', 'branding',
    'web', 'ui', 'ux',
    'illüstrasyon', 'illustration',
    'motion', 'animasyon', 'animation',
    'video',
    'sosyal medya', 'social media',
    'reklam',
  ];

  /// Bir tasarımcı profilinin iç mekâna uygun olup olmadığını döndürür.
  /// specialty boşsa (null/empty) kabul edilir — eski kayıtlar filtreyle
  /// tamamen silinmesin.
  static bool _isInteriorSpecialty(Map<String, dynamic> p) {
    final s = (p['specialty'] ?? '').toString().toLowerCase().trim();
    if (s.isEmpty) return true;
    for (final kw in _nonInteriorSpecialtyKeywords) {
      if (s.contains(kw)) return false;
    }
    return true;
  }

  /// Tüm tasarımcıları getir (role = 'designer').
  ///
  /// [interiorOnly] true ise grafik/logo/web vb. uzmanlık alanları client-side
  /// dışlanır. [roomType]/[style] verilirse eşleşen specialty'ler puanlanıp
  /// öne alınır (sıralama sabit olmaz — rastgeleleştirilmiş).
  static Future<List<Map<String, dynamic>>> getDesigners({
    int limit = 20,
    int offset = 0,
    String? city,
    String? specialty,
    bool interiorOnly = false,
    String? roomType,
    String? style,
  }) async {
    var query = client.from('profiles').select().eq('role', 'designer');

    if (city != null && city.isNotEmpty) {
      query = query.eq('city', city);
    }

    // Aynı ilk-N'i döndürmemek için havuzu genişlet: limit*4 veya 40 cap.
    final poolSize = interiorOnly
        ? (limit * 4).clamp(limit, 40)
        : limit;

    final data = await query
        .order('created_at', ascending: false)
        .range(offset, offset + poolSize - 1);
    var list = List<Map<String, dynamic>>.from(data);

    if (interiorOnly) {
      final before = list.length;
      list = list.where(_isInteriorSpecialty).toList();
      debugPrint('EvlumbaLive: interior filter $before → ${list.length}');
    }

    if (interiorOnly) {
      // Puanla: room/style eşleşmesi + küçük rastgele bozulma
      // → her çağrı farklı ama alakalılar hâlâ öne geliyor.
      final rt = (roomType ?? '').toLowerCase().trim();
      final st = (style ?? '').toLowerCase().trim();
      final rand = _rand;
      int score(Map<String, dynamic> p) {
        final spec = (p['specialty'] ?? '').toString().toLowerCase();
        final bio = (p['bio'] ?? '').toString().toLowerCase();
        var s = 0;
        if (rt.isNotEmpty && (spec.contains(rt) || bio.contains(rt))) s += 5;
        if (st.isNotEmpty && (spec.contains(st) || bio.contains(st))) s += 4;
        for (final kw in ['iç mimar', 'mimar', 'dekoratör', 'dekorasyon', 'interior']) {
          if (spec.contains(kw)) { s += 2; break; }
        }
        s += rand.nextInt(3); // diversity jitter
        return s;
      }
      list.sort((a, b) => score(b).compareTo(score(a)));
    }

    final result = list.take(limit).toList();
    debugPrint('EvlumbaLive: ${result.length}/${list.length} designers returned (pool=$poolSize)');
    return result;
  }

  static final Random _rand = Random();

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

  /// Tasarımcı ara (isim veya uzmanlık).
  /// Çoklu kelime/token desteği: "Gökhan'ı bul" gibi sorgular için
  /// her token ayrı ilike'a dönüşür; boş stopwords (bul, göster, bana, ...)
  /// atılır; Türkçe akküzatif eki (ı/i/yı/yi/nı/ni) kırpılır.
  static Future<List<Map<String, dynamic>>> searchDesigners(
    String query,
  ) async {
    final raw = query.trim();
    if (raw.isEmpty) return [];
    const stopwords = {
      'bul', 'bulur', 'bulabilir', 'goster', 'göster', 'ara', 'bana', 'bize',
      'bir', 'biraz', 'bi', 'icin', 'için', 'lutfen', 'lütfen', 've', 'ile',
      'veya', 'mi', 'mı', 'misin', 'olan', 'var',
    };
    final tokens = raw
        .toLowerCase()
        .split(RegExp(r'''[\s,;:'".!?]+'''))
        .where((t) => t.isNotEmpty && !stopwords.contains(t))
        .map((t) {
      // kısa akküzatif eki kırp
      for (final suf in ['yi', 'yu', 'yü', 'ya', 'ye', 'nı', 'ni', 'nu']) {
        if (t.length > suf.length + 2 && t.endsWith(suf)) {
          return t.substring(0, t.length - suf.length);
        }
      }
      if (t.length > 3 && RegExp(r'[aeıioöuü]$').hasMatch(t)) {
        final prev = t[t.length - 2];
        if (!RegExp(r'[aeıioöuü]').hasMatch(prev)) {
          return t.substring(0, t.length - 1);
        }
      }
      return t;
    }).toList();

    // Hiç anlamlı token yoksa orijinal query ile tek atış yap
    final effective = tokens.isEmpty ? [raw] : tokens;
    // Tüm token'ları birleştiren OR sorgusu — herhangi bir alan herhangi bir
    // token'ı içeren tasarımcıları döndürür.
    final orClauses = <String>[];
    for (final t in effective) {
      final safe = t.replaceAll(',', ' ').replaceAll('(', '').replaceAll(')', '');
      orClauses.add('full_name.ilike.%$safe%');
      orClauses.add('specialty.ilike.%$safe%');
      orClauses.add('business_name.ilike.%$safe%');
    }
    final data = await client
        .from('profiles')
        .select()
        .eq('role', 'designer')
        .or(orClauses.join(','))
        .order('created_at', ascending: false)
        .limit(20);
    var results = List<Map<String, dynamic>>.from(data);

    // İsim eşleşmelerini koru (full_name match), sadece name match YOKKEN
    // specialty match ile gelen non-interior'ları dışla. Böylece
    // "Hakan bul" yine Hakan'ı getirir ama "modern tasarımcı" grafik
    // tasarımcı getirmez.
    results = results.where((p) {
      if (_isInteriorSpecialty(p)) return true;
      // Non-interior; sadece full_name eşleşirse kabul et
      final name = (p['full_name'] ?? '').toString().toLowerCase();
      for (final t in effective) {
        if (t.length >= 3 && name.contains(t)) return true;
      }
      return false;
    }).toList();

    // Name-priority: isim token'ı eşleşenleri öne al
    results.sort((a, b) {
      final an = (a['full_name'] ?? '').toString().toLowerCase();
      final bn = (b['full_name'] ?? '').toString().toLowerCase();
      int scoreA = 0;
      int scoreB = 0;
      for (final t in effective) {
        if (an.contains(t)) scoreA += 10;
        if (bn.contains(t)) scoreB += 10;
      }
      return scoreB.compareTo(scoreA);
    });
    return results;
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
