import 'package:supabase_flutter/supabase_flutter.dart';

/// Kullanıcının tasarladığı mekanın stiline ve şehrine göre en uygun
/// profesyonelleri getirir. Supabase RPC `match_pros_by_style` — text
/// array overlap + city + rating sıralaması.
///
/// MVP: CLIP embedding YOK. Sprint 3.5'te portfolio embed + vector sim
/// ile upgrade edilecek (şema zaten hazır — `pros.portfolio_embed`).
///
/// Kullanım:
/// ```dart
/// final matches = await ProMatchService.match(
///   styles: ['Modern','Minimalist'],
///   city: 'İstanbul',
/// );
/// ```
class ProMatchService {
  ProMatchService._();

  static Future<List<ProMatch>> match({
    required List<String> styles,
    String? city,
    int limit = 10,
  }) async {
    if (styles.isEmpty) return const [];

    final supabase = Supabase.instance.client;

    try {
      final res = await supabase.rpc(
        'match_pros_by_style',
        params: {
          'p_styles': styles,
          'p_city': city,
          'p_limit': limit,
        },
      );

      if (res is! List) return const [];
      return res
          .whereType<Map<String, dynamic>>()
          .map(ProMatch.fromJson)
          .toList();
    } catch (e) {
      // RLS/network/şema sorunu olursa boş dön — UI empty state gösterir.
      return const [];
    }
  }
}

/// Pro match DTO — RPC response row'uyla birebir.
class ProMatch {
  final String id;
  final String name;
  final String? city;
  final String? bio;
  final double rating;
  final List<String> topStyles;
  final double? avgPricePerSqm;
  final String? contactWhatsapp;
  final String? contactEmail;
  final String? profileImageUrl;
  final int? yearsExperience;
  final int overlapCount;

  const ProMatch({
    required this.id,
    required this.name,
    required this.city,
    required this.bio,
    required this.rating,
    required this.topStyles,
    required this.avgPricePerSqm,
    required this.contactWhatsapp,
    required this.contactEmail,
    required this.profileImageUrl,
    required this.yearsExperience,
    required this.overlapCount,
  });

  factory ProMatch.fromJson(Map<String, dynamic> j) => ProMatch(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? 'İsimsiz',
        city: j['city']?.toString(),
        bio: j['bio']?.toString(),
        rating: (j['rating'] as num?)?.toDouble() ?? 0,
        topStyles: (j['top_styles'] as List?)?.cast<String>() ?? const [],
        avgPricePerSqm: (j['avg_price_per_sqm'] as num?)?.toDouble(),
        contactWhatsapp: j['contact_whatsapp']?.toString(),
        contactEmail: j['contact_email']?.toString(),
        profileImageUrl: j['profile_image_url']?.toString(),
        yearsExperience: (j['years_experience'] as num?)?.toInt(),
        overlapCount: (j['overlap_count'] as num?)?.toInt() ?? 0,
      );

  /// Gösterilecek fiyat bandı (₺/m²) — null ise "Fiyat için mesaj".
  String priceLabel() {
    if (avgPricePerSqm == null) return 'Fiyat için mesaj';
    final p = avgPricePerSqm!.round();
    return '~₺$p/m²';
  }

  /// WhatsApp URL — ön doldurulmuş mesaj ile.
  Uri? whatsappUri({String? prefilledMessage}) {
    if (contactWhatsapp == null || contactWhatsapp!.isEmpty) return null;
    final msg = prefilledMessage ?? 'Merhaba, Koala üzerinden projemi sizinle görüşmek istiyorum.';
    return Uri.parse('https://wa.me/${contactWhatsapp!}?text=${Uri.encodeComponent(msg)}');
  }

  /// Portföy fetch — ayrı RPC/query. İlk versiyonda profile screen'de kullanılır.
  static Future<List<ProPortfolioItem>> portfolioFor(String proId) async {
    try {
      final res = await Supabase.instance.client
          .from('pro_portfolio')
          .select('id, image_url, style_label')
          .eq('pro_id', proId)
          .limit(20);
      return (res as List)
          .whereType<Map<String, dynamic>>()
          .map(ProPortfolioItem.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

class ProPortfolioItem {
  final String id;
  final String imageUrl;
  final String? styleLabel;

  const ProPortfolioItem({
    required this.id,
    required this.imageUrl,
    required this.styleLabel,
  });

  factory ProPortfolioItem.fromJson(Map<String, dynamic> j) => ProPortfolioItem(
        id: j['id']?.toString() ?? '',
        imageUrl: j['image_url']?.toString() ?? '',
        styleLabel: j['style_label']?.toString(),
      );
}
