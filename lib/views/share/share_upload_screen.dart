// Instagram-tarzı paylaşım composer — premium redesign.
//
// Akış:
//   Step 1: Fotoğraf seç — hero illustration + büyük tile'lar.
//   Step 2: Caption + room type + tag chip'leri — preview top.
//   Step 3: Yayınla — animated loading, blurred image bg, status text.
//
// Mekan re-design wizard'ından FARKLI: bu sadece bir post; AI ile yeniden
// tasarlama yapmıyor. Pro gate yok — paylaşım herkese ücretsiz.
//
// Web: image_picker camera unreliable — on web we still SHOW the camera
// tile but route taps to gallery picker with an info snackbar, so the
// affordance isn't hidden and discovery feels consistent across platforms.

import 'dart:typed_data';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/koala_tokens.dart';
import '../../services/shared_design_service.dart';
import '../../widgets/koala_back_button.dart';

class ShareUploadScreen extends StatefulWidget {
  const ShareUploadScreen({super.key});

  @override
  State<ShareUploadScreen> createState() => _ShareUploadScreenState();
}

class _ShareUploadScreenState extends State<ShareUploadScreen>
    with TickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _captionCtl = TextEditingController();

  Uint8List? _bytes;
  int _step = 0; // 0=pick, 1=compose, 2=publishing
  bool _busy = false;
  String? _selectedRoom;
  final Set<String> _selectedTags = <String>{};

  // Publishing sub-state.
  // 0=upload, 1=moderate, 2=publish, 3=done, -1=fail
  int _pubPhase = 0;
  String? _failMsg;

  late final AnimationController _sparkleCtl;

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
  void initState() {
    super.initState();
    _sparkleCtl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _captionCtl.dispose();
    _sparkleCtl.dispose();
    super.dispose();
  }

  // ─── Step 1: foto seç ───
  Future<void> _pick(ImageSource source) async {
    // Web kamera image_picker'da güvenilmez → galeri'ye düş, kullanıcıya
    // kibar bir snackbar ile bildir. Mobile'da kamera normal akışa devam.
    ImageSource effective = source;
    if (kIsWeb && source == ImageSource.camera) {
      _snack('Tarayıcıda kamera desteklenmiyor — galeriden seç');
      effective = ImageSource.gallery;
    }
    try {
      final f = await _picker.pickImage(
        source: effective,
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
      // Don't block UI — surface actual error so user knows what went wrong
      // (e.g. permission denied vs. cancelled).
      _snack('Fotoğraf seçilemedi: $e');
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
      _pubPhase = 0;
      _failMsg = null;
    });

    // 1) Upload
    final url = await SharedDesignService.uploadImage(_bytes!);
    if (url == null) {
      _fail('Yükleme başarısız — bağlantını kontrol et');
      return;
    }
    if (!mounted) return;
    setState(() => _pubPhase = 1);

    // 2) AI moderation
    final mod = await SharedDesignService.moderate(imageUrl: url);
    if (!mod.ok) {
      final reason = mod.reason ?? 'unknown';
      _fail(_humanReason(reason));
      return;
    }
    if (!mounted) return;
    setState(() => _pubPhase = 2);

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

    if (!mounted) return;
    setState(() => _pubPhase = 3);

    // Done — bir an "yayında" hissini göster, sonra kapat.
    await Future<void>.delayed(const Duration(milliseconds: 650));

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
      _pubPhase = -1;
      _failMsg = msg;
    });
  }

  void _retryFromFail() {
    setState(() {
      _step = 1;
      _busy = false;
      _pubPhase = 0;
      _failMsg = null;
    });
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
      // Step 0'da kendi içinde tam ekran hero göstereceğiz; AppBar'ı sade
      // tutuyoruz ki "dünyaya açılan kapı" hissi bozulmasın.
      appBar: _step == 0
          ? null
          : AppBar(
              backgroundColor: KoalaColors.bg,
              elevation: 0,
              surfaceTintColor: KoalaColors.bg,
              title: Text(
                _step == 1 ? 'Yeni gönderi' : 'Yayınlanıyor',
                style: KoalaText.h2,
              ),
              leading: KoalaBackButton(
                onTap: _busy
                    ? () {}
                    : () {
                        if (_step == 1) {
                          setState(() => _step = 0);
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
              ),
              leadingWidth: 64,
              actions: [
                if (_step == 1)
                  Padding(
                    padding: const EdgeInsets.only(right: KoalaSpacing.md),
                    child: TextButton(
                      onPressed: _busy ? null : _publish,
                      style: TextButton.styleFrom(
                        backgroundColor: KoalaColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(KoalaRadius.pill),
                        ),
                      ),
                      child: const Text(
                        'Yayınla',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) {
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(anim);
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(position: slide, child: child),
          );
        },
        child: KeyedSubtree(
          key: ValueKey<int>(_step),
          child: _step == 0
              ? _stepPick()
              : _step == 1
                  ? _stepCompose()
                  : _stepPublishing(),
        ),
      ),
    );
  }

  // ─── Step 1: Picker — hero + tiles ───
  Widget _stepPick() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final heroH = constraints.maxHeight * 0.5;
        return Stack(
          children: [
            // Hero illustration (50% height) with gradient overlay.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: heroH,
              child: _heroIllustration(),
            ),
            // Content
            SafeArea(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    children: [
                      // İptal pinned top-left over hero.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            KoalaSpacing.md, KoalaSpacing.sm, KoalaSpacing.md, 0),
                        child: Row(
                          children: [
                            _ghostIconBtn(
                              icon: LucideIcons.x,
                              onTap: () => Navigator.of(context).pop(),
                            ),
                            const Spacer(),
                          ],
                        ),
                      ),
                      SizedBox(height: heroH - 80),
                      // Card with headline + tiles.
                      Container(
                        margin: const EdgeInsets.fromLTRB(
                            KoalaSpacing.lg, 0, KoalaSpacing.lg, KoalaSpacing.lg),
                        padding: const EdgeInsets.fromLTRB(
                            KoalaSpacing.xl, KoalaSpacing.xxl,
                            KoalaSpacing.xl, KoalaSpacing.xl),
                        decoration: BoxDecoration(
                          color: KoalaColors.surface,
                          borderRadius:
                              BorderRadius.circular(KoalaRadius.xl),
                          boxShadow: KoalaShadows.elevated,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Tasarımını paylaş 🌍',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: KoalaColors.text,
                                letterSpacing: -0.5,
                                height: 1.15,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: KoalaSpacing.sm),
                            const Text(
                              'Toplulukla buluşsun, ilham ver.',
                              style: TextStyle(
                                fontSize: 14,
                                color: KoalaColors.textSec,
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: KoalaSpacing.xxl),
                            _pickTile(
                              icon: LucideIcons.image,
                              label: 'Galeriden seç',
                              sub: 'Cihazındaki bir fotoğrafı yükle',
                              gradient: true,
                              onTap: () => _pick(ImageSource.gallery),
                            ),
                            const SizedBox(height: KoalaSpacing.md),
                            _pickTile(
                              icon: LucideIcons.camera,
                              label: 'Kamera ile çek',
                              sub: kIsWeb
                                  ? 'Tarayıcıda galeri açılır'
                                  : 'Anlık bir fotoğraf çek',
                              gradient: false,
                              onTap: () => _pick(ImageSource.camera),
                            ),
                            const SizedBox(height: KoalaSpacing.lg),
                            const Text(
                              'AI içerik kontrolünden geçer; uygunsuz veya oda olmayan görseller reddedilir.',
                              style: TextStyle(
                                color: KoalaColors.textTer,
                                fontSize: 11.5,
                                height: 1.45,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Gemini-generated hero (16:9). Falls back to onboarding asset, then to
  // brand gradient if neither loads — so screen never breaks.
  static const String _heroUrl =
      'https://xgefjepaqnghaotqybpi.supabase.co/storage/v1/object/public/koala-seed/share/hero-v1.webp';

  Widget _heroIllustration() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background image with cascading fallback: remote → asset → gradient.
        CachedNetworkImage(
          imageUrl: _heroUrl,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 260),
          placeholder: (_, __) => Image.asset(
            'assets/onboarding/step2.webp',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              decoration: const BoxDecoration(
                gradient: KoalaColors.accentGradientV,
              ),
            ),
          ),
          errorWidget: (_, __, ___) => Image.asset(
            'assets/onboarding/step2.webp',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              decoration: const BoxDecoration(
                gradient: KoalaColors.accentGradientV,
              ),
            ),
          ),
        ),
        // Purple-ish overlay for legibility + brand cohesion.
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                KoalaColors.accent.withValues(alpha: 0.30),
                KoalaColors.accentDark.withValues(alpha: 0.45),
                KoalaColors.bg,
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
        // Sparkle accent — top-right.
        Positioned(
          top: 48,
          right: 28,
          child: AnimatedBuilder(
            animation: _sparkleCtl,
            builder: (_, __) {
              final t = _sparkleCtl.value;
              return Opacity(
                opacity: 0.6 + 0.4 * (0.5 + 0.5 * (t * 2 - 1).abs()),
                child: const Icon(
                  LucideIcons.sparkles,
                  size: 28,
                  color: Colors.white,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _ghostIconBtn({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.85),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(KoalaSpacing.sm),
          child: Icon(LucideIcons.x, size: 20, color: KoalaColors.text),
        ),
      ),
    );
  }

  Widget _pickTile({
    required IconData icon,
    required String label,
    required String sub,
    required bool gradient,
    required VoidCallback onTap,
  }) {
    final decoration = gradient
        ? BoxDecoration(
            gradient: KoalaColors.accentGradient,
            borderRadius: BorderRadius.circular(KoalaRadius.lg),
            boxShadow: KoalaShadows.accentGlow,
          )
        : BoxDecoration(
            color: KoalaColors.surface,
            borderRadius: BorderRadius.circular(KoalaRadius.lg),
            border: Border.all(color: KoalaColors.borderSolid, width: 1),
            boxShadow: KoalaShadows.card,
          );
    final fg = gradient ? Colors.white : KoalaColors.text;
    final subFg = gradient
        ? Colors.white.withValues(alpha: 0.85)
        : KoalaColors.textSec;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KoalaRadius.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: KoalaSpacing.lg, vertical: KoalaSpacing.lg),
        decoration: decoration,
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: gradient
                    ? Colors.white.withValues(alpha: 0.22)
                    : KoalaColors.accentSoft,
                borderRadius: BorderRadius.circular(KoalaRadius.md),
              ),
              child: Icon(
                icon,
                color: gradient ? Colors.white : KoalaColors.accent,
                size: 22,
              ),
            ),
            const SizedBox(width: KoalaSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: TextStyle(
                      color: subFg,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              color: gradient ? Colors.white : KoalaColors.textTer,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Step 2: Compose ───
  Widget _stepCompose() {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, c) {
          final previewH = c.maxHeight * 0.45;
          return Stack(
            children: [
              SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  KoalaSpacing.lg,
                  KoalaSpacing.sm,
                  KoalaSpacing.lg,
                  // bottom space for pinned bar.
                  88,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Preview
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: SizedBox(
                        height: previewH,
                        width: double.infinity,
                        child: _bytes == null
                            ? Container(color: KoalaColors.surfaceAlt)
                            : Image.memory(_bytes!, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(height: KoalaSpacing.lg),
                    // Card with form
                    Container(
                      padding: const EdgeInsets.all(KoalaSpacing.lg),
                      decoration: BoxDecoration(
                        color: KoalaColors.surface,
                        borderRadius:
                            BorderRadius.circular(KoalaRadius.lg),
                        border: Border.all(
                            color: KoalaColors.border, width: 0.5),
                        boxShadow: KoalaShadows.card,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Açıklama', style: KoalaText.label),
                          const SizedBox(height: KoalaSpacing.sm),
                          TextField(
                            controller: _captionCtl,
                            maxLength: 250,
                            maxLines: 4,
                            style: KoalaText.body,
                            decoration: InputDecoration(
                              hintText:
                                  'Bu mekan hakkında bir şeyler yaz…',
                              hintStyle: KoalaText.hint,
                              filled: true,
                              fillColor: KoalaColors.surfaceMuted,
                              contentPadding: const EdgeInsets.all(14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                    KoalaRadius.sm),
                                borderSide: BorderSide(
                                    color: KoalaColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                    KoalaRadius.sm),
                                borderSide: BorderSide(
                                    color: KoalaColors.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                    KoalaRadius.sm),
                                borderSide: const BorderSide(
                                    color: KoalaColors.accent,
                                    width: 1.4),
                              ),
                            ),
                          ),
                          const SizedBox(height: KoalaSpacing.md),
                          const Text('Oda tipi', style: KoalaText.label),
                          const SizedBox(height: KoalaSpacing.sm),
                          Wrap(
                            spacing: KoalaSpacing.sm,
                            runSpacing: KoalaSpacing.sm,
                            children: _rooms.map((r) {
                              final on = _selectedRoom == r.key;
                              return _chip(
                                label: r.label,
                                selected: on,
                                onTap: () => setState(() =>
                                    _selectedRoom = on ? null : r.key),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: KoalaSpacing.lg),
                          const Text('Tarz etiketleri',
                              style: KoalaText.label),
                          const SizedBox(height: KoalaSpacing.sm),
                          Wrap(
                            spacing: KoalaSpacing.sm,
                            runSpacing: KoalaSpacing.sm,
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
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Pinned bottom bar
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(
                      KoalaSpacing.lg, KoalaSpacing.md,
                      KoalaSpacing.lg, KoalaSpacing.lg),
                  decoration: BoxDecoration(
                    color: KoalaColors.bg.withValues(alpha: 0.92),
                    border: Border(
                      top: BorderSide(
                          color: KoalaColors.border, width: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _step = 0),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: KoalaColors.text,
                            side: BorderSide(
                                color: KoalaColors.borderSolid),
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(KoalaRadius.md),
                            ),
                          ),
                          child: const Text(
                            'Geri',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15),
                          ),
                        ),
                      ),
                      const SizedBox(width: KoalaSpacing.md),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _busy ? null : _publish,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: KoalaColors.accent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(KoalaRadius.md),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Devam et',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              SizedBox(width: 6),
                              Icon(LucideIcons.arrowRight, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ─── Step 3: Publishing ───
  Widget _stepPublishing() {
    final isFail = _pubPhase == -1;
    final isDone = _pubPhase == 3;
    final phaseText = isFail
        ? (_failMsg ?? 'Bir şeyler ters gitti')
        : isDone
            ? 'Tasarımın yayında ✨'
            : _pubPhase == 0
                ? 'Yükleniyor…'
                : _pubPhase == 1
                    ? 'AI uygunluğu kontrol ediliyor…'
                    : 'Yayınlanıyor…';

    return SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred image background.
          if (_bytes != null)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Image.memory(
                _bytes!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          Container(
            color: KoalaColors.bg.withValues(alpha: 0.78),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(KoalaSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isFail)
                    _failBlock()
                  else
                    _publishingBlock(isDone),
                  const SizedBox(height: KoalaSpacing.xl),
                  Text(
                    phaseText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isFail
                          ? KoalaColors.errorDark
                          : KoalaColors.text,
                      height: 1.4,
                    ),
                  ),
                  if (isFail) ...[
                    const SizedBox(height: KoalaSpacing.xl),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: KoalaColors.text,
                            side: BorderSide(
                                color: KoalaColors.borderSolid),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(KoalaRadius.md),
                            ),
                          ),
                          child: const Text('Vazgeç'),
                        ),
                        const SizedBox(width: KoalaSpacing.md),
                        ElevatedButton.icon(
                          onPressed: _retryFromFail,
                          icon: const Icon(LucideIcons.refreshCw,
                              size: 16),
                          label: const Text('Düzenle ve tekrar dene'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: KoalaColors.accent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(KoalaRadius.md),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _publishingBlock(bool done) {
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer rotating sparkles
          AnimatedBuilder(
            animation: _sparkleCtl,
            builder: (_, __) {
              return Transform.rotate(
                angle: _sparkleCtl.value * 6.283,
                child: Stack(
                  children: [
                    Positioned(
                      top: 6,
                      left: 60,
                      child: _sparkleDot(size: 6, color: KoalaColors.accent),
                    ),
                    Positioned(
                      bottom: 10,
                      left: 18,
                      child: _sparkleDot(
                          size: 4, color: KoalaColors.accentMuted),
                    ),
                    Positioned(
                      top: 40,
                      right: 8,
                      child: _sparkleDot(
                          size: 5, color: KoalaColors.accentDeep),
                    ),
                    Positioned(
                      bottom: 30,
                      right: 22,
                      child: _sparkleDot(size: 3, color: KoalaColors.pink),
                    ),
                  ],
                ),
              );
            },
          ),
          // Center disk
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              gradient: KoalaColors.accentGradient,
              shape: BoxShape.circle,
              boxShadow: KoalaShadows.accentGlow,
            ),
            alignment: Alignment.center,
            child: done
                ? const Icon(LucideIcons.check,
                    color: Colors.white, size: 44)
                : const SizedBox(
                    width: 42,
                    height: 42,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sparkleDot({required double size, required Color color}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.6),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  Widget _failBlock() {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: KoalaColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: KoalaColors.errorBright, width: 2),
        boxShadow: KoalaShadows.card,
      ),
      child: const Icon(
        LucideIcons.alertCircle,
        color: KoalaColors.errorDark,
        size: 44,
      ),
    );
  }

  // ─── Bits ───
  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KoalaRadius.pill),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? KoalaColors.accent : KoalaColors.surface,
          borderRadius: BorderRadius.circular(KoalaRadius.pill),
          border: Border.all(
            color: selected
                ? KoalaColors.accent
                : KoalaColors.borderSolid,
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
