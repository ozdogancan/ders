#!/usr/bin/env python3
import os
BASE = r"C:\Users\canoz\Egitim-clean\koala"
path = os.path.join(BASE, "lib", "views", "home_screen.dart")
with open(path, 'r', encoding='utf-8') as f:
    h = f.read()

h = h.replace(
    "class _PressableState extends State<_Pressable> {",
    "class _PressableState extends State<_Pressable> with SingleTickerProviderStateMixin {"
)

with open(path, 'w', encoding='utf-8') as f:
    f.write(h)
print("  ✅ Fixed: _PressableState + SingleTickerProviderStateMixin")
print("  Test: .\\run.ps1")
