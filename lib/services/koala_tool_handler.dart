import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/config/env.dart';
import 'evlumba_live_service.dart';

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
      final query = (args['query'] as String?) ?? '';
      final roomType = args['room_type'] as String?;
      final maxPrice = args['max_price'] as num?;
      final limit = (args['limit'] as num?)?.toInt().clamp(1, 8) ?? 6;

      // Koala API'den gerçek ürün ara (Google Search Grounding)
      final apiResult = await _searchProductsFromAPI(
        query: query,
        roomType: roomType,
        maxPrice: maxPrice,
        limit: limit,
      );

      if (apiResult != null && (apiResult['products'] as List).isNotEmpty) {
        return apiResult;
      }

      // API başarısız olursa Evlumba DB fallback
      debugPrint('KoalaToolHandler: API returned no products, trying Evlumba DB fallback');
      return _searchProductsFromEvlumba(
        query: query,
        roomType: roomType,
        maxPrice: maxPrice,
        limit: limit,
      );
    } catch (e) {
      debugPrint('KoalaToolHandler _searchProducts error: $e');
      return {'products': [], 'error': e.toString()};
    }
  }

  /// Koala API üzerinden Gemini Google Search Grounding ile gerçek ürün ara
  static Future<Map<String, dynamic>?> _searchProductsFromAPI({
    required String query,
    String? roomType,
    num? maxPrice,
    required int limit,
  }) async {
    try {
      final uri = Uri.parse('${Env.koalaApiUrl}/api/products/search');
      final body = {
        'query': query,
        if (roomType != null && roomType.isNotEmpty) 'room_type': roomType,
        if (maxPrice != null) 'max_price': maxPrice,
        'limit': limit,
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

      // API formatını UI formatına dönüştür (zaten uyumlu ama garanti olsun)
      final result = products.map((p) {
        final item = p as Map<String, dynamic>;
        return {
          'id': item['id'] ?? 'search-${DateTime.now().millisecondsSinceEpoch}',
          'name': item['name'] ?? 'Ürün',
          'price': item['price'] ?? '',
          'image_url': item['image_url'] ?? '',
          'url': item['url'] ?? '',
          'shop_name': item['shop_name'] ?? '',
          'source': item['source'] ?? 'google_search',
          'project_id': '',
        };
      }).toList();

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
  }) async {
    try {
      final mappedRoom = _mapRoomType(roomType);

      var projectQuery = EvlumbaLiveService.client
          .from('designer_projects')
          .select('id')
          .eq('is_published', true);

      if (mappedRoom != null && mappedRoom.isNotEmpty) {
        projectQuery = projectQuery.ilike('project_type', mappedRoom);
      }

      final projects = await projectQuery.limit(50);
      final projectIds =
          (projects as List).map((p) => p['id'] as String).toList();

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
        shopQuery = shopQuery.ilike('product_title', '%$query%');
      }

      final rawProducts = await shopQuery.limit(limit * 3);

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

      final result = products.take(limit).map((p) {
        return {
          'id': p['id'],
          'name': p['product_title'] ?? 'Ürün',
          'price': p['product_price'] ?? '',
          'image_url': p['product_image_url'] ?? '',
          'url': p['product_url'] ?? '',
          'shop_name': p['shop_name'] ?? '',
          'source': 'evlumba',
          'project_id': p['project_id'],
        };
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
      final roomType = _mapRoomType(args['room_type'] as String?);
      final limit = (args['limit'] as num?)?.toInt().clamp(1, 6) ?? 4;
      final offset = (args['offset'] as num?)?.toInt().clamp(0, 50) ?? 0;

      final projects = await EvlumbaLiveService.getProjects(
        limit: limit,
        offset: offset,
        projectType: roomType,
      );

      final result = projects.map((p) {
        final images = (p['designer_project_images'] as List?) ?? [];
        final firstImage =
            images.isNotEmpty ? images.first['image_url'] : null;
        final desc = (p['description'] ?? '').toString();
        return {
          'id': p['id'],
          'title': p['title'] ?? '',
          'description': desc.length > 150 ? '${desc.substring(0, 150)}...' : desc,
          'room_type': p['project_type'] ?? '',
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
      final city = args['city'] as String?;
      final query = args['query'] as String?;
      final limit = (args['limit'] as num?)?.toInt().clamp(1, 5) ?? 3;

      List<Map<String, dynamic>> designers;

      if (query != null && query.isNotEmpty) {
        designers = await EvlumbaLiveService.searchDesigners(query);
      } else {
        designers =
            await EvlumbaLiveService.getDesigners(limit: limit, city: city);
      }

      // Her tasarımcıya 3 portfolio görseli ekle
      final result = await Future.wait(
        designers.take(limit).map((d) async {
          final designerId = (d['id'] ?? '').toString();
          List<String> portfolioImages = [];
          if (designerId.isNotEmpty) {
            try {
              final projects = await EvlumbaLiveService.getProjects(
                limit: 3,
                designerId: designerId,
              );
              for (final p in projects) {
                final images = (p['designer_project_images'] as List?) ?? [];
                if (images.isNotEmpty) {
                  portfolioImages.add(images.first['image_url'] as String);
                } else if (p['cover_image_url'] != null) {
                  portfolioImages.add(p['cover_image_url'] as String);
                }
              }
            } catch (_) {}
          }
          return {
            'id': d['id'],
            'name': d['full_name'] ?? '',
            'specialty': d['specialty'] ?? '',
            'city': d['city'] ?? '',
            'avatar_url': d['avatar_url'] ?? '',
            'business_name': d['business_name'] ?? '',
            if (portfolioImages.isNotEmpty) 'portfolio_images': portfolioImages,
          };
        }),
      );

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

      final allProducts = <Map<String, dynamic>>[];
      for (final name in productNames.take(3)) {
        final result = await _searchProducts({
          'query': name,
          'room_type': roomType,
          'limit': 1,
        });
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
