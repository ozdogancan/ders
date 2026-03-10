import 'dart:ui';
import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();
  static const Color primaryBlue = Color(0xFF2196F3);
  static const Color white = Color(0xFFFFFFFF);
  static const Color grey100 = Color(0xFFF5F7FA);
  static const Color grey300 = Color(0xFFD7DEE8);
  static const Color grey700 = Color(0xFF4A5565);
  static const Color successGreen = Color(0xFF2E7D32);
  static const Color errorRed = Color(0xFFC62828);
  static const Color brand = Color(0xFF6366F1);
  static const Color brandLight = Color(0xFFEEF2FF);
  static const Color ink = Color(0xFF0F172A);
  static const Color inkSoft = Color(0xFF1E293B);
  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color surface = Color(0xFFF8FAFC);
  static const Color border = Color(0xFFE2E8F0);
  static const Color accent = Color(0xFF8B5CF6);
  static const Color accentLight = Color(0xFFFEF2F2);
  static const Color teal = Color(0xFF14B8A6);
  static const Color cyan = Color(0xFF06B6D4);
  static const Color rose = Color(0xFFF43F5E);
  static const Color sun = Color(0xFFFBBF24);
  static const Color warning = Color(0xFFF59E0B);
  static const Color success = Color(0xFF22C55E);
  static const Color successLight = Color(0xFFDCFCE7);
  static const Color subjectMat = Color(0xFF6366F1);
  static const Color subjectFizik = Color(0xFFEC4899);
}

class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child, this.primaryGlow, this.secondaryGlow, this.showGrid = true});
  final Widget child;
  final Color? primaryGlow;
  final Color? secondaryGlow;
  final bool showGrid;

  @override
  Widget build(BuildContext context) {
    final Color p = primaryGlow ?? AppColors.brand;
    final Color s = secondaryGlow ?? AppColors.cyan;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppColors.surface, p.withValues(alpha: 0.04), s.withValues(alpha: 0.03), AppColors.surface],
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
            color: color ?? AppColors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: borderColor ?? AppColors.white.withValues(alpha: 0.5)),
            boxShadow: <BoxShadow>[BoxShadow(color: AppColors.ink.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))],
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
          Text(eyebrow!, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.brand, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
          const SizedBox(height: 6),
        ],
        Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
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
    final Color bg = backgroundColor ?? AppColors.white.withValues(alpha: 0.14);
    final Color fg = foregroundColor ?? AppColors.white;
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
    final Color valueColor = light ? AppColors.white : AppColors.textPrimary;
    final Color labelColor = light ? AppColors.white.withValues(alpha: 0.7) : AppColors.textSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: valueColor, fontWeight: FontWeight.w800)),
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: labelColor)),
      ],
    );
  }
}
