import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;
import 'package:http/http.dart' as http;

/// Moondream tarafından üretilen renk — "cream (#F5F1EA)" gibi stringlerden
/// parse edilir.
class MekanColor {
  final String name;
  final Color color;
  final String hex;
  const MekanColor({required this.name, required this.color, required this.hex});
}

/// Backend'den gelen kalite sorunları — Türkçe öneri için map'leme yapılır.
enum QualityIssue {
  blurry,
  tooDark,
  tooFar,
  partialView,
  clutteredWithPeople,
  lowResolution,
  unknown,
}

QualityIssue _parseIssue(String raw) {
  switch (raw.toLowerCase().trim()) {
    case 'blurry': return QualityIssue.blurry;
    case 'too_dark': return QualityIssue.tooDark;
    case 'too_far': return QualityIssue.tooFar;
    case 'partial_view': return QualityIssue.partialView;
    case 'cluttered_with_people': return QualityIssue.clutteredWithPeople;
    case 'low_resolution': return QualityIssue.lowResolution;
    default: return QualityIssue.unknown;
  }
}

/// Kalite bandı — qualityScore + issues kombinasyonu UI rotasını belirler.
/// good   → sessizce ilerle (sıcak yol)
/// soft   → bottom sheet ile öner ama "yine de devam et" sun (kullanıcı seçer)
/// reject → şu an kullanılmıyor (is_room=false zaten ayrı yolda) — gelecekte
///           çok agresif filtrelemek istersek hazır.
enum QualityBand { good, soft, reject }

class AnalyzeResult {
  final bool isRoom;      // Gemini is_room — doğrudan model cevabı
  final String roomType;  // ör. "living_room", "bedroom", "other"
  final String style;     // ör. "minimalist"
  final List<MekanColor> colors;
  final String caption;   // kısa sahne açıklaması
  final String mood;      // ör. "calm, warm"
  final double qualityScore; // 0-1, restyle için kullanılabilirlik
  final List<QualityIssue> issues;

  const AnalyzeResult({
    required this.isRoom,
    required this.roomType,
    required this.style,
    required this.colors,
    required this.caption,
    required this.mood,
    this.qualityScore = 1.0,
    this.issues = const [],
  });

  /// Model is_room=false dediyse kesin mekan değil.
  /// Heuristik: ek güvence için caption/roomType kontrolü.
  bool get isNotMekan {
    if (!isRoom) return true;
    final rt = roomType.toLowerCase();
    if (rt.contains('other') || rt.isEmpty || rt == 'unknown') return true;
    return false;
  }

  /// Kalite bandı.
  /// - issues boş + score>=0.7  → good
  /// - aksi halde                → soft (kullanıcıya öner ama bloklamadan)
  /// reject şimdilik kullanılmıyor — soft band kullanıcıya kontrol bırakıyor.
  QualityBand get qualityBand {
    if (issues.isEmpty && qualityScore >= 0.7) return QualityBand.good;
    return QualityBand.soft;
  }

  /// Standart oda anahtarı — Gemini'nin room_type çıktısını mekan_constants
  /// anahtarlarına (living_room, kitchen, bedroom, bathroom, dining_room,
  /// office) eşler. Eşleşme yoksa living_room döner (en güvenli fallback).
  String get roomKey {
    final rt = roomType.toLowerCase().replaceAll('-', '_');
    if (rt.contains('living')) return 'living_room';
    if (rt.contains('bed') || rt.contains('kids') || rt.contains('child')) {
      return 'bedroom';
    }
    if (rt.contains('kitchen')) return 'kitchen';
    if (rt.contains('bath') || rt.contains('wc') || rt.contains('toilet')) {
      return 'bathroom';
    }
    if (rt.contains('dining')) return 'dining_room';
    if (rt.contains('office') || rt.contains('study') || rt.contains('work')) {
      return 'office';
    }
    return 'living_room';
  }

  /// UI'da kullanılacak kısa Türkçe etiket.
  String get roomLabelTr {
    final rt = roomType.toLowerCase().replaceAll('_', ' ');
    if (rt.contains('living')) return 'Salon';
    if (rt.contains('bed')) return 'Yatak odası';
    if (rt.contains('kitchen')) return 'Mutfak';
    if (rt.contains('bath')) return 'Banyo';
    if (rt.contains('dining')) return 'Yemek odası';
    if (rt.contains('office') || rt.contains('study')) return 'Çalışma';
    if (rt.contains('hall') || rt.contains('entry')) return 'Giriş';
    if (rt.contains('kids') || rt.contains('child')) return 'Çocuk odası';
    if (rt.isEmpty) return 'Mekan';
    // ilk harf büyük
    return rt[0].toUpperCase() + rt.substring(1);
  }
}

class MekanAnalyzeException implements Exception {
  final String code;
  final String detail;
  MekanAnalyzeException(this.code, this.detail);
  @override
  String toString() => 'MekanAnalyzeException($code): $detail';
}

class MekanAnalyzeService {
  static const String _apiBase = String.fromEnvironment(
    'KOALA_API_URL',
    defaultValue: 'https://koala-api-olive.vercel.app',
  );

  static Future<AnalyzeResult> analyze(Uint8List imageBytes) async {
    final b64 = base64Encode(imageBytes);
    final dataUrl = 'data:image/jpeg;base64,$b64';

    final resp = await http.post(
      Uri.parse('$_apiBase/api/analyze-room'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'image': dataUrl}),
    );

    Map<String, dynamic> j;
    try {
      j = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw MekanAnalyzeException('bad_response', 'HTTP ${resp.statusCode}');
    }

    if (resp.statusCode >= 400) {
      throw MekanAnalyzeException(
        (j['error'] ?? 'http_${resp.statusCode}').toString(),
        (j['detail'] ?? resp.body).toString(),
      );
    }

    final rawQ = j['quality_score'];
    final q = (rawQ is num) ? rawQ.toDouble().clamp(0.0, 1.0) : 1.0;
    final rawIssues = j['issues'];
    final issues = (rawIssues is List)
        ? rawIssues
            .map((x) => _parseIssue(x.toString()))
            .where((x) => x != QualityIssue.unknown)
            .toList()
        : <QualityIssue>[];

    return AnalyzeResult(
      isRoom: j['is_room'] == true,
      roomType: (j['room_type'] ?? '').toString(),
      style: (j['style'] ?? '').toString(),
      caption: (j['caption'] ?? '').toString(),
      mood: (j['mood'] ?? '').toString(),
      colors: parseColors((j['colors'] ?? '').toString()),
      qualityScore: q,
      issues: issues,
    );
  }

  /// "cream (#F5F1EA), oak (#C4A27B)" -> `List<MekanColor>`
  static List<MekanColor> parseColors(String raw) {
    if (raw.isEmpty) return const [];
    final re = RegExp(r'([A-Za-z][A-Za-z\s\-]*?)\s*\(#([0-9a-fA-F]{3,8})\)');
    final out = <MekanColor>[];
    for (final m in re.allMatches(raw)) {
      final name = (m.group(1) ?? '').trim();
      final hex = (m.group(2) ?? '').trim();
      final c = _hexToColor(hex);
      if (c != null && name.isNotEmpty) {
        out.add(MekanColor(name: name, color: c, hex: '#${hex.toUpperCase()}'));
      }
    }
    return out;
  }

  static Color? _hexToColor(String hex) {
    var h = hex.replaceAll('#', '');
    if (h.length == 3) {
      h = h.split('').map((c) => '$c$c').join();
    }
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    final v = int.tryParse(h, radix: 16);
    if (v == null) return null;
    return Color(v);
  }

  // ────────────────────────────────────────────────────────────────────────
  // analyzeRoom — yeni /api/analyze-room sözleşmesi (CLIP gate + style hints)
  // ────────────────────────────────────────────────────────────────────────
  //
  // Eski `analyze()` Gemini tabanlı sözleşmeyi kullanıyor; bu metot ayrı bir
  // pipeline — `valid: bool` + style_tags/mood/dominant_colors. UI bunu restyle
  // hand-off'undan hemen önce çağırıp `StyleHints` stash eder; reddedilirse
  // dostane bir Türkçe diyalog ile picker'a yönlendirir.

  /// Yeni endpoint imzası — `image: dataUrl|httpsUrl`.
  /// Network/parse hatasında [MekanAnalyzeException] fırlatır.
  static Future<RoomAnalysis> analyzeRoom({
    required String imageDataUrlOrHttps,
  }) async {
    final http.Response resp;
    try {
      resp = await http
          .post(
            Uri.parse('$_apiBase/api/analyze-room'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'image': imageDataUrlOrHttps}),
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw MekanAnalyzeException('network', e.toString());
    }

    Map<String, dynamic> j;
    try {
      j = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw MekanAnalyzeException('bad_response', 'HTTP ${resp.statusCode}');
    }

    if (resp.statusCode >= 400) {
      throw MekanAnalyzeException(
        (j['error'] ?? 'http_${resp.statusCode}').toString(),
        (j['detail'] ?? resp.body).toString(),
      );
    }

    final latency = (j['latency_ms'] as num?)?.toInt();

    if (j['valid'] == true) {
      // Yeni route `style_hints` alanı altında map dönüyor; eski sözleşmede
      // `style` string. Geri uyumluluk için ikisini de dene.
      final raw = j['style_hints'] ?? j['style'];
      final style = (raw is Map)
          ? raw.cast<String, dynamic>()
          : const <String, dynamic>{};
      return RoomAnalysisValid(
        style: StyleHints.fromJson(style),
        latencyMs: latency,
      );
    }

    return RoomAnalysisInvalid(
      reason: (j['reason'] ?? 'unknown').toString(),
      confidence: (j['confidence'] as num?)?.toDouble() ?? 0.0,
      latencyMs: latency,
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Sealed-result style — RoomAnalysis = Valid | Invalid
// (Dart sealed classes ihtiyacı yok; abstract base + iki concrete sınıf
//  pattern matching ile aynı işi yapıyor, codegen-free.)
// ──────────────────────────────────────────────────────────────────────────

abstract class RoomAnalysis {
  const RoomAnalysis();
  bool get isValid => this is RoomAnalysisValid;
}

class RoomAnalysisValid extends RoomAnalysis {
  final StyleHints style;
  final int? latencyMs;
  const RoomAnalysisValid({required this.style, this.latencyMs});
}

class RoomAnalysisInvalid extends RoomAnalysis {
  final String reason;
  final double confidence;
  final int? latencyMs;
  const RoomAnalysisInvalid({
    required this.reason,
    required this.confidence,
    this.latencyMs,
  });
}

/// Restyle prompt'unu zenginleştirmek için /api/analyze-room'dan toplanan
/// stil sinyalleri. Görünmez şekilde flow state'inde tutulur, restyle
/// çağrısında theme metnine appendlenir.
class StyleHints {
  final List<String> tags;
  final String mood;
  final List<String> materials;
  final List<Color> dominantColors;
  final String roomTypeGuess;
  final double confidence;

  const StyleHints({
    required this.tags,
    required this.mood,
    required this.materials,
    required this.dominantColors,
    required this.roomTypeGuess,
    required this.confidence,
  });

  factory StyleHints.fromJson(Map<String, dynamic> j) {
    List<String> strList(dynamic v) =>
        (v is List) ? v.map((e) => e.toString()).toList() : const <String>[];

    final colorsRaw = (j['dominant_colors'] is List)
        ? (j['dominant_colors'] as List)
        : const [];
    final colors = <Color>[];
    for (final c in colorsRaw) {
      final parsed = MekanAnalyzeService._hexToColor(c.toString());
      // Parse hatasında nötr fallback — UI hiç boş kalmasın.
      colors.add(parsed ?? const Color(0xFFB8AFA3));
    }

    return StyleHints(
      tags: strList(j['style_tags']),
      mood: (j['mood'] ?? '').toString(),
      materials: strList(j['materials']),
      dominantColors: colors,
      roomTypeGuess: (j['room_type_guess'] ?? '').toString(),
      confidence: (j['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Restyle prompt enrichment — theme metnine eklenir.
  /// Boşsa boş string döner (caller append etmeden önce kontrol etmeli).
  String toPromptSuffix() {
    if (tags.isEmpty && mood.isEmpty) return '';
    final parts = <String>[];
    if (tags.isNotEmpty) parts.add('stil: ${tags.join(', ')}');
    if (mood.isNotEmpty) parts.add('mood: $mood');
    return ' · ${parts.join(' · ')}';
  }
}
