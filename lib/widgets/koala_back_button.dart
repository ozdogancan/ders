import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/koala_tokens.dart';

/// Shared back button for Koala AppBars.
///
/// Drop-in for `AppBar.leading`: returns a 40x40 circular pill with a soft
/// purple-tinted surface, a lucide arrow-left icon centered inside, and a
/// subtle border. Uses `Navigator.maybePop` by default.
class KoalaBackButton extends StatelessWidget {
  const KoalaBackButton({
    super.key,
    this.onTap,
    this.padding = const EdgeInsets.only(left: 12),
  });

  /// Custom tap handler. Defaults to `Navigator.maybePop`.
  final VoidCallback? onTap;

  /// Outer padding around the 40x40 tap target.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Center(
        child: Material(
          color: KoalaColors.surface,
          shape: CircleBorder(
            side: BorderSide(
              color: KoalaColors.borderSolid.withValues(alpha: 0.8),
              width: 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              HapticFeedback.selectionClick();
              if (onTap != null) {
                onTap!();
              } else {
                Navigator.maybePop(context);
              }
            },
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: Icon(
                  LucideIcons.arrowLeft,
                  size: 18,
                  color: KoalaColors.accentDeep,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
