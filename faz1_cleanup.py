#!/usr/bin/env python3
"""
KOALA FAZ 1 — PARÇA A: Dead Code Temizliği
============================================
Eski eğitim/AI tutor uygulamasından kalan dosyaları siler.
Bu dosyalar artık Koala'da kullanılmıyor.
"""
import os
import shutil

BASE = r"C:\Users\canoz\Egitim-clean\koala"

# ═══════════════════════════════════════════════════════════
# SİLİNECEK DOSYALAR — dead code
# ═══════════════════════════════════════════════════════════
dead_files = [
    # Eski eğitim constants
    "lib/core/constants/app_prompts.dart",
    "lib/core/constants/exam_catalog.dart",
    "lib/core/constants/lgs_math_learning_catalog.dart",
    "lib/core/constants/math_topic_catalog.dart",
    "lib/core/constants/tutor_catalog.dart",

    # Eski modeller
    "lib/models/ai_solution.dart",
    "lib/models/exam.dart",
    "lib/models/guided_lesson.dart",
    "lib/models/question.dart",
    "lib/models/tutor_profile.dart",

    # Eski servisler
    "lib/services/ai_tutor_service.dart",
    "lib/services/chatgpt_service.dart",
    "lib/services/chat_service.dart",        # Claude Code'un yarım bıraktığı
    "lib/services/credit_service.dart",
    "lib/services/did_service.dart",
    "lib/services/learning_resume_service.dart",
    "lib/services/proactive_feed_service.dart",
    "lib/services/room_analysis_service.dart",
    "lib/services/supabase_storage_service.dart",
    "lib/services/tutor_voice_service.dart",

    # Eski store'lar
    "lib/stores/mastery_store.dart",
    "lib/stores/question_store.dart",
    "lib/stores/scan_store.dart",

    # Eski ekranlar
    "lib/views/ask_question_screen.dart",
    "lib/views/chat_screen.dart",          # Eski chat (ChatDetailScreen kullanılıyor)
    "lib/views/credit_store_screen.dart",
    "lib/views/exam_subjects_screen.dart",
    "lib/views/login_screen.dart",         # auth_entry_screen kullanılıyor
    "lib/views/mastery_learn_screen.dart",
    "lib/views/mastery_new_topic_screen.dart",
    "lib/views/mastery_tab.dart",
    "lib/views/mastery_topic_screen.dart",
    "lib/views/math_tutor_screen.dart",
    "lib/views/question_share_screen.dart",
    "lib/views/scan_home_screen.dart",
    "lib/views/scan_screen.dart",
    "lib/views/signup_screen.dart",
    "lib/views/solution_screen.dart",
    "lib/views/subject_lessons_screen.dart",

    # Eski widget'lar
    "lib/widgets/did_video_view.dart",
    "lib/widgets/math_text_block.dart",
    "lib/widgets/question_card.dart",
    "lib/widgets/question_share_fab.dart",
    "lib/widgets/tutor_subject_card.dart",

    # Eski providers
    "lib/providers/app_providers.dart",

    # Duplicate/leftover files
    "lib/lib/core/constants/koala_prompts.dart",
    "lib/lib/services/koala_ai_service.dart",
    "lib/lib/views/chat_detail_screen.dart",

    # Eski chat modeli (Firestore bazlı, kullanılmıyor)
    "lib/models/chat_models.dart",
]

deleted = 0
skipped = 0

for rel in dead_files:
    full = os.path.join(BASE, rel.replace('/', os.sep))
    if os.path.exists(full):
        os.remove(full)
        deleted += 1
        print(f"  🗑️  {rel}")
    else:
        skipped += 1

# Clean empty lib/lib directory if it exists
lib_lib = os.path.join(BASE, "lib", "lib")
if os.path.exists(lib_lib):
    shutil.rmtree(lib_lib)
    print(f"  🗑️  lib/lib/ (empty directory)")

# Clean empty stores directory
stores_dir = os.path.join(BASE, "lib", "stores")
if os.path.exists(stores_dir) and not os.listdir(stores_dir):
    os.rmdir(stores_dir)
    print(f"  🗑️  lib/stores/ (empty directory)")

# Clean empty providers directory
providers_dir = os.path.join(BASE, "lib", "providers")
if os.path.exists(providers_dir) and not os.listdir(providers_dir):
    os.rmdir(providers_dir)
    print(f"  🗑️  lib/providers/ (empty directory)")

print()
print(f"  Silindi: {deleted}, Bulunamadı: {skipped}")
print()
print("Kalan aktif dosyalar:")
print("  lib/core/config/env.dart")
print("  lib/core/constants/koala_prompts.dart")
print("  lib/core/theme/app_theme.dart")
print("  lib/models/flow_models.dart")
print("  lib/models/koala_card.dart")
print("  lib/models/scan_analysis.dart")
print("  lib/services/analytics_service.dart")
print("  lib/services/chat_persistence.dart")
print("  lib/services/evlumba_service.dart")
print("  lib/services/firebase_service.dart")
print("  lib/services/koala_ai_service.dart")
print("  lib/services/koala_image_service.dart")
print("  lib/views/auth_*.dart")
print("  lib/views/chat_detail_screen.dart")
print("  lib/views/chat_list_screen.dart")
print("  lib/views/explore_screen.dart")
print("  lib/views/guided_flow_screen.dart")
print("  lib/views/home_screen.dart")
print("  lib/views/main_shell.dart")
print("  lib/views/onboarding_screen.dart")
print("  lib/views/phone_auth_screen.dart")
print("  lib/views/profile_screen.dart")
print("  lib/widgets/auth_required_sheet.dart")
print("  lib/widgets/experience_ui.dart")
print("  lib/widgets/flow_*.dart")
print("  lib/widgets/koala_logo.dart")
print("  lib/widgets/responsive_frame.dart")
