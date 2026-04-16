import 'dart:math' as math;

/// Pure swipe physics + feedback math. Kept side-effect free so it can be
/// unit-tested without a Flutter harness and reused by multiple deck widgets
/// (onboarding discovery, feed, home peek).
///
/// The constants here are the production values observed in the original
/// StyleDiscoveryScreen (lib/views/style_discovery_screen.dart) — every
/// behaviour change should update the matching test in
/// test/widgets/swipe/swipe_math_test.dart so regressions break CI loudly.
class SwipeMath {
  const SwipeMath._();

  // ─── Commit thresholds ──────────────────────────────────────────
  //
  // A drag commits when the horizontal offset or the fling velocity
  // exceeds EITHER threshold — whichever fires first wins.

  /// Horizontal drag distance (logical px) at which a release commits.
  static const double commitDragDx = 90;

  /// Fling velocity (px/s, signed) at which a release commits regardless
  /// of how far the card travelled.
  static const double commitVelocityPxPerSec = 700;

  /// Vertical (up) drag distance at which a release commits as "save".
  /// Slightly larger than the horizontal threshold because accidental
  /// up-motion during a horizontal drag is common — the extra margin
  /// keeps the save gesture deliberate.
  static const double commitDragDyUp = 140;

  /// Upward fling velocity (signed, negative = up) at which a release
  /// commits as "save" regardless of distance.
  static const double commitVelocityUpPxPerSec = -900;

  // ─── Visual coupling ────────────────────────────────────────────

  /// Rotation (radians) applied per logical px of horizontal drag.
  /// `dx=600 → ~1 rad` was the original StyleDiscovery feel.
  static const double rotationPerPx = 1 / 600;

  /// Vertical drag is damped so the card stays anchored to the horizontal
  /// axis — resists accidental up/down noise during a right/left swipe.
  static const double verticalDampening = 0.3;

  /// Like/nope overlay becomes fully opaque at this drag distance. Matches
  /// the swipeRatio=1 normalization used by the card view.
  static const double overlaySaturationDx = 120;

  /// Save overlay saturates at this upward drag distance.
  static const double overlaySaturationDyUp = 140;

  // ─── Exit animation ─────────────────────────────────────────────

  /// Target horizontal offset as a multiple of screen width when the card
  /// flies off. 1.4 keeps the card visible for the whole eject frame.
  static const double exitTargetWidthMultiplier = 1.4;

  /// Minimum start offset for an exit when the user tapped a button (no
  /// drag). Gives the animation a visible direction instead of starting at
  /// zero.
  static const double minExitStartDx = 24;

  /// Target upward offset as a multiple of screen height when the card
  /// flies up on a save commit.
  static const double exitTargetHeightMultiplier = 1.3;

  /// Minimum upward start offset (negative) for a button/tap style save.
  static const double minSaveExitStartDy = -24;

  // ─── Derived helpers ───────────────────────────────────────────

  /// Confidence multiplier driven by release velocity. A slow/hesitant
  /// drag carries less signal than a decisive flick; a button tap (v=0)
  /// is treated as a deliberate neutral signal.
  ///
  /// Bands (absolute px/s):
  ///   [0,   200) → 1.0   // button tap or near-still release
  ///   [200, 500) → 0.7   // tentative drag
  ///   [500,1000) → 1.0   // normal swipe
  ///   [1000,  ∞) → 1.3   // fast decisive flick
  static double velocityMultiplier(double absVelocity) {
    final v = absVelocity.abs();
    if (v < 200) return 1.0;
    if (v < 500) return 0.7;
    if (v < 1000) return 1.0;
    return 1.3;
  }

  /// True if a release with the given horizontal drag + velocity should
  /// commit (eject the card) rather than snap back to centre.
  ///
  /// Positive = right/like, negative = left/nope. Zero means the caller
  /// needs to inspect both fields separately (handled below).
  static int commitDirection({required double dragDx, required double velocity}) {
    if (dragDx > commitDragDx || velocity > commitVelocityPxPerSec) return 1;
    if (dragDx < -commitDragDx || velocity < -commitVelocityPxPerSec) return -1;
    return 0;
  }

  /// Rotation angle (radians) for a given horizontal drag offset.
  static double rotationForDx(double dx) => dx * rotationPerPx;

  /// Vertical drag after dampening is applied.
  static double dampenedDy(double rawDy) => rawDy * verticalDampening;

  /// Normalized [-1, 1] like/nope ratio for overlay alpha. Callers usually
  /// use `ratio > 0` for the like overlay and `ratio < 0` for the nope
  /// overlay.
  static double swipeRatio(double dx) {
    if (overlaySaturationDx <= 0) return 0;
    final r = dx / overlaySaturationDx;
    return r.clamp(-1.0, 1.0);
  }

  /// Horizontal offset where the exit animation should start from. If the
  /// current drag is tiny (button tap), we bias it away from zero so the
  /// fly-out has a visible direction.
  static double exitStartDx({required double currentDragDx, required bool liked}) {
    if (currentDragDx.abs() >= minExitStartDx) return currentDragDx;
    return liked ? minExitStartDx : -minExitStartDx;
  }

  /// Horizontal offset where the exit animation should end. Scales with
  /// screen width so the card leaves the viewport on every device.
  static double exitTargetDx({required double screenWidth, required bool liked}) {
    return screenWidth *
        (liked ? exitTargetWidthMultiplier : -exitTargetWidthMultiplier);
  }

  /// Linear interpolation used by the exit tween. `t` in [0,1].
  static double lerp(double start, double end, double t) {
    final clamped = t.clamp(0.0, 1.0);
    return start + (end - start) * clamped;
  }

  /// Haptic intensity selector: button taps and normal drags are medium,
  /// very fast flicks get a heavier bump.
  static HapticHint hapticFor(double absVelocity) {
    if (absVelocity >= 1200) return HapticHint.heavy;
    if (absVelocity <= 0 || absVelocity < 200) return HapticHint.medium;
    return HapticHint.medium;
  }

  /// Diagonal magnitude (for optional "velocity" telemetry). Same shape as
  /// `Offset.distance` but without the Flutter import so tests stay pure.
  static double magnitude(double dx, double dy) =>
      math.sqrt(dx * dx + dy * dy);

  // ─── Multi-axis commit (like / pass / save) ────────────────────

  /// Heuristic: does this drag feel like a deliberate upward "save" rather
  /// than a sideways like/pass? We classify as save when the upward motion
  /// dominates horizontal motion AND is large enough to not be noise.
  ///
  /// The 0.8 ratio lets diagonals still count as save if the user is
  /// flicking up-and-right slightly, which matches how thumbs actually move.
  static bool isSaveIntent({required double dragDx, required double dragDy}) {
    if (dragDy >= 0) return false;
    final absDy = -dragDy;
    final absDx = dragDx.abs();
    if (absDy < 30) return false;
    return absDy > absDx * 0.8;
  }

  /// Multi-axis commit resolution. Inspects both axes and returns the
  /// single direction that should eject the card, or none for snap-back.
  ///
  /// When both axes would commit independently (a hard diagonal flick),
  /// we pick by dominant magnitude so the user's strongest signal wins.
  static SwipeAxis commitAxis({
    required double dragDx,
    required double dragDy,
    required double velocityX,
    required double velocityY,
  }) {
    final horizontal = commitDirection(dragDx: dragDx, velocity: velocityX);
    final verticalUp =
        dragDy < -commitDragDyUp || velocityY < commitVelocityUpPxPerSec;

    if (horizontal != 0 && verticalUp) {
      // Diagonal hard-commit. Pick the axis the user moved further on.
      if (dragDx.abs() >= dragDy.abs()) {
        return horizontal > 0 ? SwipeAxis.right : SwipeAxis.left;
      }
      return SwipeAxis.up;
    }
    if (horizontal == 1) return SwipeAxis.right;
    if (horizontal == -1) return SwipeAxis.left;
    if (verticalUp) return SwipeAxis.up;
    return SwipeAxis.none;
  }

  /// Normalized [0, 1] save ratio for the "KAYDET" overlay. Only positive
  /// for upward motion — zero otherwise so the overlay stays hidden on
  /// horizontal or downward drags.
  static double saveRatio(double dy) {
    if (dy >= 0) return 0;
    if (overlaySaturationDyUp <= 0) return 0;
    final r = (-dy) / overlaySaturationDyUp;
    return r.clamp(0.0, 1.0);
  }

  /// Upward exit target (negative = up). Scales with screen height so the
  /// card fully leaves the viewport on tall devices.
  static double exitTargetDy({required double screenHeight}) {
    return -screenHeight * exitTargetHeightMultiplier;
  }

  /// Vertical start offset for a save-axis exit. When the current drag
  /// isn't decisively upward yet (e.g. the user tapped a save button),
  /// bias the start a little up so the fly-out has a visible direction.
  static double saveExitStartDy({required double currentDragDy}) {
    if (currentDragDy <= minSaveExitStartDy) return currentDragDy;
    return minSaveExitStartDy;
  }

  // ─── Progressive haptic thresholds ─────────────────────────────

  /// Three-step escalation so the user *feels* the commit approaching
  /// rather than getting a single click at the finish line. Callers track
  /// the previously fired level and only fire when it changes upward.
  static SwipeHaptic hapticLevel(double absRatio) {
    if (absRatio >= 1.0) return SwipeHaptic.commit;
    if (absRatio >= 0.7) return SwipeHaptic.nearCommit;
    if (absRatio >= 0.4) return SwipeHaptic.approach;
    return SwipeHaptic.idle;
  }
}

enum HapticHint { light, medium, heavy }

/// Resolved axis for a swipe commit. `none` means snap-back.
enum SwipeAxis { none, right, left, up }

/// Progressive haptic escalation. Fire only on upward transitions, and
/// reset to [idle] when the drag retreats past the first threshold.
enum SwipeHaptic { idle, approach, nearCommit, commit }
