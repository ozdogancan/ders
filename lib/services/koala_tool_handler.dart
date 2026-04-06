import 'package:flutter/material.dart';
import 'evlumba_live_service.dart';

/// Gemini Function Calling handler.
/// AI'dan gelen tool çağrılarını alıp evlumba DB'den gerçek veri döndürür.
class KoalaToolHandler {
  const KoalaToolHandler._();

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
  // ÜRÜN ARA — designer_project_shop_links tablosundan
  // Evlumba'da ayrı products tablosu yok, ürünler proje bazlı
  // ═══════════════════════════════════════════════════════
  static Future<Map<String, dynamic>> _searchProducts(
    Map<String, dynamic> args,
  ) async {
    try {
      final query = (args['query'] as String?) ?? '';
      final roomType = args['room_type'] as String?;
      final maxPrice = args['max_price'] as num?;
      final limit = (args['limit'] as num?)?.toInt().clamp(1, 8) ?? 6;

      // 1) Önce projeleri filtrele (room_type varsa)
      var projectQuery = EvlumbaLiveService.client
          .from('designer_projects')
          .select('id')
          .eq('is_published', true);

      if (roomType != null && roomType.isNotEmpty) {
        projectQuery = projectQuery.eq('project_type', roomType);
      }

      final projects = await projectQuery.limit(50);
      final projectIds =
          (projects as List).map((p) => p['id'] as String).toList();

      if (projectIds.isEmpty) {
        return {
          'products': [],
          'message': 'Bu alan için ürün kataloğu henüz hazırlanıyor. Kullanıcıya ürün önerisi yerine tasarım ipuçları veya tasarımcı önerisi sun.',
        };
      }

      // 2) Bu projelerdeki ürünleri ara
      var shopQuery = EvlumbaLiveService.client
          .from('designer_project_shop_links')
          .select(
            'id, project_id, product_title, product_price, product_image_url, product_url, shop_name',
          )
          .inFilter('project_id', projectIds);

      // Ürün adında arama — ama oda adı (salon, yatak odası vb.) ise filtre yapma,
      // çünkü room_type zaten projeleri filtreledi
      if (query.isNotEmpty && !_isRoomName(query)) {
        shopQuery = shopQuery.ilike('product_title', '%$query%');
      }

      final rawProducts =
          await shopQuery.limit(limit * 3); // fazla çek, sonra filtrele

      // 3) Fiyat filtresi (product_price string olabilir, parse et)
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

      // 4) Limitle ve döndür
      final result = products.take(limit).map((p) {
        return {
          'id': p['id'],
          'name': p['product_title'] ?? 'Ürün',
          'price': p['product_price'] ?? '',
          'image_url': p['product_image_url'] ?? '',
          'url': p['product_url'] ?? '',
          'shop_name': p['shop_name'] ?? '',
          'project_id': p['project_id'],
        };
      }).toList();

      if (result.isEmpty) {
        return {
          'products': [],
          'count': 0,
          'message': 'Ürün kataloğu henüz hazırlanıyor. Kullanıcıya ürün önerisi yerine tasarım ipuçları, renk önerileri veya uzman önerisi sun.',
        };
      }
      return {'products': result, 'count': result.length};
    } catch (e) {
      debugPrint('KoalaToolHandler _searchProducts error: $e');
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
      final roomType = args['room_type'] as String?;
      final limit = (args['limit'] as num?)?.toInt().clamp(1, 6) ?? 4;

      final projects = await EvlumbaLiveService.getProjects(
        limit: limit,
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
