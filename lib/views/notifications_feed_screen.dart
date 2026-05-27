import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/router/app_router.dart';
import '../core/theme/koala_tokens.dart';
import '../core/utils/format_utils.dart';
import '../helpers/paywall_router.dart';
import '../services/notifications_feed_service.dart';
import '../widgets/koala_back_button.dart';
import 'designer_profile_screen.dart';
import 'my_designs/design_detail_screen.dart';
import 'projeler_screen.dart' show ProjectItem, ProjectDetailScreen;

/// Premium bildirim feed'i — Koala renk + font dilinde.
/// Bugün / Daha önce gruplama, mark-all-read, pull-to-refresh,
/// kart-stili tile'lar ve action_type bazlı deep-link.
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
    Future.microtask(() {
      try {
        ref.invalidate(unreadNotificationsProvider);
      } catch (_) {}
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
    // 1. Optimistic mark-as-read.
    if (!n.read) {
      // Optimistic UI
      setState(() {
        final i = _items.indexWhere((x) => x.id == n.id);
        if (i >= 0) _items[i] = _asRead(_items[i]);
      });
      ref.read(unreadNotificationsProvider.notifier).decrement();
      // Fire-and-forget service call.
      // ignore: unawaited_futures
      NotificationsFeedService.markRead(n.id);
    }
    // 2. Deep-link navigation by action_type.
    await _navigate(n);
  }

  Future<void> _navigate(KoalaNotification n) async {
    final data = n.actionData ?? const <String, dynamic>{};
    final action = (n.actionType ?? '').trim();
    if (!mounted) return;

    try {
      switch (action) {
        case 'open_conversation':
        case 'new_message':
          {
            final convId = data['conversation_id']?.toString();
            if (convId == null || convId.isEmpty) {
              _unknownAction();
              return;
            }
            appRouter.push('/chat/dm/$convId', extra: {
              if (data['designer_id'] != null)
                'designerId': data['designer_id'].toString(),
              if (data['designer_name'] != null ||
                  data['sender_name'] != null)
                'designerName':
                    (data['designer_name'] ?? data['sender_name']).toString(),
              if (data['designer_avatar_url'] != null ||
                  data['avatar_url'] != null)
                'designerAvatarUrl':
                    (data['designer_avatar_url'] ?? data['avatar_url'])
                        .toString(),
            });
            break;
          }
        case 'open_designer':
        case 'designer_match':
          {
            final designerId = data['designer_id']?.toString();
            if (designerId != null && designerId.isNotEmpty) {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DesignerProfileScreen(
                    designerId: designerId,
                    designerName: data['designer_name']?.toString(),
                  ),
                ),
              );
            } else {
              appRouter.push('/designers');
            }
            break;
          }
        case 'open_design':
          {
            final imageUrl =
                (data['image_url'] ?? n.imageUrl ?? '').toString();
            final id = (data['design_id'] ?? data['id'] ?? '').toString();
            if (imageUrl.isEmpty && id.isEmpty) {
              _unknownAction();
              return;
            }
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DesignDetailScreen(item: {
                  'id': id,
                  'image_url': imageUrl,
                  'title': data['title']?.toString() ?? n.title,
                  'subtitle': data['subtitle']?.toString() ?? '',
                }),
              ),
            );
            break;
          }
        case 'open_before_after':
        case 'project_ready':
          {
            try {
              final raw = Map<String, dynamic>.from(data);
              final pid = (raw['project_id'] ?? raw['id'] ?? '').toString();
              final item = ProjectItem(
                id: pid,
                itemId: pid,
                title: (raw['title'] ?? n.title).toString(),
                imageUrl: (raw['image_url'] ?? n.imageUrl ?? '').toString(),
                subtitle: (raw['subtitle'] ?? '').toString(),
                createdAt: n.createdAt,
                extra: raw,
              );
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProjectDetailScreen(item: item),
                ),
              );
            } catch (e) {
              _unknownAction();
            }
            break;
          }
        case 'open_paywall':
        case 'pro_offer':
          {
            final trigger =
                (data['trigger'] ?? 'pro_offer').toString();
            await showPaywall(context, trigger: 'notification_$trigger');
            break;
          }
        case 'open_collection':
          appRouter.push('/collections');
          break;
        case 'open_notifications':
          // No-op — already on this screen.
          break;
        default:
          _unknownAction();
      }
    } catch (e) {
      debugPrint('[notif-feed] navigate error: $e');
      _unknownAction();
    }
  }

  void _unknownAction() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bu bildirim için aksiyon tanımlı değil'),
        duration: Duration(seconds: 2),
      ),
    );
  }

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
    // İlk unread item — ekstra vurgulu zemin için.
    final firstUnreadIdx = _items.indexWhere((n) => !n.read);
    final firstUnreadId = firstUnreadIdx >= 0 ? _items[firstUnreadIdx].id : '';

    return Scaffold(
      backgroundColor: KoalaColors.bg,
      appBar: AppBar(
        backgroundColor: KoalaColors.bg,
        surfaceTintColor: KoalaColors.bg,
        elevation: 0,
        leading: const KoalaBackButton(),
        leadingWidth: 64,
        titleSpacing: 0,
        title: const Text(
          'Bildirimler',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: KoalaColors.ink,
          ),
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
                  child: _buildList(firstUnreadId: firstUnreadId),
                ),
    );
  }

  Widget _buildList({required String firstUnreadId}) {
    final g = _grouped();
    final children = <Widget>[];

    if (g.today.isNotEmpty) {
      children.add(const _SectionLabel(label: 'Bugün'));
      for (final n in g.today) {
        children.add(_NotifTile(
          notif: n,
          highlightFirst: n.id == firstUnreadId,
          onTap: () => _onTap(n),
        ));
      }
    }
    if (g.earlier.isNotEmpty) {
      children.add(const _SectionLabel(label: 'Daha önce'));
      for (final n in g.earlier) {
        children.add(_NotifTile(
          notif: n,
          highlightFirst: n.id == firstUnreadId,
          onTap: () => _onTap(n),
        ));
      }
    }
    children.add(const SizedBox(height: 24));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: children,
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
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    KoalaColors.accentSoft,
                    KoalaColors.accentSoft.withValues(alpha: 0.0),
                  ],
                  stops: const [0.55, 1.0],
                ),
              ),
              child: const Center(
                child: Icon(
                  LucideIcons.bell,
                  size: 30,
                  color: KoalaColors.accentDeep,
                ),
              ),
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

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Color(0xFF6B7280),
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Tile türü — leading thumbnail seçimine yön verir.
enum _TileKind {
  message, // sender avatarı
  ai, // sparkles
  inspiration, // lamp
  pro, // crown
  designUpdated, // image preview
  generic, // fallback ikon
}

_TileKind _detectKind(KoalaNotification n) {
  final data = n.actionData ?? const <String, dynamic>{};
  final kind = (data['kind']?.toString() ?? '').toLowerCase();
  final action = (n.actionType ?? '').toLowerCase();
  final type = (n.type).toLowerCase();

  if (kind == 'message' ||
      action == 'open_conversation' ||
      action == 'new_message' ||
      type == 'new_message') {
    return _TileKind.message;
  }
  if (kind == 'ai' || type == 'ai' || action == 'open_chat') {
    return _TileKind.ai;
  }
  if (kind == 'inspiration' ||
      type == 'collection_update' ||
      action == 'open_collection') {
    return _TileKind.inspiration;
  }
  if (kind == 'pro' ||
      action == 'open_paywall' ||
      action == 'pro_offer' ||
      type == 'promo') {
    return _TileKind.pro;
  }
  if (kind == 'design_updated' ||
      action == 'open_before_after' ||
      action == 'project_ready' ||
      action == 'open_design' ||
      (n.imageUrl ?? '').isNotEmpty) {
    return _TileKind.designUpdated;
  }
  return _TileKind.generic;
}

class _NotifTile extends StatelessWidget {
  final KoalaNotification notif;
  final bool highlightFirst;
  final VoidCallback onTap;
  const _NotifTile({
    required this.notif,
    required this.highlightFirst,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final unread = !notif.read;
    final tileBg = (unread && highlightFirst)
        ? const Color(0xFFF4F2FE)
        : Colors.white;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: tileBg,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: Ink(
                decoration: BoxDecoration(
                  color: tileBg,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Leading(notif: notif),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              notif.title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: KoalaColors.ink,
                                height: 1.25,
                                letterSpacing: -0.1,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if ((notif.body ?? '').isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                notif.body!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: KoalaColors.textSec,
                                  height: 1.35,
                                ),
                                maxLines: 2,
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
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: KoalaColors.textTer,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Icon(
                            LucideIcons.chevronRight,
                            size: 16,
                            color: KoalaColors.textTer,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (unread)
            Positioned(
              top: -2,
              left: -2,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KoalaColors.accentDeep,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Leading extends StatelessWidget {
  final KoalaNotification notif;
  const _Leading({required this.notif});

  @override
  Widget build(BuildContext context) {
    final kind = _detectKind(notif);
    switch (kind) {
      case _TileKind.message:
        return _avatarThumb(notif);
      case _TileKind.ai:
        return _typedSquare(
          bg: const Color(0xFF1F1B3A),
          icon: LucideIcons.sparkles,
          iconColor: Colors.white,
        );
      case _TileKind.inspiration:
        return _typedSquare(
          bg: const Color(0xFFFBEFE0),
          icon: LucideIcons.lamp,
          iconColor: const Color(0xFF7C5A1E),
        );
      case _TileKind.pro:
        return Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE5C879), Color(0xFFD4A853)],
            ),
          ),
          child: const Icon(
            LucideIcons.crown,
            size: 22,
            color: Colors.white,
          ),
        );
      case _TileKind.designUpdated:
        return _imageSquare(notif);
      case _TileKind.generic:
        return _typedSquare(
          bg: KoalaColors.accentSoft,
          icon: LucideIcons.bell,
          iconColor: KoalaColors.accentDeep,
        );
    }
  }

  Widget _typedSquare({
    required Color bg,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, size: 22, color: iconColor),
    );
  }

  Widget _avatarThumb(KoalaNotification n) {
    final url = (n.actionData?['designer_avatar_url'] ??
            n.actionData?['avatar_url'] ??
            n.actionData?['sender_avatar_url'] ??
            n.imageUrl ??
            '')
        .toString();
    if (url.isEmpty) {
      return _typedSquare(
        bg: KoalaColors.accentSoft,
        icon: LucideIcons.messageCircle,
        iconColor: KoalaColors.accentDeep,
      );
    }
    return ClipOval(
      child: SizedBox(
        width: 52,
        height: 52,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          memCacheWidth: 220,
          placeholder: (_, _) => Container(color: KoalaColors.accentSoft),
          errorWidget: (_, _, _) => Container(
            color: KoalaColors.accentSoft,
            alignment: Alignment.center,
            child: const Icon(
              LucideIcons.user,
              size: 22,
              color: KoalaColors.accentDeep,
            ),
          ),
        ),
      ),
    );
  }

  Widget _imageSquare(KoalaNotification n) {
    final url = (n.imageUrl ?? n.actionData?['image_url'] ?? '').toString();
    if (url.isEmpty) {
      return _typedSquare(
        bg: KoalaColors.accentSoft,
        icon: LucideIcons.image,
        iconColor: KoalaColors.accentDeep,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 52,
        height: 52,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          memCacheWidth: 220,
          placeholder: (_, _) => Container(color: KoalaColors.accentSoft),
          errorWidget: (_, _, _) => Container(
            color: KoalaColors.accentSoft,
            alignment: Alignment.center,
            child: const Icon(
              LucideIcons.image,
              size: 22,
              color: KoalaColors.accentDeep,
            ),
          ),
        ),
      ),
    );
  }
}
