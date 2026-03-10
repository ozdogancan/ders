import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/chatgpt_service.dart';
import '../services/credit_service.dart';
import '../stores/question_store.dart';
import 'credit_store_screen.dart';
import '../services/analytics_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.questionId});
  final String questionId;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatGptService _chat = ChatGptService();
  final CreditService _credit = CreditService();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;
  bool _coachMode = false;
  int _credits = -1;
  bool _popupDone = false;
  
  bool _feedbackMode = false;
  final TextEditingController _feedbackCtrl = TextEditingController();

  LocalQuestion? get _q => QuestionStore.instance.getById(widget.questionId);
  String get _tutorAsset => tutorAssetForSubject(_q?.subject ?? 'Matematik');

  @override
  void initState() {
    super.initState();
    QuestionStore.instance.addListener(_onUpdate);
    
    _loadCredits();
    _loadPopup();
    _scroll.addListener(_checkScrollButton);
    Analytics.chatOpened(widget.questionId, _q?.subject ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firstOpen = false;
    });
  }

  @override
  void dispose() {
    QuestionStore.instance.removeListener(_onUpdate);
    _input.dispose();
    _scroll.dispose();
    _feedbackCtrl.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
    if (!_firstOpen) _scrollEnd(true);
  }



  bool _firstOpen = true;
  bool _showScrollDown = false;

  void _scrollEnd(bool animate) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      if (animate) {
        _scroll.animateTo(_scroll.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      } else {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _checkScrollButton() {
    if (!_scroll.hasClients) return;
    final show = _scroll.position.maxScrollExtent - _scroll.position.pixels > 200;
    if (show != _showScrollDown && mounted) setState(() => _showScrollDown = show);
  }

  Future<void> _loadCredits() async {
    final c = await _credit.getCredits();
    if (mounted) setState(() => _credits = c);
  }

  Future<void> _loadPopup() async {
    final p = await SharedPreferences.getInstance();
    _popupDone = p.getBool('credit_popup_v1') ?? false;
  }

  Future<void> _markPopup() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('credit_popup_v1', true);
    _popupDone = true;
  }

  Future<bool> _creditPopup() async {
    if (_popupDone) return true;
    final ok = await showDialog<bool>(context: context, barrierDismissible: false,
      builder: (ctx) => Dialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 64, height: 64,
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF6366F1).withAlpha(15)),
              child: const Icon(Icons.bolt_rounded, size: 32, color: Color(0xFF6366F1))),
            const SizedBox(height: 16),
            const Text('Kredi Bilgilendirmesi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
            const SizedBox(height: 10),
            Text('Koala ile her mesajda 1 kredi kullan\u0131l\u0131r.', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.5)),
            const SizedBox(height: 12),
            Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.bolt_rounded, size: 18, color: Color(0xFF6366F1)),
                const SizedBox(width: 6),
                Text('Mevcut kredin: $_credits', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF6366F1))),
              ])),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, height: 48,
              child: FilledButton(onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6366F1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: const Text('Anlad\u0131m', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Vazge\u00e7', style: TextStyle(color: Colors.grey.shade500))),
          ]))));
    if (ok == true) { await _markPopup(); return true; }
    return false;
  }

  Future<void> _sendMsg({String? preset}) async {
    final text = preset ?? _input.text.trim();
    if (text.isEmpty || _sending) return;
    final q = _q;
    if (q == null) return;
    if (_credits <= 0) { _noCredit(); return; }
    if (!_popupDone) { final ok = await _creditPopup(); if (!ok) return; }

    _input.clear();
    QuestionStore.instance.addChat(q.id, ChatMsg(role: 'user', text: text));
    setState(() => _sending = true);

    try {
      final upd = await _credit.spendOneCredit();
      setState(() => _credits = upd);
      final msgs = q.chatMessages.map((m) => <String, String>{'role': m.role == 'ai' ? 'assistant' : 'user', 'content': m.text}).toList();

      final sys = _coachMode
        ? 'Sen Koala uygulamasinin AI kocusun. Ogrenciyle benzer soru cozuyorsun. '
          'Turkce yaz. Markdown KULLANMA. Duz metin yaz. '
          'Soruyu KENDIN COZME. Ogrenciye yonlendirici soru sor. '
          'Dogru cevap verirse kutla ve sonraki adima gec. Yanlis verirse ipucu ver. '
          'Her mesajda sadece 1 adim sor. Kisa ve net ol, 2-4 satir. '
          'Formulleri duz yazdir (3 x 5 = 15 gibi), LaTeX kullanma.'
        : 'Sen Koala uygulamasinin AI kocusun. Turkce yaz. Markdown KULLANMA. Duz metin yaz. '
          'Kisa ve net cevap ver. Bombing yapma. '
          'Formulleri LaTeX formatinda yaz ama dolar isareti KULLANMA. '
          'SADECE JSON formatinda cevap ver, baska hicbir sey yazma. '
          'JSON semasi: {"summary":"ozet","steps":[{"explanation":"aciklama","formula":"latex veya null"}],"final_answer":"sonuc","tip":"motivasyon"}';

      final reply = await _chat.askConversation(systemPrompt: sys, messages: msgs);
      QuestionStore.instance.addChat(q.id, ChatMsg(role: 'ai', text: reply));
    } catch (e) {
      QuestionStore.instance.addChat(q.id, ChatMsg(role: 'ai', text: 'Bir hata olu\u015ftu, tekrar dene.'));
    }
    if (mounted) { setState(() => _sending = false); _loadCredits(); }
  }

  void _startCoach() {
    _coachMode = true;
    _sendMsg(preset: 'Benzer bir soruyu birlikte \u00e7\u00f6zmek istiyorum. Beni y\u00f6nlendirerek \u00e7\u00f6zd\u00fcr.');
  }

  Future<void> _noCredit() async {
    final go = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Kredi bitti', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('Mesaj g\u00f6ndermek i\u00e7in kredi gerekiyor.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazge\u00e7')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6366F1)), child: const Text('Kredi Al')),
        ]));
    if (go == true && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreditStoreScreen()));
      _loadCredits();
    }
  }

  List<String> _smartChips() {
    final q = _q;
    if (q == null) return [];
    final msgs = q.chatMessages;
    if (msgs.isEmpty) return [];
    final lastAi = msgs.lastWhere((m) => m.role == 'ai', orElse: () => ChatMsg(role: 'ai', text: '')).text;
    final lower = lastAi.toLowerCase();
    
    if (_coachMode) {
      if (lower.contains('?')) {
        if (lower.contains('hangi') || lower.contains('ilk')) return ['Nas\u0131l ba\u015flamal\u0131y\u0131m?', '\u0130pucu ver'];
        if (lower.contains('sonuc') || lower.contains('ka\u00e7')) return ['Kontrol eder misin?', '\u0130pucu ver'];
        return ['Haz\u0131r\u0131m', 'Biraz daha a\u00e7\u0131kla'];
      }
      if (lower.contains('tebrik') || lower.contains('do\u011fru')) return ['Sonraki ad\u0131m', 'Ba\u015fka soru'];
      return ['Devam edelim', 'Tekrar a\u00e7\u0131kla'];
    }
    if (lower.contains('?')) {
      if (lower.contains('anla') || lower.contains('bilmek')) return ['Evet, anlat', 'Hay\u0131r, ge\u00e7'];
      return ['Evet', 'A\u00e7\u0131klar m\u0131s\u0131n?'];
    }
    if (lower.contains('cevap') || lower.contains('sonu\u00e7')) return ['Neden b\u00f6yle?', 'Farkl\u0131 y\u00f6ntem var m\u0131?'];
    if (lower.contains('ad\u0131m')) return ['Daha detayl\u0131 anlat', 'Bu ad\u0131m\u0131 atlayabilir miyim?'];
    return ['Daha basit anlat', 'Neden b\u00f6yle?'];
  }

  // Clean LaTeX: remove $ signs
  String _cleanLatex(String s) {
    return s.replaceAll(RegExp(r'^\$+|\$+$'), '').replaceAll('\$', '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q;
    if (q == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Soru bulunamad\u0131')));

    final solved = q.status == QStatus.solved;
    final hasAi = q.chatMessages.isNotEmpty && q.chatMessages.first.role == 'ai';
    final userCount = q.chatMessages.where((m) => m.role == 'user').length;
    final showCoach = solved && hasAi && !_coachMode && userCount == 0;
    final chips = _smartChips();

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white, surfaceTintColor: Colors.transparent, elevation: 0,
        leading: IconButton(onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1E293B))),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: const Color(0xFF6366F1).withAlpha(15), borderRadius: BorderRadius.circular(99)),
            child: Text(q.subject, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF6366F1)))),
          const SizedBox(width: 8),
          if (q.status == QStatus.solving)
            Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.amber.shade600)),
              const SizedBox(width: 4),
              Text('\u00c7\u00f6z\u00fcl\u00fcyor...', style: TextStyle(fontSize: 12, color: Colors.amber.shade700, fontWeight: FontWeight.w600))])
          else
            const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF22C55E)),
              SizedBox(width: 4),
              Text('\u00c7\u00f6z\u00fcld\u00fc', style: TextStyle(fontSize: 12, color: Color(0xFF22C55E), fontWeight: FontWeight.w600))]),
        ]),
        centerTitle: true,
        actions: [
          Padding(padding: const EdgeInsets.only(right: 12),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: const Color(0xFF6366F1).withAlpha(15), borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.bolt_rounded, size: 14, color: Color(0xFF6366F1)),
                const SizedBox(width: 3),
                Text(_credits < 0 ? '' : '$_credits', style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.w800, fontSize: 13)),
              ]))),
        ],
      ),
      body: Stack(children: [
        Column(children: [
          Expanded(
            child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
              // Question image
              // Question image
              Center(child: GestureDetector(
                onTap: () => _showFullImage(q.imageBytes),
                child: Container(margin: const EdgeInsets.only(bottom: 16),
                constraints: const BoxConstraints(maxWidth: 220, maxHeight: 160),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 8, offset: const Offset(0, 4))]),
                child: ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.memory(q.imageBytes, fit: BoxFit.cover))))),

              // All messages
              ...q.chatMessages.asMap().entries.map((e) {
                final m = e.value;
                if (m.role == 'user') return _userBubble(m.text);
                return _smartAiMsg(m.text, q.subject);
              }),

              // Rating
              if (hasAi && solved && q.rating == null && !_coachMode && !_feedbackMode)
                _ratingWidget(q),

              // Rating feedback (3 stars or less)
              if (_feedbackMode) _feedbackWidget(q),

              // Rated
              if (q.rating != null && !_feedbackMode) _ratedWidget(q.rating!),

              // Coach
              if (showCoach) _coachBtn(),

              if (_sending) _typingBubble(),
            ])),

          // Input
          if (solved)
            Container(padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
              decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE2E8F0)))),
              child: SafeArea(top: false,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (chips.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: chips.map((c) => Expanded(
                        child: GestureDetector(onTap: () => _sendMsg(preset: c),
                          child: Container(margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(color: const Color(0xFF6366F1).withAlpha(8),
                              borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF6366F1).withAlpha(20))),
                            child: Text(c, textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6366F1))))))).toList())),
                  Row(children: [
                    Expanded(child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(24)),
                      child: TextField(controller: _input, onSubmitted: (_) => _sendMsg(),
                        textInputAction: TextInputAction.send,
                        decoration: const InputDecoration(hintText: 'Soru sor...',
                          hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                          border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12))))),
                    const SizedBox(width: 8),
                    Container(width: 44, height: 44,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF6366F1)),
                      child: IconButton(onPressed: _sending ? null : () => _sendMsg(),
                        icon: _sending
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 20))),
                  ]),
                ]))),
        ]),

        // Scroll to bottom button
        if (_showScrollDown)
          Positioned(
            bottom: solved ? 120 : 20,
            right: 16,
            child: GestureDetector(
              onTap: () => _scrollEnd(true),
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF6366F1), size: 24),
              ),
            ),
          ),
      ]),
    ));
  }

  // ═══════════════════════════════════════
  // SMART AI MESSAGE (structured or fallback)
  // ═══════════════════════════════════════

  Widget _smartAiMsg(String raw, String subject) {
    final structured = StructuredAnswer.tryParse(raw);
    if (structured != null) return _structuredCard(structured);

    // Fallback: parse text into visual cards
    final cleaned = raw.replaceAll(RegExp(r'\*\*'), '').replaceAll(RegExp(r'^---+\$', multiLine: true), '').replaceAll(RegExp(r'^#{1,3}\s*', multiLine: true), '').trim();
    final lines = cleaned.split('\n').where((s) => s.trim().isNotEmpty).toList();
    
    if (lines.length <= 1) {
      // Short message - simple bubble
      return Padding(padding: const EdgeInsets.only(bottom: 12, right: 24),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 4, right: 8), child: _avatar(28)),
          Flexible(child: Container(padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(6), blurRadius: 6, offset: const Offset(0, 2))]),
            child: SelectableText(cleaned, style: const TextStyle(fontSize: 14, color: Color(0xFF334155), height: 1.6)))),
        ]));
    }

    // Multi-line: build visual cards
    const stepColors = [Color(0xFF6366F1), Color(0xFF0EA5E9), Color(0xFF8B5CF6), Color(0xFF14B8A6), Color(0xFFF59E0B), Color(0xFFEC4899)];
    int stepIdx = 0;

    return Padding(padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _avatar(32), const SizedBox(width: 10),
          Text(tutorNameForSubject(_q?.subject ?? 'Matematik'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
        ]),
        const SizedBox(height: 12),
        ...lines.map((line) {
          final trimmed = line.trim();
          final bool isFormula = _looksLikeFormula(trimmed);
          final bool isQuestion = trimmed.endsWith('?');
          
          if (isFormula) {
            // Formula card
            final formulaText = _extractFormula(trimmed);
            final c = stepColors[stepIdx % stepColors.length];
            return Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: c.withAlpha(8), borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.withAlpha(25))),
              child: Math.tex(_cleanLatex(formulaText),
                  textStyle: TextStyle(fontSize: 18, color: c),
                  mathStyle: MathStyle.display,
                  onErrorFallback: (_) => Text(formulaText,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c, fontFamily: 'monospace'))));
          }
          
          if (isQuestion) {
            // Question highlight card
            return Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [const Color(0xFF6366F1).withAlpha(10), const Color(0xFF8B5CF6).withAlpha(6)]),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF6366F1).withAlpha(20))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.help_outline_rounded, size: 18, color: Color(0xFF6366F1)),
                const SizedBox(width: 10),
                Expanded(child: Text(trimmed, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B), height: 1.5))),
              ]));
          }

          // Regular text card with step number
          final c = stepColors[stepIdx % stepColors.length];
          stepIdx++;
          return Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.withAlpha(20)),
              boxShadow: [BoxShadow(color: c.withAlpha(6), blurRadius: 6, offset: const Offset(0, 2))]),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 24, height: 24,
                decoration: BoxDecoration(shape: BoxShape.circle, color: c.withAlpha(15)),
                child: Center(child: Text('\u2022', style: TextStyle(color: c, fontSize: 14, fontWeight: FontWeight.w800)))),
              const SizedBox(width: 10),
              Expanded(child: Text(trimmed, style: const TextStyle(fontSize: 14, color: Color(0xFF334155), height: 1.5))),
            ]));
        }),
      ]));
  }

  Widget _structuredCard(StructuredAnswer a) {
    const colors = [Color(0xFF6366F1), Color(0xFF0EA5E9), Color(0xFF8B5CF6), Color(0xFF14B8A6), Color(0xFFF59E0B), Color(0xFFEC4899)];

    return Padding(padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _avatar(36), const SizedBox(width: 10),
          Text(tutorNameForSubject(_q?.subject ?? 'Matematik'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
          const SizedBox(width: 6),
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFF22C55E).withAlpha(15), borderRadius: BorderRadius.circular(6)),
            child: const Text('\u00c7\u00f6z\u00fcm', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF22C55E)))),
        ]),
        const SizedBox(height: 14),

        if (a.summary.isNotEmpty)
          Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(14)),
            child: Text(a.summary, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF475569), height: 1.5))),

        ...a.steps.asMap().entries.map((e) {
          final i = e.key; final step = e.value; final c = colors[i % colors.length];
          return Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.withAlpha(30)),
              boxShadow: [BoxShadow(color: c.withAlpha(8), blurRadius: 8, offset: const Offset(0, 3))]),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 28, height: 28,
                decoration: BoxDecoration(shape: BoxShape.circle, color: c.withAlpha(20)),
                child: Center(child: Text('${i + 1}', style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.w800)))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _renderMixedText(step.explanation),
                if (step.formula != null && step.formula!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(color: c.withAlpha(8), borderRadius: BorderRadius.circular(10)),
                    child: Math.tex(_cleanLatex(step.formula!),
                      textStyle: TextStyle(fontSize: 16, color: c),
                      mathStyle: MathStyle.display,
                      onErrorFallback: (_) => Text(_cleanLatex(step.formula!),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c, fontFamily: 'monospace')))),
                ],
              ])),
            ]));
        }),

        if (a.finalAnswer.isNotEmpty)
          Container(width: double.infinity, margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [const Color(0xFF6366F1).withAlpha(15), const Color(0xFF22C55E).withAlpha(10)]),
              borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF6366F1).withAlpha(25))),
            child: Row(children: [
              Container(width: 36, height: 36, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF22C55E).withAlpha(20)),
                child: const Icon(Icons.check_rounded, size: 20, color: Color(0xFF22C55E))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Cevap', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                const SizedBox(height: 2),
                Text(a.finalAnswer, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
              ])),
            ])),

        if (a.tip != null && a.tip!.isNotEmpty)
          Container(width: double.infinity, margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFBBF24).withAlpha(12), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFBBF24).withAlpha(25))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('\u{1F4A1}', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(child: Text(a.tip!, style: const TextStyle(fontSize: 13, color: Color(0xFF78350F), height: 1.4))),
            ])),
      ]));
  }

  // ═══════════════════════════════════════
  // RATING
  // ═══════════════════════════════════════

  Widget _ratingWidget(LocalQuestion q) {
    return Padding(padding: const EdgeInsets.only(bottom: 12),
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 8, offset: const Offset(0, 2))]),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('\u00c7\u00f6z\u00fcm\u00fc de\u011ferlendir', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (i) =>
            GestureDetector(onTap: () {
              QuestionStore.instance.rate(q.id, i + 1);
              if (i + 1 <= 3) setState(() => _feedbackMode = true);
            },
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Container(width: 42, height: 42,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFFBBF24).withAlpha(10)),
                  child: const Icon(Icons.star_rounded, size: 30, color: Color(0xFFE2E8F0))))))),
        ])));
  }

  Widget _feedbackWidget(LocalQuestion q) {
    return Padding(padding: const EdgeInsets.only(bottom: 12),
      child: Container(padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: List.generate(5, (i) =>
            Icon(i < (q.rating ?? 0) ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 20, color: i < (q.rating ?? 0) ? const Color(0xFFFBBF24) : Colors.grey.shade300))),
          const SizedBox(height: 10),
          Text('Neyi daha iyi yapabiliriz?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          TextField(controller: _feedbackCtrl, maxLines: 2, maxLength: 200,
            decoration: InputDecoration(
              hintText: 'Geri bildirimini yaz...',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              filled: true, fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1))),
              contentPadding: const EdgeInsets.all(12), counterText: '')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextButton(onPressed: () => setState(() => _feedbackMode = false),
              child: Text('Ge\u00e7', style: TextStyle(color: Colors.grey.shade500)))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton(onPressed: () {
              setState(() => _feedbackMode = false);
              ScaffoldMessenger.of(context).clearSnackBars(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                behavior: SnackBarBehavior.floating, backgroundColor: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16), duration: const Duration(seconds: 3),
                content: const Text('Geri bildiriminizi ald\u0131k, de\u011ferlendirip iyile\u015ftirece\u011fiz.',
                  style: TextStyle(color: Colors.white, fontSize: 13))));
            }, style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6366F1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('G\u00f6nder', style: TextStyle(fontWeight: FontWeight.w700)))),
          ]),
        ])));
  }

  Widget _ratedWidget(int stars) {
    final msgs = ['', 'Geri bildirim i\u00e7in te\u015fekk\u00fcrler!', '\u0130yile\u015ftirece\u011fiz!', 'Te\u015fekk\u00fcrler!', 'Harika, memnun olduk!', 'M\u00fckemmel! \u{1F680}'];
    return Padding(padding: const EdgeInsets.only(bottom: 12),
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [const Color(0xFFFBBF24).withAlpha(10), const Color(0xFFF59E0B).withAlpha(6)]),
          borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFFBBF24).withAlpha(20))),
        child: Row(children: [
          ...List.generate(5, (i) => Icon(i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 16, color: i < stars ? const Color(0xFFFBBF24) : Colors.grey.shade300)),
          const SizedBox(width: 10),
          Expanded(child: Text(msgs[stars.clamp(1, 5)], style: TextStyle(fontSize: 12, color: Colors.amber.shade800, fontWeight: FontWeight.w500))),
        ])));
  }

  // ═══════════════════════════════════════
  // WIDGETS
  // ═══════════════════════════════════════

  Widget _renderMixedText(String text) {
    // Split text by comma or period followed by space to find formula boundaries
    // Look for LaTeX-like patterns: things with ^, _, \frac, \left etc.
    final formulaRegex = RegExp(r'(?<![a-zA-ZığüşöçİĞÜŞÖÇ])([a-zA-Z0-9]*(?:\\[a-zA-Z]+|[\^_])[^\s,\.;:!?]*(?:\{[^}]*\})*[^\s,\.;:!?]*)(?![a-zA-ZığüşöçİĞÜŞÖÇ])');
    final parts = <InlineSpan>[];
    int lastEnd = 0;
    
    for (final match in formulaRegex.allMatches(text)) {
      // Add text before the formula
      if (match.start > lastEnd) {
        parts.add(TextSpan(text: text.substring(lastEnd, match.start),
          style: const TextStyle(fontSize: 14, color: Color(0xFF334155), height: 1.5)));
      }
      final formula = match.group(0)!.trim();
      // Only render as LaTeX if it actually looks like math
      if (formula.contains('^') || formula.contains('\\') || formula.contains('_') || formula.contains('\\frac')) {
        parts.add(WidgetSpan(alignment: PlaceholderAlignment.middle,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Math.tex(_cleanLatex(formula),
              textStyle: const TextStyle(fontSize: 15, color: Color(0xFF6366F1)),
              onErrorFallback: (_) => Text(formula,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF6366F1)))))));
      } else {
        parts.add(TextSpan(text: formula,
          style: const TextStyle(fontSize: 14, color: Color(0xFF334155), height: 1.5)));
      }
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      parts.add(TextSpan(text: text.substring(lastEnd),
        style: const TextStyle(fontSize: 14, color: Color(0xFF334155), height: 1.5)));
    }
    if (parts.isEmpty) {
      return Text(text, style: const TextStyle(fontSize: 14, color: Color(0xFF334155), height: 1.5));
    }
    return Text.rich(TextSpan(children: parts));
  }

  void _showFullImage(Uint8List bytes) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim, __) {
        return FadeTransition(opacity: anim,
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            onVerticalDragEnd: (d) { if (d.primaryVelocity != null && d.primaryVelocity!.abs() > 200) Navigator.pop(context); },
            child: Center(child: InteractiveViewer(
              minScale: 0.5, maxScale: 4.0,
              child: Padding(padding: const EdgeInsets.all(24),
                child: ClipRRect(borderRadius: BorderRadius.circular(16),
                  child: Image.memory(bytes, fit: BoxFit.contain)))))));
      }));
  }

  Widget _avatar(double s) {
    return Container(width: s, height: s,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF6366F1).withAlpha(30))),
      child: ClipOval(child: Image.asset(_tutorAsset, fit: BoxFit.cover, alignment: Alignment.topCenter,
        errorBuilder: (_, __, ___) => Container(color: const Color(0xFF6366F1).withAlpha(15),
          child: Icon(Icons.auto_awesome, size: s * 0.4, color: const Color(0xFF6366F1))))));
  }

  Widget _userBubble(String text) {
    return Padding(padding: const EdgeInsets.only(bottom: 12, left: 40),
      child: Align(alignment: Alignment.centerRight,
        child: Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFF6366F1), borderRadius: BorderRadius.circular(18)),
          child: Text(text, style: const TextStyle(fontSize: 14, color: Colors.white, height: 1.5)))));
  }

  Widget _solvingBubble() {
    return Padding(padding: const EdgeInsets.only(bottom: 12, right: 40),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 4, right: 8), child: _avatar(28)),
        Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE2E8F0))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey.shade400)),
            const SizedBox(width: 10),
            Text('Koala \u00e7\u00f6z\u00fcm \u00fcretiyor...', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          ])),
      ]));
  }

  Widget _typingBubble() {
    return Padding(padding: const EdgeInsets.only(bottom: 12, right: 40),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 4, right: 8), child: _avatar(28)),
        Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE2E8F0))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey.shade400)),
            const SizedBox(width: 10),
            Text('Yaz\u0131yor...', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          ])),
      ]));
  }

  Widget _coachBtn() {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [const Color(0xFF6366F1).withAlpha(10), const Color(0xFF8B5CF6).withAlpha(8)]),
          borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF6366F1).withAlpha(20))),
        child: Material(color: Colors.transparent,
          child: InkWell(onTap: _startCoach, borderRadius: BorderRadius.circular(18),
            child: Padding(padding: const EdgeInsets.all(16),
              child: Row(children: [
                Container(width: 44, height: 44, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF6366F1).withAlpha(15)),
                  child: const Icon(Icons.psychology_rounded, color: Color(0xFF6366F1), size: 24)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Benzerini birlikte \u00e7\u00f6zelim', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                  const SizedBox(height: 3),
                  Text('Tutor seni y\u00f6nlendirsin, sen \u00e7\u00f6z', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ])),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF6366F1), borderRadius: BorderRadius.circular(99)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.bolt_rounded, size: 12, color: Colors.white), SizedBox(width: 2),
                    Text('1', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))])),
              ]))))));
  }

  bool _looksLikeFormula(String s) {
    final trimmed = s.trim();
    // Only pure formula lines (mostly numbers and operators, minimal text)
    final textChars = trimmed.replaceAll(RegExp(r'[0-9\s+\-*/÷×=.,()\[\]{}\\]'), '');
    // If more than 30% is text, it's not a formula
    if (trimmed.isEmpty) return false;
    if (textChars.length > trimmed.length * 0.3) return false;
    final mathPattern = RegExp(r'[0-9]+\s*[+\-*/÷×=]\s*[0-9]');
    return mathPattern.hasMatch(trimmed);
  }

  String _extractFormula(String s) {
    final trimmed = s.trim();
    return trimmed
      .replaceAll('÷', ' \\div ')
      .replaceAll('×', ' \\times ')
      .replaceAll(' x ', ' \\times ')
      .replaceAll(RegExp(r'(?<=\d)x(?=\d)'), ' \\times ')
      .replaceAll(RegExp(r'(\d+)/(\d+)'), r'\\frac{\1}{\2}');
  }

}





