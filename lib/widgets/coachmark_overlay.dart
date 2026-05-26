import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/koala_tokens.dart';

/// Lifetime-once "shell coachmark" — darkens screen, cuts a spotlight hole
/// around each anchor, and shows a small Koala-voice info card next to it.
///
/// Premium feel: smooth fade + slight slide between steps, eased timings.
/// Use via [CoachmarkOverlay.show] from anywhere with an Overlay in scope.
class CoachmarkStep {
  final GlobalKey anchorKey;
  final String title;
  final String body;
  final IconData? icon;
  /// Extra padding around the cutout (default 10).
  final double padding;
  /// Force corner radius (default: derived from anchor size).
  final double? radius;

  const CoachmarkStep({
    required this.anchorKey,
    required this.title,
    required this.body,
    this.icon,
    this.padding = 10,
    this.radius,
  });
}

class CoachmarkOverlay extends StatefulWidget {
  final List<CoachmarkStep> steps;
  final VoidCallback onDone;

  const CoachmarkOverlay({
    super.key,
    required this.steps,
    required this.onDone,
  });

  /// Push the overlay onto the nearest Overlay. Returns the [OverlayEntry]
  /// in case caller wants to dismiss manually (normally the overlay removes
  /// itself when the user finishes / skips).
  static OverlayEntry show({
    required BuildContext context,
    required List<CoachmarkStep> steps,
    VoidCallback? onDone,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => CoachmarkOverlay(
        steps: steps,
        onDone: () {
          entry.remove();
          if (onDone != null) onDone();
        },
      ),
    );
    overlay.insert(entry);
    return entry;
  }

  @override
  State<CoachmarkOverlay> createState() => _CoachmarkOverlayState();
}

class _CoachmarkOverlayState extends State<CoachmarkOverlay>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ctrl.forward());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_index >= widget.steps.length - 1) {
      await _ctrl.reverse();
      widget.onDone();
      return;
    }
    await _ctrl.reverse();
    if (!mounted) return;
    setState(() => _index++);
    await _ctrl.forward();
  }

  Future<void> _skip() async {
    await _ctrl.reverse();
    widget.onDone();
  }

  Rect? _anchorRect(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.attached) return null;
    final size = ro.size;
    final topLeft = ro.localToGlobal(Offset.zero);
    return topLeft & size;
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_index];
    final media = MediaQuery.of(context);
    final screen = media.size;

    // Resolve anchor — if missing (e.g. tab not mounted) skip step.
    final rect = _anchorRect(step.anchorKey);
    if (rect == null) {
      // Skip silently next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => _next());
      return const SizedBox.shrink();
    }

    final padded = Rect.fromLTRB(
      rect.left - step.padding,
      rect.top - step.padding,
      rect.right + step.padding,
      rect.bottom + step.padding,
    );
    final radius = step.radius ??
        (padded.shortestSide / 2).clamp(12.0, 28.0).toDouble();

    final cardBelow = padded.center.dy < screen.height * 0.5;
    final isLast = _index >= widget.steps.length - 1;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // ── 1. Dimmed backdrop with spotlight hole ──
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _fade,
              builder: (_, __) => IgnorePointer(
                ignoring: true,
                child: CustomPaint(
                  painter: _SpotlightPainter(
                    hole: padded,
                    radius: radius,
                    dimAlpha: 0.62 * _fade.value,
                  ),
                ),
              ),
            ),
          ),
          // ── 2. Tap-to-advance layer (everywhere except the hole) ──
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _next,
            ),
          ),
          // ── 3. Pulse ring around the hole (subtle) ──
          Positioned.fromRect(
            rect: padded,
            child: IgnorePointer(
              child: FadeTransition(
                opacity: _fade,
                child: _PulseRing(radius: radius),
              ),
            ),
          ),
          // ── 4. Info card ──
          _positionCard(
            screen: screen,
            anchor: padded,
            below: cardBelow,
            safeTop: media.padding.top,
            safeBottom: media.padding.bottom,
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: Offset(0, cardBelow ? -0.06 : 0.06),
                  end: Offset.zero,
                ).animate(_fade),
                child: _CoachmarkCard(
                  step: step,
                  index: _index,
                  total: widget.steps.length,
                  isLast: isLast,
                  onSkip: _skip,
                  onNext: _next,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _positionCard({
    required Size screen,
    required Rect anchor,
    required bool below,
    required double safeTop,
    required double safeBottom,
    required Widget child,
  }) {
    const gap = 18.0;
    const sideMargin = 18.0;
    final maxWidth = screen.width - sideMargin * 2;

    final cardWidth = maxWidth.clamp(0.0, 360.0).toDouble();
    final leftDefault = (anchor.center.dx - cardWidth / 2)
        .clamp(sideMargin, screen.width - sideMargin - cardWidth);

    if (below) {
      // Card BELOW anchor.
      return Positioned(
        top: anchor.bottom + gap,
        left: leftDefault,
        width: cardWidth,
        child: child,
      );
    }
    // Card ABOVE anchor.
    return Positioned(
      bottom: (screen.height - anchor.top) + gap,
      left: leftDefault,
      width: cardWidth,
      child: child,
    );
  }
}

class _CoachmarkCard extends StatelessWidget {
  final CoachmarkStep step;
  final int index;
  final int total;
  final bool isLast;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  const _CoachmarkCard({
    required this.step,
    required this.index,
    required this.total,
    required this.isLast,
    required this.onSkip,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
      decoration: BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: KoalaColors.border, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: KoalaColors.accent.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (step.icon != null) ...[
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KoalaColors.accentSoft,
                  ),
                  child: Icon(step.icon,
                      size: 16, color: KoalaColors.accentDeep),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  step.title,
                  style: KoalaText.h3.copyWith(letterSpacing: -0.2),
                ),
              ),
              Text(
                '${index + 1}/$total',
                style: KoalaText.labelSmall.copyWith(
                  color: KoalaColors.textTer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            step.body,
            style: KoalaText.body.copyWith(
              color: KoalaColors.textMed,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  foregroundColor: KoalaColors.textSec,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Atla',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: onNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: KoalaColors.accentDeep,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  minimumSize: const Size(0, 38),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isLast ? 'Tamam' : 'İleri',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      isLast ? LucideIcons.check : LucideIcons.arrowRight,
                      size: 14,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect hole;
  final double radius;
  final double dimAlpha;

  _SpotlightPainter({
    required this.hole,
    required this.radius,
    required this.dimAlpha,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Path()..addRect(Offset.zero & size);
    final cut = Path()
      ..addRRect(RRect.fromRectAndRadius(hole, Radius.circular(radius)));
    final mask = Path.combine(PathOperation.difference, bg, cut);
    canvas.drawPath(
      mask,
      Paint()..color = Colors.black.withValues(alpha: dimAlpha),
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) =>
      old.hole != hole || old.radius != radius || old.dimAlpha != dimAlpha;
}

class _PulseRing extends StatefulWidget {
  final double radius;
  const _PulseRing({required this.radius});

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeOut.transform(_c.value);
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(
              color: Colors.white.withValues(alpha: (1 - t) * 0.55),
              width: 1.5 + t * 2.5,
            ),
          ),
        );
      },
    );
  }
}
