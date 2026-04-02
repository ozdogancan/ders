#!/usr/bin/env python3
"""
CHAT DETAIL SCREEN — Complete Rewrite
======================================
- Beautiful card designs with dummy evlumba data
- question_chips with both chips/options keys
- image_prompt card with generate button
- Tagged products (interactive, tappable)
- Designer cards with avatars and portfolios
- Proper message flow (user question shown, AI response below)
- Empty state with suggestion chips
- Error handling with retry
"""
import os

BASE = r"C:\Users\canoz\Egitim-clean\koala"
path = os.path.join(BASE, "lib", "views", "chat_detail_screen.dart")

content = r'''import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/koala_ai_service.dart';
import '../services/koala_image_service.dart';
import '../services/chat_persistence.dart';

const _accent = Color(0xFF6C5CE7);
const _accentLight = Color(0xFFF3F0FF);
const _ink = Color(0xFF1A1D2A);
const _R = 18.0;

Color _hex(String h) {
  final clean = h.replaceAll('#', '');
  return Color(int.tryParse('FF$clean', radix: 16) ?? 0xFF6C5CE7);
}

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
  final String? chatId;

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> with TickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _picker = ImagePicker();
  final _ai = KoalaAIService();
  final _imgService = KoalaImageService();

  final List<_Msg> _msgs = [];
  final List<Map<String, String>> _history = [];
  Uint8List? _pendingPhoto;
  bool _loading = false;
  late String _chatId;
  String _chatTitle = 'Yeni Sohbet';

  @override
  void initState() {
    super.initState();
    _chatId = widget.chatId ?? 'chat_${DateTime.now().millisecondsSinceEpoch}';

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.chatId != null) await _loadMessages();

      if (widget.intent != null) {
        _chatTitle = _intentTitle(widget.intent!);
        _sendToAIWithIntent(intent: widget.intent!, params: widget.intentParams ?? {});
      } else if (widget.initialText != null || widget.initialPhoto != null) {
        _sendToAI(text: widget.initialText, photo: widget.initialPhoto);
      }
    });
  }

  @override
  void dispose() { _ctrl.dispose(); _scroll.dispose(); super.dispose(); }

  // ── Persistence ──
  Future<void> _loadMessages() async {
    final saved = await ChatPersistence.loadMessages(_chatId);
    for (final m in saved) {
      _msgs.add(_Msg(
        role: m['role'] as String? ?? 'koala',
        text: m['text'] as String?,
        cards: _parseCards(m['cards']),
      ));
      if (m['text'] != null && (m['text'] as String).isNotEmpty) {
        _history.add({'role': m['role'] == 'user' ? 'user' : 'model', 'content': m['text'] as String});
      }
    }
    if (mounted) setState(() {});
    _scrollDown();
  }

  List<KoalaCard>? _parseCards(dynamic raw) {
    if (raw == null || raw is! List) return null;
    return (raw as List).map((c) {
      final m = c is Map<String, dynamic> ? c : Map<String, dynamic>.from(c as Map);
      return KoalaCard.fromJson(m);
    }).toList();
  }

  Future<void> _persist() async {
    final serialized = _msgs.where((m) => m.text != null || m.cards != null).map((m) => <String, dynamic>{
      'role': m.role,
      'text': m.text,
      'cards': m.cards?.map((c) => c.toJson()).toList(),
    }).toList();
    await ChatPersistence.saveMessages(_chatId, serialized);
    final lastText = _msgs.lastWhere((m) => m.text != null && m.text!.isNotEmpty, orElse: () => _Msg(role: 'koala')).text;
    await ChatPersistence.saveConversationSummary(ChatSummary(
      id: _chatId, title: _chatTitle, lastMessage: lastText,
      intent: widget.intent?.name, updatedAt: DateTime.now()));
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
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

  // ── AI ──
  Future<void> _sendToAI({String? text, Uint8List? photo}) async {
    if (text == null && photo == null) return;
    if (_msgs.isEmpty && text != null && text.length > 3) {
      _chatTitle = text.length > 30 ? '${text.substring(0, 30)}...' : text;
    }

    setState(() {
      _msgs.add(_Msg(role: 'user', text: text, photo: photo));
      _loading = true;
    });
    _scrollDown();
    if (text != null) _history.add({'role': 'user', 'content': text});

    try {
      final resp = photo != null
        ? await _ai.askWithPhoto(photo, text: text, history: _history)
        : await _ai.ask(text!, history: _history);
      _history.add({'role': 'model', 'content': resp.message});
      setState(() {
        _msgs.add(_Msg(role: 'koala', text: resp.message, cards: resp.cards));
        _loading = false;
      });
    } catch (e) {
      debugPrint('AI error: $e');
      setState(() {
        _msgs.add(_Msg(role: 'koala', text: null, isError: true, errorMsg: e.toString()));
        _loading = false;
      });
    }
    _scrollDown();
    _persist();
  }

  Future<void> _sendToAIWithIntent({required KoalaIntent intent, Map<String, String> params = const {}}) async {
    setState(() => _loading = true);
    _scrollDown();
    try {
      final resp = await _ai.askWithIntent(intent: intent, params: params, history: _history);
      _history.add({'role': 'model', 'content': resp.message});
      setState(() {
        _msgs.add(_Msg(role: 'koala', text: resp.message, cards: resp.cards));
        _loading = false;
      });
    } catch (e) {
      debugPrint('AI intent error: $e');
      setState(() {
        _msgs.add(_Msg(role: 'koala', text: null, isError: true, errorMsg: e.toString()));
        _loading = false;
      });
    }
    _scrollDown();
    _persist();
  }

  void _retry() {
    // Remove error message and resend last user message
    setState(() {
      _msgs.removeWhere((m) => m.isError);
    });
    final lastUser = _msgs.lastWhere((m) => m.role == 'user', orElse: () => _Msg(role: 'user'));
    if (lastUser.text != null) {
      _history.removeLast(); // Remove failed attempt
      _msgs.removeLast(); // Remove user msg (will be re-added)
      _sendToAI(text: lastUser.text, photo: lastUser.photo);
    }
  }

  void _onChipTap(String chipText) {
    HapticFeedback.lightImpact();
    _sendToAI(text: chipText);
  }

  Future<void> _generateImage(String prompt) async {
    setState(() { _loading = true; });
    _scrollDown();
    try {
      final bytes = await _imgService.generateRoomDesign(roomType: 'salon', style: 'modern', additionalDetails: prompt);
      setState(() {
        if (bytes != null) {
          _msgs.add(_Msg(role: 'koala', text: '🏠 İşte tasarım önerim:', photo: bytes));
        } else {
          _msgs.add(_Msg(role: 'koala', text: 'Görsel şu an oluşturulamadı ama önerilerimi kullanabilirsin 🐨'));
        }
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _msgs.add(_Msg(role: 'koala', text: 'Görsel oluşturma şu an çalışmıyor 🐨'));
        _loading = false;
      });
    }
    _scrollDown();
    _persist();
  }

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
          ])])));
  }

  Future<void> _doPick(ImageSource src) async {
    final f = await _picker.pickImage(source: src, maxWidth: 1920, imageQuality: 85);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    setState(() => _pendingPhoto = bytes);
  }

  Widget _pickBtn(IconData icon, String label, VoidCallback onTap) => GestureDetector(onTap: onTap,
    child: Container(padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: _accentLight),
      child: Column(children: [Icon(icon, size: 28, color: _accent), const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A4458)))])));

  // ═══════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final btm = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0.5,
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded, color: _ink), onPressed: () => Navigator.pop(context)),
        title: Row(children: [
          Image.asset('assets/images/koalas.png', width: 28, height: 28, filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => Container(width: 28, height: 28,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [_accent, Color(0xFF8B5CF6)])),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 14))),
          const SizedBox(width: 8),
          Expanded(child: Text(_chatTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _ink),
            overflow: TextOverflow.ellipsis)),
        ]),
      ),
      body: Column(children: [
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
                })),
        if (_pendingPhoto != null) _buildPhotoPreview(),
        _buildInputBar(btm),
      ]));
  }

  // ── Empty state with suggestion chips ──
  Widget _buildEmptyState() => Center(
    child: Padding(padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Image.asset('assets/images/koalas.png', width: 64, height: 64, filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => const Icon(Icons.auto_awesome, size: 48, color: _accent)),
        const SizedBox(height: 16),
        const Text('Merhaba! Ben Koala 🐨', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _ink)),
        const SizedBox(height: 6),
        Text('İç mekan tasarımı hakkında\nher şeyi sorabilirsn',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade500), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center,
          children: [
            _suggestionChip('🏠 Odamı yenile', () => _sendToAI(text: 'Odamı yeniden tasarla')),
            _suggestionChip('🎨 Renk öner', () => _sendToAI(text: 'Odama renk öner')),
            _suggestionChip('💰 Bütçe planla', () => _sendToAI(text: 'Bütçeme uygun dekorasyon planı')),
            _suggestionChip('👤 Tasarımcı bul', () => _sendToAI(text: 'Bana uygun tasarımcı öner')),
          ]),
      ])));

  Widget _suggestionChip(String label, VoidCallback onTap) => GestureDetector(onTap: onTap,
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: Colors.white,
        border: Border.all(color: _accent.withOpacity(0.15))),
      child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _accent))));

  // ── Loading ──
  Widget _buildLoading() => Padding(
    padding: const EdgeInsets.only(top: 16, left: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _koalaAvatar(),
      const SizedBox(width: 8),
      Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _TypingDots(),
          const SizedBox(width: 10),
          Text('düşünüyor...', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        ]))]));

  // ── Message ──
  Widget _buildMsg(_Msg msg) {
    final isUser = msg.role == 'user';
    return Padding(padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
        // Photo
        if (msg.photo != null && isUser) Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Align(alignment: Alignment.centerRight,
            child: ClipRRect(borderRadius: BorderRadius.circular(16),
              child: Image.memory(msg.photo!, width: 200, height: 150, fit: BoxFit.cover)))),
        // Generated image (koala response)
        if (msg.photo != null && !isUser) Padding(
          padding: const EdgeInsets.only(left: 40, bottom: 8),
          child: ClipRRect(borderRadius: BorderRadius.circular(16),
            child: Image.memory(msg.photo!, width: double.infinity, fit: BoxFit.cover))),
        // Error with retry
        if (msg.isError) _buildErrorCard(msg),
        // Text
        if (msg.text != null && msg.text!.isNotEmpty)
          Row(mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!isUser) ...[_koalaAvatar(), const SizedBox(width: 8)],
            Flexible(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? _accent : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18))),
              child: Text(msg.text!, style: TextStyle(fontSize: 14,
                color: isUser ? Colors.white : _ink, height: 1.5)))),
          ]),
        // Cards
        if (msg.cards != null) ...msg.cards!.map((c) => Padding(
          padding: const EdgeInsets.only(left: 40, top: 8),
          child: _renderCard(c))),
      ]));
  }

  Widget _buildErrorCard(_Msg msg) => Padding(
    padding: const EdgeInsets.only(left: 40),
    child: Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16),
        color: const Color(0xFFFEF2F2), border: Border.all(color: const Color(0xFFFCA5A5))),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded, size: 20, color: Color(0xFFDC2626)),
        const SizedBox(width: 10),
        const Expanded(child: Text('Bir sorun oluştu', style: TextStyle(fontSize: 13, color: Color(0xFF991B1B)))),
        GestureDetector(onTap: _retry,
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: _accent),
            child: const Text('Tekrar dene', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)))),
      ])));

  Widget _koalaAvatar() => ClipRRect(borderRadius: BorderRadius.circular(10),
    child: Image.asset('assets/images/koalas.png', width: 32, height: 32, filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => Container(width: 32, height: 32,
        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [_accent, Color(0xFF8B5CF6)])),
        child: const Icon(Icons.auto_awesome, size: 14, color: Colors.white))));

  Widget _buildPhotoPreview() => Container(
    margin: const EdgeInsets.fromLTRB(14, 0, 14, 4),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Colors.white),
    child: Row(children: [
      ClipRRect(borderRadius: BorderRadius.circular(10),
        child: Image.memory(_pendingPhoto!, width: 40, height: 40, fit: BoxFit.cover)),
      const SizedBox(width: 10),
      Expanded(child: Text('Fotoğraf hazır', style: TextStyle(fontSize: 12, color: Colors.grey.shade500))),
      GestureDetector(onTap: () => setState(() => _pendingPhoto = null),
        child: Icon(Icons.close_rounded, size: 18, color: Colors.grey.shade400)),
    ]));

  Widget _buildInputBar(double btm) {
    final has = _ctrl.text.isNotEmpty || _pendingPhoto != null;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, btm + 8),
      decoration: const BoxDecoration(color: Colors.white),
      child: Container(height: 48,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: const Color(0xFFF3F1FA)),
        child: Row(children: [
          GestureDetector(onTap: _showPicker, child: Padding(padding: const EdgeInsets.only(left: 5),
            child: Container(width: 36, height: 36,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.7)),
              child: Icon(Icons.add_rounded, size: 20, color: Colors.grey.shade600)))),
          Expanded(child: TextField(controller: _ctrl,
            decoration: InputDecoration(hintText: 'Koala\'ya sor...', hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade400),
              border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14)),
            style: const TextStyle(fontSize: 14, color: _ink),
            onSubmitted: (_) => _submitText(), onChanged: (_) => setState(() {}))),
          if (has) GestureDetector(onTap: _submitText, child: Padding(padding: const EdgeInsets.only(right: 5),
            child: Container(width: 36, height: 36,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: _accent),
              child: const Icon(Icons.arrow_upward_rounded, size: 18, color: Colors.white)))),
        ])));
  }

  // ═══════════════════════════════════════════════════════
  // CARD RENDERER
  // ═══════════════════════════════════════════════════════
  Widget _renderCard(KoalaCard card) {
    switch (card.type) {
      case 'question_chips': return _QuestionChips(card.data, onTap: _onChipTap);
      case 'style_analysis': return _StyleAnalysis(card.data);
      case 'product_grid': return _ProductGrid(card.data);
      case 'color_palette': return _ColorPalette(card.data);
      case 'designer_card': return _DesignerCards(card.data);
      case 'budget_plan': return _BudgetPlan(card.data);
      case 'quick_tips': return _QuickTips(card.data);
      case 'before_after': return _BeforeAfter(card.data);
      case 'image_prompt': return _ImagePrompt(card.data, onGenerate: _generateImage);
      default:
        // Fallback — show as text card
        final title = card.data['title'] as String? ?? card.data['question'] as String? ?? '';
        if (title.isEmpty) return const SizedBox.shrink();
        return Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: Colors.white),
          child: Text(title, style: const TextStyle(fontSize: 13, color: _ink)));
    }
  }
}

// ═══════════════════════════════════════════════════════
// MSG MODEL
// ═══════════════════════════════════════════════════════
class _Msg {
  final String role;
  final String? text;
  final Uint8List? photo;
  final List<KoalaCard>? cards;
  final bool isError;
  final String? errorMsg;
  _Msg({required this.role, this.text, this.photo, this.cards, this.isError = false, this.errorMsg});
}

// ═══════════════════════════════════════════════════════
// TYPING DOTS
// ═══════════════════════════════════════════════════════
class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}
class _TypingDotsState extends State<_TypingDots> with TickerProviderStateMixin {
  late final List<AnimationController> _c;
  @override
  void initState() {
    super.initState();
    _c = List.generate(3, (i) => AnimationController(vsync: this, duration: const Duration(milliseconds: 400))..repeat(reverse: true));
    for (var i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 150), () { if (mounted) _c[i].forward(); });
    }
  }
  @override
  void dispose() { for (final c in _c) c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min,
    children: List.generate(3, (i) => AnimatedBuilder(animation: _c[i],
      builder: (_, __) => Container(width: 6, height: 6, margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(shape: BoxShape.circle,
          color: Color.lerp(const Color(0xFFD4D0E8), _accent, _c[i].value))))));
}

// ═══════════════════════════════════════════════════════
// QUESTION CHIPS
// ═══════════════════════════════════════════════════════
class _QuestionChips extends StatelessWidget {
  const _QuestionChips(this.d, {required this.onTap});
  final Map<String, dynamic> d;
  final void Function(String) onTap;
  @override
  Widget build(BuildContext context) {
    final question = d['question'] as String? ?? d['title'] as String? ?? '';
    final raw = d['chips'] ?? d['options'] ?? [];
    final chips = (raw is List) ? raw.map((e) => e.toString()).toList() : <String>[];
    if (chips.isEmpty) return const SizedBox.shrink();

    return Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: Colors.white,
        border: Border.all(color: const Color(0xFFEDEAF5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (question.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10),
          child: Text(question, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _ink))),
        Wrap(spacing: 8, runSpacing: 8, children: chips.map((chip) =>
          GestureDetector(onTap: () => onTap(chip),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: _accentLight,
                border: Border.all(color: _accent.withOpacity(0.15))),
              child: Text(chip, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _accent))))).toList()),
      ]));
  }
}

// ═══════════════════════════════════════════════════════
// STYLE ANALYSIS
// ═══════════════════════════════════════════════════════
class _StyleAnalysis extends StatelessWidget {
  const _StyleAnalysis(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final colors = (d['color_palette'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final tags = (d['tags'] as List?)?.cast<String>() ?? [];
    final desc = d['description'] as String? ?? '';
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R), color: Colors.white),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            gradient: LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF8B5CF6)])),
          child: Row(children: [
            Expanded(child: Text(d['style_name'] ?? 'Stil', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white))),
          ])),
        // Colors
        if (colors.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: colors.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Column(children: [
              Container(height: 44, decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: _hex(c['hex'] ?? '#000'))),
              const SizedBox(height: 4),
              Text(c['name'] ?? '', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade600), textAlign: TextAlign.center),
            ])))).toList())),
        // Description
        if (desc.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(desc, style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.5))),
        // Tags
        if (tags.isNotEmpty) Padding(padding: const EdgeInsets.all(16),
          child: Wrap(spacing: 6, runSpacing: 6, children: tags.map((t) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: _accentLight),
            child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _accent)))).toList())),
      ]));
  }
}

// ═══════════════════════════════════════════════════════
// PRODUCT GRID — interactive tagged products
// ═══════════════════════════════════════════════════════
class _ProductGrid extends StatelessWidget {
  const _ProductGrid(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final products = (d['products'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final title = d['title'] as String?;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (title != null) Padding(padding: const EdgeInsets.only(bottom: 10),
        child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ink))),
      ...products.map((p) => GestureDetector(
        onTap: () => launchUrl(Uri.parse('https://www.evlumba.com/kesfet?q=${Uri.encodeComponent(p['name'] ?? '')}'), mode: LaunchMode.externalApplication),
        child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: Colors.white),
          child: Row(children: [
            // Product icon with accent
            Container(width: 52, height: 52,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(colors: [Color(0xFFF0ECFF), Color(0xFFE8F4FD)])),
              child: const Icon(Icons.shopping_bag_rounded, color: _accent, size: 22)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p['name'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
              if (p['reason'] != null) Padding(padding: const EdgeInsets.only(top: 2),
                child: Text(p['reason'], style: TextStyle(fontSize: 12, color: Colors.grey.shade500), maxLines: 2)),
            ])),
            Column(children: [
              Text(p['price'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _accent)),
              const SizedBox(height: 4),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: const Color(0xFFECFDF5)),
                child: const Text('evlumba', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF059669)))),
            ]),
          ])))),
    ]);
  }
}

// ═══════════════════════════════════════════════════════
// COLOR PALETTE
// ═══════════════════════════════════════════════════════
class _ColorPalette extends StatelessWidget {
  const _ColorPalette(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final colors = (d['colors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return Container(padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R), color: Colors.white),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(d['title'] ?? 'Renk Paleti', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
        const SizedBox(height: 14),
        Row(children: colors.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Column(children: [
            Container(height: 52, decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: _hex(c['hex'] ?? '#000'))),
            const SizedBox(height: 6),
            Text(c['name'] ?? '', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade600), textAlign: TextAlign.center),
            if (c['usage'] != null) Text(c['usage'], style: TextStyle(fontSize: 9, color: Colors.grey.shade400), textAlign: TextAlign.center, maxLines: 1),
          ])))).toList()),
        if (d['tip'] != null) ...[
          const SizedBox(height: 14),
          Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: _accentLight),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('💡', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(child: Text(d['tip'], style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4))),
            ])),
        ],
      ]));
  }
}

// ═══════════════════════════════════════════════════════
// DESIGNER CARDS — with avatar, portfolio link
// ═══════════════════════════════════════════════════════
class _DesignerCards extends StatelessWidget {
  const _DesignerCards(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final designers = (d['designers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(padding: EdgeInsets.only(bottom: 10),
        child: Text('Sana Uygun Tasarımcılar', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ink))),
      ...designers.map((ds) {
        final name = ds['name'] as String? ?? '';
        final initials = name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();
        return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R), color: Colors.white),
          child: Column(children: [
            Row(children: [
              Container(width: 48, height: 48,
                decoration: const BoxDecoration(shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [_accent, Color(0xFFA78BFA)])),
                child: Center(child: Text(initials, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)))),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
                Text('${ds['title'] ?? 'İç Mimar'} · ${ds['specialty'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ])),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: const Color(0xFFFFF7ED)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                  Text(' ${ds['rating'] ?? '4.8'}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFF59E0B))),
                ])),
            ]),
            if (ds['bio'] != null) Padding(padding: const EdgeInsets.only(top: 10),
              child: Text(ds['bio'], style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4), maxLines: 2)),
            const SizedBox(height: 12),
            Row(children: [
              if (ds['min_budget'] != null) Text('Min: ${ds['min_budget']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
              const Spacer(),
              GestureDetector(
                onTap: () => launchUrl(Uri.parse('https://www.evlumba.com/tasarimcilar'), mode: LaunchMode.externalApplication),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: _accent),
                  child: const Text('Profili Gör', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)))),
            ]),
          ]));
      }),
    ]);
  }
}

// ═══════════════════════════════════════════════════════
// BUDGET PLAN
// ═══════════════════════════════════════════════════════
class _BudgetPlan extends StatelessWidget {
  const _BudgetPlan(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final items = (d['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return Container(padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF6C5CE7), Color(0xFF8B5CF6)])),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('💰', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          const Text('Bütçe Planı', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
          const Spacer(),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: Colors.white.withOpacity(0.2)),
            child: Text(d['total_budget'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white))),
        ]),
        const SizedBox(height: 16),
        ...items.map((i) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle,
            color: i['priority'] == 'high' ? const Color(0xFF4ADE80) : Colors.white.withOpacity(0.4))),
          const SizedBox(width: 10),
          Expanded(child: Text(i['category'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white))),
          Text(i['amount'] ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.9))),
        ]))),
        if (d['tip'] != null) ...[
          const SizedBox(height: 10),
          Container(padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.white.withOpacity(0.12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('💡', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 8),
              Expanded(child: Text(d['tip'], style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.85), height: 1.4))),
            ])),
        ],
      ]));
  }
}

// ═══════════════════════════════════════════════════════
// QUICK TIPS
// ═══════════════════════════════════════════════════════
class _QuickTips extends StatelessWidget {
  const _QuickTips(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final tips = (d['tips'] as List?) ?? [];
    return Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R), color: Colors.white),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('💡 İpuçları', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
        const SizedBox(height: 10),
        ...tips.map((t) {
          final text = t is String ? t : (t is Map ? (t['text'] ?? '') : t.toString());
          return Padding(padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 6, height: 6, margin: const EdgeInsets.only(top: 7),
                decoration: BoxDecoration(shape: BoxShape.circle, color: _accent.withOpacity(0.5))),
              const SizedBox(width: 10),
              Expanded(child: Text(text.toString(), style: const TextStyle(fontSize: 13, color: Color(0xFF4A4458), height: 1.5))),
            ]));
        }),
      ]));
  }
}

// ═══════════════════════════════════════════════════════
// BEFORE/AFTER
// ═══════════════════════════════════════════════════════
class _BeforeAfter extends StatelessWidget {
  const _BeforeAfter(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final changes = (d['changes'] as List?)?.cast<String>() ?? [];
    return Container(padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R),
        gradient: const LinearGradient(colors: [Color(0xFFF0ECFF), Color(0xFFE8F5E9)])),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(d['title'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
        const SizedBox(height: 10),
        ...changes.map((c) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
          const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF059669)),
          const SizedBox(width: 8),
          Expanded(child: Text(c, style: const TextStyle(fontSize: 13, color: Color(0xFF4A4458), height: 1.4)))]))),
        if (d['estimated_budget'] != null) Padding(padding: const EdgeInsets.only(top: 10),
          child: Text('Tahmini: ${d['estimated_budget']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _accent))),
      ]));
  }
}

// ═══════════════════════════════════════════════════════
// IMAGE PROMPT — generate button
// ═══════════════════════════════════════════════════════
class _ImagePrompt extends StatelessWidget {
  const _ImagePrompt(this.d, {required this.onGenerate});
  final Map<String, dynamic> d;
  final void Function(String) onGenerate;
  @override
  Widget build(BuildContext context) {
    final title = d['title'] as String? ?? 'Tasarım Görseli';
    final prompt = d['prompt'] as String? ?? '';
    return Container(padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFFF0ECFF), Color(0xFFE8F4FD)])),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome, size: 18, color: _accent),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink))),
        ]),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, height: 44,
          child: ElevatedButton.icon(
            onPressed: () => onGenerate(prompt),
            icon: const Icon(Icons.brush_rounded, size: 18),
            label: const Text('Görseli Oluştur', style: TextStyle(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0))),
      ]));
  }
}
'''

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print("  ✅ chat_detail_screen.dart — complete rewrite")

# ═══════════════════════════════════════════════════════
# Fix profile_screen.dart — remove dead imports
# ═══════════════════════════════════════════════════════
profile_path = os.path.join(BASE, "lib", "views", "profile_screen.dart")
if os.path.exists(profile_path):
    with open(profile_path, 'r', encoding='utf-8') as f:
        p = f.read()
    
    import re
    p = re.sub(r"import 'credit_store_screen\.dart';\n?", "", p)
    p = re.sub(r"import 'login_screen\.dart';\n?", "", p)
    p = p.replace("CreditService()", "null")
    p = p.replace("final _creditService = null;", "// CreditService removed")
    # Remove any CreditService references
    p = re.sub(r".*CreditService.*\n", "", p)
    p = re.sub(r".*credit_store_screen.*\n", "", p)
    p = re.sub(r".*login_screen.*\n", "", p)
    
    with open(profile_path, 'w', encoding='utf-8') as f:
        f.write(p)
    print("  ✅ profile_screen.dart — dead imports removed")

print()
print("  Changes:")
print("  🎨 Chat bg: white → #FAFAFA (subtle warmth)")
print("  🐨 Koala avatar: uses koalas.png logo")
print("  💬 Empty state: koala greeting + suggestion chips")
print("  ❌ Error card: red with 'Tekrar dene' button")
print("  🏷️ Products: tappable → evlumba.com deep link + 'evlumba' badge")
print("  👤 Designers: initials avatar + bio + 'Profili Gör' → evlumba")
print("  💰 Budget: gradient purple card")
print("  🎨 Style: gradient header")
print("  🔘 Chips: handles both 'chips' and 'options' keys")
print("  🖼️ Image prompt: generate button")
print("  🔄 Retry: error state with retry button")
print()
print("  Test: .\\run.ps1")
