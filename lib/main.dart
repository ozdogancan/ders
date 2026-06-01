import 'dart:async';
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/router/app_router.dart';
import 'services/analytics_service.dart';
import 'services/mock_mode.dart';
import 'services/cache_service.dart';
import 'services/connectivity_service.dart';
import 'services/evlumba_live_service.dart';
import 'services/push_token_service.dart';
import 'services/saved_items_service.dart';
import 'services/billing_service.dart';
import 'services/quota_service.dart';
import 'helpers/paywall_router.dart';
import 'core/router/app_router.dart' as koala_router;
import 'core/config/env.dart';
import 'views/splash_screen.dart';
import 'firebase_options.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// FCM background handler — uygulama kill edildiğinde (ya da terminated state'te)
/// gelen data mesajlarını işlemek için top-level fonksiyon OLMAK ZORUNDA.
/// Şimdilik sadece log atıyor; iş akışı tarafı PushHandlerService foreground
/// içinde navigate ediyor. Sprint 5.5'te burada unread badge bump'layabiliriz.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background'da tam Firebase env yok — initializeApp gerekirse lazım olur.
  // Şu an no-op yeterli; notification payload zaten system bar'da göstiriliyor.
  debugPrint('[fcm/bg] ${message.messageId}: ${message.notification?.title}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Background message handler'ı runApp'tan ÖNCE register et — Android'de
  // terminated state'te gelen mesajlar için zorunlu. kIsWeb'de no-op.
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }
  PaintingBinding.instance.imageCache.maximumSizeBytes = 100 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 200;

  // Font'ları bundle'dan yükle — TTF'ler assets/google_fonts/ altında, pubspec'te
  // declared. Package ÖNCE local'e bakar, bulamazsa CDN'e düşer. CLS düşer
  // (ilk frame'de doğru font var), normal akışta 1 DNS+TLS handshake kaybolur,
  // Google'a her sayfa açılışında IP sızmaz.
  //
  // allowRuntimeFetching=true bırakıldı (default) — bundle yüklenmezse eski
  // davranışa fallback. Canlıyı bozmaz. İleride 1-2 release stabil gittikten
  // sonra `false`a çevirip network path'ı tamamen kapatabiliriz.

  // Android: edge-to-edge + şeffaf status/navigation bar.
  // Aksi halde Samsung gibi bazı cihazlarda status bar OEM arkaplanıyla
  // koyu bir şerit olarak görünüp ekranla uyumsuz kalıyor.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  // Global error handler — unhandled exceptions don't crash the app.
  // Sprint 5 — mobile (Android/iOS) release builds forward Flutter + platform
  // errors to Firebase Crashlytics. Web skips (firebase_crashlytics has no web
  // implementation) and debug builds just print.
  final crashlyticsActive = !kIsWeb && kReleaseMode;
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
    if (crashlyticsActive) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled: $error\n$stack');
    if (crashlyticsActive) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    }
    return true; // prevents crash
  };

  // Build-time config guard: fail loud if a release bundle was built without
  // dart-defines (e.g. `flutter build web --release` run directly instead of
  // .\build_web.ps1). Silent empty-config bundles have regressed 3+ times.
  if (kReleaseMode && !Env.hasSupabaseConfig) {
    runApp(const _MisconfiguredBuildApp());
    return;
  }

  // Mock mode init (URL ?mock=1 / sharedprefs flag) — restyle çağrısı
  // başlamadan önce tamamlansın diye await ediyoruz (sharedprefs read fast).
  await MockMode.init();

  // Disk caches → RAM warm: paralel oku, ilk frame'de hazır olsun.
  // Hard refresh sonrası Projelerim ve Swipe deck anında çiziliyor.
  await Future.wait([
    SavedItemsService.warmFromDiskCache(),
    EvlumbaLiveService.warmDeckFromDisk(),
    // Pro/Premium billing — Android only; web/iOS no-op (see BillingService).
    BillingService.initialize(),
  ]);

  runApp(const _BootstrapApp());
}

class _MisconfiguredBuildApp extends StatelessWidget {
  const _MisconfiguredBuildApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFB00020),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(LucideIcons.alertCircle, color: Colors.white, size: 72),
                SizedBox(height: 24),
                Text(
                  'Build misconfigured',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16),
                Text(
                  'SUPABASE_URL / SUPABASE_ANON_KEY were empty at build time.\n\n'
                  'This release was built without --dart-define values. '
                  'Rebuild using .\\build_web.ps1 (web) or .\\build_android.ps1 (Android) '
                  'instead of running `flutter build` directly.',
                  style: TextStyle(color: Colors.white, fontSize: 16, height: 1.4),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();
  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  late final Future<void> _initFuture = _initializeBackends();
  bool _didTrackStartup = false;
  bool _supabaseReady = false;
  // Önceki auth UID — auth state değiştiğinde in-memory cache'i temizlemek
  // için tutulur. Login / logout / user switch durumlarında stale count
  // (başka kullanıcının saved_counts vs.) görünmesin.
  String? _lastAuthUid;

  Future<void> _initializeBackends() async {
    final _bootSw = Stopwatch()..start();
    void _bt(String step) =>
        debugPrint('[boot] $step @${_bootSw.elapsedMilliseconds}ms');
    _bt('init-start');
    try {
      // Timeout — web'de Firebase JS SDK bazen asılabiliyor; SplashScreen'in
      // sonsuza kalmaması için 12sn sınır. Hata/timeout → catch loglar, app
      // devam eder (login gerekiyorsa /auth'a yönlenir, splash'ta takılmaz).
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 12));
      _bt('firebase-done');
      // Crashlytics collection: sadece mobil release build'de aç. Debug'da
      // false tutarak geliştirme sırasında fake crash flood'u engelle.
      if (!kIsWeb) {
        try {
          await FirebaseCrashlytics.instance
              .setCrashlyticsCollectionEnabled(kReleaseMode);
        } catch (e) {
          debugPrint('Crashlytics toggle skipped: $e');
        }
      }
    } catch (error) {
      debugPrint('Firebase init skipped: $error');
    }

    // 2026-05: Misafir kullanıcı tamamen kaldırıldı (REQUIRE_LOGIN=true).
    // signInAnonymously() çağrısı yapılmıyor — kullanıcı /auth ekranında
    // gerçek bir hesapla giriş yapana kadar currentUser=null kalır.
    // Geriye dönük güvenlik: eğer eski bir cihazda anonim oturum kaldıysa
    // sessizce signOut et ki AuthGate login duvarına yönlendirsin.
    if (Env.requireLogin) {
      final existing = FirebaseAuth.instance.currentUser;
      if (existing != null && existing.isAnonymous) {
        try {
          await FirebaseAuth.instance
              .signOut()
              .timeout(const Duration(seconds: 6));
          debugPrint('Stale anonymous session signed out');
        } catch (e) {
          debugPrint('Anonymous sign-out skipped: $e');
        }
      }
    } else if (FirebaseAuth.instance.currentUser == null) {
      // Geliştirme modu (REQUIRE_LOGIN=false): anonim oturum hâlâ destekli.
      try {
        await FirebaseAuth.instance.signInAnonymously();
        debugPrint('Anonymous auth completed (dev mode)');
      } catch (e) {
        debugPrint('Anonymous auth skipped: $e');
      }
    }

    // Auth state değişiminde in-memory cache temizliği.
    // Logout / login / user-switch → eski kullanıcının saved_counts_xxx
    // gibi key'leri yeni kullanıcıya sızmasın.
    _lastAuthUid = FirebaseAuth.instance.currentUser?.uid;
    FirebaseAuth.instance.authStateChanges().listen((user) {
      final prev = _lastAuthUid;
      final curr = user?.uid;
      if (prev != curr) {
        CacheService.clearAll();
        debugPrint('Auth changed ($prev → $curr), cache cleared');
      }
      _lastAuthUid = curr;
    });

    if (Env.hasSupabaseConfig) {
      try {
        await Supabase.initialize(
          url: Env.supabaseUrl,
          anonKey: Env.supabaseAnonKey,
        );
        _supabaseReady = true;
        // KRİTİK: x-user-id header'ını Firebase auth state'ine kilitle.
        // Aksi halde hard refresh sonrası session restore olsa bile header
        // boş kalır, RLS bütün UPDATE'leri sessizce reddeder (markAsRead,
        // unread_count vs. çalışmaz).
        final sb = Supabase.instance.client;
        final initUid = FirebaseAuth.instance.currentUser?.uid;
        if (initUid != null) {
          sb.rest.headers['x-user-id'] = initUid;
        }
        FirebaseAuth.instance.authStateChanges().listen((user) {
          if (user?.uid != null) {
            sb.rest.headers['x-user-id'] = user!.uid;
          } else {
            sb.rest.headers.remove('x-user-id');
          }
        });
      } catch (error) {
        debugPrint('Supabase init skipped: $error');
      }
    }
    _bt('supabase-done');

    // Connectivity monitoring
    ConnectivityService.init();

    // NOT: Bildirim izni artık home_screen'de isteniyor, onboarding'de değil

    // Router state (onboarding flag) — prefs okuması; yine de timeout+catch ile
    // sar ki hiçbir koşulda init (ve dolayısıyla SplashScreen) asılı kalmasın.
    try {
      await initRouterState().timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('initRouterState skipped: $e');
    }
    _bt('router-done');

    // Evlumba DB (read-only source)
    if (Env.hasEvlumbaConfig) {
      try {
        EvlumbaLiveService.initialize(
          url: Env.evlumbaUrl,
          anonKey: Env.evlumbaAnonKey,
        );
        debugPrint('Evlumba DB connected');
      } catch (error) {
        debugPrint('Evlumba init skipped: $error');
      }
    }

    // Anasayfa swipe deck'i için proaktif prefetch — splash görünürken
    // designer_projects ilk batch, koala_cards seed havuzu ve ilk 3 cover
    // bitmap'i paralel olarak ısıtılır. NOT awaited: splash'ı blokle*MEZ*,
    // başarısız olsa bile boot etkilenmez. StyleDiscoveryLiveScreen mount
    // olduğunda EvlumbaLiveService.prefetchedDeck zaten dolu → ilk kart
    // anında çıkar.
    if (_supabaseReady) {
      unawaited(EvlumbaLiveService.prefetchForHome());
    }
    _bt('init-end');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // Boot / async init sırasında gösterilen unified splash ekranı.
          // Android native splash (krem #F7F4EF) ile aynı tonda olduğu için
          // geçiş kesintisiz; web preloader da aynı tasarımı kullanır.
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: SplashScreen(),
          );
        }
        if (!_didTrackStartup) {
          _didTrackStartup = true;
          debugPrint('[boot] futurebuilder-done → render KoalaApp');
          Analytics.instance.init(
            platform: _platformName(),
            appVersion: '1.0.0',
            enabled: _supabaseReady,
          );
          Analytics.appOpened();
          // TODO(analytics-batch): Analytics now batches INSERTs (30s / 50
          // events). No WidgetsBindingObserver exists in _BootstrapApp, so
          // the lifecycle flush is wired into the existing observer in
          // lib/views/home_screen.dart's didChangeAppLifecycleState — when
          // touching that file next, add:
          //   if (state == AppLifecycleState.paused ||
          //       state == AppLifecycleState.detached) {
          //     Analytics.flushNow();
          //   }
          // Acceptable loss window otherwise: up to 50 events / 30s on
          // process death before first flush.
          // Wire global 402 → paywall handler. Services call this when API
          // returns 402 quota_exceeded; we route via the GoRouter navigator key.
          QuotaService.onQuotaExceeded = (trigger) {
            final ctx =
                koala_router.appRouter.routerDelegate.navigatorKey.currentContext;
            if (ctx == null) return;
            QuotaService.invalidate();
            showPaywall(ctx, trigger: trigger);
          };
        }
        return const ProviderScope(child: KoalaApp());
      },
    );
  }

  // NOT: Push notification token registration tek bir yerde:
  // `firebase_service.dart:_registerFcmToken`. Eski duplicate `_initPushNotifications`
  // Sprint 5'te kaldırıldı (analyzer "unused_element" warning'i + iki farklı
  // yerde aynı token register kodunun sync'siz tutulma riski vardı).

  String _platformName() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }
}
