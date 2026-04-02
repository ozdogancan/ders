#!/usr/bin/env python3
import os

BASE = r"C:\Users\canoz\Egitim-clean\koala"
path = os.path.join(BASE, "lib", "views", "home_screen.dart")

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

OLD = r"""Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      color: const Color(0xFFEDE9FE)),
                    padding: const EdgeInsets.all(18),
                    child: Image.asset('assets/images/koala_icon.png', fit: BoxFit.contain)),"""

NEW = r"""Image.asset('assets/images/koala_icon.png',
                      width: 120, height: 120, fit: BoxFit.contain),"""

if OLD in content:
    content = content.replace(OLD, NEW)
    print("  ✅ Fixed: container removed, PNG shown at 120x120 directly")
else:
    print("  ❌ Could not find the block")

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("  PNG already has its own purple bg + rounded corners.")
print("  No container needed. Just show it big and clean.")
print("  Test: flutter run -d chrome")
