#!/usr/bin/env python3
"""
Fix the ShaderMask issue — it washes out the koala's original dark purple colors.
Remove ShaderMask, show PNG as-is. Keep container, font, spacing from Gemini.
"""
import os

BASE = r"C:\Users\canoz\Egitim-clean\koala"
path = os.path.join(BASE, "lib", "views", "home_screen.dart")

with open(path, 'r', encoding='utf-8') as f:
    c = f.read()

# Replace the ShaderMask block with plain Image.asset
OLD = """                          child: Center(
                            child: ShaderMask(
                              // Logoya dikey gradyan uygular
                              shaderCallback: (bounds) => const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xFF9E8DB3), Color(0xFF3A2E46)],
                              ).createShader(bounds),
                              child: Image.asset(
                                'assets/images/koalas.png',
                                width: 90,
                                height: 90,
                                fit: BoxFit.contain,
                                // ShaderMask'ın çalışması için resmin siyah/transparan olması idealdir
                                color: Colors.white, 
                                colorBlendMode: BlendMode.modulate,
                              ),
                            ),
                          ),"""

NEW = """                          child: Center(
                            child: Image.asset(
                              'assets/images/koalas.png',
                              width: 90,
                              height: 90,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),"""

if OLD in c:
    c = c.replace(OLD, NEW)
    print("  ✅ ShaderMask removed — original colors preserved")
else:
    print("  ❌ Could not find ShaderMask block")

with open(path, 'w', encoding='utf-8') as f:
    f.write(c)

# Also make sure koalas.png is in assets
import shutil
src = os.path.join(os.environ['USERPROFILE'], 'Downloads', 'koalas.png')
dst = os.path.join(BASE, 'assets', 'images', 'koalas.png')
if os.path.exists(src) and not os.path.exists(dst):
    shutil.copy2(src, dst)
    print(f"  ✅ Copied koalas.png to assets/images/")
elif os.path.exists(dst):
    print(f"  ✅ koalas.png already in assets")

print("\n  Test: flutter run -d chrome")
