import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../views/home_screen.dart';
import '../../views/explore_screen.dart';
import '../../views/saved/saved_screen_v2.dart';
import '../../views/chat_list_screen.dart';
import '../../views/profile_screen.dart';
import '../../views/chat_detail_screen.dart';
import '../../services/koala_ai_service.dart';
import '../../views/conversation_detail_screen.dart';
import '../../views/designers_screen.dart';
import '../../views/collections_screen.dart';
import '../../views/notifications_screen.dart';
import '../../views/onboarding_screen.dart';
import '../../views/style_discovery_screen.dart';
import '../../views/style_profile_screen.dart';
import '../../views/mekan/swipe_screen.dart' as mekan_swipe;
import '../../views/designer_profile_screen.dart';
import '../../views/auth_common.dart';
import '../../views/auth_entry_screen.dart';
import '../../views/admin/admin_shell.dart';
import '../../views/my_designs/my_designs_screen.dart';

/// Onboarding tamamlandı mı? AuthGate ve goToHome tarafından set ediliyor.
bool onboardingComplete = false;

/// Uygulama başlarken SharedPreferences'dan yükle.
Future<void> initRouterState() async {
  final prefs = await SharedPreferences.getInstance();
  onboardingComplete = prefs.getBool('onboarding_done') ?? false;
}

/// Koala app router — Hub-style, ShellRoute yok.
/// Home ekranı hub, diğer ekranlar push ile açılır.
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  debugLogDiagnostics: false,
  redirect: (context, state) {
    final loc = state.matchedLocation;
    debugPrint('[GoRouter] redirect: loc=$loc, onboardingComplete=$onboardingComplete');
    // Auth ve onboarding sayfalarına her zaman izin ver
    if (loc == '/auth' || loc == '/onboarding' || loc == '/test-photo') return null;
    // Onboarding tamamlanmadıysa ve ana sayfa/alt sayfalardaysa → / 'a (OnboardingScreen)
    if (!onboardingComplete && loc != '/') return '/';
    return null;
  },
  routes: [
    // ─── Hub (Home) veya Onboarding ───
    GoRoute(
      path: '/',
      builder: (context, state) {
        if (!onboardingComplete) return const OnboardingScreen();
        final openPull = state.uri.queryParameters['openPull'] == '1';
        return HomeScreen(openStyleDiscovery: openPull);
      },
    ),

    // ─── Auth (giriş ekranı) ───
    GoRoute(
      path: '/auth',
      builder: (context, state) => const AuthEntryScreen(mode: AuthFlowMode.login),
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
      path: '/collections',
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
