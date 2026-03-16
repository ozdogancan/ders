import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'signup_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pc = PageController();
  int _idx = 0;
  late final AnimationController _entry;
  final GlobalKey<_Page2State> _page2Key = GlobalKey<_Page2State>();

  final List<_PD> _pages = [
    _PD(
      'Merhaba,\nben Koala!',
      'Hangi konuda takılırsan takıl, adım adım çözüm üretiyorum.',
      const Color(0xFF6366F1),
      const Color(0xFF818CF8),
      0,
    ),
    _PD(
      'Çek, gönder, anla',
      'Sorunun fotoğrafını çek. Koala adım adım çözsün.',
      const Color(0xFF0EA5E9),
      const Color(0xFF06B6D4),
      1,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400))
      ..forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Fotoğrafı ekran açılmadan belleğe al — ilk frame'de hazır olsun
    precacheImage(
      const AssetImage('assets/tutors/Matematik Man.png'),
      context,
    );
  }

  @override
  void dispose() {
    _pc.dispose();
    _entry.dispose();
    super.dispose();
  }

  void _next() {
    if (_idx >= _pages.length - 1) {
      _goSignup();
      return;
    }
    // 450ms → 300ms: daha çevik geçiş
    _pc.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic);
  }

  Future<void> _goSignup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, a, __) => const SignupScreen(),
        transitionsBuilder: (_, a, __, c) => FadeTransition(
            opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
            child: c),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pg = _pages[_idx];
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(fit: StackFit.expand, children: [
        // 600ms → 400ms: gradient geçişi
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [pg.c1, pg.c2, pg.c1],
            ),
          ),
        ),
        SafeArea(
          child: FadeTransition(
            opacity: CurvedAnimation(parent: _entry, curve: Curves.easeOut),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 16, 0),
                child: Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      // withAlpha(n) → const Color hex ile alpha
                      color: const Color(0x1FFFFFFF),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0x1AFFFFFF)),
                    ),
                    child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome,
                              size: 15, color: Colors.white),
                          SizedBox(width: 6),
                          Text('Koala',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13)),
                        ]),
                  ),
                ]),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pc,
                  itemCount: _pages.length,
                  allowImplicitScrolling: true,
                  onPageChanged: (i) {
                    setState(() => _idx = i);
                    // 2. sayfaya her gelişte gif baştan başlasın
                    if (i == 1) {
                      _page2Key.currentState?.restartAnimation();
                    }
                  },
                  itemBuilder: (_, i) =>
                      i == 0 ? const _Page1() : _Page2(key: _page2Key),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                // AnimatedSwitcher: başlık geçişine crossfade
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: Column(
                    key: ValueKey(_idx),
                    children: [
                      Text(pg.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1.2,
                              letterSpacing: -0.5)),
                      const SizedBox(height: 10),
                      Opacity(
                        opacity: 0.72,
                        child: Text(pg.body,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                                height: 1.5)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) {
                  final bool on = i == _idx;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: on ? 32 : 10,
                    height: 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      // Colors.white24 → const Color
                      color: on ? Colors.white : const Color(0x3DFFFFFF),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: pg.c1,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                        _idx == _pages.length - 1 ? 'Başla' : 'Devam',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════
// PAGE 1 — KOALA HERO (değişiklik yok, const'lar düzeltildi)
// ═══════════════════════════════════════════════════

class _Page1 extends StatelessWidget {
  const _Page1();

  @override
  Widget build(BuildContext context) {
    // Center yerine Column + Spacer: avatar alt kısma yakın otursun
    // böylece başlıkla arasındaki boşluk kapansın
    return Column(
      children: [
        const Spacer(flex: 3),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutBack,
          builder: (_, v, child) => Transform.scale(
              scale: 0.8 + 0.2 * v,
              child: Opacity(opacity: v.clamp(0.0, 1.0), child: child)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(alignment: Alignment.center, children: [
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
              ),
            ),
            Container(
              width: 170,
              height: 170,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Color(0x506366F1),
                      blurRadius: 50,
                      spreadRadius: 15),
                ],
              ),
            ),
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x61FFFFFF), width: 3),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x32000000),
                      blurRadius: 24,
                      offset: Offset(0, 10))
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/tutors/Matematik Man.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFF6366F1),
                    child:
                        const Icon(Icons.person, color: Colors.white, size: 60),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 10,
              right: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x28000000),
                        blurRadius: 10,
                        offset: Offset(0, 4))
                  ],
                ),
                child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome,
                          size: 14, color: Color(0xFF6366F1)),
                      SizedBox(width: 4),
                      Text('Koala',
                          style: TextStyle(
                              color: Color(0xFF6366F1),
                              fontWeight: FontWeight.w900,
                              fontSize: 12)),
                    ]),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              _FeatureChip(Icons.camera_alt_rounded, 'Foto ile soru çöz'),
              _FeatureChip(Icons.route_rounded, 'Adım adım çözüm'),
              _FeatureChip(Icons.school_rounded, '9 branş'),
            ],
          ),
        ]),
      ),
        const Spacer(flex: 1),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x33FFFFFF),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0x26FFFFFF)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: const Color(0xB3FFFFFF)),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                color: Color(0xB3FFFFFF),
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════
// PAGE 2 — GERÇEKÇI KAMERA DEMO
// Faz 1 (0.0-0.20): Defter kağıdı üzerinde soru görseli + kamera çerçevesi
// Faz 2 (0.20-0.35): Tarama animasyonu + "Analiz ediliyor"
// Faz 3 (0.35-0.75): Adım adım çözüm kartları beliriyor
// Faz 4 (0.75-0.90): Yeşil sonuç
// Faz 5 (0.90-1.0): Kısa bekleme, sonra loop
// ═══════════════════════════════════════════════════

class _Page2 extends StatefulWidget {
  const _Page2({super.key});
  @override
  State<_Page2> createState() => _Page2State();
}

class _Page2State extends State<_Page2>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final AnimationController _anim;

  @override
  bool get wantKeepAlive => true;

  /// Dışarıdan çağrılır — animasyonu baştan başlatır
  void restartAnimation() {
    _anim.reset();
    _anim.repeat();
  }

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 14000),
    )..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin gerektirir
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: Column(
        children: [
          const Spacer(flex: 2),
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _anim,
              builder: (context, _) {
                final double t = _anim.value;
                return _MiniAppDemo(t: t);
              },
            ),
          ),
          const Spacer(flex: 1),
        ],
      ),
    );
  }
}

/// Mini uygulama demo — telefon içinde telefon hissi
class _MiniAppDemo extends StatelessWidget {
  const _MiniAppDemo({required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    // Ekran yüksekliğinin %55'inden fazla yer kaplamasın
    final maxH = MediaQuery.of(context).size.height * 0.52;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxWidth: 340, maxHeight: maxH),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color(0xFF0C1425),
        border: Border.all(color: const Color(0x30FFFFFF)),
      ),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          // Mini app bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0x10FFFFFF)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF6366F1),
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Koala Tutor',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0x60FFFFFF),
                  ),
                ),
                const Spacer(),
                // Faz göstergesi
                _PhaseIndicator(t: t),
              ],
            ),
          ),
          // İçerik
          Padding(
            padding: const EdgeInsets.all(12),
            child: _buildContent(),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildContent() {
    // FAZ 1: Kamera çerçevesi + soru görseli (0.0 - 0.20)
    if (t < 0.20) {
      return _CameraPhase(t: t);
    }
    // FAZ 2: Analiz (0.20 - 0.35)
    if (t < 0.35) {
      return _AnalyzePhase(t: t);
    }
    // FAZ 3-4-5: Çözüm adımları + sonuç (0.35 - 1.0)
    return _SolvePhase(t: t);
  }
}

/// Faz göstergesi — 3 nokta, aktif olan beyaz
class _PhaseIndicator extends StatelessWidget {
  const _PhaseIndicator({required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    final int phase = t < 0.20 ? 0 : (t < 0.35 ? 1 : 2);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final bool done = i < phase;
        final bool current = i == phase;
        return Container(
          margin: const EdgeInsets.only(left: 3),
          width: current ? 16 : 6,
          height: 3,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            color: done
                ? const Color(0xFF22C55E)
                : current
                    ? Colors.white
                    : const Color(0x20FFFFFF),
          ),
        );
      }),
    );
  }
}

/// FAZ 1: Kamera çerçevesi + defter kağıdı üstünde soru
class _CameraPhase extends StatelessWidget {
  const _CameraPhase({required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    // t: 0.0 - 0.20 → normalize 0-1
    final double nt = (t / 0.20).clamp(0.0, 1.0);
    // Shutter flash efekti t=0.15 civarında
    final bool flash = t > 0.16 && t < 0.19;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Kamera çerçevesi
        Container(
          height: 150,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: flash ? Colors.white : const Color(0x15FFFFFF),
              width: flash ? 2 : 1.5,
            ),
            color: const Color(0x08FFFFFF),
          ),
          child: Stack(
            children: [
              // Defter kağıdı + soru (CustomPaint)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Opacity(
                    opacity: (nt * 2).clamp(0.0, 1.0),
                    child: const CustomPaint(
                      painter: _NotebookPainter(),
                    ),
                  ),
                ),
              ),
              // Kamera köşe işaretleri
              ..._buildCornerMarks(),
              // Tarama çizgisi (scan line)
              if (nt > 0.3 && nt < 0.85)
                Positioned(
                  left: 8,
                  right: 8,
                  top: 10 + (125 * ((nt - 0.3) / 0.55)).clamp(0.0, 125.0),
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(1),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0x0006B6D4),
                          Color(0xAA06B6D4),
                          Color(0x0006B6D4),
                        ],
                      ),
                    ),
                  ),
                ),
              // Flash efekti
              if (flash)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: const Color(0x40FFFFFF),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Alt bilgi
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              flash ? Icons.check_circle_rounded : Icons.camera_alt_rounded,
              size: 14,
              color: flash
                  ? const Color(0xFF22C55E)
                  : const Color(0x50FFFFFF),
            ),
            const SizedBox(width: 5),
            Text(
              flash ? 'Soru algılandı!' : 'Soruyu çerçeveye al...',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: flash
                    ? const Color(0xFF22C55E)
                    : const Color(0x50FFFFFF),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildCornerMarks() {
    const color = Color(0xFF06B6D4);
    const len = 18.0;
    const w = 2.0;
    return [
      // Sol üst
      Positioned(left: 6, top: 6, child: Container(width: len, height: w, color: color)),
      Positioned(left: 6, top: 6, child: Container(width: w, height: len, color: color)),
      // Sağ üst
      Positioned(right: 6, top: 6, child: Container(width: len, height: w, color: color)),
      Positioned(right: 6, top: 6, child: Container(width: w, height: len, color: color)),
      // Sol alt
      Positioned(left: 6, bottom: 6, child: Container(width: len, height: w, color: color)),
      Positioned(left: 6, bottom: 6, child: Container(width: w, height: len, color: color)),
      // Sağ alt
      Positioned(right: 6, bottom: 6, child: Container(width: len, height: w, color: color)),
      Positioned(right: 6, bottom: 6, child: Container(width: w, height: len, color: color)),
    ];
  }
}

/// Defter kağıdı üzerinde matematik sorusu çizen painter
class _NotebookPainter extends CustomPainter {
  const _NotebookPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Kağıt arka plan
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFFF8F6F0),
    );

    // Çizgiler
    final linePaint = Paint()
      ..color = const Color(0x1A94A3B8)
      ..strokeWidth = 0.8;
    for (double y = 28; y < size.height; y += 22) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // Sol kenar kırmızı çizgi
    canvas.drawLine(
      Offset(36, 0),
      Offset(36, size.height),
      Paint()
        ..color = const Color(0x30EF4444)
        ..strokeWidth = 1,
    );

    // "Soru 5)" yazısı
    final titlePainter = TextPainter(
      text: const TextSpan(
        text: 'Soru 5)',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Color(0xFF475569),
          fontFamily: 'serif',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    titlePainter.layout();
    titlePainter.paint(canvas, const Offset(44, 32));

    // Denklem
    final eqPainter = TextPainter(
      text: const TextSpan(
        text: '2x + 5 = 11',
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1E293B),
          letterSpacing: 1.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    eqPainter.layout();
    eqPainter.paint(canvas, Offset(44, 58));

    // Alt not
    final notePainter = TextPainter(
      text: const TextSpan(
        text: 'x = ?',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Color(0xFF6366F1),
          fontStyle: FontStyle.italic,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    notePainter.layout();
    notePainter.paint(canvas, const Offset(44, 92));

    // Altını çiz
    canvas.drawLine(
      const Offset(44, 110),
      const Offset(80, 110),
      Paint()
        ..color = const Color(0xFF6366F1)
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// FAZ 2: Analiz ediliyor
class _AnalyzePhase extends StatelessWidget {
  const _AnalyzePhase({required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    // t: 0.20 - 0.35 → normalize 0-1
    final double nt = ((t - 0.20) / 0.15).clamp(0.0, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Algılanan soru kartı
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: const Color(0x156366F1),
            border: Border.all(color: const Color(0x306366F1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome, size: 13, color: Color(0xFF818CF8)),
                  SizedBox(width: 4),
                  Text(
                    'Algılanan soru',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF818CF8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                '2x + 5 = 11',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Progress bar
        Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: const Color(0xFF06B6D4),
                value: nt,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Koala analiz ediyor...',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0x60FFFFFF),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Progress bar
        Container(
          height: 3,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            color: const Color(0x15FFFFFF),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: nt,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: const LinearGradient(
                  colors: [Color(0xFF06B6D4), Color(0xFF6366F1)],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Branş tespiti
        if (nt > 0.5)
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: const Color(0x206366F1),
                ),
                child: const Text(
                  'Matematik',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF818CF8),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: const Color(0x2006B6D4),
                ),
                child: const Text(
                  '1. Derece Denklem',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF06B6D4),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// FAZ 3-4-5: Adım adım çözüm + sonuç
class _SolvePhase extends StatelessWidget {
  const _SolvePhase({required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    // t: 0.35 - 1.0
    final double nt = ((t - 0.35) / 0.65).clamp(0.0, 1.0);
    final bool showStep1 = nt > 0.0;
    final bool showStep2 = nt > 0.25;
    final bool showFinal = nt > 0.50;
    final bool showResult = nt > 0.65;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Soru özeti (küçük)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: const Color(0x15FFFFFF),
            border: Border.all(color: const Color(0x12FFFFFF)),
          ),
          child: const Row(
            children: [
              Text(
                '2x + 5 = 11',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xB0FFFFFF),
                ),
              ),
              Spacer(),
              Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF4ADE80)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Çözüm adımları
        if (showStep1) _SolveStep(
          num: '1',
          title: 'Her iki taraftan 5 çıkar',
          math: '2x + 5 - 5 = 11 - 5',
          result: '2x = 6',
        ),
        if (showStep2) _SolveStep(
          num: '2',
          title: 'Her iki tarafı 2\'ye böl',
          math: '2x / 2 = 6 / 2',
          result: 'x = 3',
        ),
        if (showFinal) _SolveStep(
          num: '✓',
          title: 'Doğrulama',
          math: '2(3) + 5 = 6 + 5 = 11 ✓',
          result: '',
          isFinal: true,
        ),
        if (showResult) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: const Color(0x3322C55E),
              border: Border.all(color: const Color(0x6022C55E)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lightbulb_rounded, size: 20, color: Color(0xFF4ADE80)),
                SizedBox(width: 8),
                Text(
                  'Cevap: x = 3',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF4ADE80),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Tek bir çözüm adımı kartı
class _SolveStep extends StatelessWidget {
  const _SolveStep({
    required this.num,
    required this.title,
    required this.math,
    required this.result,
    this.isFinal = false,
  });
  final String num;
  final String title;
  final String math;
  final String result;
  final bool isFinal;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (_, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - v)),
          child: child,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isFinal
                ? const Color(0x2222C55E)
                : const Color(0x18FFFFFF),
            border: Border.all(
              color: isFinal
                  ? const Color(0x4022C55E)
                  : const Color(0x18FFFFFF),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFinal
                      ? const Color(0x4022C55E)
                      : const Color(0x15FFFFFF),
                ),
                child: Center(
                  child: Text(
                    num,
                    style: TextStyle(
                      fontSize: isFinal ? 13 : 11,
                      fontWeight: FontWeight.w800,
                      color: isFinal
                          ? const Color(0xFF22C55E)
                          : const Color(0x80FFFFFF),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isFinal
                            ? const Color(0xFF4ADE80)
                            : const Color(0xAAFFFFFF),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      math,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isFinal
                            ? const Color(0xBB4ADE80)
                            : const Color(0x70FFFFFF),
                      ),
                    ),
                    if (result.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        result,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF22D3EE),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// DATA
// ═══════════════════════════════════════════════════

class _PD {
  _PD(this.title, this.body, this.c1, this.c2, this.t);
  final String title;
  final String body;
  final Color c1;
  final Color c2;
  final int t;
}
