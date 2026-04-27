// swipe_onboarding_overlay.dart — Koala by evlumba
// One-time first-run overlay mounted from SwipeScreen.
// Teaches right-swipe (like), left-swipe (pass), up-swipe (save).
// Persists flag `koala.swipe_onboarding_seen.v1` via SharedPreferences.
// See DESIGN.md § "Fix #4 — First-run onboarding" for the locked spec.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/koala_tokens.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Full-screen onboarding overlay for the `/swipe` route.
///
/// Shows three gesture tutorial steps, then self-dismisses via [onDismissed].
/// Absorbs all pointer events so the card deck underneath cannot be swiped
/// while the overlay is visible.
class SwipeOnboardingOverlay extends StatefulWidget {
  const SwipeOnboardingOverlay({super.key, required this.onDismissed});

  /// Called when the overlay finishes (either "Anladım" or the X close button).
  final VoidCallback onDismissed;

  @override
  State<SwipeOnboardingOverlay> createState() => _SwipeOnboardingOverlayState();
}

class _SwipeOnboardingOverlayState extends State<SwipeOnboardingOverlay> {
  int _step = 0;
  bool _dismissing = false;

  static const _flagKey = 'koala.swipe_onboarding_seen.v1';

  static const _steps = [
    _StepData(
      title: 'Beğen',
      icon: LucideIcons.arrowRight,
      subtitle: 'Sağa çek →',
    ),
    _StepData(
      title: 'Geç',
      icon: LucideIcons.arrowLeft,
      subtitle: '← Sola çek',
    ),
    _StepData(
      title: 'Kaydet',
      icon: LucideIcons.arrowUp,
      subtitle: 'Yukarı çek ↑',
    ),
  ];

  void _persistFlag() {
    unawaited(
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setBool(_flagKey, true)),
    );
  }

  void _dismiss() {
    if (_dismissing) return;
    _dismissing = true;
    _persistFlag();
    widget.onDismissed();
  }

  void _next() {
    if (_step < _steps.length - 1) {
      setState(() => _step++);
    } else {
      _dismiss();
    }
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    final isLast = _step == _steps.length - 1;

    // Scrim-level GestureDetector with HitTestBehavior.opaque swallows
    // taps/pans/long-presses that land in empty scrim regions so they
    // never reach the deck behind. Buttons inside the card claim their
    // own gestures via nearer GestureDetectors (FilledButton/TextButton),
    // so they keep working — do NOT wrap this subtree in AbsorbPointer,
    // that would kill the buttons.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // swallow stray taps on scrim
      onPanStart: (_) {},
      onPanUpdate: (_) {},
      onPanEnd: (_) {},
      onLongPress: () {},
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.72),
        child: Stack(
            children: [
              // ── Centered tutorial card ──────────────────────────────
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      elevation: 16,
                      shadowColor: Colors.black38,
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Icon
                            Icon(
                              step.icon,
                              size: 64,
                              color: KoalaColors.accent,
                            ),
                            const SizedBox(height: 16),
                            // Title
                            Text(
                              step.title,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Subtitle
                            Text(
                              step.subtitle,
                              style: const TextStyle(
                                fontSize: 15,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 24),
                            // Dot indicator
                            _DotIndicator(
                              total: _steps.length,
                              current: _step,
                            ),
                            const SizedBox(height: 24),
                            // Navigation row
                            Row(
                              children: [
                                if (_step > 0) ...[
                                  TextButton(
                                    onPressed: _back,
                                    child: const Text('Geri'),
                                  ),
                                  const Spacer(),
                                ],
                                FilledButton(
                                  onPressed: _next,
                                  child: Text(isLast ? 'Anladım' : 'Devam'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── X close button (top-right of scrim) ────────────────
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 12,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: GestureDetector(
                    onTap: _dismiss,
                    behavior: HitTestBehavior.opaque,
                    child: const Icon(
                      LucideIcons.x,
                      size: 32,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Three-dot step indicator.
class _DotIndicator extends StatelessWidget {
  const _DotIndicator({required this.total, required this.current});

  final int total;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (i) {
        final isCurrent = i == current;
        return Padding(
          padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
          child: isCurrent
              ? Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: KoalaColors.accent,
                    shape: BoxShape.circle,
                  ),
                )
              : Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: KoalaColors.accent, width: 1.5),
                  ),
                ),
        );
      }),
    );
  }
}

/// Immutable data for a single onboarding step.
class _StepData {
  const _StepData({
    required this.title,
    required this.icon,
    required this.subtitle,
  });

  final String title;
  final IconData icon;
  final String subtitle;
}
