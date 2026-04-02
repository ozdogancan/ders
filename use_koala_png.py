#!/usr/bin/env python3
"""
Use koalaal.png as the Koala hero logo.
1. Copy the PNG to assets/images/
2. Update home_screen.dart hero to use Image.asset instead of CustomPaint
3. Remove the _KoalaLogoPainter class if it exists
"""
import os
import shutil

BASE = r"C:\Users\canoz\Egitim-clean\koala"

# ═══════════════════════════════════════════════════════════
# Step 1: Copy koalaal.png to assets/images/
# ═══════════════════════════════════════════════════════════
src = os.path.join(os.environ['USERPROFILE'], 'Downloads', 'koalaal.png')
dst_dir = os.path.join(BASE, 'assets', 'images')
dst = os.path.join(dst_dir, 'koala_logo.png')

os.makedirs(dst_dir, exist_ok=True)

if os.path.exists(src):
    shutil.copy2(src, dst)
    print(f"  ✅ Copied koalaal.png → assets/images/koala_logo.png")
else:
    print(f"  ❌ {src} not found!")
    print(f"     Make sure koalaal.png is in Downloads folder")

# ═══════════════════════════════════════════════════════════
# Step 2: Make sure pubspec.yaml has the asset
# ═══════════════════════════════════════════════════════════
pubspec_path = os.path.join(BASE, 'pubspec.yaml')
with open(pubspec_path, 'r', encoding='utf-8') as f:
    pubspec = f.read()

if 'assets/images/koala_logo.png' not in pubspec and 'assets/images/' in pubspec:
    print("  ✅ assets/images/ already in pubspec.yaml (wildcard or folder)")
elif 'assets/images/koala_logo.png' in pubspec:
    print("  ✅ koala_logo.png already in pubspec.yaml")
else:
    print("  ⚠️  You may need to add 'assets/images/' to pubspec.yaml assets section")

# ═══════════════════════════════════════════════════════════
# Step 3: Update home_screen.dart
# ═══════════════════════════════════════════════════════════
path = os.path.join(BASE, "lib", "views", "home_screen.dart")
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace the hero section (CustomPaint version)
OLD = r"""                  // Koala face SVG in rounded container
                  Container(width: 80, height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      color: const Color(0xFFEDE9FE),
                      boxShadow: [BoxShadow(color: const Color(0xFF6C5CE7).withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 6))]),
                    child: Center(child: CustomPaint(size: const Size(50, 50), painter: _KoalaLogoPainter()))),
                  const SizedBox(height: 16),
                  // Brand name — bold, rounded
                  const Text('koala', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF1A1D2A), letterSpacing: -1.0)),"""

NEW = r"""                  // Koala logo from PNG asset
                  Container(width: 84, height: 84,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: const Color(0xFFEDE9FE),
                      boxShadow: [BoxShadow(color: const Color(0xFF6C5CE7).withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 6))]),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Image.asset('assets/images/koala_logo.png', fit: BoxFit.contain))),
                  const SizedBox(height: 16),
                  // Brand name — bold, rounded
                  const Text('koala', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF1A1D2A), letterSpacing: -1.0)),"""

if OLD in content:
    content = content.replace(OLD, NEW)
    print("  ✅ Hero updated to use koala_logo.png")
else:
    # Try finding the old Icon version
    OLD_ICON = r"""                  // Larger Koala icon with subtle shadow
                  Container(width: 68, height: 68,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: const Color(0xFFF0ECFF),
                      boxShadow: [BoxShadow(color: const Color(0xFF6C5CE7).withOpacity(0.08), blurRadius: 24, offset: const Offset(0, 8))]),
                    child: const Icon(Icons.auto_awesome, size: 30, color: Color(0xFF6C5CE7))),
                  const SizedBox(height: 14),
                  // Brand name — slightly larger
                  const Text('koala', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1A1D2A), letterSpacing: -0.8)),"""

    NEW_ICON = r"""                  // Koala logo from PNG asset
                  Container(width: 84, height: 84,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: const Color(0xFFEDE9FE),
                      boxShadow: [BoxShadow(color: const Color(0xFF6C5CE7).withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 6))]),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Image.asset('assets/images/koala_logo.png', fit: BoxFit.contain))),
                  const SizedBox(height: 16),
                  // Brand name — bold, rounded
                  const Text('koala', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF1A1D2A), letterSpacing: -1.0)),"""

    if OLD_ICON in content:
        content = content.replace(OLD_ICON, NEW_ICON)
        print("  ✅ Hero updated to use koala_logo.png (from Icon version)")
    else:
        print("  ❌ Could not find hero section to replace")

# ═══════════════════════════════════════════════════════════
# Step 4: Remove _KoalaLogoPainter if exists
# ═══════════════════════════════════════════════════════════
painter_start = content.find("class _KoalaLogoPainter")
if painter_start != -1:
    # Find the end of the class (next class or end of file)
    # Look for the closing of shouldRepaint method
    painter_end = content.find("bool shouldRepaint(covariant CustomPainter oldDelegate) => false;\n}", painter_start)
    if painter_end != -1:
        painter_end = painter_end + len("bool shouldRepaint(covariant CustomPainter oldDelegate) => false;\n}")
        content = content[:painter_start] + content[painter_end:]
        print("  ✅ Removed _KoalaLogoPainter class")
    else:
        print("  ⚠️  Found _KoalaLogoPainter but couldn't find its end")
else:
    print("  ℹ️  _KoalaLogoPainter not found (already removed or not added)")

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print()
print("Done! Summary:")
print("  🐨 koalaal.png → assets/images/koala_logo.png")
print("  🖼️ Hero now uses Image.asset (PNG, not CustomPaint)")
print("  📦 Container: 84×84, #EDE9FE bg, radius 24, 14px padding")
print("  🔤 'koala' text: 28px, w800")
print()
print("Test: flutter run -d chrome")
