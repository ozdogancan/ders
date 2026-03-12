import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/chatgpt_service.dart';
import '../services/credit_service.dart';
import '../stores/question_store.dart';
import 'chat_screen.dart';
import 'credit_store_screen.dart';
import '../services/analytics_service.dart';

class QuestionShareScreen extends StatefulWidget {
  const QuestionShareScreen({super.key});
  @override
  State<QuestionShareScreen> createState() => _QuestionShareScreenState();
}

class _QuestionShareScreenState extends State<QuestionShareScreen> {
  final ImagePicker _picker = ImagePicker();
  final CreditService _creditService = CreditService();
  final ChatGptService _chatGptService = ChatGptService();

  Uint8List? _imageBytes;
  String? _detectedSubject;
  String? _selectedSubject;
  bool _detectingSubject = false;
  bool _detectionFailed = false;
  int _credits = 1;
  bool _loading = true;
  bool _sending = false;
  int _step = 0;

  static const List<String> _subjects = [
    'Matematik', 'Geometri', 'Fizik', 'Kimya', 'Biyoloji',
    'T\u00fcrk\u00e7e', 'Edebiyat', 'Tarih', 'Co\u011frafya',
    'Felsefe', '\u0130ngilizce', 'Din K\u00fclt\u00fcr\u00fc',
  ];

  @override
  void initState() {
    super.initState();
    _loadCredits();
  }

  Future<void> _loadCredits() async {
    final c = await _creditService.getCredits();
    if (!mounted) return;
    setState(() { _credits = c; _loading = false; });
  }


  void _showImageSourcePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Text('Foto\u011fraf Se\u00e7', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
          const SizedBox(height: 20),
          ListTile(leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFF6366F1).withAlpha(15), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.camera_alt_rounded, color: Color(0xFF6366F1), size: 20)), title: const Text('Kamera ile \u00c7ek', style: TextStyle(fontWeight: FontWeight.w600)), onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.camera); }),
          const Divider(height: 1, indent: 60, endIndent: 20),
          ListTile(leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFF0EA5E9).withAlpha(15), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.photo_library_rounded, color: Color(0xFF0EA5E9), size: 20)), title: const Text('Galeriden Se\u00e7', style: TextStyle(fontWeight: FontWeight.w600)), onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.gallery); }),
          const SizedBox(height: 8),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: SizedBox(width: double.infinity, height: 48, child: TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Vazge\u00e7', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600, fontSize: 15))))),
          const SizedBox(height: 8),
        ]))));
  }
  Future<void> _pickImage(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 90);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _step = 1;
      _detectedSubject = null;
      _selectedSubject = null;
    });
    _detectSubject(bytes);
  }

  Future<void> _detectSubject(Uint8List bytes) async {
    setState(() => _detectingSubject = true);
    try {
      final result = await _chatGptService.askImageBytes(bytes,
        prompt: 'Bu fotograftaki sorunun hangi ders ile ilgili oldugunu tek kelimeyle yaz. '
               'Sadece su seceneklerden birini yaz: '
               'Matematik, Geometri, Fizik, Kimya, Biyoloji, Turkce, Edebiyat, Tarih, Cografya, Felsefe, Ingilizce');
      final cleaned = result.trim().replaceAll('.', '').replaceAll(',', '');
      String? matched;
      final lower = cleaned.toLowerCase();
      if (lower.contains('mat')) { matched = 'Matematik'; }
      else if (lower.contains('geo')) { matched = 'Geometri'; }
      else if (lower.contains('fiz')) { matched = 'Fizik'; }
      else if (lower.contains('kim')) { matched = 'Kimya'; }
      else if (lower.contains('bio') || lower.contains('biyo')) { matched = 'Biyoloji'; }
      else if (lower.contains('turk') || lower.contains('t\u00fcrk')) { matched = 'T\u00fcrk\u00e7e'; }
      else if (lower.contains('ede')) { matched = 'Edebiyat'; }
      else if (lower.contains('tar')) { matched = 'Tarih'; }
      else if (lower.contains('cog') || lower.contains('co\u011f')) { matched = 'Co\u011frafya'; }
      else if (lower.contains('fel')) { matched = 'Felsefe'; }
      else if (lower.contains('ing')) { matched = '\u0130ngilizce'; }
      else if (lower.contains('din')) { matched = 'Din K\u00fclt\u00fcr\u00fc'; }
      else { matched = null; }
      if (!mounted) return;
      if (matched == null) {
        setState(() { _detectionFailed = true; _detectingSubject = false; });
      } else {
        setState(() { _detectionFailed = false; _detectedSubject = matched; _selectedSubject = matched; _detectingSubject = false; });
      // AI tespit ettiyse otomatik gonder
      _send();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() { _detectingSubject = false; _detectionFailed = true; });
    }
  }

  void _retake() {
    setState(() { _imageBytes = null; _selectedSubject = null; _detectedSubject = null; _detectionFailed = false; _step = 0; });
  }

  Future<void> _send() async {
    if (_imageBytes == null || _selectedSubject == null) return;
    if (_credits <= 0) { _showNoCredit(); return; }
    setState(() { _step = 2; _sending = true; });
    try {
      await _creditService.spendOneCredit();
      final q = QuestionStore.instance.add(imageBytes: _imageBytes!, subject: _selectedSubject!);
      Analytics.questionSubmitted(q.id, _selectedSubject!);
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      _solveInBackground(q.id, _imageBytes!, _selectedSubject!);
      if (!mounted) return;
      // Direkt chat ekranina git - basarili ekranini gosterme
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ChatScreen(questionId: q.id)));
    } catch (e) {
      if (!mounted) return;
      setState(() { _step = 1; _sending = false; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  void _solveInBackground(String qId, Uint8List bytes, String subject) async {
    try {
      final sw = Stopwatch()..start();
      final answer = await _chatGptService.askImageBytes(bytes,
        prompt: subject == 'Matematik' || subject == 'Geometri' ? _getMathPrompt(subject, bytes) : _getGeneralPrompt(subject));
      final elapsed = sw.elapsedMilliseconds;
      if (elapsed < 5000) await Future.delayed(Duration(milliseconds: 5000 - elapsed));
      QuestionStore.instance.solve(qId, answer);
      Analytics.questionSolved(qId, elapsed ~/ 1000, subject);
    } catch (_) {
      QuestionStore.instance.setError(qId);
      Analytics.questionSolveError(qId);
      try { await CreditService().refundOneCredit(); } catch (_) {}
    }
  }

  String _getMathPrompt(String subject, dynamic bytes) {
    return '$subject soruyu coz. SADECE JSON dondur. '
      'Once soruya bak: direkt hesaplama ise TIP1, metin problemi ise TIP2 olarak coz. '
      'TIP1 (3-4 adim, kisa oz): given/find/modeling null birak. Gereksiz uzatma. '
      'TIP2 (4-6 adim, detayli): given/find/modeling DOLDUR. HER adimda reasoning yaz. 1 adim is_critical:true. Samimi anlat. '
      'ORTAK JSON: {"question_type":"problem","summary":"aciklama",'
      '"given":["veri"] veya null,"find":"istenen" veya null,"modeling":"formul" veya null,'
      '"steps":[{"explanation":"aciklama","formula":"saf LaTeX veya null","reasoning":"neden veya null","is_critical":false}],'
      '"final_answer":"sonuc","golden_rule":"kural","tip":"motivasyon"} '
      'FORMUL KURALLARI: formula alanina SADECE saf matematik. '
      'YASAK: \\text, \\mathrm, \\boxed, \\newline, Turkce karakter. '
      'Degiskenleri tek harf yap: x, y, A, B. '
      'LaTeX: \\frac{a}{b}, \\times, \\div, \\Rightarrow, \\cdot. '
      'Dolar isareti KULLANMA. final_answer kisa. tip samimi.';
  }

  String _getGeneralPrompt(String subject) {
    return '$subject soruyu coz. SADECE JSON dondur. Turkce yaz. 4-6 adim. '
      'HER adimda reasoning yaz. 1 adim is_critical:true. golden_rule zorunlu. '
      'FORMUL KURALLARI: formula alanina SADECE saf matematik. '
      'YASAK: \\text, \\boxed, Turkce karakter. '
      'LaTeX: \\frac{a}{b}, \\times, \\div. Dolar isareti KULLANMA. '
      'JSON: {"question_type":"genel","summary":"ozet",'
      '"steps":[{"explanation":"aciklama","reasoning":"neden","formula":"LaTeX veya null","is_critical":false}],'
      '"final_answer":"sonuc","golden_rule":"kural","tip":"motivasyon"}';
  }

  Future<void> _showNoCredit() async {
    final go = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Kredi bitti', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('Soru sormak i\u00e7in kredi gerekiyor.'),
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

  void _goHome() { Navigator.of(context).pop(); }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF6366F1))));
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _step == 3 ? null : AppBar(
        backgroundColor: Colors.white, surfaceTintColor: Colors.transparent, elevation: 0,
        leading: IconButton(
          onPressed: () { if (_step == 1) { _retake(); } else { Navigator.pop(context); } },
          icon: Icon(_step == 1 ? Icons.arrow_back_rounded : Icons.close_rounded, color: const Color(0xFF1E293B))),
        title: Text(_step == 0 ? 'Soru Sor' : _step == 1 ? 'Soru G\u00f6nder' : 'G\u00f6nderiliyor...',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
        centerTitle: true,
        actions: [
          Padding(padding: const EdgeInsets.only(right: 12),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: const Color(0xFF6366F1).withAlpha(15), borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.bolt_rounded, size: 14, color: Color(0xFF6366F1)),
                const SizedBox(width: 3),
                Text('$_credits', style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.w800, fontSize: 13)),
              ]))),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: switch (_step) { 0 => _buildPicker(), 1 => _buildConfig(), 2 => _buildSolving(), _ => _buildSuccess() },
      ),
    );
  }

  Widget _buildPicker() {
    return Center(key: const ValueKey(0), child: Container(
      constraints: const BoxConstraints(maxWidth: 420), padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 120, height: 120,
          decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF6366F1).withAlpha(15)),
          child: const Icon(Icons.camera_alt_rounded, size: 48, color: Color(0xFF6366F1))),
        const SizedBox(height: 24),
        const Text('Sorunu \u00e7ek veya y\u00fckle', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
        const SizedBox(height: 8),
        Text('Net bir foto\u011fraf \u00e7ek, Koala \u00f6\u011fretsin.', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade500, height: 1.5)),
        const SizedBox(height: 32),
        SizedBox(width: double.infinity, height: 54,
          child: FilledButton.icon(onPressed: _showImageSourcePicker,
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6366F1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            icon: const Icon(Icons.camera_alt_rounded, size: 20),
            label: const Text('Kamera ile \u00c7ek', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, height: 54,
          child: OutlinedButton.icon(onPressed: _showImageSourcePicker,
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF6366F1), side: const BorderSide(color: Color(0xFFE2E8F0)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            icon: const Icon(Icons.photo_library_rounded, size: 20),
            label: const Text('Galeriden Se\u00e7', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))),
      ])));
  }

  Widget _buildConfig() {
    final wide = MediaQuery.of(context).size.width > 700;
    return SingleChildScrollView(key: const ValueKey(1),
      child: Center(child: Container(
        constraints: BoxConstraints(maxWidth: wide ? 560 : double.infinity),
        padding: EdgeInsets.all(wide ? 32 : 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Image preview: FULL image, no cropping ──
        Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0)), color: const Color(0xFF1E293B)),
          child: Column(children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: _imageBytes != null
                ? Container(width: double.infinity, constraints: const BoxConstraints(maxHeight: 400), color: const Color(0xFF1E293B),
                    child: Image.memory(_imageBytes!, fit: BoxFit.contain))
                : Container(height: 200, color: const Color(0xFFF1F5F9))),
            Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(bottom: Radius.circular(16))),
              child: Row(children: [
                Container(width: 28, height: 28, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF22C55E).withAlpha(20)),
                  child: const Icon(Icons.check_rounded, size: 14, color: Color(0xFF22C55E))),
                const SizedBox(width: 10),
                const Expanded(child: Text('Foto\u011fraf y\u00fcklendi', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)))),
                TextButton(onPressed: _retake, child: const Text('De\u011fi\u015ftir', style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.w600, fontSize: 13))),
              ])),
          ])),
        const SizedBox(height: 24),
        Row(children: [
          const Text('Ders', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
          const Spacer(),
          if (_detectingSubject)
            Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.grey.shade400)),
              const SizedBox(width: 6),
              Text('AI tespit ediyor...', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ])
          else if (_detectedSubject != null)
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFF6366F1).withAlpha(12), borderRadius: BorderRadius.circular(99),
                border: Border.all(color: const Color(0xFF6366F1).withAlpha(25))),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.auto_awesome, size: 11, color: Color(0xFF6366F1)), SizedBox(width: 4),
                Text('AI tespit etti', style: TextStyle(fontSize: 11, color: Color(0xFF6366F1), fontWeight: FontWeight.w600)),
              ])),
        ]),
        const SizedBox(height: 4),
        _detectionFailed
          ? Container(margin: const EdgeInsets.only(bottom: 4), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFFF59E0B).withAlpha(15), borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF59E0B).withAlpha(30))),
              child: Row(children: [
                Icon(Icons.info_outline_rounded, color: const Color(0xFFF59E0B), size: 18), const SizedBox(width: 10),
                Expanded(child: Text('G\u00f6r\u00fcnt\u00fcden konu tespit edilemedi. L\u00fctfen dersi se\u00e7.',
                  style: TextStyle(fontSize: 13, color: Colors.amber.shade800))),
              ]))
          : Text('Otomatik alg\u0131land\u0131, istersen de\u011fi\u015ftir', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8,
          children: _subjects.map((s) {
            final sel = _selectedSubject == s;
            return GestureDetector(onTap: () => setState(() => _selectedSubject = s),
              child: AnimatedContainer(duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(color: sel ? const Color(0xFF6366F1) : Colors.white, borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: sel ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0)),
                  boxShadow: sel ? [BoxShadow(color: const Color(0xFF6366F1).withAlpha(40), blurRadius: 8, offset: const Offset(0, 3))] : null),
                child: Text(s, style: TextStyle(color: sel ? Colors.white : const Color(0xFF475569), fontWeight: FontWeight.w600, fontSize: 13))));
          }).toList()),
        const SizedBox(height: 28),
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            const Icon(Icons.bolt_rounded, color: Color(0xFF6366F1), size: 20), const SizedBox(width: 8),
            const Expanded(child: Text('1 kredi harcanacak', style: TextStyle(fontSize: 13, color: Color(0xFF475569)))),
            Text('Kalan: $_credits', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF6366F1))),
          ])),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, height: 54,
          child: FilledButton.icon(
            onPressed: (_selectedSubject != null && !_sending) ? _send : null,
            style: FilledButton.styleFrom(backgroundColor: _selectedSubject != null ? const Color(0xFF6366F1) : const Color(0xFFCBD5E1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            icon: const Icon(Icons.send_rounded, size: 20),
            label: const Text('G\u00d6NDER', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5)))),
      ]))));
  }

  Widget _buildSolving() {
    return Center(key: const ValueKey(2), child: Padding(padding: const EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 100, height: 100,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF6366F1).withAlpha(40), width: 3),
            boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withAlpha(30), blurRadius: 24)]),
          child: ClipOval(child: Image.asset('assets/tutors/Matematik Man.png', fit: BoxFit.cover, alignment: Alignment.topCenter,
            errorBuilder: (_, __, ___) => Container(color: const Color(0xFF6366F1).withAlpha(20),
              child: const Icon(Icons.person, color: Color(0xFF6366F1), size: 40))))),
        const SizedBox(height: 24),
        const Text('Sorun iletiliyor...', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
        const SizedBox(height: 8),
        Text('Koala haz\u0131rlan\u0131yor', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
        const SizedBox(height: 28),
        const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF6366F1))),
      ])));
  }

  Widget _buildSuccess() {
    return Center(key: const ValueKey(3),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0), duration: const Duration(milliseconds: 600), curve: Curves.easeOutBack,
        builder: (_, v, child) => Transform.scale(scale: 0.8 + 0.2 * v, child: Opacity(opacity: v.clamp(0.0, 1.0), child: child)),
        child: Container(constraints: const BoxConstraints(maxWidth: 420), padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Stack(alignment: Alignment.center, children: [
              Container(width: 130, height: 130, decoration: BoxDecoration(shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: const Color(0xFF22C55E).withAlpha(40), blurRadius: 40, spreadRadius: 10)])),
              Container(width: 110, height: 110,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF22C55E).withAlpha(60), width: 3)),
                child: ClipOval(child: Image.asset('assets/tutors/Matematik Man.png', fit: BoxFit.cover, alignment: Alignment.topCenter,
                  errorBuilder: (_, __, ___) => Container(color: const Color(0xFF22C55E).withAlpha(20),
                    child: const Icon(Icons.person, color: Color(0xFF22C55E), size: 44))))),
              Positioned(bottom: 0, right: 0,
                child: Container(width: 36, height: 36,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF22C55E),
                    border: Border.all(color: Colors.white, width: 3), boxShadow: [BoxShadow(color: Colors.black.withAlpha(25), blurRadius: 8)]),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 20))),
            ]),
            const SizedBox(height: 28),
            const Text('Sorun g\u00f6nderildi!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
            const SizedBox(height: 10),
            Text('Koala \u00e7\u00f6z\u00fcm \u00fcretiyor.\nHaz\u0131r olunca bildirim alacaks\u0131n.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey.shade500, height: 1.6)),
            const SizedBox(height: 12),
            Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFF6366F1).withAlpha(10), borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF6366F1).withAlpha(20))),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.notifications_active_rounded, size: 16, color: Color(0xFF6366F1)), SizedBox(width: 8),
                Text('Bildirimleri a\u00e7\u0131k tut', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6366F1))),
              ])),
            const SizedBox(height: 28),
            SizedBox(width: double.infinity, height: 50,
              child: FilledButton(onPressed: _goHome,
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6366F1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: const Text('Ana Sayfaya D\u00f6n', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
          ]))));
  }
}
