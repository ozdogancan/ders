import 'dart:convert';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/koala_tokens.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Önce/Sonra slider — paket yok. Parmakla yatay sürükle.
/// Before: orijinal bytes. After: URL (Replicate) ya da data URL (mock).
class BeforeAfter extends StatefulWidget {
  final Uint8List beforeBytes;
  final String afterSrc;
  const BeforeAfter({
    super.key,
    required this.beforeBytes,
    required this.afterSrc,
  });

  @override
  State<BeforeAfter> createState() => _BeforeAfterState();
}

class _BeforeAfterState extends State<BeforeAfter> {
  double _pos = 0.5; // 0..1

  void _updateFromGlobal(Offset global, BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(global);
    final pct = (local.dx / box.size.width).clamp(0.02, 0.98);
    setState(() => _pos = pct);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(KoalaRadius.lg),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: LayoutBuilder(builder: (ctx, c) {
          final w = c.maxWidth;
          return Stack(
            children: [
              // After (alt katman, tam)
              Positioned.fill(child: _afterImage()),
              // Before (üst katman, sola kırpılmış)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: w * _pos,
                child: ClipRect(
                  child: OverflowBox(
                    maxWidth: w,
                    minWidth: w,
                    alignment: Alignment.centerLeft,
                    child: Image.memory(widget.beforeBytes, fit: BoxFit.cover),
                  ),
                ),
              ),
              // Divider + handle
              Positioned(
                left: w * _pos - 1,
                top: 0,
                bottom: 0,
                width: 2,
                child: Container(color: KoalaColors.surface),
              ),
              Positioned(
                left: w * _pos - 20,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: KoalaColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: KoalaColors.borderSolid, width: 1),
                      boxShadow: KoalaShadows.card,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(LucideIcons.arrowLeftRight,
                        size: 18, color: KoalaColors.text),
                  ),
                ),
              ),
              // Corner labels
              _cornerLabel(top: 12, left: 12, text: 'Önce'),
              _cornerLabel(top: 12, right: 12, text: 'Sonra'),
              // Gesture layer
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (d) =>
                      _updateFromGlobal(d.globalPosition, ctx),
                  onHorizontalDragUpdate: (d) =>
                      _updateFromGlobal(d.globalPosition, ctx),
                  onTapDown: (d) => _updateFromGlobal(d.globalPosition, ctx),
                ),
              ),
              // Çerçeve
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border:
                          Border.all(color: KoalaColors.border, width: 0.5),
                      borderRadius: BorderRadius.circular(KoalaRadius.lg),
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _afterImage() {
    final s = widget.afterSrc;
    // ignore: avoid_print
    print('[BeforeAfter] afterSrc len=${s.length} prefix="${s.length > 40 ? s.substring(0, 40) : s}"');

    if (s.startsWith('data:image')) {
      // Flutter web'de UriData.fromString().contentAsBytes() base64'ü decode
      // etmeden ham UTF-8 string bytes döndürüyor. Manuel decode şart.
      final commaIdx = s.indexOf(',');
      if (commaIdx < 0) {
        // ignore: avoid_print
        print('[BeforeAfter] no comma in data URL — fallback');
        return Container(color: KoalaColors.surfaceAlt);
      }
      try {
        final b = base64Decode(s.substring(commaIdx + 1));
        // ignore: avoid_print
        print('[BeforeAfter] decoded ${b.length} bytes header=${b.take(4).map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ')}');
        return Image.memory(
          b,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, err, __) {
            // ignore: avoid_print
            print('[BeforeAfter] Image.memory errorBuilder: $err');
            return Container(color: KoalaColors.surfaceAlt);
          },
        );
      } catch (e) {
        // ignore: avoid_print
        print('[BeforeAfter] base64Decode threw: $e');
        return Container(color: KoalaColors.surfaceAlt);
      }
    }
    if (s.isEmpty) {
      // ignore: avoid_print
      print('[BeforeAfter] empty afterSrc — placeholder');
      return Container(color: KoalaColors.surfaceAlt);
    }
    return CachedNetworkImage(
      imageUrl: s,
      fit: BoxFit.cover,
      placeholder: (_, _) => Container(color: KoalaColors.surfaceAlt),
      errorWidget: (_, _, _) => Container(color: KoalaColors.surfaceAlt),
    );
  }

  Widget _cornerLabel({
    double? top, double? left, double? right,
    required String text,
  }) =>
      Positioned(
        top: top, left: left, right: right,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: KoalaColors.surface,
            borderRadius: BorderRadius.circular(KoalaRadius.sm),
            border: Border.all(color: KoalaColors.border, width: 0.5),
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: KoalaColors.text,
              letterSpacing: 0.2,
            ),
          ),
        ),
      );
}
