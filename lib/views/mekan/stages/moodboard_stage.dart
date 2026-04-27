import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/koala_tokens.dart';
import '../../../services/taste_service.dart';
import '../widgets/mekan_ui.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Swipe bittikten sonra / veya taste confident durumunda gösterilen
/// "senin tarzın bu" reveal ekranı.
///
/// UX hedefi: kullanıcıya AI'ın onu anladığı hissini vermek. 3 adımlı
/// staggered reveal: 1) headline, 2) top stiller, 3) CTA.
class MoodboardStage extends StatefulWidget {
  final VoidCallback onContinue;
  final VoidCallback? onRefine; // "Biraz daha swipe"

  const MoodboardStage({
    super.key,
    required this.onContinue,
    this.onRefine,
  });

  @override
  State<MoodboardStage> createState() => _MoodboardStageState();
}

class _MoodboardStageState extends State<MoodboardStage> {
  MoodboardSummary? _summary;

  @override
  void initState() {
    super.initState();
    TasteService.summaryForMoodboard().then((s) {
      if (!mounted) return;
      setState(() => _summary = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    if (s == null) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(KoalaColors.accentDeep),
          strokeWidth: 2.5,
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          KoalaSpacing.xl, KoalaSpacing.lg, KoalaSpacing.xl, KoalaSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sparkle rozeti
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: KoalaColors.accentDeep.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(KoalaRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(LucideIcons.sparkles,
                    size: 12, color: KoalaColors.accentDeep),
                SizedBox(width: 4),
                Text(
                  'Moodboard',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: KoalaColors.accentDeep,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.2, end: 0),

          const SizedBox(height: KoalaSpacing.lg),

          Text(s.headline, style: KoalaText.h1)
              .animate(delay: 150.ms)
              .fadeIn(duration: 450.ms)
              .slideY(begin: 0.15, end: 0, curve: Curves.easeOutCubic),

          const SizedBox(height: KoalaSpacing.sm),

          Text(s.subline, style: KoalaText.bodySec)
              .animate(delay: 350.ms)
              .fadeIn(duration: 400.ms),

          const SizedBox(height: KoalaSpacing.xxl),

          // Stil kartları — staggered
          if (s.hasData)
            ...List.generate(s.topStyles.length, (i) {
              final style = s.topStyles[i];
              final pct = (style.share * 100).round();
              return Padding(
                padding: const EdgeInsets.only(bottom: KoalaSpacing.md),
                child: _StyleRow(
                  label: _prettyStyle(style.style),
                  percent: pct,
                  rank: i + 1,
                )
                    .animate(delay: (500 + i * 180).ms)
                    .fadeIn(duration: 420.ms)
                    .slideX(begin: 0.12, end: 0, curve: Curves.easeOutCubic),
              );
            }),

          const SizedBox(height: KoalaSpacing.xl),

          if (s.hasData)
            MekanPrimaryButton(
              label: 'Mekanımı bu tarzda tasarla',
              onTap: widget.onContinue,
              trailing: LucideIcons.sparkles,
            )
                .animate(delay: (500 + s.topStyles.length * 180 + 100).ms)
                .fadeIn(duration: 400.ms)
                .scaleXY(begin: 0.96, end: 1.0)
          else
            MekanPrimaryButton(
              label: 'Keşfetmeye devam et',
              onTap: widget.onRefine ?? widget.onContinue,
              trailing: LucideIcons.arrowRight,
            ).animate(delay: 500.ms).fadeIn(),

          if (s.hasData && widget.onRefine != null) ...[
            const SizedBox(height: KoalaSpacing.md),
            Center(
              child: TextButton(
                onPressed: widget.onRefine,
                child: Text(
                  'Biraz daha keşfet',
                  style: KoalaText.label.copyWith(
                    color: KoalaColors.textSec,
                  ),
                ),
              ),
            ).animate(delay: 1000.ms).fadeIn(),
          ],
        ],
      ),
    );
  }

  String _prettyStyle(String key) {
    const tr = {
      'modern': 'Modern',
      'minimalist': 'Minimalist',
      'iskandinav': 'Skandinav',
      'klasik': 'Klasik',
      'endüstriyel': 'Endüstriyel',
      'boho': 'Bohem',
      'rustik': 'Rustik',
      'japandi': 'Japandi',
      'mid_century': 'Mid-Century',
      'mediterranean': 'Akdeniz',
    };
    return tr[key] ?? (key.isEmpty ? key : key[0].toUpperCase() + key.substring(1));
  }
}

class _StyleRow extends StatelessWidget {
  final String label;
  final int percent;
  final int rank;
  const _StyleRow({
    required this.label,
    required this.percent,
    required this.rank,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: KoalaSpacing.lg, vertical: KoalaSpacing.md),
      decoration: BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(KoalaRadius.lg),
        border: Border.all(
          color: rank == 1
              ? KoalaColors.accentDeep.withValues(alpha: 0.35)
              : KoalaColors.border,
          width: rank == 1 ? 1.5 : 0.5,
        ),
        boxShadow: rank == 1 ? KoalaShadows.accentGlow : null,
      ),
      child: Row(
        children: [
          // Rank rozeti
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: rank == 1
                  ? KoalaColors.accentDeep
                  : KoalaColors.surfaceAlt,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: rank == 1 ? Colors.white : KoalaColors.textSec,
              ),
            ),
          ),
          const SizedBox(width: KoalaSpacing.md),
          Expanded(
            child: Text(
              label,
              style: KoalaText.h3.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Percent bar
          SizedBox(
            width: 80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '%$percent',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: rank == 1
                        ? KoalaColors.accentDeep
                        : KoalaColors.textSec,
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(KoalaRadius.pill),
                  child: LinearProgressIndicator(
                    value: percent / 100,
                    minHeight: 3,
                    backgroundColor: KoalaColors.surfaceAlt,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      rank == 1 ? KoalaColors.accentDeep : KoalaColors.textSec,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
