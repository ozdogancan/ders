// Reusable Pro upsell card. Used in the Projeler empty-state and elsewhere
// to softly nudge free users toward Pro without modal-blocking them.

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/koala_tokens.dart';
import '../../../helpers/paywall_router.dart';

class ProCard extends StatelessWidget {
  const ProCard({
    super.key,
    required this.headline,
    required this.body,
    required this.trigger,
    this.icon = LucideIcons.gem,
    this.ctaLabel = 'Detaylar',
  });

  final String headline;
  final String body;
  final String trigger;
  final IconData icon;
  final String ctaLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KoalaColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showPaywall(context, trigger: trigger),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: KoalaColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border(
              left: BorderSide(
                color: KoalaColors.accentDeep,
                width: 3,
              ),
              top: BorderSide(
                  color: KoalaColors.border, width: 0.5),
              right: BorderSide(
                  color: KoalaColors.border, width: 0.5),
              bottom: BorderSide(
                  color: KoalaColors.border, width: 0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: KoalaColors.accentDeep.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: KoalaColors.accentSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon,
                    size: 18, color: KoalaColors.accentDeep),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      headline,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: KoalaColors.text,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: KoalaColors.textMed,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                ctaLabel,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: KoalaColors.accentDeep,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(LucideIcons.arrowRight,
                  size: 14, color: KoalaColors.accentDeep),
            ],
          ),
        ),
      ),
    );
  }
}
