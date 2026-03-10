import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/chatgpt_service.dart';
import '../stores/mastery_store.dart';
import '../stores/question_store.dart';
import 'mastery_topic_screen.dart';

class MasteryNewTopicScreen extends StatefulWidget {
  const MasteryNewTopicScreen({super.key});
  @override
  State<MasteryNewTopicScreen> createState() => _MasteryNewTopicScreenState();
}

class _MasteryNewTopicScreenState extends State<MasteryNewTopicScreen> {
  final TextEditingController _textCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final ChatGptService _chatService = ChatGptService();
  Uint8List? _imageBytes;
  bool _loading = false;

  Future<void> _pickImage(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 90);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _imageBytes = bytes);

    // Auto-detect topic from image
    setState(() => _loading = true);
    try {
      final result = await _chatService.askImageBytes(bytes,
        prompt: 'Bu fotograftaki konunun basligini Turkce tek cumle olarak yaz. Sadece konu basligini yaz, baska hicbir sey yazma.');
      _textCtrl.text = result.trim().replaceAll('.', '').replaceAll('"', '');
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _start() async {
    final title = _textCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('L\u00fctfen bir konu yaz veya foto\u011fraf \u00e7ek')));
      return;
    }

    setState(() => _loading = true);

    // Detect subject
    String subject = 'Matematik';
    try {
      final result = await _chatService.askText(
        'Bu konu hangi derse ait: "$title". Sadece ders adini yaz: Matematik, Geometri, Fizik, Kimya, Biyoloji, Turkce, Edebiyat, Tarih, Cografya, Felsefe, Ingilizce');
      final lower = result.trim().toLowerCase();
      if (lower.contains('mat')) subject = 'Matematik';
      else if (lower.contains('geo')) subject = 'Geometri';
      else if (lower.contains('fiz')) subject = 'Fizik';
      else if (lower.contains('kim')) subject = 'Kimya';
      else if (lower.contains('bio')) subject = 'Biyoloji';
      else if (lower.contains('turk') || lower.contains('ede')) subject = 'T\u00fcrk\u00e7e';
      else if (lower.contains('tar')) subject = 'Tarih';
      else if (lower.contains('cog')) subject = 'Co\u011frafya';
      else if (lower.contains('fel')) subject = 'Felsefe';
      else if (lower.contains('ing')) subject = '\u0130ngilizce';
    } catch (_) {}

    final teacher = tutorNameForSubject(subject);

    final topic = MasteryStore.instance.addTopic(
      title: title, subject: subject, teacherName: teacher, imageBytes: _imageBytes);

    setState(() => _loading = false);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => MasteryTopicScreen(topicId: topic.id)));
    }
  }

  @override
  void dispose() { _textCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFD),
      appBar: AppBar(
        backgroundColor: Colors.white, surfaceTintColor: Colors.transparent, elevation: 0,
        leading: IconButton(onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, color: Color(0xFF0F172A))),
        title: const Text('Yeni Konu', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Hero
          Center(child: Column(children: [
            Container(width: 72, height: 72,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(colors: [const Color(0xFF6366F1).withAlpha(15), const Color(0xFF8B5CF6).withAlpha(8)])),
              child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF6366F1), size: 32)),
            const SizedBox(height: 16),
            const Text('Bir konuda ustala\u015f', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
            const SizedBox(height: 6),
            Text('Konu se\u00e7, Koala sana ad\u0131m ad\u0131m \u00f6\u011fretsin', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
          ])),

          const SizedBox(height: 32),

          // Photo options
          _Option(
            icon: Icons.camera_alt_rounded,
            color: const Color(0xFF6366F1),
            title: 'Foto\u011fraf \u00c7ek',
            subtitle: 'Kitaptan konu ba\u015fl\u0131\u011f\u0131n\u0131 \u00e7ek',
            onTap: () => _pickImage(ImageSource.camera)),
          const SizedBox(height: 12),
          _Option(
            icon: Icons.photo_library_rounded,
            color: const Color(0xFF0EA5E9),
            title: 'Galeriden Y\u00fckle',
            subtitle: 'Kay\u0131tl\u0131 foto\u011fraftan konu se\u00e7',
            onTap: () => _pickImage(ImageSource.gallery)),

          // Image preview
          if (_imageBytes != null)
            Container(margin: const EdgeInsets.only(top: 16),
              height: 120, width: double.infinity,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFEEF2F7))),
              child: ClipRRect(borderRadius: BorderRadius.circular(16),
                child: Image.memory(_imageBytes!, fit: BoxFit.contain))),

          const SizedBox(height: 20),

          // Divider
          Row(children: [
            Expanded(child: Container(height: 1, color: const Color(0xFFEEF2F7))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('veya konu yaz', style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontWeight: FontWeight.w600))),
            Expanded(child: Container(height: 1, color: const Color(0xFFEEF2F7))),
          ]),

          const SizedBox(height: 20),

          // Text input
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFEEF2F7)),
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 8)]),
            child: TextField(controller: _textCtrl,
              style: const TextStyle(fontSize: 16, color: Color(0xFF0F172A), fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: '\u00d6rn: \u00dcsl\u00fc say\u0131lar, Kuvvet ve hareket...',
                hintStyle: TextStyle(color: Colors.grey.shade300, fontWeight: FontWeight.w400),
                border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none)),
          ),

          const SizedBox(height: 32),

          // Start button
          SizedBox(width: double.infinity, height: 56,
            child: FilledButton(
              onPressed: _loading ? null : _start,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
              child: _loading
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Text('Ustala\u015fmaya Ba\u015fla', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)))),
        ]),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});
  final IconData icon; final Color color; final String title; final String subtitle; final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(color: Colors.white, borderRadius: BorderRadius.circular(18),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18),
        child: Container(padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFEEF2F7))),
          child: Row(children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(colors: [color.withAlpha(15), color.withAlpha(8)])),
              child: Icon(icon, color: color, size: 22)),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ])),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade300, size: 22),
          ]))));
  }
}
