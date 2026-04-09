import 'package:flutter/material.dart';
import '../core/theme/koala_tokens.dart';
import '../core/utils/format_utils.dart';
import '../services/notifications_service.dart';
import '../widgets/koala_widgets.dart';
import 'conversation_detail_screen.dart';

/// In-app bildirim ekranı
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;
  bool _hasError = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  static const _pageSize = 30;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    NotificationsService.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _hasError = false; });
    try {
      final data = await NotificationsService.getAll(limit: _pageSize);
      if (mounted) setState(() {
        _notifications = data;
        _loading = false;
        _hasMore = data.length >= _pageSize;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _hasError = true; });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final data = await NotificationsService.getAll(
        limit: _pageSize,
        offset: _notifications.length,
      );
      if (mounted) setState(() {
        _notifications.addAll(data);
        _loadingMore = false;
        _hasMore = data.length >= _pageSize;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _subscribeRealtime() {
    NotificationsService.subscribe(
      onNotification: (notif) {
        if (mounted) setState(() => _notifications.insert(0, notif));
      },
    );
  }

  Future<void> _markAllRead() async {
    await NotificationsService.markAllAsRead();
    if (mounted) {
      setState(() {
        for (var n in _notifications) {
          n['is_read'] = true;
        }
      });
    }
  }

  Future<void> _onTap(Map<String, dynamic> notif) async {
    // Okundu işaretle
    final id = notif['id'] as String;
    await NotificationsService.markAsRead(id);
    if (mounted) setState(() => notif['is_read'] = true);

    // Aksiyona yönlendir
    final actionType = notif['action_type'] as String?;
    final actionData = notif['action_data'] as Map<String, dynamic>?;

    if (actionType == null || actionData == null || !mounted) return;

    switch (actionType) {
      case 'open_conversation':
        final convId = actionData['conversation_id'] as String?;
        if (convId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ConversationDetailScreen(
                conversationId: convId,
                designerName: actionData['designer_name'] as String? ?? 'Tasarımcı',
              ),
            ),
          );
        }
        break;
      case 'open_url':
        // TODO: URL açma
        break;
      default:
        break;
    }
  }

  IconData _iconForType(String? type) {
    switch (type) {
      case 'new_message':
        return Icons.chat_rounded;
      case 'designer_match':
        return Icons.person_search_rounded;
      case 'product_recommend':
        return Icons.shopping_bag_rounded;
      case 'style_result':
        return Icons.palette_rounded;
      case 'budget_ready':
        return Icons.account_balance_wallet_rounded;
      case 'collection_update':
        return Icons.collections_bookmark_rounded;
      case 'promo':
        return Icons.local_offer_rounded;
      case 'system':
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _colorForType(String? type) {
    switch (type) {
      case 'new_message':
        return KoalaColors.accent;
      case 'designer_match':
        return KoalaColors.star;
      case 'product_recommend':
        return KoalaColors.green;
      case 'style_result':
        return KoalaColors.pink;
      case 'promo':
        return KoalaColors.errorBright;
      default:
        return KoalaColors.textSec;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      appBar: AppBar(
        backgroundColor: KoalaColors.bg,
        surfaceTintColor: KoalaColors.bg,
        elevation: 0,
        title: const Text('Bildirimler', style: KoalaText.h2),
        actions: [
          if (_notifications.any((n) => n['is_read'] == false))
            TextButton(
              onPressed: _markAllRead,
              child: Text(
                'Tümünü Oku',
                style: KoalaText.label.copyWith(color: KoalaColors.accent),
              ),
            ),
        ],
      ),
      body: _loading
          ? const ShimmerList(itemCount: 6, cardHeight: 72)
          : _hasError
              ? ErrorState(onRetry: _load)
              : _notifications.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_none_rounded,
                          size: 64, color: KoalaColors.textTer),
                      SizedBox(height: KoalaSpacing.lg),
                      Text('Bildirim yok', style: KoalaText.bodySec),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: KoalaColors.accent,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: KoalaSpacing.lg,
                      vertical: KoalaSpacing.sm,
                    ),
                    itemCount: _notifications.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _notifications.length) {
                        _loadMore();
                        return const Padding(
                          padding: EdgeInsets.all(KoalaSpacing.lg),
                          child: LoadingState(),
                        );
                      }
                      final notif = _notifications[index];
                      final isRead = notif['is_read'] == true;
                      final type = notif['type'] as String?;
                      final createdAt = DateTime.tryParse(
                          notif['created_at']?.toString() ?? '');

                      return GestureDetector(
                        onTap: () => _onTap(notif),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: KoalaSpacing.sm),
                          padding: const EdgeInsets.all(KoalaSpacing.lg),
                          decoration: BoxDecoration(
                            color: isRead
                                ? KoalaColors.surface
                                : KoalaColors.accentLight.withValues(alpha:0.5),
                            borderRadius:
                                BorderRadius.circular(KoalaRadius.lg),
                            border:
                                Border.all(color: KoalaColors.border, width: 0.5),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Icon
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _colorForType(type).withValues(alpha:0.12),
                                  borderRadius:
                                      BorderRadius.circular(KoalaRadius.sm),
                                ),
                                child: Icon(
                                  _iconForType(type),
                                  size: 20,
                                  color: _colorForType(type),
                                ),
                              ),
                              const SizedBox(width: KoalaSpacing.md),

                              // Content
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      notif['title'] as String? ?? '',
                                      style: isRead
                                          ? KoalaText.label
                                          : KoalaText.h4,
                                    ),
                                    if (notif['body'] != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        notif['body'] as String,
                                        style: KoalaText.bodySec,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    if (createdAt != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        timeAgo(createdAt),
                                        style: KoalaText.labelSmall,
                                      ),
                                    ],
                                  ],
                                ),
                              ),

                              // Unread dot
                              if (!isRead)
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(top: 6),
                                  decoration: const BoxDecoration(
                                    color: KoalaColors.accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

}
