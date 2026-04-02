import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

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
  final String projectId;

  const ProductCarouselItem({
    required this.id,
    required this.name,
    required this.price,
    required this.imageUrl,
    required this.url,
    this.shopName = '',
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
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Bu kriterlere uygun ürün bulunamadı.',
          style: TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
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
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1A1D2A)),
                ),
              ),
              Text(
                '${_visibleIndex + 1}/${widget.products.length}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
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

        // Dot indicator (3'ten fazla üründe)
        if (widget.products.length > 3)
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
                    color: i == _visibleIndex ? const Color(0xFF7C6EF2) : const Color(0xFFE0E0E0),
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
      ProfileFeedbackService.recordSaveSignal(
        itemTitle: widget.product.name,
      );
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF6C5CE7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
          content: const Text('Kaydedildi', style: TextStyle(color: Colors.white)),
          action: SnackBarAction(
            label: 'Kaydedilenlerimi Gör',
            textColor: Colors.white,
            onPressed: () {
              Navigator.of(context).pushNamed('/saved');
            },
          ),
        ),
      );
    }
    await Future.delayed(const Duration(milliseconds: 250));
    if (mounted) setState(() => _animating = false);
  }

  void _openProduct() {
    final link = widget.product.url.isNotEmpty
        ? widget.product.url
        : 'https://www.evlumba.com/kesfet?q=${Uri.encodeComponent(widget.product.name)}';
    launchUrl(Uri.parse(link), mode: LaunchMode.inAppBrowserView);
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
                decoration: BoxDecoration(color: const Color(0xFFE0E0E0), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${p.name} hakkında sor',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1A1D2A)),
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
                    color: const Color(0xFFF3F0FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF7C6EF2).withValues(alpha:0.15)),
                  ),
                  child: Text(q, style: const TextStyle(fontSize: 14, color: Color(0xFF7C6EF2), fontWeight: FontWeight.w500)),
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
                          color: _isSaved ? const Color(0xFFE53935) : const Color(0xFF666666),
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
                    // Mağaza
                    if (p.shopName.isNotEmpty)
                      Text(p.shopName,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    // Ürün adı
                    Text(p.name,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1D2A), height: 1.3),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                    const Spacer(),
                    // Fiyat
                    if (p.price.isNotEmpty)
                      Text(p.price,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1D9E75)),
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
                                color: const Color(0xFF1D9E75),
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
                              color: const Color(0xFFF3F0FF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.auto_awesome, size: 12, color: Color(0xFF7C6EF2)),
                                SizedBox(width: 3),
                                Text('Sor', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF7C6EF2))),
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

  Widget _placeholder() {
    return Container(
      width: 180, height: 140,
      color: const Color(0xFFF5F5F5),
      child: const Center(child: Icon(Icons.shopping_bag_outlined, color: Colors.grey, size: 32)),
    );
  }
}
