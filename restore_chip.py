#!/usr/bin/env python3
"""Restore the rotating chip animation that was removed"""
import os, re

BASE = r"C:\Users\canoz\Egitim-clean\koala"
path = os.path.join(BASE, "lib", "views", "home_screen.dart")

with open(path, 'r', encoding='utf-8') as f:
    h = f.read()

# 1. Add back SingleTickerProviderStateMixin + Timer import
h = h.replace(
    "class _HomeScreenState extends State<HomeScreen> {",
    "class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {"
)

if "dart:async" not in h:
    h = "import 'dart:async';\n" + h

# 2. Add back chip fields after _pendingPhoto
OLD_FIELDS = "  Uint8List? _pendingPhoto;\n"
NEW_FIELDS = """  Uint8List? _pendingPhoto;
  late final AnimationController _chipCtrl;
  late final Animation<double> _chipFade;
  int _chipIdx = 0;
  Timer? _chipTimer;

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
  ];
"""

if "_chipCtrl" not in h:
    h = h.replace(OLD_FIELDS, NEW_FIELDS)
    print("  ✅ Chip fields restored")

# 3. Fix initState
OLD_INIT = "  @override\n  void initState() { super.initState(); }"
NEW_INIT = """  @override
  void initState() {
    super.initState();
    _chipCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300))..value = 1.0;
    _chipFade = CurvedAnimation(parent: _chipCtrl, curve: Curves.easeInOut);
    _chipTimer = Timer.periodic(const Duration(seconds: 3), (_) => _nextChip());
  }

  void _nextChip() {
    _chipCtrl.reverse().then((_) {
      setState(() => _chipIdx = (_chipIdx + 1) % _chipTexts.length);
      _chipCtrl.forward();
    });
  }"""

if OLD_INIT in h:
    h = h.replace(OLD_INIT, NEW_INIT)
    print("  ✅ initState restored with chip animation")

# 4. Fix dispose
h = h.replace(
    "void dispose() { _inputCtrl.dispose(); super.dispose(); }",
    "void dispose() { _chipTimer?.cancel(); _chipCtrl.dispose(); _inputCtrl.dispose(); super.dispose(); }"
)
print("  ✅ dispose fixed")

# 5. Replace static chips with rotating chip
OLD_STATIC_CHIPS = """const SizedBox(height: 20),
                  // Quick action chips
                  Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                    _QuickChip(icon: Icons.camera_alt_rounded, label: 'Odanı tara',
                      onTap: () { HapticFeedback.lightImpact(); _showPicker(); }),
                    _QuickChip(icon: Icons.palette_rounded, label: 'Renk öner',
                      onTap: () { HapticFeedback.lightImpact(); _openChat(intent: KoalaIntent.colorAdvice); }),
                    _QuickChip(icon: Icons.shopping_bag_rounded, label: 'Ürün bul',
                      onTap: () { HapticFeedback.lightImpact(); _openChat(text: 'Odama uygun ürün öner'); }),
                  ]),"""

NEW_ROTATING_CHIP = """const SizedBox(height: 24),
                  // Rotating hint chip
                  FadeTransition(opacity: _chipFade, child: GestureDetector(
                    onTap: () { HapticFeedback.lightImpact(); _go(_chipTexts[_chipIdx]); },
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
                      ])))),"""

if OLD_STATIC_CHIPS in h:
    h = h.replace(OLD_STATIC_CHIPS, NEW_ROTATING_CHIP)
    print("  ✅ Static chips → rotating chip restored")
else:
    print("  ⚠️  Could not find static chips block")

with open(path, 'w', encoding='utf-8') as f:
    f.write(h)

print("\n  Test: .\\run.ps1")
