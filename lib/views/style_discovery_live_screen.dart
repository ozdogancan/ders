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
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../core/theme/koala_tokens.dart';
import '../helpers/paywall_router.dart';
import '../providers/pro_status_provider.dart';
import '../widgets/koala_bottom_nav.dart';
import '../widgets/taste_summary_sheet.dart';
import 'main_shell.dart';
import 'mekan/mekan_flow_screen.dart';
import 'mekan/wizard/mekan_wizard_screen.dart';
import 'chat_list_screen.dart';
import 'projeler_screen.dart';
import '../services/evlumba_live_service.dart';
import '../services/messaging_service.dart';
import '../services/saved_items_service.dart';
import '../services/analytics_service.dart';
import '../services/taste_profile_service.dart';
import '../services/usage_limit_service.dart';

class StyleDiscoveryLiveScreen extends ConsumerStatefulWidget {
  const StyleDiscoveryLiveScreen({super.key});

  @override
  ConsumerState<StyleDiscoveryLiveScreen> createState() =>
      _StyleDiscoveryLiveScreenState();
}

// Cold-start başına bir kez gösterilecek realize tutorial flag'i.
// In-memory — app process restart edilince doğal olarak false'a döner.
bool _realizeHintShownInSession = false;

class _StyleDiscoveryLiveScreenState
    extends ConsumerState<StyleDiscoveryLiveScreen>
    with TickerProviderStateMixin {
  static const int _batchSize = 10;
  static const int _prefetchThreshold = 3; // kalan kart sayısı < bu → fetch

  // Kategori filtresi — opsiyonel. null / boş = Hepsi.
  // Persist key: SharedPreferences üzerinden session'lar arası korunur.
  static const String _prefsCategoryKey = 'style_discovery_category';
  // Warm-disk cache: önceki oturumun ilk batch'i — anlık deck için.
  // Refresh sonrası boş kart yerine cache'den hızlıca çiziliyor, fresh fetch
  // arka planda gelince swap ediliyor.
  static const String _prefsDeckCacheKey = 'style_discovery_deck_cache_v1';
  static const int _deckCacheMax = 12;
  // Sıra burada UI'da kullanılan sıra — bottom sheet chip sırası.
  // Key = DB'deki project_type değeri (Türkçe, ilike ile eşleştirilir).
  // Sadece canlı verilerde gerçekten proje olan kategoriler listelenir.
  static const List<({String key, String label, IconData icon})>
      _categoryOptions = [
    (key: '', label: 'Hepsi', icon: LucideIcons.layoutGrid),
    (key: 'Oturma Odası', label: 'Oturma Odası', icon: LucideIcons.sofa),
    (key: 'Yatak Odası', label: 'Yatak Odası', icon: LucideIcons.bed),
    (key: 'Mutfak', label: 'Mutfak', icon: LucideIcons.chefHat),
    (key: 'Banyo', label: 'Banyo', icon: LucideIcons.bath),
    (key: 'Antre', label: 'Antre', icon: LucideIcons.doorOpen),
  ];
  String? _selectedCategory; // null = Hepsi
  // Tasarım kaynağı filtresi — 'all' (hepsi), 'evlumba' (yalnız Evlumba Design),
  // 'real' (yalnız tasarımcı projeleri). Filtre ikonundan ayarlanır.
  String _sourceFilter = 'all';

  // Onboarding gesture demo — idle bekleyince çalışır; kullanıcı dokunursa
  // iptal edilir. Session başına bir kez tetiklenir.
  late AnimationController _demoCtrl;
  bool _demoRunning = false;
  bool _demoShownInSession = false;
  Timer? _demoIdleTimer;
  static const Duration _demoIdleWait = Duration(seconds: 5);

  // Kategori bazlı deck önbelleği — sekme değişiminde tekrar fetch yapma.
  final Map<String, _CatSnapshot> _catCache = {};

  final List<Map<String, dynamic>> _deck = [];
  final Set<String> _seenIds = <String>{};
  // Tap hint kaldırıldı — direktif gereği hiçbir tutorial gösterilmiyor.
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

  // Evlumba Design seeded tasarımları (koala_cards, source='gemini-seed').
  // Evlumba designer_projects feed'ine harmanlanır.
  final List<Map<String, dynamic>> _seedPool = [];
  bool _seedLoaded = false;

  double _dragDx = 0;
  double _dragDy = 0;
  bool _animatingExit = false;

  // Pro upsell card cadence: free user her 6 swipe'tan sonra (yani 7., 13.,
  // 19. slotta) Pro upgrade kartı görür. Pro user'da hiç gösterilmez.
  int _swipeCount = 0;
  // Her 10 beğenide tarz özeti popup'ı — session bazlı beğeni sayacı.
  int _likeCount = 0;
  static const int _proSlotEvery = 6;
  bool get _isProSlot => _isFreeUser && _swipeCount > 0 &&
      _swipeCount % _proSlotEvery == 0;
  bool _isFreeUser = true;
  // Günlük swipe kotası UsageLimitService üzerinden takip ediliyor (10/gün).
  // Free + quota tükendiğinde deck'in NEXT kartı _ProQuotaCard ile değiştirilir
  // ve swipe gesture'ları absorbe edilir. Pro'da hep false.
  bool _quotaExhausted = false;

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
    _demoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )
      ..addListener(_onDemoTick)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          if (!mounted) return;
          setState(() {
            _demoRunning = false;
            _dragDx = 0;
            _dragDy = 0;
          });
        }
      });
    // RAM warm cache: boot-time'da disk'ten yüklenen deck'i veya önceki
    // ekran ziyaretinden kalan listeyi anında göster — ilk frame'de kart.
    final ramWarm = EvlumbaLiveService.prefetchedDeck;
    if (ramWarm != null && ramWarm.isNotEmpty) {
      for (final p in ramWarm) {
        final id = p['id']?.toString() ?? '';
        if (id.isEmpty || _seenIds.contains(id)) continue;
        if (_coverOf(p).isEmpty) continue;
        _seenIds.add(id);
        _deck.add(p);
      }
      if (_deck.isNotEmpty) _loading = false;
    }
    _loadSavedCategory().then((_) => _bootstrap());
    unawaited(_refreshQuota());
    Analytics.screenViewed('style_discovery_live');
    // Tab her aktive olduğunda "Hepsi"ye reset et + tutorial kontrolü.
    MainShell.activeTab.addListener(_onTabActivate);
    // Swipe onboarding tutorial geçici olarak devre dışı — yeni bir onboarding
    // tasarımı planlanıyor.
  }

  Future<void> _maybeShowRealizeHint() async {
    if (!mounted || _realizeHintShownInSession) return;
    _realizeHintShownInSession = true;
    await _showRealizeHint(context);
  }

  Future<void> _loadSavedCategory() async {
    _selectedCategory = null;
    // Tutorial gif kaldırıldı — kullanıcı kart tap'ini kendi keşfedecek.
  }

  Future<void> _refreshQuota() async {
    try {
      final can = await UsageLimitService.canSwipe();
      if (!mounted) return;
      final next = !can;
      if (next != _quotaExhausted) {
        setState(() => _quotaExhausted = next);
      }
    } catch (_) {/* sessiz — UI hint */}
  }

  /// İlk-tap teaching: tasarımı kendi mekanına uygulayabileceğini öğret.
  /// Cold-start başına bir kez — _realizeHintShownInSession in-memory flag'i
  /// app process'i yeniden başlayınca sıfırlanır.
  Future<void> _showRealizeHint(BuildContext context) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'realize-hint',
      barrierColor: Colors.black.withValues(alpha: 0.32),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, __) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, __) {
        final t = Curves.easeOutCubic.transform(anim.value);
        return BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Opacity(
            opacity: anim.value,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 24),
                child: const SafeArea(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: _SwipeIntroCarousel(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _onCardTap(Map<String, dynamic> project) async {
    HapticFeedback.selectionClick();
    final url = _coverOf(project);
    if (url.isEmpty) return;
    // Tutorial hint artık ekran açılışında gösteriliyor (_maybeShowRealizeHint),
    // tap'te tekrar tetiklenmiyor.
    // Pro paywall gate — restyle is Pro-only. Block at the BUTTON onTap so
    // free users never enter the picker / MekanFlow / waiting screen.
    final pro = ref.read(proStatusProvider).value?.isPro ?? false;
    if (!pro) {
      await showPaywall(context, trigger: 'realize_to_my_room');
      return;
    }
    if (!mounted) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SwipePhotoSheet(),
    );
    if (source == null || !mounted) return;
    try {
      final picker = ImagePicker();
      final f = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        imageQuality: 60,
      );
      if (f == null || !mounted) return;
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      // Swipe akışı — wizard'ı ATLA, direkt MekanFlowScreen'e git.
      // Synthetic wizard sonucu üret: oda otomatik tespit edilecek, theme
      // referenceMatch (gerçek prompt backend'de buildVariants(refMode=true)).
      final synthWizard = MekanWizardResult(
        roomKey: '',
        roomTr: 'Mekanım',
        styleValue: 'reference',
        styleTr: 'Bu Tasarım',
        styleCustomPrompt: null,
        paletteKey: 'reference',
        paletteTr: 'Referans',
        paletteColors: const [],
        layout: LayoutMode.preserve,
      );
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MekanFlowScreen(
            initialBytes: bytes,
            wizard: synthWizard,
            targetDesignUrl: url,
            targetDesignerId:
                (project['designer_id'] ?? '').toString(),
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> _bootstrap() async {
    // 1) Disk cache'den anında deck'i göster — refresh sonrası boş kart yok.
    await _warmFromDiskCache();
    // 1b) Evlumba Design seeded tasarım havuzunu yükle (Koala DB).
    await _loadSeedPool();
    // 2) Backend ready'ye paralelden bekle, fresh fetch ile cache'i yenile.
    final ready = await EvlumbaLiveService.waitForReady(
        timeout: const Duration(seconds: 6));
    if (!ready) {
      debugPrint('StyleDiscoveryLive: EvlumbaLiveService NOT ready');
      // Evlumba erişilemese de seeded tasarımları göster.
      final seedBatch = <Map<String, dynamic>>[];
      _blendSeedCards(seedBatch);
      if (mounted) {
        setState(() {
          if (seedBatch.isNotEmpty) _deck.addAll(seedBatch);
          _loading = false;
        });
      }
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
      _persistDeckCache();
      _scheduleDemoIdleTimer();
    } catch (e) {
      debugPrint('StyleDiscoveryLive: bootstrap failed → $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Önceki oturumun ilk birkaç kartını disk cache'inden anında deck'e ekler.
  /// Backend fetch'i tamamlanmadan kullanıcı kart görür → algılanan latency
  /// 0'a yakın.
  Future<void> _warmFromDiskCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsDeckCacheKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) return;
      // Cache, _selectedCategory'den bağımsız yazılıyor. Aktif bir filtre
      // varken cache'i olduğu gibi göstermek "chip çalışmıyor" hissi verir.
      // Cache item'larını mevcut filtreye göre client-side süzeriz.
      final cat = _selectedCategory?.trim().toLowerCase();
      final filtered = <Map<String, dynamic>>[];
      for (final p in list) {
        final id = p['id']?.toString() ?? '';
        if (id.isEmpty || _seenIds.contains(id)) continue;
        if (_coverOf(p).isEmpty) continue;
        if (cat != null && cat.isNotEmpty) {
          final pt = (p['project_type'] ?? '').toString().trim().toLowerCase();
          if (pt != cat) continue;
        }
        _seenIds.add(id);
        filtered.add(p);
      }
      if (filtered.isEmpty || !mounted) return;
      setState(() {
        _deck.addAll(filtered);
        _loading = false;
      });
      _precacheNext();
    } catch (_) {}
  }

  Future<void> _persistDeckCache() async {
    try {
      // İlk N kartı kaydet — küçük, hızlı.
      final snap = _deck.take(_deckCacheMax).toList();
      if (snap.isEmpty) return;
      // RAM warm cache'i de güncelle — re-mount sırasında kullanılır.
      EvlumbaLiveService.prefetchedDeck = snap;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsDeckCacheKey, jsonEncode(snap));
    } catch (_) {}
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
      // Kaynak filtresi 'evlumba' iken Evlumba projelerini hiç çekme —
      // sadece seeded havuzdan harmanla.
      final List<Map<String, dynamic>> batch;
      if (_sourceFilter == 'evlumba') {
        batch = <Map<String, dynamic>>[];
      } else {
        batch = await EvlumbaLiveService.getProjects(
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
        batch.shuffle(_rng);
      }
      // Dedup + görsel filtrele
      final filtered = <Map<String, dynamic>>[];
      for (final p in batch) {
        final id = p['id']?.toString() ?? '';
        if (id.isEmpty || _seenIds.contains(id)) continue;
        if (_coverOf(p).isEmpty) continue;
        _seenIds.add(id);
        filtered.add(p);
      }
      // Evlumba Design seeded kartlarını batch'e harmanla (kaynak filtresi
      // 'real' değilse).
      _blendSeedCards(filtered);
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

  // koala_cards room_type -> designer_projects project_type (TR etiket).
  static const Map<String, String> _seedRoomTr = {
    'salon': 'Salon', 'yatak_odasi': 'Yatak Odası', 'mutfak': 'Mutfak',
    'banyo': 'Banyo', 'cocuk_odasi': 'Çocuk Odası', 'ofis': 'Çalışma Odası',
    'antre': 'Antre', 'balkon': 'Balkon',
  };

  /// koala_cards satırını swipe kartı şekline çevirir.
  Map<String, dynamic> _mapSeedCard(Map<String, dynamic> r) {
    final rt = (r['room_type'] ?? '').toString();
    return {
      'id': r['id'],
      'designer_id': 'evlumba-design',
      'title': (r['title'] ?? '').toString(),
      'description': (r['description'] ?? '').toString(),
      'project_type': _seedRoomTr[rt] ?? rt,
      'cover_image_url': (r['cdn_url'] ?? r['original_url'] ?? '').toString(),
      'created_at': r['created_at'],
      'tags': const <String>[],
      'color_palette': const <String>[],
      '_seed': true,
    };
  }

  /// Seeded tasarım havuzunu Koala DB'den bir kez yükler.
  Future<void> _loadSeedPool() async {
    if (_seedLoaded) return;
    _seedLoaded = true;
    try {
      final data = await Supabase.instance.client
          .from('koala_cards')
          .select('id, title, description, room_type, style, cdn_url, '
              'original_url, created_at')
          .eq('source', 'gemini-seed')
          .eq('is_published', true)
          .limit(300);
      _seedPool
        ..clear()
        ..addAll(List<Map<String, dynamic>>.from(data).map(_mapSeedCard));
      debugPrint('StyleDiscoveryLive: seed pool ${_seedPool.length}');
    } catch (e) {
      debugPrint('StyleDiscoveryLive: seed pool load failed → $e');
    }
  }

  /// Havuzdan, kategoriye uyan ve henüz eklenmemiş seeded kartları
  /// batch'e harmanlar (en çok 5 / batch).
  void _blendSeedCards(List<Map<String, dynamic>> batch) {
    if (_seedPool.isEmpty) return;
    // Kaynak filtresi 'real' iken seeded kartları gizle.
    if (_sourceFilter == 'real') return;
    final cat = _selectedCategory?.trim().toLowerCase();
    var added = 0;
    for (final s in _seedPool) {
      if (added >= 5) break;
      final id = s['id']?.toString() ?? '';
      if (id.isEmpty || _seenIds.contains(id)) continue;
      if (cat != null &&
          cat.isNotEmpty &&
          (s['project_type'] ?? '').toString().toLowerCase() != cat) {
        continue;
      }
      _seenIds.add(id);
      batch.add(s);
      added++;
    }
    if (added > 0) batch.shuffle(_rng);
  }

  void _precacheNext() {
    // 3 kart ileriyi ısıt — deck'te current + next zaten mount; ekstra bir
    // kart daha cache'te hazır olunca hızlı kaydırmada bile boş kart olmaz.
    for (int i = _index + 1; i < math.min(_index + 4, _deck.length); i++) {
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
    if (_demoRunning) _cancelDemo();
    _demoIdleTimer?.cancel();
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
    // ── Pro upsell slot? ──
    // Free user her 6 swipe'tan sonra normal kart yerine Pro upgrade kartı
    // görüyor. Burada özel davranış: like → paywall, skip → next.
    if (_isProSlot) {
      HapticFeedback.selectionClick();
      if (liked) {
        unawaited(Analytics.log('upsell_swipe_card_clicked', const {}));
        await showPaywall(context, trigger: 'swipe_premium_styles');
      } else {
        unawaited(Analytics.log('upsell_swipe_card_skipped', const {}));
      }
      // Slot'u tüket — _swipeCount'u bump et, render normal karta dönsün.
      if (mounted) setState(() => _swipeCount++);
      return;
    }
    final card = _currentCard;
    if (card == null) return;
    // Swipe başlar başlamaz sıradaki kartların görsellerini ısıt — çıkış
    // animasyonu (280ms) bitip yeni kart öne geçmeden cache'e girsinler.
    // Önceden yalnızca _onExitComplete'te (animasyon bitince) çağrılıyordu.
    _precacheNext();
    // Undo için snapshot al — exit animasyonu bitince _index++ oluyor.
    _history.add({
      'index': _index,
      'liked': liked,
      'id': card['id']?.toString() ?? '',
    });
    // Her gerçek swipe sayılır — Pro slot cadence'ı için.
    _swipeCount++;
    // Günlük kota sayacı — sessizce arttır, paywall popup AÇMA. Deck-level
    // quota kartı (gating) görsel sınır olarak iş görüyor.
    unawaited(UsageLimitService.incrementSwipe().then((_) => _refreshQuota()));
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
      // Her 10 beğenide tarz özeti popup'ı (lokal veri — AI çağrısı yok).
      _likeCount++;
      if (_likeCount % 10 == 0) {
        unawaited(_showTasteSummary());
      }
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

  /// Her 10 beğenide gösterilen tarz özeti popup'ı. Tüm veri lokal
  /// (TasteProfileService) + bellekteki deck — AI çağrısı / maliyet yok.
  Future<void> _showTasteSummary() async {
    await Future<void>.delayed(const Duration(milliseconds: 460));
    if (!mounted) return;
    final profile = await TasteProfileService.computeProfile();
    if (!mounted || !profile.isActive || profile.topStyles.isEmpty) return;

    final topStyle = profile.topStyles.first.style;

    // Önerilen tasarım: deck'te ilerideki, baskın stile uyan ilk kart.
    Map<String, dynamic>? rec;
    for (int i = _index + 1; i < _deck.length && i < _index + 30; i++) {
      if (TasteProfileService.stylesOf(_deck[i]).contains(topStyle)) {
        rec = _deck[i];
        break;
      }
    }
    rec ??= _nextCard;

    Map<String, String>? recCard;
    if (rec != null) {
      recCard = {
        'id': rec['id']?.toString() ?? '',
        'title': (rec['title'] ?? '').toString().trim(),
        'imageUrl': _coverOf(rec),
        'designerId': (rec['designer_id'] ?? '').toString(),
        'category': _prettyCategory((rec['project_type'] ?? '').toString()),
      };
    }

    if (!mounted) return;
    HapticFeedback.selectionClick();
    await TasteSummarySheet.show(
      context,
      profile: profile,
      topStyleKey: topStyle,
      palette: TasteSummarySheet.paletteFor(topStyle),
      recCard: recCard,
    );
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
    final projectTitle = (card['title'] ?? '').toString().trim();
    final rawDesc = (card['description'] ?? '').toString().trim();
    final tagline = _quickFirstSentence(rawDesc);
    final d = _designerCache[designerId];
    final designerName =
        ((d?['full_name'] ?? d?['business_name'] ?? '') as String).trim();
    final designerAvatar = ((d?['avatar_url'] ?? '') as String).trim();
    final displayTitle = projectTitle.isNotEmpty
        ? projectTitle
        : (cat.isNotEmpty ? '$cat projesi' : 'Tasarım');

    // pendingDesign — seçilen hedefe göre tasarımı chat'e iliştirir.
    Map<String, dynamic> pendingDesign(String forDesignerId) => {
          'id': projectId,
          'title': displayTitle,
          if (tagline.isNotEmpty) 'tagline': tagline,
          if (cat.isNotEmpty) 'category': cat,
          'imageUrl': coverUrl,
          'designerId': forDesignerId,
        };

    // "Sor" → alt-popup. Koala AI / Evlumba Design stüdyosu / tasarımın
    // sahibi. Seeded (designer_id='evlumba-design') kartlarda sahip zaten
    // Evlumba Design olduğu için 3. seçenek gizlenir → 2 seçenek kalır.
    final isEvlumbaDesign = designerId == 'evlumba-design';
    Widget askOption({
      required Widget leading,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Material(
          color: KoalaColors.surface,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
              child: Row(
                children: [
                  SizedBox(width: 48, height: 48, child: leading),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: KoalaText.h4),
                        const SizedBox(height: 2),
                        Text(subtitle, style: KoalaText.bodySmall),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: KoalaColors.textMuted, size: 20),
                ],
              ),
            ),
          ),
        ),
      );
    }

    _askingInFlight = true;
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: KoalaColors.bg,
      barrierColor: Colors.black54,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
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
              const SizedBox(height: 14),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Text('Kime soralım?', style: KoalaText.h2),
              ),
              const SizedBox(height: 6),
              askOption(
                leading: const _AskLeading(
                  icon: Icons.auto_awesome_rounded,
                  gradient: true,
                ),
                title: "Koala AI'ya sor",
                subtitle: 'Yapay zekâ asistanından anında fikir al',
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.push('/chat/ai', extra: {
                    'initialText': 'Bu tasarımı beğendim: "$displayTitle"'
                        '${cat.isNotEmpty ? ' ($cat)' : ''}. '
                        'Bunun gibi bir tarzı evime nasıl uygulayabilirim?',
                  });
                },
              ),
              askOption(
                leading: const _AskLeading(
                  imageUrl: _evlumbaDesignAvatarUrl,
                  icon: Icons.home_work_rounded,
                ),
                title: "Evlumba Design'a sor",
                subtitle: 'Evlumba stüdyosundan profesyonel destek al',
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.push('/chat/dm/new', extra: {
                    'designerId': 'evlumba-design',
                    'designerName': 'Evlumba Design',
                    'projectTitle': displayTitle,
                    'pendingDesign': pendingDesign('evlumba-design'),
                  });
                },
              ),
              if (!isEvlumbaDesign)
                askOption(
                  leading: _AskLeading(
                    imageUrl:
                        designerAvatar.isNotEmpty ? designerAvatar : null,
                    icon: Icons.person_rounded,
                  ),
                  title: 'Tasarımcısına sor',
                  subtitle: designerName.isNotEmpty
                      ? '$designerName ile doğrudan konuş'
                      : 'Bu tasarımı yapan tasarımcıyla konuş',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    context.push('/chat/dm/new', extra: {
                      'designerId': designerId,
                      if (designerName.isNotEmpty)
                        'designerName': designerName,
                      if (designerAvatar.isNotEmpty)
                        'designerAvatarUrl': designerAvatar,
                      'projectTitle': displayTitle,
                      'pendingDesign': pendingDesign(designerId),
                    });
                  },
                ),
            ],
          ),
        ),
      ),
    );
    if (mounted) _askingInFlight = false;
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
    // Evlumba Design seeded kartları için sentetik tasarımcı — Evlumba
    // marketplace DB'sinde böyle bir profil yok; UI badge + avatar için
    // sabit bir kayıt kullanıyoruz.
    if (designerId == 'evlumba-design') {
      const synthetic = <String, dynamic>{
        'id': 'evlumba-design',
        'full_name': 'Evlumba Design',
        'business_name': 'Evlumba Design',
        'profession': 'İç Mimari Stüdyosu',
        'avatar_url':
            'https://xgefjepaqnghaotqybpi.supabase.co/storage/v1/object/public/koala-seed/avatars/evlumba-design.webp',
      };
      if (mounted) setState(() => _designerCache[designerId] = synthetic);
      return;
    }
    if (_designerInFlight.contains(designerId)) return;
    _designerInFlight.add(designerId);
    final d = await EvlumbaLiveService.getDesigner(designerId);
    _designerInFlight.remove(designerId);
    if (!mounted || d == null) return;
    setState(() => _designerCache[designerId] = d);
  }

  /// AppBar ayarlar ikonundan açılır — Ayarlar ekranı.
  void _openSettings() {
    HapticFeedback.selectionClick();
    context.push('/profile');
  }

  /// Karta dokunulduğunda açılan tasarımcı profil sheet'i. Mekana uygula
  /// aksiyonu artık altın pillte; tap = profil.
  Future<void> _openDesignerSheet(Map<String, dynamic> card) async {
    HapticFeedback.selectionClick();
    final designerId = (card['designer_id'] ?? '').toString();
    if (designerId.isEmpty) return;
    await _loadDesigner(designerId);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: KoalaColors.bg,
      barrierColor: Colors.black54,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => DesignerProfileSheet(
        designerId: designerId,
        designer: _designerCache[designerId],
        seedPool:
            designerId == 'evlumba-design' ? List.of(_seedPool) : null,
        onAsk: () {
          Navigator.pop(ctx);
          _onAskDesigner();
        },
      ),
    );
  }

  /// Onboarding gesture demo — lifetime'da bir kez. Önce kart Evlumba Design
  /// seeded, sağa hafifçe salınır, sola hafifçe salınır, kart commit
  /// edilmez. Kullanıcı kartların yön semantiğini öğrenir.
  void _onDemoTick() {
    if (!mounted) return;
    final t = _demoCtrl.value;
    const peak = 90.0;
    double dx;
    if (t < 0.25) {
      // 0 → +peak (sağa kay)
      dx = peak * Curves.easeOutCubic.transform(t / 0.25);
    } else if (t < 0.5) {
      // +peak → 0 (geri dön)
      dx = peak * (1 - Curves.easeInCubic.transform((t - 0.25) / 0.25));
    } else if (t < 0.75) {
      // 0 → -peak (sola kay)
      dx = -peak * Curves.easeOutCubic.transform((t - 0.5) / 0.25);
    } else {
      // -peak → 0 (geri dön)
      dx = -peak * (1 - Curves.easeInCubic.transform((t - 0.75) / 0.25));
    }
    setState(() => _dragDx = dx);
  }

  /// Deck hazır olduğunda 5 saniye idle bekler, ardından `_maybeShowDemo()`
  /// çalışır. Kullanıcı bu süre içinde herhangi bir gestürü yaparsa timer
  /// (ve demo) iptal edilir.
  void _scheduleDemoIdleTimer() {
    if (_demoShownInSession || _demoRunning) return;
    _demoIdleTimer?.cancel();
    _demoIdleTimer = Timer(_demoIdleWait, () {
      if (!mounted) return;
      if (_demoShownInSession || _demoRunning) return;
      // Kullanıcı home tab'ında ve etkileşimsiz değilse sustur.
      if (MainShell.activeTab.value != KoalaTab.home) return;
      unawaited(_maybeShowDemo());
    });
  }

  void _cancelDemo() {
    if (!_demoRunning) return;
    _demoCtrl.stop();
    _demoShownInSession = true;
    if (mounted) {
      setState(() {
        _demoRunning = false;
        _dragDx = 0;
        _dragDy = 0;
      });
    }
  }

  Future<void> _maybeShowDemo() async {
    if (_demoShownInSession || _demoRunning) return;
    if (!mounted || _deck.isEmpty) return;
    try {
      // Evlumba Design seeded kartı deck[0]'a taşı / ekle — ilk kart o olsun.
      Map<String, dynamic>? evCard;
      int existingIdx = -1;
      for (int i = 0; i < _deck.length; i++) {
        if ((_deck[i]['designer_id'] ?? '') == 'evlumba-design') {
          evCard = _deck[i];
          existingIdx = i;
          break;
        }
      }
      if (evCard == null) {
        for (final s in _seedPool) {
          final id = s['id']?.toString() ?? '';
          if (id.isEmpty || _seenIds.contains(id)) continue;
          _seenIds.add(id);
          evCard = s;
          break;
        }
        if (evCard == null) return;
        if (mounted) setState(() => _deck.insert(0, evCard!));
      } else if (existingIdx > 0) {
        if (mounted) {
          setState(() {
            _deck.removeAt(existingIdx);
            _deck.insert(0, evCard!);
          });
        }
      }
      // Bir frame bekle ki kart ekranda render olsun.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      // Tekrar kontrol — kullanıcı bu arada dokunmuş olabilir.
      if (_demoShownInSession || _demoRunning) return;
      setState(() => _demoRunning = true);
      HapticFeedback.lightImpact();
      await _demoCtrl.forward(from: 0);
      _demoShownInSession = true;
    } catch (e) {
      debugPrint('demo show failed: $e');
    }
  }

  @override
  void dispose() {
    MainShell.activeTab.removeListener(_onTabActivate);
    _exitCtrl.dispose();
    _demoCtrl.dispose();
    super.dispose();
  }

  void _onTabActivate() {
    if (MainShell.activeTab.value != KoalaTab.home) return;
    if (_selectedCategory != null) _applyCategory('');
  }

  @override
  Widget build(BuildContext context) {
    final asyncPro = ref.watch(proStatusProvider);
    _isFreeUser = !asyncPro.maybeWhen(
        data: (s) => s.isPro, orElse: () => false);
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      extendBody: true,
      // bottomNavigationBar MainShell tarafından sağlanıyor.
      // Mesajlar ekranı ile birebir aynı AppBar — leading/title hizası app genelinde tutarlı.
      appBar: AppBar(
        backgroundColor: KoalaColors.bg,
        surfaceTintColor: KoalaColors.bg,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        toolbarHeight: 88,
        title: const _BrandLockup(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _SettingsButton(
              isPro: ref.watch(proStatusProvider).value?.isPro ?? false,
              onTap: _openSettings,
            ),
          ),
        ],
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
                            // extendBody:true — aksiyon butonları sistem
                            // gesture bar'ının arkasında kalmasın.
                            SizedBox(
                                height: 20 +
                                    MediaQuery.of(context)
                                        .viewPadding
                                        .bottom),
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
                        label: e.label,
                        icon: e.icon,
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
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        itemCount: _categoryOptions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final e = _categoryOptions[i];
          final active = (_selectedCategory ?? '') == e.key;
          return _CategoryChip(
            label: e.label,
            icon: e.icon,
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

    // Mevcut kategorinin durumunu önbelleğe al — kullanıcı geri dönerse tekrar
    // fetch yapılmasın.
    final currentKey = current ?? '';
    _catCache[currentKey] = _CatSnapshot(
      deck: List.of(_deck),
      seenIds: Set.of(_seenIds),
      history: List.of(_history),
      index: _index,
      offset: _offset,
      totalCount: _totalCount,
    );

    // Hedef kategori önbellekte varsa anında geri yükle, fetch yapma.
    final nextKey = next ?? '';
    final cached = _catCache[nextKey];
    if (cached != null && cached.deck.isNotEmpty) {
      setState(() {
        _selectedCategory = next;
        _deck
          ..clear()
          ..addAll(cached.deck);
        _seenIds
          ..clear()
          ..addAll(cached.seenIds);
        _history
          ..clear()
          ..addAll(cached.history);
        _index = cached.index;
        _offset = cached.offset;
        _totalCount = cached.totalCount;
        _dragDx = 0;
        _dragDy = 0;
        _loading = false;
      });
      _precacheNext();
      return;
    }

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
    // Günlük kota tükendiyse (free user) — deck'in mevcut kartı yerine
    // _ProQuotaCard göster. Swipe/drag gesture'larını absorbe et.
    if (_isFreeUser && _quotaExhausted) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: GestureDetector(
          // Pan/drag absorbe — kart swipe edilemez.
          onPanUpdate: (_) {},
          onPanEnd: (_) {},
          onPanStart: (_) {},
          onTap: () {
            HapticFeedback.selectionClick();
            showPaywall(context, trigger: 'swipe_quota_end');
          },
          child: const _ProQuotaCard(),
        ),
      );
    }
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
                          onTap: _isProSlot
                              ? () {
                                  HapticFeedback.selectionClick();
                                  showPaywall(context,
                                      trigger: 'swipe_premium_styles');
                                }
                              : () => _openDesignerSheet(current),
                          child: Stack(
                            children: [
                              if (_isProSlot)
                                const _ProUpsellCard()
                              else
                              _Card(
                                project: current,
                                coverOf: _coverOf,
                                prettyCategory: _prettyCategory,
                                designer: _designerCache[
                                    (current['designer_id'] ?? '').toString()],
                                onApply: () => _onCardTap(current),
                              ),
                              // Tap hint kalıcı olarak kaldırıldı — kullanıcı
                              // direktifi: hiçbir tutorial/hint gösterilmesin.
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
    final disabled = _currentCard == null ||
        _animatingExit ||
        (_isFreeUser && _quotaExhausted);
    // Modern, uygulama aksentine bağlı, 3'lü denge: Pas — Beğen (primary) — Sor
    final askDisabled = disabled ||
        _isProSlot ||
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
    this.onApply,
  });
  final Map<String, dynamic> project;
  final String Function(Map<String, dynamic>) coverOf;
  // ignore: unused_element_parameter
  final String Function(String) prettyCategory;
  final Map<String, dynamic>? designer;
  final VoidCallback? onApply;

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
          if (designer != null || palette.isNotEmpty || onApply != null)
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
                    if (onApply != null) ...[
                      Align(
                        alignment: Alignment.center,
                        child: _ApplyPill(onTap: onApply!),
                      ),
                      const SizedBox(height: 16),
                    ],
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
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _CategoryChip({
    required this.label,
    required this.icon,
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
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? KoalaColors.accentDeep : KoalaColors.surface,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color:
                active ? KoalaColors.accentDeep : KoalaColors.border,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: active ? Colors.white : KoalaColors.textSec,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : KoalaColors.text,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// _TapHintOverlay kaldırıldı — direktif gereği hiçbir tutorial gösterilmiyor.

/// Pro upsell kartı — swipe deck'inde her 6 swipe'tan sonra free user'a
/// gösterilir. Skip → pas, Like → paywall. Aynı boyut/radius normal kartla.
class _ProUpsellCard extends StatelessWidget {
  const _ProUpsellCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1A1325),
            KoalaColors.text,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Subtle gold radial highlight
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.4),
                radius: 0.85,
                colors: [
                  const Color(0xFFB8862F).withValues(alpha: 0.20),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 36, 28, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Mini PRO badge
                Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE0B96B), Color(0xFFB8862F)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.crown,
                          size: 12, color: Colors.white),
                      SizedBox(width: 5),
                      Text(
                        'PRO',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.8,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                const Text(
                  'Premium stilleri keşfet',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Bohem-Lüks, Vintage Atelier, Japandi-Pro,\nBrutal-Modern ve 9 özel stil daha.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.85),
                    height: 1.45,
                    letterSpacing: -0.1,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.crown,
                          size: 14, color: Color(0xFFB8862F)),
                      SizedBox(width: 8),
                      Text(
                        "Pro'ya Geç",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: KoalaColors.text,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Beğen → Pro\'ya geç · Geç → atla',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.55),
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Realize tutorial popup'ının üst görseli. İki fotoğrafın AI ile birleşip
/// tek bir mekan tasarımına dönüştüğünü gösterir: sol = beğendiğin tasarım,
/// sağ = senin mekanın, ortada "+" → tek sonuç.
///
/// Swipe ekranı tanıtım carousel'i — sağa kaydırılabilir 3 sayfa:
/// 1) mekana uygula, 2) tarzını keşfet, 3) sor. Oturum başına bir kez.
class _IntroPage {
  const _IntroPage({this.image, required this.title, required this.body});

  /// null → kod-çizimli [_RealizeHintImage]; aksi halde asset yolu.
  final String? image;
  final String title;
  final String body;
}

class _SwipeIntroCarousel extends StatefulWidget {
  const _SwipeIntroCarousel();

  @override
  State<_SwipeIntroCarousel> createState() => _SwipeIntroCarouselState();
}

class _SwipeIntroCarouselState extends State<_SwipeIntroCarousel> {
  final PageController _pc = PageController();
  int _idx = 0;

  static const List<_IntroPage> _pages = [
    _IntroPage(
      title: 'Bunu kendi mekanında dene',
      body: 'Beğendiğin tasarımı seç, AI senin mekanının fotoğrafına '
          'uygular — saniyeler içinde.',
    ),
    _IntroPage(
      image: 'assets/images/intro_style.webp',
      title: 'Tarzını keşfet',
      body: 'Tasarımları kaydır; beğendiğin sağa gitsin. Koala zevkini '
          'öğrenip sana daha iyi öneriler sunar.',
    ),
    _IntroPage(
      image: 'assets/images/intro_ask.webp',
      title: 'Merak ettiğini sor',
      body: 'Beğendiğin tasarımın altındaki "Sor" ile tek dokunuşla '
          'uzmana danış, fikrini al.',
    ),
  ];

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _onButton() {
    if (_idx < _pages.length - 1) {
      _pc.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _idx == _pages.length - 1;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 300,
                child: PageView.builder(
                  controller: _pc,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _idx = i),
                  itemBuilder: (_, i) => _IntroPageView(page: _pages[i]),
                ),
              ),
              const SizedBox(height: 14),
              // Nokta göstergeleri.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) {
                  final on = i == _idx;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: on ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: on
                          ? const Color(0xFF6C63FF)
                          : const Color(0xFFD9D5EC),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),
              Material(
                color: const Color(0xFF6C63FF),
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: _onButton,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      isLast ? 'Başla' : 'İleri',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.1,
                      ),
                    ),
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

class _IntroPageView extends StatelessWidget {
  const _IntroPageView({required this.page});
  final _IntroPage page;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (page.image == null)
          const _RealizeHintImage()
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset(
              page.image!,
              height: 150,
              fit: BoxFit.cover,
            ),
          ),
        const SizedBox(height: 16),
        Text(
          page.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: KoalaColors.text,
            letterSpacing: -0.2,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          page.body,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: KoalaColors.textSec,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

/// Gemini ile profesyonel bir illüstrasyon üretmek istersen
/// `pro-assets/realize-tutorial.webp` path'ine upload et; bu bileşeni
/// Image.network ile değiştir.
class _RealizeHintImage extends StatelessWidget {
  const _RealizeHintImage();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 150,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF3F0FF), Color(0xFFFAF8FF)],
          ),
          border: Border.all(color: const Color(0xFFE0DAFF)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Sol kart: beğendiğin tasarım — küçük etiket "Tasarım"
            Positioned(
              left: 8,
              top: 8,
              bottom: 8,
              width: 130,
              child: Transform.rotate(
                angle: -0.06,
                child: _RealizeMiniCard(
                  asset: 'assets/showcase/after.webp',
                  label: 'Tasarım',
                ),
              ),
            ),
            // Sağ kart: senin mekanın
            Positioned(
              right: 8,
              top: 8,
              bottom: 8,
              width: 130,
              child: Transform.rotate(
                angle: 0.06,
                child: _RealizeMiniCard(
                  asset: 'assets/showcase/before.webp',
                  label: 'Mekanın',
                ),
              ),
            ),
            // Ortada "+" badge — iki kartın birleştiğini anlatır.
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6C63FF), Color(0xFF9B5CFF)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x336C63FF),
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 26),
            ),
          ],
        ),
      ),
    );
  }
}

class _RealizeMiniCard extends StatelessWidget {
  final String asset;
  final String label;
  const _RealizeMiniCard({required this.asset, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(asset, fit: BoxFit.cover),
            // Alt etiket
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.3,
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

/// Günlük swipe kotası bittiğinde swipe deck'i bu kartla "kilitler". Tap →
/// paywall. Pan/drag absorbe parent'ta yapılıyor; bu sadece görsel.
class _ProQuotaCard extends StatelessWidget {
  const _ProQuotaCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF6C63FF),
            Color(0xFF9B5CFF),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C63FF).withValues(alpha: 0.30),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Üst-merkez radial highlight — yumuşak parlama.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.7),
                radius: 0.9,
                colors: [
                  Colors.white.withValues(alpha: 0.22),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 36, 28, 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.workspace_premium,
                  size: 36,
                  color: Colors.white,
                ),
                const SizedBox(height: 18),
                const Text(
                  'Günlük Limit Doldu',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Pro ile sınırsız keşif, sınırsız ilham seni bekliyor.',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.85),
                    height: 1.45,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    "Pro'ya Geç",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF6C63FF),
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipePhotoSheet extends StatelessWidget {
  const _SwipePhotoSheet();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: KoalaColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: KoalaColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Mekanını yükle',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: KoalaColors.text,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'AI bu tasarımı senin mekanına uygulayacak.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: KoalaColors.textSec,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SwipeOpt(
                  icon: LucideIcons.camera,
                  label: 'Kamera',
                  onTap: () => Navigator.of(context).pop(ImageSource.camera),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SwipeOpt(
                  icon: LucideIcons.image,
                  label: 'Galeri',
                  onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SwipeOpt extends StatelessWidget {
  const _SwipeOpt({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: KoalaColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: KoalaColors.border, width: 0.6),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KoalaColors.accentSoft,
                ),
                child: Icon(icon, size: 22, color: KoalaColors.accentDeep),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: KoalaColors.text,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Brand lockup + Sor popup avatarları + Filtreler sheet
// ═══════════════════════════════════════════════════════════

const String _evlumbaDesignAvatarUrl =
    'https://xgefjepaqnghaotqybpi.supabase.co/storage/v1/object/public/koala-seed/avatars/evlumba-design.webp';

/// AppBar başlığı: "koala by evlumba" wordmark + slogan. Inter (theme).
class _BrandLockup extends StatelessWidget {
  const _BrandLockup();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: const [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'koala',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: KoalaColors.ink,
                letterSpacing: -1.2,
                height: 1.0,
              ),
            ),
            SizedBox(width: 5),
            Padding(
              padding: EdgeInsets.only(bottom: 2),
              child: Text(
                'by evlumba',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: KoalaColors.accentDeep,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 3),
        Text(
          'Evin için ilham ve hızlı tasarım.',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: KoalaColors.textTer,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }
}

/// Sor popup'ında her seçenek için 48x48 yuvarlak başlangıç.
/// `imageUrl` varsa CachedNetworkImage; yoksa gradient/soft daire + ikon.
class _AskLeading extends StatelessWidget {
  final String? imageUrl;
  final IconData? icon;
  final bool gradient;
  const _AskLeading({this.imageUrl, this.icon, this.gradient = false});

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: gradient && !hasImage
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [KoalaColors.accentDeep, KoalaColors.accent],
              )
            : null,
        color: hasImage
            ? null
            : (gradient ? null : KoalaColors.accentSoft),
        boxShadow: [
          BoxShadow(
            color: KoalaColors.accent.withValues(alpha: 0.16),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: hasImage ? Clip.antiAlias : Clip.none,
      child: hasImage
          ? CachedNetworkImage(
              imageUrl: imageUrl!,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(color: KoalaColors.accentSoft),
              errorWidget: (_, _, _) => Container(
                color: KoalaColors.accentSoft,
                child: Icon(
                  icon ?? Icons.person_rounded,
                  color: KoalaColors.accentDeep,
                  size: 22,
                ),
              ),
            )
          : Center(
              child: Icon(
                icon ?? Icons.help_outline_rounded,
                size: 22,
                color: gradient ? Colors.white : KoalaColors.accentDeep,
              ),
            ),
    );
  }
}

/// AppBar sağındaki ayarlar düğmesi.
/// Pro: sweep-gradient halka + beyaz iç daire + altın "PRO" pill rozeti.
/// Free: ince bordürlü beyaz daire + ayar ikonu.
class _SettingsButton extends StatelessWidget {
  final bool isPro;
  final VoidCallback onTap;
  const _SettingsButton({required this.isPro, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 50,
          height: 50,
          child: Center(
            child: isPro ? _proInner() : _freeInner(),
          ),
        ),
      ),
    );
  }

  Widget _proInner() {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // Dış sweep-gradient halka.
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const SweepGradient(
              colors: [
                KoalaColors.accentDeep,
                KoalaColors.brandLight,
                Color(0xFFFFC44C),
                KoalaColors.accent,
                KoalaColors.accentDeep,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: KoalaColors.accent.withValues(alpha: 0.32),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(2.2),
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            alignment: Alignment.center,
            child: const Icon(
              LucideIcons.settings,
              size: 18,
              color: KoalaColors.accentDeep,
            ),
          ),
        ),
        // Sağ alt: altın PRO pill.
        Positioned(
          bottom: -4,
          right: -8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFD66B), Color(0xFFEFA01F)],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: KoalaColors.bg, width: 1.4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: const Text(
              'PRO',
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.4,
                height: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _freeInner() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: KoalaColors.surface,
        border: Border.all(color: KoalaColors.borderSolid, width: 0.8),
      ),
      alignment: Alignment.center,
      child: const Icon(LucideIcons.settings,
          size: 19, color: KoalaColors.text),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Mekana uygula pill + Kategori snapshot + Designer profile sheet
// ═══════════════════════════════════════════════════════════

/// Karta yerleşen altın aksan CTA: "Mekanıma uygula" (AI restyle başlatır).
class _ApplyPill extends StatelessWidget {
  final VoidCallback onTap;
  const _ApplyPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFD66B), Color(0xFFEFA01F)],
            ),
            borderRadius: BorderRadius.circular(100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.32),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.wand, size: 16, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'Mekanıma uygula',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kategori değişiminde önbelleğe alınan deck durumu — geri dönünce tekrar
/// fetch yapılmasın.
class _CatSnapshot {
  final List<Map<String, dynamic>> deck;
  final Set<String> seenIds;
  final List<Map<String, dynamic>> history;
  final int index;
  final int offset;
  final int totalCount;
  const _CatSnapshot({
    required this.deck,
    required this.seenIds,
    required this.history,
    required this.index,
    required this.offset,
    required this.totalCount,
  });
}

/// Tasarımcı profil sheet'i — karta dokununca açılır. Bilgi + diğer
/// projeler grid + Sor aksiyonu.
class DesignerProfileSheet extends StatefulWidget {
  final String designerId;
  final Map<String, dynamic>? designer;
  final List<Map<String, dynamic>>? seedPool;
  final VoidCallback onAsk;

  const DesignerProfileSheet({
    super.key,
    required this.designerId,
    required this.designer,
    required this.onAsk,
    this.seedPool,
  });

  @override
  State<DesignerProfileSheet> createState() => _DesignerProfileSheetState();
}

class _DesignerProfileSheetState extends State<DesignerProfileSheet> {
  List<Map<String, dynamic>> _projects = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    try {
      List<Map<String, dynamic>> list;
      if (widget.designerId == 'evlumba-design') {
        list = List<Map<String, dynamic>>.from(widget.seedPool ?? const []);
      } else {
        list = await EvlumbaLiveService.getProjects(
          designerId: widget.designerId,
          limit: 30,
        );
      }
      if (mounted) {
        setState(() {
          _projects = list;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('profile sheet load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _coverOf(Map<String, dynamic> p) {
    for (final k in ['cover_image_url', 'cover_url', 'image_url']) {
      final v = (p[k] ?? '').toString().trim();
      if (v.isNotEmpty && !v.startsWith('data:')) return v;
    }
    final imgs = p['designer_project_images'] as List?;
    if (imgs != null && imgs.isNotEmpty) {
      final sorted = List<Map<String, dynamic>>.from(
        imgs.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
      )..sort((a, b) => ((a['sort_order'] as num?)?.toInt() ?? 9999)
          .compareTo((b['sort_order'] as num?)?.toInt() ?? 9999));
      return (sorted.first['image_url'] ?? '').toString();
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.designer;
    final name = ((d?['full_name'] ?? d?['business_name'] ?? '') as String)
        .trim();
    final profession = ((d?['profession'] ?? d?['specialty'] ?? '') as String)
        .trim();
    final city = ((d?['city'] ?? '') as String).trim();
    final avatar = ((d?['avatar_url'] ?? '') as String).trim();
    final bio = ((d?['bio'] ?? d?['about'] ?? '') as String).trim();
    final isEvlumba = widget.designerId == 'evlumba-design';

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: KoalaColors.border,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.zero,
                children: [
                  _hero(name, profession, city, avatar, isEvlumba),
                  _stats(),
                  _actions(),
                  if (bio.isNotEmpty) _aboutSection(bio),
                  _projectsHeader(),
                  _projectsGrid(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _hero(String name, String profession, String city, String avatar,
      bool isEvlumba) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            KoalaColors.accentSoft.withValues(alpha: 0.55),
            KoalaColors.bg,
          ],
        ),
      ),
      child: Column(
        children: [
          _avatar(avatar, isEvlumba),
          const SizedBox(height: 14),
          Text(
            name.isNotEmpty ? name : 'Tasarımcı',
            style: KoalaText.h2,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (profession.isNotEmpty || city.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              [profession, if (city.isNotEmpty) city]
                  .where((s) => s.isNotEmpty)
                  .join(' · '),
              style: KoalaText.bodySec,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _avatar(String url, bool isEvlumba) {
    final hasUrl = url.isNotEmpty;
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isEvlumba
            ? const SweepGradient(
                colors: [
                  KoalaColors.accentDeep,
                  KoalaColors.brandLight,
                  Color(0xFFFFC44C),
                  KoalaColors.accent,
                  KoalaColors.accentDeep,
                ],
              )
            : null,
        color: isEvlumba ? null : Colors.transparent,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: EdgeInsets.all(isEvlumba ? 3 : 0),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hasUrl ? Colors.white : KoalaColors.accentSoft,
        ),
        clipBehavior: Clip.antiAlias,
        child: hasUrl
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, _) =>
                    Container(color: KoalaColors.accentSoft),
                errorWidget: (_, _, _) => const Center(
                    child: Icon(LucideIcons.user,
                        size: 36, color: KoalaColors.accentDeep)),
              )
            : const Center(
                child: Icon(LucideIcons.user,
                    size: 36, color: KoalaColors.accentDeep),
              ),
      ),
    );
  }

  Widget _stats() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Row(
        children: [
          _stat(label: 'Tasarım', value: '${_projects.length}'),
          _statDiv(),
          _stat(label: 'Değerlendirme', value: '—', subtle: true),
          _statDiv(),
          _stat(label: 'Yanıt', value: '24s'),
        ],
      ),
    );
  }

  Widget _stat(
      {required String label, required String value, bool subtle = false}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: subtle ? KoalaColors.textTer : KoalaColors.text,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: KoalaText.labelSmall),
        ],
      ),
    );
  }

  Widget _statDiv() =>
      Container(width: 1, height: 26, color: KoalaColors.border);

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: widget.onAsk,
          style: ElevatedButton.styleFrom(
            backgroundColor: KoalaColors.accentDeep,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          icon: const Icon(LucideIcons.messageCircle, size: 18),
          label: const Text('Sor', style: KoalaText.button),
        ),
      ),
    );
  }

  Widget _aboutSection(String bio) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('HAKKINDA', style: KoalaText.caption),
          const SizedBox(height: 6),
          Text(bio, style: KoalaText.body),
        ],
      ),
    );
  }

  Widget _projectsHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      child: Row(
        children: [
          const Text('TASARIMLARI', style: KoalaText.caption),
          const Spacer(),
          if (_projects.isNotEmpty)
            Text('${_projects.length} adet', style: KoalaText.labelSmall),
        ],
      ),
    );
  }

  Widget _projectsGrid() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_projects.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
        child: Center(
          child: Text(
            'Henüz yayınlanmış tasarım yok.',
            style: KoalaText.bodySec,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.78,
        ),
        itemCount: _projects.length,
        itemBuilder: (_, i) {
          final p = _projects[i];
          final cover = _coverOf(p);
          final title = (p['title'] ?? '').toString();
          return GestureDetector(
            onTap: () => _showProjectPreview(cover, title),
            behavior: HitTestBehavior.opaque,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (cover.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: cover,
                      fit: BoxFit.cover,
                      memCacheWidth: 400,
                      placeholder: (_, _) =>
                          Container(color: KoalaColors.surfaceAlt),
                      errorWidget: (_, _, _) =>
                          Container(color: KoalaColors.surfaceAlt),
                    )
                  else
                    Container(color: KoalaColors.surfaceAlt),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.55),
                          ],
                          stops: const [0.55, 1.0],
                        ),
                      ),
                    ),
                  ),
                  if (title.isNotEmpty)
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showProjectPreview(String cover, String title) {
    if (cover.isEmpty) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: CachedNetworkImage(
                imageUrl: cover,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 12),
            if (title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            IconButton(
              icon: const Icon(LucideIcons.x, color: Colors.white),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }
}
