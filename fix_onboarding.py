#!/usr/bin/env python3
import os, re

BASE = r"C:\Users\canoz\Egitim-clean\koala"
path = os.path.join(BASE, "lib", "views", "onboarding_screen.dart")

with open(path, 'r', encoding='utf-8') as f:
    c = f.read()

# Remove auth_entry import
c = re.sub(r"import 'auth_entry_screen\.dart';\n?", "", c)

# Add main_shell import if missing
if "main_shell.dart" not in c:
    c = c.replace(
        "import 'package:flutter/material.dart';",
        "import 'package:flutter/material.dart';\nimport 'main_shell.dart';"
    )

# Replace AuthEntryScreen() with MainShell()
c = c.replace("AuthEntryScreen()", "MainShell()")
c = c.replace("const AuthEntryScreen()", "const MainShell()")

with open(path, 'w', encoding='utf-8') as f:
    f.write(c)

print("  ✅ onboarding → MainShell()")
print("  Test: flutter run -d chrome")
