import 'package:flutter/material.dart';
import '../core/theme/koala_ds.dart';
import '../core/theme/koala_tokens.dart';
import '../services/collections_service.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Koleksiyon oluşturma / seçme bottom sheet.
/// SaveButton'dan veya herhangi bir kaydetme akışından çağrılır.
///
/// Kullanım:
/// ```dart
/// final collectionId = await CollectionBottomSheet.show(context, savedItemId: 'xxx');
/// ```
class CollectionBottomSheet extends StatefulWidget {
  const CollectionBottomSheet({super.key, this.savedItemId});

  final String? savedItemId; // varsa öğeyi koleksiyona ekler

  /// Bottom sheet'i göster, seçilen/oluşturulan koleksiyonun ID'sini döner
  static Future<String?> show(BuildContext context, {String? savedItemId}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CollectionBottomSheet(savedItemId: savedItemId),
    );
  }

  @override
  State<CollectionBottomSheet> createState() => _CollectionBottomSheetState();
}

class _CollectionBottomSheetState extends State<CollectionBottomSheet> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  List<Map<String, dynamic>> _collections = [];
  bool _loading = true;
  bool _creating = false;
  bool _showCreateForm = false;

  @override
  void initState() {
    super.initState();
    _loadCollections();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _loadCollections() async {
    final data = await CollectionsService.getAll();
    if (mounted) setState(() { _collections = data; _loading = false; });
  }

  Future<void> _createCollection() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _creating = true);
    final id = await CollectionsService.create(
      name: name,
      description: _descController.text.trim().isEmpty
          ? null
          : _descController.text.trim(),
    );

    if (id != null && widget.savedItemId != null) {
      await CollectionsService.addItemToCollection(
        savedItemId: widget.savedItemId!,
        collectionId: id,
      );
    }

    if (!mounted) return;
    if (id == null) {
      setState(() => _creating = false);
      final err = CollectionsService.lastCreateError ?? 'Koleksiyon oluşturulamadı';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err, maxLines: 3),
          backgroundColor: KoalaDS.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.pop(context, id);
  }

  Future<void> _selectCollection(String collectionId) async {
    if (widget.savedItemId != null) {
      await CollectionsService.addItemToCollection(
        savedItemId: widget.savedItemId!,
        collectionId: collectionId,
      );
    }
    if (mounted) Navigator.pop(context, collectionId);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: EdgeInsets.only(bottom: bottomPad),
      decoration: const BoxDecoration(
        color: KoalaDS.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(KoalaRadius.xl)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: KoalaSpacing.sm),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: KoalaDS.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(KoalaSpacing.lg),
            child: Row(
              children: [
                Text(
                  _showCreateForm ? 'Yeni Koleksiyon' : 'Koleksiyona Ekle',
                  style: KoalaText.h3,
                ),
                const Spacer(),
                if (!_showCreateForm)
                  GestureDetector(
                    onTap: () => setState(() => _showCreateForm = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: KoalaSpacing.md,
                        vertical: KoalaSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: KoalaDS.accentTint,
                        borderRadius: BorderRadius.circular(KoalaRadius.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.plus, size: 16, color: KoalaDS.accent),
                          const SizedBox(width: 4),
                          Text('Yeni', style: KoalaText.label.copyWith(color: KoalaDS.accent)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Content
          if (_showCreateForm) _buildCreateForm(),
          if (!_showCreateForm) _buildCollectionList(),

          SizedBox(height: KoalaSpacing.lg + MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildCreateForm() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.lg),
      child: Column(
        children: [
          // Name field
          TextField(
            controller: _nameController,
            autofocus: true,
            style: KoalaText.body,
            decoration: InputDecoration(
              hintText: 'Koleksiyon adı',
              hintStyle: KoalaText.hint,
              filled: true,
              fillColor: KoalaDS.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KoalaR.md),
                borderSide: BorderSide(color: KoalaDS.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KoalaR.md),
                borderSide: BorderSide(color: KoalaDS.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KoalaR.md),
                borderSide: BorderSide(color: KoalaDS.accent),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: KoalaSpacing.lg,
                vertical: KoalaSpacing.md,
              ),
            ),
          ),
          const SizedBox(height: KoalaSpacing.md),

          // Description field
          TextField(
            controller: _descController,
            style: KoalaText.body,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Açıklama (opsiyonel)',
              hintStyle: KoalaText.hint,
              filled: true,
              fillColor: KoalaDS.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KoalaR.md),
                borderSide: BorderSide(color: KoalaDS.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KoalaR.md),
                borderSide: BorderSide(color: KoalaDS.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KoalaR.md),
                borderSide: BorderSide(color: KoalaDS.accent),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: KoalaSpacing.lg,
                vertical: KoalaSpacing.md,
              ),
            ),
          ),
          const SizedBox(height: KoalaSpacing.lg),

          // Buttons
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _showCreateForm = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: KoalaSpacing.md),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(KoalaRadius.md),
                      border: Border.all(color: KoalaDS.line),
                    ),
                    child: Center(
                      child: Text('İptal', style: KoalaText.label),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: KoalaSpacing.md),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: _creating ? null : _createCollection,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: KoalaSpacing.md),
                    decoration: BoxDecoration(
                      color: KoalaDS.cta,
                      borderRadius: BorderRadius.circular(KoalaR.md),
                      boxShadow: KoalaElev.ctaGlow,
                    ),
                    child: Center(
                      child: _creating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text('Oluştur', style: KoalaText.button),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionList() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(KoalaSpacing.xxl),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: KoalaDS.accent,
          ),
        ),
      );
    }

    if (_collections.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(KoalaSpacing.xxl),
        child: Column(
          children: [
            Icon(LucideIcons.folderHeart,
                size: 48, color: KoalaDS.inkFaint),
            const SizedBox(height: KoalaSpacing.md),
            Text('Henüz koleksiyonun yok', style: KoalaText.bodySec),
            const SizedBox(height: KoalaSpacing.sm),
            Text('"Yeni" ile ilk koleksiyonunu oluştur',
                style: KoalaText.bodySmall),
          ],
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 300),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.lg),
        itemCount: _collections.length,
        separatorBuilder: (_, __) => const SizedBox(height: KoalaSpacing.sm),
        itemBuilder: (context, index) {
          final col = _collections[index];
          return GestureDetector(
            onTap: () => _selectCollection(col['id'] as String),
            child: Container(
              padding: const EdgeInsets.all(KoalaSpacing.lg),
              decoration: BoxDecoration(
                color: KoalaDS.surface,
                borderRadius: BorderRadius.circular(KoalaR.lg),
                border: Border.all(color: KoalaDS.line, width: 0.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: KoalaDS.accentTint,
                      borderRadius: BorderRadius.circular(KoalaRadius.sm),
                    ),
                    child: const Icon(
                      LucideIcons.folder,
                      color: KoalaDS.accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: KoalaSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          col['name'] as String? ?? '',
                          style: KoalaText.h4,
                        ),
                        if (col['description'] != null)
                          Text(
                            col['description'] as String,
                            style: KoalaText.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const Icon(
                    LucideIcons.chevronRight,
                    color: KoalaDS.inkFaint,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
