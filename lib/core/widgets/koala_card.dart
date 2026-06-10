import 'package:flutter/material.dart';

import '../theme/koala_ds.dart';

/// Koala V2 standart kartı: surface + warm line + card shadow + lg20 radius.
/// onTap verilirse ripple'lı tıklanabilir olur.
class KoalaCard extends StatelessWidget {
  const KoalaCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(KoalaGap.lg),
    this.radius = KoalaR.lg,
    this.elevated = true,
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double radius;
  final bool elevated;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final card = AnimatedContainer(
      duration: KoalaMotion.fast,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? KoalaDS.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: KoalaDS.line, width: 1),
        boxShadow: elevated ? KoalaElev.card : null,
      ),
      child: child,
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        splashColor: KoalaDS.accentTint.withValues(alpha: 0.5),
        highlightColor: KoalaDS.surfaceMuted,
        child: card,
      ),
    );
  }
}

/// Seçilebilir chip (filtre/kategori). selected = accent tint + accent border.
class KoalaChip extends StatelessWidget {
  const KoalaChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.leading,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? leading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: KoalaMotion.fast,
        padding: const EdgeInsets.symmetric(
            horizontal: KoalaGap.lg, vertical: KoalaGap.sm),
        decoration: BoxDecoration(
          color: selected ? KoalaDS.accentTint : KoalaDS.surface,
          borderRadius: BorderRadius.circular(KoalaR.pill),
          border: Border.all(
            color: selected ? KoalaDS.accent : KoalaDS.line,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              Icon(leading, size: 16,
                  color: selected ? KoalaDS.accentDeep : KoalaDS.inkSoft),
              const SizedBox(width: KoalaGap.xs),
            ],
            Text(label,
                style: KoalaType.label.copyWith(
                    color: selected ? KoalaDS.accentDeep : KoalaDS.ink)),
          ],
        ),
      ),
    );
  }
}
