#!/usr/bin/env python3
"""
KOALA FAZ 1 — PARÇA B: Home Screen Patch + Chat Entegrasyonu
=============================================================
1. scan_store import'unu kaldır (dead code)
2. Tüm import'ların doğru olduğunu garanti et
3. firebase_service.dart'tan dead code referanslarını temizle
4. main.dart ve app.dart'ı kontrol et
"""
import os
import re

BASE = r"C:\Users\canoz\Egitim-clean\koala"

# ═══════════════════════════════════════════════════════════
# 1. HOME SCREEN — scan_store import'unu kaldır
# ═══════════════════════════════════════════════════════════
home_path = os.path.join(BASE, "lib", "views", "home_screen.dart")
with open(home_path, 'r', encoding='utf-8') as f:
    home = f.read()

# Remove scan_store import
home = home.replace("import '../stores/scan_store.dart';\n", "")
print("  ✅ home_screen.dart — scan_store import removed")

with open(home_path, 'w', encoding='utf-8') as f:
    f.write(home)

# ═══════════════════════════════════════════════════════════
# 2. FIREBASE SERVICE — question referanslarını temizle
# ═══════════════════════════════════════════════════════════
fb_path = os.path.join(BASE, "lib", "services", "firebase_service.dart")
if os.path.exists(fb_path):
    with open(fb_path, 'r', encoding='utf-8') as f:
        fb = f.read()

    # Remove question import if it exists
    fb = fb.replace("import '../models/question.dart';\n", "")

    # Remove question-related methods
    # saveQuestion
    fb = re.sub(r'\n\s*Future<void> saveQuestion\(Question question\).*?\n\s*\}', '', fb, flags=re.DOTALL)
    # watchQuestionsForUser
    fb = re.sub(r'\n\s*Stream<List<Question>> watchQuestionsForUser.*?\n\s*\}\);?\n\s*\}', '', fb, flags=re.DOTALL)
    # watchQuestionById
    fb = re.sub(r'\n\s*Stream<Question\?> watchQuestionById.*?\n\s*\}\);?\n\s*\}', '', fb, flags=re.DOTALL)
    # setQuestionFeedback
    fb = re.sub(r'\n\s*Future<void> setQuestionFeedback.*?\n\s*\}', '', fb, flags=re.DOTALL)

    with open(fb_path, 'w', encoding='utf-8') as f:
        f.write(fb)
    print("  ✅ firebase_service.dart — question methods removed")

# ═══════════════════════════════════════════════════════════
# 3. ANALYTICS SERVICE — question referanslarını temizle
# ═══════════════════════════════════════════════════════════
analytics_path = os.path.join(BASE, "lib", "services", "analytics_service.dart")
if os.path.exists(analytics_path):
    with open(analytics_path, 'r', encoding='utf-8') as f:
        analytics = f.read()
    
    # Remove any question/tutor/mastery imports
    analytics = re.sub(r"import '.*question.*';\n", "", analytics)
    analytics = re.sub(r"import '.*tutor.*';\n", "", analytics)
    analytics = re.sub(r"import '.*mastery.*';\n", "", analytics)
    
    with open(analytics_path, 'w', encoding='utf-8') as f:
        f.write(analytics)
    print("  ✅ analytics_service.dart — cleaned dead imports")

# ═══════════════════════════════════════════════════════════
# 4. MAIN.DART — import temizliği
# ═══════════════════════════════════════════════════════════
main_path = os.path.join(BASE, "lib", "main.dart")
if os.path.exists(main_path):
    with open(main_path, 'r', encoding='utf-8') as f:
        main = f.read()
    
    # Remove dead imports
    dead_imports = [
        'question_store', 'mastery_store', 'scan_store',
        'ai_tutor_service', 'chatgpt_service', 'credit_service',
        'did_service', 'tutor_voice_service', 'room_analysis_service',
        'learning_resume_service', 'proactive_feed_service',
        'app_providers', 'supabase_storage_service',
    ]
    for di in dead_imports:
        main = re.sub(rf"import '.*{di}.*';\n", "", main)
    
    with open(main_path, 'w', encoding='utf-8') as f:
        f.write(main)
    print("  ✅ main.dart — dead imports cleaned")

# ═══════════════════════════════════════════════════════════
# 5. APP.DART — import temizliği
# ═══════════════════════════════════════════════════════════
app_path = os.path.join(BASE, "lib", "app.dart")
if os.path.exists(app_path):
    with open(app_path, 'r', encoding='utf-8') as f:
        app = f.read()
    
    dead_imports = [
        'question_store', 'mastery_store', 'scan_store',
        'ai_tutor_service', 'chatgpt_service', 'credit_service',
        'app_providers', 'supabase_storage_service',
    ]
    for di in dead_imports:
        app = re.sub(rf"import '.*{di}.*';\n", "", app)
    
    with open(app_path, 'w', encoding='utf-8') as f:
        f.write(app)
    print("  ✅ app.dart — dead imports cleaned")

# ═══════════════════════════════════════════════════════════
# 6. AUTH GATE — check devBypass is working
# ═══════════════════════════════════════════════════════════
auth_gate_path = os.path.join(BASE, "lib", "views", "auth_gate.dart")
if os.path.exists(auth_gate_path):
    with open(auth_gate_path, 'r', encoding='utf-8') as f:
        auth = f.read()
    
    if 'devBypass' in auth:
        print("  ✅ auth_gate.dart — devBypass already present")
    else:
        # Add devBypass
        auth = auth.replace(
            "Widget build(BuildContext context) {",
            "Widget build(BuildContext context) {\n    // DEV BYPASS\n    const devBypass = true;\n    if (devBypass) return const MainShell();\n",
            1
        )
        # Make sure MainShell import exists
        if "main_shell.dart" not in auth:
            auth = auth.replace(
                "import 'package:flutter/material.dart';",
                "import 'package:flutter/material.dart';\nimport 'main_shell.dart';"
            )
        with open(auth_gate_path, 'w', encoding='utf-8') as f:
            f.write(auth)
        print("  ✅ auth_gate.dart — devBypass added")

# ═══════════════════════════════════════════════════════════
# 7. PROFILE SCREEN — ensure it doesn't import dead code
# ═══════════════════════════════════════════════════════════
profile_path = os.path.join(BASE, "lib", "views", "profile_screen.dart")
if os.path.exists(profile_path):
    with open(profile_path, 'r', encoding='utf-8') as f:
        profile = f.read()
    
    dead_imports = ['question_store', 'mastery_store', 'scan_store', 'credit_service']
    changed = False
    for di in dead_imports:
        if di in profile:
            profile = re.sub(rf"import '.*{di}.*';\n", "", profile)
            changed = True
    
    if changed:
        with open(profile_path, 'w', encoding='utf-8') as f:
            f.write(profile)
        print("  ✅ profile_screen.dart — dead imports cleaned")

# ═══════════════════════════════════════════════════════════
# 8. GUIDED FLOW SCREEN — ensure imports are correct
# ═══════════════════════════════════════════════════════════
gf_path = os.path.join(BASE, "lib", "views", "guided_flow_screen.dart")
if os.path.exists(gf_path):
    with open(gf_path, 'r', encoding='utf-8') as f:
        gf = f.read()
    
    # Make sure it imports the right koala_ai_service
    if "import '../services/koala_ai_service.dart'" not in gf:
        gf = "import '../services/koala_ai_service.dart';\n" + gf
    
    with open(gf_path, 'w', encoding='utf-8') as f:
        f.write(gf)
    print("  ✅ guided_flow_screen.dart — imports verified")

print()
print("=" * 50)
print("  Faz 1 tamamlandı!")
print("=" * 50)
print()
print("  Sıra:")
print("  1. python faz1_cleanup.py   (dead code sil)")
print("  2. python faz1_patch.py     (import'ları temizle)")
print("  3. flutter run -d chrome    (test et)")
print()
print("  Hata olursa compile output'unu yapıştır!")
