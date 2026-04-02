#!/usr/bin/env python3
"""
Update hero section in home_screen.dart
- More vertical breathing room (Yandex AI style)
- Larger Koala icon
- Refined slogan typography
- Keep everything else exactly the same
"""
import os

BASE = r"C:\Users\canoz\Egitim-clean\koala"
path = os.path.join(BASE, "lib", "views", "home_screen.dart")

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# Find and replace ONLY the hero section
# ═══════════════════════════════════════════════════════════

OLD_HERO = r"""              // ── Hero ──
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 4),
                child: Column(children: [
                  Container(width: 48, height: 48,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: const Color(0xFFF0ECFF)),
                    child: const Icon(Icons.auto_awesome, size: 22, color: Color(0xFF6C5CE7))),
                  const SizedBox(height: 8),
                  const Text('koala', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A1D2A), letterSpacing: -0.6)),
                  const SizedBox(height: 2),
                  Text('tara. keşfet. tasarla.', style: TextStyle(fontSize: 12, color: Colors.grey.shade400, letterSpacing: 0.2)),
                  const SizedBox(height: 14),
                  FadeTransition(opacity: _chipFade, child: GestureDetector(
                    onTap: () => _go(_chips[_chipIdx][1]),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: const Color(0xFFF3F0FF)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(_chips[_chipIdx][0], style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 7),
                        Text(_chips[_chipIdx][1], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF4A4458))),
                      ])))),
                ]))"""

NEW_HERO = r"""              // ── Hero (Yandex AI style — breathable) ──
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
                  Text('tara.  keşfet.  tasarla.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: Colors.grey.shade400, letterSpacing: 1.2)),
                  const SizedBox(height: 28),
                  // Rotating hint chip
                  FadeTransition(opacity: _chipFade, child: GestureDetector(
                    onTap: () => _go(_chips[_chipIdx][1]),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        color: const Color(0xFFF3F0FF),
                        border: Border.all(color: const Color(0xFFEDEAF5), width: 0.5)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(_chips[_chipIdx][0], style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 8),
                        Text(_chips[_chipIdx][1], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF4A4458))),
                      ])))),
                ]))"""

if OLD_HERO in content:
    content = content.replace(OLD_HERO, NEW_HERO)
    print("  ✅ Hero section updated")
else:
    print("  ❌ Could not find hero section!")
    print("     Dumping first 200 chars around 'Hero' for debug...")
    idx = content.find('Hero')
    if idx > 0:
        print(content[idx-50:idx+200])

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print()
print("Changes:")
print("  📐 Top padding: 20px → 48px (more breathing room)")
print("  📐 Bottom padding: 4px → 32px")  
print("  🔲 Koala icon: 48×48 → 68×68, radius 14→20, subtle shadow")
print("  🔤 Brand name: 22px → 26px")
print("  🔤 Slogan: letter-spacing 0.2 → 1.2, more airy")
print("  📐 Gap before chip: 14px → 28px")
print("  🔲 Chip: subtle border added")
print()
print("Test: flutter run -d chrome")
