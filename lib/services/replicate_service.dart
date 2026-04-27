import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import 'mekan_analyze_service.dart' show StyleHints;

/// Mekan restyle servisi — koala-api proxy üzerinden Replicate.
/// Key Flutter'a gömülmez; sadece koala-api (Vercel) env var'ında durur.
/// MOCK_MEKAN=true ile mock moda alınır (API çağrısı yapılmaz, orijinal foto döner).
class ReplicateService {
  static const String _apiBase = String.fromEnvironment(
    'KOALA_API_URL',
    defaultValue: 'https://koala-api-olive.vercel.app',
  );

  static const bool _forceMock =
      bool.fromEnvironment('MOCK_MEKAN', defaultValue: false);

  static Future<RestyleResult> restyle({
    required Uint8List imageBytes,
    required String room,
    required String theme,
    StyleHints? styleHints,
  }) async {
    final b64 = base64Encode(imageBytes);
    final dataUrl = 'data:image/jpeg;base64,$b64';

    if (_forceMock) {
      await Future.delayed(const Duration(milliseconds: 2500));
      return RestyleResult(output: dataUrl, mock: true);
    }

    // Style hints varsa theme metnine tek satır enrichment append et.
    final enrichedTheme =
        '${theme.toLowerCase()}${styleHints?.toPromptSuffix() ?? ''}';

    final resp = await http.post(
      Uri.parse('$_apiBase/api/restyle'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'image': dataUrl,
        'room': room.toLowerCase(),
        'theme': enrichedTheme,
      }),
    );

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

    final output = j['output'] as String?;
    if (output == null || output.isEmpty) {
      throw ReplicateException('no_output', resp.body);
    }
    return RestyleResult(output: output, mock: false);
  }
}

class RestyleResult {
  final String output;
  final bool mock;
  const RestyleResult({required this.output, required this.mock});
}

class ReplicateException implements Exception {
  final String code;
  final String detail;
  ReplicateException(this.code, this.detail);
  @override
  String toString() => 'ReplicateException($code): $detail';
}
