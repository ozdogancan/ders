import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/router/app_router.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pc = PageController();
  int _idx = 0;
  bool _busy = false;
  late final AnimationController _entry;
  final GlobalKey<_Page2State> _page2Key = GlobalKey<_Page2State>();

  final List<_PD> _pages = [
    _PD(
      'Evini akıllıca\ntasarla',
      'Fotoğrafını yükle, stilini analiz edeyim, ürün ve tasarım önerileri çıkarayım.',
      const Color(0xFF7C6EF2),
      const Color(0xFF4F46E5),
      0,
    ),
    _PD(
      'Fotoğrafını yükle,\nKoala yönünü çıkarsın',
      'Mekanını analiz eder, stilini tahmin eder ve uygulanabilir ürün önerileri hazırlar.',
      const Color(0xFF6C5CE7),
      const Color(0xFF4338CA),
      1,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
  }

  @override
  void dispose() {
    _pc.dispose();
    _entry.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_busy) return;
    if (_idx >= _pages.length - 1) {
      setState(() => _busy = true);
      await _goSignup();
      if (mounted) setState(() => _busy = false);
      return;
    }
    await _pc.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _goSignup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    onboardingComplete = true;
    if (!mounted) return;
    // GoRouter ile /auth'a git — Navigator push kullanma
    context.go('/auth');
  }

  @override
  Widget build(BuildContext context) {
    final pg = _pages[_idx];
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [pg.c1, pg.c2],
              ),
            ),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: CurvedAnimation(parent: _entry, curve: Curves.easeOut),
              child: Column(
                children: [
                  Expanded(
                    child: PageView.builder(
                      controller: _pc,
                      itemCount: _pages.length,
                      allowImplicitScrolling: true,
                      onPageChanged: (i) {
                        setState(() => _idx = i);
                        if (i == 1) {
                          _page2Key.currentState?.restartAnimation();
                        }
                      },
                      itemBuilder: (_, i) =>
                          i == 0 ? const _Page1() : _Page2(key: _page2Key),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: IndexedStack(
                      index: _idx,
                      alignment: Alignment.topCenter,
                      children: _pages
                          .map(
                            (p) => AnimatedOpacity(
                              opacity: p == pg ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 250),
                              child: Column(
                                children: [
                                  Text(
                                    p.title,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 34,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      height: 1.18,
                                      letterSpacing: -0.8,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    p.body,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w400,
                                      color: Colors.white.withValues(
                                        alpha: 0.72,
                                      ),
                                      height: 1.6,
                                      letterSpacing: 0.1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_pages.length, (i) {
                      final bool on = i == _idx;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: on ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          color: on
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.3),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 32),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _next,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: pg.c1,
                          elevation: 0,
                          disabledBackgroundColor: Colors.white.withValues(
                            alpha: 0.6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _busy
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: pg.c1,
                                ),
                              )
                            : Text(
                                _idx == _pages.length - 1 ? 'Başla' : 'Devam',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
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
}

class _Page1 extends StatefulWidget {
  const _Page1();
  @override
  State<_Page1> createState() => _Page1State();
}

class _Page1State extends State<_Page1> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final double innerCircleSize = screenW * 0.46;
    final double koalaSize = screenW * 0.74;
    final double stackSize = screenW * 0.80;
    return Column(
      children: [
        const Spacer(flex: 2),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutBack,
          builder: (_, v, child) => Transform.scale(
            scale: 0.8 + 0.2 * v,
            child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: stackSize,
                height: stackSize,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, child) {
                        final p = _pulse.value;
                        final scale = 1.0 + 0.02 * p;
                        final opacity = 0.09 + 0.06 * p;
                        return Transform.scale(
                          scale: scale,
                          child: Container(
                            width: screenW * 0.66,
                            height: screenW * 0.66,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: opacity),
                                width: 1.5,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, child) {
                        final p = _pulse.value;
                        final scale = 1.0 + 0.015 * (1.0 - p);
                        final opacity = 0.22 + 0.08 * p;
                        return Transform.scale(
                          scale: scale,
                          child: Container(
                            width: innerCircleSize,
                            height: innerCircleSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(
                                alpha: 0.06 + 0.03 * p,
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: opacity),
                                width: 1.5,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    ClipPath(
                      clipper: _KoalaClipper(koalaSize, innerCircleSize),
                      child: SizedBox(
                        width: koalaSize,
                        height: koalaSize,
                        child: Image.asset(
                          'assets/images/koala_hero.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: screenW * 0.10,
                      right: screenW * 0.02,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(99),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 16,
                              color: Color(0xFF7C6EF2),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Koala AI',
                              style: TextStyle(
                                color: Color(0xFF7C6EF2),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            _FeatureChip(Icons.home_work_rounded, 'Mekan analizi'),
            SizedBox(width: 10),
            _FeatureChip(Icons.auto_awesome_rounded, 'Stil önerileri'),
          ],
        ),
        const Spacer(flex: 2),
      ],
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.28),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.90)),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _KoalaClipper extends CustomClipper<Path> {
  final double koalaSize, circleSize;
  _KoalaClipper(this.koalaSize, this.circleSize);
  @override
  Path getClip(Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = circleSize / 2;
    final topRect = Path()
      ..addRect(Rect.fromLTRB(0, 0, size.width, center.dy + r * 0.15));
    final circle = Path()..addOval(Rect.fromCircle(center: center, radius: r));
    return Path.combine(PathOperation.union, topRect, circle);
  }

  @override
  bool shouldReclip(covariant _KoalaClipper old) =>
      old.koalaSize != koalaSize || old.circleSize != circleSize;
}

// ═══════════════════════════════════════════════════════════
// PAGE 2 — Demo animasyonlu AI analiz gösterimi
// 7sn loop: foto fade-in → scanning → stil kartı → ürün kartı
// ═══════════════════════════════════════════════════════════
class _Page2 extends StatefulWidget {
  const _Page2({super.key});
  @override
  State<_Page2> createState() => _Page2State();
}

class _Page2State extends State<_Page2>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final AnimationController _ctrl;
  @override
  bool get wantKeepAlive => true;

  static const _totalMs = 7000;

  void restartAnimation() {
    _ctrl.reset();
    _ctrl.repeat();
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _totalMs),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double _phase(double startSec, double endSec) {
    final start = startSec / 7.0;
    final end = endSec / 7.0;
    final t = ((_ctrl.value - start) / (end - start)).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(t);
  }

  double _scanLine() {
    if (_ctrl.value > 2.0 / 7.0) return 1.0;
    return (_ctrl.value / (2.0 / 7.0)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final w = MediaQuery.of(context).size.width;
    final photoW = w - 48;
    final photoH = photoW * 0.65;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final photoOpacity = _phase(0.0, 1.0);
        final scanProgress = _scanLine();
        final showScan = _ctrl.value < 2.5 / 7.0;
        final styleOpacity = _phase(2.0, 3.0);
        final productOpacity = _phase(4.0, 5.0);

        final availH = MediaQuery.of(context).size.height * 0.6;
        final clampedPhotoH = photoH.clamp(140.0, availH - 100);

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 24),
                Opacity(
                  opacity: photoOpacity,
                  child: SizedBox(
                    width: photoW,
                    height: clampedPhotoH + 90,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(
                            'assets/images/room_demo.jpg',
                            width: photoW,
                            height: clampedPhotoH,
                            fit: BoxFit.cover,
                          ),
                        ),
                        if (showScan)
                          Positioned(
                            top: clampedPhotoH * scanProgress - 6,
                            left: 0,
                            right: 0,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  height: 6,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        const Color(
                                          0xFF7C6EF2,
                                        ).withValues(alpha: 0.25),
                                        const Color(
                                          0xFFA78BFA,
                                        ).withValues(alpha: 0.25),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                                Container(
                                  height: 3,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        const Color(0xFF7C6EF2),
                                        const Color(0xFFA78BFA),
                                        Colors.transparent,
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF7C6EF2,
                                        ).withValues(alpha: 0.6),
                                        blurRadius: 12,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  height: 6,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        const Color(
                                          0xFFA78BFA,
                                        ).withValues(alpha: 0.25),
                                        const Color(
                                          0xFF7C6EF2,
                                        ).withValues(alpha: 0.25),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (showScan)
                          Positioned(
                            top: 12,
                            left: 12,
                            child: Opacity(
                              opacity: (1.0 - _phase(1.5, 2.5)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Analiz ediliyor...',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Opacity(
                            opacity: styleOpacity,
                            child: Transform.translate(
                              offset: Offset(20 * (1 - styleOpacity), 0),
                              child: Container(
                                width: 150,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.12,
                                      ),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(
                                          Icons.auto_awesome,
                                          size: 14,
                                          color: Color(0xFF7C6EF2),
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Stil Analizi',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF7C6EF2),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Boho & Doğal',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF1A1D2A),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: const [
                                        _ColorDot(0xFFF5F0EB, 'Krem'),
                                        _ColorDot(0xFFA0845C, 'Ahşap'),
                                        _ColorDot(0xFF6B8E6B, 'Yeşil'),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          left: 8,
                          right: 8,
                          child: Opacity(
                            opacity: productOpacity,
                            child: Transform.translate(
                              offset: Offset(0, 20 * (1 - productOpacity)),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.10,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.shopping_bag_rounded,
                                                size: 14,
                                                color: Color(0xFF8B5CF6),
                                              ),
                                              SizedBox(width: 4),
                                              Text(
                                                'Önerilen Ürünler',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF8B5CF6),
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            'Sana uygun 6 ürün buldum',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF1A1D2A),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    ...const [
                                      (0xFF7C6EF2, Icons.weekend_rounded),
                                      (0xFF8B5CF6, Icons.light_rounded),
                                      (0xFFA78BFA, Icons.table_bar_rounded),
                                    ].map(
                                      (e) => Container(
                                        width: 32,
                                        height: 32,
                                        margin: const EdgeInsets.only(left: 6),
                                        decoration: BoxDecoration(
                                          color: Color(
                                            e.$1,
                                          ).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Icon(
                                          e.$2,
                                          size: 16,
                                          color: Color(e.$1),
                                        ),
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
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot(this.hex, this.label);
  final int hex;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Column(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Color(0xFF000000 | hex),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black12, width: 0.5),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _PD {
  _PD(this.title, this.body, this.c1, this.c2, this.t);
  final String title, body;
  final Color c1, c2;
  final int t;
}
