import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final TextEditingController _textCtrl = TextEditingController();
  final FocusNode _textFocus = FocusNode();

  Uint8List? _imageBytes;
  String? _detectedSubject;
  String? _selectedSubject;
  bool _detectingSubject = false;
  bool _detectionFailed = false;
  int _credits = 1;
  bool _loading = true;
  bool _sending = false;
  int _step = 0; // 0=input, 1=config, 2=solving

  // Drag state
  bool _isDragging = false;

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

  @override
  void dispose() {
    _textCtrl.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  Future<void> _loadCredits() async {
    final c = await _creditService.getCredits();
    if (!mounted) return;
    setState(() { _credits = c; _loading = false; });
  }

  bool get _hasImage => _imageBytes != null;
  bool get _hasText => _textCtrl.text.trim().isNotEmpty;
  bool get _hasInput => _hasImage || _hasText;

  // ── IMAGE PICKING ──

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
          ListTile(
            leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFF6366F1).withAlpha(15), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.camera_alt_rounded, color: Color(0xFF6366F1), size: 20)),
            title: const Text('Kamera ile \u00c7ek', style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.camera); }),
          const Divider(height: 1, indent: 60, endIndent: 20),
          ListTile(
            leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFF0EA5E9).withAlpha(15), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.photo_library_rounded, color: Color(0xFF0EA5E9), size: 20)),
            title: const Text('Galeriden Se\u00e7', style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.gallery); }),
          const SizedBox(height: 8),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(width: double.infinity, height: 48,
              child: TextButton(onPressed: () => Navigator.pop(ctx),
                child: Text('Vazge\u00e7', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600, fontSize: 15))))),
          const SizedBox(height: 8),
        ]))));
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 90);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    _setImage(bytes);
  }

  void _setImage(Uint8List bytes) {
    setState(() {
      _imageBytes = bytes;
      _detectedSubject = null;
      _selectedSubject = null;
      _detectionFailed = false;
    });
    _detectSubject(bytes);
  }

  void _removeImage() {
    setState(() {
      _imageBytes = null;
      _detectedSubject = null;
      if (_selectedSubject != null && _detectedSubject == _selectedSubject) {
        _selectedSubject = null;
      }
      _detectionFailed = false;
    });
  }

  // ── CLIPBOARD PASTE (Ctrl+V) ──

  Future<void> _handlePaste() async {
    try {
      final data = await Clipboard.getData('text/plain');
      // Try to get image from clipboard
      // On web, we can't directly access clipboard images via Clipboard.getData
      // But we handle it via the KeyboardListener below
    } catch (_) {}
  }

  // ── DRAG & DROP ──

  // Note: Flutter web drag-and-drop for files requires platform-level handling.
  // We'll implement it using a transparent overlay that accepts drops.
  // For now, the visual indicator is shown but actual drop handling
  // requires the `super_drag_and_drop` or `desktop_drop` package.
  // As a pragmatic alternative, we show a prominent "paste" hint.

  // ── SUBJECT DETECTION ──

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
        // AI tespit ettiyse otomatik gönder
        _send();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() { _detectingSubject = false; _detectionFailed = true; });
    }
  }

  // ── SEND ──

  Future<void> _send() async {
    if (!_hasInput || _selectedSubject == null) return;
    if (_credits <= 0) { _showNoCredit(); return; }
    setState(() { _step = 2; _sending = true; });
    try {
      await _creditService.spendOneCredit();

      // Create placeholder image if no photo (1x1 transparent)
      final imgBytes = _imageBytes ?? _createPlaceholderImage();
      final q = QuestionStore.instance.add(imageBytes: imgBytes, subject: _selectedSubject!);
      Analytics.questionSubmitted(q.id, _selectedSubject!);
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      _solveInBackground(q.id, _imageBytes, _textCtrl.text.trim(), _selectedSubject!);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ChatScreen(questionId: q.id)));
    } catch (e) {
      if (!mounted) return;
      setState(() { _step = 0; _sending = false; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Uint8List _createPlaceholderImage() {
    // Minimal 1x1 PNG (transparent)
    return Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x00, 0x00, 0x02,
      0x00, 0x01, 0xE5, 0x27, 0xDE, 0xFC, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
      0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);
  }

  void _solveInBackground(String qId, Uint8List? imageBytes, String textInput, String subject) async {
    try {
      final sw = Stopwatch()..start();
      String answer;

      if (imageBytes != null && textInput.isNotEmpty) {
        // Both image + text
        final prompt = '$textInput\n\n${subject == 'Matematik' || subject == 'Geometri' ? _getMathPrompt(subject) : _getGeneralPrompt(subject)}';
        answer = await _chatGptService.askImageBytes(imageBytes, prompt: prompt);
      } else if (imageBytes != null) {
        // Only image
        answer = await _chatGptService.askImageBytes(imageBytes,
          prompt: subject == 'Matematik' || subject == 'Geometri' ? _getMathPrompt(subject) : _getGeneralPrompt(subject));
      } else {
        // Only text
        final prompt = 'Soru: $textInput\n\n${subject == 'Matematik' || subject == 'Geometri' ? _getMathPrompt(subject) : _getGeneralPrompt(subject)}';
        answer = await _chatGptService.askConversation(
          systemPrompt: 'Sen Koala uygulamasinin AI ogretmenisin. Turkce yaz.',
          messages: [{'role': 'user', 'content': prompt}]);
      }

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

  String _getMathPrompt(String subject) {
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
    final wide = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _step == 2 ? null : AppBar(
        backgroundColor: Colors.white, surfaceTintColor: Colors.transparent, elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, color: Color(0xFF1E293B))),
        title: const Text('Soru Sor', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
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
        duration: const Duration(milliseconds: 300),
        child: _step == 2 ? _buildSolving() : _buildInputScreen(wide),
      ),
    );
  }

  // ╔══════════════════════════════════════════════════╗
  // ║  MAIN INPUT SCREEN (photo + text + subject)     ║
  // ╚══════════════════════════════════════════════════╝

  Widget _buildInputScreen(bool wide) {
    return SingleChildScrollView(
      key: const ValueKey('input'),
      padding: EdgeInsets.all(wide ? 32 : 20),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: wide ? 600 : double.infinity),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── PHOTO SECTION ──
            _buildPhotoSection(wide),
            const SizedBox(height: 20),

            // ── TEXT INPUT SECTION ──
            _buildTextSection(),
            const SizedBox(height: 24),

            // ── SUBJECT SELECTION ──
            _buildSubjectSection(),
            const SizedBox(height: 24),

            // ── CREDIT INFO ──
            Container(padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                const Icon(Icons.bolt_rounded, color: Color(0xFF6366F1), size: 20), const SizedBox(width: 8),
                const Expanded(child: Text('1 kredi harcanacak', style: TextStyle(fontSize: 13, color: Color(0xFF475569)))),
                Text('Kalan: $_credits', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF6366F1))),
              ])),
            const SizedBox(height: 20),

            // ── SEND BUTTON ──
            SizedBox(width: double.infinity, height: 54,
              child: FilledButton.icon(
                onPressed: (_hasInput && _selectedSubject != null && !_sending) ? _send : null,
                style: FilledButton.styleFrom(
                  backgroundColor: (_hasInput && _selectedSubject != null) ? const Color(0xFF6366F1) : const Color(0xFFCBD5E1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                icon: const Icon(Icons.send_rounded, size: 20),
                label: Text(_hasImage && !_hasText ? 'G\u00d6NDER' : _hasText && !_hasImage ? 'SORUYU G\u00d6NDER' : 'G\u00d6NDER',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5)))),

            if (!_hasInput)
              Padding(padding: const EdgeInsets.only(top: 12),
                child: Center(child: Text('Foto\u011fraf veya metin ekleyerek ba\u015fla',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400)))),

            const SizedBox(height: 40),
          ]),
        ),
      ),
    );
  }

  // ── PHOTO SECTION ──

  Widget _buildPhotoSection(bool wide) {
    if (_hasImage) {
      return _buildPhotoPreview();
    }
    return _buildPhotoUploader(wide);
  }

  Widget _buildPhotoUploader(bool wide) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _isDragging ? const Color(0xFF6366F1).withAlpha(8) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isDragging ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0),
          width: _isDragging ? 2 : 1,
          strokeAlign: BorderSide.strokeAlignInside),
      ),
      child: Column(children: [
        Container(width: 56, height: 56,
          decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF6366F1).withAlpha(10)),
          child: const Icon(Icons.add_photo_alternate_rounded, size: 28, color: Color(0xFF6366F1))),
        const SizedBox(height: 14),
        Text('Foto\u011fraf ekle', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
        const SizedBox(height: 4),
        Text('Opsiyonel \u2014 sadece metin ile de soru sorabilirsin',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _miniBtn(Icons.camera_alt_rounded, 'Kamera', const Color(0xFF6366F1), () => _pickImage(ImageSource.camera)),
          const SizedBox(width: 12),
          _miniBtn(Icons.photo_library_rounded, 'Galeri', const Color(0xFF0EA5E9), () => _pickImage(ImageSource.gallery)),
          if (wide) ...[
            const SizedBox(width: 12),
            _miniBtn(Icons.content_paste_rounded, 'Yap\u0131\u015ft\u0131r', const Color(0xFF8B5CF6), _pasteFromClipboard),
          ],
        ]),
        if (wide)
          Padding(padding: const EdgeInsets.only(top: 12),
            child: Text('veya Ctrl+V ile yap\u0131\u015ft\u0131r',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400))),
      ]),
    );
  }

  Widget _miniBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(25))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null && data!.text!.isNotEmpty) {
        // If it's text, put it in the text field
        setState(() {
          _textCtrl.text = data.text!;
          _textCtrl.selection = TextSelection.fromPosition(TextPosition(offset: data.text!.length));
        });
        return;
      }
    } catch (_) {}

    // Show hint that image paste works with Ctrl+V
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating, backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16), duration: const Duration(seconds: 3),
        content: const Row(children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFF818CF8), size: 18), SizedBox(width: 10),
          Expanded(child: Text('G\u00f6rsel yap\u0131\u015ft\u0131rmak i\u00e7in Ctrl+V kullan', style: TextStyle(color: Colors.white, fontSize: 13))),
        ]),
      ));
    }
  }

  Widget _buildPhotoPreview() {
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0)), color: const Color(0xFF1E293B)),
      child: Column(children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: Container(width: double.infinity, constraints: const BoxConstraints(maxHeight: 300), color: const Color(0xFF1E293B),
            child: Image.memory(_imageBytes!, fit: BoxFit.contain))),
        Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(bottom: Radius.circular(16))),
          child: Row(children: [
            Container(width: 28, height: 28, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF22C55E).withAlpha(20)),
              child: const Icon(Icons.check_rounded, size: 14, color: Color(0xFF22C55E))),
            const SizedBox(width: 10),
            const Expanded(child: Text('Foto\u011fraf y\u00fcklendi', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)))),
            if (_detectingSubject)
              Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.grey.shade400)),
                const SizedBox(width: 6),
                Text('Tespit ediliyor...', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ]),
            TextButton(onPressed: _removeImage,
              child: const Text('Kald\u0131r', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600, fontSize: 13))),
          ])),
      ]),
    );
  }

  // ── TEXT INPUT SECTION ──

  Widget _buildTextSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Soruyu yaz', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
        const SizedBox(width: 6),
        Text('opsiyonel', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
      ]),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(children: [
          TextField(
            controller: _textCtrl,
            focusNode: _textFocus,
            maxLines: 4,
            minLines: 2,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B), height: 1.5),
            decoration: InputDecoration(
              hintText: 'Soruyu buraya yazabilirsin...\n\u00d6rn: "x\u00b2 + 5x + 6 = 0 denklemini \u00e7\u00f6z"',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14, height: 1.5),
              border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            ),
          ),
          // Bottom toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: const Color(0xFFE2E8F0).withAlpha(80))),
            ),
            child: Row(children: [
              // Voice dictation button
              _toolbarBtn(Icons.mic_rounded, 'Sesle s\u00f6yle', const Color(0xFFEF4444), _startVoiceInput),
              const Spacer(),
              if (_hasText)
                GestureDetector(
                  onTap: () => setState(() => _textCtrl.clear()),
                  child: Text('Temizle', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade400)),
                ),
            ]),
          ),
        ]),
      ),
    ]);
  }

  Widget _toolbarBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(8),
          borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    );
  }

  // ── VOICE INPUT ──

  void _startVoiceInput() {
    // Show voice recording dialog
    showDialog(context: context, barrierDismissible: true,
      builder: (ctx) => _VoiceInputDialog(
        onResult: (text) {
          if (text.isNotEmpty) {
            setState(() {
              if (_textCtrl.text.isNotEmpty) {
                _textCtrl.text = '${_textCtrl.text} $text';
              } else {
                _textCtrl.text = text;
              }
              _textCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _textCtrl.text.length));
            });
          }
        },
      ),
    );
  }

  // ── SUBJECT SECTION ──

  Widget _buildSubjectSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Ders', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
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
      if (_detectionFailed)
        Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: const Color(0xFFF59E0B).withAlpha(15), borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFF59E0B).withAlpha(30))),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B), size: 18), const SizedBox(width: 10),
            Expanded(child: Text('Otomatik tespit edilemedi. L\u00fctfen dersi se\u00e7.',
              style: TextStyle(fontSize: 13, color: Colors.amber.shade800))),
          ])),
      const SizedBox(height: 4),
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
    ]);
  }

  // ── SOLVING STATE ──

  Widget _buildSolving() {
    return Center(key: const ValueKey('solving'), child: Padding(padding: const EdgeInsets.all(40),
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
}

// ╔══════════════════════════════════════════════════╗
// ║  VOICE INPUT DIALOG                             ║
// ╚══════════════════════════════════════════════════╝

class _VoiceInputDialog extends StatefulWidget {
  const _VoiceInputDialog({required this.onResult});
  final ValueChanged<String> onResult;
  @override
  State<_VoiceInputDialog> createState() => _VoiceInputDialogState();
}

class _VoiceInputDialogState extends State<_VoiceInputDialog> {
  final TextEditingController _ctrl = TextEditingController();
  bool _recording = false;
  String _hint = 'Taray\u0131c\u0131n\u0131n mikrofon iznini kontrol et';

  // Web Speech API integration
  // Flutter web doesn't have native speech-to-text, so we provide a manual text input
  // with a note about browser speech API. For production, use speech_to_text package.

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Mic icon
          Container(width: 64, height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFEF4444).withAlpha(12),
              border: Border.all(color: const Color(0xFFEF4444).withAlpha(25), width: 2)),
            child: const Icon(Icons.mic_rounded, size: 32, color: Color(0xFFEF4444))),
          const SizedBox(height: 16),
          const Text('Sesli Giri\u015f', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
          const SizedBox(height: 8),
          Text('Soruyu a\u015fa\u011f\u0131ya dikte et veya yaz',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          const SizedBox(height: 16),
          // Text input (fallback for voice)
          TextField(
            controller: _ctrl,
            maxLines: 3,
            autofocus: true,
            style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
            decoration: InputDecoration(
              hintText: 'Soruyu buraya yaz veya dikte et...',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              filled: true, fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF6366F1))),
              contentPadding: const EdgeInsets.all(14)),
          ),
          const SizedBox(height: 8),
          // Info about browser speech
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Icon(Icons.info_outline_rounded, size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Taray\u0131c\u0131n\u0131n adres \u00e7ubu\u011funda mikrofon simgesine t\u0131klayarak sesli giri\u015fi etkinle\u015ftirebilirsin.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500, height: 1.4))),
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: TextButton(onPressed: () => Navigator.pop(context),
              child: Text('Vazge\u00e7', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600)))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton(
              onPressed: () {
                widget.onResult(_ctrl.text.trim());
                Navigator.pop(context);
              },
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6366F1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: const Text('Ekle', style: TextStyle(fontWeight: FontWeight.w700)))),
          ]),
        ])),
    );
  }
}
