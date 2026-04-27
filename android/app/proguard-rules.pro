# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Supabase
-keep class io.supabase.** { *; }

# Google Sign In
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Kotlin
-keep class kotlin.** { *; }
-dontwarn kotlin.**

# Play Core (deferred components)
-dontwarn com.google.android.play.core.**

# ─── Sprint 5 adds ───
# Google ML Kit (face detection + image labeling). R8 strips reflection-loaded
# model classes under aggressive shrinking → ML Kit fails silently at runtime.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }
-dontwarn com.google.mlkit.**

# image_cropper (uCrop). Activity + params loaded reflectively.
-keep class com.yalantis.ucrop.** { *; }
-dontwarn com.yalantis.ucrop.**

# firebase_messaging notification payload models
-keep class com.google.firebase.messaging.** { *; }

# firebase_crashlytics — kullanıcının gizlenmiş stack trace'i işe yaramaz
-keep class com.google.firebase.crashlytics.** { *; }

# OkHttp / Retrofit (Supabase transit, some plugins)
-dontwarn okhttp3.**
-dontwarn okio.**

# Görselleri decode ederken reflection kullanan image_picker helper'ları
-keep class androidx.core.content.FileProvider { *; }
