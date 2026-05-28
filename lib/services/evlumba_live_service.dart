import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cache_service.dart';

/// Evlumba DB'den gerçek tasarımcı, proje ve ürün çeken servis.
/// Koala'nın Supabase'inden AYRI — read-only bağlantı.
class EvlumbaLiveService {
  EvlumbaLiveService._();

  /// Boot-time RAM warm: önceki oturumdan saklanan style-discovery deck'i.
  /// StyleDiscoveryLiveScreen initState'te bu listeyi sync olarak okuyup
  /// ilk frame'de kart gösterebilir. Navigate-out / navigate-in sırasında
  /// da kullanılır — screen unmount olsa bile RAM'de kalır.
  static List<Map<String, dynamic>>? prefetchedDeck;
  static const String _prefsDeckCacheKey = 'style_discovery_deck_cache_v1';

  /// Koala DB (Supabase) `koala_cards` seed havuzu — splash boyunca proaktif
  /// olarak çekilir, böylece StyleDiscoveryLiveScreen mount olduğunda
  /// _loadSeedPool tekrar ağ sorgusu yapmak yerine bu listeyi kullanabilir.
  /// null = henüz prefetch çalışmadı; [] = çalıştı ama boş döndü.
  static List<Map<String, dynamic>>? prefetchedSeedPool;
  static bool _prefetchInFlight = false;
  static bool _prefetchDone = false;

  /// Tek-shot proaktif prefetch — main.dart Supabase init'inden hemen sonra
  /// (NOT awaited) çağrılır. Splash sırasında paralel olarak:
  ///   1) EvlumbaLiveService.waitForReady (zaten initialize çağrıldıysa hızlı)
  ///   2) İlk 10 designer_projects (cover + designer_project_images join'i)
  ///   3) koala_cards seed havuzu (gemini-seed, limit 300)
  ///   4) İlk 3 cover URL'ini CachedNetworkImage cache'ine (bitmap download)
  /// Her adım kendi try/catch'inde — bir hata diğerlerini blokle*MEZ*.
  ///
  /// StyleDiscoveryLiveScreen mount olduğunda `prefetchedDeck` ve
  /// `prefetchedSeedPool` zaten dolu → ramWarm path'i tetiklenir, ilk kart
  /// anında çıkar.
  static Future<void> prefetchForHome() async {
    if (_prefetchDone || _prefetchInFlight) return;
    _prefetchInFlight = true;
    try {
      // 1) Evlumba ready bekle — initialize çağrılmadan çağrılırsa kısa devre.
      bool evlumbaReady = false;
      try {
        evlumbaReady = await waitForReady(
          timeout: const Duration(seconds: 6),
        );
      } catch (e) {
        debugPrint('EvlumbaLive.prefetch: waitForReady error → $e');
      }

      // 2) + 3) paralel: designer_projects ilk batch + koala_cards seed pool.
      final futures = <Future<void>>[];

      if (evlumbaReady && prefetchedDeck == null) {
        futures.add(() async {
          try {
            final projects = await getProjects(limit: 10);
            // Cover'ı olmayanları ele
            final filtered = projects.where((p) {
              for (final k in ['cover_image_url', 'cover_url', 'image_url']) {
                final v = (p[k] ?? '').toString().trim();
                if (v.isNotEmpty && !v.startsWith('data:')) return true;
              }
              final imgs = p['designer_project_images'] as List?;
              return imgs != null && imgs.isNotEmpty;
            }).toList();
            if (filtered.isNotEmpty) {
              prefetchedDeck = filtered;
              debugPrint(
                  'EvlumbaLive.prefetch: deck primed (${filtered.length})');
              // 4) İlk 3 cover'ı bitmap-cache'e ısıt — context'siz, sadece
              // download tetikle.
              _precacheFirstCovers(filtered);
            }
          } catch (e) {
            debugPrint('EvlumbaLive.prefetch: getProjects failed → $e');
          }
        }());
      }

      // koala_cards seed pool — Koala'nın ana Supabase client'ı kullanılıyor.
      futures.add(() async {
        try {
          final sb = Supabase.instance.client;
          final data = await sb
              .from('koala_cards')
              .select('id, title, description, room_type, style, cdn_url, '
                  'original_url, aspect, created_at')
              .eq('source', 'gemini-seed')
              .eq('is_published', true)
              .limit(300);
          prefetchedSeedPool = List<Map<String, dynamic>>.from(data);
          debugPrint(
              'EvlumbaLive.prefetch: seed pool primed (${prefetchedSeedPool!.length})');
        } catch (e) {
          debugPrint('EvlumbaLive.prefetch: seed pool failed → $e');
        }
      }());

      await Future.wait(futures);
    } catch (e) {
      debugPrint('EvlumbaLive.prefetch: unexpected → $e');
    } finally {
      _prefetchInFlight = false;
      _prefetchDone = true;
    }
  }

  /// İlk birkaç cover URL'ini CachedNetworkImage disk+RAM cache'ine indir.
  /// context yok — resolve(ImageConfiguration.empty) network çağrısını
  /// tetikler; sonuç ImageProvider'ın paylaşımlı cache'inde kalır.
  static void _precacheFirstCovers(List<Map<String, dynamic>> projects) {
    try {
      var primed = 0;
      for (final p in projects) {
        if (primed >= 3) break;
        String url = '';
        for (final k in ['cover_image_url', 'cover_url', 'image_url']) {
          final v = (p[k] ?? '').toString().trim();
          if (v.isNotEmpty && !v.startsWith('data:')) {
            url = v;
            break;
          }
        }
        if (url.isEmpty) {
          final imgs = p['designer_project_images'] as List?;
          if (imgs != null && imgs.isNotEmpty) {
            final first = imgs.first;
            if (first is Map) {
              url = (first['image_url'] ?? '').toString();
            }
          }
        }
        if (url.isEmpty) continue;
        try {
          // resolve() çağrısı, ImageProvider'ın load akışını başlatır →
          // CachedNetworkImage HTTP fetch yapıp diske yazar.
          CachedNetworkImageProvider(url)
              .resolve(const ImageConfiguration())
              .addListener(ImageStreamListener(
            (_, _) {},
            onError: (e, _) {
              debugPrint(
                  'EvlumbaLive.prefetch: cover bitmap failed ($url) → $e');
            },
          ));
          primed++;
        } catch (e) {
          debugPrint('EvlumbaLive.prefetch: cover resolve failed → $e');
        }
      }
      if (primed > 0) {
        debugPrint('EvlumbaLive.prefetch: $primed cover bitmaps warming');
      }
    } catch (_) {}
  }

  /// main.dart boot sırasında, paralel `Future.wait` içinden çağrılır.
  /// Disk'ten deck cache'ini RAM'e alır. ~5-15ms, JSON decode dahil.
  static Future<void> warmDeckFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsDeckCacheKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      if (list.isNotEmpty) prefetchedDeck = list;
    } catch (_) {}
  }

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
    // perf: in-memory cache 5dk — designer profile değişmez sıklıkta, aynı id
    // birden çok ekranda tekrar çağrılıyor (chat, projects, designer detail).
    final cacheKey = 'evlumba_designer_$id';
    final cached = CacheService.get<Map<String, dynamic>>(cacheKey);
    if (cached != null) return cached;
    final data = await client
        .from('profiles')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (data != null) {
      CacheService.set(cacheKey, Map<String, dynamic>.from(data),
          duration: const Duration(minutes: 5));
    }
    return data;
  }

  /// Birden fazla tasarımcıyı tek sorguda getir (N+1 önleme)
  /// Batch sorgu başarısız olursa tek tek fallback yapar.
  static Future<List<Map<String, dynamic>>> getDesignersByIds(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return [];
    // perf: cache hit'leri ayır, sadece eksik id'leri DB'den çek.
    final results = <Map<String, dynamic>>[];
    final missing = <String>[];
    for (final id in ids) {
      final c = CacheService.get<Map<String, dynamic>>('evlumba_designer_$id');
      if (c != null) {
        results.add(c);
      } else {
        missing.add(id);
      }
    }
    if (missing.isEmpty) {
      debugPrint('EvlumbaLive: getDesignersByIds all cache hit → ${results.length}');
      return results;
    }
    try {
      // Chunk: PostgREST URL uzunluğu aşılmasın (max 15 ID per chunk)
      for (var i = 0; i < missing.length; i += 15) {
        final chunk = missing.sublist(i, (i + 15).clamp(0, missing.length));
        final data = await client
            .from('profiles')
            .select()
            .inFilter('id', chunk);
        for (final row in List<Map<String, dynamic>>.from(data)) {
          final id = row['id']?.toString();
          if (id != null && id.isNotEmpty) {
            CacheService.set('evlumba_designer_$id', row,
                duration: const Duration(minutes: 5));
          }
          results.add(row);
        }
      }
      debugPrint('EvlumbaLive: getDesignersByIds batch OK → ${results.length}/${ids.length} (cache hit ${ids.length - missing.length})');
      return results;
    } catch (e) {
      debugPrint('EvlumbaLive: getDesignersByIds batch failed ($e), falling back to individual queries');
      // Fallback: tek tek çek (N+1 ama en azından çalışır). Cache hit'leri
      // koru, eksikleri tek tek getDesigner ile çek (kendisi cache'liyor).
      for (final id in missing) {
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
    // perf: getDesigner ile aynı cache key'i paylaş — duplicate fetch'leri ele.
    final cacheKey = 'evlumba_designer_$designerId';
    final cached = CacheService.get<Map<String, dynamic>>(cacheKey);
    if (cached != null) return cached;
    try {
      final data = await client
          .from('profiles')
          .select()
          .eq('id', designerId)
          .maybeSingle();
      if (data != null) {
        CacheService.set(cacheKey, Map<String, dynamic>.from(data),
            duration: const Duration(minutes: 5));
      }
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

  /// Tasarımcının projeleri — paginated (cursor: created_at ISO string).
  /// Defansif: bağlantı yoksa boş döner. LazyGridView ile uyumlu shape.
  static Future<({List<Map<String, dynamic>> items, bool hasMore, dynamic cursor})>
      getDesignerProjectsPaged(
    String designerId, {
    int limit = 18,
    String? beforeCreatedAt,
  }) async {
    if (designerId.isEmpty) {
      return (items: <Map<String, dynamic>>[], hasMore: false, cursor: null);
    }
    try {
      if (!isReady) {
        await waitForReady(timeout: const Duration(seconds: 4));
      }
      if (!isReady) {
        return (items: <Map<String, dynamic>>[], hasMore: false, cursor: null);
      }
      // 2026-05-28 FIX 3: `is_published=true` filter removed because many
      // existing designer_projects rows have NULL/false on this column even
      // though they are curated (e.g. Neslihan Doğan). Treat the table as
      // curated upstream by Evlumba team. TODO: re-enable filter once a
      // backfill sets is_published=true for all curated rows.
      var q = client
          .from('designer_projects')
          .select('*, designer_project_images(image_url, sort_order)')
          .eq('designer_id', designerId);
      if (beforeCreatedAt != null && beforeCreatedAt.isNotEmpty) {
        q = q.lt('created_at', beforeCreatedAt);
      }
      final data = await q
          .order('created_at', ascending: false)
          .limit(limit);
      final rows = List<Map<String, dynamic>>.from(data);
      debugPrint(
          '[evlumba] getDesignerProjectsPaged($designerId) → ${rows.length} rows');
      final nextCursor =
          rows.isNotEmpty ? rows.last['created_at']?.toString() : null;
      return (
        items: rows,
        hasMore: rows.length >= limit,
        cursor: nextCursor,
      );
    } catch (e) {
      debugPrint('EvlumbaLive.getDesignerProjectsPaged($designerId) failed: $e');
      return (items: <Map<String, dynamic>>[], hasMore: false, cursor: null);
    }
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
