#!/usr/bin/env python3
"""Fix broken initState + clean chip remnants + fix ShimmerBlock"""
import os, re

BASE = r"C:\Users\canoz\Egitim-clean\koala"

# ═══════════════════════════════════════════════════════════
# 1. HOME: Fix initState and remove chip remnants
# ═══════════════════════════════════════════════════════════
home_path = os.path.join(BASE, "lib", "views", "home_screen.dart")
with open(home_path, 'r', encoding='utf-8') as f:
    h = f.read()

# Fix: Replace broken initState + dead chip declarations
OLD_BROKEN = """class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _inputCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  late final AnimationController _chipFade;
  Uint8List? _pendingPhoto;
  // Icons instead of emojis (emojis break on first web load)
  static const _chipIcons = [
    Icons.home_rounded,
    Icons.palette_rounded,
    Icons.chair_rounded,
    Icons.lightbulb_rounded,
    Icons.auto_awesome_rounded,
  ];
  static const _chipTexts = [
    'odamÄ± yeniden tasarla',
    'duvar rengi Ã¶ner',
    'bu dolaba ne yakÄ±ÅŸÄ±r?',
    'bÃ¼tÃ§eye uygun dekorasyon',
    'salonumu modernleÅŸtir',
  ];
  @override
  void initState() {
    super.initState();
    _chipFade = AnimationController(vsync: this, duration: const Duration(milliseconds: 300))..value = 1.0;
    });
  }
  @override
  void dispose() { _inputCtrl.dispose(); _chipFade.dispose(); super.dispose(); }"""

NEW_FIXED = """class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  Uint8List? _pendingPhoto;

  @override
  void dispose() { _inputCtrl.dispose(); super.dispose(); }"""

if OLD_BROKEN in h:
    h = h.replace(OLD_BROKEN, NEW_FIXED)
    print("  ✅ initState fixed, chip code removed, SingleTickerProvider removed")
else:
    # Try to fix just the broken part
    print("  ⚠️  Exact match not found, trying line-by-line fix...")
    
    # Remove SingleTickerProviderStateMixin since we don't need it anymore
    h = h.replace("with SingleTickerProviderStateMixin {", "{")
    
    # Remove chip-related fields
    h = re.sub(r"\s*late final AnimationController _chipFade;\n", "\n", h)
    h = re.sub(r"\s*static const _chipIcons = \[[\s\S]*?\];\n", "\n", h)
    h = re.sub(r"\s*static const _chipTexts = \[[\s\S]*?\];\n", "\n", h)
    
    # Fix broken initState
    h = re.sub(
        r"@override\s*\n\s*void initState\(\) \{[\s\S]*?\n\s*\}\s*\n",
        "@override\n  void initState() { super.initState(); }\n",
        h, count=1
    )
    
    # Fix dispose
    h = re.sub(
        r"void dispose\(\) \{[^}]*_chipFade\.dispose\(\);[^}]*\}",
        "void dispose() { _inputCtrl.dispose(); super.dispose(); }",
        h
    )
    print("  ✅ Fixed via line-by-line")

# Also remove any remaining ); that's orphaned
h = h.replace("    });\n  }\n  @override\n  void dispose()", "  @override\n  void dispose()")

with open(home_path, 'w', encoding='utf-8') as f:
    f.write(h)

# ═══════════════════════════════════════════════════════════
# 2. CHAT: Ensure _ShimmerBlock is a proper top-level class
# ═══════════════════════════════════════════════════════════
chat_path = os.path.join(BASE, "lib", "views", "chat_detail_screen.dart")
with open(chat_path, 'r', encoding='utf-8') as f:
    c = f.read()

if "class _ShimmerBlock" not in c:
    SHIMMER = r"""

class _ShimmerBlock extends StatefulWidget {
  const _ShimmerBlock({required this.width, required this.height});
  final double width, height;
  @override
  State<_ShimmerBlock> createState() => _ShimmerBlockState();
}

class _ShimmerBlockState extends State<_ShimmerBlock> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => Container(
      width: widget.width, height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment(-1.0 + 2.0 * _ctrl.value, 0),
          end: Alignment(-1.0 + 2.0 * _ctrl.value + 1, 0),
          colors: const [Color(0xFFF3F0FF), Color(0xFFEDE9FF), Color(0xFFF3F0FF)]))));
}
"""
    c = c.rstrip() + SHIMMER
    with open(chat_path, 'w', encoding='utf-8') as f:
        f.write(c)
    print("  ✅ _ShimmerBlock added to chat")
else:
    print("  ✅ _ShimmerBlock already exists")

print("\n  Test: .\\run.ps1")
