import 'package:flutter/material.dart';
import '../../../core/theme/koala_tokens.dart';

class PricingTile extends StatelessWidget {
  final String title;
  final String price;
  final String? subtitle;
  final String? badge;
  final Color? badgeColor;
  final bool selected;
  final VoidCallback onTap;

  const PricingTile({
    super.key,
    required this.title,
    required this.price,
    required this.onTap,
    required this.selected,
    this.subtitle,
    this.badge,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? KoalaColors.accentDeep : KoalaColors.border;
    final bg = selected ? KoalaColors.accentSoft : KoalaColors.surface;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(
            color: borderColor,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(KoalaRadius.lg),
          boxShadow: selected ? KoalaShadows.card : null,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? KoalaColors.accentDeep : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? KoalaColors.accentDeep
                          : KoalaColors.hintBorder,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white, size: 14)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: KoalaColors.text,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: KoalaColors.textSec,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  price,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: KoalaColors.text,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            if (badge != null)
              Positioned(
                top: -22,
                right: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor ?? KoalaColors.errorBright,
                    borderRadius: BorderRadius.circular(KoalaRadius.pill),
                    boxShadow: [
                      BoxShadow(
                        color: (badgeColor ?? KoalaColors.errorBright)
                            .withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.6,
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
