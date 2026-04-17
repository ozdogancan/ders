import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:go_router/go_router.dart';

import '../core/theme/koala_tokens.dart';
import '../services/messaging_service.dart';
import '../services/evlumba_live_service.dart';
import '../services/saved_items_service.dart';
import '../services/share_service.dart';

/// Paylaş modal sheet'i — 3 kanal:
///   1) Sohbette paylaş → conversation picker → shareInChat
///   2) Bağlantıyı kopyala → clipboard
///   3) Sistem paylaş → share_plus (iOS/Android/web)
///
/// Kullanım:
///   ShareSheet.show(context,
///     itemType: SavedItemType.design, itemId: projectId,
///     title: 'Salon tasarımı', imageUrl: coverUrl);
class ShareSheet {
  ShareSheet._();

  static Future<void> show(
    BuildContext context, {
    required SavedItemType itemType,
    required String itemId,
    String? title,
    String? imageUrl,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareSheetBody(
        itemType: itemType,
        itemId: itemId,
        title: title,
        imageUrl: imageUrl,
      ),
    );
  }
}

class _ShareSheetBody extends StatelessWidget {
  const _ShareSheetBody({
    required this.itemType,
    required this.itemId,
    this.title,
    this.imageUrl,
  });

  final SavedItemType itemType;
  final String itemId;
  final String? title;
  final String? imageUrl;

  void _close(BuildContext context) {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _copyLink(BuildContext context) async {
    await ShareService.copyLink(type: itemType, itemId: itemId);
    if (!context.mounted) return;
    _close(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Bağlantı kopyalandı'),
        duration: Duration(seconds: 2),
      ));
  }

  Future<void> _systemShare(BuildContext context) async {
    _close(context);
    await ShareService.nativeShare(
      type: itemType,
      itemId: itemId,
      title: title,
    );
  }

  Future<void> _chatShare(BuildContext context) async {
    _close(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConversationPickerSheet(
        itemType: itemType,
        itemId: itemId,
        title: title,
        imageUrl: imageUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Paylaş',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: KoalaColors.text,
              ),
            ),
            if (title != null && title!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                title!,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 16),
            _ShareAction(
              icon: LucideIcons.messageCircle,
              label: 'Sohbette paylaş',
              subtitle: 'Tasarımcıyla dahili mesaj olarak gönder',
              color: KoalaColors.accent,
              onTap: () => _chatShare(context),
            ),
            _ShareAction(
              icon: LucideIcons.link,
              label: 'Bağlantıyı kopyala',
              subtitle: 'URL panoya alınır',
              color: KoalaColors.greenAlt,
              onTap: () => _copyLink(context),
            ),
            _ShareAction(
              icon: LucideIcons.share2,
              label: 'Diğer uygulamalar',
              subtitle: 'WhatsApp, e-posta, sistem paylaş',
              color: const Color(0xFF6366F1),
              onTap: () => _systemShare(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareAction extends StatelessWidget {
  const _ShareAction({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: KoalaColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronRight,
                  size: 18, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mevcut sohbetler listesi — paylaşım hedefi seçmek için.
/// Sohbeti yoksa: "Önce bir tasarımcıya mesaj at" empty state.
class _ConversationPickerSheet extends StatefulWidget {
  const _ConversationPickerSheet({
    required this.itemType,
    required this.itemId,
    this.title,
    this.imageUrl,
  });

  final SavedItemType itemType;
  final String itemId;
  final String? title;
  final String? imageUrl;

  @override
  State<_ConversationPickerSheet> createState() =>
      _ConversationPickerSheetState();
}

class _ConversationPickerSheetState extends State<_ConversationPickerSheet> {
  List<Map<String, dynamic>> _convs = [];
  final Map<String, Map<String, String?>> _designerCache = {};
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final convs = await MessagingService.getConversations(limit: 30);
      // Designer isimlerini batch çek
      final ids = <String>{};
      for (final c in convs) {
        final did = c['designer_id']?.toString();
        if (did != null && did.isNotEmpty) ids.add(did);
      }
      if (ids.isNotEmpty && EvlumbaLiveService.isReady) {
        final profiles =
            await EvlumbaLiveService.getDesignersByIds(ids.toList());
        for (final p in profiles) {
          _designerCache[p['id'].toString()] = {
            'name': (p['full_name'] ?? p['business_name'] ?? '').toString(),
            'avatar': (p['avatar_url'] ?? '').toString(),
          };
        }
      }
      if (mounted) {
        setState(() {
          _convs = convs;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send(Map<String, dynamic> conv) async {
    if (_sending) return;
    setState(() => _sending = true);

    // Design paylaşımında direkt mesaj atma — önce conversation'a navigate,
    // input üstünde design preview göster. Kullanıcı kendi notunu yazıp
    // ekleyebilsin. Diğer tipler (designer/product) için eski flow.
    if (widget.itemType == SavedItemType.design) {
      final conversationId = conv['id'].toString();
      final designerId = conv['designer_id']?.toString();
      final pending = <String, dynamic>{
        'id': widget.itemId,
        'title': widget.title ?? '',
        'imageUrl': widget.imageUrl ?? '',
        'designerId': designerId ?? '',
      };
      if (!mounted) return;
      Navigator.of(context).pop();
      context.push('/chat/dm/$conversationId', extra: {
        'designerId': designerId,
        'pendingDesign': pending,
      });
      return;
    }

    final ok = await ShareService.shareInChat(
      type: widget.itemType,
      itemId: widget.itemId,
      conversationId: conv['id'].toString(),
      designerId: conv['designer_id']?.toString(),
      title: widget.title,
      imageUrl: widget.imageUrl,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(ok ? 'Sohbete iletildi' : 'Gönderilemedi, tekrar dene'),
        backgroundColor: ok ? KoalaColors.greenAlt : Colors.red.shade700,
        duration: const Duration(seconds: 3),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.72,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 14, 18, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Hangi sohbete göndermek istersin?',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: KoalaColors.text,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_convs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.messageCircle,
                  size: 40, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              const Text(
                'Henüz bir sohbet yok',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: KoalaColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Önce bir tasarımcıya mesaj at,\nsonra buradan paylaşabilirsin.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: _convs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (_, i) {
        final c = _convs[i];
        final did = c['designer_id']?.toString() ?? '';
        final cached = _designerCache[did];
        final name = (cached?['name']?.trim().isNotEmpty ?? false)
            ? cached!['name']!
            : 'Tasarımcı';
        final avatar = cached?['avatar'];
        final initials = name
            .split(' ')
            .where((w) => w.isNotEmpty)
            .map((w) => w[0])
            .take(2)
            .join()
            .toUpperCase();
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _sending ? null : () => _send(c),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [KoalaColors.accent, KoalaColors.accentMuted],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: avatar != null && avatar.isNotEmpty
                      ? ClipOval(
                          child: Image.network(
                            avatar,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Text(
                              initials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                      : Text(
                          initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: KoalaColors.text,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if ((c['last_message'] ?? '').toString().isNotEmpty)
                        Text(
                          (c['last_message'] ?? '').toString().trim(),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Icon(LucideIcons.send, size: 16, color: KoalaColors.accent),
              ],
            ),
          ),
        );
      },
    );
  }
}
