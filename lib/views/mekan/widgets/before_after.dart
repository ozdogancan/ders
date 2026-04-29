import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui show ImageFilter;
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
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.94),
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, anim, _) {
          return FadeTransition(
            opacity: anim,
            child: _ZoomModal(
              beforeBytes: widget.beforeBytes,
              afterSrc: widget.afterSrc,
              initialAfter: _mode != _CompareMode.before,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
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

                  // Gesture layer — ÖNCE (alt katman) ki üstüne gelen
                  // butonlar tap eat'lemesin.
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
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _setMode(_CompareMode.slider),
                        onDoubleTap: () => _openZoom(context),
                      ),
                    ),

                  // Köşe etiketleri — Önce: koyu cam, Sonra: mor accent
                  if (_mode == _CompareMode.slider) ...[
                    _darkLabel(top: 14, left: 14, text: 'Önce'),
                    _accentLabel(top: 14, right: 14, text: 'Sonra'),
                  ] else if (_mode == _CompareMode.after)
                    _accentLabel(top: 14, left: 14, text: 'Sonra')
                  else
                    _darkLabel(top: 14, left: 14, text: 'Önce'),

                  // Zoom (büyüteç) butonu — gesture'dan sonra ki tap'i alır
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: _ZoomFab(onTap: () => _openZoom(context)),
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

  /// "Önce" — koyu cam pill (siyahımsı, hafif blur).
  Widget _darkLabel({
    double? top, double? left, double? right,
    required String text,
  }) =>
      Positioned(
        top: top, left: left, right: right,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18),
                  width: 0.6,
                ),
              ),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ),
        ),
      );

  /// "Sonra" — mor accent pill (brand'in dili).
  Widget _accentLabel({
    double? top, double? left, double? right,
    required String text,
  }) =>
      Positioned(
        top: top, left: left, right: right,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: KoalaColors.accentSoft,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: KoalaColors.accent.withValues(alpha: 0.32),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: KoalaColors.accentDeep,
              letterSpacing: 0.1,
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
    // Karşılaştır seçili olduğunda mor accent (brand vurgusu); diğer
    // ikisi (Önce/Sonra) seçili iken koyu metin — daha sakin görünür.
    final isCompare = m == _CompareMode.slider;
    final activeColor =
        isCompare ? KoalaColors.accentDeep : KoalaColors.text;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(m),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: active ? KoalaColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(KoalaRadius.pill),
            boxShadow: active ? KoalaShadows.card : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 14,
                  color: active ? activeColor : KoalaColors.textSec),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active ? activeColor : KoalaColors.textSec,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Glass FAB — büyüt ikonu, opak yerine cam görünüm.
class _ZoomFab extends StatelessWidget {
  final VoidCallback onTap;
  const _ZoomFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          color: Colors.white.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.6),
              width: 0.7,
            ),
          ),
          elevation: 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(LucideIcons.expand, size: 18, color: KoalaColors.text),
            ),
          ),
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
