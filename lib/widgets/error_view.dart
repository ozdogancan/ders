import 'package:flutter/material.dart';
import '../core/theme/koala_tokens.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Global error widget — network, server, timeout hataları
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.type = ErrorType.general,
  });

  final String message;
  final VoidCallback? onRetry;
  final ErrorType type;

  factory ErrorView.network({VoidCallback? onRetry}) => ErrorView(
    message: 'Bağlantı sorunu. İnternetini kontrol et.',
    onRetry: onRetry,
    type: ErrorType.network,
  );

  factory ErrorView.server({VoidCallback? onRetry}) => ErrorView(
    message: 'Bir sorun oluştu. Biraz sonra tekrar dene.',
    onRetry: onRetry,
    type: ErrorType.server,
  );

  factory ErrorView.timeout({VoidCallback? onRetry}) => ErrorView(
    message: 'İstek zaman aşımına uğradı.',
    onRetry: onRetry,
    type: ErrorType.timeout,
  );

  IconData get _icon {
    switch (type) {
      case ErrorType.network: return LucideIcons.wifiOff;
      case ErrorType.server: return LucideIcons.cloudOff;
      case ErrorType.timeout: return LucideIcons.timerOff;
      case ErrorType.general: return LucideIcons.alertCircle;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KoalaSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: 48, color: KoalaColors.textTer),
            const SizedBox(height: KoalaSpacing.lg),
            Text(message, style: KoalaText.bodySec, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: KoalaSpacing.xl),
              GestureDetector(
                onTap: onRetry,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.xl, vertical: KoalaSpacing.md),
                  decoration: BoxDecoration(
                    color: KoalaColors.accent,
                    borderRadius: BorderRadius.circular(KoalaRadius.md),
                  ),
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

enum ErrorType { network, server, timeout, general }
