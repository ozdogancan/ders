import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/config/env.dart';
import '../core/constants/koala_prompts.dart';
import 'koala_tool_handler.dart';
import 'taste_profile_service.dart';

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
  // Foto-bazlı dar-amaçlı intent'ler — tool çağırmaz, sadece ilgili kart üretir
  colorPaletteFromPhoto,
  styleAnalysisFromPhoto,
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
          'description': 'Evlumba tasarım projelerini (iç mekan fotoğrafları + tasarımcı) ara. '
              'ZORUNLU tetikleyiciler: "salon göster/bul", "bana X göster", "oturma odası örneği", '
              '"yatak odası göster", "mutfak göster", "proje göster", "örnek göster", "ilham ver", '
              '"tasarım göster", "nasıl dekore etmeliyim" gibi ilham/örnek istekleri. '
              'Bu isteklerde ASLA uydurma proje adları dönme; MUTLAKA bu fonksiyonu çağır. '
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
          'description': 'Evlumba iç mimar / dekoratör tasarımcılarını ara. Kullanıcı '
              'oda/ev için profesyonel yardım istediğinde, belirli bir şehirdeki '
              'tasarımcıları aradığında veya "uzman öner" dediğinde çağır. '
              'Grafik tasarımcı, logo/web tasarımcısı vb. iç mekân dışı uzmanlıklar '
              'otomatik dışlanır.',
          'parameters': {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'description': 'Tasarımcı adı. Boş bırakılabilir — oda/stil önerisi '
                    'yapıyorsan query GEREKMEZ, sadece room_type/style ver.',
              },
              'city': {
                'type': 'string',
                'description': 'Şehir filtresi. Örnekler: İstanbul, Ankara, İzmir',
              },
              'room_type': {
                'type': 'string',
                'description': 'Oda tipi: salon, yatak_odasi, mutfak, banyo, ofis, cocuk_odasi. '
                    'Kullanıcı belirli bir oda için uzman istiyorsa mutlaka ver.',
              },
              'style': {
                'type': 'string',
                'description': 'Stil anahtarı: modern, minimalist, klasik, iskandinav, '
                    'endüstriyel, boho, rustik, art_deco vb. Kullanıcının fotoğraf '
                    'analizinden ya da tercihinden bilinen stili geçir.',
              },
              'min_projects': {
                'type': 'integer',
                'description': 'Tasarımcının portfolyosunda en az kaç geçerli proje olmalı. '
                    'Kalite filtresi — varsayılan 2. Yeterli sonuç dönmezse 1\'e düşebilir.',
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

  // Cached taste profile — refreshed once per message send (≤10ms overhead).
  String? _tasteHint;
  DateTime? _tasteHintAt;

  /// Warm the taste hint cache if stale (>60s). Safe to await each ask.
  Future<void> _refreshTasteHintIfStale() async {
    final now = DateTime.now();
    if (_tasteHintAt != null &&
        now.difference(_tasteHintAt!).inSeconds < 60) {
      return;
    }
    try {
      final profile = await TasteProfileService.computeProfile();
      _tasteHint = profile.toPromptHint();
      _tasteHintAt = now;
    } catch (_) {
      _tasteHint = null;
      _tasteHintAt = now;
    }
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
      tasteHint: _tasteHint,
    );
    if (block.isEmpty) return prompt;
    return prompt + block;
  }

  /// Builds the system_instruction text for ALL Gemini calls.
  /// Includes Koala identity + user preferences — so every call sees the same base.
  String _buildSystemInstructionText({bool includeProfile = true}) {
    if (!includeProfile) return KoalaPrompts.systemBase;
    return KoalaPrompts.buildSystemInstruction(
      style: _userPrefs['style'],
      colors: _userPrefs['colors'],
      room: _userPrefs['room'],
      budget: _userPrefs['budget'],
      dislikedStyles: _userPrefs['dislikedStyles'],
      dislikedColors: _userPrefs['dislikedColors'],
      likedDetailsText: _userPrefs['likedDetailsText'],
      tasteHint: _tasteHint,
    );
  }

  /// Product intent detection — used to decide whether to force search_products
  /// on photo flow (mode=ANY) vs let the model decide (mode=AUTO).
  static final RegExp _productIntentRegex = RegExp(
    r'\b(öner|önerir|bul|göster|arıyor|bakıyor|lazım|tavsiye|'
    r'ürün|mobilya|halı|kilim|masa|sandalye|kanepe|koltuk|lamba|avize|'
    r'perde|yatak|dolap|gardırop|komodin|raf|kitaplık|sehpa|puf|berjer|'
    r'tv\s*ünitesi|yemek\s*masası|abajur|saksı|ayna|tablo|ottoman)\b',
    caseSensitive: false,
  );
  bool _isProductRequest(String? text) {
    if (text == null || text.trim().isEmpty) return false;
    return _productIntentRegex.hasMatch(text);
  }

  /// JSON response intents — these return structured JSON (responseMimeType).
  /// Casual chat returns plain text, NOT JSON.
  static const Set<KoalaIntent> _jsonIntents = {
    KoalaIntent.styleExplore,
    KoalaIntent.roomRenovation,
    KoalaIntent.colorAdvice,
    KoalaIntent.designerMatch,
    KoalaIntent.budgetPlan,
    KoalaIntent.beforeAfter,
    KoalaIntent.pollResult,
    KoalaIntent.photoAnalysis,
    KoalaIntent.colorPaletteFromPhoto,
    KoalaIntent.styleAnalysisFromPhoto,
  };

  /// Main entry — with conversation history
  Future<KoalaResponse> askWithIntent({
    required KoalaIntent intent,
    Map<String, String> params = const {},
    String? freeText,
    Uint8List? photo,
    List<Map<String, String>>? history,
  }) async {
    await _refreshTasteHintIfStale();
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
            room: params['room'],
          );
        } else {
          prompt = KoalaPrompts.designerMatch(
            room: params['room'],
            style: params['style'],
            city: params['city'],
          );
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
        {
          final txt = freeText ?? 'Merhaba';
          // Dart-side intent detection → TOOL_HINT
          String? toolHint;
          if (_isProductRequest(txt)) {
            toolHint = 'search_products';
          } else if (RegExp(r'(tasarımcı|iç\s*mimar|mimar|uzman)', caseSensitive: false).hasMatch(txt)) {
            toolHint = 'search_designers';
          } else if (RegExp(r'(proje|ilham|örnek|göster)', caseSensitive: false).hasMatch(txt)) {
            toolHint = 'search_projects';
          }
          prompt = KoalaPrompts.freeChat(txt, toolHint: toolHint);
        }
      case KoalaIntent.colorPaletteFromPhoto:
        prompt = KoalaPrompts.colorPaletteFromPhoto();
      case KoalaIntent.styleAnalysisFromPhoto:
        prompt = KoalaPrompts.styleAnalysisFromPhoto();
    }

    // Inject user profile — fotoğraf analizinde profil ekleme (bias yaratır)
    // photoAnalysis ve foto-bazlı dar intent'lerde AI odanın gerçek halini yorumlamalı
    const noProfileIntents = {
      KoalaIntent.photoAnalysis,
      KoalaIntent.colorPaletteFromPhoto,
      KoalaIntent.styleAnalysisFromPhoto,
    };
    if (!noProfileIntents.contains(intent)) {
      prompt = _withProfile(prompt);
    }

    final isJsonIntent = _jsonIntents.contains(intent);

    if (photo != null) {
      // Dar-amaçlı foto intent'lerde tool'ları kapat — yalnız ilgili kart üretilsin
      final disableTools = intent == KoalaIntent.colorPaletteFromPhoto ||
          intent == KoalaIntent.styleAnalysisFromPhoto;
      return _callGeminiWithImage(
        prompt: prompt,
        imageBytes: photo,
        disableTools: disableTools,
        userText: freeText,
        jsonMode: isJsonIntent,
      );
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
      return _callGeminiWithTools(
        prompt: prompt,
        history: history,
        initialAllowedFunctions: allowedFunctions,
        userText: freeText,
        jsonMode: isJsonIntent,
      );
    }

    return _callGemini(
      prompt: prompt,
      history: history,
      userText: freeText,
      jsonMode: isJsonIntent,
    );
  }

  /// Builds prompt with user profile injected (for streaming usage).
  String buildPromptForFreeChat(String text) =>
    _withProfile(KoalaPrompts.freeChat(text));

  // Note: freeChat prompt artık minimal; system_instruction tüm ağır kısmı taşıyor.

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
      'system_instruction': {'parts': [{'text': _buildSystemInstructionText()}]},
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

  Future<KoalaResponse> _callGemini({
    required String prompt,
    List<Map<String, String>>? history,
    String? userText,
    bool jsonMode = false,
  }) async {
    // system_instruction = Koala kimliği + kullanıcı profili + intent-specific prompt
    final systemText = '${_buildSystemInstructionText()}\n\n${prompt.trim()}';
    final systemInstruction = {'parts': [{'text': systemText}]};
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

    // Fix: YENİ user mesajı contents'e somut olarak eklensin
    final userMsg = (userText ?? '').trim();
    if (userMsg.isNotEmpty) {
      contents.add({'role': 'user', 'parts': [{'text': userMsg}]});
    } else if (contents.isEmpty || (contents.last['role'] != 'user')) {
      // Gemini en az 1 user mesajı ister — hiç user mesajı yoksa fallback
      contents.add({'role': 'user', 'parts': [{'text': 'Devam et'}]});
    }

    final generationConfig = <String, dynamic>{
      'temperature': 0.7,
      'maxOutputTokens': 2048,
    };
    if (jsonMode) {
      generationConfig['responseMimeType'] = 'application/json';
    }

    final payload = {
      'system_instruction': systemInstruction,
      'contents': contents,
      'generationConfig': generationConfig,
    };

    debugPrint('KoalaAI: Sending request via proxy (${contents.length} messages, jsonMode=$jsonMode)...');
    final response = await _client.post(_proxyUri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload))
        .timeout(const Duration(seconds: 30));

    if (response.statusCode >= 300) {
      debugPrint('KoalaAI ERROR ${response.statusCode}: ${_truncForLog(response.body, 300)}');
      throw Exception('Gemini failed: ${response.statusCode}');
    }

    return _parseResponse(_extractText(response.body), jsonMode: jsonMode);
  }

  /// Safe substring for log lines.
  String _truncForLog(String s, [int n = 200]) =>
      s.length > n ? s.substring(0, n) : s;

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

  Future<KoalaResponse> _callGeminiWithImage({
    required String prompt,
    required Uint8List imageBytes,
    bool disableTools = false,
    String? userText,
    bool jsonMode = false,
  }) async {
    // Moondream devre dışı — API key 401 veriyor, 8s boşa bekleme yapıyordu
    // final preAnalysis = await _moondreamPreAnalyze(imageBytes);
    final mimeType = _detectMimeType(imageBytes);

    // Moondream devre dışı — API key 401, 8s boşa bekleme
    // Gemini 2.5 Flash image'ı doğrudan analiz ediyor
    String enrichedPrompt = prompt;

    // Akıllı mode seçimi: user gerçekten ürün istiyorsa ANY ile zorla,
    // aksi halde AUTO ile modele bırak (halüsinasyon koruması zaten mevcut).
    final wantsProducts = _isProductRequest(userText);

    // ── Tur 1: Görsel + tools ile Gemini çağır ──
    final imageB64 = base64Encode(imageBytes);
    final systemText = _buildSystemInstructionText();
    final generationConfig = <String, dynamic>{
      'temperature': 0.7,
      'maxOutputTokens': 4096,
    };
    if (jsonMode && disableTools) {
      // Tools açıkken responseMimeType=application/json uyumsuzluk yaratır.
      generationConfig['responseMimeType'] = 'application/json';
    }
    final firstPayload = <String, dynamic>{
      'system_instruction': {'parts': [{'text': systemText}]},
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': enrichedPrompt},
            {'inline_data': {'mime_type': mimeType, 'data': imageB64}},
          ]
        }
      ],
      'generationConfig': generationConfig,
    };
    if (!disableTools) {
      firstPayload['tools'] = _toolDeclarations;
      if (wantsProducts) {
        // Kullanıcı açıkça ürün istedi → mode=ANY ile zorla, halüsinasyonu engelle.
        firstPayload['tool_config'] = {
          'function_calling_config': {
            'mode': 'ANY',
            'allowed_function_names': ['search_products'],
          },
        };
        debugPrint('KoalaAI: Image — product intent detected, mode=ANY');
      } else {
        // Kullanıcı ürün istemediyse modele bırak; halüsinasyon stripping zaten aktif.
        firstPayload['tool_config'] = {
          'function_calling_config': {'mode': 'AUTO'},
        };
        debugPrint('KoalaAI: Image — no product intent, mode=AUTO');
      }
    } else {
      debugPrint('KoalaAI: Image call with tools DISABLED (narrow-intent)');
    }

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
      debugPrint('KoalaAI: Image FAIL: ${response.statusCode} — ${_truncForLog(response.body, 300)}');
      throw Exception('Fotoğraf analizi başarısız (hata: ${response.statusCode}). Lütfen tekrar dene.');
    }

    var data = jsonDecode(response.body) as Map<String, dynamic>;
    var candidates = data['candidates'] as List<dynamic>? ?? [];
    if (candidates.isEmpty) throw const FormatException('No candidates');

    var content = (candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>? ?? {};
    var parts = content['parts'] as List<dynamic>? ?? [];

    // Paralel function call desteği — tüm functionCall part'larını topla
    final functionCalls = parts
        .whereType<Map<String, dynamic>>()
        .where((p) => p.containsKey('functionCall'))
        .toList();

    // ── Tur 2: Function call varsa çalıştır, sonuçla tekrar çağır (IMAGE OLMADAN) ──
    final imageFunctionCards = <KoalaCard>[];
    if (functionCalls.isNotEmpty) {
      // Paralel çalıştır
      final resolved = await Future.wait(functionCalls.map((p) async {
        final fc = p['functionCall'] as Map<String, dynamic>;
        final fnName = fc['name'] as String;
        final fnArgs = (fc['args'] as Map<String, dynamic>?) ?? {};
        debugPrint('KoalaAI: Image function call → $fnName($fnArgs)');
        final result = await KoalaToolHandler.handle(fnName, fnArgs);
        return {'name': fnName, 'args': fnArgs, 'result': result};
      }));

      // Function result'tan direkt kart oluştur
      for (final r in resolved) {
        imageFunctionCards.addAll(_buildCardsFromFunctionResult(
          r['name'] as String, r['result'] as Map<String, dynamic>));
      }

      // 2. tur: image yok, sadece text context + function call sonuçları
      final modelParts = resolved
          .map((r) => {'functionCall': {'name': r['name'], 'args': r['args']}})
          .toList();
      final responseParts = resolved
          .map((r) => {'functionResponse': {'name': r['name'], 'response': r['result']}})
          .toList();

      final turn2Gen = <String, dynamic>{
        'temperature': 0.7,
        'maxOutputTokens': 2048,
      };
      if (jsonMode) turn2Gen['responseMimeType'] = 'application/json';

      final turn2Payload = {
        'system_instruction': {'parts': [{'text': systemText}]},
        'contents': [
          // Orijinal kullanıcı mesajı (image olmadan, sadece text)
          {'role': 'user', 'parts': [{'text': enrichedPrompt}]},
          // Model'in function call'ları (hepsi tek turn'de)
          {'role': 'model', 'parts': modelParts},
          // Function sonuçları (hepsi tek turn'de)
          {'role': 'user', 'parts': responseParts},
        ],
        'tools': _toolDeclarations,
        'tool_config': {'function_calling_config': {'mode': 'NONE'}},
        'generationConfig': turn2Gen,
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
      // Gemini text boş ama function result kartları var — mesaj alanını boş bırak
      return KoalaResponse(message: '', cards: imageFunctionCards);
    }
    if (text.isEmpty) {
      // Exception yerine boş yanıt — kullanıcıya "aksilik" mesajı göstermek yerine sessiz ol
      return const KoalaResponse(message: '', cards: []);
    }

    // Gemini'nin JSON'unu parse et, function result kartlarını ekle
    final parsed = _parseResponse(text, jsonMode: jsonMode);
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
    // HALÜSİNASYON KORUMASI: search_products/find_designers çağrılmamışsa
    // Gemini'nin ürettiği product_grid/designer_card kartları halüsinasyondur
    // (gerçek evlumba verisi değil). Bunları temizle.
    final safeCards = parsed.cards
        .where((c) => c.type != 'product_grid' && c.type != 'designer_card' && c.type != 'project_card')
        .toList();
    if (safeCards.length != parsed.cards.length) {
      debugPrint('KoalaAI: Stripped ${parsed.cards.length - safeCards.length} hallucinated product/designer cards (no function call)');
    }
    return KoalaResponse(message: parsed.message, cards: safeCards);
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
    List<String>? initialAllowedFunctions,
    String? userText,
    bool jsonMode = false,
  }) async {
    var allowedFunctions = initialAllowedFunctions;

    // System instruction: Koala kimliği + kullanıcı profili + intent-specific prompt
    // Bu, history'nin system prompt ile kirlenmesini önler.
    final systemText = '${_buildSystemInstructionText()}\n\n${prompt.trim()}';
    final systemInstruction = {'parts': [{'text': systemText}]};

    // Mesaj geçmişi hazırla (max 8 mesaj, max 6000 karakter)
    // Fix C: History'deki önceki functionCall/functionResponse part'larını temizle
    // Bunlar yeni user mesajı için alakasız ve Gemini'yi yanıltır
    final contents = <Map<String, dynamic>>[];
    if (history != null) {
      final recent = history.length > 8 ? history.sublist(history.length - 8) : history;
      int totalChars = 0;
      const maxHistoryChars = 6000;
      for (final msg in recent.reversed) {
        final text = msg['content'] ?? '';
        if (totalChars + text.length > maxHistoryChars) break;
        totalChars += text.length;
        // Sadece text part'ı ekle — functionCall/functionResponse geçmişten çıkar
        contents.insert(0, {
          'role': msg['role'] == 'user' ? 'user' : 'model',
          'parts': [{'text': text}],
        });
      }
    }
    // YENİ user mesajı contents'e somut olarak eklensin
    final userMsg = (userText ?? '').trim();
    if (userMsg.isNotEmpty) {
      contents.add({'role': 'user', 'parts': [{'text': userMsg}]});
    } else if (contents.isEmpty || (contents.last['role'] != 'user')) {
      // Gerçekten hiç user mesajı yoksa fallback
      contents.add({'role': 'user', 'parts': [{'text': 'Devam et'}]});
    }

    // Son kullanıcı mesajında ürün/tasarımcı isteği var mı kontrol et
    final lastUserText = contents.isNotEmpty
        ? (contents.last['parts'] as List?)?.firstWhere(
            (p) => (p as Map).containsKey('text'), orElse: () => {'text': ''})['text'] as String? ?? ''
        : '';

    // Fix B: Casual-chat escape — kısa selamlama/dolgu sözcükleri için tool çağırma
    final designKeywords = RegExp(
      r'\b(oda|salon|banyo|mutfak|mobilya|renk|ürün|tasarım|tasarımcı|mimar|uzman|stil|boya|duvar|zemin|koltuk|kanepe|masa|sandalye|yatak|dolap|fotoğraf|foto|resim)\b',
      caseSensitive: false,
    );
    final isCasualGreeting = RegExp(
      r'^(naber|nbr|nasılsın|nslsn|selam|merhaba|mrb|sa|selamün|aleyküm|hi|hey|hello|yoo|teşekkürler|teşekkür|tşk|sağol|sağ ol|eyvallah|tamam|tmm|peki|ok|okay|hmm|hmmm|evet|hayır|yes|no|güzel|harika|süper|iyi|iyiyim|sen)[\s\!\?\.\,]*$',
      caseSensitive: false,
    ).hasMatch(lastUserText.trim());
    final isShortNonDesign = lastUserText.trim().split(RegExp(r'\s+')).length <= 3 &&
        !designKeywords.hasMatch(lastUserText);
    // ÖNEMLİ: initialAllowedFunctions varsa (designerMatch gibi intent'li çağrı)
    // casual escape'e ASLA düşme — kullanıcı chip'e bastı, function call mutlaka çalışsın.
    // Chip handler user mesajını _history'ye eklemediği için lastUserText burada
    // "Devam et" default'una düşüp yanlışlıkla casual path'e sapıyordu (bug: chip'ten
    // "Uzman öner" deyince "Harika, hazırım!" gibi saçma yanıt).
    final isCasualMessage = initialAllowedFunctions == null &&
        (isCasualGreeting || isShortNonDesign) &&
        !designKeywords.hasMatch(lastUserText);

    if (isCasualMessage) {
      debugPrint('KoalaAI: Casual message detected (v2) — plain text path: "$lastUserText"');
      // Fix B-v2: JSON parser'a hiç gitmeden plain text yanıt al. Casual prompt JSON
      // üretmiyor; eski yol _parseResponse'a düşüyordu → "aksilik oldu" fallback'i.
      final casualPrompt =
          'Sen Koala\'sın — samimi bir iç mimari asistan. Kullanıcı: "$lastUserText". '
          'Çok kısa, dostça, 1-2 cümlelik TÜRKÇE bir cevap ver. '
          'Örn: "Selam! Bir oda fotoğrafı paylaşırsan birlikte bakalım 🐨". '
          'Kart, liste, JSON, başlık verme. Sadece düz metin.';
      try {
        final text = await askPlainText(casualPrompt);
        final clean = text.trim();
        if (clean.isNotEmpty) {
          return KoalaResponse(message: _sanitizeMessage(clean), cards: const []);
        }
      } catch (e) {
        debugPrint('KoalaAI: Casual plain-text failed: $e — using static fallback');
      }
      // Son çare: Gemini cevap vermediyse sabit samimi yanıt
      return const KoalaResponse(
        message: 'Selam! 🐨 Bir oda fotoğrafı paylaşırsan sana renk, stil ve ürün önerileri yapabilirim.',
        cards: [],
      );
    }

    // Fix E: Belirsiz ürün isteği → oda sorusu sor
    final isVagueProductRequest = RegExp(
      r'\b(odama|evime|bana|burama|şuraya)\s+(ürün|bir şey|öneri|tavsiye)\b',
      caseSensitive: false,
    ).hasMatch(lastUserText);
    if (isVagueProductRequest) {
      debugPrint('KoalaAI: Vague product request, asking for room type');
      return KoalaResponse(
        message: 'Hangi oda için öneri istiyorsun?',
        cards: [KoalaCard(type: 'question_chips', data: {
          'options': ['🛋️ Salon', '🛏️ Yatak odası', '🍳 Mutfak', '🚿 Banyo', '📚 Çalışma odası'],
        })],
      );
    }

    // Fix E: Belirsiz tasarımcı isteği (stil bilinmiyor) → stil sorusu sor
    final isVagueDesignerRequest = RegExp(
      r'(iç mimar|tasarımcı|mimar).*(bana göre|benim için|bana uygun)|bana göre.*(iç mimar|tasarımcı|mimar)',
      caseSensitive: false,
    ).hasMatch(lastUserText);
    if (isVagueDesignerRequest && !_userPrefs.containsKey('style')) {
      debugPrint('KoalaAI: Vague designer request, no style profile — asking for style');
      return KoalaResponse(
        message: 'Hangi stilde tasarımcı arıyorsun?',
        cards: [KoalaCard(type: 'question_chips', data: {
          'options': ['Modern', 'Minimal', 'Skandinav', 'Bohem', 'Klasik', 'Endüstriyel'],
        })],
      );
    }

    // Tasarımcı/iç mimar araması — fiil veya net niyet ile birlikte
    final isDesignerRequest = RegExp(
      r'(tasarımcı|mimar)\s+(öner|bul|ara|tavsiye|seç|lazım|arıyor|bakıyor)|'
      r'(iç\s*mimar)|'
      r'(uzman)\s+(öner|bul|tavsiye|ara)|'
      r'(bana|bize|bana göre|bize göre)\s+.*(tasarımcı|mimar)|'
      r'(tasarımcı|mimar).*(bul|öner|seç|tavsiye|uygun)',
      caseSensitive: false,
    ).hasMatch(lastUserText);
    // Ürün isteği: fiil + isim ya da doğrudan mobilya/dekor nesnesi
    // "kanepe arıyorum", "koltuk önerir misin", "mutfakta masa lazım" gibi serbest ifadeleri de yakalar
    // Ürün isteği: fiil + isim ya da somut mobilya/dekor nesnesi
    // "kanepe arıyorum", "odama koltuk bakıyorum", "mutfakta masa lazım" da yakalanır
    final isProductRequest = RegExp(
      r'(ürün|mobilya|dekorasyon)\s+(öner|bul|ara|tavsiye|lazım|arıyor|bakıyor)|'
      r'\b(koltuk|kanepe|sehpa|masa|sandalye|aydınlatma|lamba|avize|halı|kilim|perde|yatak|dolap|gardırop|komodin|raf|kitaplık|vitrin|puf|berjer|tv\s*ünitesi|yemek\s*masası|abajur|saksı|ayna|tablo|ottoman)\b',
      caseSensitive: false,
    ).hasMatch(lastUserText);
    // Proje/ilham isteği — "salon göster/bul", "yatak odası göster", "proje göster",
    // "örnek göster", "bana X göster", "ilham ver" vb.
    final isProjectRequest = RegExp(
      r'\b(salon|oturma\s*odası|yatak\s*odası|mutfak|banyo|çalışma\s*odası|çocuk\s*odası|ofis|antre|balkon)\s+(göster|bul|ara|bak|örnek|istiyor|lazım)|'
      r'\b(proje|örnek|tasarım|ilham)\s+(göster|ver|öner|bul|istiyor|lazım|bak)|'
      r'bana\s+(salon|oturma|yatak|mutfak|banyo|ofis|çocuk|antre|balkon|proje|örnek|ilham|tasarım)|'
      r'\b(ilham\s*ver|proje\s*bak|tasarım\s*bak)',
      caseSensitive: false,
    ).hasMatch(lastUserText);
    final shouldForceTools =
        isDesignerRequest || isProductRequest || isProjectRequest;

    // freeChat'te de keyword'den doğru fonksiyonu kısıtla
    if (allowedFunctions == null && isDesignerRequest) {
      allowedFunctions = ['search_designers'];
    } else if (allowedFunctions == null && isProductRequest) {
      allowedFunctions = ['search_products'];
    } else if (allowedFunctions == null && isProjectRequest) {
      allowedFunctions = ['search_projects'];
    }

    // Function result'lardan oluşturulan kartları biriktir
    final functionResultCards = <KoalaCard>[];
    // Tekrar eden önerileri filtrele — aynı sohbette aynı öğeyi iki kere gösterme
    final seenProjectIds = <String>{};
    final seenDesignerIds = <String>{};
    final seenProductNames = <String>{};

    // Max 3 tur (ilk istek + 2 function call) — lite hızlı, 3 tur yeterli
    for (int turn = 0; turn < 3; turn++) {
      // jsonMode sadece son sentez turlarında (function call üretmeyen turda) güvenli.
      // İlk turda function call'ı zorlarken responseMimeType kullanmıyoruz.
      final genConfig = <String, dynamic>{
        'temperature': 0.7,
        'maxOutputTokens': jsonMode ? 2048 : 1024,
      };
      if (jsonMode && turn > 0) {
        genConfig['responseMimeType'] = 'application/json';
      }
      final payload = <String, dynamic>{
        'system_instruction': systemInstruction,
        'contents': contents,
        'tools': _toolDeclarations,
        'generationConfig': genConfig,
      };
      // İlk turda function call'ı zorla:
      // 1. allowedFunctions varsa → belirli fonksiyona kısıtla (designerMatch gibi)
      // 2. shouldForceTools → ürün/tasarımcı keyword'ü algılandı
      // Fix D: Sonraki turlarda NONE moda geç — Gemini sadece text sentezi yapsın, yeni function call açma
      if (turn == 0 && (allowedFunctions != null || shouldForceTools)) {
        final fcConfig = <String, dynamic>{'mode': 'ANY'};
        if (allowedFunctions != null) {
          fcConfig['allowed_function_names'] = allowedFunctions;
        }
        payload['tool_config'] = {'function_calling_config': fcConfig};
        debugPrint('KoalaAI: Forcing function call (allowed: ${allowedFunctions ?? "any"})');
      } else if (turn > 0) {
        // Sentez turu — yeni function call açılmasın
        payload['tool_config'] = {'function_calling_config': {'mode': 'NONE'}};
        debugPrint('KoalaAI: Turn $turn synthesis mode — function calls disabled');
      }

      debugPrint('KoalaAI: Tools request turn=$turn (${contents.length} messages)...');
      final response = await _client.post(
        _proxyUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode >= 300) {
        debugPrint('KoalaAI ERROR ${response.statusCode}: ${_truncForLog(response.body, 300)}');
        throw Exception('Gemini failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>? ?? [];
      if (candidates.isEmpty) throw const FormatException('No candidates');

      final content = (candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>? ?? {};
      final parts = content['parts'] as List<dynamic>? ?? [];

      // Paralel function call desteği — tüm functionCall part'larını topla
      final functionCallParts = parts
          .whereType<Map<String, dynamic>>()
          .where((p) => p.containsKey('functionCall'))
          .toList();

      if (functionCallParts.isNotEmpty) {
        // Hepsini paralel çalıştır
        final resolved = await Future.wait(functionCallParts.map((p) async {
          final fc = p['functionCall'] as Map<String, dynamic>;
          final fnName = fc['name'] as String;
          final fnArgs = (fc['args'] as Map<String, dynamic>?) ?? {};
          debugPrint('KoalaAI: Function call → $fnName($fnArgs)');
          final result = await KoalaToolHandler.handle(fnName, fnArgs)
              .timeout(const Duration(seconds: 15), onTimeout: () {
            debugPrint('KoalaAI: Function handler timeout for $fnName');
            return <String, dynamic>{'error': 'timeout', 'message': 'Veri alınamadı'};
          });
          debugPrint('KoalaAI: Function result → ${result.keys.toList()}');
          return {'name': fnName, 'args': fnArgs, 'result': result};
        }));

        // Tüm sonuçları dedup + kart üretimi
        for (final r in resolved) {
          final fnName = r['name'] as String;
          final result = r['result'] as Map<String, dynamic>;
          _deduplicateResult(fnName, result, seenProjectIds, seenDesignerIds, seenProductNames);
          final builtCards = _buildCardsFromFunctionResult(fnName, result);
          if (builtCards.isNotEmpty) {
            functionResultCards.addAll(builtCards);
          }
        }

        // Boş sonuç durumu: tek fn için eski davranışı koru
        if (resolved.length == 1) {
          final r = resolved.first;
          final fnName = r['name'] as String;
          final result = r['result'] as Map<String, dynamic>;
          final builtCards = _buildCardsFromFunctionResult(fnName, result);
          final isEmpty = (fnName == 'search_products' && ((result['products'] as List?)?.isEmpty ?? true)) ||
              (fnName == 'search_designers' && ((result['designers'] as List?)?.isEmpty ?? true)) ||
              (fnName == 'search_projects' && ((result['projects'] as List?)?.isEmpty ?? true));
          if (isEmpty && builtCards.isNotEmpty) {
            String emptyMsg;
            if (fnName == 'search_products') {
              final roomType = (result['room_type'] as String? ?? 'oda').toLowerCase();
              emptyMsg = '$roomType için hangi tür ürün? Seç, daha isabetli arayayım.';
            } else if (fnName == 'search_designers') {
              emptyMsg = 'Hangi stilde tasarımcı arıyorsun?';
            } else {
              emptyMsg = 'Farklı bir seçenek dene.';
            }
            return KoalaResponse(message: emptyMsg, cards: builtCards);
          }
        }

        // Model'in function call'larını tek turn'de history'ye ekle
        contents.add({
          'role': 'model',
          'parts': resolved
              .map((r) => {'functionCall': {'name': r['name'], 'args': r['args']}})
              .toList(),
        });
        // Function sonuçlarını tek user turn'ünde ekle
        contents.add({
          'role': 'user',
          'parts': resolved
              .map((r) => {'functionResponse': {'name': r['name'], 'response': r['result']}})
              .toList(),
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
      final hadFunctionCall = functionResultCards.isNotEmpty;

      if (text.isNotEmpty) {
        // JSON parse dene — Gemini doğru JSON döndüyse onun kartlarını da ekle
        final parsed = _parseResponse(text, jsonMode: jsonMode);
        message = parsed.message;
        // HALÜSİNASYON KORUMASI: Gerçek function call yapılmadıysa
        // model'in ürettiği product_grid/designer_card/project_card kartları
        // halüsinasyon olabilir — strip et.
        for (final card in parsed.cards) {
          final isRealDataCard = card.type == 'product_grid' ||
              card.type == 'designer_card' ||
              card.type == 'project_card';
          if (!isRealDataCard) {
            cards.add(card);
          } else if (hadFunctionCall) {
            // Function call yapıldıysa zaten functionResultCards'a eklendi,
            // Gemini'nin kendi ürettiği tekrarını atla.
            continue;
          } else {
            debugPrint('KoalaAI: Stripped hallucinated ${card.type} (no function call)');
          }
        }

        // JSON parse başarısızsa düz metinden kart çıkarmayı dene
        if (message.isEmpty && text.length > 20 && !text.trimLeft().startsWith('{')) {
          message = _sanitizeMessage(text);
          if (cards.isEmpty) {
            cards.addAll(_extractCardsFromPlainText(text));
          }
        }
      }

      // Mesaj boşsa: klişe fallback YOK — UI boş mesajı bar'ı gizleyecek.
      // (Eski: "İşte senin için bulduklarım!" — klişe, her zaman aynı.)

      // Kartlar varsa mesajı kısa tut — uzun text'i kırp
      if (cards.isNotEmpty && message.length > 150) {
        final sentences = message.split(RegExp(r'[.!?]\s+'));
        if (sentences.length > 2) {
          message = '${sentences.take(2).join('. ')}.';
        }
      }

      return KoalaResponse(message: message, cards: cards);
    }

    // Turlar tükendi — toplanan kartlar varsa mesajsız göster
    debugPrint('KoalaAI: Turns exhausted, functionResultCards=${functionResultCards.length}');
    if (functionResultCards.isNotEmpty) {
      return KoalaResponse(message: '', cards: functionResultCards);
    }
    return const KoalaResponse(message: '', cards: []);
  }

  /// Aynı sohbette tekrar eden önerileri filtrele
  void _deduplicateResult(
    String fnName,
    Map<String, dynamic> result,
    Set<String> seenProjectIds,
    Set<String> seenDesignerIds,
    Set<String> seenProductNames,
  ) {
    switch (fnName) {
      case 'search_projects':
        final projects = result['projects'] as List<dynamic>? ?? [];
        final unique = projects.where((p) {
          final id = (p as Map<String, dynamic>)['id']?.toString() ?? '';
          if (id.isEmpty || seenProjectIds.contains(id)) return false;
          seenProjectIds.add(id);
          return true;
        }).toList();
        result['projects'] = unique;
        result['count'] = unique.length;
        break;
      case 'search_designers':
        final designers = result['designers'] as List<dynamic>? ?? [];
        final unique = designers.where((d) {
          final id = (d as Map<String, dynamic>)['id']?.toString() ?? '';
          if (id.isEmpty || seenDesignerIds.contains(id)) return false;
          seenDesignerIds.add(id);
          return true;
        }).toList();
        result['designers'] = unique;
        result['count'] = unique.length;
        break;
      case 'search_products':
        final products = result['products'] as List<dynamic>? ?? [];
        final unique = products.where((p) {
          final name = ((p as Map<String, dynamic>)['name'] ?? '').toString().toLowerCase().trim();
          if (name.isEmpty || seenProductNames.contains(name)) return false;
          seenProductNames.add(name);
          return true;
        }).toList();
        result['products'] = unique;
        result['count'] = unique.length;
        break;
    }
  }

  /// Function result'tan direkt kart oluştur — Gemini'nin JSON formatına güvenme
  List<KoalaCard> _buildCardsFromFunctionResult(
    String fnName, Map<String, dynamic> result,
  ) {
    switch (fnName) {
      case 'search_products':
        final productsAll = result['products'] as List<dynamic>? ?? [];
        // Görseli olmayan ürünleri filtrele — UI'de boş kart gösterme
        final products = productsAll.where((p) {
          final pm = p as Map<String, dynamic>;
          final img = (pm['image_url'] ?? '').toString().trim();
          return img.isNotEmpty;
        }).toList();
        // Fix F: Boş sonuç → daraltma chipleri göster
        if (products.isEmpty) {
          final roomType = (result['room_type'] as String? ?? '').toLowerCase();
          List<String> narrowingOptions;
          if (roomType.contains('salon') || roomType.contains('oturma')) {
            narrowingOptions = ['Kanepe', 'Koltuk', 'Sehpa', 'TV ünitesi', 'Halı', 'Aydınlatma'];
          } else if (roomType.contains('yatak')) {
            narrowingOptions = ['Yatak', 'Başucu masası', 'Gardırop', 'Şifonyer', 'Ayna', 'Aydınlatma'];
          } else if (roomType.contains('mutfak')) {
            narrowingOptions = ['Bar sandalyesi', 'Mutfak masası', 'Depolama', 'Aydınlatma', 'Halı'];
          } else if (roomType.contains('banyo')) {
            narrowingOptions = ['Ayna', 'Raf', 'Havlu askısı', 'Aydınlatma', 'Aksesuar'];
          } else {
            narrowingOptions = ['Kanepe', 'Masa', 'Sandalye', 'Aydınlatma', 'Dekorasyon', 'Halı'];
          }
          debugPrint('KoalaAI: search_products empty — returning narrowing chips for room: $roomType');
          return [KoalaCard(type: 'question_chips', data: {
            'options': narrowingOptions,
          })];
        }
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
        // Fix F: Boş tasarımcı sonucu → stil daraltma chipleri
        if (designers.isEmpty) {
          debugPrint('KoalaAI: search_designers empty — returning style chips');
          return [KoalaCard(type: 'question_chips', data: {
            'options': ['Modern', 'Minimal', 'Skandinav', 'Bohem', 'Klasik', 'Endüstriyel'],
          })];
        }
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

  KoalaResponse _parseResponse(String raw, {bool jsonMode = false}) {
    // Casual chat (jsonMode=false): Gemini doğal metin döndürür,
    // JSON değilse direkt metni mesaj olarak dön, "aksilik" fallback'i YOK.
    if (!jsonMode) {
      final trimmed = raw.trim();
      final looksLikeJson = trimmed.startsWith('{') || trimmed.startsWith('[') ||
          trimmed.startsWith('```');
      if (!looksLikeJson) {
        return KoalaResponse(message: _sanitizeMessage(trimmed), cards: const []);
      }
      // JSON gibi görünse de jsonMode değilse: parse dene, fail olursa natural text.
    }

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
      debugPrint('KoalaAI parse error: $e\nRaw: ${_truncForLog(raw, 300)}');
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
      // Son çare: exception fırlatma, natural text'i mesaj olarak dön.
      final friendly = _extractFriendlyText(raw);
      return KoalaResponse(message: friendly, cards: const []);
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
    // KLİŞE GİRİŞ FİLTRESİ — prompt kuralına ek güvenlik.
    // Mesajın ilk kelimesi klişe filler ise tüm ilk cümleyi at; arta kalan boşsa
    // sadece ilk kelimeyi at ve kalanı Büyük harfle başlat.
    const fillers = {
      'işte', 'harika', 'tabii', 'elbette', 'tamam', 'peki', 'süper',
      'muhteşem', 'mükemmel', 'hemen',
    };
    final stripped = clean.replaceFirst(RegExp(r'^[\s"\u{201C}\u{201D}]+', unicode: true), '');
    final firstWordMatch = RegExp(r'^([A-Za-zÇĞİıÖŞÜçğıöşü]+)').firstMatch(stripped);
    if (firstWordMatch != null) {
      final firstWord = firstWordMatch.group(1)!.toLowerCase();
      if (fillers.contains(firstWord)) {
        // İlk cümle sonunu bul: `.`, `!`, `?`
        final sentEnd = RegExp(r'[.!?]\s+').firstMatch(stripped);
        String rest;
        if (sentEnd != null && sentEnd.end < stripped.length) {
          rest = stripped.substring(sentEnd.end).trim();
        } else {
          rest = stripped.substring(firstWordMatch.end).trim();
          // Başındaki virgül/noktalama temizle
          rest = rest.replaceFirst(RegExp(r'^[,;:\s]+'), '');
        }
        if (rest.isNotEmpty) {
          clean = rest[0].toUpperCase() + rest.substring(1);
        }
      }
    }
    return clean;
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
    // JSON değilse (casual prompt → plain text yanıt) ham text'i mesaj olarak kullan
    // Örn: "naber" → "Selam! Nasılsın? 🐨"
    final trimmed = raw.trim();
    final looksLikeJson = trimmed.startsWith('{') || trimmed.startsWith('[') ||
        trimmed.startsWith('```');
    if (!looksLikeJson && trimmed.isNotEmpty && trimmed.length < 500) {
      return _sanitizeMessage(trimmed);
    }
    // Hiçbir şey bulamazsa boş mesaj — UI mesaj bar'ı gizleyecek.
    return '';
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
        'maxOutputTokens': 2048,
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
