import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/router/app_router.dart';
import 'services/analytics_service.dart';
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
  runApp(const _BootstrapApp());
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

    if (Env.hasSupabaseConfig) {
      try {
        await Supabase.initialize(
          url: Env.supabaseUrl,
          anonKey: Env.supabaseAnonKey,
        );
        _supabaseReady = true;
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
