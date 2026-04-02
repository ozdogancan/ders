import 'package:flutter/material.dart';
import '../core/theme/koala_tokens.dart';

/// Boş durum widget'ı — veri yokken gösterilir
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.buttonText,
    this.onButtonTap,
  });

  final IconData icon;
  final String title;
  final String? description;
  final String? buttonText;
  final VoidCallback? onButtonTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KoalaSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: KoalaColors.textTer),
            const SizedBox(height: KoalaSpacing.lg),
            Text(
              title,
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
            if (buttonText != null && onButtonTap != null) ...[
              const SizedBox(height: KoalaSpacing.xl),
              GestureDetector(
                onTap: onButtonTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KoalaSpacing.xl,
                    vertical: KoalaSpacing.md,
                  ),
                  decoration: KoalaDeco.accentPill,
                  child: Text(buttonText!, style: KoalaText.button),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
