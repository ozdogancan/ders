import 'package:flutter/material.dart';
import '../core/theme/koala_tokens.dart';
import '../services/collections_service.dart';
import '../services/saved_items_service.dart';
import '../widgets/collection_bottom_sheet.dart';
import '../widgets/koala_widgets.dart';

/// Koleksiyonlar ekranı — grid görünümü
class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  List<Map<String, dynamic>> _collections = [];
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _hasError = false; });
    try {
      final data = await CollectionsService.getAll();
      if (mounted) setState(() { _collections = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _hasError = true; });
    }
  }

  Future<void> _deleteCollection(String id, int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Koleksiyonu Sil'),
        content: const Text('Bu koleksiyon kalıcı olarak silinecek. Devam etmek istiyor musun?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sil', style: TextStyle(color: KoalaColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final success = await CollectionsService.delete(id);
    if (success && mounted) {
      setState(() => _collections.removeAt(index));
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
        title: const Text('Koleksiyonlarım', style: KoalaText.h2),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final id = await CollectionBottomSheet.show(context);
          if (id != null) _load();
        },
        backgroundColor: KoalaColors.accent,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: _loading
          ? const ShimmerGrid(itemCount: 4)
          : _hasError
              ? ErrorState(onRetry: _load)
              : _collections.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: KoalaColors.accent,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(KoalaSpacing.lg),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: KoalaSpacing.md,
                      crossAxisSpacing: KoalaSpacing.md,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: _collections.length,
                    itemBuilder: (context, index) {
                      final col = _collections[index];
                      return _CollectionCard(
                        collection: col,
                        onTap: () => _openDetail(col),
                        onLongPress: () => _showOptions(col, index),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KoalaSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.collections_bookmark_rounded,
                size: 64, color: KoalaColors.textTer),
            const SizedBox(height: KoalaSpacing.lg),
            const Text('Henüz koleksiyonun yok', style: KoalaText.h3),
            const SizedBox(height: KoalaSpacing.sm),
            Text(
              'Beğendiğin tasarımları, tasarımcıları ve ürünleri koleksiyonlarda grupla',
              style: KoalaText.bodySec,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KoalaSpacing.xl),
            GestureDetector(
              onTap: () async {
                final id = await CollectionBottomSheet.show(context);
                if (id != null) _load();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: KoalaSpacing.xl,
                  vertical: KoalaSpacing.md,
                ),
                decoration: KoalaDeco.accentPill,
                child: const Text('İlk Koleksiyonunu Oluştur', style: KoalaText.button),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetail(Map<String, dynamic> col) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CollectionDetailScreen(collection: col),
      ),
    );
  }

  void _showOptions(Map<String, dynamic> col, int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KoalaColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(KoalaRadius.xl)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(KoalaSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: KoalaColors.accent),
              title: const Text('Düzenle', style: KoalaText.label),
              onTap: () {
                Navigator.pop(ctx);
                // TODO: edit flow
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_rounded, color: KoalaColors.error),
              title: Text('Sil', style: KoalaText.label.copyWith(color: KoalaColors.error)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteCollection(col['id'] as String, index);
              },
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// KOLEKSIYON KARTI
// ═══════════════════════════════════════════════════════
class _CollectionCard extends StatelessWidget {
  const _CollectionCard({
    required this.collection,
    required this.onTap,
    required this.onLongPress,
  });

  final Map<String, dynamic> collection;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final name = collection['name'] as String? ?? '';
    final coverUrl = collection['cover_image_url'] as String?;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: KoalaDeco.cardElevated,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover
            Expanded(
              child: Container(
                width: double.infinity,
                color: KoalaColors.surfaceAlt,
                child: coverUrl != null
                    ? Image.network(coverUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder())
                    : _placeholder(),
              ),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.all(KoalaSpacing.md),
              child: Text(
                name,
                style: KoalaText.h4,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return const Center(
      child: Icon(Icons.collections_bookmark_rounded,
          size: 36, color: KoalaColors.textTer),
    );
  }
}

// ═══════════════════════════════════════════════════════
// KOLEKSIYON DETAY (içindeki öğeler)
// ═══════════════════════════════════════════════════════
class _CollectionDetailScreen extends StatefulWidget {
  const _CollectionDetailScreen({required this.collection});
  final Map<String, dynamic> collection;

  @override
  State<_CollectionDetailScreen> createState() =>
      _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<_CollectionDetailScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await SavedItemsService.getByCollection(
      widget.collection['id'] as String,
    );
    if (mounted) setState(() { _items = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.collection['name'] as String? ?? 'Koleksiyon';

    return Scaffold(
      backgroundColor: KoalaColors.bg,
      appBar: AppBar(
        backgroundColor: KoalaColors.bg,
        surfaceTintColor: KoalaColors.bg,
        elevation: 0,
        title: Text(name, style: KoalaText.h2),
      ),
      body: _loading
          ? const LoadingState()
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.inbox_rounded,
                          size: 48, color: KoalaColors.textTer),
                      const SizedBox(height: KoalaSpacing.md),
                      const Text('Bu koleksiyon boş', style: KoalaText.bodySec),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: KoalaColors.accent,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(KoalaSpacing.lg),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: KoalaSpacing.md),
                        decoration: KoalaDeco.cardElevated,
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(KoalaRadius.lg),
                              ),
                              child: Container(
                                width: 80,
                                height: 80,
                                color: KoalaColors.surfaceAlt,
                                child: item['image_url'] != null
                                    ? Image.network(
                                        item['image_url'] as String,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.image_rounded,
                                                color: KoalaColors.textTer),
                                      )
                                    : const Icon(Icons.image_rounded,
                                        color: KoalaColors.textTer),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(KoalaSpacing.md),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['title'] as String? ?? '',
                                      style: KoalaText.h4,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (item['subtitle'] != null) ...[
                                      const SizedBox(height: KoalaSpacing.xs),
                                      Text(
                                        item['subtitle'] as String,
                                        style: KoalaText.bodySmall,
                                        maxLines: 1,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
