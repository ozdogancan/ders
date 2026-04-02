p = 'lib/views/onboarding_screen.dart'
with open(p, 'r', encoding='utf-8') as f:
    content = f.read()

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
              Container(width: screenW * 0.66, height: screenW * 0.66, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.09), width: 1.5))),
              Container(width: innerCircleSize, height: innerCircleSize, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.06), border: Border.all(color: Colors.white.withOpacity(0.22), width: 1.5))),
              ClipPath(clipper: _KoalaClipper(koalaSize, innerCircleSize),
                child: SizedBox(width: koalaSize, height: koalaSize, child: Image.asset('assets/images/koala_hero.png', fit: BoxFit.contain))),
              Positioned(bottom: screenW * 0.10, right: screenW * 0.02,
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12, offset: const Offset(0, 4))]),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.auto_awesome, size: 16, color: Color(0xFF6C5CE7)), SizedBox(width: 6), Text('Koala', style: TextStyle(color: Color(0xFF6C5CE7), fontWeight: FontWeight.bold, fontSize: 14))]))),
            ])),
        ])),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
        _FeatureChip(Icons.camera_alt_rounded, 'Foto ile analiz'),
        SizedBox(width: 10),
        _FeatureChip(Icons.palette_rounded, 'Stil tespiti'),
      ]),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
        _FeatureChip(Icons.home_rounded, 'Mekan analizi'),
        SizedBox(width: 10),
        _FeatureChip(Icons.people_rounded, 'Tasarimci bul'),
      ]),
      const Spacer(flex: 2),
    ]);
  }
}

'''

content = content[:s] + new_page1 + content[e:]

with open(p, 'w', encoding='utf-8') as f:
    f.write(content)

print('Done - Page1 temizlendi, 4 chip 2x2 grid')
