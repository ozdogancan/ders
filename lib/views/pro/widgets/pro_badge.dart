// Reusable PRO badge — small gradient pill with crown icon + "PRO" text.
// ~24×16 px (or scaled). Used as overlay or inline indicator on locked
// features, save buttons over quota, hi-res download etc.

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/koala_tokens.dart';

class ProBadge extends StatelessWidget {
  const ProBadge({
    super.key,
    this.compact = false,
    this.gold = false,
  });

  /// Smaller version (16h) — fits inside chips, list trailing, icon corners.
  final bool compact;

  /// Use the gold/premium accent rather than the indigo gradient.
  final bool gold;

  @override
  Widget build(BuildContext context) {
    final h = compact ? 16.0 : 20.0;
    final fontSize = compact ? 8.5 : 10.0;
    final iconSize = compact ? 8.5 : 11.0;
    final pad = compact
        ? const EdgeInsets.symmetric(horizontal: 5, vertical: 1)
        : const EdgeInsets.symmetric(horizontal: 7, vertical: 2);
    final gradient = gold
        ? const LinearGradient(
            colors: [Color(0xFFE0B96B), Color(0xFFB8862F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [KoalaColors.accentDeep, KoalaColors.accentMuted],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
    return Container(
      height: h,
      padding: pad,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(99),
        boxShadow: [
          BoxShadow(
            color: (gold ? const Color(0xFFB8862F) : KoalaColors.accentDeep)
                .withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.crown, size: iconSize, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            'PRO',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.6,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
