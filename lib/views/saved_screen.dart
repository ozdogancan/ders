import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/koala_tokens.dart';
import '../services/messaging_service.dart';
import '../services/saved_items_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/shimmer_loading.dart';
import 'conversation_detail_screen.dart';

/// Kaydedilenler ekranı — 3 tab: Tasarımlar / Tasarımcılar / Ürünler
class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      appBar: AppBar(
        backgroundColor: KoalaColors.bg,
        surfaceTintColor: KoalaColors.bg,
        elevation: 0,
        leading: IconButton(
          onPressed: _goBackHome,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Kaydedilenlerim', style: KoalaText.h2),
        bottom: TabBar(
          controller: _tabController,
          labelColor: KoalaColors.accent,
          unselectedLabelColor: KoalaColors.textSec,
          indicatorColor: KoalaColors.accent,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: KoalaText.label,
          tabs: const [
            Tab(text: 'Tasarımlar'),
            Tab(text: 'Tasarımcılar'),
            Tab(text: 'Ürünler'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _SavedList(type: SavedItemType.design),
          _SavedList(type: SavedItemType.designer),
          _SavedList(type: SavedItemType.product),
        ],
      ),
    );
  }

  void _goBackHome() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.go('/');
  }
}

class _SavedList extends StatefulWidget {
  const _SavedList({required this.type});
  final SavedItemType type;

  @override
  State<_SavedList> createState() => _SavedListState();
}

class _SavedListState extends State<_SavedList>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _hasError = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  final _scrollCtrl = ScrollController();
  static const _pageSize = 20;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels > _scrollCtrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _hasError = false; });
    try {
      final data = await SavedItemsService.getByType(widget.type, limit: _pageSize);
      if (mounted) setState(() { _items = data; _loading = false; _hasMore = data.length >= _pageSize; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _hasError = true; });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final data = await SavedItemsService.getByType(widget.type, limit: _pageSize, offset: _items.length);
    if (mounted) {
      setState(() {
        _items.addAll(data);
        _loadingMore = false;
        _hasMore = data.length >= _pageSize;
      });
    }
  }

  Future<void> _removeItem(int index) async {
    final item = _items[index];
    final id = item['item_id'] as String? ?? '';
    final success = await SavedItemsService.removeItem(
      type: widget.type,
      itemId: id,
    );
    if (success && mounted) {
      final removed = _items[index];
      setState(() => _items.removeAt(index));
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Kaldırıldı'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Geri Al',
            onPressed: () async {
              await SavedItemsService.saveItem(
                type: widget.type,
                itemId: id,
                title: removed['title'] as String?,
                imageUrl: removed['image_url'] as String?,
                subtitle: removed['subtitle'] as String?,
              );
              _load();
            },
          ),
        ),
      );
    }
  }

  /// Kaydedilen öğeye tıklama aksiyonu — detay bottom sheet göster
  void _onItemTap(Map<String, dynamic> item, int index) {
    HapticFeedback.lightImpact();
    _showItemDetailSheet(item, index);
  }

  void _showItemDetailSheet(Map<String, dynamic> item, int index) {
    final title = item['title'] as String? ?? 'İsimsiz';
    final subtitle = item['subtitle'] as String?;
    final imageUrl = item['image_url'] as String?;
    final extraData = item['extra_data'] as Map<String, dynamic>?;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            // Image + info
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 100, height: 100,
                    color: KoalaColors.surfaceAlt,
                    child: imageUrl != null
                        ? Image.network(imageUrl, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(_emptyIcon, size: 32, color: KoalaColors.textTer))
                        : Icon(_emptyIcon, size: 32, color: KoalaColors.textTer),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: KoalaText.h3, maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(subtitle, style: KoalaText.bodySmall.copyWith(
                          color: widget.type == SavedItemType.product
                              ? const Color(0xFF1D9E75)
                              : KoalaColors.textSec,
                          fontWeight: widget.type == SavedItemType.product
                              ? FontWeight.w700
                              : FontWeight.normal,
                        ), maxLines: 2),
                      ],
                      if (extraData?['shop_name'] != null && (extraData!['shop_name'] as String).isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(extraData['shop_name'] as String, style: KoalaText.bodySmall),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Action buttons
            Row(
              children: [
                // Primary action
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _executePrimaryAction(item);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: widget.type == SavedItemType.designer
                            ? const Color(0xFF10B981)
                            : KoalaColors.accent,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_actionIcon, size: 16, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            _primaryActionLabel,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Remove button
                GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    _removeItem(index);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: const Color(0xFFFEF2F2),
                      border: Border.all(color: const Color(0xFFFCA5A5).withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFDC2626)),
                        SizedBox(width: 4),
                        Text('Kaldır', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFDC2626))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String get _primaryActionLabel {
    switch (widget.type) {
      case SavedItemType.product:
        return 'Ürünü İncele';
      case SavedItemType.designer:
        return 'Mesaj Gönder';
      case SavedItemType.design:
        return 'Tasarımı İncele';
    }
  }

  void _executePrimaryAction(Map<String, dynamic> item) {
    final itemId = item['item_id'] as String? ?? '';
    final extraData = item['extra_data'] as Map<String, dynamic>?;

    switch (widget.type) {
      case SavedItemType.product:
        final url = extraData?['url'] as String? ?? '';
        if (url.isNotEmpty) {
          launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
        } else {
          final name = item['title'] as String? ?? '';
          launchUrl(
            Uri.parse('https://www.evlumba.com/kesfet?q=${Uri.encodeComponent(name)}'),
            mode: LaunchMode.inAppBrowserView,
          );
        }
        break;

      case SavedItemType.designer:
        _openDesignerChat(itemId, item['title'] as String? ?? 'Tasarımcı');
        break;

      case SavedItemType.design:
        final projectId = extraData?['project_id'] as String? ?? itemId;
        if (projectId.isNotEmpty) {
          launchUrl(
            Uri.parse('https://www.evlumba.com/proje/$projectId'),
            mode: LaunchMode.inAppBrowserView,
          );
        }
        break;
    }
  }

  Future<void> _openDesignerChat(String designerId, String name) async {
    if (designerId.isEmpty) return;
    final conv = await MessagingService.getOrCreateConversation(
      designerId: designerId,
      contextType: 'designer',
      contextId: designerId,
      contextTitle: name,
    );
    if (conv != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ConversationDetailScreen(
            conversationId: conv['id'] as String,
            designerName: name,
          ),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF10B981),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 4),
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Expanded(child: Text('Mesajınız iletildi! Genellikle 24 saat içinde dönüş yapılır.', style: TextStyle(color: Colors.white, fontSize: 13))),
              ],
            ),
          ),
        );
      }
    } else if (mounted) {
      // Fallback: profil aç
      launchUrl(
        Uri.parse('https://www.evlumba.com/tasarimci/$designerId'),
        mode: LaunchMode.inAppBrowserView,
      );
    }
  }

  /// Tap aksiyon ikonu
  IconData get _actionIcon {
    switch (widget.type) {
      case SavedItemType.product:
        return Icons.open_in_new_rounded;
      case SavedItemType.designer:
        return Icons.chat_bubble_outline_rounded;
      case SavedItemType.design:
        return Icons.open_in_new_rounded;
    }
  }

  String get _emptyTitle {
    switch (widget.type) {
      case SavedItemType.design:
        return 'Henüz kaydettiğin tasarım yok';
      case SavedItemType.designer:
        return 'Henüz kaydettiğin tasarımcı yok';
      case SavedItemType.product:
        return 'Henüz kaydettiğin ürün yok';
    }
  }

  String get _emptySubtitle {
    switch (widget.type) {
      case SavedItemType.design:
        return 'Beğendiğin tasarımları kalp ikonuna basarak kaydet';
      case SavedItemType.designer:
        return 'Tasarımcı profillerinde kalp ikonuna bas';
      case SavedItemType.product:
        return 'AI önerdiği ürünleri kaydet';
    }
  }

  IconData get _emptyIcon {
    switch (widget.type) {
      case SavedItemType.design:
        return Icons.palette_rounded;
      case SavedItemType.designer:
        return Icons.person_rounded;
      case SavedItemType.product:
        return Icons.shopping_bag_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const ShimmerList(itemCount: 5, cardHeight: 90);
    }
    if (_hasError) {
      return ErrorState(onRetry: _load);
    }

    if (_items.isEmpty) {
      return EmptyState(
        icon: _emptyIcon,
        title: _emptyTitle,
        description: _emptySubtitle,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: KoalaColors.accent,
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.all(KoalaSpacing.lg),
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return const Padding(
              padding: EdgeInsets.all(KoalaSpacing.lg),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: KoalaColors.accent)),
            );
          }
          final item = _items[index];
          return GestureDetector(
            onTap: () => _onItemTap(item, index),
            onLongPress: () => _showDeleteDialog(index),
            child: Container(
              margin: const EdgeInsets.only(bottom: KoalaSpacing.md),
              decoration: KoalaDeco.cardElevated,
              child: Row(
                children: [
                  // Image
                  ClipRRect(
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(KoalaRadius.lg),
                    ),
                    child: Container(
                      width: 90,
                      height: 90,
                      color: KoalaColors.surfaceAlt,
                      child: item['image_url'] != null
                          ? Image.network(
                              item['image_url'] as String,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.image_rounded,
                                      color: KoalaColors.textTer),
                            )
                          : Icon(_emptyIcon,
                              size: 32, color: KoalaColors.textTer),
                    ),
                  ),
                  // Info
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(KoalaSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['title'] as String? ?? 'İsimsiz',
                            style: KoalaText.h4,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (item['subtitle'] != null) ...[
                            const SizedBox(height: KoalaSpacing.xs),
                            Text(
                              item['subtitle'] as String,
                              style: KoalaText.bodySmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Action indicator
                  Padding(
                    padding: const EdgeInsets.only(right: KoalaSpacing.md),
                    child: Icon(
                      _actionIcon,
                      size: 18,
                      color: KoalaColors.textTer,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showDeleteDialog(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KoalaColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KoalaRadius.lg),
        ),
        title: const Text('Kaldır', style: KoalaText.h3),
        content: const Text(
          'Bu öğeyi kaydedilenlerden kaldırmak istiyor musun?',
          style: KoalaText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('İptal', style: KoalaText.label.copyWith(color: KoalaColors.textSec)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _removeItem(index);
            },
            child: Text('Kaldır', style: KoalaText.label.copyWith(color: KoalaColors.error)),
          ),
        ],
      ),
    );
  }
}
