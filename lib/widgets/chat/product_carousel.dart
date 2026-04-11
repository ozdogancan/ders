import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/koala_tokens.dart';
import '../../services/product_analytics_service.dart';
import '../../services/saved_items_service.dart';
import '../../services/profile_feedback_service.dart';

/// Ürün veri modeli — AI function call sonucundan parse
class ProductCarouselItem {
  final String id;
  final String name;
  final String price;
  final String imageUrl;
  final String url;
  final String shopName;
  final String source;
  final String projectId;

  const ProductCarouselItem({
    required this.id,
    required this.name,
    required this.price,
    required this.imageUrl,
    required this.url,
    this.shopName = '',
    this.source = '',
    this.projectId = '',
  });

  factory ProductCarouselItem.fromCardData(Map<String, dynamic> data) {
    // Fiyatı normalize et — bazen sayı, bazen string geliyor
    var price = (data['price'] ?? data['product_price'] ?? '').toString();
    // Eğer fiyat sadece sayı ise TL ekle
    if (price.isNotEmpty && !price.contains('TL') && double.tryParse(price.replaceAll('.', '').replaceAll(',', '.')) != null) {
      price = '$price TL';
    }

    return ProductCarouselItem(
      id: (data['id'] ?? data['product_id'] ?? '').toString(),
      name: data['name'] ?? data['product_title'] ?? data['title'] ?? 'Ürün',
      price: price,
      imageUrl: (data['image_url'] ?? data['product_image_url'] ?? '').toString(),
      url: (data['url'] ?? data['product_url'] ?? '').toString(),
      shopName: (data['shop_name'] ?? '').toString(),
      source: (data['source'] ?? '').toString(),
      projectId: (data['project_id'] ?? '').toString(),
    );
  }
}

/// Havenly tarzı yatay ürün carousel'i — chat içi product_grid kartı
class ProductCarousel extends StatefulWidget {
  final String title;
  final List<ProductCarouselItem> products;
  final void Function(ProductCarouselItem product, String question)? onAskAI;

  const ProductCarousel({
    super.key,
    required this.title,
    required this.products,
    this.onAskAI,
  });

  @override
  State<ProductCarousel> createState() => _ProductCarouselState();
}

class _ProductCarouselState extends State<ProductCarousel> {
  final _scrollCtrl = ScrollController();
  int _visibleIndex = 0;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    final idx = (_scrollCtrl.offset / 192).round().clamp(0, widget.products.length - 1);
    if (idx != _visibleIndex) setState(() => _visibleIndex = idx);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.products.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: KoalaColors.accentSoft,
          border: Border.all(color: KoalaColors.borderMed),
        ),
        child: const Row(
          children: [
            Icon(Icons.shopping_bag_outlined, size: 20, color: KoalaColors.accentDeep),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Bu alan için ürün kataloğu hazırlanıyor. Çok yakında burada gerçek ürün önerileri göreceksin!',
                style: TextStyle(color: KoalaColors.textSec, fontSize: 13, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Başlık + sayaç
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title.isNotEmpty ? widget.title : 'Önerilen Ürünler',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: KoalaColors.ink),
                ),
              ),
              Text(
                '${_visibleIndex + 1}/${widget.products.length}',
                style: const TextStyle(fontSize: 12, color: KoalaColors.textSec),
              ),
            ],
          ),
        ),

        // Carousel
        SizedBox(
          height: 285,
          child: ListView.separated(
            controller: _scrollCtrl,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: widget.products.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _ProductCard(
              product: widget.products[index],
              onAskAI: widget.onAskAI,
            ),
          ),
        ),

        // Dot indicator (4'ten fazla üründe — max 4 ürün önerildiğinde gizle)
        if (widget.products.length > 4)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.products.length.clamp(0, 8),
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _visibleIndex ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: i == _visibleIndex ? KoalaColors.accent : KoalaColors.borderMed,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
// TEK ÜRÜN KARTI — 180x260
// ═══════════════════════════════════════════════════════
class _ProductCard extends StatefulWidget {
  final ProductCarouselItem product;
  final void Function(ProductCarouselItem product, String question)? onAskAI;

  const _ProductCard({required this.product, this.onAskAI});

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  bool _isSaved = false;
  bool _animating = false;

  @override
  void initState() {
    super.initState();
    _checkSaved();
    _trackImpression();
  }

  void _trackImpression() {
    final p = widget.product;
    ProductAnalyticsService.trackImpression(
      productId: p.id,
      productName: p.name,
      shopName: p.shopName,
      price: p.price,
      url: p.url,
      source: p.source,
    );
  }

  Future<void> _checkSaved() async {
    // ID yoksa name-based fallback key kullan
    final key = widget.product.id.isNotEmpty
        ? widget.product.id
        : 'name_${widget.product.name.hashCode}';
    final saved = await SavedItemsService.isSaved(
      type: SavedItemType.product,
      itemId: key,
    );
    if (mounted) setState(() => _isSaved = saved);
  }

  Future<void> _toggleSave() async {
    HapticFeedback.lightImpact();
    setState(() => _animating = true);

    final key = widget.product.id.isNotEmpty
        ? widget.product.id
        : 'name_${widget.product.name.hashCode}';
    await SavedItemsService.toggle(
      type: SavedItemType.product,
      itemId: key,
      title: widget.product.name,
      imageUrl: widget.product.imageUrl.isNotEmpty ? widget.product.imageUrl : null,
      subtitle: widget.product.price.isNotEmpty ? widget.product.price : null,
      extraData: {
        if (widget.product.url.isNotEmpty) 'url': widget.product.url,
        if (widget.product.shopName.isNotEmpty) 'shop_name': widget.product.shopName,
      },
    );

    final nowSaved = !_isSaved;
    if (mounted) setState(() { _isSaved = nowSaved; });
    if (nowSaved && mounted) {
      ProductAnalyticsService.trackSave(
        productId: widget.product.id,
        productName: widget.product.name,
        shopName: widget.product.shopName,
        price: widget.product.price,
        source: widget.product.source,
      );
      ProfileFeedbackService.recordSaveSignal(
        itemTitle: widget.product.name,
      );
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: KoalaColors.accentDeep,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
          content: const Text('Kaydedildi', style: TextStyle(color: Colors.white)),
          action: SnackBarAction(
            label: 'Kaydedilenlerimi Gör',
            textColor: Colors.white,
            onPressed: () {
              GoRouter.of(context).push('/saved');
            },
          ),
        ),
      );
    }
    await Future.delayed(const Duration(milliseconds: 250));
    if (mounted) setState(() => _animating = false);
  }

  void _openProduct() {
    final p = widget.product;
    // Tıklama analitik kaydı
    ProductAnalyticsService.trackClick(
      productId: p.id,
      productName: p.name,
      shopName: p.shopName,
      price: p.price,
      url: p.url,
      source: p.source,
    );
    final link = p.url.isNotEmpty
        ? p.url
        : 'https://www.evlumba.com/kesfet?q=${Uri.encodeComponent(p.name)}';
    try {
      final uri = Uri.parse(link);
      if (uri.scheme.isEmpty || (!uri.scheme.startsWith('http'))) {
        debugPrint('KoalaCarousel: Invalid URL scheme: $link');
        return;
      }
      launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (e) {
      debugPrint('KoalaCarousel: Failed to open URL: $link — $e');
    }
  }

  void _showAskAISheet() {
    final p = widget.product;
    final questions = [
      'Bu ürünü odama nasıl yerleştiririm?',
      'Benzer ama daha uygun fiyatlı alternatifler?',
      'Bu ürünle hangi renkler uyumlu?',
      'Bu ürünün artıları ve eksileri neler?',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: KoalaColors.borderMed, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${p.name} hakkında sor',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: KoalaColors.ink),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            ...questions.map((q) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onAskAI?.call(p, q);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: KoalaColors.accentSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: KoalaColors.accent.withValues(alpha:0.15)),
                  ),
                  child: Text(q, style: const TextStyle(fontSize: 14, color: KoalaColors.accent, fontWeight: FontWeight.w500)),
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;

    return Semantics(
      button: true,
      label: '${p.name}, ${p.price}',
      child: GestureDetector(
      onTap: _openProduct,
      child: Container(
        width: 180,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha:0.06)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha:0.04), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Görsel + Kaydet ──
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: p.imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: p.imageUrl,
                          width: 180, height: 140,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _placeholder(),
                          errorWidget: (_, __, ___) => _placeholder(),
                        )
                      : _placeholder(),
                ),
                // Mağaza badge
                if (p.shopName.isNotEmpty)
                  Positioned(
                    top: 8, left: 8,
                    child: _marketplaceBadge(p.shopName),
                  ),
                // Kaydet butonu
                Positioned(
                  top: 8, right: 8,
                  child: GestureDetector(
                    onTap: _toggleSave,
                    child: AnimatedScale(
                      scale: _animating ? 1.3 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutBack,
                      child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha:0.9),
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.1), blurRadius: 4)],
                        ),
                        child: Icon(
                          _isSaved ? Icons.favorite : Icons.favorite_border,
                          size: 18,
                          color: _isSaved ? KoalaColors.error : KoalaColors.textSec,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // ── Bilgi ──
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Ürün adı
                    Text(p.name,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: KoalaColors.ink, height: 1.3),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                    const Spacer(),
                    // Fiyat
                    if (p.price.isNotEmpty)
                      Text(p.price,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: KoalaColors.green),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    // Ürünü İncele + Sor
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _openProduct,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              decoration: BoxDecoration(
                                color: KoalaColors.green,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.open_in_new_rounded, size: 12, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text('İncele', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: _showAskAISheet,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: KoalaColors.accentSoft,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.auto_awesome, size: 12, color: KoalaColors.accent),
                                SizedBox(width: 3),
                                Text('Sor', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: KoalaColors.accent)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _marketplaceBadge(String shop) {
    final key = shop.toLowerCase().trim();
    Color bg;
    Color fg;
    if (key.contains('trendyol')) {
      bg = const Color(0xFFFF6600);
      fg = Colors.white;
    } else if (key.contains('hepsiburada')) {
      bg = const Color(0xFF00AEEF);
      fg = Colors.white;
    } else if (key.contains('ikea')) {
      bg = const Color(0xFF0058A3);
      fg = const Color(0xFFFFDA1A);
    } else if (key.contains('amazon')) {
      bg = const Color(0xFF232F3E);
      fg = const Color(0xFFFF9900);
    } else if (key.contains('koçtaş') || key.contains('koctas')) {
      bg = const Color(0xFF00A651);
      fg = Colors.white;
    } else {
      bg = KoalaColors.accentSoft;
      fg = KoalaColors.textSec;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        shop,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: 180, height: 140,
      color: KoalaColors.surfaceMuted,
      child: const Center(child: Icon(Icons.shopping_bag_outlined, color: Colors.grey, size: 32)),
    );
  }
}
