import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/config/env.dart';

class ChatGptService {
  ChatGptService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const String _defaultSystemPrompt =
      'Sen Turkce konusan, net, sabirli ve ogretici bir ogretmensin. '
      'Gerektiginde kisa bir yol haritasi ver, sonra cozumu adim adim ve sade bir dille anlat.';

  Future<String> askText(String question) async {
    if (question.trim().isEmpty) {
      throw ArgumentError('Question text is empty.');
    }

    if (Env.aiProvider == AiProvider.gemini) {
      return _geminiText(question.trim());
    }
    return _requestImageOrText(
      userContent: <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'text': question.trim()},
      ],
      systemPrompt: _defaultSystemPrompt,
    );
  }

  Future<String> askImage(File imageFile, {String? prompt}) async {
    final Uint8List bytes = await imageFile.readAsBytes();
    return askImageBytes(bytes, prompt: prompt);
  }

  Future<String> askImageBytes(Uint8List imageBytes, {String? prompt}) async {
    final String base64Image = base64Encode(imageBytes);

    if (Env.aiProvider == AiProvider.gemini) {
      return _geminiImage(base64Image, prompt: prompt);
    }
    return _requestImageOrText(
      userContent: <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'text',
          'text': prompt?.trim().isNotEmpty == true
              ? prompt!.trim()
              : 'Bu soruyu adim adim coz ve kisa acikla.',
        },
        <String, dynamic>{
          'type': 'image_url',
          'image_url': <String, dynamic>{
            'url': 'data:image/jpeg;base64,$base64Image',
          },
        },
      ],
      systemPrompt: _defaultSystemPrompt,
    );
  }

  Future<String> askConversation({
    required String systemPrompt,
    required List<Map<String, String>> messages,
  }) async {
    if (messages.isEmpty) {
      throw ArgumentError('Conversation is empty.');
    }

    if (Env.aiProvider == AiProvider.gemini) {
      return _geminiConversation(
        systemPrompt: systemPrompt,
        messages: messages,
      );
    }

    if (Env.openAiApiKey.isEmpty) {
      throw StateError('OPENAI_API_KEY missing. Pass via --dart-define.');
    }

    final Uri uri = Uri.parse('https://api.openai.com/v1/chat/completions');
    final List<Map<String, dynamic>> payloadMessages = <Map<String, dynamic>>[
      <String, dynamic>{'role': 'system', 'content': systemPrompt.trim()},
      ...messages.map((Map<String, String> message) {
        return <String, dynamic>{
          'role': message['role'] ?? 'user',
          'content': message['content'] ?? '',
        };
      }),
    ];

    final Map<String, dynamic> payload = <String, dynamic>{
      'model': Env.openAiModel,
      'temperature': 0.35,
      'messages': payloadMessages,
    };

    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{
        'Authorization': 'Bearer ${Env.openAiApiKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode >= 300) {
      throw Exception('ChatGPT request failed: ${response.body}');
    }

    return _extractTextFromResponse(response.body);
  }

  // ── Gemini helpers ──

  Future<String> _geminiText(String question) async {
    if (Env.geminiApiKey.isEmpty) {
      throw StateError('GEMINI_API_KEY missing. Pass via --dart-define.');
    }

    final Uri uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '${Uri.encodeComponent(Env.geminiModel)}:generateContent?key=${Env.geminiApiKey}',
    );

    final Map<String, dynamic> payload = <String, dynamic>{
      'contents': <Map<String, dynamic>>[
        <String, dynamic>{
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{'text': '$_defaultSystemPrompt\n\n$question'},
          ],
        },
      ],
      'generationConfig': <String, dynamic>{'temperature': 0.3},
    };

    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode >= 300) {
      throw Exception('Gemini request failed: ${response.body}');
    }

    return _extractGeminiText(response.body);
  }

  Future<String> _geminiImage(String base64Image, {String? prompt}) async {
    if (Env.geminiApiKey.isEmpty) {
      throw StateError('GEMINI_API_KEY missing. Pass via --dart-define.');
    }

    final Uri uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '${Uri.encodeComponent(Env.geminiModel)}:generateContent?key=${Env.geminiApiKey}',
    );

    final String textPrompt = prompt?.trim().isNotEmpty == true
        ? prompt!.trim()
        : 'Bu soruyu adim adim coz ve kisa acikla.';

    final Map<String, dynamic> payload = <String, dynamic>{
      'contents': <Map<String, dynamic>>[
        <String, dynamic>{
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{'text': '$_defaultSystemPrompt\n\n$textPrompt'},
            <String, dynamic>{
              'inline_data': <String, dynamic>{
                'mime_type': 'image/jpeg',
                'data': base64Image,
              },
            },
          ],
        },
      ],
      'generationConfig': <String, dynamic>{'temperature': 0.3},
    };

    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode >= 300) {
      throw Exception('Gemini image request failed: ${response.body}');
    }

    return _extractGeminiText(response.body);
  }

  Future<String> _geminiConversation({
    required String systemPrompt,
    required List<Map<String, String>> messages,
  }) async {
    if (Env.geminiApiKey.isEmpty) {
      throw StateError('GEMINI_API_KEY missing. Pass via --dart-define.');
    }

    final Uri uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '${Uri.encodeComponent(Env.geminiModel)}:generateContent?key=${Env.geminiApiKey}',
    );

    final StringBuffer conversationText = StringBuffer(systemPrompt.trim());
    for (final Map<String, String> msg in messages) {
      final String role = msg['role'] ?? 'user';
      final String content = msg['content'] ?? '';
      conversationText.write('\n$role: $content');
    }

    final Map<String, dynamic> payload = <String, dynamic>{
      'contents': <Map<String, dynamic>>[
        <String, dynamic>{
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{'text': conversationText.toString()},
          ],
        },
      ],
      'generationConfig': <String, dynamic>{'temperature': 0.35},
    };

    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode >= 300) {
      throw Exception('Gemini conversation failed: ${response.body}');
    }

    return _extractGeminiText(response.body);
  }

  String _extractGeminiText(String rawBody) {
    final Map<String, dynamic> data =
        jsonDecode(rawBody) as Map<String, dynamic>;
    final List<dynamic> candidates =
        data['candidates'] as List<dynamic>? ?? <dynamic>[];
    if (candidates.isEmpty) {
      throw const FormatException('Gemini returned no candidates.');
    }
    final Map<String, dynamic> content =
        (candidates.first as Map<String, dynamic>)['content']
            as Map<String, dynamic>? ??
        <String, dynamic>{};
    final List<dynamic> parts =
        content['parts'] as List<dynamic>? ?? <dynamic>[];
    if (parts.isEmpty) {
      throw const FormatException('Gemini returned empty parts.');
    }
    final String text =
        ((parts.first as Map<String, dynamic>)['text'] as String? ?? '').trim();
    if (text.isEmpty) {
      throw const FormatException('Gemini returned empty text.');
    }
    return text;
  }

  // ── OpenAI helpers ──

  Future<String> _requestImageOrText({
    required List<Map<String, dynamic>> userContent,
    required String systemPrompt,
  }) async {
    if (Env.openAiApiKey.isEmpty) {
      throw StateError('OPENAI_API_KEY missing. Pass via --dart-define.');
    }

    final Uri uri = Uri.parse('https://api.openai.com/v1/chat/completions');

    final Map<String, dynamic> payload = <String, dynamic>{
      'model': Env.openAiModel,
      'temperature': 0.3,
      'messages': <Map<String, dynamic>>[
        <String, dynamic>{'role': 'system', 'content': systemPrompt},
        <String, dynamic>{'role': 'user', 'content': userContent},
      ],
    };

    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{
        'Authorization': 'Bearer ${Env.openAiApiKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode >= 300) {
      throw Exception('ChatGPT request failed: ${response.body}');
    }

    return _extractTextFromResponse(response.body);
  }

  String _extractTextFromResponse(String rawBody) {
    final Map<String, dynamic> data =
        jsonDecode(rawBody) as Map<String, dynamic>;
    final List<dynamic> choices =
        data['choices'] as List<dynamic>? ?? <dynamic>[];
    if (choices.isEmpty) {
      throw const FormatException('Empty response from ChatGPT.');
    }

    final Map<String, dynamic> message =
        (choices.first as Map<String, dynamic>)['message']
            as Map<String, dynamic>? ??
        <String, dynamic>{};

    final String text = (message['content'] as String? ?? '').trim();
    if (text.isEmpty) {
      throw const FormatException('ChatGPT returned empty answer.');
    }

    return text;
  }
}
