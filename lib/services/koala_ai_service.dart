import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/config/env.dart';
import '../core/constants/koala_prompts.dart';
import 'koala_tool_handler.dart';

/// Card in Koala's response
class KoalaCard {
  final String type;
  final Map<String, dynamic> data;
  const KoalaCard({required this.type, required this.data});
  factory KoalaCard.fromJson(Map<String, dynamic> json) =>
    KoalaCard(type: json['type'] as String? ?? 'text', data: json);

  Map<String, dynamic> toJson() => {'type': type, ...data};
}

/// Full response
class KoalaResponse {
  final String message;
  final List<KoalaCard> cards;
  const KoalaResponse({required this.message, required this.cards});
}

/// Intent types
enum KoalaIntent {
  styleExplore,
  roomRenovation,
  colorAdvice,
  designerMatch,
  budgetPlan,
  beforeAfter,
  pollResult,
  photoAnalysis,
  freeChat,
}

class KoalaAIService {
  KoalaAIService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  /// Gemini Function Calling tool tanımları
  static const List<Map<String, dynamic>> _toolDeclarations = [
    {
      'function_declarations': [
        {
          'name': 'search_products',
          'description': 'Evlumba ürün kataloğundan gerçek ürün ara. Kullanıcı bir ürün tipi söylediğinde, '
              'mobilya/dekorasyon önerisi istediğinde veya bütçeye göre ürün filtrelemek istediğinde çağır. '
              'ASLA ürün adı, fiyat veya marka uydurma — bu fonksiyonu çağır.',
          'parameters': {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'description': 'Aranacak ürün anahtar kelimesi. Türkçe yaz. Örnekler: kanepe, sehpa, sandalye, aydınlatma, halı, perde',
              },
              'room_type': {
                'type': 'string',
                'enum': ['salon', 'yatak_odasi', 'mutfak', 'banyo', 'ofis', 'cocuk_odasi', 'antre', 'balkon', 'ev_ofisi'],
                'description': 'Oda tipi filtresi',
              },
              'max_price': {
                'type': 'number',
                'description': 'Maksimum fiyat (TL). Kullanıcının bütçesine göre filtrele.',
              },
              'limit': {
                'type': 'integer',
                'description': 'Kaç ürün dönsün (varsayılan 6, max 8)',
              },
            },
            'required': ['query'],
          },
        },
        {
          'name': 'search_projects',
          'description': 'Evlumba tasarım projelerini ara. Kullanıcıya ilham vermek, '
              'örnek tasarımlar göstermek veya belirli bir oda tipi için tasarım örnekleri sunmak istediğinde çağır. '
              'Kullanıcı "farklı projeler göster" veya "başka öneriler" derse offset parametresini artır.',
          'parameters': {
            'type': 'object',
            'properties': {
              'room_type': {
                'type': 'string',
                'enum': ['salon', 'yatak_odasi', 'mutfak', 'banyo', 'ofis', 'cocuk_odasi', 'antre', 'balkon', 'ev_ofisi'],
                'description': 'Oda tipi filtresi',
              },
              'limit': {
                'type': 'integer',
                'description': 'Kaç proje dönsün (varsayılan 4, max 6)',
              },
              'offset': {
                'type': 'integer',
                'description': 'Kaç proje atlansın. İlk çağrıda 0, "farklı göster" denirse 4, sonraki için 8 vb.',
              },
            },
          },
        },
        {
          'name': 'search_designers',
          'description': 'Evlumba tasarımcılarını ara. Kullanıcı tasarımcı bulmak istediğinde, '
              'profesyonel yardım sorduğunda veya belirli bir şehirdeki tasarımcıları aradığında çağır.',
          'parameters': {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'description': 'Tasarımcı adı veya uzmanlık alanı ile ara',
              },
              'city': {
                'type': 'string',
                'description': 'Şehir filtresi. Örnekler: İstanbul, Ankara, İzmir',
              },
              'limit': {
                'type': 'integer',
                'description': 'Kaç tasarımcı dönsün (varsayılan 3, max 5)',
              },
            },
          },
        },
        {
          'name': 'compare_products',
          'description': 'Birden fazla ürünü karşılaştır. Kullanıcı iki veya daha fazla ürünü '
              'kıyaslamak istediğinde, hangisini tercih etmesi gerektiğini sorduğunda çağır.',
          'parameters': {
            'type': 'object',
            'properties': {
              'product_names': {
                'type': 'array',
                'items': {'type': 'string'},
                'description': 'Karşılaştırılacak ürün adları (max 3)',
              },
              'room_type': {
                'type': 'string',
                'enum': ['salon', 'yatak_odasi', 'mutfak', 'banyo', 'ofis', 'cocuk_odasi'],
                'description': 'Oda tipi filtresi',
              },
            },
            'required': ['product_names'],
          },
        },
      ],
    },
  ];

  /// User preferences from onboarding (injected into prompts)
  Map<String, String> _userPrefs = const {};

  /// Public getters for profile-aware UI
  String? get userStyle => _userPrefs['style'];
  String? get userRoom => _userPrefs['room'];
  String? get userBudget => _userPrefs['budget'];

  /// Set user preferences (call once from chat screen)
  void setUserPreferences({
    String? style,
    String? colors,
    String? room,
    String? budget,
    String? dislikedStyles,
    String? dislikedColors,
    String? likedDetailsText,
  }) {
    _userPrefs = {
      if (style != null && style.isNotEmpty) 'style': style,
      if (colors != null && colors.isNotEmpty) 'colors': colors,
      if (room != null && room.isNotEmpty) 'room': room,
      if (budget != null && budget.isNotEmpty) 'budget': budget,
      if (dislikedStyles != null && dislikedStyles.isNotEmpty) 'dislikedStyles': dislikedStyles,
      if (dislikedColors != null && dislikedColors.isNotEmpty) 'dislikedColors': dislikedColors,
      if (likedDetailsText != null && likedDetailsText.isNotEmpty) 'likedDetailsText': likedDetailsText,
    };
  }

  /// Injects user profile into any prompt
  String _withProfile(String prompt) {
    final block = KoalaPrompts.userProfileBlock(
      style: _userPrefs['style'],
      colors: _userPrefs['colors'],
      room: _userPrefs['room'],
      budget: _userPrefs['budget'],
      dislikedStyles: _userPrefs['dislikedStyles'],
      dislikedColors: _userPrefs['dislikedColors'],
      likedDetailsText: _userPrefs['likedDetailsText'],
    );
    if (block.isEmpty) return prompt;
    return prompt + block;
  }

  /// Main entry — with conversation history
  Future<KoalaResponse> askWithIntent({
    required KoalaIntent intent,
    Map<String, String> params = const {},
    String? freeText,
    Uint8List? photo,
    List<Map<String, String>>? history,
  }) async {
    String prompt;

    switch (intent) {
      case KoalaIntent.styleExplore:
        prompt = KoalaPrompts.styleExplore(params['style'] ?? 'Modern');
      case KoalaIntent.roomRenovation:
        if (params.containsKey('budget')) {
          prompt = KoalaPrompts.roomResult(
            roomType: params['room'] ?? 'salon',
            style: params['style'] ?? 'modern',
            budget: params['budget'] ?? '30-60K TL',
            priority: params['priority'] ?? 'komple',
            hasPhoto: photo != null,
          );
        } else {
          prompt = KoalaPrompts.roomRenovation(
            params['room'] ?? 'salon',
            params['style'] ?? 'modern',
          );
        }
      case KoalaIntent.colorAdvice:
        prompt = KoalaPrompts.colorAdvice(params['room']);
      case KoalaIntent.designerMatch:
        if (params.containsKey('style') && params.containsKey('budget')) {
          prompt = KoalaPrompts.designerResult(params['style']!, params['budget']!);
        } else {
          prompt = KoalaPrompts.designerMatch();
        }
      case KoalaIntent.budgetPlan:
        if (params.containsKey('room') && params.containsKey('budget')) {
          prompt = KoalaPrompts.budgetResult(params['room']!, params['budget']!, params['priority'] ?? 'komple');
        } else {
          prompt = KoalaPrompts.budgetPlan();
        }
      case KoalaIntent.beforeAfter:
        prompt = KoalaPrompts.beforeAfter();
      case KoalaIntent.pollResult:
        prompt = KoalaPrompts.pollResult(params['style'] ?? 'Minimalist');
      case KoalaIntent.photoAnalysis:
        prompt = KoalaPrompts.photoAnalysis(freeText);
      case KoalaIntent.freeChat:
        prompt = KoalaPrompts.freeChat(freeText ?? 'Merhaba');
    }

    // Inject user profile into prompt
    prompt = _withProfile(prompt);

    if (photo != null) {
      return _callGeminiWithImage(prompt: prompt, imageBytes: photo);
    }

    // Ürün/tasarımcı/proje içerebilecek intent'lerde function calling kullan
    const toolIntents = {
      KoalaIntent.freeChat,
      KoalaIntent.roomRenovation,
      KoalaIntent.styleExplore,
      KoalaIntent.designerMatch,
      KoalaIntent.budgetPlan,
      KoalaIntent.beforeAfter,
    };

    if (toolIntents.contains(intent)) {
      return _callGeminiWithTools(prompt: prompt, history: history);
    }

    return _callGemini(prompt: prompt, history: history);
  }

  /// Builds prompt with user profile injected (for streaming usage).
  String buildPromptForFreeChat(String text) =>
    _withProfile(KoalaPrompts.freeChat(text));

  /// Simple ask with history
  Future<KoalaResponse> ask(String text, {List<Map<String, String>>? history}) =>
    askWithIntent(intent: KoalaIntent.freeChat, freeText: text, history: history);

  /// Photo ask
  Future<KoalaResponse> askWithPhoto(Uint8List photo, {String? text, List<Map<String, String>>? history}) =>
    askWithIntent(intent: KoalaIntent.photoAnalysis, freeText: text, photo: photo, history: history);

  // ── Gemini API (via proxy) ──

  /// Proxy URL for Koala API backend
  Uri get _proxyUri => Uri.parse('${Env.koalaApiUrl}/api/chat');

  Future<KoalaResponse> _callGemini({required String prompt, List<Map<String, String>>? history}) async {
    final contents = <Map<String, dynamic>>[];

    // Conversation history (last 10 messages for context)
    if (history != null) {
      final recent = history.length > 10 ? history.sublist(history.length - 10) : history;
      for (final msg in recent) {
        contents.add({
          'role': msg['role'] == 'user' ? 'user' : 'model',
          'parts': [{'text': msg['content'] ?? ''}],
        });
      }
    }

    contents.add({
      'role': 'user',
      'parts': [{'text': prompt}],
    });

    final payload = {
      'contents': contents,
      'generationConfig': {
        'temperature': 0.7,
        'responseMimeType': 'application/json',
      },
    };

    debugPrint('KoalaAI: Sending request via proxy (${contents.length} messages)...');
    final response = await _client.post(_proxyUri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload));

    if (response.statusCode >= 300) {
      debugPrint('KoalaAI ERROR ${response.statusCode}: ${response.body.substring(0, 300.clamp(0, response.body.length))}');
      throw Exception('Gemini failed: ${response.statusCode}');
    }

    return _parseResponse(_extractText(response.body));
  }

  /// Moondream ön-analiz endpoint'i
  Uri get _moondreamUri => Uri.parse('${Env.koalaApiUrl}/api/analyze-room');

  /// Moondream ile oda fotoğrafını ön-analiz et
  Future<Map<String, dynamic>?> _moondreamPreAnalyze(Uint8List imageBytes) async {
    try {
      final b64 = base64Encode(imageBytes);
      final response = await _client
          .post(
            _moondreamUri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'image': b64}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('Moondream: room_type=${data['room_type']}, style=${data['style']}');
        return data;
      }
      debugPrint('Moondream: ${response.statusCode} — falling back to Gemini only');
      return null;
    } catch (e) {
      debugPrint('Moondream: $e — falling back to Gemini only');
      return null;
    }
  }

  Future<KoalaResponse> _callGeminiWithImage({required String prompt, required Uint8List imageBytes}) async {
    // Moondream ön-analiz (paralel değil, önce çalışsın — context zenginleştirme)
    final preAnalysis = await _moondreamPreAnalyze(imageBytes);

    // Moondream sonuçlarını prompt'a ekle
    String enrichedPrompt = prompt;
    if (preAnalysis != null) {
      final context = StringBuffer('\n\n--- Oda Ön-Analizi (Vision AI) ---\n');
      if (preAnalysis['room_type'] != null) {
        context.write('Oda tipi: ${preAnalysis['room_type']}\n');
      }
      if (preAnalysis['style'] != null) {
        context.write('Tespit edilen stil: ${preAnalysis['style']}\n');
      }
      if (preAnalysis['colors'] != null) {
        context.write('Dominant renkler: ${preAnalysis['colors']}\n');
      }
      if (preAnalysis['mood'] != null) {
        context.write('Atmosfer: ${preAnalysis['mood']}\n');
      }
      if (preAnalysis['caption'] != null) {
        context.write('Genel açıklama: ${preAnalysis['caption']}\n');
      }
      final furniture = preAnalysis['furniture'] as List<dynamic>? ?? [];
      if (furniture.isNotEmpty) {
        final labels = furniture
            .map((f) => (f as Map<String, dynamic>)['label'] ?? '')
            .where((l) => l.toString().isNotEmpty)
            .toSet()
            .join(', ');
        context.write('Tespit edilen mobilyalar: $labels\n');
      }
      context.write('--- Ön-Analiz Sonu ---\n');
      context.write('Yukarıdaki ön-analiz verisini dikkate alarak yanıt ver.\n');
      enrichedPrompt = '$prompt${context.toString()}';
    }

    final payload = {
      'contents': [
        {
          'parts': [
            {'text': enrichedPrompt},
            {'inline_data': {'mime_type': 'image/jpeg', 'data': base64Encode(imageBytes)}},
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.7,
        'responseMimeType': 'application/json',
      },
    };

    final response = await _client
        .post(_proxyUri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload))
        .timeout(const Duration(seconds: 30));

    if (response.statusCode >= 300) {
      throw Exception('Gemini image failed: ${response.statusCode}');
    }

    return _parseResponse(_extractText(response.body));
  }

  String _extractText(String rawBody) {
    final data = jsonDecode(rawBody) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>? ?? [];
    if (candidates.isEmpty) throw const FormatException('No candidates');
    final content = (candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>? ?? {};
    final parts = content['parts'] as List<dynamic>? ?? [];
    if (parts.isEmpty) throw const FormatException('Empty parts');
    return ((parts.first as Map<String, dynamic>)['text'] as String? ?? '').trim();
  }

  // ═══════════════════════════════════════════════════════
  // FUNCTION CALLING — gerçek evlumba verisi ile AI yanıtı
  // ═══════════════════════════════════════════════════════

  Future<KoalaResponse> _callGeminiWithTools({
    required String prompt,
    List<Map<String, String>>? history,
  }) async {

    // Mesaj geçmişi hazırla
    final contents = <Map<String, dynamic>>[];
    if (history != null) {
      final recent = history.length > 10 ? history.sublist(history.length - 10) : history;
      for (final msg in recent) {
        contents.add({
          'role': msg['role'] == 'user' ? 'user' : 'model',
          'parts': [{'text': msg['content'] ?? ''}],
        });
      }
    }
    contents.add({'role': 'user', 'parts': [{'text': prompt}]});

    // Max 3 tur (ilk istek + 2 function call)
    for (int turn = 0; turn < 3; turn++) {
      // Not: responseMimeType + tools birlikte kullanılmaz — Gemini function call
      // döndürmesi gereken turda JSON zorlama function call'ı engelleyebilir.
      // JSON formatını prompt ile zorluyoruz (SADECE JSON kuralı).
      final payload = {
        'contents': contents,
        'tools': _toolDeclarations,
        'generationConfig': {
          'temperature': 0.7,
        },
      };

      debugPrint('KoalaAI: Tools request turn=$turn (${contents.length} messages)...');
      final response = await _client.post(
        _proxyUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode >= 300) {
        debugPrint('KoalaAI ERROR ${response.statusCode}: ${response.body.substring(0, 300.clamp(0, response.body.length))}');
        throw Exception('Gemini failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>? ?? [];
      if (candidates.isEmpty) throw const FormatException('No candidates');

      final content = (candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>? ?? {};
      final parts = content['parts'] as List<dynamic>? ?? [];

      // Function call kontrolü
      Map<String, dynamic>? functionCall;
      for (final p in parts) {
        if ((p as Map<String, dynamic>).containsKey('functionCall')) {
          functionCall = p;
          break;
        }
      }

      if (functionCall != null) {
        final fc = functionCall['functionCall'] as Map<String, dynamic>;
        final fnName = fc['name'] as String;
        final fnArgs = (fc['args'] as Map<String, dynamic>?) ?? {};

        debugPrint('KoalaAI: Function call → $fnName($fnArgs)');

        // Function'ı çalıştır
        final result = await KoalaToolHandler.handle(fnName, fnArgs);

        debugPrint('KoalaAI: Function result → ${result.keys.toList()}');

        // Model response'u history'ye ekle
        contents.add({
          'role': 'model',
          'parts': [{'functionCall': {'name': fnName, 'args': fnArgs}}],
        });

        // Function sonucunu ekle
        contents.add({
          'role': 'user',
          'parts': [
            {
              'functionResponse': {
                'name': fnName,
                'response': result,
              },
            },
          ],
        });

        // Döngü devam: Gemini sonuçla birlikte final cevap üretsin
        continue;
      }

      // Function call yoksa → normal text response
      String text = '';
      for (final p in parts) {
        if ((p as Map<String, dynamic>).containsKey('text')) {
          text = (p['text'] as String? ?? '').trim();
          break;
        }
      }

      // JSON parse dene
      final parsed = _parseResponse(text);
      // Eğer parse başarılı ve kartlar varsa → döndür
      if (parsed.cards.isNotEmpty) return parsed;
      // Kartlar boşsa ama mesaj varsa → mesajla birlikte döndür (Gemini JSON vermemiş olabilir)
      if (parsed.message.isNotEmpty && parsed.message != 'İşte önerilerim!') return parsed;

      // Gemini JSON döndürmedi → responseMimeType ile tekrar dene (tools olmadan)
      debugPrint('KoalaAI: Tools response was not JSON, retrying with _callGemini...');
      return _callGemini(prompt: prompt, history: history);
    }

    // 3 tur dolduysa fallback — son çare olarak tools olmadan dene
    debugPrint('KoalaAI: 3 turns exhausted, falling back to _callGemini...');
    return _callGemini(prompt: prompt, history: history);
  }

  KoalaResponse _parseResponse(String raw) {
    try {
      final cleaned = _extractJsonString(raw);
      final data = jsonDecode(cleaned) as Map<String, dynamic>;
      final message = _sanitizeMessage(data['message'] as String? ?? '');
      final cardsRaw = data['cards'] as List<dynamic>? ?? [];
      final cards = cardsRaw
          .where((c) => c is Map<String, dynamic>)
          .map((c) => KoalaCard.fromJson(c as Map<String, dynamic>))
          .toList();
      return KoalaResponse(message: message, cards: cards);
    } catch (e) {
      debugPrint('KoalaAI parse error: $e\nRaw: ${raw.substring(0, 300.clamp(0, raw.length))}');
      // İkinci deneme: JSON bloğunu regex ile bul
      try {
        final jsonMatch = RegExp(r'\{[\s\S]*"message"[\s\S]*"cards"[\s\S]*\}').firstMatch(raw);
        if (jsonMatch != null) {
          final data = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
          final message = _sanitizeMessage(data['message'] as String? ?? '');
          final cardsRaw = data['cards'] as List<dynamic>? ?? [];
          final cards = cardsRaw
              .where((c) => c is Map<String, dynamic>)
              .map((c) => KoalaCard.fromJson(c as Map<String, dynamic>))
              .toList();
          debugPrint('KoalaAI: Recovered ${cards.length} cards via regex fallback');
          return KoalaResponse(message: message, cards: cards);
        }
      } catch (_) {}
      // Son çare: sadece mesajı göster
      final friendly = _extractFriendlyText(raw);
      return KoalaResponse(message: friendly, cards: []);
    }
  }

  /// Ham yanıttan JSON string'i temizle (code fence, BOM, trailing text)
  String _extractJsonString(String raw) {
    var cleaned = raw.trim();
    // BOM kaldır
    if (cleaned.startsWith('\uFEFF')) cleaned = cleaned.substring(1);
    // Markdown code fence kaldır
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replaceFirst(RegExp(r'^```\w*\n?'), '').trimRight();
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3).trimRight();
      }
    }
    // Bazen Gemini JSON'dan sonra açıklama ekliyor — ilk {...} bloğunu al
    final firstBrace = cleaned.indexOf('{');
    if (firstBrace > 0) cleaned = cleaned.substring(firstBrace);
    final lastBrace = cleaned.lastIndexOf('}');
    if (lastBrace >= 0 && lastBrace < cleaned.length - 1) {
      cleaned = cleaned.substring(0, lastBrace + 1);
    }
    return cleaned;
  }

  /// AI mesajından kod kalıntılarını ve markdown artefaktlarını temizle
  String _sanitizeMessage(String msg) {
    var clean = msg.trim();
    // Markdown code fence kaldır
    clean = clean.replaceAll(RegExp(r'```\w*\n?'), '').replaceAll('```', '');
    // Escaped unicode kaldır
    clean = clean.replaceAll(RegExp(r'\\u[0-9a-fA-F]{4}'), '');
    // Birden fazla boşluk/newline temizle
    clean = clean.replaceAll(RegExp(r'\s{3,}'), '  ');
    return clean.isEmpty ? 'İşte önerilerim!' : clean;
  }

  /// Parse başarısız olduğunda ham text'ten okunabilir kısmı çıkar
  String _extractFriendlyText(String raw) {
    // "message" alanını regex ile yakala
    final match = RegExp(r'"message"\s*:\s*"((?:[^"\\]|\\.)*)').firstMatch(raw);
    if (match != null) {
      final decoded = (match.group(1) ?? '')
          .replaceAll(r'\"', '"')
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\\', r'\')
          .trim();
      if (decoded.isNotEmpty) return _sanitizeMessage(decoded);
    }
    // Hiçbir şey bulamazsa genel mesaj
    return 'Yanıtımı hazırlarken bir aksilik oldu. Tekrar dener misin? 🐨';
  }

  // ═══════════════════════════════════════════════════════
  // STREAMING SUPPORT
  // ═══════════════════════════════════════════════════════

  /// Streaming ile mesaj gönder — her chunk'ı yield eder.
  /// Son chunk'ta tam JSON parse edilip KoalaResponse döner.
  /// Gemini streamGenerateContent SSE endpoint kullanır.
  Stream<StreamChunk> streamMessage({
    required String prompt,
    List<Map<String, String>>? history,
  }) async* {
    final contents = <Map<String, dynamic>>[];
    if (history != null) {
      final recent = history.length > 10 ? history.sublist(history.length - 10) : history;
      for (final msg in recent) {
        contents.add({
          'role': msg['role'] == 'user' ? 'user' : 'model',
          'parts': [{'text': msg['content'] ?? ''}],
        });
      }
    }
    contents.add({'role': 'user', 'parts': [{'text': prompt}]});

    final payload = jsonEncode({
      'contents': contents,
      'stream': true,
      'generationConfig': {
        'temperature': 0.7,
        'responseMimeType': 'application/json',
      },
    });

    final request = http.Request('POST', _proxyUri)
      ..headers['Content-Type'] = 'application/json'
      ..body = payload;

    final http.StreamedResponse streamedResponse = await _client.send(request);
    if (streamedResponse.statusCode >= 300) {
      throw Exception('Gemini stream failed: ${streamedResponse.statusCode}');
    }

    final buffer = StringBuffer();

    await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
      // SSE format: "data: {...}\n\n"
      for (final line in chunk.split('\n')) {
        if (line.startsWith('data: ')) {
          final jsonStr = line.substring(6).trim();
          if (jsonStr.isEmpty) continue;
          try {
            final data = jsonDecode(jsonStr) as Map<String, dynamic>;
            final candidates = data['candidates'] as List? ?? [];
            if (candidates.isNotEmpty) {
              final content = (candidates.first as Map)['content'] as Map? ?? {};
              final parts = content['parts'] as List? ?? [];
              if (parts.isNotEmpty) {
                final text = (parts.first as Map)['text'] as String? ?? '';
                buffer.write(text);
                yield StreamChunk(text: text, accumulated: buffer.toString(), isDone: false);
              }
            }
          } catch (_) {}
        }
      }
    }

    // Son: tam yanıtı parse et
    final fullText = buffer.toString().trim();
    try {
      final response = _parseResponse(fullText);
      yield StreamChunk(text: '', accumulated: fullText, isDone: true, response: response);
    } catch (e) {
      yield StreamChunk(text: '', accumulated: fullText, isDone: true,
        response: KoalaResponse(message: fullText, cards: []));
    }
  }
}

/// Streaming chunk verisi
class StreamChunk {
  final String text;        // bu chunk'taki yeni metin
  final String accumulated; // şimdiye kadarki toplam metin
  final bool isDone;        // stream bitti mi
  final KoalaResponse? response; // isDone=true ise parse edilmiş yanıt

  StreamChunk({required this.text, required this.accumulated, required this.isDone, this.response});
}
