import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/koala_tokens.dart';
import '../core/utils/format_utils.dart';
import '../services/notifications_feed_service.dart';

/// Premium bildirim feed'i — Koala renk + font dilinde.
/// Sektörel: Today / Earlier section labels, mark-all-read AppBar icon,
/// pull-to-refresh, premium card-row tasarım.
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

  @override
  void dispose() {
    // Ekran kapanırken bell badge sayısını taze tut.
    // (notifier zaten periodic refresh yapıyor, ama kullanıcı geri dönerken
    // anlık doğru sayıyı görsün diye burada da invalidate ediyoruz.)
    Future.microtask(() {
      try {
        ref.invalidate(unreadNotificationsProvider);
      } catch (_) {/* sessiz */}
    });
    super.dispose();
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
      _items = _items.map(_asRead).toList();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tüm bildirimler okundu işaretlendi'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  KoalaNotification _asRead(KoalaNotification n) => KoalaNotification(
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

  Future<void> _onTap(KoalaNotification n) async {
    if (!n.read) {
      await NotificationsFeedService.markRead(n.id);
      ref.read(unreadNotificationsProvider.notifier).decrement();
      if (mounted) {
        setState(() {
          final i = _items.indexWhere((x) => x.id == n.id);
          if (i >= 0) _items[i] = _asRead(_items[i]);
        });
      }
    }
    // TODO: actionType bazlı yönlendirme — şimdilik sadece okundu işaretleniyor.
  }

  /// İki bölüme ayır: Bugün / Daha önce.
  ({List<KoalaNotification> today, List<KoalaNotification> earlier}) _grouped() {
    final nowLocal = DateTime.now();
    final startOfToday = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final today = <KoalaNotification>[];
    final earlier = <KoalaNotification>[];
    for (final n in _items) {
      final created = n.createdAt.isUtc ? n.createdAt.toLocal() : n.createdAt;
      if (!created.isBefore(startOfToday)) {
        today.add(n);
      } else {
        earlier.add(n);
      }
    }
    return (today: today, earlier: earlier);
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _items.where((n) => !n.read).length;
    final hasUnread = unreadCount > 0;

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
        titleSpacing: 0,
        title: Row(
          children: [
            const Text('Bildirimler', style: KoalaText.h2),
            if (hasUnread) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: KoalaColors.accentSoft,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: KoalaColors.accentDeep,
                    height: 1.0,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (hasUnread)
            IconButton(
              tooltip: 'Tümünü okundu işaretle',
              icon: const Icon(LucideIcons.checkCheck, size: 20),
              color: KoalaColors.accentDeep,
              onPressed: _markAllRead,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? RefreshIndicator(
                  onRefresh: _load,
                  color: KoalaColors.accent,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.7,
                        child: _empty(),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: KoalaColors.accent,
                  child: _buildList(),
                ),
    );
  }

  Widget _buildList() {
    final g = _grouped();
    final slivers = <Widget>[];

    if (g.today.isNotEmpty) {
      slivers.add(const _SectionLabel(label: 'Bugün'));
      for (final n in g.today) {
        slivers.add(_NotifTile(notif: n, onTap: () => _onTap(n)));
        slivers.add(const _ItemDivider());
      }
    }
    if (g.earlier.isNotEmpty) {
      slivers.add(const _SectionLabel(label: 'Daha önce'));
      for (final n in g.earlier) {
        slivers.add(_NotifTile(notif: n, onTap: () => _onTap(n)));
        slivers.add(const _ItemDivider());
      }
    }
    // Son divider'ı kaldır (visual cleanliness).
    if (slivers.isNotEmpty && slivers.last is _ItemDivider) {
      slivers.removeLast();
    }
    slivers.add(const SizedBox(height: 24));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: slivers,
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
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KoalaColors.accentSoft,
                boxShadow: [
                  BoxShadow(
                    color: KoalaColors.accent.withValues(alpha: 0.10),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(LucideIcons.bell,
                  size: 30, color: KoalaColors.accentDeep),
            ),
            const SizedBox(height: 18),
            const Text('Henüz bildirim yok', style: KoalaText.h3),
            const SizedBox(height: 6),
            const Text(
              'Yeni mesajlar ve güncellemeler burada görünür.',
              textAlign: TextAlign.center,
              style: KoalaText.bodySec,
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemDivider extends StatelessWidget {
  const _ItemDivider();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(left: 72),
        child: Divider(height: 1, color: KoalaColors.borderLight),
      );
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: KoalaColors.textSec,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _NotifTile extends StatelessWidget {
  final KoalaNotification notif;
  final VoidCallback onTap;
  const _NotifTile({required this.notif, required this.onTap});

  IconData _iconForType(String type) {
    switch (type) {
      case 'new_message':
        return LucideIcons.messageCircle;
      case 'designer_match':
        return LucideIcons.users;
      case 'product_recommend':
        return LucideIcons.shoppingBag;
      case 'style_result':
        return LucideIcons.palette;
      case 'budget_ready':
        return LucideIcons.wallet;
      case 'collection_update':
        return LucideIcons.folderHeart;
      case 'promo':
        return LucideIcons.tag;
      default:
        return LucideIcons.bell;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = !notif.read;
    return Material(
      color: unread
          ? KoalaColors.accentSoft.withValues(alpha: 0.35)
          : KoalaColors.bg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _leading(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notif.title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight:
                            unread ? FontWeight.w700 : FontWeight.w600,
                        color: KoalaColors.text,
                        letterSpacing: -0.1,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if ((notif.body ?? '').isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        notif.body!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: KoalaColors.textMed,
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    timeAgo(notif.createdAt),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: KoalaColors.textTer,
                    ),
                  ),
                  if (unread) ...[
                    const SizedBox(height: 6),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _leading() {
    final hasImage = (notif.imageUrl ?? '').isNotEmpty;
    // Image varsa avatar olarak göster; yoksa type'a göre renkli ikon kapsülü.
    if (hasImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 44,
          height: 44,
          child: CachedNetworkImage(
            imageUrl: notif.imageUrl!,
            fit: BoxFit.cover,
            memCacheWidth: 200,
            placeholder: (_, _) => Container(color: KoalaColors.accentSoft),
            errorWidget: (_, _, _) => _iconBox(),
          ),
        ),
      );
    }
    return _iconBox();
  }

  Widget _iconBox() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: KoalaColors.accentSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        _iconForType(notif.type),
        size: 20,
        color: KoalaColors.accentDeep,
      ),
    );
  }
}
