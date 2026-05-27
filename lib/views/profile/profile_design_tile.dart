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
  final bool isAi;
  final VoidCallback onTap;
  final VoidCallback onApply;
  final VoidCallback onAsk;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const ProfileDesignTile({
    super.key,
    required this.item,
    this.isAi = false,
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
    final extra = item['extra_data'];
    final beforeUrl = extra is Map
        ? (extra['before_url']?.toString() ?? '')
        : '';
    final hasBeforeAfter = isAi && beforeUrl.isNotEmpty && imageUrl.isNotEmpty;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      onLongPress: () => _openActions(context),
      child: Hero(
        tag: 'design-$id',
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Base after image (or placeholder).
            Container(
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
            // Before/After split overlay — only when both exist. Diagonal
            // clip shows BEFORE in the bottom-left triangle, AFTER (base)
            // in the top-right. Hairline divider makes the split readable.
            if (hasBeforeAfter)
              IgnorePointer(
                child: ClipPath(
                  clipper: _DiagonalClipper(),
                  child: CachedNetworkImage(
                    imageUrl: beforeUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, _) =>
                        Container(color: KoalaColors.surfaceAlt),
                    errorWidget: (_, _, _) =>
                        Container(color: KoalaColors.surfaceAlt),
                  ),
                ),
              ),
            if (hasBeforeAfter)
              IgnorePointer(
                child: CustomPaint(
                  painter: _DiagonalDividerPainter(),
                  size: Size.infinite,
                ),
              ),
            // Tiny corner labels (Önce / Sonra).
            if (hasBeforeAfter) ...[
              const Positioned(
                left: 4,
                bottom: 4,
                child: _CornerLabel(text: 'Önce'),
              ),
              const Positioned(
                right: 4,
                top: 4,
                child: _CornerLabel(text: 'Sonra'),
              ),
            ],
            // AI pill — top-right (only when no before/after, otherwise the
            // "Sonra" label already carries that signal).
            if (isAi && !hasBeforeAfter)
              const Positioned(
                top: 5,
                right: 5,
                child: _AiPill(),
              ),
          ],
        ),
      ),
    );
  }
}

/// Diagonal clipper — bottom-left triangle reveals BEFORE underneath the
/// AFTER base layer.
class _DiagonalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final p = Path();
    p.moveTo(0, 0);
    p.lineTo(0, size.height);
    p.lineTo(size.width, size.height);
    p.close();
    return p;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Hairline diagonal divider between BEFORE (bottom-left) and AFTER
/// (top-right) — subtle white line with soft shadow for readability.
class _DiagonalDividerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, 0),
      shadow,
    );
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, 0),
      line,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CornerLabel extends StatelessWidget {
  final String text;
  const _CornerLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.2,
          height: 1.0,
        ),
      ),
    );
  }
}

class _AiPill extends StatelessWidget {
  const _AiPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(99),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.sparkles,
              size: 8, color: KoalaColors.accentDeep),
          const SizedBox(width: 3),
          const Text(
            'AI',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              color: KoalaColors.accentDeep,
              letterSpacing: 0.3,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
