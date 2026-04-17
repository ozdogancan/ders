// ═══════════════════════════════════════════════════════════
// STYLE DISCOVERY LIVE — tüm evlumba projeleri arasında
// sonsuz, karıştırılmış (shuffled) swipe deck. Kullanıcı
// tasarım sayısını GÖRMEZ. Liked projeler SavedItems.design
// olarak kaydedilir. Wrap-around ile sonsuz akış.
//
// Home'daki pull-to-reveal handle'dan açılır.
// ═══════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/koala_tokens.dart';
import '../services/evlumba_live_service.dart';
import '../services/messaging_service.dart';
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
  final math.Random _rng = math.Random();
  // designer_id → profile. Lazy cache — card için küçük avatar+isim chip'i.
  final Map<String, Map<String, dynamic>> _designerCache = {};
  final Set<String> _designerInFlight = <String>{};
  int _offset = 0;
  bool _loading = true;
  bool _fetchingMore = false;
  bool _askingInFlight = false;
  int _totalCount = 0;
  int _index = 0;

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
    final ready = await EvlumbaLiveService.waitForReady(
        timeout: const Duration(seconds: 6));
    if (!ready) {
      debugPrint('StyleDiscoveryLive: EvlumbaLiveService NOT ready');
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      _totalCount = await _fetchCount();
      // Her oturumda rastgele offset — aynı sıra tekrarlanmasın
      if (_totalCount > _batchSize) {
        _offset = _rng.nextInt(math.max(1, _totalCount - _batchSize));
      } else {
        _offset = 0;
      }
      await _fetchBatch();
      if (!mounted) return;
      setState(() => _loading = false);
      _prefetchCurrentDesigner();
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
    if (_fetchingMore) return;
    _fetchingMore = true;
    try {
      final batch = await EvlumbaLiveService.getProjects(
        limit: _batchSize,
        offset: _offset,
      );
      _offset += _batchSize;
      // Wrap-around: bir tur tamamlandıysa başa dön ve seenIds temizle
      if (batch.isEmpty) {
        _offset = 0;
        _seenIds.clear();
        final retry = await EvlumbaLiveService.getProjects(
          limit: _batchSize,
          offset: 0,
        );
        _offset = _batchSize;
        batch.addAll(retry);
      }
      // Batch'i karıştır — random sıra
      batch.shuffle(_rng);
      // Dedup + görsel filtrele
      final filtered = <Map<String, dynamic>>[];
      for (final p in batch) {
        final id = p['id']?.toString() ?? '';
        if (id.isEmpty || _seenIds.contains(id)) continue;
        if (_coverOf(p).isEmpty) continue;
        _seenIds.add(id);
        filtered.add(p);
      }
      debugPrint(
          'StyleDiscoveryLive: batch=${batch.length} filtered=${filtered.length} deck=${_deck.length + filtered.length} offset=$_offset');
      if (!mounted) return;
      setState(() => _deck.addAll(filtered));
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
    _precacheNext();
    _prefetchCurrentDesigner();
    final remaining = _deck.length - _index;
    if (remaining <= _prefetchThreshold) {
      _fetchBatch();
    }
  }

  void _prefetchCurrentDesigner() {
    final c = _currentCard;
    if (c == null) return;
    final did = (c['designer_id'] ?? '').toString();
    if (did.isNotEmpty) unawaited(_loadDesigner(did));
    // Sonraki kart için de önceden yükle
    final n = _nextCard;
    if (n != null) {
      final nid = (n['designer_id'] ?? '').toString();
      if (nid.isNotEmpty) unawaited(_loadDesigner(nid));
    }
  }

  Map<String, dynamic>? get _currentCard =>
      _index < _deck.length ? _deck[_index] : null;

  Map<String, dynamic>? get _nextCard =>
      _index + 1 < _deck.length ? _deck[_index + 1] : null;

  void _onBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      context.go('/');
    }
  }

  Future<void> _onAskDesigner() async {
    if (_askingInFlight) return;
    final card = _currentCard;
    if (card == null) return;
    final designerId = (card['designer_id'] ?? '').toString();
    if (designerId.isEmpty) return;
    setState(() => _askingInFlight = true);
    final projectId = card['id']?.toString() ?? '';
    final cat = _prettyCategory((card['project_type'] ?? '').toString());
    final coverUrl = _coverOf(card);
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
    final convId = (conv['id'] ?? '').toString();
    if (convId.isEmpty) return;
    // Tasarımcı profilini cache'den al — ismi/avatarı chat header'ına geçir.
    // Yoksa hızlıca çek (blok süresi kısa, kullanıcı fark etmez).
    Map<String, dynamic>? d = _designerCache[designerId];
    d ??= await EvlumbaLiveService.getDesigner(designerId);
    if (!mounted) return;
    final designerName =
        ((d?['full_name'] ?? d?['business_name'] ?? '') as String).trim();
    final designerAvatar = ((d?['avatar_url'] ?? '') as String).trim();
    // /chat/dm'e push — swipe ekranı stack'te kalır, native back ile geri dönülür
    context.push('/chat/dm/$convId', extra: {
      'designerId': designerId,
      if (designerName.isNotEmpty) 'designerName': designerName,
      if (designerAvatar.isNotEmpty) 'designerAvatarUrl': designerAvatar,
      'pendingDesign': {
        'id': projectId,
        'title': cat,
        'imageUrl': coverUrl,
        'designerId': designerId,
      },
    });
  }

  /// Lazy fetch designer info for the card's designer_id.
  /// Cache'li → tekrarlı çağrı ucuz. setState sadece cache değişirse.
  Future<void> _loadDesigner(String designerId) async {
    if (designerId.isEmpty) return;
    if (_designerCache.containsKey(designerId)) return;
    if (_designerInFlight.contains(designerId)) return;
    _designerInFlight.add(designerId);
    final d = await EvlumbaLiveService.getDesigner(designerId);
    _designerInFlight.remove(designerId);
    if (!mounted || d == null) return;
    setState(() => _designerCache[designerId] = d);
  }

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
                      const SizedBox(height: 20),
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
              onPressed: _onBack,
              child: const Text('Kapat'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    // Mesaj ekranı ile birebir aynı tipografi & back iconu — app tutarlılığı.
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: _onBack,
            icon: const Icon(Icons.arrow_back_rounded,
                color: KoalaColors.text, size: 22),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Tarzını Keşfet',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: KoalaColors.text,
                  height: 1.2,
                ),
              ),
            ),
          ),
          // IconButton default 48 genişlik — title tam merkezde kalsın diye
          // sağda aynı genişlikte boşluk
          const SizedBox(width: 48),
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
                dx = _exitStartDx + (_exitTargetDx - _exitStartDx) * t;
                dy = _dragDy + (_exitTargetDy - _dragDy) * t;
              }
              final rot = (dx / cs.maxWidth) * 0.22;
              final likeOpacity =
                  (dx / (cs.maxWidth * 0.3)).clamp(0.0, 1.0);
              final passOpacity =
                  (-dx / (cs.maxWidth * 0.3)).clamp(0.0, 1.0);

              return Stack(
                children: [
                  if (next != null)
                    Positioned.fill(
                      child: Transform.scale(
                        scale: 0.94 +
                            (dx.abs() / cs.maxWidth).clamp(0.0, 1.0) * 0.06,
                        child: Opacity(
                          opacity: 0.6 +
                              (dx.abs() / cs.maxWidth).clamp(0.0, 1.0) * 0.4,
                          child: _Card(
                            project: next,
                            coverOf: _coverOf,
                            prettyCategory: _prettyCategory,
                            designer: _designerCache[
                                (next['designer_id'] ?? '').toString()],
                          ),
                        ),
                      ),
                    ),
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
                              _Card(
                                project: current,
                                coverOf: _coverOf,
                                prettyCategory: _prettyCategory,
                                designer: _designerCache[
                                    (current['designer_id'] ?? '').toString()],
                              ),
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
            const Text(
              'Biraz dinlenelim, sonra yenileri gelsin ✨',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: KoalaColors.ink,
              ),
            ),
            const SizedBox(height: 20),
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
    // Modern, uygulama aksentine bağlı, 3'lü denge: Pas — Beğen (primary) — Sor
    final askDisabled = disabled ||
        ((_currentCard?['designer_id'] ?? '').toString().isEmpty) ||
        _askingInFlight;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 4, 32, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionBtn(
            icon: LucideIcons.x,
            label: 'Geç',
            onTap: disabled ? null : () => _swipe(liked: false),
            variant: _ActionVariant.outlined,
          ),
          _ActionBtn(
            icon: Icons.favorite_rounded,
            label: 'Beğen',
            onTap: disabled ? null : () => _swipe(liked: true),
            variant: _ActionVariant.primary,
            large: true,
          ),
          _ActionBtn(
            icon: LucideIcons.messageCircle,
            label: 'Sor',
            onTap: askDisabled ? null : _onAskDesigner,
            variant: _ActionVariant.soft,
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
    this.designer,
  });
  final Map<String, dynamic> project;
  final String Function(Map<String, dynamic>) coverOf;
  final String Function(String) prettyCategory;
  final Map<String, dynamic>? designer;

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

  String _firstSentence(String s) {
    final t = s.trim();
    if (t.isEmpty) return '';
    // İlk nokta/ünlem/soru işaretine kadar
    final idx = t.indexOf(RegExp(r'[.!?]'));
    if (idx > 0 && idx < t.length - 1) return t.substring(0, idx + 1);
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final url = coverOf(project);
    final title = (project['title'] ?? '').toString().trim();
    final rawType = (project['project_type'] ?? '').toString().trim();
    final cat = prettyCategory(rawType);
    final description = (project['description'] ?? '').toString().trim();
    final subtitle = _firstSentence(description);
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
          // Gradient overlay - alttan üste (merkez 60% görsel kalsın)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.2, 0.7, 1.0],
                  colors: [
                    Colors.black.withValues(alpha: 0.12),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.78),
                  ],
                ),
              ),
            ),
          ),

          // Top pills — SADECE oda pill + (opsiyonel) stil
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Row(
              children: [
                if (cat.isNotEmpty)
                  _GlassPill(icon: _roomIcon(rawType), text: cat),
                const Spacer(),
                if (style.isNotEmpty)
                  _GlassPill(text: style, accent: true),
              ],
            ),
          ),

          // Bottom content — en alt ~25%
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
                    title.isEmpty ? (cat.isEmpty ? 'Tasarım' : '$cat Projesi') : title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                      height: 1.15,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: Colors.white.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (designer != null) ...[
                    const SizedBox(height: 12),
                    _DesignerChip(designer: designer!),
                  ],
                  if (palette.isNotEmpty) ...[
                    const SizedBox(height: 12),
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

enum _ActionVariant { outlined, soft, primary }

/// Modern aksiyon butonu — ikon dairesi + alt label.
/// Koala aksent paletine sadık, hepsi aynı görsel dilde.
class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.variant,
    this.onTap,
    this.large = false,
  });
  final IconData icon;
  final String label;
  final _ActionVariant variant;
  final VoidCallback? onTap;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final size = large ? 68.0 : 56.0;
    final iconSize = large ? 28.0 : 22.0;

    Color bg;
    Color fg;
    Color? border;
    List<BoxShadow>? shadow;

    switch (variant) {
      case _ActionVariant.outlined:
        bg = Colors.white;
        fg = KoalaColors.textMed;
        border = KoalaColors.border;
        shadow = [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ];
        break;
      case _ActionVariant.soft:
        bg = KoalaColors.accentSoft;
        fg = KoalaColors.accentDeep;
        border = null;
        shadow = null;
        break;
      case _ActionVariant.primary:
        bg = KoalaColors.accentDeep;
        fg = Colors.white;
        border = null;
        shadow = [
          BoxShadow(
            color: KoalaColors.accentDeep.withValues(alpha: 0.30),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ];
        break;
    }

    return AnimatedOpacity(
      opacity: disabled ? 0.4 : 1.0,
      duration: const Duration(milliseconds: 180),
      child: GestureDetector(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                onTap!();
              },
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bg,
                border: border != null ? Border.all(color: border) : null,
                boxShadow: shadow,
              ),
              child: Icon(icon, color: fg, size: iconSize),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: KoalaColors.textSec,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kart altında tasarımcı avatar + ismi — kullanıcı bu tasarımın kime
/// ait olduğunu bilsin. Dark gradient üzerinde okunaklı, küçük ve zarif.
class _DesignerChip extends StatelessWidget {
  const _DesignerChip({required this.designer});
  final Map<String, dynamic> designer;

  @override
  Widget build(BuildContext context) {
    final name = (designer['full_name'] ??
            designer['business_name'] ??
            '')
        .toString()
        .trim();
    final avatar = (designer['avatar_url'] ?? '').toString().trim();
    if (name.isEmpty && avatar.isEmpty) return const SizedBox.shrink();

    final initials = _initials(name);
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KoalaColors.accentDeep,
              image: avatar.isEmpty
                  ? null
                  : DecorationImage(
                      image: CachedNetworkImageProvider(avatar),
                      fit: BoxFit.cover,
                    ),
            ),
            alignment: Alignment.center,
            child: avatar.isEmpty
                ? Text(
                    initials,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              name.isEmpty ? 'Tasarımcı' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '·';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}
