import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/router/app_router.dart';
import 'services/analytics_service.dart';
import 'services/cache_service.dart';
import 'services/connectivity_service.dart';
import 'services/evlumba_live_service.dart';
import 'services/push_token_service.dart';
import 'core/config/env.dart';
import 'widgets/experience_ui.dart';
import 'firebase_options.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 100 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 200;

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

  // Global error handler — unhandled exceptions don't crash the app
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled: $error\n$stack');
    return true; // prevents crash
  };

  // Build-time config guard: fail loud if a release bundle was built without
  // dart-defines (e.g. `flutter build web --release` run directly instead of
  // .\build_web.ps1). Silent empty-config bundles have regressed 3+ times.
  if (kReleaseMode && !Env.hasSupabaseConfig) {
    runApp(const _MisconfiguredBuildApp());
    return;
  }

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
                Icon(Icons.error_outline, color: Colors.white, size: 72),
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
                  'Rebuild with .\\build_web.ps1 instead of running '
                  '`flutter build web --release` directly.',
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
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (error) {
      debugPrint('Firebase init skipped: $error');
    }

    // Login gerektirmiyorsa ve kullanıcı yoksa anonim giriş dene
    if (!Env.requireLogin && FirebaseAuth.instance.currentUser == null) {
      try {
        await FirebaseAuth.instance.signInAnonymously();
        debugPrint('Anonymous auth completed');
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

    // Connectivity monitoring
    ConnectivityService.init();

    // NOT: Bildirim izni artık home_screen'de isteniyor, onboarding'de değil

    // Router state (onboarding flag)
    await initRouterState();

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
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: AppBackdrop(
                showGrid: false,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          );
        }
        if (!_didTrackStartup) {
          _didTrackStartup = true;
          Analytics.instance.init(
            platform: _platformName(),
            appVersion: '1.0.0',
            enabled: _supabaseReady,
          );
          Analytics.appOpened();
        }
        return const ProviderScope(child: KoalaApp());
      },
    );
  }

  Future<void> _initPushNotifications() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        final token = await messaging.getToken();
        if (token != null) {
          final platform = kIsWeb
              ? TokenPlatform.web
              : defaultTargetPlatform == TargetPlatform.iOS
                  ? TokenPlatform.ios
                  : TokenPlatform.android;
          await PushTokenService.registerToken(
            deviceToken: token,
            platform: platform,
          );
        }
        // Listen for token refresh
        messaging.onTokenRefresh.listen((newToken) {
          final platform = kIsWeb
              ? TokenPlatform.web
              : defaultTargetPlatform == TargetPlatform.iOS
                  ? TokenPlatform.ios
                  : TokenPlatform.android;
          PushTokenService.registerToken(
            deviceToken: newToken,
            platform: platform,
          );
        });
      }
    } catch (e) {
      debugPrint('Push notification init skipped: $e');
    }
  }

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
