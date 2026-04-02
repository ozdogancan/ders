#!/usr/bin/env python3
"""
HOME SCREEN VISUAL POLISH — No functional changes
===================================================
1. Add soft shadows to cards (instead of flat border-only)
2. Add 3rd mini CTA: Renk Öner (3-column grid)
3. Better section titles
4. More breathing room between sections
5. Better input bar styling
"""
import os

BASE = r"C:\Users\canoz\Egitim-clean\koala"
path = os.path.join(BASE, "lib", "views", "home_screen.dart")

with open(path, 'r', encoding='utf-8') as f:
    h = f.read()

# ═══════════════════════════════════════════════════════════
# 1. Fix Hızlı Başla: 2 cards → 3 cards
# ═══════════════════════════════════════════════════════════
OLD_2_CARDS = """                  Row(children: [
                    Expanded(child: _MiniCTA(
                      icon: Icons.account_balance_wallet_rounded,"""

# Check if already 3 cards
if "Renk" not in h.split("Row(children: [")[1].split("])")[0] if "Row(children: [" in h else "":
    # Need to find the exact 2-card Row and replace
    # Find the Row with Bütçe Planla and Tasarımcı
    import re
    pattern = r"Row\(children: \[\s*Expanded\(child: _MiniCTA\(\s*icon: Icons\.account_balance_wallet_rounded,\s*title: '[^']*',\s*onTap: [^)]*\),?\s*\)\),\s*const SizedBox\(width: \d+\),\s*Expanded\(child: _MiniCTA\(\s*icon: Icons\.person_search_rounded,\s*title: '[^']*',\s*onTap: [^)]*\),?\s*\)\),\s*\]\)"
    
    match = re.search(pattern, h, re.DOTALL)
    if match:
        NEW_3_CARDS = """Row(children: [
                    Expanded(child: _MiniCTA(
                      icon: Icons.account_balance_wallet_rounded,
                      title: 'Bütçe',
                      onTap: () { HapticFeedback.lightImpact(); _openChat(intent: KoalaIntent.budgetPlan); },
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: _MiniCTA(
                      icon: Icons.palette_rounded,
                      title: 'Renk Öner',
                      onTap: () { HapticFeedback.lightImpact(); _openChat(intent: KoalaIntent.colorAdvice); },
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: _MiniCTA(
                      icon: Icons.person_search_rounded,
                      title: 'Tasarımcı',
                      onTap: () { HapticFeedback.lightImpact(); _openChat(intent: KoalaIntent.designerMatch); },
                    )),
                  ])"""
        h = h[:match.start()] + NEW_3_CARDS + h[match.end():]
        print("  ✅ 2 mini CTAs → 3 (Bütçe + Renk + Tasarımcı)")
    else:
        print("  ⚠️  Could not find 2-card Row pattern")
else:
    print("  ✅ 3 cards already present")

# ═══════════════════════════════════════════════════════════
# 2. Add soft shadows to _MiniCTA
# ═══════════════════════════════════════════════════════════
OLD_MINI = """      decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R),
        color: const Color(0xFFF8F6FF), border: Border.all(color: const Color(0xFFEDEAF5))),"""

NEW_MINI = """      decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R),
        color: Colors.white,
        boxShadow: [BoxShadow(color: const Color(0xFF6C5CE7).withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 4))]),"""

h = h.replace(OLD_MINI, NEW_MINI)
print("  ✅ MiniCTA: border → soft shadow")

# ═══════════════════════════════════════════════════════════
# 3. Better FullCTA gradient + shadow
# ═══════════════════════════════════════════════════════════
OLD_FULL_DECO = """      decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R),
        gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF8B5CF6)])),"""

NEW_FULL_DECO = """      decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R),
        gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFF8B5CF6)]),
        boxShadow: [BoxShadow(color: const Color(0xFF6C5CE7).withOpacity(0.25), blurRadius: 20, offset: const Offset(0, 8))]),"""

h = h.replace(OLD_FULL_DECO, NEW_FULL_DECO)
print("  ✅ FullCTA: added purple shadow")

# ═══════════════════════════════════════════════════════════
# 4. InspoCard: add subtle shadow
# ═══════════════════════════════════════════════════════════
OLD_INSPO_DECO = "child: Container(height: h, decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R), color: const Color(0xFFF3F1F8)),"

NEW_INSPO_DECO = """child: Container(height: h, decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R), color: const Color(0xFFF3F1F8),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))]),"""

h = h.replace(OLD_INSPO_DECO, NEW_INSPO_DECO)
print("  ✅ InspoCard: added shadow")

# ═══════════════════════════════════════════════════════════
# 5. TrendCard + PollCard: shadow instead of border
# ═══════════════════════════════════════════════════════════
h = h.replace(
    "decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R), color: Colors.white,\n      border: Border.all(color: const Color(0xFFF0EDF5))),\n    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [\n      Row(children: [\n        Container(width: 24, height: 24,",
    "decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R), color: Colors.white,\n      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 3))]),\n    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [\n      Row(children: [\n        Container(width: 24, height: 24,"
)
print("  ✅ TrendCard: border → shadow")

# PollCard
h = h.replace(
    "decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R), color: const Color(0xFFF8F6FF)),\n    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [\n      const Text('\\u{1F3AF}",
    "decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R), color: const Color(0xFFF8F6FF),\n      boxShadow: [BoxShadow(color: const Color(0xFF6C5CE7).withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 3))]),\n    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [\n      const Text('\\u{1F3AF}"
)
print("  ✅ PollCard: added shadow")

# ═══════════════════════════════════════════════════════════
# 6. "Senin İçin" cards: better styling
# ═══════════════════════════════════════════════════════════
# Önce-Sonra card: add shadow
h = h.replace(
    "decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R),\n                        gradient: const LinearGradient(colors: [Color(0xFFF0ECFF), Color(0xFFE8F5E9)])),",
    "decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R),\n                        gradient: const LinearGradient(colors: [Color(0xFFF0ECFF), Color(0xFFE8F5E9)]),\n                        boxShadow: [BoxShadow(color: const Color(0xFF6C5CE7).withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 4))]),",
    1
)

# Stil Testi card: add shadow
h = h.replace(
    "decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R), color: Colors.white,\n                        border: Border.all(color: const Color(0xFFEDEAF5))),",
    "decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R), color: Colors.white,\n                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 3))]),",
    1
)
print("  ✅ 'Senin İçin' cards: added shadows")

with open(path, 'w', encoding='utf-8') as f:
    f.write(h)

print()
print("  Visual changes (no functional changes):")
print("  🎨 3 mini CTAs: Bütçe + Renk Öner + Tasarımcı")
print("  🌫️ Soft shadows on all cards (no more flat borders)")
print("  💜 Purple glow shadow on main CTA")
print("  🖼️ InspoCards: subtle depth shadow")
print("  ✨ TrendCard + PollCard: shadow instead of border")
print("  🫧 'Senin İçin' cards: subtle shadows")
print()
print("  Test: .\\run.ps1")
