p = 'lib/views/onboarding_screen.dart'
with open(p, 'r', encoding='utf-8') as f:
    content = f.read()

# _Page2, _Page2State, _MiniAppDemo, _PhaseIndicator, _CameraPhase, _NotebookPainter,
# _AnalyzePhase, _SolvePhase, _SolveStep siniflarini tamamen degistir

old_start = "class _Page2 extends StatefulWidget {"
old_end = "class _PD { _PD(this.title, this.body, this.c1, this.c2, this.t); final String title, body; final Color c1, c2; final int t; }"

start_idx = content.index(old_start)
end_idx = content.index(old_end)

new_page2 = '''class _Page2 extends StatefulWidget {
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
  Widget build(BuildContext context) { super.build(context);
    return Stack(children: [
      Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        child: Align(
          alignment: const Alignment(0, 0.20),
          child: RepaintBoundary(child: AnimatedBuilder(animation: _anim, builder: (context, _) {
            return _RoomAnalysisDemo(t: _anim.value);
          })))),
      Positioned(top: 14, left: 24,
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white.withOpacity(0.20))),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.auto_awesome, size: 16, color: Colors.white), SizedBox(width: 6), Text('Koala', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14))]))),
    ]);
  }
}

class _RoomAnalysisDemo extends StatelessWidget {
  const _RoomAnalysisDemo({required this.t}); final double t;
  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.52;
    return Container(width: double.infinity, constraints: BoxConstraints(maxWidth: 340, maxHeight: maxH),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), color: const Color(0xFF0C1425), border: Border.all(color: const Color(0x30FFFFFF))),
      child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x10FFFFFF)))),
            child: Row(children: [Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF00B894))), const SizedBox(width: 6),
              const Text('Koala Analiz', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0x60FFFFFF))), const Spacer(), _DemoPhaseIndicator(t: t)])),
          Padding(padding: const EdgeInsets.all(10), child: _buildContent())])));
  }
  Widget _buildContent() {
    if (t < 0.18) return _ScanPhase(t: t);
    if (t < 0.32) return _DetectPhase(t: t);
    return _ResultPhase(t: t);
  }
}

class _DemoPhaseIndicator extends StatelessWidget {
  const _DemoPhaseIndicator({required this.t}); final double t;
  @override Widget build(BuildContext context) {
    final int phase = t < 0.18 ? 0 : (t < 0.32 ? 1 : 2);
    return Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) => Container(margin: const EdgeInsets.only(left: 3), width: i == phase ? 16 : 6, height: 3,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: i < phase ? const Color(0xFF00B894) : i == phase ? Colors.white : const Color(0x20FFFFFF)))));
  }
}

// Faz 1: Oda fotografinin taraniyor efekti
class _ScanPhase extends StatelessWidget {
  const _ScanPhase({required this.t}); final double t;
  @override Widget build(BuildContext context) {
    final double nt = (t / 0.18).clamp(0.0, 1.0);
    final bool flash = t > 0.15 && t < 0.18;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(height: 160, width: double.infinity,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: flash ? const Color(0xFF00B894) : const Color(0x15FFFFFF), width: flash ? 2 : 1.5), color: const Color(0x08FFFFFF)),
        child: Stack(children: [
          // Oda gorseli (basit cizim)
          Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Opacity(opacity: (nt * 2).clamp(0.0, 1.0), child: const CustomPaint(painter: _RoomPainter())))),
          // Tarama cizgisi
          if (nt > 0.2 && nt < 0.85) Positioned(left: 8, right: 8, top: 10 + (140 * ((nt - 0.2) / 0.65)).clamp(0.0, 140.0),
            child: Container(height: 2, decoration: BoxDecoration(borderRadius: BorderRadius.circular(1), gradient: const LinearGradient(colors: [Color(0x0000B894), Color(0xAA00B894), Color(0x0000B894)])))),
          // Flash efekti
          if (flash) Positioned.fill(child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0x2000B894)))),
          // Kose isaretleri
          ..._corners(),
        ])),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(flash ? Icons.check_circle_rounded : Icons.fullscreen_rounded, size: 14, color: flash ? const Color(0xFF00B894) : const Color(0x50FFFFFF)), const SizedBox(width: 5),
        Text(flash ? 'Mekan algilandi!' : 'Odani cercevele...', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: flash ? const Color(0xFF00B894) : const Color(0x50FFFFFF)))])]);
  }
  List<Widget> _corners() { const c = Color(0xFF00B894); const l = 18.0; const w = 2.0; return [
    Positioned(left:6,top:6,child:Container(width:l,height:w,color:c)),Positioned(left:6,top:6,child:Container(width:w,height:l,color:c)),
    Positioned(right:6,top:6,child:Container(width:l,height:w,color:c)),Positioned(right:6,top:6,child:Container(width:w,height:l,color:c)),
    Positioned(left:6,bottom:6,child:Container(width:l,height:w,color:c)),Positioned(left:6,bottom:6,child:Container(width:w,height:l,color:c)),
    Positioned(right:6,bottom:6,child:Container(width:l,height:w,color:c)),Positioned(right:6,bottom:6,child:Container(width:w,height:l,color:c))]; }
}

// Faz 2: Stil tespiti ve analiz
class _DetectPhase extends StatelessWidget {
  const _DetectPhase({required this.t}); final double t;
  @override Widget build(BuildContext context) {
    final double nt = ((t - 0.18) / 0.14).clamp(0.0, 1.0);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      // Stil karti
      Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0x1500B894), border: Border.all(color: const Color(0x3000B894))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Icon(Icons.auto_awesome, size: 13, color: Color(0xFF00B894)), SizedBox(width: 4), Text('Tespit edilen stil', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF00B894)))]),
          const SizedBox(height: 6),
          const Text('Modern Minimalist', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.3)),
          const SizedBox(height: 2),
          Text('%92 uyum', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5)))])),
      const SizedBox(height: 10),
      // Progress
      Row(children: [SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: const Color(0xFF00B894), value: nt)), const SizedBox(width: 8), const Text('Analiz ediliyor...', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0x60FFFFFF)))]),
      const SizedBox(height: 8),
      Container(height: 3, width: double.infinity, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: const Color(0x15FFFFFF)),
        child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: nt, child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), gradient: const LinearGradient(colors: [Color(0xFF00B894), Color(0xFF6C5CE7)]))))),
      const SizedBox(height: 14),
      // Renk paleti
      if (nt > 0.4) Row(children: [
        _ColorDot(color: const Color(0xFFE8E5E0)),
        const SizedBox(width: 4),
        _ColorDot(color: const Color(0xFF2C2C2C)),
        const SizedBox(width: 4),
        _ColorDot(color: const Color(0xFF8B7355)),
        const SizedBox(width: 4),
        _ColorDot(color: const Color(0xFFF5F0EB)),
        const SizedBox(width: 8),
        Text('Renk paleti', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.4)))]),
      if (nt > 0.7) ...[const SizedBox(height: 10),
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: const Color(0x2000B894)),
            child: const Text('Salon', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF00B894)))),
          const SizedBox(width: 6),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: const Color(0x206C5CE7)),
            child: const Text('20-25 m\\u00b2', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFA29BFE))))])]]);
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color}); final Color color;
  @override Widget build(BuildContext context) {
    return Container(width: 22, height: 22, decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: color, border: Border.all(color: Colors.white.withOpacity(0.15), width: 1)));
  }
}

// Faz 3: Sonuclar ve evlumba yonlendirme
class _ResultPhase extends StatelessWidget {
  const _ResultPhase({required this.t}); final double t;
  @override Widget build(BuildContext context) {
    final double nt = ((t - 0.32) / 0.68).clamp(0.0, 1.0);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      // Mini stil header
      Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: const Color(0x15FFFFFF), border: Border.all(color: const Color(0x12FFFFFF))),
        child: Row(children: [const Text('Modern Minimalist', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xB0FFFFFF))), const Spacer(), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: const Color(0x3000B894)), child: const Text('%92', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF00B894))))])),
      const SizedBox(height: 6),
      // Guclu yon
      if (nt > 0.0) _ResultCard(icon: Icons.check_circle_rounded, iconColor: const Color(0xFF00B894), bgColor: const Color(0x1500B894), borderColor: const Color(0x3000B894), title: 'Dogal isik kullanimi basarili', subtitle: 'Pencere yerlesimi ideal'),
      // Iyilestirme
      if (nt > 0.25) _ResultCard(icon: Icons.tips_and_updates_rounded, iconColor: const Color(0xFFFBBF24), bgColor: const Color(0x15FBBF24), borderColor: const Color(0x30FBBF24), title: 'Tekstil ve yastik ekle', subtitle: 'Sicaklik hissi artar'),
      // Ic mimar onerisi
      if (nt > 0.45) _ResultCard(icon: Icons.person_rounded, iconColor: const Color(0xFFA29BFE), bgColor: const Color(0x156C5CE7), borderColor: const Color(0x306C5CE7), title: '3 tasarimci eslesti', subtitle: 'Senin tarzina uygun'),
      // evlumba CTA
      if (nt > 0.65) ...[const SizedBox(height: 4), Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF8B5CF6)])),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.open_in_new_rounded, size: 14, color: Colors.white), const SizedBox(width: 6), const Text('evlumba\\'da kesfet', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white))]))]]);
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.icon, required this.iconColor, required this.bgColor, required this.borderColor, required this.title, required this.subtitle});
  final IconData icon; final Color iconColor, bgColor, borderColor; final String title, subtitle;
  @override Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(tween: Tween(begin: 0.0, end: 1.0), duration: const Duration(milliseconds: 300), curve: Curves.easeOut,
      builder: (_, v, child) => Opacity(opacity: v.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, 8 * (1 - v)), child: child)),
      child: Padding(padding: const EdgeInsets.only(top: 5), child: Container(width: double.infinity, padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: bgColor, border: Border.all(color: borderColor)),
        child: Row(children: [
          Icon(icon, size: 16, color: iconColor), const SizedBox(width: 10),
          Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: iconColor)),
            Text(subtitle, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.4)))]))])))); 
  }
}

// Oda cizimi (basit salon gorseli)
class _RoomPainter extends CustomPainter {
  const _RoomPainter();
  @override void paint(Canvas canvas, Size size) {
    // Duvar
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = const Color(0xFFF5F0EB));
    // Zemin
    canvas.drawRect(Rect.fromLTWH(0, size.height * 0.65, size.width, size.height * 0.35), Paint()..color = const Color(0xFFE8E0D5));
    // Zemin cizgisi
    canvas.drawLine(Offset(0, size.height * 0.65), Offset(size.width, size.height * 0.65), Paint()..color = const Color(0xFFD5CCC0)..strokeWidth = 1);
    // Pencere
    final wx = size.width * 0.55; final wy = size.height * 0.08;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(wx, wy, size.width * 0.35, size.height * 0.38), const Radius.circular(4)), Paint()..color = const Color(0xFFD6E8F0));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(wx, wy, size.width * 0.35, size.height * 0.38), const Radius.circular(4)), Paint()..color = const Color(0xFFB0C4CE)..style = PaintingStyle.stroke..strokeWidth = 2);
    canvas.drawLine(Offset(wx + size.width * 0.175, wy), Offset(wx + size.width * 0.175, wy + size.height * 0.38), Paint()..color = const Color(0xFFB0C4CE)..strokeWidth = 1.5);
    canvas.drawLine(Offset(wx, wy + size.height * 0.19), Offset(wx + size.width * 0.35, wy + size.height * 0.19), Paint()..color = const Color(0xFFB0C4CE)..strokeWidth = 1.5);
    // Koltuk (basit dikdortgen)
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.06, size.height * 0.45, size.width * 0.42, size.height * 0.22), const Radius.circular(6)), Paint()..color = const Color(0xFF8B7355));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.06, size.height * 0.38, size.width * 0.42, size.height * 0.12), const Radius.circular(6)), Paint()..color = const Color(0xFF9C8466));
    // Yastik
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.10, size.height * 0.40, size.width * 0.10, size.height * 0.08), const Radius.circular(4)), Paint()..color = const Color(0xFFD4A574));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.33, size.height * 0.40, size.width * 0.10, size.height * 0.08), const Radius.circular(4)), Paint()..color = const Color(0xFFBFA68E));
    // Sehpa
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.52, size.height * 0.52, size.width * 0.16, size.height * 0.14), const Radius.circular(3)), Paint()..color = const Color(0xFF2C2C2C));
    // Bitki
    final px = size.width * 0.80; final py = size.height * 0.28;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(px, size.height * 0.50, size.width * 0.08, size.height * 0.16), const Radius.circular(3)), Paint()..color = const Color(0xFFD4A574));
    canvas.drawCircle(Offset(px + size.width * 0.04, py + size.height * 0.06), 14, Paint()..color = const Color(0xFF4A8C5C));
    canvas.drawCircle(Offset(px + size.width * 0.07, py + size.height * 0.12), 10, Paint()..color = const Color(0xFF5AA06A));
    canvas.drawCircle(Offset(px + size.width * 0.01, py + size.height * 0.13), 11, Paint()..color = const Color(0xFF3D7A4E));
    // Tablo (duvarda)
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.12, size.height * 0.08, size.width * 0.28, size.height * 0.22), const Radius.circular(2)), Paint()..color = const Color(0xFFDDD5C8));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.12, size.height * 0.08, size.width * 0.28, size.height * 0.22), const Radius.circular(2)), Paint()..color = const Color(0xFFC5BDB0)..style = PaintingStyle.stroke..strokeWidth = 2);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

'''

content = content[:start_idx] + new_page2 + content[end_idx:]

with open(p, 'w', encoding='utf-8') as f:
    f.write(content)

print('Done - Page2 tamamen yeniden yazildi')
