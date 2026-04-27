import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/koala_tokens.dart';
import '../../../services/analytics_service.dart';
import '../../../services/style_discovery_service.dart';

/// Tarz keşfi sonrası "Senin tarzın" reveal modal.
///
/// Yapı (yukarıdan aşağıya):
///  - drag handle
///  - hero görsel (en sevilen kart, 16:9)
///  - serif başlık "Senin tarzın"
///  - "tag1 · tag2 · tag3" subtitle (KoalaText.bodySec, lowercase, no emoji)
///  - 3-4 dot renk satırı
///  - 2 thumbnail mood-board (next-2 most-liked, 1:1)
///  - sticky CTA "Şimdi mekanını bu tarzda yeniden tasarla"
///  - secondary link "Tarzı yenile"
///
/// Ritm pro_match_sheet ile aynı:
///   - drag handle: statik
///   - hero: 80ms gecikme, 280ms fade + slideY begin: 0.06
///   - başlık: 120ms gecikme, 280ms fade
///   - subtitle: 160ms fade
///   - dots/board: 220ms+ stagger
///   - CTA: 280ms fade
class StyleRevealSheet extends StatelessWidget {
  final StyleHints hints;
  final List<DiscoveryCard> likedCards;

  /// Kullanıcı CTA'ya bastığında çağrılır — parent flow `StyleHints` alır.
  /// Sheet kendi başına Navigator.pop yapar; parent ek pop ETMEZ.
  final void Function(StyleHints hints) onAccept;

  /// "Tarzı yenile" tıklanınca parent swipe'a geri dönsün diye.
  final VoidCallback onRefine;

  const StyleRevealSheet({
    super.key,
    required this.hints,
    required this.likedCards,
    required this.onAccept,
    required this.onRefine,
  });

  /// Modal bottom sheet helper. 88% yükseklik, üst köşeler KoalaRadius.xl.
  static Future<StyleHints?> show(
    BuildContext context, {
    required StyleHints hints,
    required List<DiscoveryCard> likedCards,
  }) {
    return showModalBottomSheet<StyleHints?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (sheetCtx) => StyleRevealSheet(
        hints: hints,
        likedCards: likedCards,
        onAccept: (h) {
          Analytics.styleDiscoveryAccepted();
          Navigator.of(sheetCtx).pop(h);
        },
        onRefine: () {
          Analytics.styleDiscoveryRefined();
          Navigator.of(sheetCtx).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.88;
    final hero = hints.heroImageUrl ??
        (likedCards.isNotEmpty ? likedCards.first.imageUrl : null);
    // Hero hariç sıradaki 2 kart — mood-board thumbnail.
    final boardThumbs = likedCards
        .where((c) => c.imageUrl != hero)
        .take(2)
        .toList();
    final tagline = hints.topTags.isEmpty
        ? hints.mood.toLowerCase()
        : hints.topTags.map((t) => t.toLowerCase()).join(' · ');

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: KoalaColors.bg,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KoalaRadius.xl),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle — statik, animasyonsuz (pro_match_sheet ile aynı).
            Padding(
              padding: const EdgeInsets.only(top: KoalaSpacing.md),
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KoalaColors.borderMed,
                    borderRadius: BorderRadius.circular(KoalaRadius.pill),
                  ),
                ),
              ),
            ),
            const SizedBox(height: KoalaSpacing.lg),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // ── Hero görsel
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: KoalaSpacing.lg,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(KoalaRadius.lg),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: hero != null && hero.isNotEmpty
                            ? Image.network(
                                hero,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  color: KoalaColors.surfaceAlt,
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    LucideIcons.image,
                                    color: KoalaColors.textTer,
                                    size: 28,
                                  ),
                                ),
                              )
                            : Container(color: KoalaColors.surfaceAlt),
                      ),
                    ),
                  )
                      .animate(delay: 80.ms)
                      .fadeIn(duration: 280.ms)
                      .slideY(
                        begin: 0.06,
                        end: 0,
                        duration: 320.ms,
                        curve: Curves.easeOutCubic,
                      ),
                  const SizedBox(height: KoalaSpacing.md),

                  // ── Başlık + tagline
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: KoalaSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Senin tarzın',
                          style: KoalaText.serif(
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                            .animate(delay: 120.ms)
                            .fadeIn(duration: 280.ms)
                            .slideY(
                              begin: 0.06,
                              end: 0,
                              duration: 320.ms,
                              curve: Curves.easeOutCubic,
                            ),
                        const SizedBox(height: KoalaSpacing.xs),
                        Text(
                          tagline,
                          style: KoalaText.bodySec,
                        ).animate(delay: 160.ms).fadeIn(duration: 280.ms),
                      ],
                    ),
                  ),
                  const SizedBox(height: KoalaSpacing.md),

                  // ── Renk noktaları
                  if (hints.topColors.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: KoalaSpacing.lg,
                      ),
                      child: _ColorRow(hexes: hints.topColors),
                    )
                        .animate(delay: 200.ms)
                        .fadeIn(duration: 260.ms)
                        .slideY(
                          begin: 0.06,
                          end: 0,
                          duration: 280.ms,
                          curve: Curves.easeOutCubic,
                        ),

                  // ── Mood-board thumbnails
                  if (boardThumbs.isNotEmpty) ...[
                    const SizedBox(height: KoalaSpacing.lg),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: KoalaSpacing.lg,
                      ),
                      child: Row(
                        children: [
                          for (int i = 0; i < boardThumbs.length; i++) ...[
                            if (i > 0) const SizedBox(width: KoalaSpacing.sm),
                            Expanded(
                              child: _MoodThumb(card: boardThumbs[i])
                                  .animate(delay: (240 + i * 60).ms)
                                  .fadeIn(duration: 260.ms)
                                  .slideY(
                                    begin: 0.06,
                                    end: 0,
                                    duration: 280.ms,
                                    curve: Curves.easeOutCubic,
                                  ),
                            ),
                          ],
                          // Boşluk doldurucu — tek thumb varsa.
                          if (boardThumbs.length == 1)
                            const Expanded(child: SizedBox.shrink()),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: KoalaSpacing.xxl),
                ],
              ),
            ),

            // ── Sticky bottom — primary CTA + secondary link.
            Container(
              padding: const EdgeInsets.fromLTRB(
                KoalaSpacing.lg,
                KoalaSpacing.md,
                KoalaSpacing.lg,
                KoalaSpacing.lg,
              ),
              decoration: const BoxDecoration(
                color: KoalaColors.surface,
                border: Border(
                  top: BorderSide(color: KoalaColors.border, width: 0.5),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => onAccept(hints),
                      style: FilledButton.styleFrom(
                        backgroundColor: KoalaColors.accentDeep,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(KoalaRadius.pill),
                        ),
                        textStyle: KoalaText.button.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text(
                        'Şimdi mekanını bu tarzda yeniden tasarla',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                      .animate(delay: 280.ms)
                      .fadeIn(duration: 260.ms)
                      .slideY(
                        begin: 0.08,
                        end: 0,
                        duration: 280.ms,
                        curve: Curves.easeOutCubic,
                      ),
                  const SizedBox(height: KoalaSpacing.sm),
                  TextButton(
                    onPressed: onRefine,
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(40),
                    ),
                    child: Text(
                      'Tarzı yenile',
                      style: KoalaText.bodySec,
                    ),
                  ).animate(delay: 320.ms).fadeIn(duration: 220.ms),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _ColorRow extends StatelessWidget {
  final List<String> hexes;
  const _ColorRow({required this.hexes});

  @override
  Widget build(BuildContext context) {
    final dots = hexes.take(4).toList();
    return Row(
      children: [
        for (int i = 0; i < dots.length; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : KoalaSpacing.sm),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: _parseHex(dots[i]),
                shape: BoxShape.circle,
                border: Border.all(color: KoalaColors.border, width: 0.5),
                boxShadow: KoalaShadows.card,
              ),
            ),
          ),
      ],
    );
  }

  Color _parseHex(String raw) {
    try {
      var s = raw.trim().replaceFirst('#', '');
      if (s.length == 6) s = 'FF$s';
      return Color(int.parse(s, radix: 16));
    } catch (_) {
      return KoalaColors.surfaceAlt;
    }
  }
}

class _MoodThumb extends StatelessWidget {
  final DiscoveryCard card;
  const _MoodThumb({required this.card});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: KoalaColors.surfaceAlt,
          borderRadius: BorderRadius.circular(KoalaRadius.md),
          border: Border.all(color: KoalaColors.divider, width: 1),
          boxShadow: KoalaShadows.card,
        ),
        clipBehavior: Clip.antiAlias,
        child: card.imageUrl.isNotEmpty
            ? Image.network(
                card.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Container(color: KoalaColors.surfaceAlt),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
