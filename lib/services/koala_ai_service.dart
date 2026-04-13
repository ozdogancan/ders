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

  void dispose() {
    _client.close();
  }

  String _detectMimeType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    if (bytes.length >= 12 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      return 'image/heic';
    }
    return 'image/jpeg';
  }

  /// Gemini Function Calling tool tanımları
  static const List<Map<String, dynamic>> _toolDeclarations = [
    {
      'function_declarations': [
        {
          'name': 'search_products',
          'description': 'Türkiye\'deki online mağazalardan (Trendyol, Hepsiburada, IKEA, Amazon TR vb.) gerçek ürün ara. '
              'Kullanıcı bir ürün tipi söylediğinde, mobilya/dekorasyon önerisi istediğinde veya bütçeye göre ürün filtrelemek istediğinde çağır. '
              'ASLA ürün adı, fiyat veya marka uydurma — bu fonksiyonu çağır. Sonuçlar gerçek marketplace ürünleridir.',
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
        if (params.containsKey('style')) {
          // Stil bilgisi varsa direkt sonuç getir (şehir/bütçe opsiyonel)
          prompt = KoalaPrompts.designerResult(
            params['style']!,
            params['budget'] ?? params['city'] ?? 'tümü',
          );
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

    // Inject user profile — fotoğraf analizinde profil ekleme (bias yaratır)
    // photoAnalysis'de AI odanın gerçek stilini tespit etmeli, kullanıcı tercihine göre değil
    if (intent != KoalaIntent.photoAnalysis) {
      prompt = _withProfile(prompt);
    }

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
      KoalaIntent.colorAdvice,
    };

    if (toolIntents.contains(intent)) {
      // Intent'e göre izin verilen fonksiyonları kısıtla
      List<String>? allowedFunctions;
      if (intent == KoalaIntent.designerMatch) {
        allowedFunctions = ['search_designers'];
      }
      return _callGeminiWithTools(prompt: prompt, history: history, allowedFunctions: allowedFunctions);
    }

    return _callGemini(prompt: prompt, history: history);
  }

  /// Builds prompt with user profile injected (for streaming usage).
  String buildPromptForFreeChat(String text) =>
    _withProfile(KoalaPrompts.freeChat(text));

  /// Simple ask with history
  Future<KoalaResponse> ask(String text, {List<Map<String, String>>? history}) =>
    askWithIntent(intent: KoalaIntent.freeChat, freeText: text, history: history);

  /// Sade metin cevabı al — JSON formatı yok, kart yok.
  /// Inline bilgi kartları için (stil analizi, kısa açıklamalar).
  Future<String> askPlainText(String prompt) async {
    final contents = [
      {
        'role': 'user',
        'parts': [{'text': prompt}],
      },
    ];
    final payload = {
      'contents': contents,
      'generationConfig': {'temperature': 0.7, 'maxOutputTokens': 300},
    };
    final response = await _client.post(_proxyUri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode >= 300) throw Exception('Gemini failed: ${response.statusCode}');
    return _extractText(response.body);
  }

  /// Photo ask
  Future<KoalaResponse> askWithPhoto(Uint8List photo, {String? text, List<Map<String, String>>? history}) =>
    askWithIntent(intent: KoalaIntent.photoAnalysis, freeText: text, photo: photo, history: history);

  // ── Gemini API (via proxy) ──

  /// Proxy URL for Koala API backend
  Uri get _proxyUri => Uri.parse('${Env.koalaApiUrl}/api/chat');

  Future<KoalaResponse> _callGemini({required String prompt, List<Map<String, String>>? history}) async {
    final systemInstruction = {'parts': [{'text': prompt}]};
    final contents = <Map<String, dynamic>>[];

    // Conversation history (last 8 messages, max 6000 karakter)
    if (history != null) {
      final recent = history.length > 8 ? history.sublist(history.length - 8) : history;
      int totalChars = 0;
      const maxHistoryChars = 6000;
      for (final msg in recent.reversed) {
        final text = msg['content'] ?? '';
        if (totalChars + text.length > maxHistoryChars) break;
        totalChars += text.length;
        contents.insert(0, {
          'role': msg['role'] == 'user' ? 'user' : 'model',
          'parts': [{'text': text}],
        });
      }
    }

    // Gemini en az 1 user mesajı ister
    if (contents.isEmpty || (contents.last['role'] != 'user')) {
      contents.add({'role': 'user', 'parts': [{'text': 'Devam et'}]});
    }

    final payload = {
      'system_instruction': systemInstruction,
      'contents': contents,
      'generationConfig': {
        'temperature': 0.7,
      },
    };

    debugPrint('KoalaAI: Sending request via proxy (${contents.length} messages)...');
    final response = await _client.post(_proxyUri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload))
        .timeout(const Duration(seconds: 30));

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
          .timeout(const Duration(seconds: 8));

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
    // Moondream devre dışı — API key 401 veriyor, 8s boşa bekleme yapıyordu
    // final preAnalysis = await _moondreamPreAnalyze(imageBytes);
    final mimeType = _detectMimeType(imageBytes);

    // Moondream devre dışı — API key 401, 8s boşa bekleme
    // Gemini 2.5 Flash image'ı doğrudan analiz ediyor
    String enrichedPrompt = prompt;

    // ── Tur 1: Görsel + tools ile Gemini çağır ──
    final imageB64 = base64Encode(imageBytes);
    final firstPayload = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': enrichedPrompt},
            {'inline_data': {'mime_type': mimeType, 'data': imageB64}},
          ]
        }
      ],
      'tools': _toolDeclarations,
      'generationConfig': {'temperature': 0.7},
    };

    final jsonBody = jsonEncode(firstPayload);
    final payloadSizeKB = (jsonBody.length / 1024).round();
    debugPrint('KoalaAI: Image+tools payload: ${payloadSizeKB}KB');

    // Retry logic — max 2 deneme, daha kısa timeout
    http.Response? response;
    for (int attempt = 1; attempt <= 2; attempt++) {
      response = await _client
          .post(_proxyUri, headers: {'Content-Type': 'application/json'}, body: jsonBody)
          .timeout(const Duration(seconds: 25));

      debugPrint('KoalaAI: Image attempt $attempt → ${response.statusCode}');
      if (response.statusCode < 300) break;
      if (response.statusCode == 503 || response.statusCode == 429) {
        if (attempt < 2) await Future.delayed(const Duration(seconds: 2));
        continue;
      }
      break;
    }

    if (response == null) {
      throw Exception('Sunucuya ulaşılamadı. İnternet bağlantını kontrol et.');
    }
    if (response.statusCode >= 300) {
      final body = response.body.length > 300 ? response.body.substring(0, 300) : response.body;
      debugPrint('KoalaAI: Image FAIL: ${response.statusCode} — $body');
      throw Exception('Fotoğraf analizi başarısız (hata: ${response.statusCode}). Lütfen tekrar dene.');
    }

    var data = jsonDecode(response.body) as Map<String, dynamic>;
    var candidates = data['candidates'] as List<dynamic>? ?? [];
    if (candidates.isEmpty) throw const FormatException('No candidates');

    var content = (candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>? ?? {};
    var parts = content['parts'] as List<dynamic>? ?? [];

    // Function call kontrolü
    Map<String, dynamic>? functionCall;
    for (final p in parts) {
      if ((p as Map<String, dynamic>).containsKey('functionCall')) {
        functionCall = p;
        break;
      }
    }

    // ── Tur 2: Function call varsa çalıştır, sonuçla tekrar çağır (IMAGE OLMADAN) ──
    final imageFunctionCards = <KoalaCard>[];
    if (functionCall != null) {
      final fc = functionCall['functionCall'] as Map<String, dynamic>;
      final fnName = fc['name'] as String;
      final fnArgs = (fc['args'] as Map<String, dynamic>?) ?? {};
      debugPrint('KoalaAI: Image function call → $fnName($fnArgs)');

      final result = await KoalaToolHandler.handle(fnName, fnArgs);

      // Function result'tan direkt kart oluştur
      imageFunctionCards.addAll(_buildCardsFromFunctionResult(fnName, result));

      // 2. tur: image yok, sadece text context + function call sonucu
      final turn2Payload = {
        'contents': [
          // Orijinal kullanıcı mesajı (image olmadan, sadece text)
          {'role': 'user', 'parts': [{'text': enrichedPrompt}]},
          // Model'in function call'ı
          {'role': 'model', 'parts': [{'functionCall': {'name': fnName, 'args': fnArgs}}]},
          // Function sonucu
          {'role': 'user', 'parts': [{'functionResponse': {'name': fnName, 'response': result}}]},
        ],
        'tools': _toolDeclarations,
        'generationConfig': {'temperature': 0.7},
      };

      debugPrint('KoalaAI: Image turn2 (function result)...');
      final resp2 = await _client
          .post(_proxyUri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(turn2Payload))
          .timeout(const Duration(seconds: 30));

      if (resp2.statusCode >= 300) {
        debugPrint('KoalaAI: Turn2 fail: ${resp2.statusCode}');
        // Function call sonucu ile cevap üretilemezse, ilk turdan text varsa onu kullan
        throw Exception('Ürün bilgileri alındı ama yanıt oluşturulamadı.');
      }

      data = jsonDecode(resp2.body) as Map<String, dynamic>;
      candidates = data['candidates'] as List<dynamic>? ?? [];
      if (candidates.isEmpty) throw const FormatException('No candidates turn2');
      content = (candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>? ?? {};
      parts = content['parts'] as List<dynamic>? ?? [];
    }

    // Text response çıkar
    String text = '';
    for (final p in parts) {
      if ((p as Map<String, dynamic>).containsKey('text')) {
        text = (p['text'] as String? ?? '').trim();
        break;
      }
    }

    if (text.isEmpty && imageFunctionCards.isNotEmpty) {
      // Gemini text boş ama function result kartları var
      return KoalaResponse(message: 'İşte odanız için önerilerim!', cards: imageFunctionCards);
    }
    if (text.isEmpty) {
      throw const FormatException('Empty response from Gemini');
    }

    // Gemini'nin JSON'unu parse et, function result kartlarını ekle
    final parsed = _parseResponse(text);
    if (imageFunctionCards.isNotEmpty) {
      final mergedCards = <KoalaCard>[];
      for (final card in parsed.cards) {
        // Function result'tan zaten oluşturulan kart tiplerini tekrarlama
        if (card.type != 'product_grid' && card.type != 'designer_card' && card.type != 'project_card') {
          mergedCards.add(card);
        }
      }
      mergedCards.addAll(imageFunctionCards);
      return KoalaResponse(message: parsed.message, cards: mergedCards);
    }
    return parsed;
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
    List<String>? allowedFunctions,
  }) async {

    // System instruction'ı ayır — contents'e kullanıcı mesajı olarak ekleme
    // Bu, history'nin system prompt ile kirlenmesini önler
    final systemInstruction = {'parts': [{'text': prompt}]};

    // Mesaj geçmişi hazırla (max 8 mesaj, max 6000 karakter)
    final contents = <Map<String, dynamic>>[];
    if (history != null) {
      final recent = history.length > 8 ? history.sublist(history.length - 8) : history;
      int totalChars = 0;
      const maxHistoryChars = 6000;
      for (final msg in recent.reversed) {
        final text = msg['content'] ?? '';
        if (totalChars + text.length > maxHistoryChars) break;
        totalChars += text.length;
        contents.insert(0, {
          'role': msg['role'] == 'user' ? 'user' : 'model',
          'parts': [{'text': text}],
        });
      }
    }
    // Son kullanıcı mesajı yoksa boş bir mesaj ekle (Gemini en az 1 user mesajı ister)
    if (contents.isEmpty || (contents.last['role'] != 'user')) {
      contents.add({'role': 'user', 'parts': [{'text': 'Devam et'}]});
    }

    // Son kullanıcı mesajında ürün/tasarımcı isteği var mı kontrol et
    final lastUserText = contents.isNotEmpty
        ? (contents.last['parts'] as List?)?.firstWhere(
            (p) => (p as Map).containsKey('text'), orElse: () => {'text': ''})['text'] as String? ?? ''
        : '';
    final shouldForceTools = RegExp(
      r'ürün öner|ürün bul|ürün ara|mobilya|tasarımcı öner|tasarımcı bul|uzman öner|uzman bul|dekorasyon öner',
      caseSensitive: false,
    ).hasMatch(lastUserText);

    // Function result'lardan oluşturulan kartları biriktir
    final functionResultCards = <KoalaCard>[];

    // Max 3 tur (ilk istek + 2 function call) — lite hızlı, 3 tur yeterli
    for (int turn = 0; turn < 3; turn++) {
      final payload = <String, dynamic>{
        'system_instruction': systemInstruction,
        'contents': contents,
        'tools': _toolDeclarations,
        'generationConfig': {
          'temperature': 0.7,
        },
      };
      // İlk turda function call'ı zorla:
      // 1. allowedFunctions varsa → belirli fonksiyona kısıtla (designerMatch gibi)
      // 2. shouldForceTools → ürün/tasarımcı keyword'ü algılandı
      // Sonraki turlarda AUTO moda dön (Gemini text response üretebilsin)
      if (turn == 0 && (allowedFunctions != null || shouldForceTools)) {
        final fcConfig = <String, dynamic>{'mode': 'ANY'};
        if (allowedFunctions != null) {
          fcConfig['allowed_function_names'] = allowedFunctions;
        }
        payload['tool_config'] = {'function_calling_config': fcConfig};
        debugPrint('KoalaAI: Forcing function call (allowed: ${allowedFunctions ?? "any"})');
      }

      debugPrint('KoalaAI: Tools request turn=$turn (${contents.length} messages)...');
      final response = await _client.post(
        _proxyUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 30));

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

        // Function sonucundan direkt kart oluştur — Gemini'nin JSON formatına güvenme
        final builtCards = _buildCardsFromFunctionResult(fnName, result);
        if (builtCards.isNotEmpty) {
          functionResultCards.addAll(builtCards);
        }

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

      // Gemini'nin text mesajını al, kartları function result'tan kullan
      String message = '';
      final cards = List<KoalaCard>.from(functionResultCards);

      if (text.isNotEmpty) {
        // JSON parse dene — Gemini doğru JSON döndüyse onun kartlarını da ekle
        final parsed = _parseResponse(text);
        message = parsed.message;
        // Sadece Gemini'nin kendi ürettiği kartları ekle (function result kartlarını tekrarlama)
        for (final card in parsed.cards) {
          if (card.type != 'product_grid' && card.type != 'designer_card' && card.type != 'project_card') {
            cards.add(card);
          }
        }

        // JSON parse başarısızsa düz metinden kart çıkarmayı dene
        if ((message.isEmpty || message.contains('aksilik oldu')) &&
            text.length > 20 && !text.trimLeft().startsWith('{')) {
          message = _sanitizeMessage(text);
          // Düz text'ten renk/stil kartları çıkarmayı dene
          if (cards.isEmpty) {
            cards.addAll(_extractCardsFromPlainText(text));
          }
        }
      }

      // Mesaj hala boşsa fallback
      if (message.isEmpty) {
        message = cards.isNotEmpty
            ? 'İşte senin için bulduklarım!'
            : 'Yanıt oluşturulamadı, lütfen tekrar deneyin.';
      }

      // Kartlar varsa mesajı kısa tut — uzun text'i kırp
      if (cards.isNotEmpty && message.length > 150) {
        // İlk 2 cümleyi al
        final sentences = message.split(RegExp(r'[.!?]\s+'));
        if (sentences.length > 2) {
          message = '${sentences.take(2).join('. ')}.';
        }
      }

      return KoalaResponse(message: message, cards: cards);
    }

    // Turlar tükendi — toplanan kartlar varsa onları göster
    debugPrint('KoalaAI: Turns exhausted, functionResultCards=${functionResultCards.length}');
    if (functionResultCards.isNotEmpty) {
      return KoalaResponse(message: 'İşte senin için bulduklarım!', cards: functionResultCards);
    }
    return KoalaResponse(message: 'İşlem tamamlanamadı, lütfen tekrar deneyin.', cards: []);
  }

  /// Function result'tan direkt kart oluştur — Gemini'nin JSON formatına güvenme
  List<KoalaCard> _buildCardsFromFunctionResult(
    String fnName, Map<String, dynamic> result,
  ) {
    switch (fnName) {
      case 'search_products':
        final products = result['products'] as List<dynamic>? ?? [];
        if (products.isEmpty) return [];
        return [KoalaCard(type: 'product_grid', data: {
          'title': 'Önerilen Ürünler',
          'products': products.map((p) {
            final pm = p as Map<String, dynamic>;
            return {
              'name': pm['name'] ?? '',
              'price': pm['price'] ?? '',
              'shop_name': pm['shop_name'] ?? '',
              'image_url': pm['image_url'] ?? '',
              'url': pm['link'] ?? pm['url'] ?? '',
            };
          }).toList(),
        })];

      case 'search_designers':
        final designers = result['designers'] as List<dynamic>? ?? [];
        if (designers.isEmpty) return [];
        // DesignerCards widget tek kart içinde designers[] array bekler
        return [KoalaCard(type: 'designer_card', data: {
          'designers': designers,
        })];

      case 'search_projects':
        final projects = result['projects'] as List<dynamic>? ?? [];
        if (projects.isEmpty) return [];
        return projects.map((p) =>
          KoalaCard(type: 'project_card', data: p as Map<String, dynamic>),
        ).toList();

      default:
        return [];
    }
  }

  /// Düz text'ten renk ve stil kartları çıkar — Gemini JSON vermediğinde fallback
  List<KoalaCard> _extractCardsFromPlainText(String text) {
    final cards = <KoalaCard>[];

    // HEX renk kodlarını bul (#RRGGBB veya #RGB)
    final hexPattern = RegExp(r'#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b');
    final hexMatches = hexPattern.allMatches(text).toList();

    if (hexMatches.length >= 3) {
      // Renk isimleri ve kullanım bilgilerini çıkarmaya çalış
      final colors = <Map<String, String>>[];
      for (final match in hexMatches.take(6)) {
        final hex = '#${match.group(1)!}';
        // Hex'in etrafındaki text'ten isim çıkar
        final start = (match.start - 40).clamp(0, text.length);
        final end = (match.end + 40).clamp(0, text.length);
        final context = text.substring(start, end);

        // "İsim (#HEX)" veya "**İsim**: #HEX" pattern'ini ara
        final nameMatch = RegExp(r'(?:\*\*)?([A-Za-zÀ-ÿçğıöşüÇĞİÖŞÜ\s]{2,25})(?:\*\*)?[\s:–\-]*' + RegExp.escape(hex))
            .firstMatch(context);
        final name = nameMatch?.group(1)?.trim() ?? 'Renk ${colors.length + 1}';

        // Kullanım bilgisi: hex'ten sonraki text
        final afterHex = text.substring(match.end, (match.end + 80).clamp(0, text.length));
        final usageMatch = RegExp(r'[:\-–]\s*(.{5,60}?)(?:\.|$|\n)').firstMatch(afterHex);
        final usage = usageMatch?.group(1)?.trim() ?? '';

        colors.add({
          'name': name,
          'hex': hex.length == 4 ? '#${hex[1]}${hex[1]}${hex[2]}${hex[2]}${hex[3]}${hex[3]}' : hex,
          'usage': usage,
        });
      }

      cards.add(KoalaCard(type: 'color_palette', data: {
        'title': 'Önerilen Renk Paleti',
        'colors': colors,
      }));
    }

    return cards;
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
      // Token limiti: toplam 12000 karakter
      int charBudget = 12000;
      final trimmed = <Map<String, String>>[];
      for (int i = recent.length - 1; i >= 0 && charBudget > 0; i--) {
        final content = recent[i]['content'] ?? '';
        if (content.length > charBudget) break;
        charBudget -= content.length;
        trimmed.insert(0, recent[i]);
      }
      for (final msg in trimmed) {
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
