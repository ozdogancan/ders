#!/usr/bin/env python3
import os

BASE = r"C:\Users\canoz\Egitim-clean\koala"
path = os.path.join(BASE, "lib", "views", "home_screen.dart")

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Fix 1: Add filterQuality and isAntiAlias to Image.asset for crisp rendering
content = content.replace(
    "Image.asset('assets/images/koala_icon.png',\n                      width: 200, height: 200, fit: BoxFit.contain),",
    "Image.asset('assets/images/koala_icon.png',\n                      width: 200, height: 200, fit: BoxFit.contain, filterQuality: FilterQuality.high),"
)

# Fix 2: Reduce gap between logo and "koala" text (16px → 4px)
content = content.replace(
    "const SizedBox(height: 16),\n                  // Brand name",
    "const SizedBox(height: 4),\n                  // Brand name"
)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("  ✅ Gap: 16px → 4px")
print("  ✅ Added FilterQuality.high (crisp lines)")
print("  Test: flutter run -d chrome")
