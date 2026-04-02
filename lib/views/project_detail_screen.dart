import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/evlumba_live_service.dart';
import '../services/messaging_service.dart';
import '../services/saved_items_service.dart';
import '../widgets/save_button.dart';
import 'conversation_detail_screen.dart';

class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({super.key, required this.project});

  final Map<String, dynamic> project;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  List<Map<String, dynamic>> _images = [];
  List<Map<String, dynamic>> _shopLinks = [];
  bool _loading = true;
  int _currentImage = 0;

  Map<String, dynamic> get project => widget.project;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final id = (project['id'] ?? '').toString();
    if (id.isEmpty || !EvlumbaLiveService.isReady) {
      setState(() => _loading = false);
      return;
    }
    try {
      final images = await EvlumbaLiveService.getProjectImages(id);
      final links = await EvlumbaLiveService.getProjectShopLinks(id);
      if (!mounted) return;
      setState(() {
        _images = images;
        _shopLinks = links;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String get _coverUrl {
    for (final key in ['cover_image_url', 'cover_url', 'image_url']) {
      final v = (project[key] ?? '').toString().trim();
      if (v.isNotEmpty && !v.startsWith('data:')) return v;
    }
    if (_images.isNotEmpty) {
      final sorted = List<Map<String, dynamic>>.from(_images)
        ..sort(
          (a, b) => ((a['sort_order'] as num?)?.toInt() ?? 9999).compareTo(
            (b['sort_order'] as num?)?.toInt() ?? 9999,
          ),
        );
      final url = (sorted.first['image_url'] ?? '').toString();
      if (!url.startsWith('data:')) return url;
    }
    return '';
  }

  List<String> get _allImages {
    final urls = <String>[];
    if (_coverUrl.isNotEmpty) urls.add(_coverUrl);
    for (final img in _images) {
      final url = (img['image_url'] ?? '').toString().trim();
      if (url.isNotEmpty && !url.startsWith('data:') && !urls.contains(url)) {
        urls.add(url);
      }
    }
    return urls;
  }

  @override
  Widget build(BuildContext context) {
    final title = (project['title'] ?? 'İsimsiz proje').toString();
    final location = (project['location'] ?? '').toString().trim();
    final description = (project['description'] ?? '').toString().trim();
    final projectType = (project['project_type'] ?? '').toString().trim();
    final designer = project['profiles'] as Map<String, dynamic>?;
    final designerName = (designer?['full_name'] ?? '').toString().trim();
    final designerAvatar = (designer?['avatar_url'] ?? '').toString().trim();
    final designerCity = (designer?['city'] ?? '').toString().trim();
    final images = _allImages;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F1EB),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            backgroundColor: const Color(0xFFF6F1EB),
            surfaceTintColor: const Color(0xFFF6F1EB),
            actions: [
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: SaveButton(
                  itemType: SavedItemType.design,
                  itemId: widget.project['id']?.toString() ?? '',
                  title: widget.project['title']?.toString(),
                  imageUrl: (widget.project['designer_project_images'] as List?)
                      ?.firstOrNull?['image_url']?.toString(),
                  subtitle: widget.project['description']?.toString(),
                  size: 20,
                ),
              ),
            ],
            leading: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.arrowLeft,
                  size: 20,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF6C5CE7),
                        strokeWidth: 2,
                      ),
                    )
                  : images.isEmpty
                  ? _galleryPlaceholder()
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        PageView.builder(
                          itemCount: images.length,
                          onPageChanged: (i) =>
                              setState(() => _currentImage = i),
                          itemBuilder: (_, i) => Image.network(
                            images[i],
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _galleryPlaceholder(),
                          ),
                        ),
                        if (images.length > 1)
                          Positioned(
                            bottom: 16,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(images.length, (i) {
                                return Container(
                                  width: _currentImage == i ? 20 : 6,
                                  height: 6,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _currentImage == i
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                );
                              }),
                            ),
                          ),
                        Positioned(
                          bottom: 16,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '${_currentImage + 1} / ${images.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (projectType.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F0FF),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        projectType,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6C5CE7),
                        ),
                      ),
                    ),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                      height: 1.3,
                    ),
                  ),
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          LucideIcons.mapPin,
                          size: 14,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          location,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (designerName.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.05),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF6C5CE7),
                              image: designerAvatar.isNotEmpty
                                  ? DecorationImage(
                                      image: NetworkImage(designerAvatar),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: designerAvatar.isEmpty
                                ? Center(
                                    child: Text(
                                      designerName[0].toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  designerName,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                if (designerCity.isNotEmpty)
                                  Text(
                                    designerCity,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          // Mesaj At
                          GestureDetector(
                            onTap: () async {
                              final id =
                                  designer?['id']?.toString() ??
                                  project['designer_id']?.toString() ??
                                  '';
                              if (id.isEmpty) return;
                              final designerName =
                                  designer?['full_name']?.toString() ?? 'Tasarımcı';
                              final conv = await MessagingService.getOrCreateConversation(
                                designerId: id,
                                contextType: 'project',
                                contextId: project['id']?.toString(),
                                contextTitle: project['title']?.toString(),
                              );
                              if (conv != null && mounted) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ConversationDetailScreen(
                                      conversationId: conv['id'] as String,
                                      designerName: designerName,
                                      designerAvatarUrl: designer?['avatar_url']?.toString(),
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6C5CE7),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.chat_rounded, size: 14, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text(
                                    'Mesaj At',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Profil
                          GestureDetector(
                            onTap: () async {
                              final id =
                                  designer?['id'] ??
                                  project['designer_id'] ??
                                  '';
                              if (id.toString().isEmpty) return;
                              final url = 'https://www.evlumba.com/tasarimci/$id';
                              final go = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  title: const Text('Harici Bağlantı'),
                                  content: const Text('Tasarımcı profili evlumba.com üzerinde açılacak. Devam etmek istiyor musun?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
                                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aç')),
                                  ],
                                ),
                              );
                              if (go == true) {
                                launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: const Color(0xFF6C5CE7)),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Profil',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF6C5CE7),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_shopLinks.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Icon(
                          LucideIcons.sparkles,
                          size: 16,
                          color: Color(0xFF6C5CE7),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Bu projedeki ürünler (${_shopLinks.length})',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 184,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _shopLinks.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, i) =>
                            _ShopLinkCard(shopLink: _shopLinks[i]),
                      ),
                    ),
                  ],
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _galleryPlaceholder() {
    return Container(
      color: const Color(0xFFF8F7FC),
      child: Center(
        child: Icon(LucideIcons.image, size: 48, color: Colors.grey.shade300),
      ),
    );
  }
}

class _ShopLinkCard extends StatelessWidget {
  const _ShopLinkCard({required this.shopLink});

  final Map<String, dynamic> shopLink;

  @override
  Widget build(BuildContext context) {
    final title = (shopLink['product_title'] ?? 'Ürün').toString();
    final price = (shopLink['product_price'] ?? '').toString();
    final imageUrl = (shopLink['product_image_url'] ?? '').toString().trim();
    final productUrl = (shopLink['product_url'] ?? '').toString().trim();

    return GestureDetector(
      onTap: () {
        if (productUrl.isNotEmpty) {
          launchUrl(
            Uri.parse(productUrl),
            mode: LaunchMode.inAppBrowserView,
          );
        }
      },
      child: Container(
        width: 144,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.84),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.05),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6C5CE7).withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: const Color(0xFFF8F7FC),
                child: imageUrl.isNotEmpty && !imageUrl.startsWith('data:')
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder(),
                      )
                    : _placeholder(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                      height: 1.3,
                    ),
                  ),
                  if (price.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      price,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6C5CE7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Center(
      child: Icon(
        LucideIcons.shoppingBag,
        size: 24,
        color: Colors.grey.shade300,
      ),
    );
  }
}
