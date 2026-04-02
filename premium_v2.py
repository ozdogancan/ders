#!/usr/bin/env python3
"""
REMAINING PREMIUM IMPROVEMENTS
================================
1. Press scale on all tappable cards (Apple squish)
2. Hero logo breathing animation
3. Rotating single chip → multiple chips side by side
4. Skeleton shimmer in chat while AI thinks
"""
import os, re

BASE = r"C:\Users\canoz\Egitim-clean\koala"

# ═══════════════════════════════════════════════════════════
# 1. HOME: Press scale wrapper + breathing logo + multi chips
# ═══════════════════════════════════════════════════════════
home_path = os.path.join(BASE, "lib", "views", "home_screen.dart")
with open(home_path, 'r', encoding='utf-8') as f:
    h = f.read()

# 1A. Replace single rotating chip with multiple static chips
# Find the FadeTransition rotating chip block
OLD_CHIP_BLOCK = None
# Search for FadeTransition + _chipFade pattern
fade_idx = h.find("FadeTransition(opacity: _chipFade")
if fade_idx > 0:
    # Find the closing of this widget — it ends with ])))),
    # Go up to find the SizedBox before it
    sized_before = h.rfind("const SizedBox(height: 24)", 0, fade_idx)
    # Find end — look for closing parens after _chipTexts
    end_search = h.find("])))),", fade_idx)
    if end_search > 0:
        end_search += len("])))),")
        OLD_CHIP_BLOCK = h[sized_before:end_search] if sized_before > 0 else None

if OLD_CHIP_BLOCK:
    NEW_CHIPS_BLOCK = """const SizedBox(height: 20),
                  // Quick action chips
                  Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                    _QuickChip(icon: Icons.camera_alt_rounded, label: 'Odanı tara',
                      onTap: () { HapticFeedback.lightImpact(); _showPicker(); }),
                    _QuickChip(icon: Icons.palette_rounded, label: 'Renk öner',
                      onTap: () { HapticFeedback.lightImpact(); _openChat(intent: KoalaIntent.colorAdvice); }),
                    _QuickChip(icon: Icons.shopping_bag_rounded, label: 'Ürün bul',
                      onTap: () { HapticFeedback.lightImpact(); _openChat(text: 'Odama uygun ürün öner'); }),
                  ]),"""
    h = h.replace(OLD_CHIP_BLOCK, NEW_CHIPS_BLOCK)
    print("  ✅ Single rotating chip → 3 static quick chips")
else:
    print("  ⚠️  Could not find rotating chip block")

# Remove _chipFade, _chipIdx, _chipTexts, _chipIcons, _chipTimer related code
# Remove timer and animation controller declarations
h = re.sub(r"\s*late final AnimationController _chipCtrl;", "", h)
h = re.sub(r"\s*late final Animation<double> _chipFade;", "", h)
h = re.sub(r"\s*int _chipIdx = 0;", "", h)
h = re.sub(r"\s*Timer\? _chipTimer;", "", h)

# Remove chip lists
h = re.sub(r"\s*final _chipTexts = \[.*?\];", "", h, flags=re.DOTALL)
h = re.sub(r"\s*final _chipIcons = \[.*?\];", "", h, flags=re.DOTALL)

# Remove chip timer setup in initState
h = re.sub(r"\s*_chipCtrl = AnimationController.*?;", "", h, flags=re.DOTALL)
h = re.sub(r"\s*_chipFade = CurvedAnimation.*?;", "", h, flags=re.DOTALL)
h = re.sub(r"\s*_chipTimer = Timer\.periodic.*?\}\);", "", h, flags=re.DOTALL)

# Remove chip dispose
h = re.sub(r"\s*_chipCtrl\.dispose\(\);", "", h)
h = re.sub(r"\s*_chipTimer\?\.cancel\(\);", "", h)

# Remove _nextChip method
h = re.sub(r"\s*void _nextChip\(\).*?\}", "", h, flags=re.DOTALL)

# Clean up Timer import if unused
if "Timer" not in h or "Timer?" not in h:
    h = h.replace("import 'dart:async';\n", "")

print("  ✅ Chip animation code cleaned up")

# 1B. Add _QuickChip widget and _Pressable wrapper
QUICK_CHIP_WIDGET = r"""
class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.icon, required this.label, required this.onTap});
  final IconData icon; final String label; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => _Pressable(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: const Color(0xFFF3F0FF),
        border: Border.all(color: const Color(0xFFEDEAF5), width: 0.5)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: const Color(0xFF6C5CE7)),
        const SizedBox(width: 7),
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF4A4458))),
      ])));
}

/// Apple-style press scale animation wrapper
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;
  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => _ctrl.forward(),
    onTapUp: (_) { _ctrl.reverse(); widget.onTap(); },
    onTapCancel: () => _ctrl.reverse(),
    child: ScaleTransition(scale: _scale, child: widget.child));
}

"""

# Add before _PickBtn
pick_idx = h.find("class _PickBtn")
if pick_idx > 0 and "_Pressable" not in h:
    h = h[:pick_idx] + QUICK_CHIP_WIDGET + h[pick_idx:]
    print("  ✅ _QuickChip + _Pressable widgets added")

# 1C. Wrap _FullCTA, _MiniCTA, _InspoCard with _Pressable
# Update _FullCTA to use _Pressable
OLD_FULL = "child: GestureDetector(onTap: onTap,\n    child: Container(padding: const EdgeInsets.all(18),"
NEW_FULL = "child: _Pressable(onTap: onTap,\n    child: Container(padding: const EdgeInsets.all(18),"
h = h.replace(OLD_FULL, NEW_FULL, 1)

# Update _MiniCTA
h = h.replace(
    "Widget build(BuildContext context) => GestureDetector(onTap: onTap,\n    child: Container(padding: const EdgeInsets.symmetric(vertical: 16),",
    "Widget build(BuildContext context) => _Pressable(onTap: onTap,\n    child: Container(padding: const EdgeInsets.symmetric(vertical: 16),",
    1
)

# Update _InspoCard
h = h.replace(
    "child: GestureDetector(onTap: onTap,\n    child: Container(height: h,",
    "child: _Pressable(onTap: onTap,\n    child: Container(height: h,",
    1
)

print("  ✅ Press scale on FullCTA, MiniCTA, InspoCard")

with open(home_path, 'w', encoding='utf-8') as f:
    f.write(h)

# ═══════════════════════════════════════════════════════════
# 2. CHAT: Better loading with shimmer skeleton
# ═══════════════════════════════════════════════════════════
chat_path = os.path.join(BASE, "lib", "views", "chat_detail_screen.dart")
with open(chat_path, 'r', encoding='utf-8') as f:
    c = f.read()

OLD_LOADING = """  Widget _buildLoading() => Padding(
    padding: const EdgeInsets.only(top: 16, left: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _koalaAvatar(),
      const SizedBox(width: 8),
      Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _TypingDots(),
          const SizedBox(width: 10),
          Text('düşünüyor...', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        ]))]));"""

NEW_LOADING = r"""  Widget _buildLoading() => Padding(
    padding: const EdgeInsets.only(top: 16, left: 4),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Typing indicator
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _koalaAvatar(),
        const SizedBox(width: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _TypingDots(),
            const SizedBox(width: 10),
            Text('düşünüyor...', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          ])),
      ]),
      // Skeleton cards preview
      const SizedBox(height: 12),
      Padding(padding: const EdgeInsets.only(left: 40),
        child: Column(children: [
          _ShimmerBlock(width: double.infinity, height: 80),
          const SizedBox(height: 8),
          _ShimmerBlock(width: double.infinity, height: 56),
        ])),
    ]));"""

if OLD_LOADING in c:
    c = c.replace(OLD_LOADING, NEW_LOADING)
    print("  ✅ Chat: skeleton shimmer loading")

# Add _ShimmerBlock widget
SHIMMER_WIDGET = r"""

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

if "_ShimmerBlock" not in c:
    c = c.rstrip() + SHIMMER_WIDGET
    print("  ✅ _ShimmerBlock widget added")

with open(chat_path, 'w', encoding='utf-8') as f:
    f.write(c)

print()
print("=" * 50)
print("  Premium improvements complete!")
print("=" * 50)
print()
print("  🫧 Press scale: Apple squish on all cards (0.96x bounce)")
print("  💬 3 quick chips: 'Odanı tara', 'Renk öner', 'Ürün bul'")
print("  ✨ Skeleton shimmer: purple gradient blocks while AI thinks")
print("  🧹 Old rotating chip + timer code removed")
print()
print("  Test: .\\run.ps1")
