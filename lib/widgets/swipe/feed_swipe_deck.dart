import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/koala_card.dart';
import '../../providers/swipe_feed_provider.dart';
import 'swipe_math.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Stack-of-cards deck that drives [swipeFeedProvider].
///
/// Renders up to [maxVisible] cards (top one interactive, rest as depth
/// hints), wires drag + button swipes into the provider, and instruments
/// dwell + fling velocity so the server can learn from hesitation too.
///
/// Modern interaction layer:
///  - Horizontal drag → like/pass (right/left)
///  - Upward drag → "save" commit with its own overlay + vertical eject
///  - Spring-simulated snap-back so below-threshold releases feel physical
///  - Progressive haptic escalation (approach → near-commit → commit)
///  - Long-press top card → peek mode (blur + floating actions)
///  - Hero tag on top card so home → /swipe feels continuous
///
/// Shared between the fullscreen `/swipe` route and the home Silent Hero
/// Deck — the home variant just constrains the size and hides the bottom
/// action bar via [showActions].
class FeedSwipeDeck extends ConsumerStatefulWidget {
  const FeedSwipeDeck({
    super.key,
    this.maxVisible = 3,
    this.showActions = true,
    this.context = 'feed',
    this.onCardTap,
    this.onExhausted,
    this.preferredAspectRatio = 3 / 4,
    this.heroTagPrefix = 'swipe-hero',
  });

  final int maxVisible;
  final bool showActions;
  final String context;
  final ValueChanged<KoalaCard>? onCardTap;
  final VoidCallback? onExhausted;
  final double preferredAspectRatio;

  /// Prefix for the Hero tag on the interactive top card. Keep identical
  /// between home and /swipe instances so the card animates between the
  /// two routes.
  final String heroTagPrefix;

  @override
  ConsumerState<FeedSwipeDeck> createState() => _FeedSwipeDeckState();
}

class _FeedSwipeDeckState extends ConsumerState<FeedSwipeDeck>
    with TickerProviderStateMixin {
  // Exit animation (card flying off after a commit).
  late final AnimationController _exitController;

  // Spring-based snap-back for below-threshold releases.
  late final AnimationController _snapController;
  double _snapFromDx = 0;
  double _snapFromDy = 0;

  // Raw drag offsets. Vertical dampening happens at render time (only when
  // the gesture is not a save-intent upward swipe) so the intent detector
  // keeps access to the unscaled signal.
  double _dragDx = 0;
  double _dragDy = 0;

  // Exit state.
  KoalaCard? _exitingCard;
  SwipeAxis _exitAxis = SwipeAxis.none;
  double _exitStartDx = 0;
  double _exitTargetDx = 0;
  double _exitStartDy = 0;
  double _exitTargetDy = 0;

  // Dwell measurement — reset whenever the top card changes.
  String? _dwellCardId;
  DateTime? _dwellStart;

  // Progressive haptic tracking — only fire when the level escalates so a
  // hesitant drag doesn't buzz the device to death.
  SwipeHaptic _lastHaptic = SwipeHaptic.idle;

  // Long-press peek state.
  bool _peekActive = false;

  bool _exhaustedFired = false;
  bool _didBootstrapLoad = false;

  @override
  void initState() {
    super.initState();
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..addStatusListener(_handleExitStatus);

    _snapController = AnimationController.unbounded(vsync: this)
      ..addListener(_handleSnapTick);
  }

  @override
  void dispose() {
    _exitController.removeStatusListener(_handleExitStatus);
    _exitController.dispose();
    _snapController.removeListener(_handleSnapTick);
    _snapController.dispose();
    super.dispose();
  }

  // ─── Animation listeners ─────────────────────────────────────────

  void _handleSnapTick() {
    // SpringSimulation starts at 1.0 (full drag offset) and decays toward
    // 0.0 with oscillation — we use its value as a "fraction of original
    // drag still in effect".
    final t = _snapController.value.clamp(-0.2, 1.0);
    setState(() {
      _dragDx = _snapFromDx * t;
      _dragDy = _snapFromDy * t;
    });
  }

  void _handleExitStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final card = _exitingCard;
    if (card == null) return;

    final axis = _exitAxis;
    final dwellMs = _dwellStart != null
        ? DateTime.now().difference(_dwellStart!).inMilliseconds
        : null;

    final dir = switch (axis) {
      SwipeAxis.right => SwipeDirection.right,
      SwipeAxis.left => SwipeDirection.left,
      SwipeAxis.up => SwipeDirection.up,
      SwipeAxis.none => SwipeDirection.right, // unreachable
    };

    ref.read(swipeFeedProvider.notifier).swipe(
          dir,
          context: widget.context,
          dwellTimeMs: dwellMs,
        );

    setState(() {
      _exitingCard = null;
      _exitAxis = SwipeAxis.none;
      _exitStartDx = 0;
      _exitTargetDx = 0;
      _exitStartDy = 0;
      _exitTargetDy = 0;
      _dragDx = 0;
      _dragDy = 0;
      _lastHaptic = SwipeHaptic.idle;
      _exitController.reset();
    });
  }

  // ─── Lifecycle helpers ─────────────────────────────────────────

  void _ensureBootstrap() {
    if (_didBootstrapLoad) return;
    _didBootstrapLoad = true;
    scheduleMicrotask(() {
      if (!mounted) return;
      ref.read(swipeFeedProvider.notifier).ensureLoaded();
    });
  }

  void _trackDwell(KoalaCard? top) {
    if (top == null) {
      _dwellCardId = null;
      _dwellStart = null;
      return;
    }
    if (top.id == _dwellCardId) return;
    _dwellCardId = top.id;
    _dwellStart = DateTime.now();
    // Fresh card = fresh haptic budget.
    _lastHaptic = SwipeHaptic.idle;
  }

  // ─── Gesture pipeline ──────────────────────────────────────────

  void _onPanStart(DragStartDetails details) {
    if (_snapController.isAnimating) _snapController.stop();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_exitController.isAnimating) return;
    if (_peekActive) return;

    final nextDx = _dragDx + details.delta.dx;
    final nextDy = _dragDy + details.delta.dy;

    // Use the dominant axis to drive the haptic ladder so both save and
    // like/pass get proportional feedback.
    final saveIntent =
        SwipeMath.isSaveIntent(dragDx: nextDx, dragDy: nextDy);
    final absRatio = saveIntent
        ? SwipeMath.saveRatio(nextDy)
        : SwipeMath.swipeRatio(nextDx).abs();

    final level = SwipeMath.hapticLevel(absRatio);
    if (_escalated(level)) {
      _fireHaptic(level);
      _lastHaptic = level;
    } else if (level == SwipeHaptic.idle) {
      _lastHaptic = SwipeHaptic.idle;
    }

    setState(() {
      _dragDx = nextDx;
      _dragDy = nextDy;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_exitController.isAnimating) return;
    if (_peekActive) return;

    final vx = details.velocity.pixelsPerSecond.dx;
    final vy = details.velocity.pixelsPerSecond.dy;

    final axis = SwipeMath.commitAxis(
      dragDx: _dragDx,
      dragDy: _dragDy,
      velocityX: vx,
      velocityY: vy,
    );

    if (axis != SwipeAxis.none) {
      _commitAxis(axis, velocityX: vx, velocityY: vy);
      return;
    }
    _springSnapBack();
  }

  bool _escalated(SwipeHaptic level) {
    return level.index > _lastHaptic.index;
  }

  void _fireHaptic(SwipeHaptic level) {
    switch (level) {
      case SwipeHaptic.approach:
        HapticFeedback.selectionClick();
      case SwipeHaptic.nearCommit:
        HapticFeedback.lightImpact();
      case SwipeHaptic.commit:
        HapticFeedback.mediumImpact();
      case SwipeHaptic.idle:
        break;
    }
  }

  void _springSnapBack() {
    _snapFromDx = _dragDx;
    _snapFromDy = _dragDy;
    // Spring decays from 1.0 → 0.0 with gentle overshoot. `stiffness`
    // dictates snappiness; `damping` controls how much it oscillates.
    final sim = SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 180, damping: 18),
      1.0,
      0.0,
      0.0,
    );
    _snapController.animateWith(sim);
  }

  // ─── Commit paths ──────────────────────────────────────────────

  /// Entry point for button-driven commits (pass/save/like buttons +
  /// programmatic triggers). Drag-driven commits go through the same path
  /// via [_commitAxis].
  void _commit(SwipeAxis axis) => _commitAxis(axis);

  void _commitAxis(SwipeAxis axis, {double velocityX = 0, double velocityY = 0}) {
    if (axis == SwipeAxis.none) return;
    if (_exitController.isAnimating) return;
    if (_snapController.isAnimating) _snapController.stop();

    final state = ref.read(swipeFeedProvider);
    final card = state.current;
    if (card == null) return;

    // Always end the commit with a medium bump even if the haptic ladder
    // already fired — commit should feel conclusive.
    if (_lastHaptic != SwipeHaptic.commit) {
      HapticFeedback.mediumImpact();
    }

    final media = MediaQuery.of(context);
    final width = media.size.width;
    final height = media.size.height;

    setState(() {
      _exitingCard = card;
      _exitAxis = axis;
      switch (axis) {
        case SwipeAxis.right:
        case SwipeAxis.left:
          final liked = axis == SwipeAxis.right;
          _exitStartDx =
              SwipeMath.exitStartDx(currentDragDx: _dragDx, liked: liked);
          _exitTargetDx =
              SwipeMath.exitTargetDx(screenWidth: width, liked: liked);
          _exitStartDy = _dragDy;
          _exitTargetDy = _dragDy * 0.3; // drift toward center as it flies
        case SwipeAxis.up:
          _exitStartDx = _dragDx;
          _exitTargetDx = _dragDx * 0.2;
          _exitStartDy = SwipeMath.saveExitStartDy(currentDragDy: _dragDy);
          _exitTargetDy = SwipeMath.exitTargetDy(screenHeight: height);
        case SwipeAxis.none:
          break;
      }
    });

    _exitController.forward(from: 0);
  }

  // ─── Peek mode ─────────────────────────────────────────────────

  void _enterPeek() {
    if (_peekActive) return;
    if (_exitController.isAnimating) return;
    if (ref.read(swipeFeedProvider).current == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _peekActive = true;
      // Any in-flight snap stops here — peek should not fight the spring.
      if (_snapController.isAnimating) _snapController.stop();
      _dragDx = 0;
      _dragDy = 0;
      _lastHaptic = SwipeHaptic.idle;
    });
  }

  void _exitPeek() {
    if (!_peekActive) return;
    setState(() => _peekActive = false);
  }

  void _peekCommit(SwipeAxis axis) {
    _exitPeek();
    // Wait one frame so the peek overlay has unwound before the card flies.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _commit(axis);
    });
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _ensureBootstrap();
    final state = ref.watch(swipeFeedProvider);
    final visible = <KoalaCard>[
      ?_exitingCard,
      ...state.remaining.take(widget.maxVisible),
    ];

    final peek = state.peek;
    if (peek != null) {
      precacheImage(
        CachedNetworkImageProvider(peek.displayUrl),
        context,
      );
    }

    _trackDwell(state.current);

    if (state.status == SwipeFeedStatus.exhausted && visible.isEmpty) {
      if (!_exhaustedFired) {
        _exhaustedFired = true;
        widget.onExhausted?.call();
      }
      return _EmptyDeck(
        onRetry: () => ref.read(swipeFeedProvider.notifier).refresh(),
      );
    }
    if (state.status == SwipeFeedStatus.ready || visible.isNotEmpty) {
      _exhaustedFired = false;
    }

    if (state.status == SwipeFeedStatus.loading && visible.isEmpty) {
      return const _DeckSkeleton();
    }

    if (state.status == SwipeFeedStatus.error && visible.isEmpty) {
      return _ErrorDeck(
        onRetry: () => ref.read(swipeFeedProvider.notifier).refresh(),
      );
    }

    return AspectRatio(
      aspectRatio: widget.preferredAspectRatio,
      child: AnimatedBuilder(
        animation: _exitController,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              for (int i = visible.length - 1; i >= 0; i--)
                _buildCardLayer(
                  card: visible[i],
                  depth: i,
                  isTop: i == 0,
                ),
              if (widget.showActions)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 12,
                  child: _ActionBar(
                    onPass: () => _commit(SwipeAxis.left),
                    onLike: () => _commit(SwipeAxis.right),
                    onSave: () => _commit(SwipeAxis.up),
                    onUndo: state.pendingUndo == null
                        ? null
                        : () {
                            HapticFeedback.lightImpact();
                            ref.read(swipeFeedProvider.notifier).undo();
                          },
                  ),
                ),
              if (_peekActive && state.current != null)
                _PeekOverlay(
                  card: state.current!,
                  heroTag: '${widget.heroTagPrefix}-${state.current!.id}',
                  aspectRatio: widget.preferredAspectRatio,
                  onDismiss: _exitPeek,
                  onPass: () => _peekCommit(SwipeAxis.left),
                  onSave: () => _peekCommit(SwipeAxis.up),
                  onLike: () => _peekCommit(SwipeAxis.right),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCardLayer({
    required KoalaCard card,
    required int depth,
    required bool isTop,
  }) {
    final isExiting = identical(card, _exitingCard);

    double dx;
    double dy;
    double rotation;
    double scale;
    double opacity = 1;

    if (isExiting) {
      final t = _exitController.value;
      dx = SwipeMath.lerp(_exitStartDx, _exitTargetDx, t);
      dy = SwipeMath.lerp(_exitStartDy, _exitTargetDy, t);
      rotation = _exitAxis == SwipeAxis.up
          ? _dragDx * SwipeMath.rotationPerPx * (1 - t) * 0.5
          : SwipeMath.rotationForDx(dx);
      scale = 1.0;
      if (_exitAxis == SwipeAxis.up) {
        opacity = (1 - t * 0.4).clamp(0.0, 1.0);
      }
    } else if (isTop) {
      final saveIntent =
          SwipeMath.isSaveIntent(dragDx: _dragDx, dragDy: _dragDy);
      dx = _dragDx;
      // When the user is intentionally swiping up, follow the finger
      // 1:1. Otherwise damp vertical noise so the card doesn't wobble
      // during a horizontal drag.
      dy = saveIntent ? _dragDy : SwipeMath.dampenedDy(_dragDy);
      rotation = saveIntent ? 0 : SwipeMath.rotationForDx(dx);
      scale = _peekActive ? 0.98 : 1.0;
    } else {
      dx = 0;
      dy = 8.0 * depth.toDouble();
      rotation = 0;
      scale = 1.0 - (0.04 * depth);
    }

    // Overlay ratios. Only live on the top card during drag, not on
    // depth layers and not during exit (exit has its own fade).
    final likeRatio = isTop && !isExiting ? SwipeMath.swipeRatio(dx) : 0.0;
    final saveR =
        isTop && !isExiting ? SwipeMath.saveRatio(_dragDy) : 0.0;

    Widget face = _CardFace(
      card: card,
      likeOpacity: likeRatio > 0 ? likeRatio : 0,
      nopeOpacity: likeRatio < 0 ? -likeRatio : 0,
      saveOpacity: saveR,
    );

    // Hero-wrap only the current interactive top card (not exit, not
    // depth layers, not peek — peek has its own Hero with matching tag).
    //
    // INVARIANT: at most one Hero with tag `${prefix}-${cardId}` exists
    // in this subtree per build. The `!_peekActive` guard here is
    // mutually exclusive with the `_peekActive && current != null`
    // render guard around `_PeekOverlay` in `build()`. Do not remove
    // either guard without reviewing the other — Flutter asserts on
    // duplicate tags in the same subtree. Cross-route tag matching
    // (home ↔ /swipe) is *intentional* and how Hero flight works.
    if (isTop && !isExiting && !_peekActive) {
      face = Hero(
        tag: '${widget.heroTagPrefix}-${card.id}',
        createRectTween: (begin, end) =>
            MaterialRectArcTween(begin: begin, end: end),
        child: face,
      );
    }

    Widget layer = Transform.translate(
      offset: Offset(dx, dy),
      child: Transform.rotate(
        angle: rotation,
        child: Transform.scale(
          scale: scale,
          child: Opacity(opacity: opacity, child: face),
        ),
      ),
    );

    if (isTop && !isExiting && !_peekActive) {
      layer = GestureDetector(
        onTap: () => widget.onCardTap?.call(card),
        onLongPress: _enterPeek,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        behavior: HitTestBehavior.opaque,
        child: layer,
      );
    }

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !isTop || isExiting || _peekActive,
        child: layer,
      ),
    );
  }
}

/// ─── Card face ────────────────────────────────────────────────

class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.card,
    required this.likeOpacity,
    required this.nopeOpacity,
    required this.saveOpacity,
  });

  final KoalaCard card;
  final double likeOpacity;
  final double nopeOpacity;
  final double saveOpacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 40,
            offset: const Offset(0, 20),
            spreadRadius: -4,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: card.displayUrl,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 180),
            placeholder: (_, _) => const _ImagePlaceholder(),
            errorWidget: (_, _, _) => const _ImagePlaceholder(
              icon: LucideIcons.imageOff,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 140,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0),
                      Colors.black.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (card.title != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: IgnorePointer(
                child: Text(
                  card.title!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    shadows: [
                      Shadow(
                        offset: Offset(0, 1),
                        blurRadius: 3,
                        color: Colors.black45,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          _StampOverlay(opacity: likeOpacity, kind: _StampKind.like),
          _StampOverlay(opacity: nopeOpacity, kind: _StampKind.nope),
          _SaveStamp(opacity: saveOpacity),
        ],
      ),
    );
  }
}

enum _StampKind { like, nope }

class _StampOverlay extends StatelessWidget {
  const _StampOverlay({required this.opacity, required this.kind});
  final double opacity;
  final _StampKind kind;

  @override
  Widget build(BuildContext context) {
    if (opacity <= 0) return const SizedBox.shrink();
    final isLike = kind == _StampKind.like;
    final color = isLike ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    return Positioned(
      top: 32,
      left: isLike ? null : 20,
      right: isLike ? 20 : null,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.rotate(
            angle: isLike ? -0.25 : 0.25,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color, width: 3),
              ),
              child: Text(
                isLike ? 'BEĞEN' : 'GEÇ',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SaveStamp extends StatelessWidget {
  const _SaveStamp({required this.opacity});
  final double opacity;

  @override
  Widget build(BuildContext context) {
    if (opacity <= 0) return const SizedBox.shrink();
    const color = Color(0xFF2563EB);
    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color, width: 3),
                  color: Colors.white.withValues(alpha: 0.75),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(LucideIcons.bookmarkPlus,
                        color: color, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'KAYDET',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({this.icon});
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF3F2F0),
      child: Center(
        child: icon == null
            ? const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 40, color: Colors.black26),
      ),
    );
  }
}

/// ─── Peek overlay ────────────────────────────────────────────

class _PeekOverlay extends StatelessWidget {
  const _PeekOverlay({
    required this.card,
    required this.heroTag,
    required this.aspectRatio,
    required this.onDismiss,
    required this.onPass,
    required this.onSave,
    required this.onLike,
  });

  final KoalaCard card;
  final Object heroTag;
  final double aspectRatio;
  final VoidCallback onDismiss;
  final VoidCallback onPass;
  final VoidCallback onSave;
  final VoidCallback onLike;

  /// Returns true when at least one contextual field is populated.
  bool get _hasInfo =>
      card.designerName != null ||
      card.roomType != null ||
      (card.styleTags != null && card.styleTags!.isNotEmpty) ||
      (card.similarCardIds != null && card.similarCardIds!.isNotEmpty);

  @override
  // Layout (bottom → top in terms of the Stack, logical top → bottom):
  //
  //  Stack (fills the deck area)
  //  ├── BackdropFilter scrim  [tap to dismiss, always present]
  //  ├── SafeArea > Column:
  //  │     Spacer()
  //  │     ↳ Hero-wrapped enlarged card (AspectRatio-constrained)
  //  │     SizedBox(16)
  //  │     ↳ _PeekInfoPanel  (only when _hasInfo == true)
  //  │     Spacer()
  //  └── Positioned bottom-32 → Wrap of _PeekChip action chips [unchanged]
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Dismiss scrim — tapping anywhere outside the peek card closes.
          GestureDetector(
            onTap: onDismiss,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                color: Colors.black.withValues(alpha: 0.28),
              ),
            ),
          ),
          // Card + optional info panel, vertically centred with spacers.
          SafeArea(
            bottom: true,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 96),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(),
                  // Enlarged card — no gesture recognisers; scrim handles dismiss.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: AspectRatio(
                      aspectRatio: aspectRatio,
                      child: Transform.scale(
                        scale: 1.06,
                        child: Hero(
                          tag: heroTag,
                          child: _CardFace(
                            card: card,
                            likeOpacity: 0,
                            nopeOpacity: 0,
                            saveOpacity: 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_hasInfo) ...[
                    const SizedBox(height: 16),
                    _PeekInfoPanel(card: card),
                  ],
                  const Spacer(),
                ],
              ),
            ),
          ),
          // Floating action chips at the bottom of the viewport.
          Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: Center(
              child: Wrap(
                spacing: 14,
                children: [
                  _PeekChip(
                    icon: LucideIcons.x,
                    label: 'Geç',
                    color: const Color(0xFFEF4444),
                    onTap: onPass,
                  ),
                  _PeekChip(
                    icon: LucideIcons.bookmarkPlus,
                    label: 'Kaydet',
                    color: const Color(0xFF2563EB),
                    onTap: onSave,
                  ),
                  _PeekChip(
                    icon: LucideIcons.heart,
                    label: 'Beğen',
                    color: const Color(0xFF22C55E),
                    onTap: onLike,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ─── Peek info panel ─────────────────────────────────────────
///
/// Rounded frosted-glass card shown below the enlarged photo during peek
/// mode. Renders only the fields that are present on the card; if every
/// field is null/empty the panel is never instantiated (guarded by
/// [_PeekOverlay._hasInfo]).

class _PeekInfoPanel extends StatelessWidget {
  const _PeekInfoPanel({required this.card});

  final KoalaCard card;

  @override
  Widget build(BuildContext context) {
    // Clamp panel width so it doesn't stretch on wide viewports.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Designer row ─────────────────────────────
                if (card.designerName != null) ...[
                  _DesignerRow(
                    name: card.designerName!,
                    avatarUrl: card.designerAvatarUrl,
                  ),
                  const SizedBox(height: 10),
                ],
                // ── Room type + style chips ──────────────────
                if (card.roomType != null ||
                    (card.styleTags != null &&
                        card.styleTags!.isNotEmpty)) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (card.roomType != null)
                        _InfoChip(label: card.roomType!),
                      if (card.styleTags != null)
                        for (final tag in card.styleTags!.take(3))
                          _InfoChip(label: tag),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                // ── Similar cards strip ──────────────────────
                if (card.similarCardIds != null &&
                    card.similarCardIds!.isNotEmpty) ...[
                  const Text(
                    'Benzer kartlar',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 84,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: card.similarCardIds!.take(3).length,
                      separatorBuilder: (context, index) => const SizedBox(width: 8),
                      itemBuilder: (_, index) {
                        final id = card.similarCardIds![index];
                        return _SimilarMiniCard(cardId: id);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesignerRow extends StatelessWidget {
  const _DesignerRow({required this.name, this.avatarUrl});

  final String name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Avatar — network image when URL present, initial-letter fallback.
        if (avatarUrl != null)
          CircleAvatar(
            radius: 22,
            backgroundImage: CachedNetworkImageProvider(avatarUrl!),
            backgroundColor: Colors.black12,
          )
        else
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFFF1EDE6),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.black87,
                fontSize: 18,
              ),
            ),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  static const _bg = Color(0xFFF1EDE6);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _SimilarMiniCard extends StatelessWidget {
  const _SimilarMiniCard({required this.cardId});

  final String cardId;

  @override
  Widget build(BuildContext context) {
    // MVP: renders a placeholder square with the card ID initial.
    // A future iteration can hydrate the full card and show a thumbnail.
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            cardId.isNotEmpty ? cardId[0].toUpperCase() : '?',
            style: const TextStyle(
              color: Colors.black38,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _PeekChip extends StatelessWidget {
  const _PeekChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ─── Action bar / states ──────────────────────────────────────

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.onPass,
    required this.onLike,
    required this.onSave,
    required this.onUndo,
  });

  final VoidCallback onPass;
  final VoidCallback onLike;
  final VoidCallback onSave;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ActionButton(
          onPressed: onPass,
          icon: LucideIcons.x,
          color: const Color(0xFFEF4444),
          size: 56,
        ),
        const SizedBox(width: 14),
        _ActionButton(
          onPressed: onUndo,
          icon: LucideIcons.undo2,
          color: const Color(0xFFF59E0B),
          size: 42,
        ),
        const SizedBox(width: 14),
        _ActionButton(
          onPressed: onSave,
          icon: LucideIcons.bookmarkPlus,
          color: const Color(0xFF2563EB),
          size: 48,
        ),
        const SizedBox(width: 14),
        _ActionButton(
          onPressed: onLike,
          icon: LucideIcons.heart,
          color: const Color(0xFF22C55E),
          size: 56,
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.onPressed,
    required this.icon,
    required this.color,
    required this.size,
  });
  final VoidCallback? onPressed;
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Material(
      color: Colors.white,
      elevation: enabled ? 6 : 0,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            color: enabled ? color : Colors.black26,
            size: size * 0.5,
          ),
        ),
      ),
    );
  }
}

class _DeckSkeleton extends StatelessWidget {
  const _DeckSkeleton();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF3F2F0),
          borderRadius: BorderRadius.circular(28),
        ),
        child: const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    );
  }
}

class _EmptyDeck extends StatelessWidget {
  const _EmptyDeck({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF8F7F5),
          borderRadius: BorderRadius.circular(28),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.sparkles, size: 40),
            const SizedBox(height: 12),
            const Text(
              'Şimdilik bu kadar',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Yeni tasarımlar geldikçe senin için hazırlayacağız.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(LucideIcons.refreshCw),
              label: const Text('Tekrar dene'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorDeck extends StatelessWidget {
  const _ErrorDeck({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFDEDED),
          borderRadius: BorderRadius.circular(28),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.wifiOff, size: 40),
            const SizedBox(height: 12),
            const Text(
              'Bağlanamadık',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'İnternet bağlantını kontrol edip tekrar deneyebilir misin?',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(LucideIcons.refreshCw),
              label: const Text('Tekrar dene'),
            ),
          ],
        ),
      ),
    );
  }
}
