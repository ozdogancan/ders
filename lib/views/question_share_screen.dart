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

class _QuestionShareScreenState extends State<QuestionShareScreen> with TickerProviderStateMixin {
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
  int _step = 0; // 0=picker, 1=config, 2=sending, 3=sent

  // Sending animation
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  static const List<String> _subjects = [
    'Matematik', 'Geometri', 'Fizik', 'Kimya', 'Biyoloji',
    'T\u00fcrk\u00e7e', 'Edebiyat', 'Tarih', 'Co\u011frafya',
    'Felsefe', '\u0130ngilizce', 'Din K\u00fclt\u00fcr\u00fc',
  ];

  @override
  void initState() {
    super.initState();
    _loadCredits();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.08).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCredits() async {
    final c = await _creditService.getCredits();
    if (!mounted) return;
    setState(() { _credits = c; _loading = false; });
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
      _detectionFailed = false;
    });
    _detectSubject(bytes);
  }

  Future<void> _detectSubject(Uint8List bytes) async {
    setState(() { _detectingSubject = true; _detectionFailed = false; });
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

    // Step 2: "Gönderiliyor" animation
    setState(() { _step = 2; _sending = true; });

    try {
      await _creditService.spendOneCredit();
      final q = QuestionStore.instance.add(imageBytes: _imageBytes!, subject: _selectedSubject!);
      Analytics.questionSubmitted(q.id, _selectedSubject!);

      // Show "Gönderiliyor" for 1.5s
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;

      // Step 3: "Gönderildi!" for 2s
      setState(() => _step = 3);
      _solveInBackground(q.id, _imageBytes!, _selectedSubject!);

      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      // Navigate to chat
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF6366F1))));
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: (_step == 2 || _step == 3) ? null : AppBar(
        backgroundColor: Colors.white, surfaceTintColor: Colors.transparent, elevation: 0,
        leading: IconButton(
          onPressed: () { if (_step == 1) { _retake(); } else { Navigator.pop(context); } },
          icon: Icon(_step == 1 ? Icons.arrow_back_rounded : Icons.close_rounded, color: const Color(0xFF1E293B))),
        title: Text(_step == 0 ? 'Soru Sor' : 'Soru G\u00f6nder',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
        centerTitle: true,
        actions: [
          GestureDetector(
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreditStoreScreen()));
              _loadCredits();
            },
            child: Padding(padding: const EdgeInsets.only(right: 12),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: const Color(0xFF6366F1).withAlpha(15), borderRadius: BorderRadius.circular(99)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.bolt_rounded, size: 14, color: Color(0xFF6366F1)),
                  const SizedBox(width: 3),
                  Text('$_credits', style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.w800, fontSize: 13)),
                ]))),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: switch (_step) {
          0 => _buildPicker(),
          1 => _buildConfig(),
          2 => _buildSending(),
          3 => _buildSent(),
          _ => _buildSending(),
        },
      ),
    );
  }

  // ╔══════════════════════════════════════════════════╗
  // ║  STEP 0: Pick image (original clean design)     ║
  // ╚══════════════════════════════════════════════════╝

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
          child: FilledButton.icon(onPressed: () => _pickImage(ImageSource.camera),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6366F1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            icon: const Icon(Icons.camera_alt_rounded, size: 20),
            label: const Text('Kamera ile \u00c7ek', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, height: 54,
          child: OutlinedButton.icon(onPressed: () => _pickImage(ImageSource.gallery),
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF6366F1), side: const BorderSide(color: Color(0xFFE2E8F0)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            icon: const Icon(Icons.photo_library_rounded, size: 20),
            label: const Text('Galeriden Se\u00e7', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))),
      ])));
  }

  // ╔══════════════════════════════════════════════════╗
  // ║  STEP 1: Image loaded, detect/select subject    ║
  // ╚══════════════════════════════════════════════════╝

  Widget _buildConfig() {
    final wide = MediaQuery.of(context).size.width > 700;
    return SingleChildScrollView(key: const ValueKey(1),
      child: Center(child: Container(
        constraints: BoxConstraints(maxWidth: wide ? 560 : double.infinity),
        padding: EdgeInsets.all(wide ? 32 : 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Image preview
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
                const Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B), size: 18), const SizedBox(width: 10),
                Expanded(child: Text('AI tespit edemedi. L\u00fctfen dersi se\u00e7.',
                  style: TextStyle(fontSize: 13, color: Colors.amber.shade800, fontWeight: FontWeight.w600))),
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

  // ╔══════════════════════════════════════════════════╗
  // ║  STEP 2: "Gönderiliyor..." with pulse animation ║
  // ╚══════════════════════════════════════════════════╝

  Widget _buildSending() {
    return Center(key: const ValueKey(2), child: Padding(padding: const EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, child) => Transform.scale(scale: _pulseAnim.value, child: child),
          child: Container(width: 110, height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [const Color(0xFF6366F1).withAlpha(20), const Color(0xFF8B5CF6).withAlpha(15)]),
              border: Border.all(color: const Color(0xFF6366F1).withAlpha(40), width: 3),
              boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withAlpha(20), blurRadius: 30, spreadRadius: 5)]),
            child: const Icon(Icons.upload_rounded, size: 44, color: Color(0xFF6366F1)),
          ),
        ),
        const SizedBox(height: 28),
        const Text('G\u00f6nderiliyor...', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
        const SizedBox(height: 10),
        Text('Sorun Koala\u2019ya iletiliyor', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
        const SizedBox(height: 32),
        SizedBox(width: 36, height: 36,
          child: CircularProgressIndicator(strokeWidth: 3, color: const Color(0xFF6366F1).withAlpha(60))),
      ])));
  }

  // ╔══════════════════════════════════════════════════╗
  // ║  STEP 3: "Gönderildi!" with checkmark animation ║
  // ╚══════════════════════════════════════════════════╝

  Widget _buildSent() {
    return Center(key: const ValueKey(3),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0), duration: const Duration(milliseconds: 600), curve: Curves.easeOutBack,
        builder: (_, v, child) => Transform.scale(scale: 0.7 + 0.3 * v, child: Opacity(opacity: v.clamp(0.0, 1.0), child: child)),
        child: Padding(padding: const EdgeInsets.all(40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Success circle with checkmark
            Stack(alignment: Alignment.center, children: [
              // Glow
              Container(width: 130, height: 130, decoration: BoxDecoration(shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: const Color(0xFF22C55E).withAlpha(40), blurRadius: 40, spreadRadius: 10)])),
              // Circle
              Container(width: 110, height: 110,
                decoration: BoxDecoration(shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFF22C55E), Color(0xFF16A34A)]),
                  boxShadow: [BoxShadow(color: const Color(0xFF22C55E).withAlpha(50), blurRadius: 20, offset: const Offset(0, 8))]),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 52)),
            ]),
            const SizedBox(height: 28),
            const Text('G\u00f6nderildi!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
            const SizedBox(height: 10),
            Text('Koala \u00e7\u00f6z\u00fcm \u00fcretmeye ba\u015flad\u0131', style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
            const SizedBox(height: 8),
            // Animated dots hint
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.grey.shade400),
              const SizedBox(width: 6),
              Text('\u00c7\u00f6z\u00fcm ekran\u0131na y\u00f6nlendiriliyorsun...', style: TextStyle(fontSize: 13, color: Colors.grey.shade400, fontWeight: FontWeight.w500)),
            ]),
          ]))));
  }
}
