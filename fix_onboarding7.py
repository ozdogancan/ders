# -*- coding: utf-8 -*-
p = 'lib/views/onboarding_screen.dart'
with open(p, 'r', encoding='utf-8') as f:
    content = f.read()

old_start = "class _Page2 extends StatefulWidget {"
old_end = "class _PD { _PD(this.title, this.body, this.c1, this.c2, this.t);"

s = content.index(old_start)
e = content.index(old_end)

new_code = r'''class _Page2 extends StatefulWidget {
  const _Page2({super.key});
  @override
  State<_Page2> createState() => _Page2State();
}

class _Page2State extends State<_Page2> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final AnimationController _anim;
  @override bool get wantKeepAlive => true;
  void restartAnimation() { _anim.reset(); _anim.repeat(); }
  @override void initState() { super.initState(); _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 16000))..repeat(); }
  @override void dispose() { _anim.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Stack(children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: Align(alignment: const Alignment(0, 0.15),
          child: RepaintBoundary(child: AnimatedBuilder(animation: _anim, builder: (context, _) {
            return _RoomDemo(t: _anim.value);
          })))),
      Positioned(top: 14, left: 24,
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white.withOpacity(0.20))),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.auto_awesome, size: 15, color: Colors.white), SizedBox(width: 6), Text('Koala', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))]))),
    ]);
  }
}

class _RoomDemo extends StatelessWidget {
  const _RoomDemo({required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.56;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxWidth: 350, maxHeight: maxH),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: const Color(0xFF0F1623),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 30, offset: const Offset(0, 10))]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.04)))),
              child: Row(children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF00B894))),
                const SizedBox(width: 7),
                Text('Koala Analiz', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.3), letterSpacing: 0.3)),
                const Spacer(),
                _PhaseChips(t: t),
              ])),
            // Body
            Padding(padding: const EdgeInsets.all(10), child: _buildPhase()),
          ]))));
  }

  Widget _buildPhase() {
    if (t < 0.15) return _ScanView(t: t);
    if (t < 0.28) return _AnalyzeView(t: t);
    return _ResultView(t: t);
  }
}

class _PhaseChips extends StatelessWidget {
  const _PhaseChips({required this.t});
  final double t;
  @override
  Widget build(BuildContext context) {
    final phase = t < 0.15 ? 0 : (t < 0.28 ? 1 : 2);
    final labels = ['Tara', 'Analiz', 'Ke\u015ffet'];
    return Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) {
      final done = i < phase;
      final active = i == phase;
      return Padding(padding: const EdgeInsets.only(left: 4),
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6),
            color: done ? const Color(0xFF00B894).withOpacity(0.2) : active ? Colors.white.withOpacity(0.08) : Colors.transparent),
          child: Text(labels[i], style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
            color: done ? const Color(0xFF00B894) : active ? Colors.white.withOpacity(0.7) : Colors.white.withOpacity(0.2)))));
    }));
  }
}

// ======= FAZ 1: TARAMA =======
class _ScanView extends StatelessWidget {
  const _ScanView({required this.t});
  final double t;
  @override
  Widget build(BuildContext context) {
    final nt = (t / 0.15).clamp(0.0, 1.0);
    final detected = t > 0.12;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(height: 160, width: double.infinity,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
          border: Border.all(color: detected ? const Color(0xFF00B894).withOpacity(0.5) : Colors.white.withOpacity(0.06), width: detected ? 1.5 : 1)),
        child: Stack(children: [
          Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(13),
            child: Opacity(opacity: (nt * 1.5).clamp(0.0, 1.0), child: const CustomPaint(painter: _RoomArt())))),
          // Tarama cizgisi
          if (!detected && nt > 0.1) Positioned(
            left: 8, right: 8,
            top: (150 * ((nt - 0.1) / 0.7)).clamp(0.0, 150.0),
            child: Container(height: 2, decoration: BoxDecoration(borderRadius: BorderRadius.circular(1),
              gradient: const LinearGradient(colors: [Color(0x0000B894), Color(0xBB00B894), Color(0x0000B894)])))),
          // Kose isaretleri
          ..._corners(detected),
          // Algilandi badge
          if (detected) Center(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: const Color(0xDD0F1623), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF00B894).withOpacity(0.3))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF00B894)),
              const SizedBox(width: 6),
              const Text('Mekan alg\u0131land\u0131!', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF00B894)))]))),
        ])),
      const SizedBox(height: 8),
      if (!detected) Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.fullscreen_rounded, size: 14, color: Colors.white.withOpacity(0.25)),
        const SizedBox(width: 5),
        Text('Odan\u0131 \u00e7er\u00e7evele...', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.25)))]),
    ]);
  }

  List<Widget> _corners(bool on) {
    final c = on ? const Color(0xFF00B894) : const Color(0xFF00B894).withOpacity(0.4);
    const l = 18.0; const w = 2.5; const m = 7.0;
    return [
      Positioned(left:m,top:m,child:Container(width:l,height:w,decoration:BoxDecoration(borderRadius:BorderRadius.circular(1),color:c))),
      Positioned(left:m,top:m,child:Container(width:w,height:l,decoration:BoxDecoration(borderRadius:BorderRadius.circular(1),color:c))),
      Positioned(right:m,top:m,child:Container(width:l,height:w,decoration:BoxDecoration(borderRadius:BorderRadius.circular(1),color:c))),
      Positioned(right:m,top:m,child:Container(width:w,height:l,decoration:BoxDecoration(borderRadius:BorderRadius.circular(1),color:c))),
      Positioned(left:m,bottom:m,child:Container(width:l,height:w,decoration:BoxDecoration(borderRadius:BorderRadius.circular(1),color:c))),
      Positioned(left:m,bottom:m,child:Container(width:w,height:l,decoration:BoxDecoration(borderRadius:BorderRadius.circular(1),color:c))),
      Positioned(right:m,bottom:m,child:Container(width:l,height:w,decoration:BoxDecoration(borderRadius:BorderRadius.circular(1),color:c))),
      Positioned(right:m,bottom:m,child:Container(width:w,height:l,decoration:BoxDecoration(borderRadius:BorderRadius.circular(1),color:c))),
    ];
  }
}

// ======= FAZ 2: ANALIZ =======
class _AnalyzeView extends StatelessWidget {
  const _AnalyzeView({required this.t});
  final double t;
  @override
  Widget build(BuildContext context) {
    final nt = ((t - 0.15) / 0.13).clamp(0.0, 1.0);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      // Stil karti
      Container(width: double.infinity, padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [const Color(0xFF00B894).withOpacity(0.12), const Color(0xFF00B894).withOpacity(0.04)]),
          border: Border.all(color: const Color(0xFF00B894).withOpacity(0.15))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome, size: 13, color: Color(0xFF00B894)),
            const SizedBox(width: 6),
            Text('ST\u0130L ANAL\u0130Z\u0130', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF00B894).withOpacity(0.8), letterSpacing: 0.8)),
            const Spacer(),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: const Color(0xFF00B894).withOpacity(0.2)),
              child: const Text('%92', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF00B894))))]),
          const SizedBox(height: 8),
          const Text('Modern Minimalist', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.3)),
          const SizedBox(height: 3),
          Text('Sakin ve ferah bir atmosfer', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4)))])),
      const SizedBox(height: 10),
      // Renk paleti
      if (nt > 0.25) Container(padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.white.withOpacity(0.03), border: Border.all(color: Colors.white.withOpacity(0.05))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Renk paleti', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.25), letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Row(children: const [
            _Swatch(color: Color(0xFFE8E5E0), name: 'Krem'),
            SizedBox(width: 5),
            _Swatch(color: Color(0xFF2C2C2C), name: 'Antrasit'),
            SizedBox(width: 5),
            _Swatch(color: Color(0xFF8B7355), name: 'Hardal'),
            SizedBox(width: 5),
            _Swatch(color: Color(0xFFF5F0EB), name: 'Bej'),
          ])])),
      const SizedBox(height: 10),
      // Progress
      Row(children: [
        SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: const Color(0xFF00B894), value: nt)),
        const SizedBox(width: 8),
        Text('Detayl\u0131 analiz haz\u0131rlan\u0131yor...', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.3)))]),
      const SizedBox(height: 6),
      ClipRRect(borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(value: nt, minHeight: 3, backgroundColor: Colors.white.withOpacity(0.05),
          valueColor: const AlwaysStoppedAnimation(Color(0xFF00B894)))),
      if (nt > 0.55) ...[const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _Tag('Salon'), _Tag('20-25 m\u00b2'), _Tag('N\u00f6tr tonlar')])],
    ]);
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.name});
  final Color color; final String name;
  @override Widget build(BuildContext context) {
    return Expanded(child: Column(children: [
      Container(height: 26, decoration: BoxDecoration(borderRadius: BorderRadius.circular(7), color: color, border: Border.all(color: Colors.white.withOpacity(0.08)))),
      const SizedBox(height: 4),
      Text(name, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.3)))]));
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);
  final String label;
  @override Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(7), color: Colors.white.withOpacity(0.05), border: Border.all(color: Colors.white.withOpacity(0.07))),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.45))));
  }
}

// ======= FAZ 3: SONUCLAR =======
class _ResultView extends StatelessWidget {
  const _ResultView({required this.t});
  final double t;
  @override
  Widget build(BuildContext context) {
    final nt = ((t - 0.28) / 0.72).clamp(0.0, 1.0);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      // Mini header
      Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(11), color: Colors.white.withOpacity(0.04), border: Border.all(color: Colors.white.withOpacity(0.05))),
        child: Row(children: [
          const Text('Modern Minimalist', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xAAFFFFFF), letterSpacing: -0.2)),
          const Spacer(),
          Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: const Color(0xFF00B894).withOpacity(0.2)),
            child: const Text('%92', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF00B894))))])),
      const SizedBox(height: 6),
      // Urun onerisi
      if (nt > 0.0) _ResCard(
        delay: 0, icon: Icons.weekend_rounded, iconColor: const Color(0xFF00B894),
        bg: const Color(0xFF00B894).withOpacity(0.07), border: const Color(0xFF00B894).withOpacity(0.12),
        title: 'Sehpa \u00f6nerisi', sub: 'Bu koltu\u011fa ah\u015fap sehpa yak\u0131\u015f\u0131r',
        trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: const Color(0xFF00B894).withOpacity(0.15)),
          child: Text('\u00dcR\u00dcN', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: const Color(0xFF00B894).withOpacity(0.8))))),
      // Tasarimci eslesmesi
      if (nt > 0.22) _ResCard(
        delay: 1, icon: Icons.people_alt_rounded, iconColor: const Color(0xFFA29BFE),
        bg: const Color(0xFF6C5CE7).withOpacity(0.07), border: const Color(0xFF6C5CE7).withOpacity(0.12),
        title: '3 tasar\u0131mc\u0131 e\u015fle\u015fti', sub: 'Minimalist uzman\u0131 i\u00e7 mimarlar',
        trailing: SizedBox(width: 52, height: 22, child: Stack(children: [
          Positioned(left: 0, child: _Avatar('S', const Color(0xFF6C5CE7))),
          Positioned(left: 14, child: _Avatar('A', const Color(0xFF00B894))),
          Positioned(left: 28, child: _Avatar('M', const Color(0xFF38BDF8)))]))),
      // Duvar rengi
      if (nt > 0.40) _ResCard(
        delay: 2, icon: Icons.format_paint_rounded, iconColor: const Color(0xFF38BDF8),
        bg: const Color(0xFF38BDF8).withOpacity(0.07), border: const Color(0xFF38BDF8).withOpacity(0.12),
        title: 'Duvar rengi \u00f6nerisi', sub: 'Warm beige tonu daha s\u0131cak yapar',
        trailing: Container(width: 22, height: 22, decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: const Color(0xFFD4A574), border: Border.all(color: Colors.white.withOpacity(0.12))))),
      // evlumba CTA
      if (nt > 0.60) ...[const SizedBox(height: 4),
        TweenAnimationBuilder<double>(tween: Tween(begin: 0.0, end: 1.0), duration: const Duration(milliseconds: 400), curve: Curves.easeOut,
          builder: (_, v, child) => Opacity(opacity: v.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, 8 * (1 - v)), child: child)),
          child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(13),
              gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF8B5CF6)]),
              boxShadow: [BoxShadow(color: const Color(0xFF6C5CE7).withOpacity(0.25), blurRadius: 12, offset: const Offset(0, 4))]),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.open_in_new_rounded, size: 14, color: Colors.white.withOpacity(0.9)),
              const SizedBox(width: 7),
              const Text("evlumba'da ke\u015ffet", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.2))])))],
    ]);
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.letter, this.color);
  final String letter; final Color color;
  @override Widget build(BuildContext context) {
    return Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, color: color, border: Border.all(color: const Color(0xFF0F1623), width: 2)),
      child: Center(child: Text(letter, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white))));
  }
}

class _ResCard extends StatelessWidget {
  const _ResCard({required this.delay, required this.icon, required this.iconColor, required this.bg, required this.border, required this.title, required this.sub, this.trailing});
  final int delay; final IconData icon; final Color iconColor, bg, border; final String title, sub; final Widget? trailing;
  @override Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(tween: Tween(begin: 0.0, end: 1.0), duration: const Duration(milliseconds: 350), curve: Curves.easeOut,
      builder: (_, v, child) => Opacity(opacity: v.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, 10 * (1 - v)), child: child)),
      child: Padding(padding: const EdgeInsets.only(top: 5),
        child: Container(width: double.infinity, padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(13), color: bg, border: Border.all(color: border)),
          child: Row(children: [
            Container(width: 30, height: 30, decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), color: iconColor.withOpacity(0.15)),
              child: Icon(icon, size: 16, color: iconColor)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xCCFFFFFF))),
              const SizedBox(height: 1),
              Text(sub, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.3)))])),
            if (trailing != null) trailing!,
          ]))));
  }
}

// ======= ODA CIZIMI =======
class _RoomArt extends CustomPainter {
  const _RoomArt();
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;
    // Duvar
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFFF5F0EB));
    // Zemin
    final fy = h * 0.62;
    canvas.drawRect(Rect.fromLTWH(0, fy, w, h - fy), Paint()..color = const Color(0xFFE8DFD3));
    canvas.drawLine(Offset(0, fy), Offset(w, fy), Paint()..color = const Color(0xFFD5C9BC)..strokeWidth = 1.2);
    // Zemin desen (ahsap cizgiler)
    final fp = Paint()..color = const Color(0xFFDDD4C6)..strokeWidth = 0.5;
    for (double y = fy + 12; y < h; y += 12) { canvas.drawLine(Offset(0, y), Offset(w, y), fp); }
    // Pencere
    final wx = w * 0.58; final wy = h * 0.06; final ww = w * 0.34; final wh = h * 0.36;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(wx, wy, ww, wh), const Radius.circular(3)), Paint()..color = const Color(0xFFCDE4F0));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(wx, wy, ww, wh), const Radius.circular(3)), Paint()..color = const Color(0xFFAFC4CE)..style = PaintingStyle.stroke..strokeWidth = 2);
    canvas.drawLine(Offset(wx + ww / 2, wy), Offset(wx + ww / 2, wy + wh), Paint()..color = const Color(0xFFAFC4CE)..strokeWidth = 1.2);
    canvas.drawLine(Offset(wx, wy + wh / 2), Offset(wx + ww, wy + wh / 2), Paint()..color = const Color(0xFFAFC4CE)..strokeWidth = 1.2);
    // Pencere isik
    canvas.drawRect(Rect.fromLTWH(wx + 3, wy + 3, ww / 2 - 5, wh / 2 - 5), Paint()..color = const Color(0x18FFFFFF));
    // Perde (sol)
    final pp = Paint()..color = const Color(0xFFE8E2D8)..style = PaintingStyle.fill;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(wx - 6, wy - 2, 10, wh + 6), const Radius.circular(2)), pp);
    // Perde (sag)
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(wx + ww - 4, wy - 2, 10, wh + 6), const Radius.circular(2)), pp);
    // Koltuk govde
    final cx = w * 0.05; final cy = h * 0.42;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx, cy + h * 0.07, w * 0.44, h * 0.17), const Radius.circular(8)), Paint()..color = const Color(0xFF8B7355));
    // Koltuk arkalik
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx, cy - h * 0.02, w * 0.44, h * 0.12), const Radius.circular(8)), Paint()..color = const Color(0xFF9C8466));
    // Koltuk kol (sol)
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 2, cy + h * 0.02, w * 0.05, h * 0.20), const Radius.circular(6)), Paint()..color = const Color(0xFF7D6648));
    // Koltuk kol (sag)
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx + w * 0.41, cy + h * 0.02, w * 0.05, h * 0.20), const Radius.circular(6)), Paint()..color = const Color(0xFF7D6648));
    // Yastiklar
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx + w * 0.05, cy + h * 0.0, w * 0.10, h * 0.08), const Radius.circular(5)), Paint()..color = const Color(0xFFD4A574));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx + w * 0.29, cy + h * 0.0, w * 0.10, h * 0.08), const Radius.circular(5)), Paint()..color = const Color(0xFFBFA68E));
    // Orta yastik (farkli renk)
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx + w * 0.16, cy + h * 0.01, w * 0.11, h * 0.07), const Radius.circular(5)), Paint()..color = const Color(0xFF00B894).withOpacity(0.6));
    // Sehpa
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.53, h * 0.51, w * 0.16, h * 0.13), const Radius.circular(4)), Paint()..color = const Color(0xFF2C2C2C));
    // Sehpa ayak golge
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.55, h * 0.635, w * 0.12, h * 0.015), const Radius.circular(2)), Paint()..color = const Color(0x15000000));
    // Sehpa ustu objeler
    canvas.drawCircle(Offset(w * 0.58, h * 0.49), 4, Paint()..color = const Color(0xFFE8C87A)); // mum
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.62, h * 0.485, 10, 7), const Radius.circular(2)), Paint()..color = const Color(0xFF00B894)); // kitap
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.635, h * 0.478, 8, 6), const Radius.circular(2)), Paint()..color = const Color(0xFF6C5CE7).withOpacity(0.7)); // kitap2
    // Bitki
    final px = w * 0.80;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(px - 4, h * 0.48, w * 0.11, h * 0.16), const Radius.circular(5)), Paint()..color = const Color(0xFFD4A574));
    canvas.drawCircle(Offset(px + w * 0.03, h * 0.32), 16, Paint()..color = const Color(0xFF4A8C5C));
    canvas.drawCircle(Offset(px + w * 0.08, h * 0.36), 12, Paint()..color = const Color(0xFF5AA06A));
    canvas.drawCircle(Offset(px - 3, h * 0.37), 13, Paint()..color = const Color(0xFF3D7A4E));
    canvas.drawCircle(Offset(px + w * 0.04, h * 0.28), 10, Paint()..color = const Color(0xFF5EA866));
    // Saksı golge
    canvas.drawOval(Rect.fromCenter(center: Offset(px + w * 0.015, h * 0.645), width: w * 0.13, height: h * 0.015), Paint()..color = const Color(0x10000000));
    // Duvarda tablo
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.14, h * 0.06, w * 0.26, h * 0.22), const Radius.circular(3)), Paint()..color = const Color(0xFFE2D9CC));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.14, h * 0.06, w * 0.26, h * 0.22), const Radius.circular(3)), Paint()..color = const Color(0xFFC8BFB0)..style = PaintingStyle.stroke..strokeWidth = 1.8);
    // Tablo icinde soyut desen
    canvas.drawCircle(Offset(w * 0.22, h * 0.13), 9, Paint()..color = const Color(0xFFBFAF98));
    canvas.drawCircle(Offset(w * 0.31, h * 0.17), 7, Paint()..color = const Color(0xFFD4C4AD));
    canvas.drawLine(Offset(w * 0.18, h * 0.20), Offset(w * 0.35, h * 0.12), Paint()..color = const Color(0xFFC5B8A5)..strokeWidth = 1.5);
    // Koltuk golge
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + w * 0.22, h * 0.665), width: w * 0.46, height: h * 0.018), Paint()..color = const Color(0x10000000));
    // Hali (koltuk onunde)
    final haliBounds = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.10, h * 0.68, w * 0.52, h * 0.10), const Radius.circular(4));
    canvas.drawRRect(haliBounds, Paint()..color = const Color(0xFFD4C4AD).withOpacity(0.5));
    canvas.drawRRect(haliBounds, Paint()..color = const Color(0xFFC5B5A0)..style = PaintingStyle.stroke..strokeWidth = 0.8);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

'''

content = content[:s] + new_code + content[e:]

with open(p, 'w', encoding='utf-8') as f:
    f.write(content)

print('Done - Page2 yeniden yazildi')
