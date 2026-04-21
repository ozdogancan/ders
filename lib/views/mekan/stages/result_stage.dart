import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../editorial_theme.dart';
import '../widgets/before_after.dart';
import '../widgets/editorial_primitives.dart';

class ResultStage extends StatelessWidget {
  final Uint8List beforeBytes;
  final String afterSrc;
  final String room;
  final String theme;
  final bool mock;
  final VoidCallback onRetry;
  final VoidCallback onNewStyle;
  final VoidCallback onRestart;
  final VoidCallback onPro;

  const ResultStage({
    super.key,
    required this.beforeBytes,
    required this.afterSrc,
    required this.room,
    required this.theme,
    required this.mock,
    required this.onRetry,
    required this.onNewStyle,
    required this.onRestart,
    required this.onPro,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 28),
            const Ordinal(n: '04', label: 'Sonuç'),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    theme,
                    style: MekanType.display(size: 28, italic: true)
                        .copyWith(letterSpacing: -0.5),
                  ),
                ),
                Caps(room, size: 10),
              ],
            ),
            const SizedBox(height: 14),
            BeforeAfter(beforeBytes: beforeBytes, afterSrc: afterSrc),
            if (mock) ...[
              const SizedBox(height: 14),
              Text(
                'DEMO · sunucu env\'inde anahtar ayarlandığında gerçek görseller gelir.',
                style: MekanType.mono(
                    size: 10, color: MekanPalette.burnt, tracking: 1.5),
              ),
            ],
            const SizedBox(height: 22),
            const Hairline(),
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: EButton(
                      label: 'Aynı tarzda tekrar',
                      onTap: onRetry,
                      fullWidth: true,
                    ),
                  ),
                  Container(width: 1, color: MekanPalette.line),
                  Expanded(
                    child: EButton(
                      label: 'Başka tarz dene',
                      onTap: onNewStyle,
                      fullWidth: true,
                    ),
                  ),
                ],
              ),
            ),
            const Hairline(),
            const SizedBox(height: 22),
            PrimaryPill(
              label: 'Bu tasarımı gerçeğe dönüştür',
              onTap: onPro,
            ),
            const SizedBox(height: 18),
            Text(
              'Bu odayı tasarlayabilecek iç mimarları sana getirelim — '
              'şehrinden ve senin tarzından çalışanları önce gösteririz.',
              style: MekanType.body(size: 14, italic: true, color: MekanPalette.fog),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: EButton(
                label: 'Yeni bir fotoğrafla başla',
                onTap: onRestart,
              ),
            ),
            const SizedBox(height: 36),
          ],
        ),
      ),
    );
  }
}
