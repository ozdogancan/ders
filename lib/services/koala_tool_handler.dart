import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/config/env.dart';
import 'evlumba_live_service.dart';
import 'taste_profile_service.dart';

/// Gemini Function Calling handler.
/// AI'dan gelen tool çağrılarını alıp evlumba DB'den gerçek veri döndürür.
class KoalaToolHandler {
  const KoalaToolHandler._();

  /// AI enum (snake_case) → DB'deki Türkçe project_type eşleme
  /// Evlumba DB'de project_type Türkçe saklanıyor, case-insensitive .ilike kullanıyoruz
  static String? _mapRoomType(String? roomType) {
    if (roomType == null || roomType.isEmpty) return null;
    const mapping = {
      'salon': 'Oturma Odası',
      'yatak_odasi': 'Yatak Odası',
      'mutfak': 'Mutfak',
      'banyo': 'Banyo',
      'ofis': 'Ofis',
      'cocuk_odasi': 'Çocuk Odası',
      'antre': 'Antre',
      'balkon': 'Balkon',
      'ev_ofisi': 'Ev Ofisi',
    };
    return mapping[roomType.toLowerCase()] ?? roomType;
  }

  /// Ham project_type → kullanıcıya gösterilecek Türkçe etiket.
  /// DB zaten TR saklar ama snake_case de gelebilir (ör. "living_room").
  static String _prettyCategoryLabel(String raw) {
    if (raw.trim().isEmpty) return '';
    final key = raw.toLowerCase().trim();
    const trMap = {
      'living_room': 'Oturma Odası',
      'salon': 'Oturma Odası',
      'oturma odası': 'Oturma Odası',
      'bedroom': 'Yatak Odası',
      'yatak_odasi': 'Yatak Odası',
      'yatak odası': 'Yatak Odası',
      'kitchen': 'Mutfak',
      'mutfak': 'Mutfak',
      'bathroom': 'Banyo',
      'banyo': 'Banyo',
      'dining_room': 'Yemek Odası',
      'yemek odası': 'Yemek Odası',
      'office': 'Çalışma Odası',
      'ofis': 'Ofis',
      'ev_ofisi': 'Ev Ofisi',
      'ev ofisi': 'Ev Ofisi',
      'kids_room': 'Çocuk Odası',
      'cocuk_odasi': 'Çocuk Odası',
      'çocuk odası': 'Çocuk Odası',
      'hallway': 'Koridor / Hol',
      'antre': 'Antre',
      'balcony': 'Balkon',
      'balkon': 'Balkon',
      'outdoor': 'Dış Mekan',
    };
    if (trMap.containsKey(key)) return trMap[key]!;
    // Zaten TR görünüyorsa olduğu gibi döndür
    if (raw.contains(' ') || RegExp(r'[çğıöşüÇĞİÖŞÜ]').hasMatch(raw)) return raw;
    // snake_case → Title Case fallback
    return raw
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  /// Gemini'den gelen function call'ı çalıştır, gerçek veri döndür
  static Future<Map<String, dynamic>> handle(
    String functionName,
    Map<String, dynamic> args,
  ) async {
    debugPrint('KoalaToolHandler: $functionName($args)');

    switch (functionName) {
      case 'search_products':
        return _searchProducts(args);
      case 'search_projects':
        return _searchProjects(args);
      case 'search_designers':
        return _searchDesigners(args);
      case 'compare_products':
        return _compareProducts(args);
      default:
        return {'error': 'Unknown function: $functionName'};
    }
  }

  // ═══════════════════════════════════════════════════════
  // ÜRÜN ARA — Gemini Google Search Grounding ile gerçek ürünler
  // Koala API /api/products/search endpoint'ini çağırır
  // Fallback: Evlumba DB'den arama
  // ═══════════════════════════════════════════════════════
  static Future<Map<String, dynamic>> _searchProducts(
    Map<String, dynamic> args,
  ) async {
    try {
      final rawQuery = (args['query'] as String?) ?? '';
      // Güvenlik: wildcard injection'ı önle — %, _, virgül karakterlerini temizle.
      final query = rawQuery.replaceAll(RegExp(r'[%_,]'), '');
      final roomType = args['room_type'] as String?;
      final maxPrice = args['max_price'] as num?;
      final limit = (args['limit'] as num?)?.toInt().clamp(1, 8) ?? 6;
      final offset = (args['offset'] as num?)?.toInt().clamp(0, 500) ?? 0;

      // exclude_ids: liste ya da virgül-ayrılmış string olabilir.
      final excludeIdsRaw = args['exclude_ids'];
      final List<String> excludeIds = <String>[];
      if (excludeIdsRaw is List) {
        for (final e in excludeIdsRaw) {
          final s = e?.toString().trim() ?? '';
          if (s.isNotEmpty) excludeIds.add(s);
        }
      } else if (excludeIdsRaw is String && excludeIdsRaw.isNotEmpty) {
        for (final s in excludeIdsRaw.split(',')) {
          final t = s.trim();
          if (t.isNotEmpty) excludeIds.add(t);
        }
      }

      // Koala API'den gerçek ürün ara (Google Search Grounding)
      final apiResult = await _searchProductsFromAPI(
        query: query,
        roomType: roomType,
        maxPrice: maxPrice,
        limit: limit,
        offset: offset,
      );

      if (apiResult != null && (apiResult['products'] as List).isNotEmpty) {
        // match_note ekle (API result'a da)
        final annotated = _annotateProductsWithMatchNote(
          (apiResult['products'] as List).cast<Map<String, dynamic>>(),
          roomType: roomType,
          maxPrice: maxPrice,
        );
        return {...apiResult, 'products': annotated};
      }

      // API başarısız olursa Evlumba DB fallback
      debugPrint('KoalaToolHandler: API returned no products, trying Evlumba DB fallback');
      return _searchProductsFromEvlumba(
        query: query,
        roomType: roomType,
        maxPrice: maxPrice,
        limit: limit,
        offset: offset,
        excludeIds: excludeIds,
      );
    } catch (e) {
      debugPrint('KoalaToolHandler _searchProducts error: $e');
      return {'products': [], 'error': e.toString()};
    }
  }

  /// Ürün listesine `match_note` alanı ekler (varsa).
  static List<Map<String, dynamic>> _annotateProductsWithMatchNote(
    List<Map<String, dynamic>> products, {
    String? roomType,
    num? maxPrice,
  }) {
    final roomPretty = (roomType != null && roomType.isNotEmpty)
        ? _prettyRoom(roomType)
        : null;
    return products.map((item) {
      String? note;
      final title = (item['name'] ?? item['product_title'] ?? '').toString().toLowerCase();
      if (roomPretty != null && title.isNotEmpty) {
        final foldedTitle = _trFold(title);
        final foldedRoom = _trFold(roomPretty.toLowerCase());
        if (foldedTitle.contains(foldedRoom)) {
          note = '$roomPretty için seçildi';
        }
      }
      if (note == null && maxPrice != null) {
        final priceStr = (item['price'] ?? '').toString().replaceAll(RegExp(r'[^\d.,]'), '');
        final parsed = double.tryParse(priceStr.replaceAll('.', '').replaceAll(',', '.'));
        if (parsed != null && parsed > 0 && parsed < maxPrice.toDouble() * 0.7) {
          note = 'Bütçenin altında';
        }
      }
      if (note == null) return item;
      return {...item, 'match_note': note};
    }).toList();
  }

  /// Koala API üzerinden Gemini Google Search Grounding ile gerçek ürün ara
  static Future<Map<String, dynamic>?> _searchProductsFromAPI({
    required String query,
    String? roomType,
    num? maxPrice,
    required int limit,
    int offset = 0,
  }) async {
    try {
      final uri = Uri.parse('${Env.koalaApiUrl}/api/products/search');
      final body = {
        'query': query,
        if (roomType != null && roomType.isNotEmpty) 'room_type': roomType,
        if (maxPrice != null) 'max_price': maxPrice,
        'limit': limit,
        if (offset > 0) 'offset': offset,
      };

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        debugPrint('KoalaToolHandler API error: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final products = (data['products'] as List?) ?? [];

      if (products.isEmpty) return null;

      // API formatını UI formatına dönüştür + kalite filtresi
      final result = <Map<String, dynamic>>[];
      for (final p in products) {
        final item = p as Map<String, dynamic>;
        final url = (item['url'] ?? '').toString();
        final price = (item['price'] ?? '').toString();

        // URL doğrulama — boş, geçersiz, ana sayfa veya alakasız URL'leri atla
        if (url.isEmpty || url.length < 15) continue;
        try {
          final uri = Uri.parse(url);
          if (!uri.hasScheme || uri.path == '/' || uri.path.isEmpty) continue;
          // Bilinen hatalı domain/path kalıplarını filtrele
          final host = uri.host.toLowerCase();
          final path = uri.path.toLowerCase();
          // Çiçeksepeti ev/dekor dışı, koçtaş oto kategorisi gibi alakasız linkleri atla
          if (host.contains('ciceksepeti') && !path.contains('ev-') && !path.contains('dekor') && !path.contains('mobilya')) continue;
          if (path.contains('/otomobil') || path.contains('/oto-') || path.contains('/araba')) continue;
          // 404 veren yaygın kalıplar
          if (path.contains('/404') || path.contains('/error')) continue;
        } catch (_) {
          continue;
        }

        // Fiyatı olmayan ürünleri atla
        if (price.isEmpty || price == 'Fiyat bilgisi yok' || price == 'Bilinmiyor') continue;

        result.add({
          'id': item['id'] ?? 'search-${DateTime.now().millisecondsSinceEpoch}',
          'name': item['name'] ?? 'Ürün',
          'price': price,
          'image_url': item['image_url'] ?? '',
          'url': url,
          'shop_name': item['shop_name'] ?? '',
          'source': item['source'] ?? 'google_search',
          'project_id': '',
        });
      }

      if (result.isEmpty) return null;
      return {'products': result, 'count': result.length};
    } catch (e) {
      debugPrint('KoalaToolHandler _searchProductsFromAPI error: $e');
      return null;
    }
  }

  /// Evlumba DB'den ürün ara (fallback)
  static Future<Map<String, dynamic>> _searchProductsFromEvlumba({
    required String query,
    String? roomType,
    num? maxPrice,
    required int limit,
    int offset = 0,
    List<String> excludeIds = const [],
  }) async {
    try {
      if (!EvlumbaLiveService.isReady) {
        await EvlumbaLiveService.waitForReady();
        if (!EvlumbaLiveService.isReady) {
          debugPrint('KoalaToolHandler: EvlumbaLiveService not initialized after wait');
          return {'products': [], 'count': 0};
        }
      }
      final mappedRoom = _mapRoomType(roomType);

      var projectQuery = EvlumbaLiveService.client
          .from('designer_projects')
          .select('id')
          .eq('is_published', true);

      if (mappedRoom != null && mappedRoom.isNotEmpty) {
        projectQuery = projectQuery.ilike('project_type', mappedRoom);
      }

      final projects = await projectQuery.limit(50);
      // id null gelirse cast crash olur — güvenli string map + empty drop.
      final projectIds = (projects as List)
          .map((p) => p['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      if (projectIds.isEmpty) {
        return {
          'products': [],
          'message': 'Bu ürün için Türkiye marketplace\'lerinde arama yapılamadı. Kullanıcıya genel tasarım ipuçları sun.',
        };
      }

      var shopQuery = EvlumbaLiveService.client
          .from('designer_project_shop_links')
          .select()
          .inFilter('project_id', projectIds);

      if (query.isNotEmpty && !_isRoomName(query)) {
        final foldedQuery = _trFold(query);
        // Hem ham hem fold edilmiş variant için ara (Türkçe normalize).
        if (foldedQuery != query.toLowerCase()) {
          shopQuery = shopQuery.or(
            'product_title.ilike.%$query%,product_title.ilike.%$foldedQuery%',
          );
        } else {
          shopQuery = shopQuery.ilike('product_title', '%$query%');
        }
      }

      final rangeStart = offset;
      final rangeEnd = offset + limit * 3 - 1;
      final rawProducts = await shopQuery.range(rangeStart, rangeEnd);

      var products = (rawProducts as List).map((p) {
        final priceStr = (p['product_price'] ?? '')
            .toString()
            .replaceAll(RegExp(r'[^\d.,]'), '');
        final price = double.tryParse(
              priceStr.replaceAll('.', '').replaceAll(',', '.'),
            ) ??
            0;
        return {...p, 'parsed_price': price};
      }).toList();

      if (maxPrice != null) {
        products = products
            .where(
              (p) => (p['parsed_price'] as double) <= maxPrice.toDouble(),
            )
            .toList();
      }

      // excludeIds: shop_link.id veya product_title match'lerini ele.
      if (excludeIds.isNotEmpty) {
        final excludeSet = excludeIds.toSet();
        products = products.where((p) {
          final pid = (p['id'] ?? '').toString();
          final ptitle = (p['product_title'] ?? '').toString();
          if (pid.isNotEmpty && excludeSet.contains(pid)) return false;
          if (ptitle.isNotEmpty && excludeSet.contains(ptitle)) return false;
          return true;
        }).toList();
      }

      final roomPretty = (roomType != null && roomType.isNotEmpty)
          ? _prettyRoom(roomType)
          : null;
      final result = products.take(limit).map((p) {
        final title = (p['product_title'] ?? 'Ürün').toString();
        final priceRaw = (p['product_price'] ?? '').toString();

        // match_note hesapla
        String? note;
        if (roomPretty != null) {
          final foldedTitle = _trFold(title.toLowerCase());
          final foldedRoom = _trFold(roomPretty.toLowerCase());
          if (foldedTitle.contains(foldedRoom)) {
            note = '$roomPretty için seçildi';
          }
        }
        if (note == null && maxPrice != null) {
          final parsed = p['parsed_price'] as double?;
          if (parsed != null && parsed > 0 && parsed < maxPrice.toDouble() * 0.7) {
            note = 'Bütçenin altında';
          }
        }

        final item = <String, dynamic>{
          'id': p['id'],
          'name': title,
          'price': priceRaw,
          'image_url': p['product_image_url'] ?? '',
          'url': p['product_url'] ?? '',
          'shop_name': p['shop_name'] ?? '',
          'source': 'evlumba',
          'project_id': p['project_id'],
        };
        if (note != null) item['match_note'] = note;
        return item;
      }).toList();

      if (result.isEmpty) {
        return {
          'products': [],
          'count': 0,
          'message': 'Bu ürün için sonuç bulunamadı. Kullanıcıya alternatif öneriler sun.',
        };
      }
      return {'products': result, 'count': result.length};
    } catch (e) {
      debugPrint('KoalaToolHandler _searchProductsFromEvlumba error: $e');
      return {'products': [], 'error': e.toString()};
    }
  }

  // ═══════════════════════════════════════════════════════
  // PROJE / TASARIM ARA
  // ═══════════════════════════════════════════════════════
  static Future<Map<String, dynamic>> _searchProjects(
    Map<String, dynamic> args,
  ) async {
    try {
      if (!EvlumbaLiveService.isReady) {
        await EvlumbaLiveService.waitForReady();
        if (!EvlumbaLiveService.isReady) {
          return {'projects': [], 'count': 0};
        }
      }
      final roomType = _mapRoomType(args['room_type'] as String?);
      final limit = (args['limit'] as num?)?.toInt().clamp(1, 6) ?? 4;
      final offset = (args['offset'] as num?)?.toInt().clamp(0, 50) ?? 0;

      final projects = await EvlumbaLiveService.getProjects(
        limit: limit,
        offset: offset,
        projectType: roomType,
      );

      final result = projects.where((p) {
        // Test/placeholder başlıkları UI'dan gizle.
        final rawTitle = (p['title'] ?? '').toString().trim();
        if (_isLowQualityProjectTitle(rawTitle)) {
          // Başlık kalitesizse bile eğer `project_type` anlamlıysa
          // görselleri "Oturma Odası" gibi kategori etiketiyle gösterilebilir.
          // Yine de tamamen boş / 1-2 karakter ise at.
          final t = rawTitle;
          if (t.length < 2) return false;
          // test prefix'li başlıklar (abc evi...) tamamen dışlanır.
          final lower = t.toLowerCase();
          for (final pref in ['abc', 'test', 'deneme', 'xxx', 'qwe', 'asd',
              'sample', 'demo', 'lorem', 'aaa', 'zzz']) {
            if (lower.startsWith(pref)) return false;
          }
        }
        return true;
      }).map((p) {
        final images = (p['designer_project_images'] as List?) ?? [];
        final firstImage =
            images.isNotEmpty ? images.first['image_url'] : null;
        final desc = (p['description'] ?? '').toString();
        final rawType = (p['project_type'] ?? '').toString();
        // Kategori etiketi: "Oturma Odası" vb. — TR saklanıyor, ama snake_case
        // gelirse de prettify et.
        final categoryLabel = _prettyCategoryLabel(rawType);
        final rawTitle = (p['title'] ?? '').toString().trim();
        // "X Projesi" tekrarlayan title'ları kategoriye çevir.
        final isGenericTitle = rawTitle.isEmpty ||
            RegExp(r'Projesi\s*$', caseSensitive: false).hasMatch(rawTitle);
        final displayTitle = isGenericTitle && categoryLabel.isNotEmpty
            ? categoryLabel
            : rawTitle;
        // Designer adı — nested profiles join varsa al
        final profile = p['profiles'] as Map<String, dynamic>?;
        final designerName = (profile?['full_name'] ??
                p['designer_name'] ??
                '')
            .toString();
        return {
          'id': p['id'],
          'title': displayTitle,
          'category': categoryLabel,
          'designer_name': designerName,
          'description': desc.length > 150 ? '${desc.substring(0, 150)}...' : desc,
          'room_type': rawType,
          'image_url':
              firstImage ?? p['cover_image_url'] ?? p['cover_url'] ?? '',
          'designer_id': p['designer_id'] ?? '',
        };
      }).toList();

      if (result.isEmpty && offset > 0) {
        return {
          'projects': [],
          'count': 0,
          'message': 'Bu oda tipi için gösterilecek başka proje kalmadı. Kullanıcıya farklı bir oda tipi veya tarz öner.',
        };
      }
      return {'projects': result, 'count': result.length};
    } catch (e) {
      debugPrint('KoalaToolHandler _searchProjects error: $e');
      return {'projects': [], 'error': e.toString()};
    }
  }

  // ═══════════════════════════════════════════════════════
  // TASARIMCI ARA
  // ═══════════════════════════════════════════════════════
  static Future<Map<String, dynamic>> _searchDesigners(
    Map<String, dynamic> args,
  ) async {
    try {
      if (!EvlumbaLiveService.isReady) {
        await EvlumbaLiveService.waitForReady();
        if (!EvlumbaLiveService.isReady) {
          return {'designers': [], 'count': 0, 'message': 'Veritabanı bağlantısı kurulamadı. Lütfen tekrar deneyin.'};
        }
      }
      final city = args['city'] as String?;
      final query = args['query'] as String?;
      final roomType = (args['room_type'] as String?)?.trim();
      var style = (args['style'] as String?)?.trim();
      final limit = (args['limit'] as num?)?.toInt().clamp(1, 5) ?? 3;
      final minProjects = (args['min_projects'] as num?)?.toInt().clamp(0, 10) ?? 2;

      // Style arg boş ve query yoksa → swipe'tan öğrenilen dominant stili kullan.
      // Sadece güçlü sinyal varsa döner (belirsizse null → dayatma yok).
      if ((style == null || style.isEmpty) &&
          (query == null || query.isEmpty)) {
        try {
          final profile = await TasteProfileService.computeProfile();
          final fb = profile.fallbackStyle();
          if (fb != null && fb.isNotEmpty) {
            style = fb;
            debugPrint('KoalaToolHandler: taste fallback style=$fb');
          }
        } catch (_) {}
      }

      List<Map<String, dynamic>> designers = [];

      // 1. Önce profiles tablosundan dene.
      //    query varsa: isim/uzmanlık araması (searchDesigners).
      //    query yoksa: oda/stil önerisi → interior-only + room/style puanlama.
      if (query != null && query.isNotEmpty) {
        designers = await EvlumbaLiveService.searchDesigners(query);
      } else {
        designers = await EvlumbaLiveService.getDesigners(
          limit: limit,
          city: city,
          interiorOnly: true,
          roomType: roomType,
          style: style,
        );
      }

      // 2. Profiles boşsa → projelerden designer keşfet (fallback)
      if (designers.isEmpty) {
        debugPrint('KoalaToolHandler: profiles empty, discovering designers from projects...');
        try {
          final projects = await EvlumbaLiveService.getProjects(limit: 20);
          // designer_id'leri topla (unique)
          final designerIds = <String>{};
          final projectsByDesigner = <String, List<Map<String, dynamic>>>{};
          for (final p in projects) {
            final did = (p['designer_id'] ?? '').toString();
            if (did.isNotEmpty && did != 'null') {
              designerIds.add(did);
              projectsByDesigner.putIfAbsent(did, () => []).add(p);
            }
          }

          // Tüm designer profilleri tek sorguda getir (N+1 → 1).
          // Aday havuzu limit*3 — sonra interior filtresi + ilk N.
          final idList = designerIds.take(limit * 3).toList();
          final profiles = await EvlumbaLiveService.getDesignersByIds(idList);
          final profileMap = <String, Map<String, dynamic>>{};
          for (final p in profiles) {
            profileMap[p['id'].toString()] = p;
          }
          for (final did in idList) {
            if (designers.length >= limit) break;
            final profile = profileMap[did];
            if (profile != null) {
              // Fallback de non-interior'ları atlasın.
              final spec = (profile['specialty'] ?? '').toString().toLowerCase();
              final isNonInterior = [
                'grafik', 'graphic', 'logo', 'brand', 'web', 'ui', 'ux',
                'illüstrasyon', 'illustration', 'motion', 'animasyon', 'video',
              ].any(spec.contains);
              if (isNonInterior) continue;
              designers.add(profile);
            } else {
              final dProjects = projectsByDesigner[did] ?? [];
              if (dProjects.isNotEmpty) {
                designers.add({
                  'id': did,
                  'full_name': 'Tasarımcı',
                  'specialty': 'İç Mimar',
                  'city': '',
                  'avatar_url': '',
                  'business_name': '',
                });
              }
            }
          }
        } catch (e) {
          debugPrint('KoalaToolHandler: project-based designer discovery failed: $e');
        }
      }

      if (designers.isEmpty) {
        return {
          'designers': [],
          'count': 0,
          'message': 'Veritabanında henüz tasarımcı profili bulunamadı. Kullanıcıyı Evlumba Design premium hizmetine yönlendir.',
        };
      }

      // Her tasarımcıya portfolio görselleri ekle. Aday havuzu limit*2 —
      // kalite filtresi (test data ayıkla + min_projects) sonrasında limit'e
      // kırpacağız. Eskiden limit=3'tü; bazı projelerin görseli olmadığı için
      // "Bilgehan: 3 proje → 2 geliyor" bug'ı oluşuyordu. 12'ye çıkardık;
      // UI'da kart max 3 thumb gösterip geri kalanı "+N Tümünü gör" overlay
      // ile profile yönlendiriyor.
      // BATCH portfolio enrichment — N+1 yerine tek sorgu.
      // Sadece ilk limit*2 aday için enrich (lazy).
      final candidates = designers.take(limit * 2).toList();
      final candidateIds = candidates
          .map((d) => (d['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();

      // designer_id → list<project>
      final Map<String, List<Map<String, dynamic>>> projectsByDesigner = {};
      if (candidateIds.isNotEmpty) {
        try {
          final rows = await EvlumbaLiveService.client
              .from('designer_projects')
              .select(
                  'id, designer_id, project_type, title, cover_image_url, designer_project_images(image_url)')
              .eq('is_published', true)
              .inFilter('designer_id', candidateIds)
              .order('created_at', ascending: false);
          for (final r in (rows as List)) {
            final row = r as Map<String, dynamic>;
            final did = (row['designer_id'] ?? '').toString();
            if (did.isEmpty) continue;
            final list = projectsByDesigner.putIfAbsent(did, () => []);
            if (list.length < 12) {
              list.add(row);
            }
          }
        } catch (e) {
          debugPrint('KoalaToolHandler: batch portfolio fetch failed: $e');
        }
      }

      final mappedRoomForScore = _mapRoomType(roomType);

      final enriched = candidates.map((d) {
        final designerId = (d['id'] ?? '').toString();
        final List<String> portfolioImages = [];
        final List<Map<String, dynamic>> portfolioProjects = [];
        int totalProjects = 0;
        int validProjects = 0;
        int roomHits = 0;

        final projects = projectsByDesigner[designerId] ?? const [];
        totalProjects = projects.length;
        for (final p in projects) {
          final rawTitle = (p['title'] ?? '').toString().trim();
          if (_isLowQualityProjectTitle(rawTitle)) continue;
          final images = (p['designer_project_images'] as List?) ?? [];
          final firstImg = images.isNotEmpty
              ? images.first['image_url']?.toString()
              : null;
          String? img;
          if (firstImg != null && firstImg.isNotEmpty) {
            img = firstImg;
          } else {
            final cover = p['cover_image_url']?.toString();
            if (cover != null && cover.isNotEmpty) img = cover;
          }
          if (img != null) {
            validProjects++;
            final pType = (p['project_type'] ?? '').toString();
            if (mappedRoomForScore != null &&
                mappedRoomForScore.isNotEmpty &&
                pType.toLowerCase() == mappedRoomForScore.toLowerCase()) {
              roomHits++;
            }
            portfolioImages.add(img);
            portfolioProjects.add({
              'id': (p['id'] ?? '').toString(),
              'title': rawTitle,
              'project_type': pType,
              'cover_image_url': img,
              'image_url': img,
              'designer_id': designerId,
            });
          }
        }

        // match_score
        int matchScore = 0;
        String? matchReason;
        if (roomType != null && roomType.isNotEmpty && validProjects > 0) {
          final rate = roomHits / validProjects;
          matchScore = (rate * 100).round();
          if (roomHits > 0) {
            matchReason =
                'Son $validProjects projesinin ${roomHits}\'i ${_prettyRoom(roomType)}';
          }
        }

        final item = <String, dynamic>{
          'id': d['id'],
          'name': d['full_name'] ?? '',
          'specialty': d['specialty'] ?? '',
          'city': d['city'] ?? '',
          'avatar_url': d['avatar_url'] ?? '',
          'business_name': d['business_name'] ?? '',
          'total_projects': totalProjects,
          '_valid_projects': validProjects,
          'match_score': matchScore,
          'room_match_count': roomHits,
          'room_match_total': validProjects,
          if (portfolioImages.isNotEmpty) 'portfolio_images': portfolioImages,
          if (portfolioProjects.isNotEmpty) 'portfolio_projects': portfolioProjects,
        };
        if (matchReason != null) item['match_reason'] = matchReason;
        return item;
      }).toList();

      // match_score DESC, valid_projects DESC
      enriched.sort((a, b) {
        final sa = (a['match_score'] as int?) ?? 0;
        final sb = (b['match_score'] as int?) ?? 0;
        if (sb != sa) return sb.compareTo(sa);
        final va = (a['_valid_projects'] as int?) ?? 0;
        final vb = (b['_valid_projects'] as int?) ?? 0;
        return vb.compareTo(va);
      });

      // Progressive relaxation: önce min_projects eşiğinde filtrele,
      // yeterli sonuç yoksa eşiği 1'e düşür.
      List<Map<String, dynamic>> filtered = enriched
          .where((d) => (d['_valid_projects'] as int) >= minProjects)
          .toList();
      if (filtered.length < 2 && minProjects > 1) {
        debugPrint('KoalaToolHandler: relaxing min_projects $minProjects→1');
        filtered = enriched
            .where((d) => (d['_valid_projects'] as int) >= 1)
            .toList();
      }
      // Hâlâ az ise portfolyosuz tasarımcıları da ekle (son çare, yine de listele).
      if (filtered.isEmpty) {
        filtered = List<Map<String, dynamic>>.from(enriched);
      }

      final result = filtered.take(limit).map((d) {
        final copy = Map<String, dynamic>.from(d);
        copy.remove('_valid_projects');
        return copy;
      }).toList();

      return {'designers': result, 'count': result.length};
    } catch (e) {
      debugPrint('KoalaToolHandler _searchDesigners error: $e');
      return {'designers': [], 'error': e.toString()};
    }
  }

  // ═══════════════════════════════════════════════════════
  // ÜRÜN KARŞILAŞTIR
  // ═══════════════════════════════════════════════════════
  static Future<Map<String, dynamic>> _compareProducts(
    Map<String, dynamic> args,
  ) async {
    try {
      final productNames = (args['product_names'] as List?)?.cast<String>() ?? [];
      final roomType = args['room_type'] as String?;

      if (productNames.isEmpty) {
        return {'comparison': [], 'message': 'Karşılaştırılacak ürün belirtilmedi'};
      }

      // Paralel ürün arama (N sequential → 1 parallel batch)
      final results = await Future.wait(
        productNames.take(3).map((name) => _searchProducts({
          'query': name,
          'room_type': roomType,
          'limit': 1,
        })),
      );
      final allProducts = <Map<String, dynamic>>[];
      for (final result in results) {
        final products = (result['products'] as List?) ?? [];
        if (products.isNotEmpty) {
          allProducts.add(Map<String, dynamic>.from(products.first));
        }
      }

      return {
        'comparison': allProducts,
        'count': allProducts.length,
      };
    } catch (e) {
      debugPrint('KoalaToolHandler _compareProducts error: $e');
      return {'comparison': [], 'error': e.toString()};
    }
  }

  /// Test/placeholder proje başlığı mı? DB'de "abc evi", "test", "deneme"
  /// gibi geliştirici test verileri olabiliyor — bunları UI'dan gizle.
  /// Kural: başlık 3 karakterden kısa, veya belirgin test prefix'leri
  /// ("abc", "test", "deneme", "xxx", "qwe", "asd", "sample", "demo") ile
  /// başlıyor, veya tamamı rakam/karmaşa ise düşük kaliteli say.
  static bool _isLowQualityProjectTitle(String title) {
    final t = title.trim();
    if (t.isEmpty) return true;
    if (t.length < 4) return true;
    final lower = t.toLowerCase();
    const testPrefixes = [
      'abc', 'test', 'deneme', 'xxx', 'qwe', 'asd', 'sample', 'demo',
      'lorem', 'aaa', 'bbb', 'ccc', 'ddd', 'eee', 'zzz', 'fff',
    ];
    for (final prefix in testPrefixes) {
      if (lower.startsWith(prefix)) return true;
    }
    // Tamamı rakam/tek harf karışımı — "a1", "12 ab" gibi
    if (RegExp(r'^[\d\s]+$').hasMatch(t)) return true;
    // Harf sayısı 3'ten az (anlamlı kelime yok)
    final letterCount = RegExp(r'[A-Za-zÇĞİıÖŞÜçğıöşü]').allMatches(t).length;
    if (letterCount < 4) return true;
    return false;
  }

  /// Türkçe karakter fold + lowercase + wildcard escape.
  /// Supabase .ilike/.or sorgularında Türkçe normalize için.
  static String _trFold(String s) {
    final buf = StringBuffer();
    for (final codeUnit in s.runes) {
      final ch = String.fromCharCode(codeUnit);
      switch (ch) {
        case 'ş':
        case 'Ş':
          buf.write('s');
          break;
        case 'ı':
          buf.write('i');
          break;
        case 'İ':
          buf.write('i');
          break;
        case 'ğ':
        case 'Ğ':
          buf.write('g');
          break;
        case 'ü':
        case 'Ü':
          buf.write('u');
          break;
        case 'ö':
        case 'Ö':
          buf.write('o');
          break;
        case 'ç':
        case 'Ç':
          buf.write('c');
          break;
        case '%':
          buf.write(r'\%');
          break;
        case '_':
          buf.write(r'\_');
          break;
        default:
          buf.write(ch.toLowerCase());
      }
    }
    return buf.toString();
  }

  /// room_type key → kullanıcıya gösterilecek kısa Türkçe etiket.
  static String _prettyRoom(String key) {
    const map = {
      'salon': 'Oturma',
      'oturma_odasi': 'Oturma',
      'yatak_odasi': 'Yatak',
      'mutfak': 'Mutfak',
      'banyo': 'Banyo',
      'ofis': 'Ofis',
      'ev_ofisi': 'Ev Ofisi',
      'cocuk_odasi': 'Çocuk Odası',
      'antre': 'Antre',
      'balkon': 'Balkon',
      'yemek_odasi': 'Yemek Odası',
      'calisma_odasi': 'Çalışma',
    };
    final k = key.toLowerCase().trim();
    if (map.containsKey(k)) return map[k]!;
    // Fallback: _prettyCategoryLabel TR map'i çok daha geniş.
    return _prettyCategoryLabel(key);
  }

  /// Sorgu bir oda adı mı? Eğer öyleyse product_title aramasına ekleme,
  /// çünkü "Salon" gibi kelimeler ürün başlığında geçmez.
  static bool _isRoomName(String query) {
    const roomNames = {
      'salon', 'oturma odası', 'yatak odası', 'mutfak', 'banyo',
      'çocuk odası', 'ofis', 'çalışma odası', 'balkon', 'teras',
      'antre', 'hol', 'koridor', 'yemek odası', 'misafir odası',
      'bebek odası', 'giyinme odası', 'living room', 'bedroom',
      'kitchen', 'bathroom', 'kids room', 'office',
    };
    return roomNames.contains(query.toLowerCase().trim());
  }
}
