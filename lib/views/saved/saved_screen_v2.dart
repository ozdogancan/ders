import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/koala_tokens.dart';
import '../../services/saved_items_service.dart';
import '../my_designs/my_designs_screen.dart';
import '../my_designs/design_detail_screen.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// SavedScreenV2 — editorial magazine-style "Kaydedilenlerim".
///
/// Tasarım kararları (agent brief'e göre):
/// - TabBar YOK. 4 tür (design / product / designer / palette) dikey olarak
///   ayrı rail'lere dizilir, her rail yatay scroll. Magazine "department" hissi.
/// - Sticky serif word-nav: `Tasarımlar · Ürünler · Tasarımcılar · Paletler` —
///   Fraunces serif, aktif kelime altı çizili accentDeep. Tap → smooth scroll.
/// - Her tür kendi native kart dilini korur:
///   * Design: 260×340 full-bleed hero (my_designs küçültülmüş)
///   * Product: 160×220 beyaz polaroid
///   * Designer: 280×96 calling-card slab
///   * Palette: 140×200 stripe-only card (palet kendisi kart)
/// - Boş state: üç blurlu pastel kart fanlandırılmış breathing animasyon.
class SavedScreenV2 extends StatefulWidget {
  const SavedScreenV2({super.key});

  @override
  State<SavedScreenV2> createState() => _SavedScreenV2State();
}

class _SavedScreenV2State extends State<SavedScreenV2> {
  final _scroll = ScrollController();
  final Map<_RailKind, GlobalKey> _anchors = {
    _RailKind.design: GlobalKey(),
    _RailKind.product: GlobalKey(),
    _RailKind.designer: GlobalKey(),
    _RailKind.palette: GlobalKey(),
  };

  late Future<_SavedData> _future;
  _RailKind _active = _RailKind.design;

  @override
  void initState() {
    super.initState();
    _future = _loadAll();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Viewport top'a en yakın rail'i aktif olarak işaretle.
    _RailKind? nearest;
    double nearestDist = double.infinity;
    for (final e in _anchors.entries) {
      final ctx = e.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      final dist = (y - 120).abs(); // 120 = sticky nav alt noktası
      if (dist < nearestDist) {
        nearestDist = dist;
        nearest = e.key;
      }
    }
    if (nearest != null && nearest != _active) {
      setState(() => _active = nearest!);
    }
  }

  Future<_SavedData> _loadAll() async {
    final results = await Future.wait([
      SavedItemsService.getByType(SavedItemType.design, limit: 20),
      SavedItemsService.getByType(SavedItemType.product, limit: 30),
      SavedItemsService.getByType(SavedItemType.designer, limit: 30),
      SavedItemsService.getByType(SavedItemType.palette, limit: 30),
    ]);
    return _SavedData(
      designs: results[0],
      products: results[1],
      designers: results[2],
      palettes: results[3],
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _loadAll());
    await _future;
  }

  void _jumpTo(_RailKind kind) {
    HapticFeedback.lightImpact();
    final ctx = _anchors[kind]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
    setState(() => _active = kind);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: KoalaColors.accentDeep,
          child: FutureBuilder<_SavedData>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return _skeleton();
              }
              final data = snap.data ?? const _SavedData.empty();
              if (data.isEmpty) return _emptyView();
              return _content(data);
            },
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // Content
  // ─────────────────────────────────────────────────────────

  Widget _content(_SavedData data) {
    final total = data.designs.length +
        data.products.length +
        data.designers.length +
        data.palettes.length;

    return CustomScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(child: _header(total)),
        SliverPersistentHeader(
          pinned: true,
          delegate: _WordNavDelegate(
            active: _active,
            onTap: _jumpTo,
            counts: {
              _RailKind.design: data.designs.length,
              _RailKind.product: data.products.length,
              _RailKind.designer: data.designers.length,
              _RailKind.palette: data.palettes.length,
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: KoalaSpacing.xl)),
        SliverToBoxAdapter(
          child: Container(
            key: _anchors[_RailKind.design],
            child: _DesignRail(items: data.designs, sectionIndex: 0),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: KoalaSpacing.xxxl)),
        SliverToBoxAdapter(
          child: Container(
            key: _anchors[_RailKind.product],
            child: _ProductRail(items: data.products, sectionIndex: 1),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: KoalaSpacing.xxxl)),
        SliverToBoxAdapter(
          child: Container(
            key: _anchors[_RailKind.designer],
            child: _DesignerRail(items: data.designers, sectionIndex: 2),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: KoalaSpacing.xxxl)),
        SliverToBoxAdapter(
          child: Container(
            key: _anchors[_RailKind.palette],
            child: _PaletteRail(items: data.palettes, sectionIndex: 3),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: KoalaSpacing.xxxl)),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  // Header
  // ─────────────────────────────────────────────────────────

  Widget _header(int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KoalaSpacing.xl,
        KoalaSpacing.lg,
        KoalaSpacing.xl,
        KoalaSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              if (GoRouter.of(context).canPop()) {
                GoRouter.of(context).pop();
              } else {
                context.go('/');
              }
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: KoalaColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: KoalaColors.border, width: 0.5),
              ),
              alignment: Alignment.center,
              child: const Icon(LucideIcons.arrowLeft, size: 20),
            ),
          ),
          const SizedBox(height: KoalaSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'Kaydedilenlerim',
                  style: KoalaText.h1.copyWith(
                    fontSize: 34,
                    letterSpacing: -0.8,
                    height: 1.05,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: KoalaColors.accentSoft,
                  borderRadius: BorderRadius.circular(KoalaRadius.pill),
                ),
                child: Text(
                  '$total',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: KoalaColors.accentDeep,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Bir gün eve dönüştüreceklerin',
            style: KoalaText.bodySec,
          ),
        ],
      )
          .animate()
          .fadeIn(duration: 420.ms)
          .slideY(begin: 0.1, end: 0, duration: 420.ms),
    );
  }

  // ─────────────────────────────────────────────────────────
  // Empty / Skeleton
  // ─────────────────────────────────────────────────────────

  Widget _emptyView() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _header(0),
        const SizedBox(height: KoalaSpacing.xxxl),
        Center(child: _emptyDeck()),
        const SizedBox(height: KoalaSpacing.xl),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.xxl),
          child: Column(
            children: [
              Text(
                'Burası senin özenle seçtiklerin',
                style: KoalaText.h2,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: KoalaSpacing.sm),
              Text(
                'Bir tasarım, bir renk, bir mobilya — beğendiğin her '
                'şey kalp ikonuyla buraya düşüyor.',
                style: KoalaText.bodySec.copyWith(height: 1.55),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: KoalaSpacing.xl),
              SizedBox(
                width: 220,
                child: FilledButton.icon(
                  onPressed: () => context.go('/explore'),
                  style: FilledButton.styleFrom(
                    backgroundColor: KoalaColors.accentDeep,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(KoalaRadius.pill),
                    ),
                  ),
                  icon: const Icon(LucideIcons.compass, size: 18),
                  label: const Text(
                    'Keşfet\'e git',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(duration: 420.ms, delay: 100.ms);
  }

  Widget _emptyDeck() {
    // Üç pastel kart fanlandırılmış, breathing.
    return SizedBox(
      width: 180,
      height: 130,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _deckCard(-12, KoalaColors.surfaceAlt),
          _deckCard(0, KoalaColors.accentSoft),
          _deckCard(12, KoalaColors.greenLight),
        ],
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scale(
          begin: const Offset(1, 1),
          end: const Offset(1.03, 1.03),
          duration: 2200.ms,
          curve: Curves.easeInOut,
        );
  }

  Widget _deckCard(double angle, Color color) {
    return Transform.rotate(
      angle: angle * 3.14159 / 180,
      child: Container(
        width: 100,
        height: 130,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(KoalaRadius.lg),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _skeleton() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _header(0),
        const SizedBox(height: KoalaSpacing.xl),
        SizedBox(
          height: 340,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.xl),
            itemCount: 3,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => Container(
              width: 260,
              decoration: BoxDecoration(
                color: KoalaColors.surfaceAlt,
                borderRadius: BorderRadius.circular(KoalaRadius.xl),
              ),
            )
                .animate(onPlay: (c) => c.repeat())
                .shimmer(
                  delay: (i * 120).ms,
                  duration: 1400.ms,
                  color: KoalaColors.surface.withValues(alpha: 0.6),
                ),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════
// Sticky serif word-nav
// ═════════════════════════════════════════════════════════════

class _WordNavDelegate extends SliverPersistentHeaderDelegate {
  final _RailKind active;
  final ValueChanged<_RailKind> onTap;
  final Map<_RailKind, int> counts;

  _WordNavDelegate({
    required this.active,
    required this.onTap,
    required this.counts,
  });

  @override
  double get minExtent => 52;
  @override
  double get maxExtent => 52;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final pinned = shrinkOffset > 0 || overlapsContent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: pinned ? KoalaColors.bg : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: pinned
                ? KoalaColors.border
                : Colors.transparent,
            width: 0.5,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: KoalaSpacing.xl, vertical: 14),
      child: Row(
        children: [
          for (int i = 0; i < _RailKind.values.length; i++) ...[
            _navWord(_RailKind.values[i], i),
            if (i < _RailKind.values.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '·',
                  style: TextStyle(
                    color: KoalaColors.textTer,
                    fontSize: 15,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _navWord(_RailKind kind, int index) {
    final isActive = active == kind;
    final count = counts[kind] ?? 0;
    return GestureDetector(
      onTap: () => onTap(kind),
      behavior: HitTestBehavior.opaque,
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 180),
        style: KoalaText.serif(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: isActive ? KoalaColors.accentDeep : KoalaColors.textSec,
          letterSpacing: -0.1,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kind.label),
                if (count > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontFamily: null,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isActive
                          ? KoalaColors.accentDeep
                          : KoalaColors.textTer,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              height: 1,
              width: isActive ? 16 : 0,
              color: KoalaColors.accentDeep,
            ),
          ],
        ),
      )
          .animate()
          .fadeIn(delay: (180 + index * 40).ms, duration: 320.ms),
    );
  }

  @override
  bool shouldRebuild(covariant _WordNavDelegate oldDelegate) {
    return oldDelegate.active != active ||
        oldDelegate.counts != counts;
  }
}

// ═════════════════════════════════════════════════════════════
// Rails
// ═════════════════════════════════════════════════════════════

abstract class _BaseRail extends StatelessWidget {
  const _BaseRail();
  String get title;
  int get sectionIndex;

  Widget buildHeader(int count, {VoidCallback? onSeeAll}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          KoalaSpacing.xl, 0, KoalaSpacing.xl, KoalaSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title,
            style: KoalaText.serif(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: KoalaColors.text,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 12,
              color: KoalaColors.textTer,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: Text(
                'Tümü',
                style: KoalaText.bodySmall.copyWith(
                  color: KoalaColors.accentDeep,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    )
        .animate()
        .fadeIn(delay: (280 + sectionIndex * 120).ms, duration: 380.ms)
        .slideX(begin: -0.05, end: 0, duration: 380.ms);
  }

  Widget buildEmptyStrip(String copy) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KoalaSpacing.xl),
      height: 88,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(KoalaRadius.lg),
        border: Border.all(
          color: KoalaColors.border,
          width: 0.5,
          style: BorderStyle.solid,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        copy,
        style: KoalaText.bodySmall.copyWith(color: KoalaColors.textSec),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget staggered(Widget child, int cardIndex) {
    final capped = cardIndex > 5 ? 5 : cardIndex;
    return child
        .animate()
        .fadeIn(
          delay: (340 + sectionIndex * 120 + capped * 60).ms,
          duration: 380.ms,
        )
        .slideY(
          begin: 0.12,
          end: 0,
          duration: 380.ms,
          curve: Curves.easeOutCubic,
        );
  }
}

// ───── Design rail ─────
class _DesignRail extends _BaseRail {
  final List<Map<String, dynamic>> items;
  @override
  final int sectionIndex;
  const _DesignRail({required this.items, required this.sectionIndex});

  @override
  String get title => 'Tasarımlar';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildHeader(
          items.length,
          onSeeAll: items.isEmpty
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const MyDesignsScreen()),
                  ),
        ),
        if (items.isEmpty)
          buildEmptyStrip(
              'Henüz AI tasarımın yok — mekanını çek, bir tane üretelim.')
        else
          SizedBox(
            height: 340,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: KoalaSpacing.xl),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => staggered(
                _DesignRailCard(item: items[i]),
                i,
              ),
            ),
          ),
      ],
    );
  }
}

class _DesignRailCard extends StatefulWidget {
  final Map<String, dynamic> item;
  const _DesignRailCard({required this.item});

  @override
  State<_DesignRailCard> createState() => _DesignRailCardState();
}

class _DesignRailCardState extends State<_DesignRailCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final imageUrl = (widget.item['image_url'] as String?) ?? '';
    final title = (widget.item['title'] as String?) ?? 'Mekan';
    final subtitle = (widget.item['subtitle'] as String?) ?? '';

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 420),
            pageBuilder: (_, _, _) =>
                DesignDetailScreen(item: widget.item),
            transitionsBuilder: (_, anim, _, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: Hero(
          tag: 'design-${widget.item['id']}',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(KoalaRadius.xl),
            child: SizedBox(
              width: 260,
              height: 340,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: KoalaColors.surfaceAlt),
                  if (imageUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 280),
                      errorWidget: (_, _, _) => Container(
                        color: KoalaColors.surfaceAlt,
                        alignment: Alignment.center,
                        child: const Icon(
                            LucideIcons.imageOff,
                            color: KoalaColors.textTer),
                      ),
                    ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.transparent,
                          Color(0xCC000000),
                        ],
                        stops: [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14, right: 14, bottom: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ───── Product rail ─────
class _ProductRail extends _BaseRail {
  final List<Map<String, dynamic>> items;
  @override
  final int sectionIndex;
  const _ProductRail({required this.items, required this.sectionIndex});
  @override
  String get title => 'Ürünler';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildHeader(items.length),
        if (items.isEmpty)
          buildEmptyStrip('Beğendiğin ürünleri kalple buraya sakla.')
        else
          SizedBox(
            height: 240,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: KoalaSpacing.xl),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) =>
                  staggered(_ProductRailCard(item: items[i]), i),
            ),
          ),
      ],
    );
  }
}

class _ProductRailCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ProductRailCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final imageUrl = (item['image_url'] as String?) ?? '';
    final title = (item['title'] as String?) ?? 'Ürün';
    final subtitle = (item['subtitle'] as String?) ?? '';

    return Container(
      width: 160,
      decoration: BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(KoalaRadius.lg),
        border: Border.all(color: KoalaColors.border, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(KoalaRadius.md),
              child: imageUrl.isEmpty
                  ? Container(
                      color: KoalaColors.surfaceAlt,
                      alignment: Alignment.center,
                      child: const Icon(LucideIcons.armchair,
                          color: KoalaColors.textTer, size: 28),
                    )
                  : CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 240),
                      errorWidget: (_, _, _) => Container(
                        color: KoalaColors.surfaceAlt,
                        alignment: Alignment.center,
                        child: const Icon(
                            LucideIcons.imageOff,
                            color: KoalaColors.textTer),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              title,
              style: KoalaText.h4,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
              child: Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: KoalaColors.green,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

// ───── Designer rail ─────
class _DesignerRail extends _BaseRail {
  final List<Map<String, dynamic>> items;
  @override
  final int sectionIndex;
  const _DesignerRail({required this.items, required this.sectionIndex});
  @override
  String get title => 'Tasarımcılar';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildHeader(items.length),
        if (items.isEmpty)
          buildEmptyStrip(
              'Projeni gerçeğe dönüştürecek profesyoneller burada olacak.')
        else
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: KoalaSpacing.xl),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) =>
                  staggered(_DesignerRailCard(item: items[i]), i),
            ),
          ),
      ],
    );
  }
}

class _DesignerRailCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _DesignerRailCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final imageUrl = (item['image_url'] as String?) ?? '';
    final name = (item['title'] as String?) ?? 'Tasarımcı';
    final discipline = (item['subtitle'] as String?) ?? 'İç Mimar';

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(KoalaRadius.lg),
        border: Border.all(color: KoalaColors.border, width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: KoalaColors.accentSoft, width: 2),
            ),
            padding: const EdgeInsets.all(2),
            child: ClipOval(
              child: imageUrl.isEmpty
                  ? Container(
                      color: KoalaColors.surfaceAlt,
                      alignment: Alignment.center,
                      child: Text(
                        name.isEmpty
                            ? '?'
                            : name.characters.first.toUpperCase(),
                        style: KoalaText.h3,
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Container(
                        color: KoalaColors.surfaceAlt,
                        alignment: Alignment.center,
                        child: const Icon(LucideIcons.user,
                            color: KoalaColors.textTer),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: KoalaText.h3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  discipline.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: KoalaColors.textSec,
                    letterSpacing: 0.8,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: KoalaColors.accentSoft,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              LucideIcons.messageCircle,
              size: 16,
              color: KoalaColors.accentDeep,
            ),
          ),
        ],
      ),
    );
  }
}

// ───── Palette rail ─────
class _PaletteRail extends _BaseRail {
  final List<Map<String, dynamic>> items;
  @override
  final int sectionIndex;
  const _PaletteRail({required this.items, required this.sectionIndex});
  @override
  String get title => 'Paletler';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildHeader(items.length),
        if (items.isEmpty)
          buildEmptyStrip('AI önerdiği paletleri kalple buraya sakla.')
        else
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: KoalaSpacing.xl),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) =>
                  staggered(_PaletteRailCard(item: items[i]), i),
            ),
          ),
      ],
    );
  }
}

class _PaletteRailCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _PaletteRailCard({required this.item});

  List<Color> _extractColors() {
    final extra = item['extra_data'];
    if (extra is Map) {
      final raw = extra['colors'];
      if (raw is List) {
        final colors = <Color>[];
        for (final c in raw) {
          if (c is String) {
            final parsed = _tryParseHex(c);
            if (parsed != null) colors.add(parsed);
          }
        }
        if (colors.isNotEmpty) return colors;
      }
    }
    // Fallback: hash'ten renk üret — kart hiç boş kalmasın.
    final name = (item['title'] as String?) ?? 'palette';
    final seed = name.hashCode;
    return [
      Color(0xFF000000 | (seed & 0xFFFFFF)),
      KoalaColors.accentSoft,
      KoalaColors.greenLight,
      KoalaColors.surfaceAlt,
    ];
  }

  Color? _tryParseHex(String v) {
    var s = v.replaceAll('#', '').trim();
    if (s.length == 6) s = 'FF$s';
    if (s.length != 8) return null;
    final n = int.tryParse(s, radix: 16);
    return n == null ? null : Color(n);
  }

  @override
  Widget build(BuildContext context) {
    final colors = _extractColors();
    final title = (item['title'] as String?) ?? 'Palet';

    return ClipRRect(
      borderRadius: BorderRadius.circular(KoalaRadius.lg),
      child: SizedBox(
        width: 140,
        height: 210,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Stripeler
            Column(
              children: [
                for (final c in colors)
                  Expanded(child: Container(color: c)),
              ],
            ),
            // Alt etiket
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                color: const Color(0xCC000000),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 10),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════
// Types
// ═════════════════════════════════════════════════════════════

enum _RailKind { design, product, designer, palette }

extension on _RailKind {
  String get label {
    switch (this) {
      case _RailKind.design:
        return 'Tasarımlar';
      case _RailKind.product:
        return 'Ürünler';
      case _RailKind.designer:
        return 'Tasarımcılar';
      case _RailKind.palette:
        return 'Paletler';
    }
  }
}

class _SavedData {
  final List<Map<String, dynamic>> designs;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> designers;
  final List<Map<String, dynamic>> palettes;
  const _SavedData({
    required this.designs,
    required this.products,
    required this.designers,
    required this.palettes,
  });
  const _SavedData.empty()
      : designs = const [],
        products = const [],
        designers = const [],
        palettes = const [];

  bool get isEmpty =>
      designs.isEmpty &&
      products.isEmpty &&
      designers.isEmpty &&
      palettes.isEmpty;
}
