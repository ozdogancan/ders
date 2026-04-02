#!/usr/bin/env python3
import os

BASE = r"C:\Users\canoz\Egitim-clean\koala"
path = os.path.join(BASE, "lib", "views", "home_screen.dart")

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace(
    "Image.asset('assets/images/koala_icon.png',\n                      width: 120, height: 120, fit: BoxFit.contain),",
    "Image.asset('assets/images/koala_icon.png',\n                      width: 200, height: 200, fit: BoxFit.contain),"
)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("  ✅ Logo: 120px → 200px")
print("  Test: flutter run -d chrome")
