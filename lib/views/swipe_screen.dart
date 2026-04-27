import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/swipe_feed_provider.dart';
import '../widgets/swipe/feed_swipe_deck.dart';
import '../widgets/swipe/swipe_onboarding_overlay.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Fullscreen swipe discovery route (`/swipe`).
///
/// Home's Silent Hero Deck is the ambient surface — tapping it pushes this
/// route, which is the full experience: the deck dominates the viewport, a
/// slim top bar carries only the close affordance, and the system chrome
/// steps out of the way for the duration.
///
/// We intentionally do NOT present a bottom nav. The screen is a focused
/// single-task surface; nav lives in the home hub.
class SwipeScreen extends ConsumerStatefulWidget {
  const SwipeScreen({super.key});

  @override
  ConsumerState<SwipeScreen> createState() => _SwipeScreenState();
}

class _SwipeScreenState extends ConsumerState<SwipeScreen>
    with WidgetsBindingObserver {
  bool _showOnboarding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Immersive feel — dim the system overlays to let the deck breathe.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOnboardingFlag());
  }

  Future<void> _checkOnboardingFlag() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('koala.swipe_onboarding_seen.v1') ?? false;
    if (!seen && mounted) {
      setState(() => _showOnboarding = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Drain anything that piled up while backgrounded (flaky wifi, lock
      // screen triggered before we could flush).
      ref.read(swipeFeedProvider.notifier).drainPending();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
          tooltip: 'Kapat',
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            tooltip: 'Yenile',
            onPressed: () =>
                ref.read(swipeFeedProvider.notifier).refresh(),
          ),
        ],
      ),
      body: Stack(
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFBF8F3), Color(0xFFF1EDE6)],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: FeedSwipeDeck(
                            // Context tag so server-side rings can tell
                            // fullscreen swipes from home-strip peeks.
                            context: 'feed',
                            showActions: true,
                          ),
                        ),
                      ),
                    ),
                    _QueueHint(textTheme: theme.textTheme),
                  ],
                ),
              ),
            ),
          ),
          if (_showOnboarding)
            Positioned.fill(
              child: SwipeOnboardingOverlay(
                onDismissed: () => setState(() => _showOnboarding = false),
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact footer that surfaces the current ring of the top card. It is
/// quiet by design — the user's attention should stay on the card. The
/// ring exposes *why* they're seeing this (e.g. "yeni" for fresh, "senin
/// için" for exploit) without leaking the word "algorithm."
/// A secondary reason line adds transparency without overwhelming the UI.
class _QueueHint extends ConsumerWidget {
  const _QueueHint({required this.textTheme});
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(swipeFeedProvider);
    final card = state.current;
    if (card == null) return const SizedBox(height: 16);

    final label = _ringLabel(card.ring);
    if (label == null) return const SizedBox(height: 16);

    final reason = _ringReason(card.ring);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: Colors.black45,
              letterSpacing: 1.1,
            ),
          ),
          if (reason != null) ...[
            const SizedBox(height: 4),
            Text(
              reason,
              style: textTheme.labelSmall?.copyWith(
                fontSize: 11,
                color: Colors.black38,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? _ringLabel(String ring) {
    switch (ring) {
      case 'exploit':
        return 'SENİN İÇİN';
      case 'explore':
        return 'KEŞFET';
      case 'fresh':
        return 'YENİ';
      case 'rare':
        return 'NADİR';
      default:
        return null;
    }
  }

  String? _ringReason(String ring) {
    switch (ring) {
      case 'exploit':
        return 'Beğenilerine yakın bir öneri';
      case 'explore':
        return 'Keşfetmeni istediğimiz bir yön';
      case 'fresh':
        return 'Yeni gelen kartlardan';
      case 'rare':
        return 'Az görülen bir kart';
      default:
        return null;
    }
  }
}
