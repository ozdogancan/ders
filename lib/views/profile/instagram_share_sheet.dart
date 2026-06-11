// Instagram-tarzı paylaş bottom-sheet.
//
// Kanallar:
//   - WhatsApp (api.whatsapp.com deep link) — çalışır
//   - Instagram → "Yakında" stub (deep link IG'ye doğrudan görsel paylaşımı
//     desteklemediği için bilinçli stub)
//   - Bağlantıyı kopyala — clipboard
//   - Sistem Paylaş — share_plus native sheet
//
// Tasarım: 4 yuvarlak ikon + label, koala-IG vibes (white bg, rounded corners).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/koala_ds.dart';
import '../../core/theme/koala_tokens.dart';

/// IG-tarzı paylaş sheet'i.
///   [title]      — paylaşılan içeriğin başlığı (snackbar/share metni)
///   [imageUrl]   — varsa tasarımın görsel URL'i (WhatsApp + sistem paylaşımı)
///   [linkUrl]    — paylaşılacak kanonik link (yoksa imageUrl kullanılır)
class InstagramShareSheet {
  InstagramShareSheet._();

  static Future<void> show(
    BuildContext context, {
    required String title,
    String? imageUrl,
    String? linkUrl,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      isScrollControlled: false,
      builder: (_) => _InstagramShareBody(
        title: title,
        imageUrl: imageUrl,
        linkUrl: linkUrl,
      ),
    );
  }
}

class _InstagramShareBody extends StatelessWidget {
  final String title;
  final String? imageUrl;
  final String? linkUrl;
  const _InstagramShareBody({
    required this.title,
    this.imageUrl,
    this.linkUrl,
  });

  String get _shareText {
    final link = (linkUrl ?? '').isNotEmpty
        ? linkUrl!
        : (imageUrl ?? 'https://koalatutor.com');
    return 'Koala\'da bu tasarıma bayıldım: $title\n$link';
  }

  Future<void> _whatsApp(BuildContext context) async {
    Navigator.of(context).pop();
    final uri = Uri.parse(
      'https://api.whatsapp.com/send?text=${Uri.encodeComponent(_shareText)}',
    );
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        _toast(context, 'WhatsApp açılamadı');
      }
    } catch (_) {
      if (context.mounted) _toast(context, 'WhatsApp açılamadı');
    }
  }

  void _instagramSoon(BuildContext context) {
    Navigator.of(context).pop();
    _toast(context, 'Instagram paylaşımı yakında');
  }

  Future<void> _copyLink(BuildContext context) async {
    Navigator.of(context).pop();
    final link =
        (linkUrl ?? imageUrl ?? 'https://koalatutor.com').toString();
    await Clipboard.setData(ClipboardData(text: link));
    if (context.mounted) _toast(context, 'Bağlantı kopyalandı');
  }

  Future<void> _systemShare(BuildContext context) async {
    Navigator.of(context).pop();
    try {
      await Share.share(_shareText, subject: title);
    } catch (_) {/* sessiz */}
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Paylaş',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: KoalaColors.text,
                ),
              ),
            ),
            const SizedBox(height: 14),
            // 4 channel row — IG-style circular icons.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _channel(
                  icon: LucideIcons.messageCircle,
                  label: 'WhatsApp',
                  gradient: const [Color(0xFF25D366), Color(0xFF128C7E)],
                  onTap: () => _whatsApp(context),
                ),
                _channel(
                  icon: LucideIcons.instagram,
                  label: 'Instagram',
                  gradient: const [
                    Color(0xFFFEDA75),
                    Color(0xFFFA7E1E),
                    Color(0xFFD62976),
                    Color(0xFF962FBF),
                  ],
                  badge: 'Yakında',
                  onTap: () => _instagramSoon(context),
                ),
                _channel(
                  icon: LucideIcons.link,
                  label: 'Linki kopyala',
                  gradient: const [KoalaDS.accent, KoalaDS.accentDeep],
                  onTap: () => _copyLink(context),
                ),
                _channel(
                  icon: LucideIcons.share2,
                  label: 'Daha fazla',
                  gradient: const [KoalaDS.inkFaint, KoalaDS.inkSoft],
                  onTap: () => _systemShare(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _channel({
    required IconData icon,
    required String label,
    required List<Color> gradient,
    required VoidCallback onTap,
    String? badge,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: gradient,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                  if (badge != null)
                    Positioned(
                      top: -4,
                      right: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: KoalaColors.text,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: KoalaColors.text,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
