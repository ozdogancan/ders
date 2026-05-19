// Pro lock overlay — semi-transparent dark scrim + crown + "Pro" label,
// used as a Positioned.fill overlay over content that requires a Pro
// subscription. Tap → opens the paywall via showPaywall.

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/koala_tokens.dart';
import '../../../helpers/paywall_router.dart';

class ProLockOverlay extends StatelessWidget {
  const ProLockOverlay({
    super.key,
    required this.trigger,
    this.label = 'Pro özellik',
    this.subtle = false,
    this.borderRadius = 16,
  });

  /// Analytics trigger string passed to showPaywall.
  final String trigger;

  /// Label shown next to the crown icon.
  final String label;

  /// If true, uses a softer scrim (15% opacity) instead of 35%. Useful when
  /// the underlying content should still be readable.
  final bool subtle;

  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final scrim = Colors.black.withValues(alpha: subtle ? 0.18 : 0.35);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Material(
        color: scrim,
        child: InkWell(
          onTap: () => showPaywall(context, trigger: trigger),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [KoalaColors.accentDeep, KoalaColors.accentMuted],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(99),
                boxShadow: [
                  BoxShadow(
                    color: KoalaColors.accentDeep.withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.crown,
                      size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
