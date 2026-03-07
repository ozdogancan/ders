import 'dart:convert';
import 'package:http/http.dart' as http;

class DidService {
  static const String _apiKey = 'aW5mb0Bldmx1bWJhLmNvbQ:DNSoQM0W1MwJuNjLMhC7u';
  static const String _baseUrl = 'https://api.d-id.com';
  final http.Client _client;

  DidService({http.Client? client}) : _client = client ?? http.Client();

  Future<String> createTalkingVideo({
    required String imageUrl,
    required String text,
  }) async {
    final uri = Uri.parse('$_baseUrl/talks');

    final payload = {
      'source_url': imageUrl,
      'script': {
        'type': 'text',
        'input': text,
        'provider': {
          'type': 'microsoft',
          'voice_id': 'tr-TR-AhmetNeural', // Türkçe erkek sesi
        },
      },
      'config': {'fluent': true, 'pad_audio': 0.0},
    };

    final response = await _client.post(
      uri,
      headers: {
        'Authorization': 'Basic $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode != 201) {
      throw Exception('D-ID request failed: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final talkId = data['id'] as String;

    return await _waitForVideoCompletion(talkId);
  }

  Future<String> _waitForVideoCompletion(String talkId) async {
    for (int i = 0; i < 60; i++) {
      // 5 dakika max bekleme
      await Future.delayed(const Duration(seconds: 5));

      final uri = Uri.parse('$_baseUrl/talks/$talkId');
      final response = await _client.get(
        uri,
        headers: {'Authorization': 'Basic $_apiKey'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final status = data['status'] as String;

        if (status == 'done') {
          return data['result_url'] as String;
        } else if (status == 'error') {
          throw Exception('D-ID video generation failed');
        }
      }
    }

    throw Exception('D-ID video generation timeout');
  }
}
