#!/usr/bin/env python3
"""
Fix: Chip emojis show broken/black on first load in Flutter web.
Solution: Replace emojis with Material Icons (instant load, no font dependency).
"""
import os

BASE = r"C:\Users\canoz\Egitim-clean\koala"
path = os.path.join(BASE, "lib", "views", "home_screen.dart")

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# ═══════════════════════════════════════════════════════════
# Replace emoji-based chips with icon-based chips
# ═══════════════════════════════════════════════════════════

OLD_CHIPS = r"""  static const _chips = [
    ['\u{1F3E0}', 'odamı yeniden tasarla'],
    ['\u{1F3A8}', 'duvar rengi öner'],
    ['\u{1F6CB}\u{FE0F}', 'bu dolaba ne yakışır?'],
    ['\u{1F4A1}', 'bütçeye uygun dekorasyon'],
  ];"""

NEW_CHIPS = r"""  // Icons instead of emojis (emojis break on first web load)
  static const _chipIcons = [
    Icons.home_rounded,
    Icons.palette_rounded,
    Icons.chair_rounded,
    Icons.lightbulb_rounded,
    Icons.auto_awesome_rounded,
  ];
  static const _chipTexts = [
    'odamı yeniden tasarla',
    'duvar rengi öner',
    'bu dolaba ne yakışır?',
    'bütçeye uygun dekorasyon',
    'salonumu modernleştir',
  ];"""

if OLD_CHIPS in content:
    content = content.replace(OLD_CHIPS, NEW_CHIPS)
    print("  ✅ Chip data replaced (emoji → icons)")
else:
    print("  ❌ Could not find old chips constant")

# ═══════════════════════════════════════════════════════════
# Update chip timer to use new length
# ═══════════════════════════════════════════════════════════
content = content.replace(
    "setState(() => _chipIdx = (_chipIdx + 1) % _chips.length);",
    "setState(() => _chipIdx = (_chipIdx + 1) % _chipTexts.length);"
)

# ═══════════════════════════════════════════════════════════
# Update chip rendering — emoji Text → Icon widget
# ═══════════════════════════════════════════════════════════

OLD_CHIP_RENDER = r"""                  FadeTransition(opacity: _chipFade, child: GestureDetector(
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
                      ]))))"""

NEW_CHIP_RENDER = r"""                  FadeTransition(opacity: _chipFade, child: GestureDetector(
                    onTap: () => _go(_chipTexts[_chipIdx]),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        color: const Color(0xFFF3F0FF),
                        border: Border.all(color: const Color(0xFFEDEAF5), width: 0.5)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_chipIcons[_chipIdx], size: 16, color: const Color(0xFF6C5CE7)),
                        const SizedBox(width: 8),
                        Text(_chipTexts[_chipIdx], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF4A4458))),
                      ]))))"""

if OLD_CHIP_RENDER in content:
    content = content.replace(OLD_CHIP_RENDER, NEW_CHIP_RENDER)
    print("  ✅ Chip rendering updated (emoji Text → Icon widget)")
else:
    # Try the original version (before hero update)
    OLD_CHIP_RENDER_V1 = r"""                  FadeTransition(opacity: _chipFade, child: GestureDetector(
                    onTap: () => _go(_chips[_chipIdx][1]),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: const Color(0xFFF3F0FF)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(_chips[_chipIdx][0], style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 7),
                        Text(_chips[_chipIdx][1], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF4A4458))),
                      ]))))"""

    NEW_CHIP_RENDER_V1 = r"""                  FadeTransition(opacity: _chipFade, child: GestureDetector(
                    onTap: () => _go(_chipTexts[_chipIdx]),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        color: const Color(0xFFF3F0FF),
                        border: Border.all(color: const Color(0xFFEDEAF5), width: 0.5)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_chipIcons[_chipIdx], size: 16, color: const Color(0xFF6C5CE7)),
                        const SizedBox(width: 8),
                        Text(_chipTexts[_chipIdx], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF4A4458))),
                      ]))))"""

    if OLD_CHIP_RENDER_V1 in content:
        content = content.replace(OLD_CHIP_RENDER_V1, NEW_CHIP_RENDER_V1)
        print("  ✅ Chip rendering updated (v1 match)")
    else:
        print("  ❌ Could not find chip render block")

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print()
print("Changes:")
print("  🔄 Emojis → Material Icons (load instantly, no broken state)")
print("  🎨 Icon color: Koala purple (#6C5CE7)")
print("  📏 Icon size: 16px (compact, clean)")
print("  ➕ Added 5th chip: 'salonumu modernleştir'")
print()
print("Test: flutter run -d chrome")
