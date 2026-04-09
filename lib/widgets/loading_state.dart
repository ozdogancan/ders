import 'package:flutter/material.dart';
import '../core/theme/koala_tokens.dart';

/// Standart loading widget — tüm ekranlarda kullanılmalı.
/// CircularProgressIndicator yerine bu widget tercih edilmeli.
class LoadingState extends StatelessWidget {
  const LoadingState({
    super.key,
    this.message,
    this.useShimmer = false,
  });

  final String? message;
  /// true ise shimmer efekti gösterir, false ise spinner
  final bool useShimmer;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KoalaSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: KoalaColors.accent,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: KoalaSpacing.lg),
              Text(
                message!,
                style: KoalaText.bodySec,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
