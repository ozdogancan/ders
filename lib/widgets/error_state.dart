import 'package:flutter/material.dart';
import '../core/theme/koala_tokens.dart';

/// Hata durumu widget'ı — veri yüklenemediğinde gösterilir
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    this.message = 'Bir şeyler ters gitti',
    this.description = 'Lütfen tekrar deneyin.',
    this.onRetry,
  });

  final String message;
  final String? description;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KoalaSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 56, color: KoalaColors.textTer),
            const SizedBox(height: KoalaSpacing.lg),
            Text(
              message,
              style: KoalaText.h3,
              textAlign: TextAlign.center,
            ),
            if (description != null) ...[
              const SizedBox(height: KoalaSpacing.sm),
              Text(
                description!,
                style: KoalaText.bodySec,
                textAlign: TextAlign.center,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: KoalaSpacing.xl),
              GestureDetector(
                onTap: onRetry,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KoalaSpacing.xl,
                    vertical: KoalaSpacing.md,
                  ),
                  decoration: KoalaDeco.accentPill,
                  child: const Text('Tekrar Dene', style: KoalaText.button),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
