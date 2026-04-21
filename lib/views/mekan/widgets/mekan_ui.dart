import 'package:flutter/material.dart';
import '../../../core/theme/koala_tokens.dart';

/// Ana aksiyon — dolgulu mor pill.
class MekanPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool fullWidth;
  final IconData? trailing;
  const MekanPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.fullWidth = true,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KoalaRadius.xl),
          child: Ink(
            decoration: KoalaDeco.accentPill,
            child: Container(
              width: fullWidth ? double.infinity : null,
              padding: const EdgeInsets.symmetric(
                vertical: 16,
                horizontal: KoalaSpacing.xxl,
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      style: KoalaText.button,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    Icon(trailing, size: 18, color: Colors.white),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// İkincil aksiyon — outline buton.
class MekanSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool fullWidth;
  final IconData? icon;
  const MekanSecondaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.fullWidth = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(KoalaRadius.xl),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KoalaRadius.xl),
          child: Container(
            width: fullWidth ? double.infinity : null,
            padding: const EdgeInsets.symmetric(
              vertical: 14,
              horizontal: KoalaSpacing.xl,
            ),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(KoalaRadius.xl),
              border: Border.all(color: KoalaColors.borderSolid, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: KoalaColors.text),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: KoalaColors.text,
                    ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Küçük bilgi rozeti — "Salon tespit edildi" gibi.
class MekanChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? tint;
  const MekanChip({super.key, required this.label, this.icon, this.tint});

  @override
  Widget build(BuildContext context) {
    final bg = tint ?? KoalaColors.accentLight;
    final fg = tint == null ? KoalaColors.accentDeep : KoalaColors.text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(KoalaRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Basit üst bar — geri butonu + ortalanmış başlık.
class MekanAppBar extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  const MekanAppBar({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KoalaSpacing.sm, KoalaSpacing.sm, KoalaSpacing.lg, KoalaSpacing.sm),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 20, color: KoalaColors.text),
              splashRadius: 22,
            )
          else
            const SizedBox(width: 48),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: KoalaText.h3,
            ),
          ),
          SizedBox(width: 48, child: trailing),
        ],
      ),
    );
  }
}
