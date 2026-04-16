import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/koala_card.dart';
import '../services/analytics_service.dart';
import '../services/connectivity_service.dart';
import '../services/koala_feed_service.dart';
import '../services/swipe_queue.dart';

/// ─── Service provider ──────────────────────────────────────────
///
/// Single instance so the underlying http.Client is reused. `keepAlive`
/// because swipe sessions jump between hub and fullscreen; tearing the
/// client down mid-session would force a reconnect for the very next
/// feed fetch.
final koalaFeedServiceProvider = Provider<KoalaFeedService>((ref) {
  final service = KoalaFeedService();
  ref.onDispose(service.dispose);
  return service;
});

/// ─── State ─────────────────────────────────────────────────────

enum SwipeFeedStatus { idle, loading, ready, exhausted, error }

@immutable
class SwipeFeedState {
  const SwipeFeedState({
    required this.cards,
    required this.cursor,
    required this.status,
    this.error,
    this.lastFetchedAt,
    this.pendingUndo,
  });

  /// All cards fetched this session, newest appended to the tail.
  final List<KoalaCard> cards;

  /// Index of the card currently on top of the deck. `cursor == cards.length`
  /// means the deck is empty and we're waiting on a refill.
  final int cursor;

  final SwipeFeedStatus status;
  final Object? error;
  final DateTime? lastFetchedAt;

  /// The most recent swipe, held briefly so the UI can surface an "undo"
  /// control. Cleared on a new swipe or an explicit [SwipeFeedNotifier.undo].
  final UndoEntry? pendingUndo;

  /// Cards still ahead of the cursor. Safe to call when `cards` is empty.
  List<KoalaCard> get remaining =>
      cursor >= cards.length ? const [] : cards.sublist(cursor);

  KoalaCard? get current =>
      cursor < cards.length ? cards[cursor] : null;

  KoalaCard? get peek =>
      cursor + 1 < cards.length ? cards[cursor + 1] : null;

  int get remainingCount => (cards.length - cursor).clamp(0, cards.length);

  static const initial = SwipeFeedState(
    cards: [],
    cursor: 0,
    status: SwipeFeedStatus.idle,
  );

  SwipeFeedState copyWith({
    List<KoalaCard>? cards,
    int? cursor,
    SwipeFeedStatus? status,
    Object? error,
    DateTime? lastFetchedAt,
    Object? pendingUndo = _undefined,
  }) {
    return SwipeFeedState(
      cards: cards ?? this.cards,
      cursor: cursor ?? this.cursor,
      status: status ?? this.status,
      error: error,
      lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
      pendingUndo: identical(pendingUndo, _undefined)
          ? this.pendingUndo
          : pendingUndo as UndoEntry?,
    );
  }
}

/// Sentinel for copyWith to distinguish "unset" from explicit null, so the
/// caller can *clear* pendingUndo by passing null.
const Object _undefined = Object();

class UndoEntry {
  UndoEntry({
    required this.card,
    required this.direction,
    required this.idempotencyKey,
    required this.swipedAt,
  });

  final KoalaCard card;
  final SwipeDirection direction;
  final String idempotencyKey;
  final DateTime swipedAt;
}

/// ─── Notifier ──────────────────────────────────────────────────

class SwipeFeedNotifier extends Notifier<SwipeFeedState> {
  /// Prefetch trigger: when remaining cards drop to this count, we start
  /// a background load. 5 is enough to hide the round-trip even on a slow
  /// network at a fast swipe rate (~1 card/sec).
  static const int _prefetchThreshold = 5;

  /// Per-batch request size. Matches the server clamp (max 50) but stays
  /// small enough to keep the first paint cheap on cold-start.
  static const int _batchSize = 30;

  /// How long an undo stays available after a swipe. Past this, the card
  /// scrolls out of affordance.
  static const Duration _undoWindow = Duration(seconds: 6);

  bool _fetchInFlight = false;
  Timer? _undoExpiryTimer;
  final Queue<String> _dedupeIds = Queue<String>();
  static const int _dedupeCap = 500;

  // Connectivity listener — drains the offline queue when the device comes
  // back online. Detached in onDispose so nothing leaks when the provider
  // is torn down (e.g. after user logout).
  VoidCallback? _connListener;

  @override
  SwipeFeedState build() {
    void onConnChanged() {
      if (ConnectivityService.status.value) {
        // Fire and forget — queue handles its own errors.
        unawaited(_svc.drainQueue());
      }
    }

    ConnectivityService.status.addListener(onConnChanged);
    _connListener = onConnChanged;

    ref.onDispose(() {
      _undoExpiryTimer?.cancel();
      if (_connListener != null) {
        ConnectivityService.status.removeListener(_connListener!);
        _connListener = null;
      }
    });
    return SwipeFeedState.initial;
  }

  KoalaFeedService get _svc => ref.read(koalaFeedServiceProvider);

  /// Initial load. Safe to call repeatedly — becomes a no-op while a fetch
  /// is in flight or the deck already has cards to show.
  Future<void> ensureLoaded() async {
    if (state.status == SwipeFeedStatus.loading) return;
    if (state.remainingCount > 0) return;
    await _fetch(initial: true);
  }

  /// Force a fresh fetch, discarding the current deck. Used for pull-to-
  /// refresh and manual "start over" affordances.
  Future<void> refresh() async {
    _dedupeIds.clear();
    state = SwipeFeedState.initial.copyWith(status: SwipeFeedStatus.loading);
    await _fetch(initial: true);
  }

  Future<void> _fetch({required bool initial}) async {
    if (_fetchInFlight) return;
    _fetchInFlight = true;
    if (initial) {
      state = state.copyWith(status: SwipeFeedStatus.loading, error: null);
    }

    try {
      final fetched = await _svc.fetchFeed(limit: _batchSize);

      // Dedupe against everything we've ever appended in this session. The
      // server's 90-day no-repeat filter usually handles this, but a just-
      // recorded swipe racing a prefetch could briefly reappear.
      final novel = <KoalaCard>[];
      for (final c in fetched) {
        if (_dedupeIds.contains(c.id)) continue;
        _rememberId(c.id);
        novel.add(c);
      }

      final newCards = initial
          ? novel
          : [...state.cards, ...novel];
      final newCursor = initial ? 0 : state.cursor;

      if (newCards.isEmpty) {
        state = state.copyWith(
          cards: newCards,
          cursor: newCursor,
          status: SwipeFeedStatus.exhausted,
          lastFetchedAt: DateTime.now(),
          error: null,
        );
        unawaited(Analytics.log('swipe_feed_exhausted', {
          'initial': initial,
        }));
      } else {
        state = state.copyWith(
          cards: newCards,
          cursor: newCursor,
          status: SwipeFeedStatus.ready,
          lastFetchedAt: DateTime.now(),
          error: null,
        );
      }
    } catch (e, st) {
      debugPrint('SwipeFeedNotifier fetch failed: $e\n$st');
      state = state.copyWith(
        status: initial ? SwipeFeedStatus.error : state.status,
        error: e,
      );
      unawaited(Analytics.log('swipe_feed_error', {
        'initial': initial,
        'error': e.toString(),
      }));
    } finally {
      _fetchInFlight = false;
    }
  }

  void _rememberId(String id) {
    _dedupeIds.add(id);
    while (_dedupeIds.length > _dedupeCap) {
      _dedupeIds.removeFirst();
    }
  }

  /// Record a swipe on the top card and advance the cursor.
  ///
  /// The network call is fire-and-forget through [SwipeQueue], so the UI
  /// never stalls on a slow POST. An idempotency key is generated here so
  /// both the enqueue and the optional undo reference the same row.
  Future<void> swipe(
    SwipeDirection direction, {
    double? velocity,
    int? dwellTimeMs,
    String context = 'feed',
  }) async {
    final card = state.current;
    if (card == null) return;

    final key = SwipeQueue.newIdempotencyKey();

    // Advance UI state first so the swipe feels instant even on poor
    // networks.
    _undoExpiryTimer?.cancel();
    state = state.copyWith(
      cursor: state.cursor + 1,
      pendingUndo: UndoEntry(
        card: card,
        direction: direction,
        idempotencyKey: key,
        swipedAt: DateTime.now(),
      ),
    );

    _undoExpiryTimer = Timer(_undoWindow, () {
      // Only clear if the entry is still the one we just set.
      if (state.pendingUndo?.idempotencyKey == key) {
        state = state.copyWith(pendingUndo: null);
      }
    });

    // Background: record the swipe + trigger a refill if the deck is
    // thinning. Errors are logged inside the service/queue and don't
    // propagate — the on-disk queue is the source of truth.
    unawaited(
      _svc.recordSwipe(
        cardId: card.id,
        direction: direction,
        context: context,
        swipeVelocity: velocity,
        dwellTimeMs: dwellTimeMs,
        idempotencyKey: key,
      ),
    );

    unawaited(Analytics.log('swipe_card', {
      'direction': direction.wire,
      'ring': card.ring,
      'context': context,
      'card_id': card.id,
      'velocity': ?velocity,
      'dwell_ms': ?dwellTimeMs,
    }));

    if (state.remainingCount <= _prefetchThreshold &&
        state.status != SwipeFeedStatus.loading) {
      unawaited(_fetch(initial: false));
    }

    if (state.remainingCount == 0 &&
        state.status != SwipeFeedStatus.loading) {
      // Fetch didn't populate anything — flag exhausted so the UI can
      // surface an empty state.
      state = state.copyWith(status: SwipeFeedStatus.exhausted);
    }
  }

  /// Walk the cursor back one step and clear the pending-undo marker.
  ///
  /// The on-server swipe is *not* cancelled — the cursor rewind is purely
  /// a client affordance. A production rollout will likely want a `DELETE`
  /// endpoint keyed on the idempotency id; leaving that as a v2 concern so
  /// this lands small.
  bool undo() {
    final entry = state.pendingUndo;
    if (entry == null) return false;
    if (state.cursor == 0) return false;

    _undoExpiryTimer?.cancel();
    state = state.copyWith(
      cursor: state.cursor - 1,
      pendingUndo: null,
    );
    unawaited(Analytics.log('swipe_undo', {
      'card_id': entry.card.id,
      'original_direction': entry.direction.wire,
    }));
    return true;
  }

  /// Drain any offline queue — call on app resume / connectivity regained.
  Future<void> drainPending() => _svc.drainQueue();
}

/// Global, keep-alive swipe feed. We intentionally don't `autoDispose` so
/// hopping between `/` (Silent Hero Deck) and `/swipe` (fullscreen) keeps
/// the same deck + cursor — the user's context should survive the nav.
final swipeFeedProvider =
    NotifierProvider<SwipeFeedNotifier, SwipeFeedState>(
  SwipeFeedNotifier.new,
);
