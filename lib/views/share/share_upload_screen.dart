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

import 'dart:async';
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
  /// FIX 7 (2026-05-28): when true the screen is being hosted inside a
  /// `showModalBottomSheet` rather than as a full route. We tweak the
  /// chrome (rounded top, drag handle) so it looks like a sheet.
  final bool inSheet;
  const ShareUploadScreen({super.key, this.inSheet = false});

  @override
  State<ShareUploadScreen> createState() => _ShareUploadScreenState();
}

/// FIX 7 (2026-05-28): open the share composer as a popup modal sheet
/// (92% maxHeight, draggable). Returns once the sheet is dismissed.
Future<void> openShareUploadSheet(BuildContext context) async {
  final mq = MediaQuery.of(context);
  await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: KoalaColors.bg,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: true,
    isDismissible: true,
    barrierColor: Colors.black54,
    // 2026-05-28 FIX 2: cap to 0.85 so the sheet doesn't visually overflow
    // beyond the popup area on tall devices.
    constraints: BoxConstraints(maxHeight: mq.size.height * 0.85),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => const ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      child: ShareUploadScreen(inSheet: true),
    ),
  );
}

class _ShareUploadScreenState extends State<ShareUploadScreen>
    with TickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();

  Uint8List? _bytes;
  // 2026-05-28 FIX 2: step semantics
  //   0 = picker (galeriden seç)
  //   1 = analyze / review / reject — AI çalışırken loading, biterse ya
  //       reject UI ya da onay UI (Yayınla butonu) gösterilir.
  //   2 = publishing (yüklüyor / yayına alıyor)
  int _step = 0;
  bool _busy = false;

  // 2026-05-28 FIX 2: AI analysis state
  // ─ _analyzing: AI çağrısı sürüyor (loading overlay).
  // ─ _analyzeOk: API ok=true döndü → review UI.
  // ─ _analyzeReject: API ok=false → reject UI.
  // ─ _detectedRoom/_detectedStyle: ok=true ise ham anahtar (örn 'salon').
  // ─ _uploadedUrl: ilk upload sonucu, publish'te tekrar yüklemiyoruz.
  bool _analyzing = false;
  bool _analyzeOk = false;
  bool _analyzeReject = false;
  String _detectedRoomRaw = ''; // e.g. 'salon', 'yatak_odasi'
  String _detectedStyleRaw = ''; // e.g. 'modern'
  String _rejectMsg = '';
  // 2026-06-02 (Task D): reddin teknik mi (yükleme/AI/ağ hatası) yoksa içerik
  // mi (not_a_room/inappropriate) olduğunu ayırt etmek için saklanan reason.
  // Teknik hatalarda sert "Bu fotoğraf uygun değil" başlığı GÖSTERİLMEZ.
  String _rejectReason = '';
  String? _uploadedUrl;

  // Publishing sub-state.
  // 0=upload, 1=moderate, 2=publish, 3=done, -1=fail
  int _pubPhase = 0;
  String? _failMsg;

  late final AnimationController _sparkleCtl;

  // 2026-05-28 FIX 2: oda/tarz seçim chip'leri kaldırıldı — AI tespit
  // ediyor. Eski _rooms / _tagOptions sabitleri silindi.

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
    _sparkleCtl.dispose();
    super.dispose();
  }

  // ─── 2026-05-28 FIX 2: kategori / tarz görünen etiketleri ───
  // API ham anahtarları → kullanıcı yüzünde gösterilecek TR etiket.
  static const Map<String, String> _kRoomLabel = {
    'salon': 'Salon',
    'yatak_odasi': 'Yatak Odası',
    'mutfak': 'Mutfak',
    'banyo': 'Banyo',
    'antre': 'Antre',
    'balkon': 'Balkon',
    'yemek_odasi': 'Yemek Odası',
    'cocuk_odasi': 'Çocuk Odası',
    'ofis': 'Ofis',
  };
  static const Map<String, String> _kStyleLabel = {
    'modern': 'Modern',
    'minimal': 'Minimal',
    'skandinav': 'Skandinav',
    'klasik': 'Klasik',
    'bohem': 'Bohem',
    'endustriyel': 'Endüstriyel',
    'luks': 'Lüks',
    'japandi': 'Japandi',
  };
  // shared_designs DB konvansiyonu (style_discovery deck'i ile uyumlu)
  // için backend ham anahtarını DB anahtarına çeviriyoruz.
  static const Map<String, String> _kRoomToDbKey = {
    'salon': 'living_room',
    'yatak_odasi': 'bedroom',
    'mutfak': 'kitchen',
    'banyo': 'bathroom',
    'antre': 'hall',
    'balkon': 'balcony',
    'yemek_odasi': 'dining_room',
    'cocuk_odasi': 'kids_room',
    'ofis': 'office',
  };

  String get _detectedRoomLabel =>
      _kRoomLabel[_detectedRoomRaw] ?? '';
  String get _detectedStyleLabel =>
      _kStyleLabel[_detectedStyleRaw] ?? '';

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
        _analyzing = true;
        _analyzeOk = false;
        _analyzeReject = false;
        _detectedRoomRaw = '';
        _detectedStyleRaw = '';
        _rejectMsg = '';
        _uploadedUrl = null;
      });
      // 2026-05-28 FIX 2: AI analyze → review/reject UI before publish.
      unawaited(_analyze());
    } catch (e) {
      // Don't block UI — surface actual error so user knows what went wrong
      // (e.g. permission denied vs. cancelled).
      _snack('Fotoğraf seçilemedi: $e');
    }
  }

  // 2026-05-28 FIX 2: AI uygunluk + kategori/tarz analizi.
  // Upload → moderate. Sonuçta ya review UI ya reject UI'e geçeriz.
  // publish() çağrısı kullanıcıya kalır (Yayınla butonu).
  Future<void> _analyze() async {
    if (_bytes == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Önce giriş yap');
      if (mounted) {
        setState(() {
          _analyzing = false;
          _step = 0;
        });
      }
      return;
    }

    // 1) Upload — moderate API public URL bekliyor.
    final url = await SharedDesignService.uploadImage(_bytes!);
    if (url == null) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _analyzeReject = true;
        _rejectReason = 'upload_failed';
        _rejectMsg = 'Fotoğraf yüklenemedi — bağlantını kontrol et.';
      });
      return;
    }

    // 2) Moderate + kategori/tarz tespiti.
    final mod = await SharedDesignService.moderate(imageUrl: url);
    if (!mounted) return;
    if (!mod.ok) {
      setState(() {
        _analyzing = false;
        _analyzeReject = true;
        _rejectReason = mod.reason ?? 'unknown';
        _rejectMsg = _humanReason(mod.reason ?? 'unknown');
        _uploadedUrl = url; // not used; we re-upload on retry anyway.
      });
      return;
    }

    // 3) Onaylandı — review UI.
    setState(() {
      _analyzing = false;
      _analyzeOk = true;
      _detectedRoomRaw = mod.roomType;
      _detectedStyleRaw = mod.style;
      _uploadedUrl = url;
    });
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

  // ─── Step 2: yayınla ───
  // 2026-05-28 FIX 2: artık burada upload + moderate yok — onlar analyze
  // fazında bitti. Sadece publish (insert) yapıyoruz.
  Future<void> _publish() async {
    if (_bytes == null || _busy) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Önce giriş yap');
      return;
    }
    final url = _uploadedUrl;
    if (url == null) {
      // Defensive: shouldn't happen because Yayınla only enabled after ok.
      _snack('Önce fotoğraf analiz edilmeli');
      return;
    }

    setState(() {
      _busy = true;
      _step = 2;
      _pubPhase = 2; // upload + moderate done, jump straight to publish phase.
      _failMsg = null;
    });

    // DB için ham anahtarı standartlaştır.
    final dbRoom = _kRoomToDbKey[_detectedRoomRaw] ?? _detectedRoomRaw;
    final tags = <String>[
      if (_detectedStyleRaw.isNotEmpty) _detectedStyleRaw,
    ];

    final saved = await SharedDesignService.publish(
      imageUrl: url,
      description: null,
      roomType: dbRoom.isEmpty ? null : dbRoom,
      tags: tags,
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
    // 2026-05-28 FIX 2: tüm analiz/state'i sıfırla, picker'a dön.
    setState(() {
      _step = 0;
      _bytes = null;
      _busy = false;
      _pubPhase = 0;
      _failMsg = null;
      _analyzing = false;
      _analyzeOk = false;
      _analyzeReject = false;
      _detectedRoomRaw = '';
      _detectedStyleRaw = '';
      _rejectMsg = '';
      _rejectReason = '';
      _uploadedUrl = null;
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
    final scaffold = Scaffold(
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
                _step == 1
                    ? (_analyzing
                        ? 'Analiz ediliyor'
                        : (_analyzeReject ? 'Uygun değil' : 'Onayla ve yayınla'))
                    : 'Yayınlanıyor',
                style: KoalaText.h2,
              ),
              leading: KoalaBackButton(
                onTap: _busy
                    ? () {}
                    : () {
                        if (_step == 1) {
                          _retryFromFail();
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
              ),
              leadingWidth: 64,
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
          // 2026-05-28 FIX 2: step 1 artık AI review/reject ekranı.
          child: _step == 0
              ? _stepPick()
              : _step == 1
                  ? _stepReview()
                  : _stepPublishing(),
        ),
      ),
    );
    if (!widget.inSheet) return scaffold;
    // 2026-06-02: Görsel popup'ın üst (yuvarlatılmış) şekline EN ÜSTTEN dayansın
    // diye drag handle artık içeriği aşağı itmiyor; scaffold tepeye yapışıyor ve
    // ince handle görselin üzerine OVERLAY ediliyor (kullanıcı isteği).
    return Stack(
      children: [
        Positioned.fill(child: scaffold),
        Positioned(
          top: 10,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(100),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
                            // 2026-05-28 FIX 2: Camera tile removed — only
                            // gallery picker, prominent single tile.
                            _pickTile(
                              icon: LucideIcons.image,
                              label: 'Galeriden seç',
                              sub: 'Cihazındaki bir fotoğrafı yükle',
                              gradient: true,
                              onTap: () => _pick(ImageSource.gallery),
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

  // Gemini-generated hero (16:9). 2026-05-28 FIX 2: v2 (cinematic editorial)
  // is the primary; falls back to v1, then onboarding asset, then brand
  // gradient if nothing loads — so screen never breaks.
  // 2026-06-02: v3 — Gemini (gemini-3-pro-image) ile üretilmiş sıcak nötr
  // tonlu premium iç mekan; alt üçte biri kreme fade oluyor → mor overlay
  // KALDIRILDI (kullanıcı isteği), sadece bg'ye yumuşak geçiş bırakıldı.
  static const String _heroUrlV3 =
      'https://xgefjepaqnghaotqybpi.supabase.co/storage/v1/object/public/koala-seed/share/hero-v3.jpg';
  static const String _heroUrlV2 =
      'https://xgefjepaqnghaotqybpi.supabase.co/storage/v1/object/public/koala-seed/share/hero-v2.webp';
  static const String _heroUrlV1 =
      'https://xgefjepaqnghaotqybpi.supabase.co/storage/v1/object/public/koala-seed/share/hero-v1.webp';

  Widget _heroIllustration() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background image with cascading fallback: v3 → v1 → asset → gradient.
        CachedNetworkImage(
          imageUrl: _heroUrlV3,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 260),
          placeholder: (_, __) => CachedNetworkImage(
            imageUrl: _heroUrlV1,
            fit: BoxFit.cover,
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
          errorWidget: (_, __, ___) => CachedNetworkImage(
            imageUrl: _heroUrlV1,
            fit: BoxFit.cover,
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
        ),
        // 2026-06-02: Mor overlay KALDIRILDI. Görselin kendisi alta doğru
        // krem tonuna fade oluyor; burada sadece okunabilirlik için en altta
        // bg'ye yumuşak, renksiz bir geçiş bırakıyoruz (mor tonu yok).
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.transparent,
                KoalaColors.bg,
              ],
              stops: const [0.0, 0.62, 1.0],
            ),
          ),
        ),
        // 2026-06-02: Mor "ışıltı"/sparkle aksanı KALDIRILDI (kullanıcı isteği).
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

  // ─── Step 2 (FIX 2): AI Analyze → Review / Reject ───
  // 3 alt-state:
  //   _analyzing   → loading overlay (spinner + "Analiz ediliyor")
  //   _analyzeReject → uygun değil ekranı (soft red, Başka fotoğraf seç)
  //   _analyzeOk   → onay ekranı (görsel + chip'ler + Yayınla butonu)
  Widget _stepReview() {
    if (_analyzing) return _reviewAnalyzing();
    if (_analyzeReject) return _reviewReject();
    return _reviewOk();
  }

  // Loading state — premium-quiet: küçük spinner + tek satır metin.
  Widget _reviewAnalyzing() {
    return SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_bytes != null)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Image.memory(_bytes!, fit: BoxFit.cover),
            ),
          Container(color: KoalaColors.bg.withValues(alpha: 0.82)),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _publishingBlock(false),
                const SizedBox(height: KoalaSpacing.xl),
                const Text(
                  'Analiz ediliyor…',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: KoalaColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'AI fotoğrafını inceliyor — birkaç saniye sürer.',
                  style: TextStyle(
                    fontSize: 13,
                    color: KoalaColors.textSec,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Reject state — premium-warm: turuncu daire + sad-koala ikon + açıklama.
  Widget _reviewReject() {
    // 2026-06-02 (Task D): Teknik hatalarda (yükleme/AI/ağ/rate-limit) sert
    // "Bu fotoğraf uygun değil" başlığını GÖSTERME — bu kullanıcının
    // fotoğrafının kötü olduğu izlenimini veriyordu. Sadece gerçek içerik
    // reddinde (not_a_room / inappropriate) o başlık kullanılır.
    const technicalReasons = {
      'upload_failed',
      'analysis_failed',
      'network',
      'rate_limited',
      'unknown',
    };
    final isTechnical = technicalReasons.contains(_rejectReason) ||
        _rejectReason.startsWith('http_');
    final title = isTechnical
        ? 'Bir sorun oluştu'
        : (_rejectReason == 'inappropriate'
            ? 'Bu içerik paylaşılamaz'
            : 'Bu fotoğraf uygun değil');
    final iconData =
        isTechnical ? LucideIcons.refreshCw : LucideIcons.imageOff;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(KoalaSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFEDDD),
                border: Border.all(
                  color: const Color(0xFFFFB680),
                  width: 1.2,
                ),
              ),
              child: Icon(
                iconData,
                size: 44,
                color: const Color(0xFFC25A1A),
              ),
            ),
            const SizedBox(height: KoalaSpacing.xl),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: KoalaColors.text,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              _rejectMsg.isEmpty
                  ? 'Bir oda fotoğrafı bekliyoruz. Başka bir görsel deneyebilirsin.'
                  : _rejectMsg,
              style: const TextStyle(
                fontSize: 14,
                color: KoalaColors.textSec,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KoalaSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _retryFromFail,
                icon: const Icon(LucideIcons.image, size: 18),
                label: const Text(
                  'Başka bir fotoğraf seç',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: KoalaColors.accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(KoalaRadius.pill),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Vazgeç',
                style: TextStyle(
                  color: KoalaColors.textSec,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // OK state — yayınla-öncesi SWIPE-KART önizlemesi ("keşfette böyle
  // görünecek") + AI kategorize bilgisi + Yayınla butonu.
  Widget _reviewOk() {
    final hasRoom = _detectedRoomLabel.isNotEmpty;
    final hasStyle = _detectedStyleLabel.isNotEmpty;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          KoalaSpacing.lg,
          KoalaSpacing.sm,
          KoalaSpacing.lg,
          KoalaSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // "Keşfette böyle görünecek" başlığı.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(LucideIcons.sparkles,
                    size: 15, color: KoalaColors.accentDeep),
                const SizedBox(width: 7),
                Text(
                  'Keşfette böyle görünecek',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: KoalaColors.textSec,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: KoalaSpacing.md),
            // Swipe deck kartının birebir önizlemesi (3:4).
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: _deckPreviewCard(),
                ),
              ),
            ),
            const SizedBox(height: KoalaSpacing.lg),
            // AI kategorize bilgisi — kompakt, kart altında.
            if (hasRoom || hasStyle)
              Center(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (hasRoom)
                      _analysisChip(
                        icon: LucideIcons.layoutGrid,
                        label: _detectedRoomLabel,
                      ),
                    if (hasStyle)
                      _analysisChip(
                        icon: LucideIcons.palette,
                        label: _detectedStyleLabel,
                      ),
                  ],
                ),
              ),
            const SizedBox(height: KoalaSpacing.xl),
            // Yayınla — premium purple gradient.
            Container(
              decoration: BoxDecoration(
                gradient: KoalaColors.accentGradient,
                borderRadius:
                    BorderRadius.circular(KoalaRadius.pill),
                boxShadow: KoalaShadows.accentGlow,
              ),
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _publish,
                  icon: const Icon(LucideIcons.sparkles, size: 18),
                  label: const Text(
                    'Yayınla ✨',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(KoalaRadius.pill),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _retryFromFail,
                icon: const Icon(LucideIcons.image,
                    size: 14, color: KoalaColors.textSec),
                label: const Text(
                  'Başka fotoğraf seç',
                  style: TextStyle(
                    color: KoalaColors.textSec,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _analysisChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: KoalaColors.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: KoalaColors.accent.withValues(alpha: 0.40),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: KoalaColors.accentDeep),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: KoalaColors.accentDeep,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Yayınla-öncesi deck-kart önizlemesi ───
  // style_discovery_live_screen'deki kartın birebir görsel kopyası: rounded
  // 24, foto cover, üç-duraklı alt gradient, sol-altta avatar + ad +
  // "Koala Kullanıcısı" altyazı. Kullanıcı kartının deck'te nasıl
  // görüneceğini gerçek görür (başlık metni kartta yok — sadece bu blok).
  Widget _deckPreviewCard() {
    final user = FirebaseAuth.instance.currentUser;
    final name = (user?.displayName ?? '').trim();
    final displayName = name.isEmpty ? 'Koala Kullanıcısı' : name;
    final avatar = (user?.photoURL ?? '').trim();
    final initials = displayName.isEmpty
        ? '?'
        : displayName.trim().split(RegExp(r'\s+')).take(2).map((w) {
            return w.isEmpty ? '' : w[0].toUpperCase();
          }).join();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: KoalaColors.surfaceAlt,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_bytes != null)
            Image.memory(_bytes!, fit: BoxFit.cover)
          else
            const Center(
              child: Icon(LucideIcons.image,
                  color: KoalaColors.textTer, size: 48),
            ),
          // Aynı üç-duraklı gradient (deck kartıyla birebir).
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.2, 0.7, 1.0],
                  colors: [
                    Colors.black.withValues(alpha: 0.12),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.78),
                  ],
                ),
              ),
            ),
          ),
          // Sol-alt: ev sahibi bilgisi (deck _DesignerBlock ile aynı düzen).
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 14, 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: KoalaColors.accentDeep,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                      image: avatar.isEmpty
                          ? null
                          : DecorationImage(
                              image: CachedNetworkImageProvider(avatar),
                              fit: BoxFit.cover,
                            ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: avatar.isEmpty
                        ? Text(
                            initials,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.1,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Koala Kullanıcısı',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.82),
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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

  // 2026-05-28 FIX 2: _chip helper ve _RoomOpt class kaldırıldı —
  // kategori/tarz chip'leri AI tarafından dolduruluyor, _analysisChip
  // doğrudan label'ı render ediyor.
}
