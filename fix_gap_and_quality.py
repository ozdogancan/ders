#!/usr/bin/env python3
"""
Only 2 fixes:
1. Gap between logo and 'koala' text: too much → tight
2. Pixelated lines → force high DPI rendering
"""
import os

BASE = r"C:\Users\canoz\Egitim-clean\koala"
path = os.path.join(BASE, "lib", "views", "home_screen.dart")

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Fix 1: Find the current logo + gap + text block and replace
# Current: logo → SizedBox(height: X) → text
# We need to find the Image.asset line, then the SizedBox after it

# Replace gap (whatever it currently is) to 0
for gap in ['16', '14', '12', '10', '8', '6', '4']:
    old = f"const SizedBox(height: {gap}),\n                  // Brand name"
    new = "const SizedBox(height: 0),\n                  // Brand name"
    if old in content:
        content = content.replace(old, new)
        print(f"  ✅ Gap: {gap}px → 0px")
        break

# Also reduce top padding so it doesn't float too high
content = content.replace(
    "padding: const EdgeInsets.only(top: 48, bottom: 32),",
    "padding: const EdgeInsets.only(top: 36, bottom: 24),"
)

# Fix 2: Ensure FilterQuality.high is on the image
if "filterQuality: FilterQuality.high" not in content:
    content = content.replace(
        "fit: BoxFit.contain),",
        "fit: BoxFit.contain, filterQuality: FilterQuality.high),"
    )
    print("  ✅ Added FilterQuality.high")
else:
    print("  ✅ FilterQuality.high already present")

# Fix 3: Use cacheWidth/cacheHeight for crisp rendering at device pixel ratio
# This forces Flutter to decode the image at a higher resolution
old_img = "Image.asset('assets/images/koala_icon.png',\n                      width: 200, height: 200, fit: BoxFit.contain, filterQuality: FilterQuality.high),"
new_img = "Image.asset('assets/images/koala_icon.png',\n                      width: 200, height: 200, fit: BoxFit.contain,\n                      filterQuality: FilterQuality.high,\n                      cacheWidth: 600, cacheHeight: 600),"

if old_img in content:
    content = content.replace(old_img, new_img)
    print("  ✅ Added cacheWidth/cacheHeight: 600 (3x for crisp lines)")
else:
    # try 130px version
    old_img2 = "Image.asset('assets/images/koala_icon.png',\n                      width: 130, height: 130, fit: BoxFit.contain, filterQuality: FilterQuality.high),"
    new_img2 = "Image.asset('assets/images/koala_icon.png',\n                      width: 200, height: 200, fit: BoxFit.contain,\n                      filterQuality: FilterQuality.high,\n                      cacheWidth: 600, cacheHeight: 600),"
    if old_img2 in content:
        content = content.replace(old_img2, new_img2)
        print("  ✅ Size back to 200 + cacheWidth 600 for crisp lines")

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print()
print("Changes:")
print("  📐 Logo↔text gap: → 0px (tight, like reference)")  
print("  🔍 cacheWidth: 600 (renders at 3x, lines will be crisp)")
print("  📐 Top padding: 48→36, bottom: 32→24")
print()
print("Test: flutter run -d chrome")
