#!/usr/bin/env python3
import os, shutil, re

BASE = r"C:\Users\canoz\Egitim-clean\koala"

# Step 1: Copy clean PNG to assets
src = os.path.join(os.environ['USERPROFILE'], 'Downloads', 'koalas_clean.png')
dst = os.path.join(BASE, 'assets', 'images', 'koala_icon.png')
shutil.copy2(src, dst)
print(f"  ✅ koalas_clean.png → assets/images/koala_icon.png ({os.path.getsize(dst)//1024} KB)")

# Step 2: Fix home_screen.dart
path = os.path.join(BASE, "lib", "views", "home_screen.dart")
with open(path, 'r', encoding='utf-8') as f:
    c = f.read()

# Replace image line — whatever params it has now
c = re.sub(
    r"Image\.asset\('assets/images/koala_icon\.png'[^)]*\),",
    "Image.asset('assets/images/koala_icon.png',\n                      width: 120, height: 120, fit: BoxFit.contain),",
    c
)
print("  ✅ Logo: 120x120")

# Ensure 0 gap — remove any SizedBox before "Brand name"  
c = re.sub(
    r"const SizedBox\(height: \d+\),\s*\n\s*// Brand name",
    "// Brand name",
    c
)
# Also check if gap was already removed
if "// Brand name" in c:
    print("  ✅ Gap: 0px")

with open(path, 'w', encoding='utf-8') as f:
    f.write(c)

print("\n  Test: flutter run -d chrome")
