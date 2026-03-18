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
    _PD('Merhaba,\nben Koala!', 'Hangi konuda takılırsan takıl, adım adım çözüm üretiyorum.', const Color(0xFF6265E8), const Color(0xFF5558DF), 0),
    _PD('Çek, gönder, anla', 'Sorunun fotoğrafını çek. Koala adım adım çözsün.', const Color(0xFF38BDF8), const Color(0xFF22D3EE), 1),
  ];

  @override
  void initState() { super.initState(); _entry = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..forward(); }
  @override
  void dispose() { _pc.dispose(); _entry.dispose(); super.dispose(); }

  void _next() { if (_idx >= _pages.length - 1) { _goSignup(); return; } _pc.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic); }

  Future<void> _goSignup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder<void>(pageBuilder: (_, a, __) => const SignupScreen(), transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: c), transitionDuration: const Duration(milliseconds: 300)));
  }

  @override
  Widget build(BuildContext context) {
    final pg = _pages[_idx];
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(fit: StackFit.expand, children: [
        AnimatedContainer(duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic,
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [pg.c1, pg.c2]))),
        SafeArea(child: FadeTransition(opacity: CurvedAnimation(parent: _entry, curve: Curves.easeOut),
          child: Column(children: [
            Expanded(child: PageView.builder(controller: _pc, itemCount: _pages.length, allowImplicitScrolling: true,
              onPageChanged: (i) { setState(() => _idx = i); if (i == 1) _page2Key.currentState?.restartAnimation(); },
              itemBuilder: (_, i) => i == 0 ? const _Page1() : _Page2(key: _page2Key))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 28),
              child: IndexedStack(index: _idx, alignment: Alignment.topCenter,
                children: _pages.map((p) => AnimatedOpacity(opacity: p == pg ? 1.0 : 0.0, duration: const Duration(milliseconds: 250),
                  child: Column(children: [
                    Text(p.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white, height: 1.18, letterSpacing: -0.8)),
                    const SizedBox(height: 12),
                    Text(p.body, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: Colors.white.withOpacity(0.72), height: 1.6, letterSpacing: 0.1))]))).toList())),
            const SizedBox(height: 28),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(_pages.length, (i) {
              final bool on = i == _idx;
              return AnimatedContainer(duration: const Duration(milliseconds: 250), margin: const EdgeInsets.symmetric(horizontal: 4), width: on ? 24 : 8, height: 8,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: on ? Colors.white : Colors.white.withOpacity(0.3)));
            })),
            const SizedBox(height: 32),
            Padding(padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
              child: SizedBox(width: double.infinity, height: 56,
                child: ElevatedButton(onPressed: _next, style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: pg.c1, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  child: Text(_idx == _pages.length - 1 ? 'Başla' : 'Devam', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))))),
          ]))),
      ]),
    );
  }
}

class _Page1 extends StatelessWidget {
  const _Page1();
  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final double innerCircleSize = screenW * 0.46;
    final double koalaSize = screenW * 0.74;
    final double stackSize = screenW * 0.80;
    return Column(children: [
      const Spacer(flex: 2),
      TweenAnimationBuilder<double>(tween: Tween(begin: 0.0, end: 1.0), duration: const Duration(milliseconds: 800), curve: Curves.easeOutBack,
        builder: (_, v, child) => Transform.scale(scale: 0.8 + 0.2 * v, child: Opacity(opacity: v.clamp(0.0, 1.0), child: child)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: stackSize, height: stackSize,
            child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
              Container(width: screenW * 0.66, height: screenW * 0.66, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.09), width: 1.5))),
              Container(width: innerCircleSize, height: innerCircleSize, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.06), border: Border.all(color: Colors.white.withOpacity(0.22), width: 1.5))),
              ClipPath(clipper: _KoalaClipper(koalaSize, innerCircleSize),
                child: SizedBox(width: koalaSize, height: koalaSize, child: Image.asset('assets/images/koala_hero.png', fit: BoxFit.contain))),
              Positioned(bottom: screenW * 0.10, right: screenW * 0.02,
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12, offset: const Offset(0, 4))]),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.auto_awesome, size: 16, color: Color(0xFF6265E8)), SizedBox(width: 6), Text('Koala', style: TextStyle(color: Color(0xFF6265E8), fontWeight: FontWeight.bold, fontSize: 14))]))),
            ])),
        ])),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: const [_FeatureChip(Icons.camera_alt, 'Foto ile soru çöz'), SizedBox(width: 10), _FeatureChip(Icons.route, 'Adım adım çözüm')]),
      const SizedBox(height: 10),
      const _FeatureChip(Icons.school, '9 branş'),
      const Spacer(flex: 2),
    ]);
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip(this.icon, this.label);
  final IconData icon; final String label;
  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(99), border: Border.all(color: Colors.white.withOpacity(0.13), width: 1.0)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: Colors.white.withOpacity(0.65)), const SizedBox(width: 7),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.70), fontSize: 12.5, fontWeight: FontWeight.w500, letterSpacing: 0.1))]));
  }
}

class _KoalaClipper extends CustomClipper<Path> {
  final double koalaSize, circleSize;
  _KoalaClipper(this.koalaSize, this.circleSize);
  @override
  Path getClip(Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = circleSize / 2;
    final topRect = Path()..addRect(Rect.fromLTRB(0, 0, size.width, size.height * 0.65));
    final circle = Path()..addOval(Rect.fromCircle(center: center, radius: r));
    return Path.combine(PathOperation.union, topRect, circle);
  }
  @override
  bool shouldReclip(covariant _KoalaClipper old) => old.koalaSize != koalaSize || old.circleSize != circleSize;
}

class _Page2 extends StatefulWidget {
  const _Page2({super.key});
  @override
  State<_Page2> createState() => _Page2State();
}

class _Page2State extends State<_Page2> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final AnimationController _anim;
  @override bool get wantKeepAlive => true;
  void restartAnimation() { _anim.reset(); _anim.repeat(); }
  @override void initState() { super.initState(); _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 14000))..repeat(); }
  @override void dispose() { _anim.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) { super.build(context);
    return Stack(children: [
      Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        child: Align(
          alignment: const Alignment(0, 0.25),
          child: RepaintBoundary(child: AnimatedBuilder(animation: _anim, builder: (context, _) {
            return _MiniAppDemo(t: _anim.value);
          })))),
      Positioned(top: 14, left: 24,
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white.withOpacity(0.20))),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.auto_awesome, size: 16, color: Colors.white), SizedBox(width: 6), Text('Koala', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14))]))),
    ]);
  }
}

class _MiniAppDemo extends StatelessWidget {
  const _MiniAppDemo({required this.t}); final double t;
  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.52;
    return Container(width: double.infinity, constraints: BoxConstraints(maxWidth: 340, maxHeight: maxH),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), color: const Color(0xFF0C1425), border: Border.all(color: const Color(0x30FFFFFF))),
      child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x10FFFFFF)))),
            child: Row(children: [Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF6366F1))), const SizedBox(width: 6),
              const Text('Koala Tutor', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0x60FFFFFF))), const Spacer(), _PhaseIndicator(t: t)])),
          Padding(padding: const EdgeInsets.all(10), child: _buildContent())])));
  }
  Widget _buildContent() { if (t < 0.20) return _CameraPhase(t: t); if (t < 0.35) return _AnalyzePhase(t: t); return _SolvePhase(t: t); }
}

class _PhaseIndicator extends StatelessWidget {
  const _PhaseIndicator({required this.t}); final double t;
  @override Widget build(BuildContext context) {
    final int phase = t < 0.20 ? 0 : (t < 0.35 ? 1 : 2);
    return Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) => Container(margin: const EdgeInsets.only(left: 3), width: i == phase ? 16 : 6, height: 3,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: i < phase ? const Color(0xFF22C55E) : i == phase ? Colors.white : const Color(0x20FFFFFF)))));
  }
}

class _CameraPhase extends StatelessWidget {
  const _CameraPhase({required this.t}); final double t;
  @override Widget build(BuildContext context) {
    final double nt = (t / 0.20).clamp(0.0, 1.0); final bool flash = t > 0.16 && t < 0.19;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(height: 150, width: double.infinity,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: flash ? Colors.white : const Color(0x15FFFFFF), width: flash ? 2 : 1.5), color: const Color(0x08FFFFFF)),
        child: Stack(children: [
          Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Opacity(opacity: (nt * 2).clamp(0.0, 1.0), child: const CustomPaint(painter: _NotebookPainter())))),
          ..._corners(),
          if (nt > 0.3 && nt < 0.85) Positioned(left: 8, right: 8, top: 10 + (125 * ((nt - 0.3) / 0.55)).clamp(0.0, 125.0), child: Container(height: 2, decoration: BoxDecoration(borderRadius: BorderRadius.circular(1), gradient: const LinearGradient(colors: [Color(0x0006B6D4), Color(0xAA06B6D4), Color(0x0006B6D4)])))),
          if (flash) Positioned.fill(child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0x40FFFFFF))))])),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(flash ? Icons.check_circle_rounded : Icons.camera_alt_rounded, size: 14, color: flash ? const Color(0xFF22C55E) : const Color(0x50FFFFFF)), const SizedBox(width: 5),
        Text(flash ? 'Soru algılandı!' : 'Soruyu çerçeveye al...', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: flash ? const Color(0xFF22C55E) : const Color(0x50FFFFFF)))])]);
  }
  List<Widget> _corners() { const c = Color(0xFF06B6D4); const l = 18.0; const w = 2.0; return [
    Positioned(left:6,top:6,child:Container(width:l,height:w,color:c)),Positioned(left:6,top:6,child:Container(width:w,height:l,color:c)),
    Positioned(right:6,top:6,child:Container(width:l,height:w,color:c)),Positioned(right:6,top:6,child:Container(width:w,height:l,color:c)),
    Positioned(left:6,bottom:6,child:Container(width:l,height:w,color:c)),Positioned(left:6,bottom:6,child:Container(width:w,height:l,color:c)),
    Positioned(right:6,bottom:6,child:Container(width:l,height:w,color:c)),Positioned(right:6,bottom:6,child:Container(width:w,height:l,color:c))]; }
}

class _NotebookPainter extends CustomPainter {
  const _NotebookPainter();
  @override void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = const Color(0xFFF8F6F0));
    final lp = Paint()..color = const Color(0x1A94A3B8)..strokeWidth = 0.8;
    for (double y = 28; y < size.height; y += 22) canvas.drawLine(Offset(0, y), Offset(size.width, y), lp);
    canvas.drawLine(Offset(36, 0), Offset(36, size.height), Paint()..color = const Color(0x30EF4444)..strokeWidth = 1);
    TextPainter(text: const TextSpan(text: 'Soru 5)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF475569), fontFamily: 'serif')), textDirection: TextDirection.ltr)..layout()..paint(canvas, const Offset(44, 32));
    TextPainter(text: const TextSpan(text: '2x + 5 = 11', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B), letterSpacing: 1.5)), textDirection: TextDirection.ltr)..layout()..paint(canvas, const Offset(44, 58));
    TextPainter(text: const TextSpan(text: 'x = ?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Color(0xFF6366F1), fontStyle: FontStyle.italic)), textDirection: TextDirection.ltr)..layout()..paint(canvas, const Offset(44, 92));
    canvas.drawLine(const Offset(44, 110), const Offset(80, 110), Paint()..color = const Color(0xFF6366F1)..strokeWidth = 1.5);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AnalyzePhase extends StatelessWidget {
  const _AnalyzePhase({required this.t}); final double t;
  @override Widget build(BuildContext context) {
    final double nt = ((t - 0.20) / 0.15).clamp(0.0, 1.0);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0x156366F1), border: Border.all(color: const Color(0x306366F1))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Icon(Icons.auto_awesome, size: 13, color: Color(0xFF818CF8)), SizedBox(width: 4), Text('Algılanan soru', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF818CF8)))]),
          const SizedBox(height: 6), const Text('2x + 5 = 11', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5))])),
      const SizedBox(height: 12),
      Row(children: [SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: const Color(0xFF06B6D4), value: nt)), const SizedBox(width: 8), const Text('Koala analiz ediyor...', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0x60FFFFFF)))]),
      const SizedBox(height: 8),
      Container(height: 3, width: double.infinity, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: const Color(0x15FFFFFF)),
        child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: nt, child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), gradient: const LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF6366F1)]))))),
      const SizedBox(height: 16),
      if (nt > 0.5) Row(children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: const Color(0x206366F1)), child: const Text('Matematik', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF818CF8)))),
        const SizedBox(width: 6),
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: const Color(0x2006B6D4)), child: const Text('1. Derece Denklem', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF06B6D4))))])]); }
}

class _SolvePhase extends StatelessWidget {
  const _SolvePhase({required this.t}); final double t;
  @override Widget build(BuildContext context) {
    final double nt = ((t - 0.35) / 0.65).clamp(0.0, 1.0);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: const Color(0x15FFFFFF), border: Border.all(color: const Color(0x12FFFFFF))),
        child: const Row(children: [Text('2x + 5 = 11', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xB0FFFFFF))), Spacer(), Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF4ADE80))])),
      const SizedBox(height: 6),
      if (nt > 0.0) _SolveStep(num: '1', title: 'Her iki taraftan 5 çıkar', math: '2x + 5 - 5 = 11 - 5', result: '2x = 6'),
      if (nt > 0.30) _SolveStep(num: '2', title: 'Her iki tarafı 2\'ye böl', math: '2x / 2 = 6 / 2', result: 'x = 3'),
      if (nt > 0.55) ...[const SizedBox(height: 6), Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0x3322C55E), border: Border.all(color: const Color(0x6022C55E))),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF4ADE80)), SizedBox(width: 8), Text('Cevap: x = 3', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF4ADE80)))]))]]); }
}

class _SolveStep extends StatelessWidget {
  const _SolveStep({required this.num, required this.title, required this.math, required this.result, this.isFinal = false});
  final String num, title, math, result; final bool isFinal;
  @override Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(tween: Tween(begin: 0.0, end: 1.0), duration: const Duration(milliseconds: 300), curve: Curves.easeOut,
      builder: (_, v, child) => Opacity(opacity: v.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, 8 * (1 - v)), child: child)),
      child: Padding(padding: const EdgeInsets.only(top: 5), child: Container(width: double.infinity, padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: isFinal ? const Color(0x2222C55E) : const Color(0x18FFFFFF), border: Border.all(color: isFinal ? const Color(0x4022C55E) : const Color(0x18FFFFFF))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 24, height: 24, decoration: BoxDecoration(shape: BoxShape.circle, color: isFinal ? const Color(0x4022C55E) : const Color(0x15FFFFFF)),
            child: Center(child: Text(num, style: TextStyle(fontSize: isFinal ? 13 : 11, fontWeight: FontWeight.w800, color: isFinal ? const Color(0xFF22C55E) : const Color(0x80FFFFFF))))),
          const SizedBox(width: 10),
          Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isFinal ? const Color(0xFF4ADE80) : const Color(0xAAFFFFFF))),
            const SizedBox(height: 2), Text(math, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isFinal ? const Color(0xBB4ADE80) : const Color(0x70FFFFFF))),
            if (result.isNotEmpty) ...[const SizedBox(height: 2), Text(result, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF22D3EE)))]]))]))));
  }
}

class _PD { _PD(this.title, this.body, this.c1, this.c2, this.t); final String title, body; final Color c1, c2; final int t; }
