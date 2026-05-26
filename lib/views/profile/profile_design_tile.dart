// Square Instagram-style grid tile.
// - Tap → swipe-detail (caller passes the list + index).
// - Long-press → bottom sheet with Uygula / Sor / Paylaş / Düzenle / Sil / İptal.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/koala_tokens.dart';

class ProfileDesignTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback onApply;
  final VoidCallback onAsk;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const ProfileDesignTile({
    super.key,
    required this.item,
    required this.onTap,
    required this.onApply,
    required this.onAsk,
    required this.onEdit,
    required this.onDelete,
  });

  void _openActions(BuildContext context) {
    HapticFeedback.selectionClick();
    final imageUrl = (item['image_url'] as String?) ?? '';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KoalaColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: KoalaColors.border,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const SizedBox(height: 8),
            _action(
              ctx,
              icon: LucideIcons.wand,
              label: 'Uygula',
              sub: 'Bu tarzı kendi mekânına uygula',
              onTap: () {
                Navigator.pop(ctx);
                onApply();
              },
            ),
            _action(
              ctx,
              icon: LucideIcons.messageCircle,
              label: 'Sor',
              sub: 'Bu tasarım hakkında sor',
              onTap: () {
                Navigator.pop(ctx);
                onAsk();
              },
            ),
            _action(
              ctx,
              icon: LucideIcons.share2,
              label: 'WhatsApp\'ta paylaş',
              sub: 'Tasarımı arkadaşına gönder',
              onTap: () async {
                Navigator.pop(ctx);
                await _shareWhatsApp(imageUrl);
              },
            ),
            const Divider(height: 1, color: KoalaColors.borderSolid),
            _action(
              ctx,
              icon: LucideIcons.pencil,
              label: 'Düzenle',
              onTap: () {
                Navigator.pop(ctx);
                onEdit();
              },
            ),
            _action(
              ctx,
              icon: LucideIcons.trash2,
              iconColor: KoalaColors.error,
              labelColor: KoalaColors.error,
              label: 'Sil',
              onTap: () {
                Navigator.pop(ctx);
                onDelete();
              },
            ),
            _action(
              ctx,
              icon: LucideIcons.x,
              iconColor: KoalaColors.textSec,
              label: 'İptal',
              onTap: () => Navigator.pop(ctx),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _action(
    BuildContext context, {
    required IconData icon,
    required String label,
    String? sub,
    Color iconColor = KoalaColors.accentDeep,
    Color labelColor = KoalaColors.text,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: labelColor,
        ),
      ),
      subtitle: sub != null ? Text(sub, style: KoalaText.caption) : null,
      onTap: onTap,
    );
  }

  Future<void> _shareWhatsApp(String imageUrl) async {
    final text = imageUrl.isEmpty
        ? 'Koala\'da bu tasarıma bayıldım! https://koalatutor.com'
        : 'Koala\'da bu tasarıma bayıldım, sana da göstermek istedim:\n$imageUrl\n\nhttps://koalatutor.com';
    final uri =
        Uri.parse('https://api.whatsapp.com/send?text=${Uri.encodeComponent(text)}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {/* swallow */}
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = (item['image_url'] as String?) ?? '';
    final title = (item['title'] as String?) ?? 'Mekan';
    final id = item['id']?.toString() ?? title;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      onLongPress: () => _openActions(context),
      child: Hero(
        tag: 'design-$id',
        child: Container(
          color: KoalaColors.surfaceAlt,
          child: imageUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, _) =>
                      Container(color: KoalaColors.surfaceAlt),
                  errorWidget: (_, _, _) => Container(
                    color: KoalaColors.surfaceAlt,
                    child: Center(
                      child: Semantics(
                        label: title,
                        child: const Icon(LucideIcons.imageOff,
                            color: KoalaColors.textTer, size: 22),
                      ),
                    ),
                  ),
                )
              : Container(color: KoalaColors.surfaceAlt),
        ),
      ),
    );
  }
}
