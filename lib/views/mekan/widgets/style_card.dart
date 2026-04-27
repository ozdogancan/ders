import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/koala_tokens.dart';
import '../../../services/style_discovery_service.dart';

/// Tek bir discovery kartı — 16:9 görsel, KoalaRadius.lg köşe, hairline
/// border, soft shadow. Sol-altta yarı saydam blur backdrop üzerinde başlık.
///
/// Discovery niyeti: kullanıcı sadece estetik karar versin. Designer adı,
/// fiyat, similarity ve diğer gürültü burada YOK — pro_match_sheet'in
/// dolu kartından kasten farklı.
///
/// Animasyon ritmi pro_match_sheet'in `_MatchCard` girişiyle paralel:
/// 240ms fade + 8px Y translate (slideY begin: 0.06).
class StyleCard extends StatelessWidget {
  final DiscoveryCard card;

  /// Render delay in ms — peek (-8px y / 0.96 scale) kartlar için 0,
  /// üstteki aktif kart için modest delay.
  final int delayMs;

  const StyleCard({
    super.key,
    required this.card,
    this.delayMs = 0,
  });

  @override
  Widget build(BuildContext context) {
    final body = Container(
      decoration: BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(KoalaRadius.lg),
        border: Border.all(color: KoalaColors.divider, width: 1),
        boxShadow: KoalaShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Görsel — full bleed.
            card.imageUrl.isNotEmpty
                ? Image.network(
                    card.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: KoalaColors.surfaceAlt,
                      alignment: Alignment.center,
                      child: const Icon(
                        LucideIcons.image,
                        color: KoalaColors.textTer,
                        size: 24,
                      ),
                    ),
                  )
                : Container(color: KoalaColors.surfaceAlt),
            // Başlık chip — sol-alt, blur backdrop üstünde KoalaText.bodySec.
            Positioned(
              left: KoalaSpacing.md,
              bottom: KoalaSpacing.md,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(KoalaRadius.pill),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: KoalaSpacing.md,
                      vertical: KoalaSpacing.xs + 2,
                    ),
                    decoration: BoxDecoration(
                      color: KoalaColors.surface.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(KoalaRadius.pill),
                      border: Border.all(
                        color: KoalaColors.border,
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      card.title,
                      style: KoalaText.bodySec.copyWith(
                        color: KoalaColors.text,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return body
        .animate(delay: Duration(milliseconds: delayMs))
        .fadeIn(duration: 240.ms)
        .slideY(
          begin: 0.06,
          end: 0,
          duration: 240.ms,
          curve: Curves.easeOutCubic,
        );
  }
}
