import 'package:flutter/material.dart';
import '../editorial_theme.dart';

/// 1px ince çizgi — kart gölgesi/kenarlığı yerine editoryal hairline.
class Hairline extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  const Hairline({super.key, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Container(height: 1, color: MekanPalette.line),
      );
}

/// "§01 · Çekim" — bölüm başlığı. Büyük section mark + küçük caps label.
class Ordinal extends StatelessWidget {
  final String n;
  final String label;
  const Ordinal({super.key, required this.n, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '§$n',
            style: MekanType.display(size: 28, color: MekanPalette.moss)
                .copyWith(letterSpacing: -0.5, height: 1),
          ),
          const SizedBox(width: 10),
          Text(label.toUpperCase(), style: MekanType.caps(tracking: 2.4, size: 10)),
        ],
      );
}

/// Tüm caps etiket — mono, tracked out.
class Caps extends StatelessWidget {
  final String text;
  final double size;
  final Color? color;
  final double tracking;
  const Caps(this.text,
      {super.key, this.size = 11, this.color, this.tracking = 2});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: MekanType.caps(size: size, color: color, tracking: tracking),
      );
}

/// Büyük italik başlık.
class Display extends StatelessWidget {
  final String text;
  final double size;
  final bool italic;
  final Color? color;
  const Display(this.text,
      {super.key, this.size = 56, this.italic = false, this.color});

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: MekanType.display(size: size, italic: italic, color: color),
      );
}

/// Altı çizili mono caps düğme — "TASARLA", "GERİ" vs.
class EButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool fullWidth;
  final IconData? leading;
  const EButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.fullWidth = false,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final color = primary ? MekanPalette.burnt : MekanPalette.ink;
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      splashColor: color.withValues(alpha: 0.06),
      highlightColor: color.withValues(alpha: 0.03),
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: Container(
          width: fullWidth ? double.infinity : null,
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[
                Icon(leading, size: 14, color: MekanPalette.burnt),
                const SizedBox(width: 10),
              ],
              Stack(children: [
                Text(label.toUpperCase(),
                    style: MekanType.caps(size: 11, color: color, tracking: 2.4)),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: -3,
                  child: Container(height: 1, color: color.withValues(alpha: 0.8)),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Siyah dolgulu pill — final commit aksiyonu. Terra cotta ok.
class PrimaryPill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const PrimaryPill({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: MekanPalette.ink,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    label.toUpperCase(),
                    style: MekanType.caps(
                      size: 12,
                      color: MekanPalette.paper,
                      tracking: 3,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                Text('→',
                    style: MekanType.caps(
                        size: 14, color: MekanPalette.burnt, tracking: 0)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Köşe işaretleri — çerçeve detayı için.
class CornerTicks extends StatelessWidget {
  const CornerTicks({super.key});

  @override
  Widget build(BuildContext context) {
    const sz = 10.0;
    Widget tick({double? top, double? right, double? bottom, double? left,
        bool topLine = false, bool rightLine = false,
        bool bottomLine = false, bool leftLine = false}) {
      return Positioned(
        top: top, right: right, bottom: bottom, left: left,
        child: Container(
          width: sz, height: sz,
          decoration: BoxDecoration(
            border: Border(
              top: topLine ? BorderSide(color: MekanPalette.ink) : BorderSide.none,
              right: rightLine ? BorderSide(color: MekanPalette.ink) : BorderSide.none,
              bottom: bottomLine ? BorderSide(color: MekanPalette.ink) : BorderSide.none,
              left: leftLine ? BorderSide(color: MekanPalette.ink) : BorderSide.none,
            ),
          ),
        ),
      );
    }

    return Stack(clipBehavior: Clip.none, children: [
      tick(top: -1, left: -1, topLine: true, leftLine: true),
      tick(top: -1, right: -1, topLine: true, rightLine: true),
      tick(bottom: -1, left: -1, bottomLine: true, leftLine: true),
      tick(bottom: -1, right: -1, bottomLine: true, rightLine: true),
    ]);
  }
}
