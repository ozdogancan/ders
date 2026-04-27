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
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/koala_tokens.dart';
import '../services/evlumba_live_service.dart';
import '../services/messaging_service.dart';
import '../services/saved_items_service.dart';
import '../services/analytics_service.dart';
import '../services/taste_profile_service.dart';

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

  // Kategori filtresi — opsiyonel. null / boş = Hepsi.
  // Persist key: SharedPreferences üzerinden session'lar arası korunur.
  static const String _prefsCategoryKey = 'style_discovery_category';
  // Sıra burada UI'da kullanılan sıra — bottom sheet chip sırası.
  // Key = DB'deki project_type değeri (Türkçe, ilike ile eşleştirilir).
  // Sadece canlı verilerde gerçekten proje olan kategoriler listelenir.
  static const List<MapEntry<String, String>> _categoryOptions = [
    MapEntry('', 'Hepsi'),
    MapEntry('Oturma Odası', 'Oturma Odası'),
    MapEntry('Yatak Odası', 'Yatak Odası'),
    MapEntry('Mutfak', 'Mutfak'),
    MapEntry('Banyo', 'Banyo'),
    MapEntry('Antre', 'Antre'),
  ];
  String? _selectedCategory; // null = Hepsi

  final List<Map<String, dynamic>> _deck = [];
  final Set<String> _seenIds = <String>{};
  // Undo stack — her swipe'ta {index, liked, id} push.
  final List<Map<String, dynamic>> _history = [];
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
    _loadSavedCategory().then((_) => _bootstrap());
    Analytics.screenViewed('style_discovery_live');
  }

  Future<void> _loadSavedCategory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_prefsCategoryKey) ?? '';
      // Sadece mevcut kategori listesinde varsa set et — eski slug ('living_room' vs)
      // kayıtları sessizce görmezden gel, "Hepsi" default kalsın.
      final validKeys = _categoryOptions.map((e) => e.key).toSet();
      if (v.isNotEmpty && validKeys.contains(v)) _selectedCategory = v;
    } catch (_) {/* sessiz geç — filtre yoksa "Hepsi" */}
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
      var q = EvlumbaLiveService.client
          .from('designer_projects')
          .select()
          .eq('is_published', true);
      final cat = _selectedCategory;
      if (cat != null && cat.isNotEmpty) {
        q = q.ilike('project_type', cat);
      }
      final res = await q.count();
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
        projectType: _selectedCategory,
      );
      _offset += _batchSize;
      // Wrap-around: bir tur tamamlandıysa başa dön ve seenIds temizle
      if (batch.isEmpty) {
        _offset = 0;
        _seenIds.clear();
        final retry = await EvlumbaLiveService.getProjects(
          limit: _batchSize,
          offset: 0,
          projectType: _selectedCategory,
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
    // Undo için snapshot al — exit animasyonu bitince _index++ oluyor.
    _history.add({
      'index': _index,
      'liked': liked,
      'id': card['id']?.toString() ?? '',
    });
    HapticFeedback.selectionClick();
    final w = MediaQuery.of(context).size.width;
    _exitStartDx = _dragDx;
    _exitTargetDx = liked ? w * 1.4 : -w * 1.4;
    _exitTargetDy = _dragDy + 40;
    _animatingExit = true;
    _exitCtrl.forward(from: 0);

    // Taste profile sinyali — arka planda, swipe animasyonunu bloklamaz.
    if (liked) {
      unawaited(TasteProfileService.recordLike(card));
    } else {
      unawaited(TasteProfileService.recordPass(card));
    }

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

  Future<void> _undo() async {
    if (_history.isEmpty || _animatingExit) return;
    final last = _history.removeLast();
    final liked = last['liked'] == true;
    final id = (last['id'] ?? '').toString();
    HapticFeedback.selectionClick();
    setState(() {
      if (_index > 0) _index--;
      _dragDx = 0;
      _dragDy = 0;
    });
    // Dedup set'inden çıkar — tekrar görünebilsin (ileride yeniden karışırsa).
    if (id.isNotEmpty) _seenIds.remove(id);
    // Beğeni geri alınırsa kayıtlardan da düş (taste profile undo metodu yok,
    // sessiz geç — kritik değil, sadece save temizlensin).
    if (liked && id.isNotEmpty) {
      unawaited(SavedItemsService.removeItem(
        type: SavedItemType.design,
        itemId: id,
      ));
    }
    _precacheNext();
    _prefetchCurrentDesigner();
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
    final projectId = card['id']?.toString() ?? '';
    final cat = _prettyCategory((card['project_type'] ?? '').toString());
    final coverUrl = _coverOf(card);
    // Karttan gizlediğimiz bilgileri chat preview'a taşıyoruz: proje başlığı
    // + kısa açıklama. "Sor"a basınca kullanıcı neyi sorduğunu görsün diye.
    final projectTitle = (card['title'] ?? '').toString().trim();
    final rawDesc = (card['description'] ?? '').toString().trim();
    final tagline = _quickFirstSentence(rawDesc);

    // ── Optimistic navigation ──
    // Eskiden burada `getOrCreateConversation` await ediliyordu → 500-1500ms
    // kullanıcıyı bekletiyordu ("Sor"a basınca buton spinner'da donuyordu).
    // Artık: designer info cache'den sync al, navigation'ı HEMEN başlat,
    // conversation'ı ConversationDetailScreen._ensureConversation() ilk
    // mesaj gönderildiğinde lazy olarak yaratsın. /chat/dm/new sentinel
    // router'da null convId'ye map ediliyor.
    final d = _designerCache[designerId];
    final designerName =
        ((d?['full_name'] ?? d?['business_name'] ?? '') as String).trim();
    final designerAvatar = ((d?['avatar_url'] ?? '') as String).trim();

    // Çift-tap koruması: 600ms pencere yeterli — route transition animasyonu
    // tamamlanana kadar buton dondurulur. Pop edince _askingInFlight zaten
    // otomatik sıfırlanır (timer).
    setState(() => _askingInFlight = true);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _askingInFlight = false);
    });

    context.push('/chat/dm/new', extra: {
      'designerId': designerId,
      if (designerName.isNotEmpty) 'designerName': designerName,
      if (designerAvatar.isNotEmpty) 'designerAvatarUrl': designerAvatar,
      'projectTitle': projectTitle.isNotEmpty ? projectTitle : cat,
      'pendingDesign': {
        'id': projectId,
        // Başlık önceliği: proje title → oda kategorisi → jenerik
        'title': projectTitle.isNotEmpty
            ? projectTitle
            : (cat.isNotEmpty ? '$cat projesi' : 'Tasarım'),
        if (tagline.isNotEmpty) 'tagline': tagline,
        if (cat.isNotEmpty) 'category': cat,
        'imageUrl': coverUrl,
        'designerId': designerId,
        // Context bilgisi: _ensureConversation bu bilgileri
        // getOrCreateConversation'a geçemez (sadece designerId + projectTitle
        // kullanıyor) ama projectTitle yeterli — conversation.context_title
        // doğru kayıt edilecek.
      },
    });
  }

  /// İlk cümle — chat preview'da ipucu olarak göstermek için.
  String _quickFirstSentence(String s) {
    final t = s.trim();
    if (t.isEmpty) return '';
    final idx = t.indexOf(RegExp(r'[.!?]'));
    final cut = idx < 0 ? t : t.substring(0, idx).trim();
    // Çok uzunsa kısalt
    return cut.length > 140 ? '${cut.substring(0, 137)}…' : cut;
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
      // Mesajlar ekranı ile birebir aynı AppBar — leading/title hizası app genelinde tutarlı.
      appBar: AppBar(
        backgroundColor: KoalaColors.bg,
        surfaceTintColor: KoalaColors.bg,
        elevation: 0,
        leading: IconButton(
          onPressed: _onBack,
          icon: const Icon(LucideIcons.arrowLeft),
        ),
        title: const Text('Tarzını Keşfet', style: KoalaText.h2),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildCategoryBar(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _deck.isEmpty
                      ? _emptyState()
                      : Column(
                          children: [
                            Expanded(child: _deckStack()),
                            _buttons(),
                            const SizedBox(height: 20),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    final filtered =
        _selectedCategory != null && _selectedCategory!.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.sparkles,
                size: 48, color: KoalaColors.textTer),
            const SizedBox(height: 12),
            Text(
              filtered
                  ? 'Bu kategoride gösterilecek tasarım kalmadı'
                  : 'Şu an gösterilecek tasarım yok',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15, color: KoalaColors.textMed),
            ),
            const SizedBox(height: 16),
            if (filtered)
              TextButton(
                onPressed: _openCategorySheet,
                child: const Text('Kategoriyi değiştir'),
              )
            else
              TextButton(
                onPressed: _onBack,
                child: const Text('Kapat'),
              ),
          ],
        ),
      ),
    );
  }

  // ───── Kategori filtresi ─────
  // Minimalist bir bottom sheet. Chip'ler pill-shape, ikonsuz.
  // User geri bildirimi: "kaos olmasın" — sade tut.
  Future<void> _openCategorySheet() async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: KoalaColors.bg,
      barrierColor: Colors.black54,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final current = _selectedCategory ?? '';
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: KoalaColors.border,
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('Kategori seç', style: KoalaText.h2),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final e in _categoryOptions)
                      _CategoryChip(
                        label: e.value,
                        active: current == e.key,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _applyCategory(e.key);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// AppBar'ın hemen altında — net, her zaman görünür yatay kategori bar'ı.
  /// Kullanıcı AppBar süzgeç ikonunu gözden kaçırırsa bile buradan seçebilir.
  Widget _buildCategoryBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: KoalaColors.bg,
        border: Border(
          bottom: BorderSide(color: KoalaColors.border, width: 0.5),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _categoryOptions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final e = _categoryOptions[i];
          final active = (_selectedCategory ?? '') == e.key;
          return _CategoryChip(
            label: e.value,
            active: active,
            onTap: () => _applyCategory(e.key),
          );
        },
      ),
    );
  }

  Future<void> _applyCategory(String key) async {
    final normalized = key.trim();
    final next = normalized.isEmpty ? null : normalized;
    final current = _selectedCategory;
    if (next == current) return; // no-op
    HapticFeedback.selectionClick();
    unawaited(Analytics.log('style_category_filter', {
      'category': normalized.isEmpty ? 'all' : normalized,
    }));
    // Persist
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsCategoryKey, normalized);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _selectedCategory = next;
      _deck.clear();
      _seenIds.clear();
      _history.clear();
      _index = 0;
      _offset = 0;
      _dragDx = 0;
      _dragDy = 0;
      _loading = true;
    });
    await _bootstrap();
  }

  // ignore: unused_element
  Widget _header() {
    // Mesaj ekranı ile birebir aynı tipografi & back iconu — app tutarlılığı.
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: _onBack,
            icon: const Icon(LucideIcons.arrowLeft,
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
    final undoDisabled = _history.isEmpty || _animatingExit;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionBtn(
            icon: LucideIcons.undo2,
            label: 'Geri al',
            onTap: undoDisabled ? null : _undo,
            variant: _ActionVariant.outlined,
            small: true,
          ),
          _ActionBtn(
            icon: LucideIcons.x,
            label: 'Geç',
            onTap: disabled ? null : () => _swipe(liked: false),
            variant: _ActionVariant.outlined,
          ),
          _ActionBtn(
            icon: LucideIcons.heart,
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
  // ignore: unused_element_parameter
  final String Function(String) prettyCategory;
  final Map<String, dynamic>? designer;

  // ignore: unused_element
  IconData _roomIcon(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'living_room':
        return LucideIcons.sofa;
      case 'bedroom':
        return LucideIcons.bed;
      case 'kitchen':
        return LucideIcons.squareStack;
      case 'bathroom':
        return LucideIcons.bath;
      case 'kids_room':
        return LucideIcons.baby;
      case 'office':
        return LucideIcons.briefcase;
      case 'dining_room':
        return LucideIcons.utensils;
      case 'hallway':
        return LucideIcons.doorOpen;
      default:
        return LucideIcons.home;
    }
  }

  // ignore: unused_element
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

  // ignore: unused_element
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
                child: Icon(LucideIcons.imageOff,
                    color: KoalaColors.textTer),
              ),
            )
          else
            const Center(
              child: Icon(LucideIcons.image,
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

          // Kart üstü: oda pill + başlık + tagline kaldırıldı (Sor'a basınca
          // chat preview'da info olarak gösteriliyor). Sadece tasarımcı chip'i
          // ve palet alt tarafta kalıyor — kim yapmış görsel olarak anlaşılsın.
          if (designer != null || palette.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (designer != null) _DesignerChip(designer: designer!),
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
// ignore: unused_element
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
    this.small = false,
  });
  final IconData icon;
  final String label;
  final _ActionVariant variant;
  final VoidCallback? onTap;
  final bool large;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final size = large ? 68.0 : (small ? 44.0 : 56.0);
    final iconSize = large ? 28.0 : (small ? 18.0 : 22.0);

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
        // "Sor" aksiyonu — primary kadar öne çıkmasın ama sönük de durmasın.
        // Hafif accent dolgu + soft accent border + mor sızıntı gölgesi.
        bg = KoalaColors.accentSoft;
        fg = KoalaColors.accentDeep;
        border = KoalaColors.accentDeep.withValues(alpha: 0.18);
        shadow = [
          BoxShadow(
            color: KoalaColors.accentDeep.withValues(alpha: 0.14),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ];
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

// Kategori seçim chip'i — pill shape, ikonsuz, sade.
// Aktif durumda accentDeep arka plan + beyaz label; pasifte surfaceAlt + border.
class _CategoryChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _CategoryChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? KoalaColors.accentDeep : KoalaColors.surfaceAlt,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: active ? KoalaColors.accentDeep : KoalaColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : KoalaColors.textMed,
          ),
        ),
      ),
    );
  }
}
