import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../core/theme/koala_tokens.dart';
import '../widgets/before_after.dart';
import '../widgets/mekan_ui.dart';

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
      padding: const EdgeInsets.fromLTRB(
        KoalaSpacing.xl, KoalaSpacing.md, KoalaSpacing.xl, KoalaSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Yeni $room', style: KoalaText.h1),
          const SizedBox(height: KoalaSpacing.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              MekanChip(label: room, icon: Icons.home_outlined),
              MekanChip(label: theme, tint: KoalaColors.surfaceAlt),
            ],
          ),
          const SizedBox(height: KoalaSpacing.lg),
          BeforeAfter(beforeBytes: beforeBytes, afterSrc: afterSrc),
          if (mock) ...[
            const SizedBox(height: KoalaSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: KoalaColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(KoalaRadius.md),
                border: Border.all(
                    color: KoalaColors.warning.withValues(alpha: 0.45),
                    width: 0.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: KoalaColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Demo · sunucuda anahtar ayarlandığında gerçek görseller gelir.',
                      style: KoalaText.bodySmall.copyWith(
                        color: KoalaColors.warning,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: KoalaSpacing.xxl),
          Row(
            children: [
              Expanded(
                child: MekanSecondaryButton(
                  label: 'Aynı tarzda tekrar',
                  onTap: onRetry,
                  fullWidth: true,
                  icon: Icons.refresh_rounded,
                ),
              ),
              const SizedBox(width: KoalaSpacing.md),
              Expanded(
                child: MekanSecondaryButton(
                  label: 'Başka tarz',
                  onTap: onNewStyle,
                  fullWidth: true,
                  icon: Icons.palette_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: KoalaSpacing.lg),
          MekanPrimaryButton(
            label: 'Bu tasarımı gerçeğe dönüştür',
            onTap: onPro,
            trailing: Icons.arrow_forward_rounded,
          ),
          const SizedBox(height: KoalaSpacing.md),
          Text(
            'Bu odayı tasarlayabilecek iç mimarları sana getirelim — '
            'şehrinden ve senin tarzından çalışanları önce gösteririz.',
            style: KoalaText.bodySec,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: KoalaSpacing.xl),
          Center(
            child: TextButton(
              onPressed: onRestart,
              child: Text(
                'Yeni fotoğrafla başla',
                style: KoalaText.label.copyWith(
                  color: KoalaColors.accentDeep,
                  decoration: TextDecoration.underline,
                  decorationColor: KoalaColors.accentDeep,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
