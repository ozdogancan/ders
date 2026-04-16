/// Single card returned by `get_swipe_feed` RPC.
///
/// Only fields actually exposed to the client are modeled here —
/// `embedding` and enrichment internals stay on the server.
class KoalaCard {
  const KoalaCard({
    required this.id,
    required this.originalUrl,
    required this.ring,
    required this.source,
    this.cdnUrl,
    this.thumbnailUrl,
    this.title,
    this.description,
    this.roomType,
    this.style,
    this.mood,
    this.budgetTier,
    this.dominantColors = const [],
    this.imageWidth,
    this.imageHeight,
    this.designerId,
    this.designerName,
    this.designerCity,
    this.designerRating,
    this.designerAvatarUrl,
    this.styleTags,
    this.similarCardIds,
  });

  /// Primary key in `koala_cards`.
  final String id;

  /// Source image URL (Evlumba CDN today). May be huge base64 for legacy rows
  /// — the enrichment pipeline replaces those with stable URLs.
  final String originalUrl;

  /// 3-ring feed algorithm bucket: `exploit` | `explore` | `fresh` | `rare` | `fallback`.
  /// The UI can tune prefetch/telemetry based on this.
  final String ring;

  /// Card source system (e.g. `evlumba`).
  final String source;

  final String? cdnUrl;
  final String? thumbnailUrl;
  final String? title;
  final String? description;
  final String? roomType;
  final String? style;
  final String? mood;
  final String? budgetTier;

  /// 2–4 hex codes extracted by Gemini tagging (e.g. `#E8D5C4`).
  final List<String> dominantColors;

  final int? imageWidth;
  final int? imageHeight;

  final String? designerId;
  final String? designerName;
  final String? designerCity;
  final num? designerRating;

  /// Avatar URL for the designer — rendered in the peek info panel.
  final String? designerAvatarUrl;

  /// Style taxonomy tags (e.g. `['minimalist', 'nordic']`).
  /// Up to 3 are shown in the peek info panel as filter chips.
  final List<String>? styleTags;

  /// IDs of visually similar cards — used to render a mini-card strip in
  /// the peek info panel. Only IDs are stored here; full card data is not
  /// prefetched. Up to 3 are displayed.
  final List<String>? similarCardIds;

  /// Best URL to render now. Prefers CDN, falls back to original.
  String get displayUrl => cdnUrl ?? originalUrl;

  /// Smallest URL for prefetch / thumbnail grids.
  String get smallUrl => thumbnailUrl ?? cdnUrl ?? originalUrl;

  factory KoalaCard.fromJson(Map<String, dynamic> json) {
    final rawColors = json['dominant_colors'];
    final colors = rawColors is List
        ? rawColors.whereType<String>().toList(growable: false)
        : const <String>[];

    return KoalaCard(
      id: json['id'] as String,
      originalUrl: (json['original_url'] as String?) ?? '',
      ring: (json['ring'] as String?) ?? 'fallback',
      source: (json['source'] as String?) ?? 'unknown',
      cdnUrl: json['cdn_url'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      title: json['title'] as String?,
      description: json['description'] as String?,
      roomType: json['room_type'] as String?,
      style: json['style'] as String?,
      mood: json['mood'] as String?,
      budgetTier: json['budget_tier'] as String?,
      dominantColors: colors,
      imageWidth: (json['image_width'] as num?)?.toInt(),
      imageHeight: (json['image_height'] as num?)?.toInt(),
      designerId: json['designer_id'] as String?,
      designerName: json['designer_name'] as String?,
      designerCity: json['designer_city'] as String?,
      designerRating: json['designer_rating'] as num?,
      designerAvatarUrl: json['designer_avatar_url'] as String?,
      styleTags: (json['style_tags'] as List<dynamic>?)?.cast<String>(),
      similarCardIds:
          (json['similar_card_ids'] as List<dynamic>?)?.cast<String>(),
    );
  }
}

/// Directions supported by the swipe engine.
///
/// Backend contract:
///   right       → like
///   left        → dislike
///   up          → super_like
///   down        → not_now (also drives hidden_until)
enum SwipeDirection {
  right,
  left,
  up,
  down;

  String get wire => name;

  static SwipeDirection? tryParse(String? raw) {
    switch (raw) {
      case 'right':
        return SwipeDirection.right;
      case 'left':
        return SwipeDirection.left;
      case 'up':
        return SwipeDirection.up;
      case 'down':
        return SwipeDirection.down;
      default:
        return null;
    }
  }
}
