#!/usr/bin/env python3
"""Fix references to deleted login_screen.dart and signup_screen.dart"""
import os, re

BASE = r"C:\Users\canoz\Egitim-clean\koala"

# ═══════════════════════════════════════════════════════════
# 1. AUTH GATE — remove login_screen import, ensure devBypass
# ═══════════════════════════════════════════════════════════
path = os.path.join(BASE, "lib", "views", "auth_gate.dart")
with open(path, 'r', encoding='utf-8') as f:
    c = f.read()

# Remove login_screen import
c = re.sub(r"import 'login_screen\.dart';\n?", "", c)
c = re.sub(r"import 'signup_screen\.dart';\n?", "", c)

# Replace any LoginScreen() reference with MainShell()
c = c.replace("LoginScreen()", "MainShell()")
c = c.replace("const LoginScreen()", "const MainShell()")

# Ensure main_shell import
if "main_shell.dart" not in c:
    c = c.replace(
        "import 'package:flutter/material.dart';",
        "import 'package:flutter/material.dart';\nimport 'main_shell.dart';"
    )

# Ensure devBypass exists
if 'devBypass' not in c:
    c = c.replace(
        "Widget build(BuildContext context) {",
        "Widget build(BuildContext context) {\n    // DEV BYPASS\n    const devBypass = true;\n    if (devBypass) return const MainShell();\n",
        1
    )

with open(path, 'w', encoding='utf-8') as f:
    f.write(c)
print("  ✅ auth_gate.dart fixed")

# ═══════════════════════════════════════════════════════════
# 2. ONBOARDING SCREEN — remove signup_screen reference
# ═══════════════════════════════════════════════════════════
path2 = os.path.join(BASE, "lib", "views", "onboarding_screen.dart")
if os.path.exists(path2):
    with open(path2, 'r', encoding='utf-8') as f:
        c2 = f.read()

    # Remove signup import
    c2 = re.sub(r"import 'signup_screen\.dart';\n?", "", c2)

    # Replace SignupScreen references with auth_entry_screen or MainShell
    # Check if auth_entry_screen exists
    auth_entry = os.path.join(BASE, "lib", "views", "auth_entry_screen.dart")
    if os.path.exists(auth_entry):
        if "auth_entry_screen.dart" not in c2:
            c2 = c2.replace(
                "import 'package:flutter/material.dart';",
                "import 'package:flutter/material.dart';\nimport 'auth_entry_screen.dart';"
            )
        c2 = c2.replace("SignupScreen()", "AuthEntryScreen()")
        c2 = c2.replace("const SignupScreen()", "const AuthEntryScreen()")
    else:
        # Fallback to MainShell
        if "main_shell.dart" not in c2:
            c2 = c2.replace(
                "import 'package:flutter/material.dart';",
                "import 'package:flutter/material.dart';\nimport 'main_shell.dart';"
            )
        c2 = c2.replace("SignupScreen()", "MainShell()")
        c2 = c2.replace("const SignupScreen()", "const MainShell()")

    with open(path2, 'w', encoding='utf-8') as f:
        f.write(c2)
    print("  ✅ onboarding_screen.dart fixed")

print("\n  Test: flutter run -d chrome")
