# Koala - Module Inventory
**Tarih:** 2026-04-09

## Ekran Envanteri (32 ekran)

### Auth Modulu
| Ekran | Dosya | Durum |
|-------|-------|-------|
| Login | login_screen.dart | Calisiyor |
| Register | register_screen.dart | Calisiyor |
| Forgot Password | forgot_password_screen.dart | Calisiyor |
| Email Verification | email_verification_screen.dart | Calisiyor |

### Onboarding Modulu
| Ekran | Dosya | Durum |
|-------|-------|-------|
| Onboarding | onboarding_screen.dart | Calisiyor |
| Profile Setup | profile_setup_screen.dart | Calisiyor |
| Interest Selection | interest_selection_screen.dart | Calisiyor |

### Ana Navigasyon
| Ekran | Dosya | Durum |
|-------|-------|-------|
| Home | home_screen.dart | Calisiyor |
| Dashboard | dashboard_screen.dart | Calisiyor |
| Bottom Nav | bottom_nav_screen.dart | Calisiyor |

### Egitmen Modulu
| Ekran | Dosya | Durum |
|-------|-------|-------|
| Tutor Listing | tutor_listing_screen.dart | Calisiyor |
| Tutor Detail | tutor_detail_screen.dart | Calisiyor |
| Tutor Profile | tutor_profile_screen.dart | Calisiyor |
| Become Tutor | become_tutor_screen.dart | Calisiyor |

### Ders/Booking Modulu
| Ekran | Dosya | Durum |
|-------|-------|-------|
| Lesson Detail | lesson_detail_screen.dart | Calisiyor |
| Booking | booking_screen.dart | Calisiyor |
| My Lessons | my_lessons_screen.dart | Calisiyor |
| Lesson History | lesson_history_screen.dart | Calisiyor |

### Chat / AI Modulu
| Ekran | Dosya | LOC | Durum |
|-------|-------|-----|-------|
| Chat List | chat_list_screen.dart | ~300 | Calisiyor |
| Chat Detail | chat_detail_screen.dart | 2993 | RISK - cok buyuk |
| AI Chat | ai_chat_screen.dart | ~400 | Calisiyor |

### Profil Modulu
| Ekran | Dosya | Durum |
|-------|-------|-------|
| Profile | profile_screen.dart | Calisiyor |
| Edit Profile | edit_profile_screen.dart | Calisiyor |
| Settings | settings_screen.dart | Calisiyor |
| Notifications | notifications_screen.dart | Calisiyor |

### Diger
| Ekran | Dosya | Durum |
|-------|-------|-------|
| Search | search_screen.dart | Calisiyor |
| Category | category_screen.dart | Calisiyor |
| Review | review_screen.dart | Calisiyor |
| Payment | payment_screen.dart | Belirsiz |
| About | about_screen.dart | Calisiyor |

## Servis Katmani (8 servis)

| Servis | Dosya | Sorumluluk | Risk |
|--------|-------|------------|------|
| Auth Service | auth_service.dart | Firebase Auth | Dusuk |
| Supabase Service | supabase_service.dart | DB CRUD | Orta |
| Koala AI Service | koala_ai_service.dart (787 LOC) | Gemini API | Yuksek |
| Chat Service | chat_service.dart | Mesajlasma | Orta |
| Notification Service | notification_service.dart | Push | Dusuk |
| Storage Service | storage_service.dart | Dosya yukleme | Dusuk |
| Booking Service | booking_service.dart | Randevu | Orta |
| Review Service | review_service.dart | Degerlendirme | Dusuk |

## Widget/Component Katmani

| Widget | Kullanim | Canonical? |
|--------|----------|------------|
| KoalaButton | Genel buton | Evet |
| KoalaCard | Kart componenti | Evet |
| KoalaTextField | Input alani | Evet |
| TutorCard | Egitmen karti | Evet |
| LessonCard | Ders karti | Evet |
| LoadingWidget | Yukleme gostergesi | Evet |
| ErrorWidget | Hata gosterimi | Hayir - tutarsiz |
| RatingStars | Puan gosterimi | Evet |

## Klasor Yapisi

```
lib/
  main.dart
  app.dart
  screens/          # 32 ekran
  services/         # 8 servis
  models/           # Veri modelleri
  widgets/          # Paylasilan widgetlar
  providers/        # Riverpod provider'lar (az)
  utils/            # Yardimci fonksiyonlar
  constants/        # Sabitler
  theme/            # Tema tanimlari
```
