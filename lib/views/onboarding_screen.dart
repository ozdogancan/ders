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
        vsync: this, duration: const Duration(milliseconds: 700))
      ..forward();
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
    _pc.nextPage(
        duration: const Duration(milliseconds: 450),
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
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pg = _pages[_idx];
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 600),
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
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white10),
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
                  const Spacer(),
                  // Skip button
                  GestureDetector(
                    onTap: _goSignup,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text('Atla',
                          style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ),
                  ),
                ]),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pc,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _idx = i),
                  itemBuilder: (_, i) =>
                      i == 0 ? const _Page1() : const _Page2(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(children: [
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
                ]),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) {
                  final bool on = i == _idx;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: on ? 32 : 10,
                    height: 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      color: on ? Colors.white : Colors.white24,
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

// ═══════════════════════════════════════════
// PAGE 1 — KOALA HERO
// ═══════════════════════════════════════════

class _Page1 extends StatelessWidget {
  const _Page1();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutBack,
        builder: (_, v, child) => Transform.scale(
            scale: 0.7 + 0.3 * v,
            child: Opacity(opacity: v.clamp(0.0, 1.0), child: child)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(alignment: Alignment.center, children: [
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white10, width: 1),
              ),
            ),
            Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFF6366F1).withAlpha(80),
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
                border: Border.all(color: Colors.white38, width: 3),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withAlpha(50),
                      blurRadius: 24,
                      offset: const Offset(0, 10))
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
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withAlpha(40),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
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
          const SizedBox(height: 28),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: const [
              _FeatureChip(Icons.camera_alt_rounded, 'Foto ile soru çöz'),
              _FeatureChip(Icons.route_rounded, 'Adım adım çözüm'),
              _FeatureChip(Icons.school_rounded, '9 branş'),
            ],
          ),
        ]),
      ),
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
        color: Colors.white.withAlpha(20),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: Colors.white70),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════
// PAGE 2 — SOLVING DEMO (same as before)
// ═══════════════════════════════════════════

class _Page2 extends StatefulWidget {
  const _Page2();
  @override
  State<_Page2> createState() => _Page2State();
}

class _Page2State extends State<_Page2> with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 6000))
      ..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Center(
        child: AnimatedBuilder(
          animation: _anim,
          builder: (context, _) {
            final double t = _anim.value;
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: const Color(0xFF0F172A).withAlpha(200),
                border: Border.all(color: Colors.white.withAlpha(15)),
              ),
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.white.withAlpha(10),
                        border: Border.all(color: Colors.white.withAlpha(12)),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                    color: Colors.white.withAlpha(15),
                                    borderRadius: BorderRadius.circular(8)),
                                child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.camera_alt_rounded,
                                          size: 11, color: Colors.white54),
                                      SizedBox(width: 4),
                                      Text('Soru',
                                          style: TextStyle(
                                              color: Colors.white54,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700)),
                                    ]),
                              ),
                              const Spacer(),
                              if (t > 0.2) _Badge(analyzing: t < 0.4),
                            ]),
                            const SizedBox(height: 10),
                            const Text('2x + 5 = 11',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1)),
                            const SizedBox(height: 2),
                            const Opacity(
                                opacity: 0.45,
                                child: Text('x değerini bulunuz.',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 12))),
                          ]),
                    ),
                    const SizedBox(height: 12),
                    if (t >= 0.2 && t < 0.4)
                      Row(children: [
                        SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white70,
                                value: ((t - 0.2) / 0.2).clamp(0.0, 1.0))),
                        const SizedBox(width: 8),
                        const Opacity(
                            opacity: 0.6,
                            child: Text('Koala çözüyor...',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600))),
                      ]),
                    if (t >= 0.4)
                      _Step(
                          num: '1',
                          text: '2x + 5 = 11\nHer iki taraftan 5 çıkar'),
                    if (t >= 0.55)
                      _Step(
                          num: '2',
                          text: '2x = 6\nHer iki tarafı 2\'ye böl'),
                    if (t >= 0.7)
                      _Step(num: '✔', text: 'x = 3', isFinal: true),
                    if (t >= 0.85)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E).withAlpha(30),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: const Color(0xFF22C55E).withAlpha(50)),
                          ),
                          child: const Row(children: [
                            Icon(Icons.lightbulb_rounded,
                                color: Color(0xFF22C55E), size: 18),
                            SizedBox(width: 8),
                            Text('Cevap: x = 3',
                                style: TextStyle(
                                    color: Color(0xFF22C55E),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900)),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.analyzing});
  final bool analyzing;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: analyzing
            ? const Color(0xFFFBBF24).withAlpha(30)
            : const Color(0xFF22C55E).withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: analyzing
                ? const Color(0xFFFBBF24).withAlpha(60)
                : const Color(0xFF22C55E).withAlpha(60)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (analyzing)
          const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: Color(0xFFFBBF24)))
        else
          const Icon(Icons.check_circle_rounded,
              size: 12, color: Color(0xFF22C55E)),
        const SizedBox(width: 4),
        Text(
          analyzing ? 'Analiz ediliyor...' : 'Çözüldü',
          style: TextStyle(
              color: analyzing
                  ? const Color(0xFFFBBF24)
                  : const Color(0xFF22C55E),
              fontSize: 10,
              fontWeight: FontWeight.w700),
        ),
      ]),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.num, required this.text, this.isFinal = false});
  final String num;
  final String text;
  final bool isFinal;
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (_, v, child) => Opacity(
          opacity: v.clamp(0.0, 1.0),
          child:
              Transform.translate(offset: Offset(0, 6 * (1 - v)), child: child)),
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isFinal
                ? const Color(0xFF22C55E).withAlpha(15)
                : Colors.white.withAlpha(8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isFinal
                    ? const Color(0xFF22C55E).withAlpha(30)
                    : Colors.white.withAlpha(8)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFinal
                      ? const Color(0xFF22C55E).withAlpha(40)
                      : Colors.white.withAlpha(15)),
              child: Center(
                  child: Text(num,
                      style: TextStyle(
                          color: isFinal
                              ? const Color(0xFF22C55E)
                              : Colors.white70,
                          fontSize: isFinal ? 13 : 10,
                          fontWeight: FontWeight.w800))),
            ),
            const SizedBox(width: 10),
            Flexible(
                child: Text(text,
                    style: TextStyle(
                        color: isFinal
                            ? const Color(0xFF22C55E)
                            : Colors.white70,
                        fontSize: 12,
                        fontWeight:
                            isFinal ? FontWeight.w700 : FontWeight.w500,
                        height: 1.4))),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
// DATA
// ═══════════════════════════════════════════

class _PD {
  _PD(this.title, this.body, this.c1, this.c2, this.t);
  final String title;
  final String body;
  final Color c1;
  final Color c2;
  final int t;
}
