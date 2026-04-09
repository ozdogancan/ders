import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/theme/koala_tokens.dart';

class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child, this.primaryGlow, this.secondaryGlow, this.showGrid = true});
  final Widget child;
  final Color? primaryGlow;
  final Color? secondaryGlow;
  final bool showGrid;

  @override
  Widget build(BuildContext context) {
    final Color p = primaryGlow ?? KoalaColors.accent;
    final Color s = secondaryGlow ?? KoalaColors.blue;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            KoalaColors.surfaceCool,
            p.withValues(alpha: 0.04),
            s.withValues(alpha: 0.03),
            KoalaColors.surfaceCool,
          ],
        ),
      ),
      child: child,
    );
  }
}

class FrostedCard extends StatelessWidget {
  const FrostedCard({super.key, required this.child, this.color, this.borderColor, this.radius = 28, this.padding = const EdgeInsets.all(20), this.onTap});
  final Widget child;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color ?? KoalaColors.surface.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: borderColor ?? KoalaColors.surface.withValues(alpha: 0.5),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: KoalaColors.inkDeep.withValues(alpha: 0.04),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    if (onTap != null) return GestureDetector(onTap: onTap, child: content);
    return content;
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({super.key, this.eyebrow, required this.title, this.subtitle});
  final String? eyebrow;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (eyebrow != null) ...<Widget>[
          Text(eyebrow!, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: KoalaColors.accent, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
          const SizedBox(height: 6),
        ],
        Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: KoalaColors.inkSoft, fontWeight: FontWeight.w800)),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: KoalaColors.textMed)),
        ],
      ],
    );
  }
}

class InfoPill extends StatelessWidget {
  const InfoPill({super.key, required this.label, this.icon, this.backgroundColor, this.foregroundColor});
  final String label;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final Color bg = backgroundColor ?? KoalaColors.surface.withValues(alpha: 0.14);
    final Color fg = foregroundColor ?? KoalaColors.surface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[Icon(icon, size: 14, color: fg), const SizedBox(width: 6)],
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class HighlightMetric extends StatelessWidget {
  const HighlightMetric({super.key, required this.value, required this.label, this.light = false});
  final String value;
  final String label;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final Color valueColor = light ? KoalaColors.surface : KoalaColors.inkSoft;
    final Color labelColor = light ? KoalaColors.surface.withValues(alpha: 0.7) : KoalaColors.textMed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: valueColor, fontWeight: FontWeight.w800)),
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: labelColor)),
      ],
    );
  }
}
