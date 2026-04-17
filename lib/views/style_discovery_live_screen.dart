// ═══════════════════════════════════════════════════════════
// STYLE DISCOVERY LIVE — tüm evlumba projeleri arasında
// sonsuz swipe deck. Batch'ler halinde (10 kart) streaming
// fetch. Liked projeler SavedItems.design olarak kaydedilir.
// Pass edilenler lokal session memory'de tutulur (dedup için).
//
// Home'daki pull-to-reveal handle'dan açılır.
// ═══════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/koala_tokens.dart';
import '../services/evlumba_live_service.dart';
import '../services/saved_items_service.dart';
import '../services/analytics_service.dart';

class StyleDiscoveryLiveScreen extends StatefulWidget {
  const StyleDiscoveryLiveScreen({super.key});

  @override
  State<StyleDiscoveryLiveScreen> createState() =>
      _StyleDiscoveryLiveScreenState();
}

class _StyleDiscoveryLiveScreenState extends State<StyleDiscoveryLiveScreen>
    with TickerProviderStateMixin {
  static const int _batchSize = 10;
  static const int _prefetchThreshold = 3; // kalan kart sayısı < bu → fetch

  final List<Map<String, dynamic>> _deck = [];
  final Set<String> _seenIds = <String>{};
  int _offset = 0;
  bool _loading = true;
  bool _fetchingMore = false;
  bool _reachedEnd = false;
  int _totalCount = 0;
  int _index = 0;
  int _likeCount = 0;
  int _passCount = 0;

  double _dragDx = 0;
  double _dragDy = 0;
  bool _animatingExit = false;

  late final AnimationController _exitCtrl;
  double _exitStartDx = 0;
  double _exitTargetDx = 0;
  double _exitTargetDy = 0;

  @override
  void initState() {
    super.initState();
    _exitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _onExitComplete();
      });
    _bootstrap();
    Analytics.screenViewed('style_discovery_live');
  }

  Future<void> _bootstrap() async {
    // Evlumba client hazır mı — bekle
    final ready = await EvlumbaLiveService.waitForReady(
        timeout: const Duration(seconds: 6));
    if (!ready) {
      debugPrint('StyleDiscoveryLive: EvlumbaLiveService NOT ready');
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final results = await Future.wait([
        _fetchCount(),
        _fetchBatch(),
      ]);
      if (!mounted) return;
      setState(() {
        _totalCount = results[0] as int;
        _loading = false;
      });
    } catch (e) {
      debugPrint('StyleDiscoveryLive: bootstrap failed → $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<int> _fetchCount() async {
    try {
      if (!EvlumbaLiveService.isReady) return 0;
      final res = await EvlumbaLiveService.client
          .from('designer_projects')
          .select()
          .eq('is_published', true)
          .count();
      return res.count;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _fetchBatch() async {
    if (_fetchingMore || _reachedEnd) return;
    _fetchingMore = true;
    try {
      final batch = await EvlumbaLiveService.getProjects(
        limit: _batchSize,
        offset: _offset,
      );
      _offset += _batchSize;
      if (batch.length < _batchSize) _reachedEnd = true;
      // Dedup + görseli OLAN projeleri al (cover_url fallback chain dahil)
      final filtered = <Map<String, dynamic>>[];
      for (final p in batch) {
        final id = p['id']?.toString() ?? '';
        if (id.isEmpty || _seenIds.contains(id)) continue;
        if (_coverOf(p).isEmpty) continue; // herhangi bir image field yoksa at
        _seenIds.add(id);
        filtered.add(p);
      }
      debugPrint('StyleDiscoveryLive: batch=${batch.length} filtered=${filtered.length} deck=${_deck.length + filtered.length}');
      if (!mounted) return;
      setState(() => _deck.addAll(filtered));
      // Sıradaki 2 kartın cover image'ını precache
      _precacheNext();
    } catch (e) {
      debugPrint('StyleDiscoveryLive: fetchBatch failed → $e');
    } finally {
      _fetchingMore = false;
    }
  }

  void _precacheNext() {
    for (int i = _index + 1; i < math.min(_index + 3, _deck.length); i++) {
      final url = _coverOf(_deck[i]);
      if (url.isNotEmpty) {
        precacheImage(CachedNetworkImageProvider(url), context);
      }
    }
  }

  String _coverOf(Map<String, dynamic> project) {
    for (final k in ['cover_image_url', 'cover_url', 'image_url']) {
      final v = (project[k] ?? '').toString().trim();
      if (v.isNotEmpty && !v.startsWith('data:')) return v;
    }
    final imgs = project['designer_project_images'] as List?;
    if (imgs != null && imgs.isNotEmpty) {
      final sorted = List<Map<String, dynamic>>.from(
        imgs.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
      )..sort((a, b) =>
          ((a['sort_order'] as num?)?.toInt() ?? 9999)
              .compareTo((b['sort_order'] as num?)?.toInt() ?? 9999));
      return (sorted.first['image_url'] ?? '').toString();
    }
    return '';
  }

  String _prettyCategory(String raw) {
    final r = raw.trim().toLowerCase();
    const map = {
      'living_room': 'Oturma Odası',
      'bedroom': 'Yatak Odası',
      'kitchen': 'Mutfak',
      'bathroom': 'Banyo',
      'kids_room': 'Çocuk Odası',
      'office': 'Çalışma Odası',
      'dining_room': 'Yemek Odası',
      'hallway': 'Antre',
    };
    return map[r] ?? raw;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_animatingExit) return;
    setState(() {
      _dragDx += d.delta.dx;
      _dragDy += d.delta.dy * 0.4;
    });
  }

  void _onPanEnd(DragEndDetails d) {
    if (_animatingExit) return;
    final w = MediaQuery.of(context).size.width;
    final threshold = w * 0.28;
    final vx = d.velocity.pixelsPerSecond.dx;
    if (_dragDx.abs() > threshold || vx.abs() > 700) {
      final liked = (_dragDx + vx * 0.15) > 0;
      _swipe(liked: liked);
    } else {
      setState(() {
        _dragDx = 0;
        _dragDy = 0;
      });
    }
  }

  Future<void> _swipe({required bool liked}) async {
    final card = _currentCard;
    if (card == null) return;
    HapticFeedback.selectionClick();
    final w = MediaQuery.of(context).size.width;
    _exitStartDx = _dragDx;
    _exitTargetDx = liked ? w * 1.4 : -w * 1.4;
    _exitTargetDy = _dragDy + 40;
    _animatingExit = true;
    _exitCtrl.forward(from: 0);

    if (liked) {
      _likeCount++;
      // Save as design — arka planda fire-and-forget
      unawaited(SavedItemsService.saveItem(
        type: SavedItemType.design,
        itemId: card['id']?.toString() ?? '',
        title: (card['title'] ?? '').toString(),
        imageUrl: _coverOf(card),
        subtitle: _prettyCategory((card['project_type'] ?? '').toString()),
        extraData: {
          'source': 'style_discovery_live',
          'designer_id': card['designer_id'],
        },
      ));
      unawaited(Analytics.log('style_like', {
        'project_id': card['id'],
        'category': card['project_type'],
      }));
    } else {
      _passCount++;
      unawaited(Analytics.log('style_pass', {
        'project_id': card['id'],
      }));
    }
  }

  void _onExitComplete() {
    setState(() {
      _index++;
      _dragDx = 0;
      _dragDy = 0;
      _animatingExit = false;
    });
    _exitCtrl.reset();
    // Preload sıradakiler
    _precacheNext();
    // Eşiğin altına indiysek yeni batch fetch et
    final remaining = _deck.length - _index;
    if (remaining <= _prefetchThreshold && !_reachedEnd) {
      _fetchBatch();
    }
  }

  Map<String, dynamic>? get _currentCard =>
      _index < _deck.length ? _deck[_index] : null;

  Map<String, dynamic>? get _nextCard =>
      _index + 1 < _deck.length ? _deck[_index + 1] : null;

  @override
  void dispose() {
    _exitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _deck.isEmpty
                ? _emptyState()
                : Column(
                    children: [
                      _header(),
                      Expanded(child: _deckStack()),
                      _buttons(),
                      const SizedBox(height: 16),
                    ],
                  ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.style_outlined,
                size: 48, color: KoalaColors.textTer),
            const SizedBox(height: 12),
            const Text(
              'Şu an gösterilecek tasarım yok',
              style: TextStyle(fontSize: 15, color: KoalaColors.textMed),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Kapat'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final shown = math.min(_index + 1, _deck.length);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(LucideIcons.x, size: 22),
            color: KoalaColors.ink,
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              children: [
                const Text(
                  'Tarzını Keşfedelim',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: KoalaColors.ink,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _totalCount > 0
                      ? '$shown / $_totalCount'
                      : '$shown gösterildi',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: KoalaColors.textSec,
                  ),
                ),
              ],
            ),
          ),
          _likesPill(),
        ],
      ),
    );
  }

  Widget _likesPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: KoalaColors.accentSoft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.favorite_rounded,
              size: 14, color: Color(0xFFEF4444)),
          const SizedBox(width: 4),
          Text(
            '$_likeCount',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: KoalaColors.accentDeep,
            ),
          ),
        ],
      ),
    );
  }

  Widget _deckStack() {
    final current = _currentCard;
    final next = _nextCard;
    if (current == null) {
      return _noMoreCards();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: LayoutBuilder(
        builder: (context, cs) {
          return AnimatedBuilder(
            animation: _exitCtrl,
            builder: (_, __) {
              double dx = _dragDx;
              double dy = _dragDy;
              if (_animatingExit) {
                final t = Curves.easeOutCubic.transform(_exitCtrl.value);
                dx = _exitStartDx +
                    (_exitTargetDx - _exitStartDx) * t;
                dy = _dragDy + (_exitTargetDy - _dragDy) * t;
              }
              final rot = (dx / cs.maxWidth) * 0.22;
              final likeOpacity =
                  (dx / (cs.maxWidth * 0.3)).clamp(0.0, 1.0);
              final passOpacity =
                  (-dx / (cs.maxWidth * 0.3)).clamp(0.0, 1.0);

              return Stack(
                children: [
                  // Arka kart (next) — hafif küçük + altta
                  if (next != null)
                    Positioned.fill(
                      child: Transform.scale(
                        scale: 0.94 +
                            (dx.abs() / cs.maxWidth).clamp(0.0, 1.0) * 0.06,
                        child: Opacity(
                          opacity: 0.6 +
                              (dx.abs() / cs.maxWidth).clamp(0.0, 1.0) * 0.4,
                          child: _Card(project: next, coverOf: _coverOf, prettyCategory: _prettyCategory),
                        ),
                      ),
                    ),
                  // Ön kart + drag
                  Positioned.fill(
                    child: Transform.translate(
                      offset: Offset(dx, dy),
                      child: Transform.rotate(
                        angle: rot,
                        child: GestureDetector(
                          onPanUpdate: _onPanUpdate,
                          onPanEnd: _onPanEnd,
                          child: Stack(
                            children: [
                              _Card(project: current, coverOf: _coverOf, prettyCategory: _prettyCategory),
                              // SEVERIM damgası
                              Positioned(
                                top: 28,
                                left: 20,
                                child: _Stamp(
                                  text: 'SEVERİM',
                                  color: const Color(0xFF22C55E),
                                  opacity: likeOpacity,
                                  rotate: -0.25,
                                ),
                              ),
                              // PAS damgası
                              Positioned(
                                top: 28,
                                right: 20,
                                child: _Stamp(
                                  text: 'PAS',
                                  color: const Color(0xFFEF4444),
                                  opacity: passOpacity,
                                  rotate: 0.25,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _noMoreCards() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.sparkles,
                size: 48, color: KoalaColors.accentDeep),
            const SizedBox(height: 14),
            Text(
              _reachedEnd
                  ? 'Tüm tasarımları gördün!'
                  : 'Birazdan devam...',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: KoalaColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$_likeCount beğeni · $_passCount pas',
              style: const TextStyle(
                fontSize: 13,
                color: KoalaColors.textSec,
              ),
            ),
            const SizedBox(height: 20),
            if (_reachedEnd)
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: KoalaColors.accentDeep,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                child: const Text('Kapat'),
              )
            else
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buttons() {
    final disabled = _currentCard == null || _animatingExit;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundBtn(
            icon: LucideIcons.x,
            color: const Color(0xFFEF4444),
            size: 52,
            onTap: disabled ? null : () => _swipe(liked: false),
          ),
          _RoundBtn(
            icon: Icons.favorite_rounded,
            color: const Color(0xFF22C55E),
            size: 64,
            filled: true,
            onTap: disabled ? null : () => _swipe(liked: true),
          ),
          _RoundBtn(
            icon: LucideIcons.rotateCcw,
            color: KoalaColors.textMed,
            size: 52,
            onTap: null, // MVP: undo yok
          ),
        ],
      ),
    );
  }
}

// ─── Tek kart ───
class _Card extends StatelessWidget {
  const _Card({
    required this.project,
    required this.coverOf,
    required this.prettyCategory,
  });
  final Map<String, dynamic> project;
  final String Function(Map<String, dynamic>) coverOf;
  final String Function(String) prettyCategory;

  IconData _roomIcon(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'living_room':
        return Icons.weekend_outlined;
      case 'bedroom':
        return Icons.bed_outlined;
      case 'kitchen':
        return Icons.countertops_outlined;
      case 'bathroom':
        return Icons.bathtub_outlined;
      case 'kids_room':
        return Icons.child_care_outlined;
      case 'office':
        return Icons.desk_outlined;
      case 'dining_room':
        return Icons.dining_outlined;
      case 'hallway':
        return Icons.door_front_door_outlined;
      default:
        return Icons.home_outlined;
    }
  }

  String _budgetLabel() {
    final min = (project['budget_min'] as num?)?.toInt();
    final max = (project['budget_max'] as num?)?.toInt();
    String fmt(int v) {
      if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
      if (v >= 1000) return '${(v / 1000).round()}K';
      return v.toString();
    }
    if (min != null && max != null && min > 0 && max > 0) {
      return '${fmt(min)}-${fmt(max)}₺';
    }
    if (max != null && max > 0) return '<${fmt(max)}₺';
    if (min != null && min > 0) return '>${fmt(min)}₺';
    return '';
  }

  String _styleLabel() {
    final style = (project['style'] ?? '').toString().trim();
    if (style.isNotEmpty) return style;
    final tags = project['tags'];
    if (tags is List && tags.isNotEmpty) {
      final t = tags.first.toString().trim();
      if (t.isNotEmpty) return t;
    }
    return '';
  }

  List<Color> _paletteColors() {
    final raw = project['palette'] ?? project['colors'];
    if (raw is List) {
      final out = <Color>[];
      for (final e in raw) {
        final s = e.toString().trim();
        if (s.startsWith('#') && s.length >= 7) {
          try {
            out.add(Color(int.parse('FF${s.substring(1, 7)}', radix: 16)));
          } catch (_) {}
        }
      }
      return out;
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final url = coverOf(project);
    final title = (project['title'] ?? '').toString().trim();
    final rawType = (project['project_type'] ?? '').toString().trim();
    final cat = prettyCategory(rawType);
    final designer = project['profiles'] as Map<String, dynamic>?;
    final designerName =
        (designer?['full_name'] ?? '').toString().trim();
    final description = (project['description'] ?? '').toString().trim();
    final subtitle = description.isNotEmpty
        ? description
        : (designerName.isNotEmpty ? '$designerName tasarımı' : '');
    final budget = _budgetLabel();
    final style = _styleLabel();
    final palette = _paletteColors();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: KoalaColors.surfaceAlt,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url.isNotEmpty)
            CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              memCacheWidth: 800,
              placeholder: (_, __) =>
                  Container(color: KoalaColors.surfaceAlt),
              errorWidget: (_, __, ___) => const Center(
                child: Icon(Icons.image_not_supported_outlined,
                    color: KoalaColors.textTer),
              ),
            )
          else
            const Center(
              child: Icon(Icons.image_outlined,
                  color: KoalaColors.textTer, size: 48),
            ),
          // Gradient overlay - top + bottom
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.35, 0.65, 1.0],
                  colors: [
                    Colors.black.withValues(alpha: 0.18),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.15),
                    Colors.black.withValues(alpha: 0.78),
                  ],
                ),
              ),
            ),
          ),

          // Top pills
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Row(
              children: [
                if (cat.isNotEmpty)
                  _GlassPill(icon: _roomIcon(rawType), text: cat),
                if (cat.isNotEmpty && budget.isNotEmpty)
                  const SizedBox(width: 8),
                if (budget.isNotEmpty) _GlassPill(text: budget),
                const Spacer(),
                if (style.isNotEmpty)
                  _GlassPill(text: style, accent: true),
              ],
            ),
          ),

          // Bottom content
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title.isEmpty ? '$cat Projesi' : title,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                      height: 1.1,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (palette.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        for (int i = 0;
                            i < palette.length && i < 4;
                            i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          _ColorDot(color: palette[i]),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Glass pill ───
class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.text, this.icon, this.accent = false});
  final String text;
  final IconData? icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent
            ? KoalaColors.accentDeep.withValues(alpha: 0.88)
            : Colors.black.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: accent ? 0.22 : 0.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Color dot ───
class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.55),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({
    required this.text,
    required this.color,
    required this.opacity,
    required this.rotate,
  });
  final String text;
  final Color color;
  final double opacity;
  final double rotate;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Transform.rotate(
        angle: rotate,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({
    required this.icon,
    required this.color,
    required this.size,
    this.onTap,
    this.filled = false,
  });
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              onTap!();
            },
      child: AnimatedOpacity(
        opacity: disabled ? 0.4 : 1.0,
        duration: const Duration(milliseconds: 180),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? color : Colors.white,
            border: filled ? null : Border.all(color: KoalaColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            icon,
            color: filled ? Colors.white : color,
            size: size * 0.42,
          ),
        ),
      ),
    );
  }
}
