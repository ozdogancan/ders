import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/router/app_router.dart';
import '../core/theme/koala_tokens.dart';

// ════════════════════════════════════════════════════════════════════════════
// OnboardingScreen — Snaphome-style 3-step intro.
//
// Layout (her adım):
//   ┌─────────────────────────────────┐
//   │  ◀                       Atla   │  Top bar (back gizli step 0'da)
//   │                                 │
//   │      ╔═════════════════╗        │
//   │      ║  Hero Image     ║        │  ~55% h, full-bleed
//   │      ║  (Gemini)       ║        │
//   │      ╚═════════════════╝        │
//   │                                 │
//   ├─ cream sheet (~45% h) ──────────┤
//   │   Saniyeler içinde              │  Fraunces serif w600 28
//   │   hayalindeki tasarım           │
//   │                                 │
//   │   Bir fotoğraf çek, AI...       │  Manrope w500 15, textMed
//   │                                 │
//   │   ●  •  •                       │  page indicator
//   │                                 │
//   │   ┌─────────────────────────┐   │
//   │   │       Sonraki           │   │  KoalaColors.text bg
//   │   └─────────────────────────┘   │
//   └─────────────────────────────────┘
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
      image: 'assets/onboarding/step1.png',
      title: 'Saniyeler içinde\nhayalindeki tasarım',
      subtitle:
          'Bir fotoğraf çek, AI saniyeler içinde mekanını yeniden tasarlasın. Yüzlerce stil arasından seç.',
    ),
    _OnboardingPage(
      image: 'assets/onboarding/step2.png',
      title: 'Türkiye’nin en iyi\niç mimarlarıyla tanış',
      subtitle:
          'Beğendiğin tasarımı seç, profesyonele tek tıkla danış. Mesajlaş, ilham al, gerçeğe dönüştür.',
    ),
    _OnboardingPage(
      image: 'assets/onboarding/step3.png',
      title: 'Tasarım koleksiyonun\nher zaman yanında',
      subtitle:
          'Beğendiğin tasarımları kaydet, koleksiyonlar oluştur, ilham defteri biriktir.',
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
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _back() async {
    if (_idx == 0) return;
    await _pc.previousPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    onboardingComplete = true;
    if (!mounted) return;
    context.go('/auth');
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final h = mq.size.height;
    // Hero ~55% of available height, sheet ~45%.
    final heroH = h * 0.55;

    return Scaffold(
      backgroundColor: KoalaColors.bg,
      body: Stack(
        children: [
          // ── Pages ────────────────────────────────────────────────────────
          PageView.builder(
            controller: _pc,
            itemCount: _pages.length,
            onPageChanged: (i) {
              setState(() => _idx = i);
            },
            itemBuilder: (_, i) => _PageBody(
              page: _pages[i],
              heroH: heroH,
            ),
          ),

          // ── Top bar (back + skip) ────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _idx == 0 ? 0 : 1,
                      child: IconButton(
                        onPressed: _idx == 0 ? null : _back,
                        icon: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.85),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            LucideIcons.chevronLeft,
                            size: 20,
                            color: KoalaColors.text,
                          ),
                        ),
                      ),
                    ),
                    TextButton(
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
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: KoalaColors.textMed,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom sheet (text + dots + CTA) ─────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomSheet(
              page: _pages[_idx],
              idx: _idx,
              total: _pages.length,
              busy: _busy,
              isLast: _idx == _pages.length - 1,
              onNext: _next,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Per-page body: full-bleed hero + soft fade ─────────────────────────────
class _PageBody extends StatelessWidget {
  const _PageBody({required this.page, required this.heroH});
  final _OnboardingPage page;
  final double heroH;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Hero image — top portion
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: heroH + 24, // small overlap behind sheet
          child: Image.asset(
            page.image,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (_, _, _) => Container(
              color: KoalaColors.accentLight,
              child: const Center(
                child: Icon(LucideIcons.image, size: 48, color: KoalaColors.textMed),
              ),
            ),
          ),
        ),
        // Soft gradient fade at the bottom of the hero into the cream sheet
        Positioned(
          top: heroH - 80,
          left: 0,
          right: 0,
          height: 100,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    KoalaColors.bg.withValues(alpha: 0.0),
                    KoalaColors.bg,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Bottom cream sheet with headline / subtitle / dots / CTA ───────────────
class _BottomSheet extends StatelessWidget {
  const _BottomSheet({
    required this.page,
    required this.idx,
    required this.total,
    required this.busy,
    required this.isLast,
    required this.onNext,
  });

  final _OnboardingPage page;
  final int idx;
  final int total;
  final bool busy;
  final bool isLast;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: KoalaColors.bg,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Headline (Fraunces serif) — fixed height to avoid jumps when
              // line-count differs between pages; fade-only transition so it
              // matches the subtitle (which also uses fade-only).
              SizedBox(
                height: 72,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: Text(
                    page.title,
                    key: ValueKey('t$idx'),
                    style: GoogleFonts.fraunces(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: KoalaColors.text,
                      height: 1.18,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Subtitle (Manrope) — fixed min-height to keep layout stable
              // across pages with different line counts.
              SizedBox(
                height: 72,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: Text(
                    page.subtitle,
                    key: ValueKey('s$idx'),
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: KoalaColors.textMed,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: List.generate(total, (i) {
                  final on = i == idx;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.only(right: 6),
                    width: on ? 24 : 8,
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
              const SizedBox(height: 20),
              // CTA
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: busy ? null : onNext,
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
                  child: busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          isLast ? 'Hemen Başla' : 'Sonraki',
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
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
