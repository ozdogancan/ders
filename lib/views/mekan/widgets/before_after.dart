import 'dart:convert';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/koala_tokens.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Önce/Sonra slider — paket yok. Parmakla yatay sürükle.
/// Before: orijinal bytes. After: URL (Replicate) ya da data URL (mock).
///
/// 2026-04-27: Üç görüntüleme modu eklendi.
///   - Slider modu (default): yarısı önce, yarısı sonra. Kaydır/değiştir.
///   - "Sonra" odak modu: After full bleed. Tek tıkla aç/kapat.
///   - "Önce" odak modu: Before full bleed. Long-press veya toggle.
/// Üst-sağ köşede üç durumlu segment kontrol var. Kullanıcı önce-sonrayı
/// görür ama isterse After'a kilitlenip detayı inceler. Çift tıkla zoom modal.
enum _CompareMode { slider, after, before }

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
  _CompareMode _mode = _CompareMode.slider;

  void _updateFromGlobal(Offset global, BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(global);
    final pct = (local.dx / box.size.width).clamp(0.02, 0.98);
    setState(() => _pos = pct);
  }

  void _setMode(_CompareMode m) {
    if (_mode == m) return;
    setState(() => _mode = m);
  }

  void _openZoom(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (_) => _ZoomModal(
        beforeBytes: widget.beforeBytes,
        afterSrc: widget.afterSrc,
        initialAfter: _mode != _CompareMode.before,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(KoalaRadius.lg),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: LayoutBuilder(builder: (ctx, c) {
              final w = c.maxWidth;
              return Stack(
                children: [
                  // After (alt katman, tam)
                  Positioned.fill(child: _afterImage()),

                  // Before katmanı — moda göre genişlik:
                  // slider → w * _pos
                  // before → w (full)
                  // after  → 0 (gizli)
                  if (_mode != _CompareMode.after)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: _mode == _CompareMode.before ? w : w * _pos,
                      child: ClipRect(
                        child: OverflowBox(
                          maxWidth: w,
                          minWidth: w,
                          alignment: Alignment.centerLeft,
                          child:
                              Image.memory(widget.beforeBytes, fit: BoxFit.cover),
                        ),
                      ),
                    ),

                  // Divider + handle — sadece slider modunda
                  if (_mode == _CompareMode.slider) ...[
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
                  ],

                  // Corner labels — moda göre
                  if (_mode == _CompareMode.slider) ...[
                    _cornerLabel(top: 12, left: 12, text: 'Önce'),
                    _cornerLabel(top: 12, right: 12, text: 'Sonra'),
                  ] else if (_mode == _CompareMode.after)
                    _cornerLabel(top: 12, left: 12, text: 'Sonra')
                  else
                    _cornerLabel(top: 12, left: 12, text: 'Önce'),

                  // Zoom (büyüteç) butonu — sağ alt
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: _IconButtonChip(
                      icon: LucideIcons.maximize2,
                      onTap: () => _openZoom(context),
                    ),
                  ),

                  // Gesture layer — sadece slider modunda sürükle aktif
                  if (_mode == _CompareMode.slider)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: (d) =>
                            _updateFromGlobal(d.globalPosition, ctx),
                        onHorizontalDragUpdate: (d) =>
                            _updateFromGlobal(d.globalPosition, ctx),
                        onDoubleTap: () => _openZoom(context),
                      ),
                    )
                  else
                    // After/Before odak modunda: çift tıkla zoom, tek tıkla
                    // slider'a dön.
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _setMode(_CompareMode.slider),
                        onDoubleTap: () => _openZoom(context),
                      ),
                    ),

                  // Çerçeve
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: KoalaColors.border, width: 0.5),
                          borderRadius:
                              BorderRadius.circular(KoalaRadius.lg),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),

        // ─── Mode segment control ─────────────────────────────────
        const SizedBox(height: KoalaSpacing.sm),
        _ModeSegment(
          mode: _mode,
          onChanged: _setMode,
        ),
      ],
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

/// Slider | Önce | Sonra segment kontrolü.
class _ModeSegment extends StatelessWidget {
  final _CompareMode mode;
  final ValueChanged<_CompareMode> onChanged;

  const _ModeSegment({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: KoalaColors.surfaceAlt,
        borderRadius: BorderRadius.circular(KoalaRadius.pill),
      ),
      child: Row(
        children: [
          _segItem(_CompareMode.slider, 'Karşılaştır', LucideIcons.arrowLeftRight),
          _segItem(_CompareMode.before, 'Önce', LucideIcons.image),
          _segItem(_CompareMode.after, 'Sonra', LucideIcons.sparkles),
        ],
      ),
    );
  }

  Widget _segItem(_CompareMode m, String label, IconData icon) {
    final active = mode == m;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(m),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? KoalaColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(KoalaRadius.pill),
            boxShadow: active ? KoalaShadows.card : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 13,
                  color: active ? KoalaColors.text : KoalaColors.textSec),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? KoalaColors.text : KoalaColors.textSec,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Köşedeki yarı saydam icon button (zoom için).
class _IconButtonChip extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconButtonChip({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KoalaColors.surface.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 16, color: KoalaColors.text),
        ),
      ),
    );
  }
}

/// Tam ekran zoom modal — pinch + pan, tek tıkla kapat.
class _ZoomModal extends StatefulWidget {
  final Uint8List beforeBytes;
  final String afterSrc;
  final bool initialAfter;
  const _ZoomModal({
    required this.beforeBytes,
    required this.afterSrc,
    required this.initialAfter,
  });

  @override
  State<_ZoomModal> createState() => _ZoomModalState();
}

class _ZoomModalState extends State<_ZoomModal> {
  late bool _showAfter = widget.initialAfter;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Stack(
        children: [
          // Görsel — InteractiveViewer ile pinch + pan
          Positioned.fill(
            child: InteractiveViewer(
              maxScale: 4,
              minScale: 1,
              child: Center(
                child: _showAfter
                    ? _afterContent(widget.afterSrc)
                    : Image.memory(widget.beforeBytes, fit: BoxFit.contain),
              ),
            ),
          ),

          // Üst bar — kapat + toggle
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    _ZoomBarButton(
                      icon: LucideIcons.x,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    _ZoomToggleChip(
                      showAfter: _showAfter,
                      onChanged: (v) => setState(() => _showAfter = v),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _afterContent(String s) {
    if (s.startsWith('data:image')) {
      final commaIdx = s.indexOf(',');
      if (commaIdx < 0) return const SizedBox.shrink();
      try {
        final b = base64Decode(s.substring(commaIdx + 1));
        return Image.memory(b, fit: BoxFit.contain);
      } catch (_) {
        return const SizedBox.shrink();
      }
    }
    if (s.isEmpty) return const SizedBox.shrink();
    return CachedNetworkImage(imageUrl: s, fit: BoxFit.contain);
  }
}

class _ZoomBarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ZoomBarButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

class _ZoomToggleChip extends StatelessWidget {
  final bool showAfter;
  final ValueChanged<bool> onChanged;
  const _ZoomToggleChip({required this.showAfter, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!showAfter),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(KoalaRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              showAfter ? LucideIcons.sparkles : LucideIcons.image,
              size: 14,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              showAfter ? 'Sonra' : 'Önce',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
