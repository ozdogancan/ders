import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../editorial_theme.dart';

/// Önce/Sonra slider — paket yok, ~90 satır. Parmakla yatay sürükle.
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
    return AspectRatio(
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
              left: w * _pos - 0.5,
              top: 0,
              bottom: 0,
              width: 1,
              child: Container(color: MekanPalette.paper),
            ),
            Positioned(
              left: w * _pos - 18,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: MekanPalette.paper,
                    shape: BoxShape.circle,
                    border: Border.all(color: MekanPalette.ink),
                  ),
                  alignment: Alignment.center,
                  child: Text('↔', style: MekanType.mono(size: 12, color: MekanPalette.ink)),
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
            // 1px frame üstünde
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: MekanPalette.line),
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _afterImage() {
    final s = widget.afterSrc;
    if (s.startsWith('data:image')) {
      final b = UriData.fromString(s).contentAsBytes();
      return Image.memory(b, fit: BoxFit.cover);
    }
    return CachedNetworkImage(
      imageUrl: s,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: MekanPalette.oat),
      errorWidget: (_, __, ___) => Container(color: MekanPalette.oat),
    );
  }

  Widget _cornerLabel({
    double? top, double? left, double? right,
    required String text,
  }) =>
      Positioned(
        top: top, left: left, right: right,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: MekanPalette.paper,
          child: Text(text.toUpperCase(),
              style: MekanType.caps(size: 9, color: MekanPalette.ink, tracking: 1.8)),
        ),
      );
}
