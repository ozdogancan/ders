#!/usr/bin/env python3
"""
Fix koala logo - PNG already has its own rounded bg, no need for container.
Show it directly, larger, clean.
"""
import os

BASE = r"C:\Users\canoz\Egitim-clean\koala"
path = os.path.join(BASE, "lib", "views", "home_screen.dart")

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

OLD = r"""                  // Koala logo from PNG asset
                  Container(width: 84, height: 84,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: const Color(0xFFEDE9FE),
                      boxShadow: [BoxShadow(color: const Color(0xFF6C5CE7).withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 6))]),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Image.asset('assets/images/koala_logo.png', fit: BoxFit.contain))),"""

NEW = r"""                  // Koala logo — PNG already has its own rounded bg
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.asset('assets/images/koala_logo.png',
                      width: 80, height: 80, fit: BoxFit.cover)),"""

if OLD in content:
    content = content.replace(OLD, NEW)
    print("  ✅ Fixed: removed container, PNG shown directly at 80x80")
else:
    print("  ❌ Could not find the container version, trying broader match...")
    # Try to find any version with koala_logo.png in a Container
    import re
    pattern = r"Container\([^;]*koala_logo\.png[^;]*\)\),"
    if re.search(pattern, content, re.DOTALL):
        content = re.sub(pattern,
            "ClipRRect(\n"
            "                    borderRadius: BorderRadius.circular(22),\n"
            "                    child: Image.asset('assets/images/koala_logo.png',\n"
            "                      width: 80, height: 80, fit: BoxFit.cover)),",
            content, flags=re.DOTALL)
        print("  ✅ Fixed via regex match")
    else:
        print("  ❌ No match found")

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print()
print("Now the PNG shows directly at 80x80 with rounded corners.")
print("No extra container, no padding, no double background.")
print()
print("Test: flutter run -d chrome")
