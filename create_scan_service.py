# -*- coding: utf-8 -*-
p = 'lib/services/ai_tutor_service.dart'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()

# Import ekle
c = c.replace(
    "import '../models/ai_solution.dart';",
    "import '../models/ai_solution.dart';\nimport '../models/scan_analysis.dart';"
)

# Sinifin sonuna (son } oncesine) yeni metod ekle
scan_method = r"""

  /// --- MEKAN ANALIZI ---
  Future<ScanAnalysis> analyzeRoom({required String imageUrl}) async {
    if (Env.geminiApiKey.isEmpty) {
      throw StateError('GEMINI_API_KEY is missing.');
    }

    final Uri uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      ':generateContent?key=',
    );

    final Map<String, dynamic> payload = <String, dynamic>{
      'contents': <Map<String, dynamic>>[
        <String, dynamic>{
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{
              'text': '\n\nBu mekan fotografini analiz et:',
            },
            <String, dynamic>{
              'inline_data': <String, dynamic>{
                'mime_type': 'image/jpeg',
                'data': await _fetchImageAsBase64(imageUrl),
              },
            },
          ],
        },
      ],
      'generationConfig': <String, dynamic>{
        'temperature': 0.3,
        'responseMimeType': 'application/json',
      },
    };

    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode >= 300) {
      throw Exception('Gemini scan request failed: ');
    }

    final Map<String, dynamic> responseJson = jsonDecode(response.body) as Map<String, dynamic>;
    final List<dynamic> candidates = responseJson['candidates'] as List<dynamic>? ?? [];
    if (candidates.isEmpty) throw const FormatException('Gemini returned no candidates.');

    final firstCandidate = candidates.first as Map<String, dynamic>;
    final content = firstCandidate['content'] as Map<String, dynamic>? ?? {};
    final parts = content['parts'] as List<dynamic>? ?? [];
    if (parts.isEmpty) throw const FormatException('Gemini returned empty parts.');

    final text = (parts.first as Map<String, dynamic>)['text'] as String? ?? '';
    if (text.trim().isEmpty) throw const FormatException('Gemini returned empty text.');

    return ScanAnalysis.fromJson(_extractJsonObject(text));
  }

  Future<String> _fetchImageAsBase64(String url) async {
    final response = await _client.get(Uri.parse(url));
    if (response.statusCode != 200) throw Exception('Image fetch failed: ');
    return base64Encode(response.bodyBytes);
  }
"""

# Son } oncesine ekle
last_brace = c.rfind('}')
c = c[:last_brace] + scan_method + '\n' + c[last_brace:]

# base64 import ekle
if "import 'dart:convert';" in c and "base64Encode" not in c.split("import")[0]:
    pass  # zaten var

with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('Done - analyzeRoom metodu eklendi')
