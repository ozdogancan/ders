// LazyGridView — generic cursor-paginated grid for profile portfolio surfaces.
//
// Birden çok ekranda (unified_profile_view, profile_tab, mini_profile_sheet,
// conversation_detail Tümünü gör sheet, style_discovery DesignerProfileSheet)
// kullanılan tek pagination primitive'i. Cursor olarak `created_at` (ya da
// herhangi opaque dynamic) kullanır — offset KULLANMAZ, çünkü yeni satır
// insert'ı offset'i kaydırır ve dup/missing'e yol açar.
//
// Kullanım:
//   LazyGridView<MyT>(
//     fetch: (cursor) async {
//       final res = await Service.pagedMethod(beforeCreatedAt: cursor);
//       return (items: res.items, hasMore: res.hasMore, cursor: res.nextCursor);
//     },
//     itemBuilder: (ctx, item, i) => MyTile(item),
//     idOf: (item) => item.id,
//   )
//
// Davranış:
//   - İlk fetch initState'te tetiklenir (cursor=null).
//   - ScrollController bottomThreshold'a yaklaşınca next fetch.
//   - 240ms debounce — double-fire engellendi.
//   - Set<id> dedupe — defansif (cursor edge case).
//   - shrinkWrap: false → CustomScrollView içine gömülmek için
//     `embedded: true` parametresi kullanılabilir (kendi controller'ı yok,
//     parent'a NotificationListener bağlanır — ileride).
//   - Boş initial: emptyState
//   - hasMore=false: endFooter

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/koala_tokens.dart';

typedef LazyPage<T> = ({List<T> items, bool hasMore, dynamic cursor});
typedef LazyFetch<T> = Future<LazyPage<T>> Function(dynamic cursor);
typedef LazyIdOf<T> = String Function(T item);

class LazyGridView<T> extends StatefulWidget {
  final LazyFetch<T> fetch;
  final Widget Function(BuildContext, T, int index) itemBuilder;
  final LazyIdOf<T> idOf;

  final int crossAxisCount;
  final double aspectRatio;
  final double spacing;
  final EdgeInsets padding;
  final double bottomThreshold;

  /// shrinkWrap: parent zaten scroll yapıyorsa true ver, kendi controller
  /// kullanma — parent'ın scroll'una bağlan.
  final bool shrinkWrap;

  /// Eğer non-null ise dış scroll controller — `shrinkWrap=true` ile beraber
  /// kullanılırsa LazyGridView kendi listener'ını bu controller'a bağlar.
  final ScrollController? parentScrollController;

  final Widget? emptyState;
  final Widget? loadingFooter;
  final Widget? endFooter;

  const LazyGridView({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    required this.idOf,
    this.crossAxisCount = 3,
    this.aspectRatio = 1.0,
    this.spacing = 2,
    this.padding = EdgeInsets.zero,
    this.bottomThreshold = 240,
    this.shrinkWrap = false,
    this.parentScrollController,
    this.emptyState,
    this.loadingFooter,
    this.endFooter,
  });

  @override
  State<LazyGridView<T>> createState() => _LazyGridViewState<T>();
}

class _LazyGridViewState<T> extends State<LazyGridView<T>> {
  final List<T> _items = <T>[];
  final Set<String> _seen = <String>{};
  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  dynamic _cursor;
  DateTime _lastFetchAt = DateTime.fromMillisecondsSinceEpoch(0);

  ScrollController? _internalCtrl;
  ScrollController get _activeCtrl =>
      widget.parentScrollController ?? _internalCtrl!;

  @override
  void initState() {
    super.initState();
    if (widget.parentScrollController == null && !widget.shrinkWrap) {
      _internalCtrl = ScrollController();
    }
    _activeCtrl.addListener(_onScroll);
    // İlk fetch microtask'e at — context.size vs. henüz yok ama fetch için
    // bunlara ihtiyaç yok, sadece async başlat.
    Future.microtask(_loadInitial);
  }

  @override
  void didUpdateWidget(covariant LazyGridView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.parentScrollController != oldWidget.parentScrollController) {
      oldWidget.parentScrollController?.removeListener(_onScroll);
      _internalCtrl?.removeListener(_onScroll);
      _internalCtrl?.dispose();
      _internalCtrl = widget.parentScrollController == null && !widget.shrinkWrap
          ? ScrollController()
          : null;
      _activeCtrl.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _activeCtrl.removeListener(_onScroll);
    _internalCtrl?.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loadingInitial) return;
    final ctrl = _activeCtrl;
    if (!ctrl.hasClients) return;
    final pos = ctrl.position;
    final distanceFromBottom = pos.maxScrollExtent - pos.pixels;
    if (distanceFromBottom <= widget.bottomThreshold) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    try {
      final page = await widget.fetch(null);
      if (!mounted) return;
      _ingest(page);
      setState(() => _loadingInitial = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingInitial = false;
        _hasMore = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final now = DateTime.now();
    if (now.difference(_lastFetchAt).inMilliseconds < 240) return;
    _lastFetchAt = now;
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.fetch(_cursor);
      if (!mounted) return;
      _ingest(page);
    } catch (_) {
      // Bir kez hata → sona ulaştık varsay (kullanıcı pull-to-refresh ile
      // dener). Defansif: sonsuz retry loop'a girme.
      if (mounted) {
        setState(() => _hasMore = false);
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _ingest(LazyPage<T> page) {
    final fresh = <T>[];
    for (final it in page.items) {
      final id = widget.idOf(it);
      if (id.isEmpty || _seen.contains(id)) continue;
      _seen.add(id);
      fresh.add(it);
    }
    setState(() {
      _items.addAll(fresh);
      _hasMore = page.hasMore && fresh.isNotEmpty;
      _cursor = page.cursor;
    });
  }

  Future<void> refresh() async {
    _seen.clear();
    _items.clear();
    _cursor = null;
    _hasMore = true;
    setState(() => _loadingInitial = true);
    await _loadInitial();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
        '[lazy-grid build] items=${_items.length} hasMore=$_hasMore loadingInitial=$_loadingInitial loadingMore=$_loadingMore shrinkWrap=${widget.shrinkWrap}');
    if (_loadingInitial) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: widget.loadingFooter ??
              const CircularProgressIndicator(
                color: KoalaColors.accentDeep,
                strokeWidth: 2,
              ),
        ),
      );
    }
    if (_items.isEmpty) {
      return widget.emptyState ??
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
            child: Center(
              child: Text(
                'Henüz tasarım yok.',
                style: KoalaText.bodySec,
                textAlign: TextAlign.center,
              ),
            ),
          );
    }

    if (widget.shrinkWrap) {
      // ─────────────────────────────────────────────────────────────
      // FIX (2026-05-28): The previous nested CustomScrollView(shrinkWrap)
      // path collapsed to 0 height when the parent was a ListView (header
      // showed "N adet" but tiles never painted). Replaced with the proven
      // GridView.builder(shrinkWrap+NeverScrollable) + footer Column pattern.
      // ─────────────────────────────────────────────────────────────
      return Padding(
        padding: widget.padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: widget.crossAxisCount,
                mainAxisSpacing: widget.spacing,
                crossAxisSpacing: widget.spacing,
                childAspectRatio: widget.aspectRatio,
              ),
              itemCount: _items.length,
              itemBuilder: (ctx, i) => widget.itemBuilder(ctx, _items[i], i),
            ),
            _footer(),
          ],
        ),
      );
    }

    // Self-scrolling path — CustomScrollView with own controller.
    final slivers = <Widget>[
      SliverPadding(
        padding: widget.padding,
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: widget.crossAxisCount,
            mainAxisSpacing: widget.spacing,
            crossAxisSpacing: widget.spacing,
            childAspectRatio: widget.aspectRatio,
          ),
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => widget.itemBuilder(ctx, _items[i], i),
            childCount: _items.length,
          ),
        ),
      ),
      SliverToBoxAdapter(child: _footer()),
    ];
    return CustomScrollView(
      controller: _internalCtrl,
      slivers: slivers,
    );
  }

  Widget _footer() {
    if (_loadingMore) {
      return widget.loadingFooter ??
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: KoalaColors.accentDeep,
                  strokeWidth: 2,
                ),
              ),
            ),
          );
    }
    if (!_hasMore) {
      return widget.endFooter ??
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text(
                'Hepsi bu kadar 🐨',
                style: TextStyle(
                  fontSize: 12,
                  color: KoalaColors.textTer,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          );
    }
    return const SizedBox(height: 12);
  }
}
