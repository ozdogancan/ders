import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/router/app_router.dart';
import '../core/theme/koala_tokens.dart';
import '../services/analytics_service.dart';

// ════════════════════════════════════════════════════════════════════════════
// OnboardingScreen — premium 3-page intro (2026-05 redesign).
//
// Layout per page:
//   ┌─────────────────────────────────┐
//   │                          Atla   │  Top-right skip
//   │  ╔═══════════════════════════╗  │
//   │  ║                           ║  │
//   │  ║   Full-bleed hero image   ║  │  ~55% h, rounded bottom 32
//   │  ║   (step1/2/3.png)         ║  │  subtle dark gradient overlay
//   │  ╚═══════════════════════════╝  │
//   │                                 │
//   │   ●  •  •                       │  pill page-dots
//   │                                 │
//   │   Tarzını keşfet                │  h1 28-32 w800
//   │   Yüzlerce tasarımı kaydır…     │  body 15 w500 muted
//   │                                 │
//   │   ┌─────────────────────────┐   │
//   │   │      Devam et / Başla   │   │  primary CTA
//   │   └─────────────────────────┘   │
//   └─────────────────────────────────┘
//
// Animation: image scales 0.96→1.0 over 280ms easeOutCubic; content fades
// in 80ms after image settles. Background is flat KoalaColors.bg.
// ════════════════════════════════════════════════════════════════════════════

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pc = PageController();
  int _idx = 0;
  bool _busy = false;

  static const List<_OnboardingPage> _pages = [
    _OnboardingPage(
      image: 'assets/onboarding/step1.webp',
      title: 'Tarzını keşfet',
      subtitle:
          'Yüzlerce tasarımı kaydır, neyi beğendiğini koala öğrensin.',
    ),
    _OnboardingPage(
      image: 'assets/onboarding/step2.webp',
      title: 'Mekânını dönüştür',
      subtitle:
          'Bir fotoğraf yükle, AI senin için yeniden tasarlasın.',
    ),
    _OnboardingPage(
      image: 'assets/onboarding/step3.webp',
      title: 'Tasarımcılarla buluş',
      subtitle:
          'Soru sor, fiyat al, projeyi başlat.',
    ),
  ];

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_busy) return;
    if (_idx >= _pages.length - 1) {
      setState(() => _busy = true);
      await _finish();
      if (mounted) setState(() => _busy = false);
      return;
    }
    await _pc.nextPage(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    onboardingComplete = true;
    if (!mounted) return;
    // Last page → show push permission nudge before /auth.
    // Skip on intermediate "Atla" too? We still show — opportunity is the same.
    await _maybeAskPushPermission();
    if (!mounted) return;
    context.go('/auth');
  }

  /// Shows a soft pre-permission sheet asking the user to enable push.
  /// On "İzin ver" we call FirebaseMessaging.requestPermission which surfaces
  /// the system dialog on iOS and Android 13+. On "Şimdi değil" we skip.
  /// Either way, we then continue to /auth (caller handles routing).
  Future<void> _maybeAskPushPermission() async {
    if (!mounted) return;
    final ctx = context;
    await Analytics.log('onboarding_push_prompt_shown');
    if (!mounted) return;
    final allow = await showModalBottomSheet<bool>(
      // ignore: use_build_context_synchronously
      context: ctx,
      isDismissible: true,
      isScrollControlled: false,
      backgroundColor: KoalaColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => _PushPermissionSheet(),
    );
    if (allow == true) {
      await Analytics.log('onboarding_push_allow');
      try {
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (_) {
        // Silently swallow — user is heading to /auth regardless.
      }
    } else {
      await Analytics.log('onboarding_push_deny');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar: skip only ─────────────────────────────────────────
            SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy ? null : _finish,
                    style: TextButton.styleFrom(
                      foregroundColor: KoalaColors.textMed,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                    child: Text(
                      'Atla',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: KoalaColors.textMed,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Page view ──────────────────────────────────────────────────
            Expanded(
              child: PageView.builder(
                controller: _pc,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _idx = i),
                itemBuilder: (_, i) => _PageBody(page: _pages[i]),
              ),
            ),

            // ── Dots ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) {
                  final on = i == _idx;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: on ? 26 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: on
                          ? KoalaColors.accentDeep
                          : KoalaColors.borderSolid,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  );
                }),
              ),
            ),

            // ── CTA ────────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: Semantics(
                  button: true,
                  enabled: !_busy,
                  label: _idx == _pages.length - 1 ? 'Başla' : 'Devam et',
                  child: ElevatedButton(
                  onPressed: _busy ? null : _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KoalaColors.text,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    disabledBackgroundColor:
                        KoalaColors.text.withValues(alpha: 0.6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(KoalaRadius.lg),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _idx == _pages.length - 1 ? 'Başla' : 'Devam et',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Per-page body: hero image (55%) + title + body, with entry animation ───
class _PageBody extends StatefulWidget {
  const _PageBody({required this.page});
  final _OnboardingPage page;

  @override
  State<_PageBody> createState() => _PageBodyState();
}

class _PageBodyState extends State<_PageBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _imgScale;
  late final Animation<double> _contentOpacity;

  @override
  void initState() {
    super.initState();
    // Image: 0..280ms scale 0.96→1.0 easeOutCubic.
    // Content fade: starts 80ms after image settles (offset 360ms),
    // duration 240ms → controller total 600ms.
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _imgScale = Tween<double>(begin: 0.96, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.467, curve: Curves.easeOutCubic),
        // 280 / 600 = 0.467
      ),
    );
    _contentOpacity = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
      // (280 + 80) / 600 = 0.6
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Available height inside the PageView (Scaffold body minus top bar 44,
    // dots ~32, CTA 80, paddings). Hero ~55% of full screen still feels
    // right; we cap so small phones stay balanced.
    final heroH = (mq.size.height * 0.50).clamp(280.0, 520.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero image — full-bleed of card, rounded bottom corners 32.
          ScaleTransition(
            scale: _imgScale,
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(32)),
              child: SizedBox(
                width: double.infinity,
                height: heroH,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      widget.page.image,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      errorBuilder: (_, _, _) => Container(
                        color: KoalaColors.accentLight,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.image_outlined,
                          size: 48,
                          color: KoalaColors.textMed,
                        ),
                      ),
                    ),
                    // Subtle dark gradient overlay at the bottom for depth.
                    // Decorative — hide from screen readers.
                    ExcludeSemantics(
                      child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.0),
                              Colors.black.withValues(alpha: 0.18),
                            ],
                            stops: const [0.6, 1.0],
                          ),
                        ),
                      ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          // Content: title + body, fades in after image settles.
          Expanded(
            child: FadeTransition(
              opacity: _contentOpacity,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.08),
                  end: Offset.zero,
                ).animate(_contentOpacity),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.page.title,
                        style: GoogleFonts.inter(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: KoalaColors.text,
                          height: 1.15,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.page.subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: KoalaColors.textMed,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPage {
  const _OnboardingPage({
    required this.image,
    required this.title,
    required this.subtitle,
  });
  final String image;
  final String title;
  final String subtitle;
}

// ─── Pre-permission sheet: warm ask before the OS push dialog ────────────────
// Returns true if user tapped "İzin ver", false / null if "Şimdi değil" or
// dismiss. Caller decides whether to actually call requestPermission().
class _PushPermissionSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Bell icon in soft accent circle.
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: KoalaColors.accentSoft,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                LucideIcons.bell,
                size: 32,
                color: KoalaColors.accentDeep,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Önemli güncellemelerden haberdar ol',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: KoalaColors.text,
                height: 1.25,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Tasarımcı yanıtları ve sana özel önerileri kaçırma. '
              'Bildirimler için izin verir misin?',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: KoalaColors.textMed,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: KoalaColors.text,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(KoalaRadius.lg),
                  ),
                ),
                child: Text(
                  'İzin ver',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: KoalaColors.textMed,
                ),
                child: Text(
                  'Şimdi değil',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: KoalaColors.textMed,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
