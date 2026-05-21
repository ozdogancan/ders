import 'package:flutter/material.dart';

import '../core/theme/koala_tokens.dart';

/// Toast türü — renk + ikon seçimini belirler.
enum ToastKind { success, error, info }

/// Modern, yumuşak görünümlü toast/snackbar gösterir.
///
/// Floating, yuvarlak köşeli (17), hafif gölgeli, küçük leading ikon içeren
/// bilgilendirme bildirimi. Mevcut SnackBar çağrıları zamanla buraya
/// taşınabilir; eski call-site'lar `app_theme.dart` içindeki
/// `snackBarTheme` sayesinde zaten yeni görünümü miras alır.
///
/// Kullanım:
/// ```dart
/// showToast(context, 'Kaydedildi', kind: ToastKind.success);
/// ```
void showToast(
  BuildContext context,
  String message, {
  ToastKind kind = ToastKind.info,
  Duration duration = const Duration(seconds: 3),
}) {
  final messenger = ScaffoldMessenger.of(context);

  final Color bg;
  final IconData icon;
  switch (kind) {
    case ToastKind.success:
      bg = KoalaColors.greenBright; // #22C55E
      icon = Icons.check_circle;
      break;
    case ToastKind.error:
      bg = KoalaColors.errorBright; // #EF4444
      icon = Icons.error;
      break;
    case ToastKind.info:
      bg = KoalaColors.ink; // #1A1D2A koyu charcoal
      icon = Icons.info;
      break;
  }

  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      duration: duration,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: Colors.transparent,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(17),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
