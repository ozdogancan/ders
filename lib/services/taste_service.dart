import 'taste_profile_service.dart';

/// Üst-seviye zevk API'si — karar mekan akışında kullanılır.
///
/// Sorulan soru: "Bu kullanıcı şu oda tipi için restyle'a hazır mı, yoksa
/// önce swipe'tan mı geçmeli?"
///
/// MVP kararı:
/// - TasteProfileService local, hızlı, ML yok → onu kullan.
/// - Daha sonra Supabase RPC `classify_user_taste` + cross-device sync'e
///   kolayca upgrade edilebilir (aynı kontrat).
///
/// Güven eşikleri (room-spesifik değil — MVP):
/// - Toplam beğeni ≥ 8 VE dominant stil payı ≥ %45  → kullan
/// - Toplam beğeni ≥ 15 VE strong flag                → direkt öner
/// - Aksi halde                                       → önce swipe
class TasteService {
  TasteService._();

  /// Restyle için en iyi stili döner. Null = belirsiz, kullanıcı swipe'a
  /// yönlendirilmeli.
  static Future<TasteDecision> decideForRoom(String roomKey) async {
    final profile = await TasteProfileService.computeProfile();

    if (!profile.isActive) {
      return TasteDecision(
        recommendation: TasteRecommendation.swipe,
        confidence: 0.0,
        style: null,
        profile: profile,
        reason: 'yetersiz_ornek',
      );
    }

    final topStyle = profile.topStyles.first;

    // Güçlü sinyal — direkt kullan.
    if (profile.isStrong) {
      return TasteDecision(
        recommendation: TasteRecommendation.use,
        confidence: topStyle.share,
        style: topStyle.style,
        profile: profile,
        reason: 'strong',
      );
    }

    // Orta güven — kullanabilir ama onay isteyebiliriz.
    if (profile.sampleCount >= 8 && topStyle.share >= 0.45) {
      return TasteDecision(
        recommendation: TasteRecommendation.use,
        confidence: topStyle.share,
        style: topStyle.style,
        profile: profile,
        reason: 'moderate',
      );
    }

    // Keşif aşaması — önce swipe.
    return TasteDecision(
      recommendation: TasteRecommendation.swipe,
      confidence: topStyle.share,
      style: topStyle.style, // referans, UI'a dominant'ı gösterebilir
      profile: profile,
      reason: profile.isExploring ? 'exploring' : 'low_confidence',
    );
  }

  /// Zevk profilini kullanıcıya göstermek için özet ("senin tarzın bunlar").
  /// Moodboard reveal ekranı kullanır.
  static Future<MoodboardSummary> summaryForMoodboard() async {
    final profile = await TasteProfileService.computeProfile();
    if (!profile.isActive || profile.topStyles.isEmpty) {
      return const MoodboardSummary(
        hasData: false,
        topStyles: [],
        sampleCount: 0,
        headline: 'Biraz daha keşfedelim',
        subline: 'Birkaç tarz daha beğen, ona göre senin için düşünürüz.',
      );
    }
    final top = profile.topStyles.take(3).toList();
    final dominant = top.first;
    final pct = (dominant.share * 100).round();
    return MoodboardSummary(
      hasData: true,
      topStyles: top,
      sampleCount: profile.sampleCount,
      headline: _headline(dominant.style, pct, profile.isExploring),
      subline: _subline(profile.isExploring, profile.sampleCount),
    );
  }

  static String _headline(String style, int pct, bool exploring) {
    final pretty = _prettyStyle(style);
    if (exploring) {
      return '$pretty\'ye yakınsın';
    }
    return 'Senin tarzın: $pretty';
  }

  static String _subline(bool exploring, int sample) {
    if (exploring) {
      return 'Son $sample seçimden çıkardık — net olmak için birkaç tane daha beğenebilirsin.';
    }
    return 'Son $sample seçiminden öğrendik. İstersen şimdi mekanını bu tarzda yeniden tasarlayalım.';
  }

  static String _prettyStyle(String key) {
    const tr = {
      'modern': 'Modern',
      'minimalist': 'Minimalist',
      'iskandinav': 'Skandinav',
      'klasik': 'Klasik',
      'endüstriyel': 'Endüstriyel',
      'boho': 'Bohem',
      'rustik': 'Rustik',
      'japandi': 'Japandi',
      'mid_century': 'Mid-Century',
      'mediterranean': 'Akdeniz',
    };
    return tr[key] ?? (key.isEmpty ? key : key[0].toUpperCase() + key.substring(1));
  }

  /// `taste_profile` key'ini Koala'nın diğer dosyalarının beklediği
  /// pretty style adına çevirir — StyleStage'in `_matchTheme` mantığıyla
  /// uyumlu (ör. `iskandinav` → `Scandinavian` ThemeOption).
  static String? tasteKeyToThemeValue(String key) {
    const map = {
      'modern': 'Modern',
      'minimalist': 'Minimalist',
      'iskandinav': 'Scandinavian',
      'klasik': 'Modern', // Klasik ThemeOption yok, en yakın
      'endüstriyel': 'Industrial',
      'boho': 'Bohemian',
      'rustik': 'Industrial', // en yakın; ileride ayrı Rustik theme
      'japandi': 'Japandi',
      'mid_century': 'Modern',
      'mediterranean': 'Bohemian',
    };
    return map[key];
  }
}

enum TasteRecommendation { use, swipe }

class TasteDecision {
  final TasteRecommendation recommendation;
  final double confidence; // 0-1
  final String? style; // taste key (e.g. 'minimalist')
  final TasteProfile profile;
  final String reason;

  const TasteDecision({
    required this.recommendation,
    required this.confidence,
    required this.style,
    required this.profile,
    required this.reason,
  });

  bool get isConfident =>
      recommendation == TasteRecommendation.use && confidence >= 0.45;

  /// Prefetch tetikleme eşiği — %55+ ve "use" → arkadan restyle başlat.
  bool get shouldPrefetch =>
      recommendation == TasteRecommendation.use && confidence >= 0.55;
}

class MoodboardSummary {
  final bool hasData;
  final List<StyleScore> topStyles;
  final int sampleCount;
  final String headline;
  final String subline;

  const MoodboardSummary({
    required this.hasData,
    required this.topStyles,
    required this.sampleCount,
    required this.headline,
    required this.subline,
  });
}
