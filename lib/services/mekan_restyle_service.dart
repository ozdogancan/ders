import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import 'mekan_analyze_service.dart' show StyleHints;
import 'mock_mode.dart';
import 'replicate_service.dart' show ReplicateException;

/// Mekan Restyle v2 — 3-variant batch (faithful · editorial · bold).
///
/// Backend `/api/restyle/batch` paralel olarak 3 Gemini Flash Image render eder,
/// pHash drift + Gemini judge ile kalite kapısından geçirir, hayatta kalan
/// variant'ları döner. UI bunlardan birini (en yüksek judge_score) seçebilir
/// veya kullanıcıya 3'ünü de gösterebilir (PageView).
///
/// Tasarım kararı: mevcut [ReplicateService.restyle] tek-shot yolu legacy
/// olarak kalıyor. Bu servis ileri yol — feature flag arkasında kademeli
/// rollout yapılır.
class MekanRestyleService {
  static const String _apiBase = String.fromEnvironment(
    'KOALA_API_URL',
    defaultValue: 'https://koala-api-olive.vercel.app',
  );

  static const bool _forceMock =
      bool.fromEnvironment('MOCK_MEKAN', defaultValue: false);

  /// 3-variant restyle. Backend tipik 25-60s arası tamamlar; client tarafında
  /// 120s timeout güvenli (Vercel Fluid maxDuration ile aynı).
  static Future<RestyleBatchResult> restyleBatch({
    required Uint8List imageBytes,
    required String room,
    required String theme,
    StyleHints? styleHints,
    String? referenceUrl, // Swipe'tan gelen ilham görseli
  }) async {
    final b64 = base64Encode(imageBytes);
    final dataUrl = 'data:image/jpeg;base64,$b64';

    // Style hints varsa theme metnine tek satır enrichment append et.
    final enrichedTheme =
        '${theme.toLowerCase()}${styleHints?.toPromptSuffix() ?? ''}';

    // _forceMock = compile-time, MockMode.enabled = compile-time veya runtime
    // (URL ?mock=1 ile etkin). Token harcamadan UI test'i için.
    if (_forceMock || MockMode.enabled) {
      await Future.delayed(const Duration(milliseconds: 1800));
      // Stil + oda eşleşmeli stock görsel — supabase style-previews'den.
      final mockUrl = MockMode.mockAfterUrl(room: room, theme: theme);
      return RestyleBatchResult(
        variants: [
          RestyleVariant(
            output: mockUrl,
            promptKind: 'faithful',
            judgeScore: 0.92,
            judgeReason: 'mock',
            phashDistance: 6,
            mock: true,
          ),
          RestyleVariant(
            output: mockUrl,
            promptKind: 'editorial',
            judgeScore: 0.85,
            judgeReason: 'mock',
            phashDistance: 12,
            mock: true,
          ),
          RestyleVariant(
            output: mockUrl,
            promptKind: 'bold',
            judgeScore: 0.78,
            judgeReason: 'mock',
            phashDistance: 18,
            mock: true,
          ),
        ],
        rejectedCount: 0,
        latencyMs: 1800,
        mock: true,
      );
    }

    final resp = await http
        .post(
          Uri.parse('$_apiBase/api/restyle/batch'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'image': dataUrl,
            'room': room.toLowerCase(),
            'theme': enrichedTheme,
            if (referenceUrl != null && referenceUrl.isNotEmpty)
              'reference_url': referenceUrl,
          }),
        )
        .timeout(const Duration(seconds: 120));

    Map<String, dynamic> j;
    try {
      j = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw ReplicateException('bad_response', 'HTTP ${resp.statusCode}');
    }

    if (resp.statusCode >= 400) {
      throw ReplicateException(
        (j['error'] ?? 'http_${resp.statusCode}').toString(),
        (j['detail'] ?? resp.body).toString(),
      );
    }

    final rawVariants = j['variants'];
    if (rawVariants is! List || rawVariants.isEmpty) {
      throw ReplicateException(
        'no_variants',
        'judge tüm variant\'ları reddetti veya boş response',
      );
    }

    final variants = rawVariants
        .whereType<Map>()
        .map((v) => RestyleVariant.fromJson(v.cast<String, dynamic>()))
        .where((v) => v.output.isNotEmpty)
        .toList();

    if (variants.isEmpty) {
      throw ReplicateException('no_variants', 'parse sonrası variant kalmadı');
    }

    // Judge score'a göre sırala — UI default olarak en yükseği gösterir.
    variants.sort((a, b) => b.judgeScore.compareTo(a.judgeScore));

    return RestyleBatchResult(
      variants: variants,
      rejectedCount: (j['rejected_count'] as num?)?.toInt() ?? 0,
      latencyMs: (j['latency_ms'] as num?)?.toInt() ?? 0,
      mock: false,
    );
  }
}

/// Tek bir variant — backend'in döndüğü zenginleştirilmiş çıktı.
class RestyleVariant {
  /// Görsel URL'i (Vercel Blob veya base64 dataUrl).
  final String output;

  /// 'faithful' | 'editorial' | 'bold'
  /// Faithful = sahneye sadık, düşük temp; bold = drama, yüksek temp.
  final String promptKind;

  /// Gemini judge skoru — 0.0 (kötü) → 1.0 (mükemmel).
  /// 0.7 altı backend'de elendi; UI ranking için kullanır.
  final double judgeScore;

  /// Judge'ın kısa Türkçe gerekçesi — debug/telemetri için.
  final String judgeReason;

  /// pHash Hamming mesafesi — 0 (aynı) → 64 (taban tabana zıt).
  /// 24 üstü "sahne kayboldu" sayılır ve backend'de elenir.
  final int phashDistance;

  /// Mock mode'da true — UI banner gösterebilir.
  final bool mock;

  const RestyleVariant({
    required this.output,
    required this.promptKind,
    required this.judgeScore,
    required this.judgeReason,
    required this.phashDistance,
    this.mock = false,
  });

  factory RestyleVariant.fromJson(Map<String, dynamic> j) {
    return RestyleVariant(
      output: (j['url'] ?? j['output'] ?? '').toString(),
      promptKind: (j['prompt_kind'] ?? 'faithful').toString(),
      judgeScore: (j['judge_score'] as num?)?.toDouble() ?? 0.0,
      judgeReason: (j['judge_reason'] ?? '').toString(),
      phashDistance: (j['phash_distance'] as num?)?.toInt() ?? 0,
      mock: false,
    );
  }

  /// UI etiketi — chip/dot label için.
  String get labelTr {
    switch (promptKind) {
      case 'faithful':
        return 'Sadık';
      case 'editorial':
        return 'Editöryel';
      case 'bold':
        return 'Cesur';
      default:
        return promptKind;
    }
  }
}

/// Batch sonucu paketi.
class RestyleBatchResult {
  final List<RestyleVariant> variants;
  final int rejectedCount;
  final int latencyMs;
  final bool mock;

  const RestyleBatchResult({
    required this.variants,
    required this.rejectedCount,
    required this.latencyMs,
    this.mock = false,
  });

  /// En yüksek skorlu — variants zaten sıralı.
  RestyleVariant get best => variants.first;
}
