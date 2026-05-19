// Inline upsell banner — compact horizontal card shown above the chat input
// (or any flow) when a free user has 1 message left in their quota.
// Dismissable per-session (the host widget is responsible for tracking the
// dismissed state — banner just exposes onDismiss).

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/koala_tokens.dart';
import '../../../helpers/paywall_router.dart';

class InlineUpsellBanner extends StatelessWidget {
  const InlineUpsellBanner({
    super.key,
    required this.text,
    required this.trigger,
    this.ctaLabel = 'Pro\'ya Geç',
    this.onDismiss,
    this.icon = LucideIcons.sparkles,
  });

  final String text;
  final String trigger;
  final String ctaLabel;
  final VoidCallback? onDismiss;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            KoalaColors.accentSoft,
            KoalaColors.accentLight,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: KoalaColors.accentDeep.withValues(alpha: 0.18),
          width: 0.6,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [KoalaColors.accentDeep, KoalaColors.accentMuted],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: KoalaColors.text,
                letterSpacing: -0.1,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => showPaywall(context, trigger: trigger),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: KoalaColors.accentDeep,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                ctaLabel,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 28,
              ),
              iconSize: 14,
              color: KoalaColors.textSec,
              icon: const Icon(LucideIcons.x),
            ),
        ],
      ),
    );
  }
}
