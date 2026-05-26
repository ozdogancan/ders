import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/koala_tokens.dart';
import '../core/utils/format_utils.dart';
import '../services/notifications_feed_service.dart';

/// Instagram tarzı bildirim feed'i — Koala renk + font dilinde.
class NotificationsFeedScreen extends ConsumerStatefulWidget {
  const NotificationsFeedScreen({super.key});

  @override
  ConsumerState<NotificationsFeedScreen> createState() =>
      _NotificationsFeedScreenState();
}

class _NotificationsFeedScreenState
    extends ConsumerState<NotificationsFeedScreen> {
  List<KoalaNotification> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await NotificationsFeedService.list(limit: 80);
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  Future<void> _markAllRead() async {
    final hadUnread = _items.any((n) => !n.read);
    if (!hadUnread) return;
    await NotificationsFeedService.markAllRead();
    ref.read(unreadNotificationsProvider.notifier).zero();
    if (!mounted) return;
    setState(() {
      _items = _items
          .map((n) => KoalaNotification(
                id: n.id,
                type: n.type,
                title: n.title,
                body: n.body,
                imageUrl: n.imageUrl,
                actionType: n.actionType,
                actionData: n.actionData,
                read: true,
                createdAt: n.createdAt,
              ))
          .toList();
    });
  }

  Future<void> _onTap(KoalaNotification n) async {
    if (!n.read) {
      await NotificationsFeedService.markRead(n.id);
      ref.read(unreadNotificationsProvider.notifier).decrement();
      if (mounted) {
        setState(() {
          final i = _items.indexWhere((x) => x.id == n.id);
          if (i >= 0) {
            _items[i] = KoalaNotification(
              id: n.id,
              type: n.type,
              title: n.title,
              body: n.body,
              imageUrl: n.imageUrl,
              actionType: n.actionType,
              actionData: n.actionData,
              read: true,
              createdAt: n.createdAt,
            );
          }
        });
      }
    }
    // TODO: actionType'a göre yönlendirme (kart önizleme / tasarımcı profili).
    // Şimdilik bildirim sadece okundu olarak işaretleniyor.
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _items.any((n) => !n.read);
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      appBar: AppBar(
        backgroundColor: KoalaColors.bg,
        surfaceTintColor: KoalaColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, size: 22),
          color: KoalaColors.text,
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Bildirimler', style: KoalaText.h2),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAllRead,
              child: const Text(
                'Tümünü okundu işaretle',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: KoalaColors.accentDeep,
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _empty()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: KoalaColors.accent,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemBuilder: (_, i) => _NotifTile(
                      notif: _items[i],
                      onTap: () => _onTap(_items[i]),
                    ),
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: KoalaColors.borderLight),
                    itemCount: _items.length,
                  ),
                ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: KoalaColors.accentSoft,
              ),
              child: const Icon(LucideIcons.bell,
                  size: 28, color: KoalaColors.accentDeep),
            ),
            const SizedBox(height: 16),
            const Text('Henüz bildirimin yok', style: KoalaText.h3),
            const SizedBox(height: 4),
            const Text(
              'Beğendiğin tasarımcıları takip et — yeni tasarım paylaştıklarında burada bildirim alacaksın.',
              textAlign: TextAlign.center,
              style: KoalaText.bodySec,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotifTile extends StatelessWidget {
  final KoalaNotification notif;
  final VoidCallback onTap;
  const _NotifTile({required this.notif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unread = !notif.read;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: unread ? KoalaColors.accentSoft.withValues(alpha: 0.4) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _avatar(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: notif.title,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: unread
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: KoalaColors.text,
                                  letterSpacing: -0.1,
                                ),
                              ),
                              if ((notif.body ?? '').isNotEmpty)
                                TextSpan(
                                  text: ' · ${notif.body}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: KoalaColors.textMed,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: KoalaColors.accentDeep,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(timeAgo(notif.createdAt),
                      style: KoalaText.labelSmall),
                ],
              ),
            ),
            if ((notif.imageUrl ?? '').isNotEmpty) ...[
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: CachedNetworkImage(
                    imageUrl: notif.imageUrl!,
                    fit: BoxFit.cover,
                    memCacheWidth: 200,
                    placeholder: (_, _) =>
                        Container(color: KoalaColors.surfaceAlt),
                    errorWidget: (_, _, _) =>
                        Container(color: KoalaColors.surfaceAlt),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _avatar() {
    const evlumbaAvatar =
        'https://xgefjepaqnghaotqybpi.supabase.co/storage/v1/object/public/koala-seed/avatars/evlumba-design.webp';
    final url = notif.designerId == 'evlumba-design'
        ? evlumbaAvatar
        : null;
    return SizedBox(
      width: 44,
      height: 44,
      child: ClipOval(
        child: url != null
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(color: KoalaColors.accentSoft),
                errorWidget: (_, _, _) => Container(
                  color: KoalaColors.accentSoft,
                  child: const Icon(LucideIcons.user,
                      size: 20, color: KoalaColors.accentDeep),
                ),
              )
            : Container(
                color: KoalaColors.accentSoft,
                child: const Icon(LucideIcons.bell,
                    size: 20, color: KoalaColors.accentDeep),
              ),
      ),
    );
  }
}
