p = 'lib/views/onboarding_screen.dart'
with open(p, 'r', encoding='utf-8') as f:
    content = f.read()

# _Page1'i tamamen degistir
old_page1_start = "class _Page1 extends StatelessWidget {"
old_page1_end = "class _FeatureChip extends StatelessWidget {"

s = content.index(old_page1_start)
e = content.index(old_page1_end)

new_page1 = '''class _Page1 extends StatelessWidget {
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
              // Dis daire
              Container(width: screenW * 0.66, height: screenW * 0.66, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.09), width: 1.5))),
              // Ic daire
              Container(width: innerCircleSize, height: innerCircleSize, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.06), border: Border.all(color: Colors.white.withOpacity(0.22), width: 1.5))),
              // Koala
              ClipPath(clipper: _KoalaClipper(koalaSize, innerCircleSize),
                child: SizedBox(width: koalaSize, height: koalaSize, child: Image.asset('assets/images/koala_hero.png', fit: BoxFit.contain))),
              // Ev ikonu (sol ust)
              Positioned(top: screenW * 0.02, left: screenW * 0.08,
                child: TweenAnimationBuilder<double>(tween: Tween(begin: 0.0, end: 1.0), duration: const Duration(milliseconds: 600), curve: Curves.easeOut,
                  builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 8 * (1 - v)), child: child)),
                  child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.18))),
                    child: Icon(Icons.home_rounded, size: 18, color: Colors.white.withOpacity(0.7))))),
              // Renk paleti ikonu (sag ust)
              Positioned(top: screenW * 0.06, right: screenW * 0.06,
                child: TweenAnimationBuilder<double>(tween: Tween(begin: 0.0, end: 1.0), duration: const Duration(milliseconds: 700), curve: Curves.easeOut,
                  builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 8 * (1 - v)), child: child)),
                  child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.18))),
                    child: Icon(Icons.palette_rounded, size: 18, color: Colors.white.withOpacity(0.7))))),
              // Kamera ikonu (sol alt)
              Positioned(bottom: screenW * 0.14, left: screenW * 0.02,
                child: TweenAnimationBuilder<double>(tween: Tween(begin: 0.0, end: 1.0), duration: const Duration(milliseconds: 800), curve: Curves.easeOut,
                  builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 8 * (1 - v)), child: child)),
                  child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.18))),
                    child: Icon(Icons.camera_alt_rounded, size: 18, color: Colors.white.withOpacity(0.7))))),
              // Renk ornekleri (sol alt kosede)
              Positioned(bottom: screenW * 0.06, left: screenW * 0.18,
                child: TweenAnimationBuilder<double>(tween: Tween(begin: 0.0, end: 1.0), duration: const Duration(milliseconds: 900), curve: Curves.easeOut,
                  builder: (_, v, child) => Opacity(opacity: v, child: Transform.scale(scale: 0.7 + 0.3 * v, child: child)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 14, height: 14, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: const Color(0xFFE8E5E0), border: Border.all(color: Colors.white.withOpacity(0.3)))),
                    const SizedBox(width: 3),
                    Container(width: 14, height: 14, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: const Color(0xFF8B7355), border: Border.all(color: Colors.white.withOpacity(0.3)))),
                    const SizedBox(width: 3),
                    Container(width: 14, height: 14, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: const Color(0xFF2C2C2C), border: Border.all(color: Colors.white.withOpacity(0.3)))),
                  ]))),
              // Koala badge (sag alt)
              Positioned(bottom: screenW * 0.10, right: screenW * 0.02,
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12, offset: const Offset(0, 4))]),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF00B894))),
                    const SizedBox(width: 6),
                    const Text('AI Analiz', style: TextStyle(color: Color(0xFF6C5CE7), fontWeight: FontWeight.bold, fontSize: 13))]))),
              // Stil badge (sag ust kose)
              Positioned(top: screenW * 0.20, right: screenW * 0.0,
                child: TweenAnimationBuilder<double>(tween: Tween(begin: 0.0, end: 1.0), duration: const Duration(milliseconds: 1000), curve: Curves.easeOut,
                  builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(12 * (1 - v), 0), child: child)),
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: const Color(0xFF00B894).withOpacity(0.2), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF00B894).withOpacity(0.3))),
                    child: const Text('Minimalist', style: TextStyle(color: Color(0xFF00B894), fontSize: 11, fontWeight: FontWeight.w700))))),
            ])),
        ])),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: const [_FeatureChip(Icons.camera_alt, 'Foto ile analiz'), SizedBox(width: 10), _FeatureChip(Icons.home_rounded, 'Stil tespiti')]),
      const SizedBox(height: 10),
      const _FeatureChip(Icons.people_rounded, 'Tasarimci eslestir'),
      const Spacer(flex: 2),
    ]);
  }
}

'''

content = content[:s] + new_page1 + content[e:]

with open(p, 'w', encoding='utf-8') as f:
    f.write(content)

print('Done - Page1 ic mekan elementleri eklendi')
