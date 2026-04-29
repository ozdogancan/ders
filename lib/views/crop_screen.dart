import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/koala_tokens.dart';

/// Tam ekran kırp + rotate — snaphome benzeri sade.
/// Siyah background + kadraj dikdörtgeni + 3x3 grid + köşe kollar.
/// Üstte: geri (sol) + rotate (sağ). Altta: kırmızı "Devam et" butonu.
class CropScreen extends StatefulWidget {
  final Uint8List imageBytes;
  const CropScreen({super.key, required this.imageBytes});

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  final _controller = CropController();
  bool _busy = false;
  late Uint8List _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = widget.imageBytes;
  }

  Future<void> _rotate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final decoded = img.decodeImage(_bytes);
      if (decoded == null) {
        setState(() => _busy = false);
        return;
      }
      final rotated = img.copyRotate(decoded, angle: 90);
      final encoded = Uint8List.fromList(img.encodeJpg(rotated, quality: 90));
      setState(() {
        _bytes = encoded;
        _busy = false;
      });
      _controller.image = encoded;
    } catch (_) {
      setState(() => _busy = false);
    }
  }

  void _confirm() {
    if (_busy) return;
    setState(() => _busy = true);
    _controller.crop();
  }

  void _onCropped(CropResult result) {
    if (!mounted) return;
    if (result is CropSuccess) {
      Navigator.of(context).pop<Uint8List>(result.croppedImage);
    } else if (result is CropFailure) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kırpma başarısız, tekrar dene')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Top bar ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.chevronLeft,
                        color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(LucideIcons.rotateCw,
                        color: Colors.white, size: 22),
                    tooltip: 'Sağa döndür',
                    onPressed: _rotate,
                  ),
                ],
              ),
            ),
            // ─── Crop area ──────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Crop(
                  controller: _controller,
                  image: _bytes,
                  onCropped: _onCropped,
                  baseColor: Colors.black,
                  maskColor: Colors.black.withValues(alpha: 0.55),
                  cornerDotBuilder: (size, edge) => Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.rectangle,
                    ),
                  ),
                  interactive: true,
                  initialRectBuilder: InitialRectBuilder.withBuilder(
                    (viewportRect, imageRect) {
                      // Başlangıçta görüntünün tamamı seçili.
                      return Rect.fromLTRB(
                        imageRect.left + 8,
                        imageRect.top + 8,
                        imageRect.right - 8,
                        imageRect.bottom - 8,
                      );
                    },
                  ),
                  willUpdateScale: (newScale) => newScale < 5,
                  progressIndicator: const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            // ─── Bottom CTA ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: SizedBox(
                height: 54,
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE45A55), // kırmızı
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _busy ? null : _confirm,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor:
                                AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Text(
                          'Devam et',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
