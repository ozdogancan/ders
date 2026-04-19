import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Swipe sinyali — Tarzını Keşfet live deck'te beğeni (right) veya geç (left).
///
/// Tasarım prensipleri:
/// - SharedPreferences only, ağ çağrısı YOK; swipe animasyonunu hiç bloklamaz.
/// - Ring buffer: son 50 beğeni + son 30 geçiş (cap'li). Storage bounded.
/// - Zamansal decay: son 14 gün=1.0, 14-30=0.6, 30+=0.3.
/// - Keyword-based extraction (ML yok) — tek regex-like geçiş, < 1 ms.
/// - Minimum örneklem 5 beğeni — altında profile inactive.
/// - Contradiction-aware: dominant stil payı < %35 ise "hâlâ keşfediyor"
///   olarak işaretler, AI'a tek stil dayatmaz.
/// - Pass (geçiş) sinyali negatif ağırlık — 5+ geçilen stil asla önerilmez.
class TasteProfileService {
  TasteProfileService._();

  static const _kLikesKey = 'taste_likes_v1';
  static const _kPassesKey = 'taste_passes_v1';
  static const _kMaxLikes = 50;
  static const _kMaxPasses = 30;
  static const _kMinSamplesForActive = 5;

  /// ═══════════════════════════════════════════════════════════════════
  /// STYLE KEYWORD SET — düşük yanlış-pozitif, Türkçe + İngilizce.
  /// Eklerken dikkat: stop-word gibi çok genel terimler eklemeyin,
  /// "sade" gibi kelimeler hem modern hem minimal hem iskandinav'a çeker.
  /// ═══════════════════════════════════════════════════════════════════
  static const Map<String, List<String>> _styleKeywords = {
    'modern': ['modern', 'çağdaş', 'cagdas', 'contemporary', 'sade çizgi'],
    'minimalist': ['minimalist', 'minimal', 'az ile çok', 'sade'],
    'iskandinav': ['iskandinav', 'scandinavian', 'nordic', 'nordik', 'hygge'],
    'klasik': ['klasik', 'classic', 'geleneksel', 'art deco', 'art-deco', 'barok', 'rokoko', 'lüks', 'luxury'],
    'endüstriyel': ['endüstriyel', 'endustriyel', 'industrial', 'loft'],
    'boho': ['boho', 'bohem', 'bohemian', 'eklektik', 'eclectic', 'etnik', 'ethnic'],
    'rustik': ['rustik', 'rustic', 'kır evi', 'country', 'farmhouse'],
    'japandi': ['japandi', 'japon', 'wabi'],
    'mid_century': ['mid-century', 'mid century', 'retro', '60s', '70s'],
    'mediterranean': ['akdeniz', 'mediterranean'],
  };

  /// Oda tipi kanonikleştirme — project_type değerlerini tekil key'e indirger.
  static const Map<String, List<String>> _roomKeywords = {
    'salon': ['salon', 'living', 'oturma odası', 'oturma odasi', 'living room'],
    'yatak_odasi': ['yatak', 'bedroom'],
    'mutfak': ['mutfak', 'kitchen'],
    'banyo': ['banyo', 'bathroom'],
    'ofis': ['ofis', 'office', 'çalışma odası', 'calisma odasi'],
    'cocuk_odasi': ['çocuk', 'cocuk', 'kids', 'child'],
    'yemek_odasi': ['yemek odası', 'yemek odasi', 'dining'],
    'giris': ['giriş', 'giris', 'hol', 'hall', 'entry', 'antre'],
  };

  /// Bir kart için style key'leri çıkar — birden fazla eşleşebilir.
  /// Performans: tek pass, toLowerCase + contains; ~0.3 ms.
  static List<String> _extractStyles(Map<String, dynamic> card) {
    final parts = <String>[
      (card['title'] ?? '').toString(),
      (card['description'] ?? '').toString(),
      (card['tags'] ?? '').toString(),
      (card['style'] ?? '').toString(),
    ];
    final hay = parts.join(' ').toLowerCase();
    if (hay.trim().isEmpty) return const [];
    final hits = <String>[];
    for (final entry in _styleKeywords.entries) {
      for (final kw in entry.value) {
        if (hay.contains(kw)) {
          hits.add(entry.key);
          break;
        }
      }
    }
    return hits;
  }

  /// Proje tipinden ya da metinden oda kategorisi çıkar.
  static String? _extractRoom(Map<String, dynamic> card) {
    final pt = (card['project_type'] ?? '').toString().toLowerCase();
    if (pt.isNotEmpty) {
      for (final entry in _roomKeywords.entries) {
        for (final kw in entry.value) {
          if (pt.contains(kw)) return entry.key;
        }
      }
    }
    final title = (card['title'] ?? '').toString().toLowerCase();
    for (final entry in _roomKeywords.entries) {
      for (final kw in entry.value) {
        if (title.contains(kw)) return entry.key;
      }
    }
    return null;
  }

  /// ═══════════════════════════════════════════════════════════════════
  /// YAZMA API'si — swipe handler'dan `unawaited` ile çağrılır.
  /// ═══════════════════════════════════════════════════════════════════

  static Future<void> recordLike(Map<String, dynamic> card) =>
      _record(card, _kLikesKey, _kMaxLikes);

  static Future<void> recordPass(Map<String, dynamic> card) =>
      _record(card, _kPassesKey, _kMaxPasses);

  static Future<void> _record(
    Map<String, dynamic> card,
    String key,
    int cap,
  ) async {
    try {
      final styles = _extractStyles(card);
      if (styles.isEmpty) return; // kategori çıkarılamadıysa kaydetme
      final room = _extractRoom(card);
      final entry = <String, dynamic>{
        't': DateTime.now().millisecondsSinceEpoch,
        's': styles,
        if (room != null) 'r': room,
      };
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(key) ?? <String>[];
      list.add(jsonEncode(entry));
      // Ring buffer: cap aşıldıysa en eskiden at.
      while (list.length > cap) {
        list.removeAt(0);
      }
      await prefs.setStringList(key, list);
    } catch (e) {
      debugPrint('TasteProfileService._record error: $e');
    }
  }

  /// ═══════════════════════════════════════════════════════════════════
  /// OKUMA API'si — prompt inject ve tool handler fallback'i için.
  /// ═══════════════════════════════════════════════════════════════════

  /// Agregasyon: decay'li stil ve oda skorları + dominant + güven.
  /// Minimum örneklem sağlanmazsa `isActive=false` döner.
  static Future<TasteProfile> computeProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final likesRaw = prefs.getStringList(_kLikesKey) ?? const [];
      final passesRaw = prefs.getStringList(_kPassesKey) ?? const [];
      if (likesRaw.length < _kMinSamplesForActive) {
        return TasteProfile.inactive(sampleCount: likesRaw.length);
      }

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final styleScores = <String, double>{};
      final roomScores = <String, double>{};
      double totalWeight = 0;

      for (final raw in likesRaw) {
        final e = _safeDecode(raw);
        if (e == null) continue;
        final t = (e['t'] as num?)?.toInt() ?? nowMs;
        final ageDays = (nowMs - t) / (1000 * 60 * 60 * 24);
        final w = _decayWeight(ageDays);
        totalWeight += w;
        final styles = (e['s'] as List?)?.cast<String>() ?? const [];
        // Kartta birden fazla stil çıktıysa ağırlığı paylaştır.
        final share = styles.isEmpty ? 0.0 : w / styles.length;
        for (final s in styles) {
          styleScores[s] = (styleScores[s] ?? 0) + share;
        }
        final r = e['r'] as String?;
        if (r != null && r.isNotEmpty) {
          roomScores[r] = (roomScores[r] ?? 0) + w;
        }
      }

      // Pass'lerden negatif ağırlık — son 5+ kez geçilen stil blocklist'e.
      final passCounts = <String, int>{};
      for (final raw in passesRaw) {
        final e = _safeDecode(raw);
        if (e == null) continue;
        final styles = (e['s'] as List?)?.cast<String>() ?? const [];
        for (final s in styles) {
          passCounts[s] = (passCounts[s] ?? 0) + 1;
        }
      }
      final blocklist = passCounts.entries
          .where((e) => e.value >= 5)
          .map((e) => e.key)
          .toSet();
      for (final b in blocklist) {
        styleScores.remove(b);
      }

      if (styleScores.isEmpty || totalWeight <= 0) {
        return TasteProfile.inactive(sampleCount: likesRaw.length);
      }

      // Normalize payları.
      final totalStyleScore = styleScores.values.fold<double>(0, (a, b) => a + b);
      final stylePct = <String, double>{};
      for (final e in styleScores.entries) {
        stylePct[e.key] = e.value / totalStyleScore;
      }

      // Sırala.
      final sortedStyles = stylePct.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final sortedRooms = roomScores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final dominantPct = sortedStyles.first.value;
      final isExploring = dominantPct < 0.35;
      final isStrong = dominantPct >= 0.50 && likesRaw.length >= 15;

      return TasteProfile(
        isActive: true,
        sampleCount: likesRaw.length,
        topStyles: sortedStyles
            .take(3)
            .map((e) => StyleScore(style: e.key, share: e.value))
            .toList(),
        topRooms: sortedRooms.take(2).map((e) => e.key).toList(),
        blockedStyles: blocklist,
        isExploring: isExploring,
        isStrong: isStrong,
      );
    } catch (e) {
      debugPrint('TasteProfileService.computeProfile error: $e');
      return TasteProfile.inactive(sampleCount: 0);
    }
  }

  /// 0-14 gün = 1.0, 14-30 = 0.6, 30+ = 0.3. Yaş < 0 ise 1.0.
  static double _decayWeight(double ageDays) {
    if (ageDays < 0) return 1.0;
    if (ageDays <= 14) return 1.0;
    if (ageDays <= 30) return 0.6;
    return 0.3;
  }

  static Map<String, dynamic>? _safeDecode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  /// Test/debug: tüm profili sıfırla.
  static Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kLikesKey);
      await prefs.remove(_kPassesKey);
    } catch (_) {}
  }
}

/// Aggregated taste profile snapshot. Immutable.
class TasteProfile {
  final bool isActive;
  final int sampleCount;
  final List<StyleScore> topStyles; // sorted desc
  final List<String> topRooms;
  final Set<String> blockedStyles;
  final bool isExploring; // dominant < %35
  final bool isStrong;    // dominant >= %50 && sample >= 15

  const TasteProfile({
    required this.isActive,
    required this.sampleCount,
    required this.topStyles,
    required this.topRooms,
    required this.blockedStyles,
    required this.isExploring,
    required this.isStrong,
  });

  factory TasteProfile.inactive({required int sampleCount}) => TasteProfile(
        isActive: false,
        sampleCount: sampleCount,
        topStyles: const [],
        topRooms: const [],
        blockedStyles: const {},
        isExploring: false,
        isStrong: false,
      );

  /// AI prompt'a enjekte edilecek, Türkçe tek paragraf.
  /// Inactive ise boş string döner → prompt hiç değişmez.
  String toPromptHint() {
    if (!isActive || topStyles.isEmpty) return '';
    final buf = StringBuffer();
    final top = topStyles.take(3).toList();
    final parts = top.map((s) {
      final pct = (s.share * 100).round();
      return '${_pretty(s.style)} (%$pct)';
    }).join(', ');
    if (isExploring) {
      buf.write(
        'Kullanıcının son $sampleCount tasarım beğenisinden çıkarılan '
        'karışık bir tercih profili var: $parts. Henüz baskın bir tarz '
        'oturmadı — keşfetme aşamasında. Tek bir stili dayatma, çeşitliliği koru. ',
      );
    } else if (isStrong) {
      final dominant = _pretty(top.first.style);
      buf.write(
        'Kullanıcının belirgin tercihi: $dominant. Diğer görünümler: $parts. '
        'Önerilerinde bu tarza ağırlık ver. ',
      );
    } else {
      buf.write('Kullanıcının son beğenilerinden çıkan tercihler: $parts. ');
    }
    if (blockedStyles.isNotEmpty) {
      final blocked = blockedStyles.map(_pretty).join(', ');
      buf.write('Sık geçtiği stiller (zorlama): $blocked. ');
    }
    if (topRooms.isNotEmpty) {
      buf.write('İlgilendiği odalar: ${topRooms.map(_pretty).join(', ')}.');
    }
    return buf.toString().trim();
  }

  /// search_designers tool çağrısında style arg'i boşsa fallback.
  /// Sadece güçlü sinyal varsa döner — belirsizse null.
  String? fallbackStyle() {
    if (!isActive || topStyles.isEmpty || isExploring) return null;
    return topStyles.first.style;
  }

  /// Sadece debug/insights için.
  String debugSummary() {
    if (!isActive) return 'inactive ($sampleCount/${TasteProfileService._kMinSamplesForActive})';
    return 'active: ${topStyles.map((s) => "${s.style} ${(s.share * 100).round()}%").join(", ")} '
        'rooms=[${topRooms.join(",")}] '
        'blocked=[${blockedStyles.join(",")}] '
        'exploring=$isExploring strong=$isStrong';
  }

  static String _pretty(String key) {
    switch (key) {
      case 'yatak_odasi':
        return 'yatak odası';
      case 'cocuk_odasi':
        return 'çocuk odası';
      case 'yemek_odasi':
        return 'yemek odası';
      case 'mid_century':
        return 'mid-century';
      case 'endüstriyel':
        return 'endüstriyel';
      default:
        return key;
    }
  }
}

class StyleScore {
  final String style;
  final double share; // 0.0 - 1.0
  const StyleScore({required this.style, required this.share});
}

