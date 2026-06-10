import 'package:flutter/material.dart';

import '../theme/koala_ds.dart';

enum KoalaButtonVariant { primary, accent, secondary, ghost, danger }

enum KoalaButtonSize { sm, md, lg }

/// Koala V2'nin tek butonu. Ekranlarda elle FilledButton/padding/shape YOK.
/// primary = yeşil CTA, accent = mor (AI/marka), secondary = outline,
/// ghost = zeminsiz, danger = kırmızı. Basışta hafif scale animasyonu.
class KoalaButton extends StatefulWidget {
  const KoalaButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = KoalaButtonVariant.primary,
    this.size = KoalaButtonSize.md,
    this.leading,
    this.trailing,
    this.loading = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final KoalaButtonVariant variant;
  final KoalaButtonSize size;
  final IconData? leading;
  final IconData? trailing;
  final bool loading;
  final bool expand;

  @override
  State<KoalaButton> createState() => _KoalaButtonState();
}

class _KoalaButtonState extends State<KoalaButton> {
  bool _down = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  ({Color bg, Color fg, Color? border, List<BoxShadow>? shadow, Gradient? grad})
      get _style {
    switch (widget.variant) {
      case KoalaButtonVariant.primary:
        return (bg: KoalaDS.cta, fg: KoalaDS.onAccent, border: null,
            shadow: KoalaElev.ctaGlow, grad: KoalaDS.ctaGradient);
      case KoalaButtonVariant.accent:
        return (bg: KoalaDS.accentDeep, fg: KoalaDS.onAccent, border: null,
            shadow: KoalaElev.accentGlow, grad: KoalaDS.accentGradient);
      case KoalaButtonVariant.secondary:
        return (bg: KoalaDS.surface, fg: KoalaDS.ink, border: KoalaDS.line,
            shadow: null, grad: null);
      case KoalaButtonVariant.ghost:
        return (bg: Colors.transparent, fg: KoalaDS.ink, border: null,
            shadow: null, grad: null);
      case KoalaButtonVariant.danger:
        return (bg: KoalaDS.dangerTint, fg: KoalaDS.danger, border: null,
            shadow: null, grad: null);
    }
  }

  EdgeInsets get _pad {
    switch (widget.size) {
      case KoalaButtonSize.sm:
        return const EdgeInsets.symmetric(horizontal: KoalaGap.lg, vertical: KoalaGap.sm);
      case KoalaButtonSize.md:
        return const EdgeInsets.symmetric(horizontal: KoalaGap.xl, vertical: 13);
      case KoalaButtonSize.lg:
        return const EdgeInsets.symmetric(horizontal: KoalaGap.xxl, vertical: 17);
    }
  }

  double get _fontSize => widget.size == KoalaButtonSize.lg ? 16 : 15;
  double get _iconSize => widget.size == KoalaButtonSize.sm ? 16 : 19;

  @override
  Widget build(BuildContext context) {
    final s = _style;
    final fg = _enabled ? s.fg : s.fg.withValues(alpha: 0.45);

    final content = widget.loading
        ? SizedBox(
            height: _iconSize, width: _iconSize,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: s.fg),
          )
        : Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.leading != null) ...[
                Icon(widget.leading, size: _iconSize, color: fg),
                const SizedBox(width: KoalaGap.sm),
              ],
              Flexible(
                child: Text(widget.label,
                    overflow: TextOverflow.ellipsis,
                    style: KoalaType.button.copyWith(color: fg, fontSize: _fontSize)),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: KoalaGap.sm),
                Icon(widget.trailing, size: _iconSize, color: fg),
              ],
            ],
          );

    return GestureDetector(
      onTapDown: _enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: _enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: _enabled ? () => setState(() => _down = false) : null,
      onTap: _enabled ? widget.onPressed : null,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: KoalaMotion.enter,
        child: AnimatedOpacity(
          opacity: _enabled ? 1 : 0.65,
          duration: KoalaMotion.fast,
          child: Container(
            padding: _pad,
            decoration: BoxDecoration(
              color: s.grad == null ? s.bg : null,
              gradient: _enabled ? s.grad : null,
              borderRadius: BorderRadius.circular(KoalaR.md),
              border: s.border != null ? Border.all(color: s.border!) : null,
              boxShadow: _enabled ? s.shadow : null,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
