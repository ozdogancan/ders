import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'feed_swipe_deck.dart';

/// The "Silent Hero Deck" — home's centrepiece.
///
/// Design decisions — all three came from a direct product call:
///   1. No label. The deck itself is the affordance; adding "Tarzını
///      Keşfet" would cheapen it to a button.
///   2. Interactive. Swiping on home advances the same shared provider
///      state used by the fullscreen `/swipe` screen, so users can dabble
///      on home and continue seamlessly in fullscreen without losing the
///      deck position.
///   3. Tapping a card pushes to fullscreen. The touch is generous — the
///      whole card area is the target — but a drag-swipe always wins over
///      a tap, so casual exploration never accidentally routes.
class HomeHeroDeck extends ConsumerWidget {
  const HomeHeroDeck({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 420,
          maxHeight: 440,
        ),
        child: FeedSwipeDeck(
          context: 'home_strip',
          showActions: false,
          maxVisible: 3,
          preferredAspectRatio: 4 / 5,
          onCardTap: (_) {
            // Fullscreen takes over — the provider is keepAlive so the
            // cursor survives the nav.
            context.push('/swipe');
          },
          onExhausted: () {
            // Home stays silent when the deck empties; the fullscreen
            // route surfaces the empty state if the user opts in.
          },
        ),
      ),
    );
  }
}
