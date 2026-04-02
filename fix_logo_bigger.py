#!/usr/bin/env python3
import os

BASE = r"C:\Users\canoz\Egitim-clean\koala"
path = os.path.join(BASE, "lib", "views", "home_screen.dart")

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace(
    "child: Image.asset('assets/images/koala_logo.png',\n                      width: 80, height: 80, fit: BoxFit.cover)),",
    "child: Image.asset('assets/images/koala_logo.png',\n                      width: 110, height: 110, fit: BoxFit.cover)),"
)

content = content.replace(
    "borderRadius: BorderRadius.circular(22),\n                    child: Image.asset('assets/images/koala_logo.png',\n                      width: 110, height: 110, fit: BoxFit.cover)),",
    "borderRadius: BorderRadius.circular(28),\n                    child: Image.asset('assets/images/koala_logo.png',\n                      width: 110, height: 110, fit: BoxFit.cover)),"
)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("  ✅ Logo: 80px → 110px, radius: 22 → 28")
print("  Test: flutter run -d chrome")
