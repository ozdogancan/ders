import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';

import '../../views/home_screen.dart';
import '../../views/main_shell.dart';
import '../../views/explore_screen.dart';
import '../../views/saved/saved_screen_v2.dart';
import '../../views/chat_list_screen.dart';
import '../../views/notifications_feed_screen.dart';
import '../../views/profile_screen.dart';
import '../../views/chat_detail_screen.dart';
import '../../services/koala_ai_service.dart';
import '../../views/conversation_detail_screen.dart';
import '../../views/designers_screen.dart';
import '../../views/collections_screen.dart';
import '../../views/projeler_screen.dart';
import '../../views/notifications_screen.dart';
import '../../views/onboarding_screen.dart';
import '../../views/style_discovery_screen.dart';
import '../../views/style_profile_screen.dart';
import '../../views/mekan/swipe_screen.dart' as mekan_swipe;
import '../../views/designer_profile_screen.dart';
import '../../views/auth_common.dart';
import '../../views/auth_entry_screen.dart';
import '../../views/evlumba_login_screen.dart';
import '../../views/admin/admin_shell.dart';
import '../../views/my_designs/my_designs_screen.dart';

/// Onboarding tamamlandı mı? AuthGate ve goToHome tarafından set ediliyor.
bool onboardingComplete = false;

// ─── Auth durumu (router redirect'i için) ───────────────────────────────
// 2026-06-02: Login duvarı GoRouter'a taşındı. Eskiden router yalnızca
// `onboardingComplete`'e bakıyordu → REQUIRE_LOGIN=true olsa bile giriş
// yapmamış (currentUser=null) kullanıcı MainShell'e düşüp "misafir" gibi
// geziyordu. Artık redirect auth'u da kontrol ediyor.
//
// Web'de Firebase oturumu ASENKRON restore eder; ilk authStateChanges olayı
// gelene kadar currentUser geçici null'dır. Bu yüzden:
//   • `_authReady` ilk olayda true olur (restore tamamlandı sinyali).
//   • `authRefresh` her auth değişiminde GoRouter redirect'ini yeniden tetikler
//     (refreshListenable). Böylece login/logout anında doğru ekrana gidilir.
final ValueNotifier<int> authRefresh = ValueNotifier<int>(0);
bool _authReady = false;
bool _isAuthed = false;
StreamSubscription<User?>? _authSub;

// 2026-06-02: admin.koalatutor.com → ayrı admin portalı. Bu host'ta uygulama
// doğrudan /admin'e gider (onboarding/keşfet yok); AdminShell kendi girişini
// (yalnız info@evlumba.com) yönetir.
final bool isAdminHost =
    kIsWeb && Uri.base.host.toLowerCase().startsWith('admin.');

/// Uygulama başlarken SharedPreferences'dan yükle + auth restore'unu bekle.
Future<void> initRouterState() async {
  final prefs = await SharedPreferences.getInstance();
  onboardingComplete = prefs.getBool('onboarding_done') ?? false;
  await _bindAuthForRouter();
}

Future<void> _bindAuthForRouter() async {
  final firstEvent = Completer<void>();
  _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) {
    _authReady = true;
    // Anonim oturum "giriş yapmış" sayılmaz (REQUIRE_LOGIN=true ile zaten
    // anonim açılmıyor; eski cihazda kalmışsa login duvarına alınır).
    _isAuthed = user != null && !user.isAnonymous;
    authRefresh.value++;
    if (!firstEvent.isCompleted) firstEvent.complete();
  });
  // İlk auth olayını (session restore) bekle ama boot'u asla asma.
  await firstEvent.future
      .timeout(const Duration(seconds: 3), onTimeout: () {});
}

/// Koala app router — Hub-style, ShellRoute yok.
/// Home ekranı hub, diğer ekranlar push ile açılır.
final GoRouter appRouter = GoRouter(
  initialLocation: isAdminHost ? '/admin' : '/',
  debugLogDiagnostics: false,
  refreshListenable: authRefresh,
  redirect: (context, state) {
    final loc = state.matchedLocation;
    // admin.koalatutor.com → her zaman /admin (onboarding/auth gate'i atla).
    if (isAdminHost) {
      return loc == '/admin' ? null : '/admin';
    }
    debugPrint(
        '[GoRouter] redirect: loc=$loc, onboardingComplete=$onboardingComplete, authReady=$_authReady, authed=$_isAuthed');
    // Auth ve onboarding sayfalarına her zaman izin ver
    if (loc == '/auth' ||
        loc == '/onboarding' ||
        loc == '/test-photo' ||
        loc == '/evlumba-magic') return null;
    // Onboarding tamamlanmadıysa ve ana sayfa/alt sayfalardaysa → / 'a (OnboardingScreen)
    if (!onboardingComplete && loc != '/') return '/';
    // 2026-06-02: Login duvarı. REQUIRE_LOGIN=true iken onboarding'i geçmiş
    // ama giriş yapmamış/anonim kullanıcı → /auth. Auth henüz restore
    // edilmediyse (ilk frame) yönlendirme yapma; authRefresh ile redirect
    // restore tamamlanınca tekrar çalışır → gerçek kullanıcı login'e fırlamaz.
    if (Env.requireLogin && onboardingComplete && _authReady && !_isAuthed) {
      return '/auth';
    }
    return null;
  },
  routes: [
    // ─── Ana Shell (Home/Chat/Swipe/Projeler 4 sekme) veya Onboarding ───
    GoRoute(
      path: '/',
      builder: (context, state) {
        if (!onboardingComplete) return const OnboardingScreen();
        return const MainShell();
      },
    ),

    // ─── Auth (giriş ekranı) ───
    GoRoute(
      path: '/auth',
      builder: (context, state) => const AuthEntryScreen(mode: AuthFlowMode.login),
    ),

    // ─── Evlumba magic link hedefi (e-postadaki bağlantı) ───
    GoRoute(
      path: '/evlumba-magic',
      builder: (context, state) => EvlumbaMagicScreen(
        token: state.uri.queryParameters['token'] ?? '',
      ),
    ),

    // ─── Ana sekmeler (push ile açılır, geri butonu ile dönülür) ───
    GoRoute(
      path: '/explore',
      builder: (context, state) => const ExploreScreen(),
    ),
    GoRoute(
      path: '/saved',
      builder: (context, state) => const SavedScreenV2(),
    ),
    GoRoute(
      path: '/chat',
      builder: (context, state) => const ChatListScreen(),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/notifications',
      builder: (context, state) => const NotificationsFeedScreen(),
    ),
    GoRoute(
      path: '/style-profile',
      builder: (context, state) => const StyleProfileScreen(),
    ),
    GoRoute(
      path: '/style-discovery',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return StyleDiscoveryScreen(
          entryPoint: extra?['entryPoint'] as String? ?? 'manual',
        );
      },
    ),
    // Mekan akışı içi "zevkimi keşfet" — caller `Navigator.pop` ile
    // `SwipeResult?` alır.
    GoRoute(
      path: '/swipe',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return mekan_swipe.SwipeScreen(
          roomTypeHint: extra?['roomTypeHint'] as String?,
        );
      },
    ),

    // ─── Test: auto-load bundled photo for analysis ───
    GoRoute(
      path: '/test-photo',
      builder: (context, state) => const ChatDetailScreen(
        intent: KoalaIntent.photoAnalysis,
        initialText: 'Bu odayı analiz et',
        testAssetPhoto: true,
      ),
    ),

    // ─── Detay ekranları ───
    GoRoute(
      path: '/chat/ai',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return ChatDetailScreen(
          chatId: extra?['chatId'] as String?,
          initialText: extra?['initialText'] as String?,
          pendingImageUrl: extra?['pendingImageUrl'] as String?,
        );
      },
    ),
    GoRoute(
      path: '/chat/ai/:sessionId',
      builder: (context, state) => ChatDetailScreen(
        chatId: state.pathParameters['sessionId'],
      ),
    ),
    GoRoute(
      path: '/chat/dm/:conversationId',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        // "new" sentinel → lazy conversation creation. designerId ile açılır,
        // ilk mesaj gönderilince _ensureConversation() conv'u yaratır. Bu
        // sayede "Sor" butonu tıklanışında `getOrCreateConversation` API
        // çağrısını beklemeden navigation animasyonu başlar (500-1500ms
        // kazanç). ConversationDetailScreen'in lazy mode'u zaten mevcut.
        final convParam = state.pathParameters['conversationId']!;
        final conversationId = convParam == 'new' ? null : convParam;
        return ConversationDetailScreen(
          conversationId: conversationId,
          designerId: extra?['designerId'] as String?,
          designerName: extra?['designerName'] as String? ?? 'Tasarımcı',
          designerAvatarUrl: extra?['designerAvatarUrl'] as String?,
          projectTitle: extra?['projectTitle'] as String?,
          unreadOnEntry: extra?['unreadOnEntry'] as int?,
          pendingDesign: extra?['pendingDesign'] as Map<String, dynamic>?,
        );
      },
    ),
    GoRoute(
      path: '/designers',
      builder: (context, state) => const DesignersScreen(),
    ),
    GoRoute(
      path: '/designer/:id',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return DesignerProfileScreen(
          designerId: state.pathParameters['id']!,
          designerName: extra?['designerName'] as String?,
        );
      },
    ),
    GoRoute(
      // Projeler — AI tasarım koleksiyonu (yeni). Eski /collections tutuluyor
      // ama uygulama içi yönlendirme buna gidiyor.
      path: '/collections',
      builder: (context, state) => const ProjelerScreen(),
    ),
    GoRoute(
      path: '/projeler',
      builder: (context, state) => const ProjelerScreen(),
    ),
    GoRoute(
      path: '/collections-legacy',
      builder: (context, state) => const CollectionsScreen(),
    ),
    GoRoute(
      path: '/notifications',
      builder: (context, state) => const NotificationsScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/admin',
      builder: (context, state) => const AdminShell(),
    ),
    GoRoute(
      path: '/my-designs',
      builder: (context, state) => const MyDesignsScreen(),
    ),
  ],
);
