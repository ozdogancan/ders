import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/koala_tokens.dart';
import '../services/messaging_service.dart';
import '../services/saved_items_service.dart';
import 'share_sheet.dart';

/// Çoklu proje galeri modalı — tasarım kartlarından, designer portfoliosundan,
/// saved tab'ından ve portfolio thumb'larından açılır.
///
/// `project_detail_screen.dart`'ın yerini alan hafif, tek ekran viewer.
/// `ProjectsGalleryPopup.show(context, projects: [...])`.
class ProjectsGalleryPopup {
  ProjectsGalleryPopup._();

  static Future<void> show(
    BuildContext context, {
    required List<Map<String, dynamic>> projects,
    int initialIndex = 0,
    Map<String, dynamic>? designer,
    bool showShare = true,
  }) {
    if (projects.isEmpty) return Future.value();
    final safeIndex = initialIndex.clamp(0, projects.length - 1);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black87,
      builder: (_) => _ProjectsGalleryBody(
        projects: projects,
        initialIndex: safeIndex,
        designer: designer,
        showShare: showShare,
      ),
    );
  }
}

class _ProjectsGalleryBody extends StatefulWidget {
  const _ProjectsGalleryBody({
    required this.projects,
    required this.initialIndex,
    required this.designer,
    required this.showShare,
  });

  final List<Map<String, dynamic>> projects;
  final int initialIndex;
  final Map<String, dynamic>? designer;
  final bool showShare;

  @override
  State<_ProjectsGalleryBody> createState() => _ProjectsGalleryBodyState();
}

class _ProjectsGalleryBodyState extends State<_ProjectsGalleryBody> {
  late PageController _pageCtrl;
  late int _currentIndex;
  final Map<String, bool> _savedCache = {};
  bool _savingInFlight = false;
  bool _askingInFlight = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
    _refreshSavedState();
  }

  Future<void> _refreshSavedState() async {
    final id = (_current['id'] ?? '').toString();
    if (id.isEmpty || _savedCache.containsKey(id)) return;
    final saved = await SavedItemsService.isSaved(
      type: SavedItemType.design,
      itemId: id,
    );
    if (!mounted) return;
    setState(() => _savedCache[id] = saved);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _current => widget.projects[_currentIndex];

  String _coverUrl(Map<String, dynamic> project) {
    for (final key in ['cover_image_url', 'cover_url', 'image_url']) {
      final v = (project[key] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    final images = (project['designer_project_images'] as List?)
        ?.whereType<Map>()
        .toList();
    if (images != null && images.isNotEmpty) {
      images.sort((a, b) =>
          ((a['sort_order'] as num?)?.toInt() ?? 9999)
              .compareTo((b['sort_order'] as num?)?.toInt() ?? 9999));
      return (images.first['image_url'] ?? '').toString().trim();
    }
    return '';
  }

  String _prettyCategory(String raw) {
    const trMap = {
      'living_room': 'Oturma Odası',
      'bedroom': 'Yatak Odası',
      'kitchen': 'Mutfak',
      'bathroom': 'Banyo',
      'kids_room': 'Çocuk Odası',
      'office': 'Çalışma Odası',
      'dining_room': 'Yemek Odası',
      'hallway': 'Antre',
      'balcony': 'Balkon',
      'outdoor': 'Dış Mekan',
    };
    final key = raw.toLowerCase().trim();
    if (trMap.containsKey(key)) return trMap[key]!;
    final cleaned = raw.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    if (cleaned.isEmpty) return 'Proje';
    return cleaned
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  String _currentCategory() {
    final p = _current;
    for (final k in ['project_type', 'room_type', 'category']) {
      final v = (p[k] ?? '').toString().trim();
      if (v.isNotEmpty) return _prettyCategory(v);
    }
    return 'Proje';
  }

  String _designerId() {
    final did = (_current['designer_id'] ?? '').toString().trim();
    if (did.isNotEmpty) return did;
    final dd = widget.designer;
    if (dd != null) return (dd['id'] ?? '').toString().trim();
    return '';
  }

  String _designerName() {
    final dd = widget.designer;
    if (dd != null) {
      final n = (dd['full_name'] ?? dd['name'] ?? '').toString().trim();
      if (n.isNotEmpty) return n;
    }
    final p = _current['profiles'];
    if (p is Map) {
      final n = (p['full_name'] ?? '').toString().trim();
      if (n.isNotEmpty) return n;
    }
    return (_current['designer_name'] ?? '').toString().trim();
  }

  String? _designerAvatar() {
    final dd = widget.designer;
    if (dd != null) {
      final a = (dd['avatar_url'] ?? '').toString().trim();
      if (a.isNotEmpty) return a;
    }
    final p = _current['profiles'];
    if (p is Map) {
      final a = (p['avatar_url'] ?? '').toString().trim();
      if (a.isNotEmpty) return a;
    }
    return null;
  }

  Future<void> _askDesigner() async {
    if (_askingInFlight) return;
    HapticFeedback.lightImpact();
    final designerId = _designerId();
    if (designerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tasarımcı bilgisi bulunamadı')),
      );
      return;
    }
    setState(() => _askingInFlight = true);
    final cat = _currentCategory();
    final projectId = (_current['id'] ?? '').toString();
    final coverUrl = _coverUrl(_current);
    // Conversation'ı getir/aç (lazy create — sadece metadata, mesaj yok)
    final conv = await MessagingService.getOrCreateConversation(
      designerId: designerId,
      contextType: 'project',
      contextId: projectId,
      contextTitle: cat,
    );
    if (!mounted) return;
    setState(() => _askingInFlight = false);
    if (conv == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sohbet başlatılamadı, tekrar dene')),
      );
      return;
    }
    final conversationId = (conv['id'] ?? '').toString();
    if (conversationId.isEmpty) return;
    Navigator.of(context).pop();
    // Chat ekranı: input üstünde design preview + text entry
    context.push('/chat/dm/$conversationId', extra: {
      'designerId': designerId,
      'pendingDesign': {
        'id': projectId,
        'title': cat,
        'imageUrl': coverUrl,
        'designerId': designerId,
      },
    });
  }

  Future<void> _save() async {
    if (_savingInFlight) return;
    HapticFeedback.lightImpact();
    final projectId = (_current['id'] ?? '').toString();
    if (projectId.isEmpty) return;
    setState(() => _savingInFlight = true);
    final currentlySaved = _savedCache[projectId] ?? false;
    final cat = _currentCategory();
    bool ok;
    if (currentlySaved) {
      ok = await SavedItemsService.removeItem(
        type: SavedItemType.design,
        itemId: projectId,
      );
    } else {
      ok = await SavedItemsService.saveItem(
        type: SavedItemType.design,
        itemId: projectId,
        title: cat,
        imageUrl: _coverUrl(_current),
        subtitle: _designerName(),
        extraData: {'designer_id': _designerId()},
      );
    }
    if (!mounted) return;
    setState(() {
      _savingInFlight = false;
      if (ok) _savedCache[projectId] = !currentlySaved;
    });
    final msg = !ok
        ? (currentlySaved
            ? 'Kaldırılamadı, tekrar dene'
            : 'Kaydedilemedi — giriş yapman gerekebilir')
        : (currentlySaved ? 'Kayıtlardan çıkarıldı' : 'Kaydedildi');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: ok ? KoalaColors.greenAlt : Colors.red.shade700,
        duration: const Duration(seconds: 2),
      ));
  }

  void _share() {
    HapticFeedback.lightImpact();
    final projectId = (_current['id'] ?? '').toString();
    if (projectId.isEmpty) return;
    final cat = _currentCategory();
    ShareSheet.show(
      context,
      itemType: SavedItemType.design,
      itemId: projectId,
      title: cat,
      imageUrl: _coverUrl(_current),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return SizedBox(
      height: media.size.height * 0.95,
      child: Container(
        decoration: const BoxDecoration(
          color: KoalaColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 10),
              _buildTopBar(),
              const SizedBox(height: 8),
              Expanded(
                child: PageView.builder(
                  controller: _pageCtrl,
                  itemCount: widget.projects.length,
                  onPageChanged: (i) {
                    setState(() => _currentIndex = i);
                    _refreshSavedState();
                  },
                  itemBuilder: (_, i) {
                    final url = _coverUrl(widget.projects[i]);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: url.isEmpty
                            ? Container(
                                color: KoalaColors.surfaceAlt,
                                alignment: Alignment.center,
                                child: const Icon(
                                  LucideIcons.image,
                                  size: 48,
                                  color: KoalaColors.textTer,
                                ),
                              )
                            : CachedNetworkImage(
                                imageUrl: url,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                placeholder: (_, __) => Container(
                                  color: KoalaColors.surfaceAlt,
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  color: KoalaColors.surfaceAlt,
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    LucideIcons.imageOff,
                                    size: 36,
                                    color: KoalaColors.textTer,
                                  ),
                                ),
                              ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              _buildDotIndicator(),
              const SizedBox(height: 10),
              _buildTitleBlock(),
              const SizedBox(height: 14),
              _buildActions(),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(LucideIcons.x, color: KoalaColors.ink, size: 22),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: KoalaColors.surface,
              borderRadius: BorderRadius.circular(KoalaRadius.pill),
              border: Border.all(color: KoalaColors.border),
            ),
            child: Text(
              '${_currentIndex + 1}/${widget.projects.length}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: KoalaColors.textMed,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildDotIndicator() {
    final total = widget.projects.length;
    if (total <= 1) return const SizedBox.shrink();
    if (total > 8) {
      return Text(
        '${_currentIndex + 1}/$total',
        style: const TextStyle(
          fontSize: 11,
          color: KoalaColors.textSec,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final active = i == _currentIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active ? KoalaColors.accentDeep : KoalaColors.border,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

  Widget _buildTitleBlock() {
    final cat = _currentCategory();
    final designerName = _designerName();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Text(
            cat,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: KoalaColors.ink,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (designerName.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              designerName,
              style: const TextStyle(
                fontSize: 13,
                color: KoalaColors.textSec,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActions() {
    final projectId = (_current['id'] ?? '').toString();
    final isSaved = _savedCache[projectId] ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _PrimaryActionButton(
              icon: LucideIcons.messageCircle,
              label: 'Tasarımcıya sor',
              onTap: _askDesigner,
              loading: _askingInFlight,
            ),
          ),
          const SizedBox(width: 10),
          _IconActionButton(
            icon: isSaved ? LucideIcons.bookmarkMinus : LucideIcons.bookmark,
            tooltip: isSaved ? 'Kayıtlı' : 'Kaydet',
            active: isSaved,
            onTap: _save,
          ),
          if (widget.showShare) ...[
            const SizedBox(width: 10),
            _IconActionButton(
              icon: LucideIcons.share2,
              tooltip: 'Paylaş',
              onTap: _share,
            ),
          ],
        ],
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KoalaColors.accentDeep,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: loading ? null : onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 16, color: Colors.white),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _IconActionButton extends StatelessWidget {
  const _IconActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final bg = active ? KoalaColors.accentSoft : KoalaColors.surface;
    final fg = active ? KoalaColors.accentDeep : KoalaColors.textMed;
    final border = active ? KoalaColors.accentDeep : KoalaColors.border;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: border),
            ),
            child: Icon(icon, size: 20, color: fg),
          ),
        ),
      ),
    );
  }
}
