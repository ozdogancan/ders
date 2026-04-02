#!/usr/bin/env python3
"""
Update hero section with custom Koala face SVG logo.
Reference: line-art koala face, purple strokes on light purple rounded rect bg.
Bold rounded 'koala' text underneath.
"""
import os

BASE = r"C:\Users\canoz\Egitim-clean\koala"
path = os.path.join(BASE, "lib", "views", "home_screen.dart")

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# Replace hero section with new SVG koala logo
# ═══════════════════════════════════════════════════════════

OLD_HERO = r"""              // ── Hero (Yandex AI style — breathable) ──
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.only(top: 48, bottom: 32),
                child: Column(children: [
                  // Larger Koala icon with subtle shadow
                  Container(width: 68, height: 68,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: const Color(0xFFF0ECFF),
                      boxShadow: [BoxShadow(color: const Color(0xFF6C5CE7).withOpacity(0.08), blurRadius: 24, offset: const Offset(0, 8))]),
                    child: const Icon(Icons.auto_awesome, size: 30, color: Color(0xFF6C5CE7))),
                  const SizedBox(height: 14),
                  // Brand name — slightly larger
                  const Text('koala', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1A1D2A), letterSpacing: -0.8)),
                  const SizedBox(height: 6),
                  // Refined slogan — lighter, more spaced
                  Text('tara.  keşfet.  tasarla.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: Colors.grey.shade400, letterSpacing: 1.2)),"""

NEW_HERO = r"""              // ── Hero — Custom Koala Logo ──
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.only(top: 48, bottom: 32),
                child: Column(children: [
                  // Koala face SVG in rounded container
                  Container(width: 80, height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      color: const Color(0xFFEDE9FE),
                      boxShadow: [BoxShadow(color: const Color(0xFF6C5CE7).withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 6))]),
                    child: Center(child: CustomPaint(size: const Size(50, 50), painter: _KoalaLogoPainter()))),
                  const SizedBox(height: 16),
                  // Brand name — bold, rounded
                  const Text('koala', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF1A1D2A), letterSpacing: -1.0)),
                  const SizedBox(height: 6),
                  // Slogan
                  Text('tara.  keşfet.  tasarla.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: Colors.grey.shade400, letterSpacing: 1.2)),"""

if OLD_HERO in content:
    content = content.replace(OLD_HERO, NEW_HERO)
    print("  ✅ Hero section updated with Koala SVG logo")
else:
    print("  ❌ Could not find hero section (trying original version)...")
    # Try the original pre-yandex hero
    OLD_HERO_ORIG = r"""              // ── Hero ──
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 4),
                child: Column(children: [
                  Container(width: 48, height: 48,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: const Color(0xFFF0ECFF)),
                    child: const Icon(Icons.auto_awesome, size: 22, color: Color(0xFF6C5CE7))),
                  const SizedBox(height: 8),
                  const Text('koala', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A1D2A), letterSpacing: -0.6)),
                  const SizedBox(height: 2),
                  Text('tara. keşfet. tasarla.', style: TextStyle(fontSize: 12, color: Colors.grey.shade400, letterSpacing: 0.2)),"""

    NEW_HERO_ORIG = r"""              // ── Hero — Custom Koala Logo ──
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.only(top: 48, bottom: 32),
                child: Column(children: [
                  // Koala face SVG in rounded container
                  Container(width: 80, height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      color: const Color(0xFFEDE9FE),
                      boxShadow: [BoxShadow(color: const Color(0xFF6C5CE7).withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 6))]),
                    child: Center(child: CustomPaint(size: const Size(50, 50), painter: _KoalaLogoPainter()))),
                  const SizedBox(height: 16),
                  // Brand name — bold, rounded
                  const Text('koala', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF1A1D2A), letterSpacing: -1.0)),
                  const SizedBox(height: 6),
                  // Slogan
                  Text('tara.  keşfet.  tasarla.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: Colors.grey.shade400, letterSpacing: 1.2)),"""

    if OLD_HERO_ORIG in content:
        content = content.replace(OLD_HERO_ORIG, NEW_HERO_ORIG)
        print("  ✅ Hero section updated (original version match)")
    else:
        print("  ❌ Neither version found. Manual edit needed.")

# ═══════════════════════════════════════════════════════════
# Add the KoalaLogoPainter class before the card widgets
# ═══════════════════════════════════════════════════════════

KOALA_PAINTER = r'''
// ═══════════════════════════════════════════════════════════
// KOALA LOGO PAINTER — Line-art koala face
// ═══════════════════════════════════════════════════════════

class _KoalaLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    final stroke = Paint()
      ..color = const Color(0xFF534AB7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fill = Paint()
      ..color = const Color(0xFF534AB7)
      ..style = PaintingStyle.fill;

    final fillLight = Paint()
      ..color = const Color(0xFFDDD6FE)
      ..style = PaintingStyle.fill;

    // ── Left ear (outer) ──
    canvas.drawCircle(Offset(cx - w * 0.30, h * 0.22), w * 0.20, stroke);

    // ── Right ear (outer) ──
    canvas.drawCircle(Offset(cx + w * 0.30, h * 0.22), w * 0.20, stroke);

    // ── Left ear (inner fill) ──
    canvas.drawCircle(Offset(cx - w * 0.30, h * 0.22), w * 0.12, fill);

    // ── Right ear (inner fill) ──
    canvas.drawCircle(Offset(cx + w * 0.30, h * 0.22), w * 0.12, fill);

    // ── Head (main circle) ──
    canvas.drawCircle(Offset(cx, h * 0.50), w * 0.36, stroke);

    // ── Left eye ──
    canvas.drawCircle(Offset(cx - w * 0.12, h * 0.44), w * 0.04, fill);

    // ── Right eye ──
    canvas.drawCircle(Offset(cx + w * 0.12, h * 0.44), w * 0.04, fill);

    // ── Nose (oval, filled) ──
    canvas.save();
    canvas.translate(cx, h * 0.56);
    canvas.scale(1.0, 0.7);
    canvas.drawCircle(Offset.zero, w * 0.08, fill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
'''

# Insert before "// CARD WIDGETS" or at the end of the file
INSERT_MARKER = "// ═══════════════════════════════════════════════════════════\n// CARD WIDGETS"
ALT_MARKER = "const _R = 18.0;"

if INSERT_MARKER in content:
    content = content.replace(INSERT_MARKER, KOALA_PAINTER + "\n" + INSERT_MARKER)
    print("  ✅ KoalaLogoPainter added before CARD WIDGETS")
elif ALT_MARKER in content:
    content = content.replace(ALT_MARKER, KOALA_PAINTER + "\n" + ALT_MARKER)
    print("  ✅ KoalaLogoPainter added before _R constant")
else:
    # Just append before last line
    content = content.rstrip() + "\n" + KOALA_PAINTER
    print("  ✅ KoalaLogoPainter appended at end")

# ═══════════════════════════════════════════════════════════
# Make sure dart:ui is imported (needed for Canvas)
# ═══════════════════════════════════════════════════════════
if "import 'dart:ui'" not in content and "import 'dart:ui'" not in content:
    # dart:ui is auto-imported via flutter/material.dart, no extra import needed
    pass

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print()
print("Changes:")
print("  🐨 Custom Koala face logo (line-art, purple strokes)")
print("  🟣 Ears: outer circle stroke + inner filled circle")
print("  ⭕ Head: main circle with stroke")
print("  👀 Eyes: two small filled dots")
print("  👃 Nose: filled oval")
print("  📦 Container: 80×80, EDE9FE bg, radius 22, subtle shadow")
print("  🔤 'koala' text: 28px, w800, -1.0 letter spacing")
print()
print("Test: flutter run -d chrome")
