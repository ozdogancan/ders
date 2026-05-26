// Instagram-tarzı paylaşım composer.
//
// Akış:
//   Step 1: Fotoğraf seç (kamera / galeri) — square 1:1 hint.
//   Step 2: Caption + room type + tag chip'leri.
//   Step 3: Yayınla — upload → AI moderation → insert → push/snackbar.
//
// Mekan re-design wizard'ından FARKLI: bu sadece bir post; AI ile yeniden
// tasarlama yapmıyor. Pro gate yok — paylaşım herkese ücretsiz.

import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/koala_tokens.dart';
import '../../services/shared_design_service.dart';

class ShareUploadScreen extends StatefulWidget {
  const ShareUploadScreen({super.key});

  @override
  State<ShareUploadScreen> createState() => _ShareUploadScreenState();
}

class _ShareUploadScreenState extends State<ShareUploadScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _captionCtl = TextEditingController();

  Uint8List? _bytes;
  int _step = 0; // 0=pick, 1=compose, 2=publishing
  bool _busy = false;
  String? _selectedRoom;
  final Set<String> _selectedTags = <String>{};

  // Style discovery ekranı ile uyumlu Türkçe oda tipleri.
  static const List<_RoomOpt> _rooms = [
    _RoomOpt('living_room', 'Salon'),
    _RoomOpt('bedroom', 'Yatak Odası'),
    _RoomOpt('kitchen', 'Mutfak'),
    _RoomOpt('bathroom', 'Banyo'),
    _RoomOpt('dining_room', 'Yemek Odası'),
    _RoomOpt('office', 'Çalışma'),
    _RoomOpt('kids_room', 'Çocuk Odası'),
    _RoomOpt('hall', 'Hol'),
  ];

  static const List<String> _tagOptions = [
    'modern',
    'minimal',
    'skandinav',
    'boho',
    'klasik',
    'endüstriyel',
  ];

  @override
  void dispose() {
    _captionCtl.dispose();
    super.dispose();
  }

  // ─── Step 1: foto seç ───
  Future<void> _pick(ImageSource source) async {
    if (kIsWeb && source == ImageSource.camera) {
      _snack('Kamera bu cihazda desteklenmiyor');
      return;
    }
    try {
      final f = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        imageQuality: 75,
      );
      if (f == null || !mounted) return;
      final bytes = await f.readAsBytes();
      final optimized = _optimize(bytes);
      setState(() {
        _bytes = optimized;
        _step = 1;
      });
    } catch (e) {
      _snack('Fotoğraf seçilemedi');
    }
  }

  // Decode + 1280 max edge + JPG q75. Memory koruma için tek pass.
  Uint8List _optimize(Uint8List input) {
    try {
      final decoded = img.decodeImage(input);
      if (decoded == null) return input;
      const maxEdge = 1280;
      img.Image scaled = decoded;
      if (decoded.width > maxEdge || decoded.height > maxEdge) {
        scaled = decoded.width >= decoded.height
            ? img.copyResize(decoded, width: maxEdge)
            : img.copyResize(decoded, height: maxEdge);
      }
      return Uint8List.fromList(img.encodeJpg(scaled, quality: 75));
    } catch (_) {
      return input;
    }
  }

  // ─── Step 3: yayınla ───
  Future<void> _publish() async {
    if (_bytes == null || _busy) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Önce giriş yap');
      return;
    }

    setState(() {
      _busy = true;
      _step = 2;
    });

    // 1) Upload
    final url = await SharedDesignService.uploadImage(_bytes!);
    if (url == null) {
      _fail('Yükleme başarısız — bağlantını kontrol et');
      return;
    }

    // 2) AI moderation
    final mod = await SharedDesignService.moderate(imageUrl: url);
    if (!mod.ok) {
      final reason = mod.reason ?? 'unknown';
      _fail(_humanReason(reason));
      return;
    }

    // 3) Insert published row
    final saved = await SharedDesignService.publish(
      imageUrl: url,
      description: _captionCtl.text.trim().isEmpty
          ? null
          : _captionCtl.text.trim(),
      roomType: _selectedRoom,
      tags: _selectedTags.toList(),
    );
    if (saved == null) {
      _fail('Yayınlanamadı — tekrar dene');
      return;
    }

    // 4) Self-notification — flutter_local_notifications yüklü değil,
    // SnackBar ile bilgilendir. TODO: koala-api/push/send shared-secret
    // ister, client'tan çağrılamaz; backend tetiklemesi için outbound_queue
    // path'i gerekecek.
    if (!mounted) return;
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tasarımın yayında ✨'),
        backgroundColor: KoalaColors.accent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _humanReason(String reason) {
    switch (reason) {
      case 'not_a_room':
        return 'Bu bir oda fotoğrafına benzemiyor. İç mekan fotoğrafı dene.';
      case 'inappropriate':
        return 'Bu içerik topluluk kurallarına uymuyor.';
      case 'analysis_failed':
        return 'AI kontrolü başarısız oldu. Tekrar dene.';
      case 'rate_limited':
        return 'Çok hızlı paylaşıyorsun. Biraz bekle.';
      case 'network':
        return 'Bağlantı sorunu. Tekrar dene.';
      default:
        return 'Paylaşım reddedildi ($reason).';
    }
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _step = 1;
    });
    _snack(msg);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // ─── Build ───
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      appBar: AppBar(
        backgroundColor: KoalaColors.bg,
        elevation: 0,
        title: Text(_step == 0 ? 'Paylaş' : 'Yeni gönderi',
            style: KoalaText.h2),
        leading: IconButton(
          icon: const Icon(LucideIcons.x, color: KoalaColors.text),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_step == 1)
            TextButton(
              onPressed: _busy ? null : _publish,
              child: const Text(
                'Yayınla',
                style: TextStyle(
                  color: KoalaColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: _step == 0
            ? _stepPick()
            : _step == 1
                ? _stepCompose()
                : _stepPublishing(),
      ),
    );
  }

  Widget _stepPick() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Text('Bir oda fotoğrafı seç', style: KoalaText.h1),
          const SizedBox(height: 8),
          const Text(
            'Topluluğa kendi mekanını göster. Kare (1:1) en iyi sonucu verir.',
            style: KoalaText.bodySec,
          ),
          const Spacer(),
          _bigBtn(
            icon: LucideIcons.camera,
            label: 'Kamera',
            onTap: () => _pick(ImageSource.camera),
          ),
          const SizedBox(height: 12),
          _bigBtn(
            icon: LucideIcons.image,
            label: 'Galeri',
            onTap: () => _pick(ImageSource.gallery),
          ),
          const Spacer(),
          const Text(
            'AI içerik kontrolünden geçer; uygunsuz veya oda olmayan görseller reddedilir.',
            style: TextStyle(color: KoalaColors.textSec, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _stepCompose() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _bytes == null
                  ? Container(color: KoalaColors.border)
                  : Image.memory(_bytes!, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 16),
          // Caption
          TextField(
            controller: _captionCtl,
            maxLength: 250,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Bu mekan hakkında bir şeyler yaz…',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: KoalaColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: KoalaColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: KoalaColors.accent, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Oda tipi', style: KoalaText.label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _rooms.map((r) {
              final on = _selectedRoom == r.key;
              return _chip(
                label: r.label,
                selected: on,
                onTap: () => setState(() => _selectedRoom = on ? null : r.key),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          const Text('Tarz etiketleri', style: KoalaText.label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _tagOptions.map((t) {
              final on = _selectedTags.contains(t);
              return _chip(
                label: t,
                selected: on,
                onTap: () {
                  setState(() {
                    if (on) {
                      _selectedTags.remove(t);
                    } else {
                      _selectedTags.add(t);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _stepPublishing() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: KoalaColors.accent),
          SizedBox(height: 20),
          Text('Yükleniyor ve AI kontrolü…', style: KoalaText.bodySec),
        ],
      ),
    );
  }

  // ─── Bits ───
  Widget _bigBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: KoalaColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: KoalaColors.accent),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: KoalaColors.text,
                )),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? KoalaColors.accent : Colors.white,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: selected ? KoalaColors.accent : KoalaColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : KoalaColors.text,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _RoomOpt {
  final String key;
  final String label;
  const _RoomOpt(this.key, this.label);
}
