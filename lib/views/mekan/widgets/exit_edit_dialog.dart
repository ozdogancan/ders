import 'package:flutter/material.dart';
import '../../../core/theme/koala_tokens.dart';

/// Mekan/widget düzenleme akışından çıkarken kullanıcıya gösterilen
/// onay diyaloğu. `true` döner → kullanıcı çıkışı onayladı (caller pop yapar).
/// `false` döner → kullanıcı vazgeçti, editöre dön.
///
/// Diyalog kendi içinde self-contained — herhangi bir editing flow'da
/// kullanılabilir. Dış tıklama ile kapanmaz.
Future<bool> showExitEditDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => const _ExitEditDialog(),
  );
  return result ?? false;
}

class _ExitEditDialog extends StatelessWidget {
  const _ExitEditDialog();

  static const _accent = Color(0xFFFF5A5F);
  static const _greyBtn = Color(0xFFF1F3F5);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Hero illustration (placeholder).
            // TODO: replace placeholder with Gemini-generated lamp+armchair
            // illustration at assets/images/koala_exit_dialog.png
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F3F5),
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.chair_outlined,
                size: 64,
                color: _accent,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Düzenleme modundan çıkmak istiyor musunuz?',
              textAlign: TextAlign.center,
              style: KoalaText.h2.copyWith(
                fontWeight: FontWeight.w700,
                color: KoalaColors.text,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Tüm mevcut görevleriniz iptal edilecek ve veriler kaydedilmeyecek.',
              textAlign: TextAlign.center,
              style: KoalaText.bodySec.copyWith(
                color: KoalaColors.textSec,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                // LEFT: grey "Çıkış" — confirms exit.
                Expanded(
                  child: _DialogButton(
                    label: 'Çıkış',
                    background: _greyBtn,
                    foreground: KoalaColors.text,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ),
                const SizedBox(width: 12),
                // RIGHT: red "İptal" — closes the dialog, stays in editor.
                Expanded(
                  child: _DialogButton(
                    label: 'İptal',
                    background: _accent,
                    foreground: Colors.white,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;
  const _DialogButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          child: Text(
            label,
            style: KoalaText.label.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
