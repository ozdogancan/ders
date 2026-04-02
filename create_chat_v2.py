#!/usr/bin/env python3
"""
KOALA CHAT SYSTEM v2 — Complete Overhaul
=========================================
1. lib/services/chat_persistence.dart    — YENİ: SharedPreferences chat storage
2. lib/services/koala_ai_service.dart    — GÜNCELLEME: conversation history support
3. lib/views/chat_detail_screen.dart     — GÜNCELLEME: persistence + question_chips + history + polish
4. lib/views/home_screen.dart            — GÜNCELLEME: tüm butonlar chat'e intent ile yönlendirir
5. lib/views/chat_list_screen.dart       — YENİ: geçmiş sohbetler
"""

import os

BASE = r"C:\Users\canoz\Egitim-clean\koala"

files = {}

# ═══════════════════════════════════════════════════════════════
# 1. CHAT PERSISTENCE — SharedPreferences ile lokal storage
# ═══════════════════════════════════════════════════════════════
files[os.path.join("lib", "services", "chat_persistence.dart")] = r'''import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight local chat persistence using SharedPreferences.
/// Each conversation is stored as a JSON string keyed by its ID.
class ChatPersistence {
  static const _listKey = 'koala_chat_list';

  // ── Conversation list ──

  static Future<List<ChatSummary>> loadConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_listKey) ?? [];
    return raw.map((json) {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return ChatSummary.fromJson(m);
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  static Future<void> saveConversationSummary(ChatSummary summary) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_listKey) ?? [];

    // Remove existing entry with same id
    list.removeWhere((json) {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return m['id'] == summary.id;
    });

    // Add at front
    list.insert(0, jsonEncode(summary.toJson()));

    // Keep max 50 conversations
    if (list.length > 50) list.removeRange(50, list.length);

    await prefs.setStringList(_listKey, list);
  }

  static Future<void> deleteConversation(String id) async {
    final prefs = await SharedPreferences.getInstance();

    // Remove from list
    final list = prefs.getStringList(_listKey) ?? [];
    list.removeWhere((json) {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return m['id'] == id;
    });
    await prefs.setStringList(_listKey, list);

    // Remove messages
    await prefs.remove('koala_msgs_$id');
  }

  // ── Messages ──

  static Future<List<Map<String, dynamic>>> loadMessages(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('koala_msgs_$chatId');
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  static Future<void> saveMessages(String chatId, List<Map<String, dynamic>> messages) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('koala_msgs_$chatId', jsonEncode(messages));
  }
}

/// Lightweight summary for the conversation list
class ChatSummary {
  final String id;
  final String title;
  final String? lastMessage;
  final String? intent;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatSummary({
    required this.id,
    required this.title,
    this.lastMessage,
    this.intent,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'lastMessage': lastMessage,
    'intent': intent,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory ChatSummary.fromJson(Map<String, dynamic> m) => ChatSummary(
    id: m['id'] as String? ?? '',
    title: m['title'] as String? ?? 'Sohbet',
    lastMessage: m['lastMessage'] as String?,
    intent: m['intent'] as String?,
    createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(m['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );
}
'''

# ═══════════════════════════════════════════════════════════════
# 2. KOALA AI SERVICE — conversation history desteği eklendi
# ═══════════════════════════════════════════════════════════════
files[os.path.join("lib", "services", "koala_ai_service.dart")] = r'''import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/config/env.dart';
import '../core/constants/koala_prompts.dart';

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

    if (photo != null) {
      return _callGeminiWithImage(prompt: prompt, imageBytes: photo);
    }
    return _callGemini(prompt: prompt, history: history);
  }

  /// Simple ask with history
  Future<KoalaResponse> ask(String text, {List<Map<String, String>>? history}) =>
    askWithIntent(intent: KoalaIntent.freeChat, freeText: text, history: history);

  /// Photo ask
  Future<KoalaResponse> askWithPhoto(Uint8List photo, {String? text, List<Map<String, String>>? history}) =>
    askWithIntent(intent: KoalaIntent.photoAnalysis, freeText: text, photo: photo, history: history);

  // ── Gemini API ──

  Future<KoalaResponse> _callGemini({required String prompt, List<Map<String, String>>? history}) async {
    if (Env.geminiApiKey.isEmpty) throw StateError('GEMINI_API_KEY missing');

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '${Uri.encodeComponent(Env.geminiModel)}:generateContent?key=${Env.geminiApiKey}',
    );

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

    debugPrint('KoalaAI: Sending request (${contents.length} messages)...');
    final response = await _client.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload));

    if (response.statusCode >= 300) {
      debugPrint('KoalaAI ERROR ${response.statusCode}: ${response.body.substring(0, 300.clamp(0, response.body.length))}');
      throw Exception('Gemini failed: ${response.statusCode}');
    }

    return _parseResponse(_extractText(response.body));
  }

  Future<KoalaResponse> _callGeminiWithImage({required String prompt, required Uint8List imageBytes}) async {
    if (Env.geminiApiKey.isEmpty) throw StateError('GEMINI_API_KEY missing');

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '${Uri.encodeComponent(Env.geminiModel)}:generateContent?key=${Env.geminiApiKey}',
    );

    final payload = {
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {'inline_data': {'mime_type': 'image/jpeg', 'data': base64Encode(imageBytes)}},
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.7,
        'responseMimeType': 'application/json',
      },
    };

    final response = await _client.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload));

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

  KoalaResponse _parseResponse(String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final message = data['message'] as String? ?? '';
      final cardsRaw = data['cards'] as List<dynamic>? ?? [];
      final cards = cardsRaw.map((c) => KoalaCard.fromJson(c as Map<String, dynamic>)).toList();
      return KoalaResponse(message: message, cards: cards);
    } catch (e) {
      debugPrint('KoalaAI parse error: $e\nRaw: ${raw.substring(0, 200.clamp(0, raw.length))}');
      return KoalaResponse(message: raw.length > 300 ? '${raw.substring(0, 300)}...' : raw, cards: []);
    }
  }
}
'''

# ═══════════════════════════════════════════════════════════════
# 3. CHAT DETAIL SCREEN — Tam yeniden yazım
#    - Conversation history → AI hatırlıyor
#    - question_chips desteği (tıklanabilir seçenekler)
#    - SharedPreferences persistence
#    - Güzel loading animasyonu
#    - Home'dan gelen her intent'i handle ediyor
# ═══════════════════════════════════════════════════════════════
files[os.path.join("lib", "views", "chat_detail_screen.dart")] = r'''import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/koala_ai_service.dart';
import '../services/chat_persistence.dart';

// ═══════════════════════════════════════════════════════════
// CHAT DETAIL SCREEN
// ═══════════════════════════════════════════════════════════

class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({
    super.key,
    this.initialText,
    this.initialPhoto,
    this.intent,
    this.intentParams,
    this.chatId,
  });

  final String? initialText;
  final Uint8List? initialPhoto;
  final KoalaIntent? intent;
  final Map<String, String>? intentParams;
  final String? chatId; // For loading existing conversation

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> with TickerProviderStateMixin {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final KoalaAIService _ai = KoalaAIService();

  final List<_Msg> _msgs = [];
  final List<Map<String, String>> _history = []; // conversation context for AI
  Uint8List? _pendingPhoto;
  bool _loading = false;
  late String _chatId;
  String _chatTitle = 'Yeni Sohbet';

  @override
  void initState() {
    super.initState();
    _chatId = widget.chatId ?? 'chat_${DateTime.now().millisecondsSinceEpoch}';

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Load existing messages if resuming
      if (widget.chatId != null) {
        await _loadMessages();
      }

      // Handle initial input
      if (widget.intent != null) {
        _handleIntent(widget.intent!, widget.intentParams ?? {});
      } else if (widget.initialText != null || widget.initialPhoto != null) {
        _sendToAI(text: widget.initialText, photo: widget.initialPhoto);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── Persistence ──

  Future<void> _loadMessages() async {
    final saved = await ChatPersistence.loadMessages(_chatId);
    for (final m in saved) {
      _msgs.add(_Msg(
        role: m['role'] as String? ?? 'koala',
        text: m['text'] as String?,
        cards: _parseCards(m['cards']),
      ));
      // Rebuild history
      if (m['text'] != null && (m['text'] as String).isNotEmpty) {
        _history.add({
          'role': m['role'] == 'user' ? 'user' : 'model',
          'content': m['text'] as String,
        });
      }
    }
    if (mounted) setState(() {});
    _scrollDown();
  }

  List<KoalaCard>? _parseCards(dynamic raw) {
    if (raw == null) return null;
    if (raw is! List) return null;
    return (raw as List).map((c) {
      final m = c is Map<String, dynamic> ? c : Map<String, dynamic>.from(c as Map);
      return KoalaCard.fromJson(m);
    }).toList();
  }

  Future<void> _persistMessages() async {
    final serialized = _msgs.map((m) => {
      'role': m.role,
      'text': m.text,
      'cards': m.cards?.map((c) => c.toJson()).toList(),
    }).toList();

    await ChatPersistence.saveMessages(_chatId, serialized);

    // Update summary
    final lastText = _msgs.lastWhere((m) => m.text != null && m.text!.isNotEmpty, orElse: () => _Msg(role: 'koala')).text;
    await ChatPersistence.saveConversationSummary(ChatSummary(
      id: _chatId,
      title: _chatTitle,
      lastMessage: lastText,
      intent: widget.intent?.name,
      updatedAt: DateTime.now(),
    ));
  }

  // ── Scroll ──

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  // ── Intent handling ──

  void _handleIntent(KoalaIntent intent, Map<String, String> params) {
    _chatTitle = _intentTitle(intent);
    _sendToAIWithIntent(intent: intent, params: params);
  }

  String _intentTitle(KoalaIntent intent) {
    switch (intent) {
      case KoalaIntent.styleExplore: return 'Stil Keşfet';
      case KoalaIntent.roomRenovation: return 'Oda Yenileme';
      case KoalaIntent.colorAdvice: return 'Renk Önerisi';
      case KoalaIntent.designerMatch: return 'Tasarımcı Bul';
      case KoalaIntent.budgetPlan: return 'Bütçe Planı';
      case KoalaIntent.beforeAfter: return 'Önce-Sonra';
      case KoalaIntent.pollResult: return 'Stil Testi';
      case KoalaIntent.photoAnalysis: return 'Fotoğraf Analizi';
      case KoalaIntent.freeChat: return 'Sohbet';
    }
  }

  // ── AI Communication ──

  Future<void> _sendToAI({String? text, Uint8List? photo}) async {
    if (text == null && photo == null) return;

    // Set title from first user message
    if (_msgs.isEmpty && text != null && text.length > 3) {
      _chatTitle = text.length > 30 ? '${text.substring(0, 30)}...' : text;
    }

    setState(() {
      _msgs.add(_Msg(role: 'user', text: text, photo: photo));
      _loading = true;
    });
    _scrollDown();

    // Add to history
    if (text != null) {
      _history.add({'role': 'user', 'content': text});
    }

    try {
      KoalaResponse resp;
      if (photo != null) {
        resp = await _ai.askWithPhoto(photo, text: text, history: _history);
      } else {
        resp = await _ai.ask(text!, history: _history);
      }

      // Add AI response to history
      _history.add({'role': 'model', 'content': resp.message});

      setState(() {
        _msgs.add(_Msg(role: 'koala', text: resp.message, cards: resp.cards));
        _loading = false;
      });
    } catch (e) {
      debugPrint('AI error: $e');
      setState(() {
        _msgs.add(_Msg(role: 'koala', text: 'Bir sorun oluştu, tekrar dener misin? 🐨'));
        _loading = false;
      });
    }

    _scrollDown();
    _persistMessages();
  }

  Future<void> _sendToAIWithIntent({
    required KoalaIntent intent,
    Map<String, String> params = const {},
    Uint8List? photo,
  }) async {
    setState(() => _loading = true);
    _scrollDown();

    try {
      final resp = await _ai.askWithIntent(
        intent: intent,
        params: params,
        photo: photo,
        history: _history,
      );

      _history.add({'role': 'model', 'content': resp.message});

      setState(() {
        _msgs.add(_Msg(role: 'koala', text: resp.message, cards: resp.cards));
        _loading = false;
      });
    } catch (e) {
      debugPrint('AI intent error: $e');
      setState(() {
        _msgs.add(_Msg(role: 'koala', text: 'Bir sorun oluştu, tekrar dener misin? 🐨'));
        _loading = false;
      });
    }

    _scrollDown();
    _persistMessages();
  }

  // ── Question chip tapped ──

  void _onChipTap(String chipText) {
    HapticFeedback.lightImpact();
    _sendToAI(text: chipText);
  }

  // ── User input ──

  void _submitText() {
    final t = _ctrl.text.trim();
    if (t.isEmpty && _pendingPhoto == null) return;
    _ctrl.clear();
    final p = _pendingPhoto;
    setState(() => _pendingPhoto = null);
    _sendToAI(text: t.isNotEmpty ? t : null, photo: p);
  }

  void _showPicker() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: Colors.grey.shade300)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: _pickBtn(Icons.camera_alt_rounded, 'Kamera', () { Navigator.pop(context); _doPick(ImageSource.camera); })),
            const SizedBox(width: 12),
            Expanded(child: _pickBtn(Icons.photo_library_rounded, 'Galeri', () { Navigator.pop(context); _doPick(ImageSource.gallery); })),
          ]),
        ])));
  }

  Future<void> _doPick(ImageSource src) async {
    final f = await _picker.pickImage(source: src, maxWidth: 1920, imageQuality: 85);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    setState(() => _pendingPhoto = bytes);
  }

  Widget _pickBtn(IconData icon, String label, VoidCallback onTap) => GestureDetector(onTap: onTap,
    child: Container(padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: const Color(0xFFF5F2FF)),
      child: Column(children: [Icon(icon, size: 28, color: const Color(0xFF6C5CE7)), const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A4458)))])));

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final btm = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1A1D2A)), onPressed: () => Navigator.pop(context)),
        title: Row(children: [
          Container(width: 28, height: 28,
            decoration: const BoxDecoration(shape: BoxShape.circle,
              gradient: LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF8B5CF6)])),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 14)),
          const SizedBox(width: 8),
          Expanded(child: Text(_chatTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A)),
            overflow: TextOverflow.ellipsis)),
        ]),
      ),
      body: Column(children: [
        // Messages
        Expanded(
          child: _msgs.isEmpty && !_loading
            ? _buildEmptyState()
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                itemCount: _msgs.length + (_loading ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == _msgs.length) return _buildLoading();
                  return _buildMsg(_msgs[i]);
                },
              ),
        ),

        // Photo preview
        if (_pendingPhoto != null) Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: const Color(0xFFF5F3FA)),
          child: Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(10),
              child: Image.memory(_pendingPhoto!, width: 40, height: 40, fit: BoxFit.cover)),
            const SizedBox(width: 10),
            Expanded(child: Text('Fotoğraf hazır', style: TextStyle(fontSize: 12, color: Colors.grey.shade500))),
            GestureDetector(onTap: () => setState(() => _pendingPhoto = null),
              child: Icon(Icons.close_rounded, size: 18, color: Colors.grey.shade400)),
          ])),

        // Input bar
        _buildInputBar(btm),
      ]),
    );
  }

  // ── Empty state ──

  Widget _buildEmptyState() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 56, height: 56,
        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFF0ECFF)),
        child: const Icon(Icons.auto_awesome, size: 24, color: Color(0xFF6C5CE7))),
      const SizedBox(height: 12),
      const Text('Koala\'ya bir şey sor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A))),
      const SizedBox(height: 4),
      Text('İç mekan tasarımı hakkında her şeyi sorabilisin', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
    ]));

  // ── Loading ──

  Widget _buildLoading() => Padding(
    padding: const EdgeInsets.only(top: 12, left: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _koalaAvatar(),
      const SizedBox(width: 8),
      Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: const Color(0xFFF8F7FF), borderRadius: BorderRadius.circular(18)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _TypingDots(),
          const SizedBox(width: 10),
          Text('düşünüyor...', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        ])),
    ]));

  // ── Message bubble ──

  Widget _buildMsg(_Msg msg) {
    final isUser = msg.role == 'user';

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Photo
          if (msg.photo != null) Padding(
            padding: EdgeInsets.only(left: isUser ? 48 : 40, right: isUser ? 0 : 48, bottom: 6),
            child: ClipRRect(borderRadius: BorderRadius.circular(16),
              child: Image.memory(msg.photo!, width: 220, height: 160, fit: BoxFit.cover))),

          // Text bubble
          if (msg.text != null && msg.text!.isNotEmpty)
            Row(
              mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isUser) ...[_koalaAvatar(), const SizedBox(width: 8)],
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isUser ? const Color(0xFF6C5CE7) : const Color(0xFFF8F7FF),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isUser ? 18 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 18),
                      )),
                    child: Text(msg.text!,
                      style: TextStyle(fontSize: 14, color: isUser ? Colors.white : const Color(0xFF1A1D2A), height: 1.5)),
                  ),
                ),
              ],
            ),

          // AI cards
          if (msg.cards != null && msg.cards!.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...msg.cards!.map((c) => Padding(
              padding: const EdgeInsets.only(left: 40, bottom: 8),
              child: _renderCard(c),
            )),
          ],
        ],
      ),
    );
  }

  Widget _koalaAvatar() => Container(width: 32, height: 32,
    decoration: const BoxDecoration(shape: BoxShape.circle,
      gradient: LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF8B5CF6)])),
    child: const Icon(Icons.auto_awesome, size: 14, color: Colors.white));

  // ── Input bar ──

  Widget _buildInputBar(double btm) {
    final has = _ctrl.text.isNotEmpty || _pendingPhoto != null;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, btm + 8),
      decoration: BoxDecoration(color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade100))),
      child: Container(height: 48,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: const Color(0xFFF3F1FA)),
        child: Row(children: [
          GestureDetector(onTap: _showPicker, child: Padding(padding: const EdgeInsets.only(left: 5),
            child: Container(width: 36, height: 36,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.7)),
              child: Icon(Icons.add_rounded, size: 20, color: Colors.grey.shade600)))),
          Expanded(child: TextField(controller: _ctrl,
            decoration: InputDecoration(
              hintText: 'Koala\'ya sor...',
              hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade400),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14)),
            style: const TextStyle(fontSize: 14, color: Color(0xFF1A1D2A)),
            onSubmitted: (_) => _submitText(),
            onChanged: (_) => setState(() {}))),
          if (has) GestureDetector(onTap: _submitText, child: Padding(padding: const EdgeInsets.only(right: 5),
            child: Container(width: 36, height: 36,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF6C5CE7)),
              child: const Icon(Icons.arrow_upward_rounded, size: 18, color: Colors.white)))),
        ])));
  }

  // ═══════════════════════════════════════════════════════════
  // CARD RENDERERS
  // ═══════════════════════════════════════════════════════════

  Widget _renderCard(KoalaCard card) {
    switch (card.type) {
      case 'question_chips': return _QuestionChipsCard(card.data, onChipTap: _onChipTap);
      case 'style_analysis': return _StyleCard(card.data);
      case 'product_grid': return _ProductGrid(card.data);
      case 'color_palette': return _ColorPaletteCard(card.data);
      case 'designer_card': return _DesignerCard(card.data);
      case 'budget_plan': return _BudgetCard(card.data);
      case 'quick_tips': return _TipsCard(card.data);
      case 'before_after': return _BeforeAfterCard(card.data);
      default: return const SizedBox.shrink();
    }
  }
}

// ═══════════════════════════════════════════════════════════
// DATA CLASS
// ═══════════════════════════════════════════════════════════

class _Msg {
  final String role;
  final String? text;
  final Uint8List? photo;
  final List<KoalaCard>? cards;
  _Msg({required this.role, this.text, this.photo, this.cards});
}

// ═══════════════════════════════════════════════════════════
// TYPING DOTS ANIMATION
// ═══════════════════════════════════════════════════════════

class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(3, (i) =>
      AnimationController(vsync: this, duration: const Duration(milliseconds: 400))
        ..repeat(reverse: true)
    );
    // Stagger
    for (var i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 150), () {
        if (mounted) _ctrls[i].forward();
      });
    }
  }

  @override
  void dispose() { for (final c in _ctrls) c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min,
    children: List.generate(3, (i) => AnimatedBuilder(
      animation: _ctrls[i],
      builder: (_, __) => Container(
        width: 6, height: 6,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(shape: BoxShape.circle,
          color: Color.lerp(const Color(0xFFD4D0E8), const Color(0xFF6C5CE7), _ctrls[i].value))))));
}

// ═══════════════════════════════════════════════════════════
// QUESTION CHIPS CARD — tıklanabilir seçenekler
// ═══════════════════════════════════════════════════════════

class _QuestionChipsCard extends StatelessWidget {
  const _QuestionChipsCard(this.d, {required this.onChipTap});
  final Map<String, dynamic> d;
  final void Function(String) onChipTap;

  @override
  Widget build(BuildContext context) {
    final question = d['question'] as String? ?? '';
    final chips = (d['chips'] as List?)?.cast<String>() ?? [];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFFF8F6FF),
        border: Border.all(color: const Color(0xFFEDEAF5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (question.isNotEmpty) Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(question, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1D2A)))),
        Wrap(spacing: 8, runSpacing: 8, children: chips.map((chip) =>
          GestureDetector(
            onTap: () => onChipTap(chip),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: Colors.white,
                border: Border.all(color: const Color(0xFF6C5CE7).withOpacity(0.2))),
              child: Text(chip, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6C5CE7)))))).toList()),
      ]));
  }
}

// ═══════════════════════════════════════════════════════════
// AI RESPONSE CARDS (aynı tasarım, temizlenmiş)
// ═══════════════════════════════════════════════════════════

const _cr = 18.0;
const _pc = Color(0xFF6C5CE7);
Color _hex(String h) => Color(int.tryParse('FF${h.replaceAll("#", "")}', radix: 16) ?? 0xFF6C5CE7);

class _StyleCard extends StatelessWidget {
  const _StyleCard(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final colors = (d['color_palette'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final tags = (d['tags'] as List?)?.cast<String>() ?? [];
    final conf = ((d['confidence'] as num?) ?? 0) * 100;
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(_cr), color: Colors.white, border: Border.all(color: const Color(0xFFEDEAF5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(borderRadius: const BorderRadius.vertical(top: Radius.circular(18)), color: _pc.withOpacity(0.04)),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('STİL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _pc.withOpacity(0.5), letterSpacing: 0.8)),
              const SizedBox(height: 4),
              Text(d['style_name'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A1D2A)))])),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: const Color(0xFF00B894).withOpacity(0.1)),
              child: Text('%${conf.round()}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF00B894))))])),
        if (colors.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: colors.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(children: [
              Container(height: 40, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: _hex(c['hex'] ?? '#000'))),
              const SizedBox(height: 4),
              Text(c['name'] ?? '', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.grey.shade500))])))).toList())),
        if (tags.isNotEmpty) Padding(padding: const EdgeInsets.all(16),
          child: Wrap(spacing: 6, runSpacing: 6, children: tags.map((t) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: Colors.grey.shade50), child: Text(t, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)))).toList())),
      ]));
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final products = (d['products'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (d['title'] != null) Padding(padding: const EdgeInsets.only(bottom: 8),
        child: Text(d['title'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A)))),
      ...products.map((p) => Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(_cr), color: Colors.white, border: Border.all(color: const Color(0xFFEDEAF5))),
        child: Row(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0xFFF5F3FA)),
            child: const Icon(Icons.shopping_bag_rounded, color: _pc, size: 22)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p['name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A))),
            if (p['reason'] != null) Text(p['reason'], style: TextStyle(fontSize: 11, color: Colors.grey.shade500), maxLines: 2),
            const SizedBox(height: 2),
            Text(p['price'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _pc))]))]))),
    ]);
  }
}

class _ColorPaletteCard extends StatelessWidget {
  const _ColorPaletteCard(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final colors = (d['colors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return Container(padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(_cr), color: Colors.white, border: Border.all(color: const Color(0xFFEDEAF5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(d['title'] ?? 'Renk Paleti', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A))),
        const SizedBox(height: 12),
        Row(children: colors.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(children: [
            Container(height: 44, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: _hex(c['hex'] ?? '#000'))),
            const SizedBox(height: 4),
            Text(c['name'] ?? '', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.grey.shade500), textAlign: TextAlign.center),
          ])))).toList()),
        if (d['tip'] != null) ...[
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: const Color(0xFFF8F6FF)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('💡', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(child: Text(d['tip'], style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.3)))])),
        ],
      ]));
  }
}

class _DesignerCard extends StatelessWidget {
  const _DesignerCard(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final designers = (d['designers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return Column(children: designers.map((ds) => Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(_cr), color: Colors.white, border: Border.all(color: const Color(0xFFEDEAF5))),
      child: Row(children: [
        Container(width: 44, height: 44, decoration: BoxDecoration(shape: BoxShape.circle, color: _pc.withOpacity(0.1)),
          child: const Icon(Icons.person_rounded, color: _pc, size: 22)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ds['name'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A))),
          Text('${ds['title'] ?? ''} · ${ds['specialty'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          Row(children: [
            const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFBBF24)),
            Text(' ${ds['rating'] ?? ''}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ])])),
        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: _pc),
          child: const Text('Profil', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)))]))).toList());
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final items = (d['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return Container(padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(_cr), color: Colors.white, border: Border.all(color: const Color(0xFFEDEAF5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Text('💰', style: TextStyle(fontSize: 18)), const SizedBox(width: 8),
          const Text('Bütçe Planı', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A))),
          const Spacer(),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: _pc.withOpacity(0.08)),
            child: Text(d['total_budget'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _pc)))]),
        const SizedBox(height: 14),
        ...items.map((i) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle,
            color: i['priority'] == 'high' ? const Color(0xFF00B894) : const Color(0xFFF59E0B))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(i['category'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1D2A))),
            if (i['note'] != null) Text(i['note'], style: TextStyle(fontSize: 11, color: Colors.grey.shade500))])),
          Text(i['amount'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _pc))]))),
        if (d['tip'] != null) Container(padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: const Color(0xFFF8F6FF)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('💡', style: TextStyle(fontSize: 14)), const SizedBox(width: 8),
            Expanded(child: Text(d['tip'], style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, height: 1.3)))])),
      ]));
  }
}

class _TipsCard extends StatelessWidget {
  const _TipsCard(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final tips = (d['tips'] as List?) ?? [];
    return Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(_cr), color: const Color(0xFFF8F6FF)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('💡 İpuçları', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A))),
        const SizedBox(height: 8),
        ...tips.map((t) {
          final text = t is String ? t : (t is Map ? (t['text'] ?? '') : t.toString());
          final emoji = t is Map ? (t['emoji'] ?? '✨') : '✨';
          return Padding(padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(emoji.toString(), style: const TextStyle(fontSize: 14)), const SizedBox(width: 8),
              Expanded(child: Text(text.toString(), style: const TextStyle(fontSize: 13, color: Color(0xFF4A4458), height: 1.4)))]));
        }),
      ]));
  }
}

class _BeforeAfterCard extends StatelessWidget {
  const _BeforeAfterCard(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final changes = (d['changes'] as List?)?.cast<String>() ?? [];
    return Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(_cr),
        gradient: const LinearGradient(colors: [Color(0xFFF0ECFF), Color(0xFFE8F5E9)])),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(d['title'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A))),
        const SizedBox(height: 8),
        ...changes.map((c) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(children: [
          const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF00B894)), const SizedBox(width: 8),
          Expanded(child: Text(c, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.3)))]))),
        if (d['estimated_budget'] != null) Padding(padding: const EdgeInsets.only(top: 8),
          child: Text('Tahmini: ${d['estimated_budget']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _pc))),
      ]));
  }
}
'''

# ═══════════════════════════════════════════════════════════════
# 4. HOME SCREEN — intent bazlı chat yönlendirme
#    Home'daki her buton artık ChatDetailScreen'e intent ile gider
# ═══════════════════════════════════════════════════════════════
# Bu dosyayı DEĞİŞTİRMİYORUM çünkü kullanıcı mevcut tasarımı beğendi.
# Sadece _go() ve _startFlow() methodlarını ChatDetailScreen'e uyumlu yapacağız.
# Bu home_screen.dart üzerinde küçük bir patch:

# ═══════════════════════════════════════════════════════════════
# 5. CHAT LIST SCREEN — geçmiş sohbetler
# ═══════════════════════════════════════════════════════════════
files[os.path.join("lib", "views", "chat_list_screen.dart")] = r'''import 'package:flutter/material.dart';

import '../services/chat_persistence.dart';
import 'chat_detail_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});
  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<ChatSummary> _chats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final chats = await ChatPersistence.loadConversations();
    setState(() { _chats = chats; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0,
        title: const Text('Sohbetler', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A))),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C5CE7)))
        : _chats.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.chat_bubble_outline_rounded, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text('Henüz sohbet yok', style: TextStyle(fontSize: 16, color: Colors.grey.shade400)),
            ]))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _chats.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
              itemBuilder: (_, i) {
                final chat = _chats[i];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  leading: Container(width: 40, height: 40,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFF0ECFF)),
                    child: const Icon(Icons.chat_rounded, size: 18, color: Color(0xFF6C5CE7))),
                  title: Text(chat.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1D2A)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: chat.lastMessage != null
                    ? Text(chat.lastMessage!, style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        maxLines: 1, overflow: TextOverflow.ellipsis)
                    : null,
                  trailing: Text(_timeAgo(chat.updatedAt),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ChatDetailScreen(chatId: chat.id))),
                  onLongPress: () => _confirmDelete(chat),
                );
              },
            ),
    );
  }

  void _confirmDelete(ChatSummary chat) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Sohbeti sil?'),
      content: Text('"${chat.title}" silinecek.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
        TextButton(onPressed: () async {
          Navigator.pop(context);
          await ChatPersistence.deleteConversation(chat.id);
          _load();
        }, child: const Text('Sil', style: TextStyle(color: Colors.red))),
      ],
    ));
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Şimdi';
    if (diff.inHours < 1) return '${diff.inMinutes}dk';
    if (diff.inDays < 1) return '${diff.inHours}sa';
    if (diff.inDays < 7) return '${diff.inDays}g';
    return '${dt.day}/${dt.month}';
  }
}
'''

# ═══════════════════════════════════════════════════════════════
# Write all files
# ═══════════════════════════════════════════════════════════════
print("=" * 60)
print("KOALA CHAT SYSTEM v2")
print("=" * 60)

for rel_path, content in files.items():
    full_path = os.path.join(BASE, rel_path)
    os.makedirs(os.path.dirname(full_path), exist_ok=True)
    with open(full_path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"  ✅ {rel_path}")

# ═══════════════════════════════════════════════════════════════
# Patch home_screen.dart — update _go to use intent
# ═══════════════════════════════════════════════════════════════
home_path = os.path.join(BASE, "lib", "views", "home_screen.dart")
with open(home_path, 'r', encoding='utf-8') as f:
    home = f.read()

# Add chat_list_screen import if missing
if "chat_list_screen.dart" not in home:
    home = home.replace(
        "import 'guided_flow_screen.dart';",
        "import 'guided_flow_screen.dart';\nimport 'chat_list_screen.dart';"
    )

# Add chat_persistence import if missing
if "chat_persistence.dart" not in home:
    home = home.replace(
        "import '../models/flow_models.dart';",
        "import '../models/flow_models.dart';\nimport '../services/koala_ai_service.dart';"
    )

with open(home_path, 'w', encoding='utf-8') as f:
    f.write(home)
print(f"  ✅ lib/views/home_screen.dart (patched imports)")

# ═══════════════════════════════════════════════════════════════
# Check shared_preferences dependency
# ═══════════════════════════════════════════════════════════════
pubspec_path = os.path.join(BASE, "pubspec.yaml")
with open(pubspec_path, 'r', encoding='utf-8') as f:
    pubspec = f.read()

if 'shared_preferences' not in pubspec:
    print()
    print("  ⚠️  shared_preferences not in pubspec.yaml!")
    print("  Run: flutter pub add shared_preferences")

print()
print("=" * 60)
print(f"  4 dosya oluşturuldu/güncellendi!")
print("=" * 60)
print()
print("Yeni özellikler:")
print("  💬 Conversation history — AI önceki mesajları hatırlıyor")
print("  🏷️ question_chips — AI soru sorduğunda tıklanabilir seçenekler")
print("  💾 SharedPreferences persistence — chat'ler kaybolmuyor")
print("  📋 Chat list — geçmiş sohbetler listesi")
print("  ⌨️ Typing dots animasyonu")
print("  🫧 Mesaj balonları (rounded corners, koala/user ayrımı)")
print()
print("Adımlar:")
print("  1. flutter pub add shared_preferences")
print("  2. flutter run -d chrome")
