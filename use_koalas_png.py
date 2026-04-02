#!/usr/bin/env python3
"""
Use koalas.png (transparent background) as the Koala logo.
- Copy koalas.png to assets/images/koala_icon.png
- Show it inside a soft purple rounded container (like the reference)
"""
import os
import shutil

BASE = r"C:\Users\canoz\Egitim-clean\koala"

# ═══════════════════════════════════════════════════════════
# Step 1: Copy koalas.png to assets
# ═══════════════════════════════════════════════════════════
src = os.path.join(os.environ['USERPROFILE'], 'Downloads', 'koalas.png')
dst = os.path.join(BASE, 'assets', 'images', 'koala_icon.png')

if os.path.exists(src):
    shutil.copy2(src, dst)
    size_kb = os.path.getsize(dst) / 1024
    print(f"  ✅ Copied koalas.png → assets/images/koala_icon.png ({size_kb:.0f} KB)")
else:
    print(f"  ❌ {src} not found! Make sure koalas.png is in Downloads")

# ═══════════════════════════════════════════════════════════
# Step 2: Update home_screen.dart
# ═══════════════════════════════════════════════════════════
path = os.path.join(BASE, "lib", "views", "home_screen.dart")
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Find the current logo block (whatever version it is) and replace
# Try multiple known versions

REPLACEMENTS = [
    # Version: ClipRRect with koala_logo.png 110px
    (
        r"""ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset('assets/images/koala_logo.png',
                      width: 110, height: 110, fit: BoxFit.cover)),""",
        "FOUND_V1"
    ),
    # Version: ClipRRect with koala_logo.png 80px
    (
        r"""ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.asset('assets/images/koala_logo.png',
                      width: 80, height: 80, fit: BoxFit.cover)),""",
        "FOUND_V2"
    ),
]

NEW_LOGO = r"""Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      color: const Color(0xFFEDE9FE)),
                    padding: const EdgeInsets.all(18),
                    child: Image.asset('assets/images/koala_icon.png', fit: BoxFit.contain)),"""

replaced = False
for old, label in REPLACEMENTS:
    if old in content:
        content = content.replace(old, NEW_LOGO)
        print(f"  ✅ Replaced logo block ({label})")
        replaced = True
        break

if not replaced:
    print("  ❌ Could not find any known logo block to replace")
    print("     Searching for any koala_logo reference...")
    if "koala_logo.png" in content:
        # Generic replace
        import re
        content = re.sub(
            r"ClipRRect\([^;]*koala_logo\.png[^;]*\)\),",
            NEW_LOGO,
            content,
            flags=re.DOTALL
        )
        print("  ✅ Replaced via regex")
    elif "Icons.auto_awesome" in content and "size: 30" in content:
        # Original Icon version
        content = content.replace(
            "child: const Icon(Icons.auto_awesome, size: 30, color: Color(0xFF6C5CE7)))",
            "padding: const EdgeInsets.all(18),\n                    child: Image.asset('assets/images/koala_icon.png', fit: BoxFit.contain))"
        )
        content = content.replace(
            "Container(width: 68, height: 68,\n                    decoration: BoxDecoration(\n                      borderRadius: BorderRadius.circular(20),\n                      color: const Color(0xFFF0ECFF)",
            "Container(width: 100, height: 100,\n                    decoration: BoxDecoration(\n                      borderRadius: BorderRadius.circular(26),\n                      color: const Color(0xFFEDE9FE)"
        )
        print("  ✅ Replaced original Icon version")

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print()
print("Result:")
print("  🐨 Transparent koala icon on soft purple (#EDE9FE) container")
print("  📦 100×100 container, 26px radius, 18px padding")
print("  🖼️ Image uses BoxFit.contain (no cropping)")
print()
print("Test: flutter run -d chrome")
