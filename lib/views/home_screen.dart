import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../core/theme/koala_tokens.dart';
import '../services/chat_persistence.dart';
import '../services/analytics_service.dart';
import '../services/koala_ai_service.dart';
import '../services/global_message_listener.dart';
import '../services/messaging_service.dart';
import '../services/push_token_service.dart';
import '../services/saved_items_service.dart';
import '../services/evlumba_live_service.dart';
import 'chat_detail_screen.dart';
import 'chat_list_screen.dart';
import 'mekan/mekan_flow_screen.dart';
import 'product_entry_screen.dart';
import 'saved/saved_screen_v2.dart';
import 'style_discovery_live_screen.dart';
import '../widgets/style_discovery_pull.dart';
import 'home/widgets/continue_design_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.openStyleDiscovery = false});
  /// `/?openPull=1` deep-link ile true gelir — postFrame'de pull otomatik açılır.
  final bool openStyleDiscovery;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}


class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  final GlobalKey<_TypewriterInputState> _inputKey = GlobalKey();
  final GlobalKey<StyleDiscoveryPullState> _pullKey = GlobalKey();
  // Whole-page drag tracking
  Offset? _pullPtrStart;
  Offset? _pullPtrLast;
  bool _pullEngaged = false;
  int _unreadMsgCount = 0;

  late final AnimationController _staggerCtrl;

  // Hero kart showcase URL'leri — evlumba designer_projects'ten 6 random
  // thumbnail. Card 1'in arkaplanında 3.5s'de bir crossfade ile döngü.
  // null → henüz fetch edilmedi (placeholder göster), [] → fetch başarısız (fallback).
  List<String>? _showcaseUrls;

  @override
  void initState() {
    super.initState();
    Analytics.screenViewed('home');
    WidgetsBinding.instance.addObserver(this);
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
    _loadUnreadMsgCount();
    _migrateChatsOnce();
    _requestNotificationPermission();
    _kickInboundSync();
    _loadShowcase();
    // Inbound polling ARTIK burada yapılmıyor — GlobalMessageListener
    // merkezi olarak adaptif interval (fg 15s / bg 60s) ile sync yapıyor.
    // Her tick sonrası syncTick.value değişiyor → _onGlobalSyncTick badge
    // yenilemesini tetikler.
    // Realtime: koala_conversations update event'lerini dinle — yeni mesaj
    // geldiğinde badge + toast anında.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _subscribeIncomingMessages();
      _maybeOpenStyleDiscovery();
      _maybeShowPullHint();
    });
    // GlobalMessageListener her sync tick'inde notify eder —
    // realtime event'e güvenmek yerine explicit refresh.
    GlobalMessageListener.syncTick.addListener(_onGlobalSyncTick);
  }

  void _onGlobalSyncTick() {
    if (!mounted) return;
    _loadUnreadMsgCount();
  }

  /// Showcase URL'lerini iki karta böl. Card 1 ilk yarı, Card 2 ikinci yarı.
  /// Eğer URL yoksa null döner; kart kendi local fallback'ini gösterir.
  List<String>? _splitShowcase({required bool first}) {
    final urls = _showcaseUrls;
    if (urls == null || urls.isEmpty) return null;
    final mid = (urls.length / 2).ceil();
    return first ? urls.sublist(0, mid) : urls.sublist(mid);
  }

  /// Hero kartlar için designer_projects'ten 6 thumbnail çek.
  /// Sessiz başarısızlık — fallback asset'lere düşer.
  Future<void> _loadShowcase() async {
    try {
      if (!EvlumbaLiveService.isReady) {
        if (mounted) setState(() => _showcaseUrls = const []);
        return;
      }
      final projects = await EvlumbaLiveService.getProjects(limit: 12);
      final urls = <String>[];
      for (final p in projects) {
        final imgs = (p['designer_project_images'] as List?) ?? const [];
        if (imgs.isEmpty) continue;
        // sort_order'a göre ilk image'i al
        final sorted = List<Map>.from(imgs.cast<Map>())
          ..sort((a, b) =>
              ((a['sort_order'] as int?) ?? 999)
                  .compareTo((b['sort_order'] as int?) ?? 999));
        final url = sorted.first['image_url']?.toString();
        if (url != null && url.isNotEmpty) urls.add(url);
        if (urls.length >= 6) break;
      }
      if (mounted) setState(() => _showcaseUrls = urls);
    } catch (_) {
      if (mounted) setState(() => _showcaseUrls = const []);
    }
  }

  // Evlumba realtime subscription ARTIK HomeScreen'de kurulmuyor —
  // GlobalMessageListener global olarak `koala_global_inbound` kanalıyla
  // messages INSERT dinliyor. Çift kanal açmak DO sunucusunda boş
  // realtime connection tutuyordu.

  /// Yeni designer mesajı geldi mi tespit etmek için conv başına son
  /// gördüğümüz unread count'u ve last_message_at'i tut. Artış → toast göster.
  final Map<String, int> _lastSeenUnread = {};
  final Map<String, String> _lastSeenMsgAt = {};

  // Realtime listener referansı — dispose'da aynı referansla kapatılır.
  void Function(Map<String, dynamic>)? _convListener;
  StreamSubscription<User?>? _authSub;

  void _subscribeIncomingMessages() {
    _convListener = (record) {
      if (!mounted) return;
      final convId = record['id']?.toString();
      if (convId == null) return;
      final uid = MessagingService.currentUserId;
      final isUser = record['user_id'] == uid;
      final unreadNow = isUser
          ? ((record['unread_count_user'] as int?) ?? 0)
          : ((record['unread_count_designer'] as int?) ?? 0);
      final prevUnread = _lastSeenUnread[convId] ?? 0;
      _lastSeenUnread[convId] = unreadNow;

      final msgAtStr = (record['last_message_at']?.toString() ?? '');
      final prevAt = _lastSeenMsgAt[convId] ?? '';
      _lastSeenMsgAt[convId] = msgAtStr;

      // Badge'i daima tazele
      _loadUnreadMsgCount();

      // Yeni gelen mesaj tespiti: unread artışı VEYA last_message_at ilerlemesi.
      // Backend bazen unread RPC yoksa sadece last_message_at'i günceller —
      // o yüzden iki sinyal birden dinleniyor.
      final bodyText = (record['last_message'] as String?)?.trim() ?? '';
      final bumpedTime = prevAt.isNotEmpty && msgAtStr.isNotEmpty && msgAtStr.compareTo(prevAt) > 0;
      final bumpedUnread = unreadNow > prevUnread;
      if ((bumpedUnread || (bumpedTime && unreadNow > 0)) && bodyText.isNotEmpty) {
        _showNewMessageToast(bodyText);
      }
    };
    MessagingService.subscribeToConversations(onUpdate: _convListener!);

    // Auth restore gecikmeli olursa (hard refresh vb.) ilk çağrı no-op olur.
    // Firebase auth state hazırlanınca subscription'ı yeniden kur.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null || _convListener == null) return;
      MessagingService.subscribeToConversations(onUpdate: _convListener!);
      _kickInboundSync();
      _loadUnreadMsgCount();
    });
  }

  // Deprecated: GlobalMessageListener artık tüm ekranlarda toast gösteriyor.
  // Home screen lokal toast göstermez — çift toast olmasın diye no-op.
  void _showNewMessageToast(String body) {
    // no-op — bkz. GlobalMessageListener
  }

  Future<void> _loadUnreadMsgCount() async {
    final count = await MessagingService.getTotalUnreadCount();
    if (mounted) setState(() => _unreadMsgCount = count);
  }

  /// Evlumba → Koala ters köprü: designer mesajlarını çek, sonra badge'i tazele.
  Future<void> _kickInboundSync() async {
    final synced = await MessagingService.pullInbound();
    if (synced > 0 || mounted) {
      _loadUnreadMsgCount();
    }
  }

  Future<void> _maybeOpenStyleDiscovery() async {
    // `/?openPull=1` deep-link ile gelindiyse StyleDiscoveryPull'ı
    // programatik olarak aç (ChatDetail'deki swipe ikonundan tetiklenir).
    if (!widget.openStyleDiscovery) return;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    _pullKey.currentState?.openProgrammatically();
  }

  /// İlk açılışta pull gesture'ı kullanıcıya tanıtmak için tek seferlik
  /// hint animasyonu oynatır. SharedPreferences ile tekrarlanmaz.
  Future<void> _maybeShowPullHint() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const key = 'home_pull_hint_shown';
      if (prefs.getBool(key) == true) return;
      // Kullanıcı ekranı görsün diye küçük bir gecikme
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      await _pullKey.currentState?.playOnboardingHint();
      await prefs.setBool(key, true);
    } catch (_) {}
  }

  /// Shows style discovery if not completed yet.
  /// Returns true only if user skipped (caller should abort navigation).
  /// Returns false if completed or already done (caller should continue).
  Future<bool> _showStyleDiscoveryIfNeeded() async {
    // DEVRE DIŞI: Chat'e ilk girişte eski sahte swipe discovery artık
    // tetiklenmiyor. Bunun yerine kullanıcı ana sayfadan "Tarzını Keşfet"
    // pull gesture'ı ile canlı evlumba tasarımları arasında swipe yapıyor.
    return false;
  }

  bool _justCompletedDiscovery = false;

  Future<void> _requestNotificationPermission() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        final token = await messaging.getToken();
        if (token != null) {
          await PushTokenService.registerToken(
            deviceToken: token,
            platform: TokenPlatform.web,
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _migrateChatsOnce() async {
    try {
      await ChatPersistence.migrateLocalToSupabase();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      // App foreground'a gelince anında inbound sync
      _kickInboundSync();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    GlobalMessageListener.syncTick.removeListener(_onGlobalSyncTick);
    try {
      MessagingService.unsubscribeFromConversations(listener: _convListener);
    } catch (_) {}
    _staggerCtrl.dispose();
    super.dispose();
  }

  // Navigation helpers
  Future<void> _openChat({
    KoalaIntent? intent,
    Map<String, String>? params,
    String? text,
    bool checkDiscovery = false,
  }) async {
    if (checkDiscovery) {
      final intercepted = await _showStyleDiscoveryIfNeeded();
      if (intercepted || !mounted) return;
    }
    final fromDiscovery = _justCompletedDiscovery;
    _justCompletedDiscovery = false;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          intent: intent,
          intentParams: params,
          initialText: text,
          fromDiscovery: fromDiscovery,
        ),
      ),
    ).then((_) {
      _inputKey.currentState?.clearAndReset();
    });
  }

  void _showPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: Colors.grey.shade300,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _PickBtn(LucideIcons.camera, 'Kamera', () {
                    Navigator.pop(context);
                    _doPick(ImageSource.camera);
                  }),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PickBtn(LucideIcons.image, 'Galeri', () {
                    Navigator.pop(context);
                    _doPick(ImageSource.gallery);
                  }),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _doPick(ImageSource src) async {
    final f = await _picker.pickImage(
      source: src,
      maxWidth: 1024,
      imageQuality: 55,
    );
    if (f == null) return;
    final bytes = await f.readAsBytes();
    // First chat interaction triggers style discovery once
    final intercepted = await _showStyleDiscoveryIfNeeded();
    if (intercepted || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MekanFlowScreen(initialBytes: bytes),
      ),
    );
  }

  Widget _staggered(int index, Widget child) {
    final begin = (index * 0.1).clamp(0.0, 1.0);
    final end = (begin + 0.6).clamp(0.0, 1.0);
    final curve = CurvedAnimation(
      parent: _staggerCtrl,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final btm = MediaQuery.of(context).padding.bottom;
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: KoalaColors.bg,
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) {
          _pullPtrStart = e.position;
          _pullPtrLast = e.position;
          _pullEngaged = false;
        },
        onPointerMove: (e) {
          if (_pullPtrStart == null) return;
          final netDy = e.position.dy - _pullPtrStart!.dy;
          if (!_pullEngaged) {
            // Engage only when clearly upward (>18px up)
            if (netDy < -18) {
              _pullEngaged = true;
              _pullKey.currentState?.beginExternalDrag();
              // Forward the already-accumulated upward delta
              _pullKey.currentState?.updateExternalDrag(netDy);
            }
          } else {
            final delta = e.position.dy - (_pullPtrLast?.dy ?? e.position.dy);
            _pullKey.currentState?.updateExternalDrag(delta);
          }
          _pullPtrLast = e.position;
        },
        onPointerUp: (e) {
          if (_pullEngaged) {
            _pullKey.currentState?.endExternalDrag(-600);
          }
          _pullPtrStart = null;
          _pullPtrLast = null;
          _pullEngaged = false;
        },
        onPointerCancel: (e) {
          if (_pullEngaged) {
            _pullKey.currentState?.endExternalDrag(0);
          }
          _pullPtrStart = null;
          _pullPtrLast = null;
          _pullEngaged = false;
        },
        child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ─── Scrollable content ───
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
            // ─── Top bar ───
            // 2026 dil: greeting kaldırıldı (sol sadelik), sağda 3 ikon triplet'i.
            // Sıra soldan sağa: Koleksiyon → Mesaj → Profil. Üçü de 36px soft
            // daire chip — profil avatarı aynı ölçüde kalıyor ki tek kimlik
            // öne çıkmasın, horizon ritmik hissedilsin.
            _staggered(
              0,
              Padding(
                padding: const EdgeInsets.only(top: 12, left: 20, right: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Koleksiyon
                    _Pressable(
                      onTap: () => context.push('/collections').then(
                        (_) => _inputKey.currentState?.clearAndReset(),
                      ),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: KoalaColors.accentSoft,
                        ),
                        child: const Icon(
                          LucideIcons.bookmark,
                          size: 18,
                          color: KoalaColors.accentDeep,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Mesajlar
                    _Pressable(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ChatListScreen(),
                        ),
                      ).then((_) {
                        _inputKey.currentState?.clearAndReset();
                        _loadUnreadMsgCount();
                      }),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: KoalaColors.accentSoft,
                            ),
                            child: const Icon(
                              LucideIcons.messageCircle,
                              size: 18,
                              color: KoalaColors.accentDeep,
                            ),
                          ),
                          if (_unreadMsgCount > 0)
                            Positioned(
                              top: -2,
                              right: -2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: KoalaColors.error,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 14,
                                  minHeight: 14,
                                ),
                                child: Text(
                                  _unreadMsgCount > 9 ? '9+' : '$_unreadMsgCount',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _Pressable(
                      onTap: () => context.push('/profile').then((_) => _inputKey.currentState?.clearAndReset()),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: KoalaColors.accentSoft,
                          image: currentUser?.photoURL != null
                              ? DecorationImage(
                                  image: CachedNetworkImageProvider(
                                    currentUser!.photoURL!,
                                  ),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: currentUser?.photoURL == null
                            ? const Icon(
                                LucideIcons.user,
                                size: 18,
                                color: KoalaColors.accentDeep,
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ─── Center brand ───
            const SizedBox(height: 24),
            _staggered(
              1,
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      const Text(
                        'koala',
                        style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Georgia',
                          color: KoalaColors.ink,
                          letterSpacing: -1.9,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'by evlumba',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: KoalaColors.accentDeep,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Evini akıllıca tasarla',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: KoalaColors.textTer,
                      letterSpacing: -0.15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ─── 2 hero kart — radical redesign 2026-04-27 ───
            // 3 kart (Mekan/Ürün/Uzman) → 2 kart (Mekan/Tarz). "Ürün Bul" yok
            // edildi, "Uzman Bul" zaten result sayfasının pro CTA'sında. İki
            // kart full-width stacked, sürekli düşük tempolu animasyonla
            // (shimmer + dot drift) "canlı" hissi verir — video referansından
            // ilham, statik AI-slop görüntüsünden uzak.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // ─ Card 1: Mekanını Çek — TEK kart, before/after wipe +
                  //          ürün tag'ları (SnapHome style) + designer pill.
                  // Card 2 kaldırıldı; "Hayalindeki tarzı keşfet" artık
                  // sayfanın altındaki swipe-up handle'a taşındı.
                  _staggered(
                    2,
                    _HeroCaptureCard(
                      onTap: _showPicker,
                      showcaseUrls: null,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ─── Devam Et kartı — son kaydedilen restyle render'ı ───
            // Retention loop'un görünür ucu. Latest design yoksa kendi kendini
            // saklar (SizedBox.shrink), placeholder basmaz.
            _staggered(
              4,
              const ContinueDesignCard(),
            ),

            const SizedBox(height: 12),

            // ─── Kaydedilenlerim kısayol ───
            _staggered(
              5,
              _SavedPreviewRow(
                onViewAll: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SavedScreenV2()),
                ),
              ),
            ),

            const SizedBox(height: 12),

            const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // ─── Bottom pull handle "kulakçık" + swipe-up gesture ─────
            // Card 2 (HeroDiscoveryCard) kaldırıldı; tarz keşfi artık
            // tamamen bu handle üzerinden. Minimal pill ("Hayalindeki tarzı
            // keşfet" + chevron-up + sparkle), ilk girişte zıplayan hint
            // (_maybeShowPullHint), yukarı kaydırınca eski sheet → swipe ekranı.
            _staggered(
              7,
              StyleDiscoveryPull(
                key: _pullKey,
                showHandleStrip: true,
                totalCountBuilder: () async {
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
                },
                child: SizedBox(height: btm + 4),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// HERO CARDS — SnapHome-style demo redesign 2026-04-27
//
// Önceki versiyonda kartlar dekoratifti (shimmer, sparkles, drift dots).
// Bu versiyon DEMONSTRATIVE: kartın üst %60'ı full-bleed image cycler,
// gerçek designer_projects thumbnail'lerini 3.5s'de bir crossfade'le
// gösteriyor. Kullanıcı kart açılmadan ürünün ne ürettiğini görüyor.
//   _HeroCaptureCard   → 5-6 oda thumbnail döngüsü + footer + Deneyin pill
//   _HeroDiscoveryCard → mosaic + floating style chip pop-in'leri
// ═══════════════════════════════════════════════════════════════════════

/// Generic crossfade image cycler — n URL arasında interval'de geçiş yapar.
/// CachedNetworkImage ile network/disk cache, ilk frame'i preload eder.
class _ImageCycler extends StatefulWidget {
  const _ImageCycler({
    required this.urls,
    required this.fallbackAsset,
    this.interval = const Duration(milliseconds: 3500),
  });

  final List<String>? urls;
  final String fallbackAsset;
  final Duration interval;

  @override
  State<_ImageCycler> createState() => _ImageCyclerState();
}

class _ImageCyclerState extends State<_ImageCycler> {
  int _idx = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _maybeStartTimer();
  }

  @override
  void didUpdateWidget(covariant _ImageCycler old) {
    super.didUpdateWidget(old);
    if (old.urls != widget.urls) {
      _idx = 0;
      _maybeStartTimer();
    }
  }

  void _maybeStartTimer() {
    _timer?.cancel();
    final urls = widget.urls;
    if (urls == null || urls.length < 2) return;
    _timer = Timer.periodic(widget.interval, (_) {
      if (!mounted) return;
      setState(() => _idx = (_idx + 1) % urls.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    Widget child;
    if (urls == null || urls.isEmpty) {
      // Fallback — local asset
      child = Image.asset(
        widget.fallbackAsset,
        key: const ValueKey('fallback'),
        fit: BoxFit.cover,
      );
    } else {
      final url = urls[_idx % urls.length];
      child = CachedNetworkImage(
        key: ValueKey('cyc_${_idx}_${url.hashCode}'),
        imageUrl: url,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (_, __) => Container(color: const Color(0xFFEFEAE3)),
        errorWidget: (_, __, ___) => Image.asset(
          widget.fallbackAsset,
          fit: BoxFit.cover,
        ),
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 700),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: SizedBox.expand(child: child),
    );
  }
}

class _HeroCaptureCard extends StatelessWidget {
  const _HeroCaptureCard({required this.onTap, this.showcaseUrls});
  final VoidCallback onTap;
  final List<String>? showcaseUrls;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: Container(
        // Hero alanı 200px + footer 88px + iç padding = 296. Tag/pill için
        // kart yüksekliği artırıldı (önceki 232 → 296). Tek karta indiğimiz
        // için sayfanın görsel ağırlığı bu kartta toplanıyor.
        height: 296,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // ── HERO before/after wipe + ürün tag'ları + designer pill ──
            Expanded(
              flex: 200,
              child: _BeforeAfterShowcase(
                urls: showcaseUrls,
                fallbackAsset: 'assets/images/koala_hero.webp',
              ),
            ),
            // ── FOOTER (white, title + sub + pill) ──
            Expanded(
              flex: 88,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hayalindeki Tasarımı Gerçeğe Dönüştür',
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w700,
                              color: KoalaColors.text,
                              letterSpacing: -0.35,
                              height: 1.15,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Bir fotoğraf · 30 sn · gerçek tasarım',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: KoalaColors.textSec,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _DenePill(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroDiscoveryCard extends StatelessWidget {
  const _HeroDiscoveryCard({required this.onTap, this.showcaseUrls});
  final VoidCallback onTap;
  final List<String>? showcaseUrls;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: Container(
        height: 232,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // ── SWIPE DECK showcase ──
            // 3 mini kart üst üste yığılı, en üstteki sürekli sağa savruluyor
            // (rotate + translate + fade), bir altındakine sıra geliyor.
            // Tinder-tarzı swipe = kullanıcı "tarz keşfi" feature'ının ne
            // olduğunu görsel olarak anlıyor.
            Expanded(
              flex: 144,
              child: _SwipeDeckShowcase(
                urls: showcaseUrls,
                fallbackAsset: 'assets/images/room_demo.jpg',
              ),
            ),
            Expanded(
              flex: 88,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hayalindeki Tarzı Bul',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: KoalaColors.text,
                              letterSpacing: -0.3,
                              height: 1.15,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '8 oda · zevkini 30 saniyede çöz',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: KoalaColors.textSec,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _DenePill(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// BEFORE/AFTER WIPE SHOWCASE — Card 1
//
// Tek görsel iki kez render ediliyor: alt katman tam renkli (Sonra), üst
// katman ColorFiltered ile desaturate + karartılmış (Önce). ClipRect ile
// üst katman'ın genişliği AnimationController'a bağlı, 0.18 → 0.82 arası
// ileri-geri loop. White divider line + circular handle slider pozisyonunu
// takip eder. Önce/Sonra glass label'ları sol-sağ köşelerde.
// 8 saniyede bir görsel değişir (showcase URL'leri arasında crossfade).
// ═══════════════════════════════════════════════════════════════════════

/// Before/After story showcase — 8 saniyelik master loop.
///
/// Curated paired images: gerçek "messy/empty room" → "designed room" çifti.
/// ColorFilter desaturate hilesi YOK; iki ayrı yüksek-kaliteli görsel.
/// Ürün tag'ları sadece SONRA (after) tarafında, gerçek nesnelerin üzerinde.
/// Designer pill gerçek bir tasarımcı fotoğrafı taşır.
///
/// Hikaye akışı:
///   Phase A (0-1500ms)    : Önce only — kasvetli/boş oda
///   Phase B (1500-3550ms) : Wipe — easeInOutCubic, sin-bounce settle
///   Phase C (3650-5300ms) : 2 ürün tag'ı staggered pop (after üzerinde)
///   Phase D (5400-7100ms) : Designer match pill warm reveal
///   Phase E (7100-8000ms) : Loop bridge → crossfade + restart
///
/// Perf:
///   - Her görsel kendi RepaintBoundary'sinde (raster cache)
///   - ClipRect ListenableBuilder scope'unda (sadece clip değişir)
///   - 3 ayrı ListenableBuilder (wipe / tags / pill) — surgical rebuild
///   - precacheImage ile her iki URL warm cache
/// Curated before/after pair — AYNI ODA, Gemini Image ile generate edildi.
/// before.webp = boş raw oda (12KB) — bare walls, dark parquet floor
/// after.webp  = Koala dokunuşlu (74KB) — sofa + chair + lamp + mirrors + rug
/// Local asset → instant render, 0 network round-trip, 0 jank.
class _BAPair {
  const _BAPair({required this.before, required this.after});
  final String before;
  final String after;
}

const _kCuratedPair = _BAPair(
  before: 'assets/showcase/before.webp',
  after: 'assets/showcase/after.webp',
);

/// Product tag — afterLayer üzerinde gerçek nesneleri pointer'lar.
/// Pozisyonlar after.webp kompozisyonuna göre kalibre edildi:
///   Lambader: sağ kenardaki beyaz floor lamp
///   Kanepe:   merkezdeki cream sofa
///   Sehpa:    önde duran marble coffee table
class _Product {
  const _Product({
    required this.label,
    required this.price,
    required this.thumbnail,
  });
  final String label;
  final String price;
  final String thumbnail;
}

/// Thumbnail = after.webp'ten ffmpeg ile kırpılan GERÇEK mobilya parçası.
/// Tag'taki mini görsel = odadaki gerçek nesne → kullanıcı "Koala bunu
/// kataloglamış" hissi alır. Local asset, instant render.
const _kProducts = <_Product>[
  _Product(
    label: 'Lambader',
    price: '₺1.850',
    thumbnail: 'assets/showcase/items/lambader.webp',
  ),
  _Product(
    label: 'Kanepe',
    price: '₺12.400',
    thumbnail: 'assets/showcase/items/kanepe.webp',
  ),
  _Product(
    label: 'Sehpa',
    price: '₺2.400',
    thumbnail: 'assets/showcase/items/sehpa.webp',
  ),
];

/// Designer card için gerçek profesyonel headshot (face crop).
const _kDesignerAvatarUrl =
    'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=200&q=85&auto=format&fit=crop&crop=face';

class _BeforeAfterShowcase extends StatefulWidget {
  const _BeforeAfterShowcase({required this.urls, required this.fallbackAsset});
  // urls — kullanılmıyor (legacy), curated pairs override ediyor
  // ignore: unused_element
  final List<String>? urls;
  final String fallbackAsset;

  @override
  State<_BeforeAfterShowcase> createState() => _BeforeAfterShowcaseState();
}

class _BeforeAfterShowcaseState extends State<_BeforeAfterShowcase>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _imgIdx = 0;
  bool _precached = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      // 12s loop (önceki 8s çok hızlıydı). User'a phase'leri okuma süresi ver:
      // wipe ~2s, tag'lar ~2.5s görünür kalır, designer ~2.5s.
      duration: const Duration(milliseconds: 12000),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          if (!mounted) return;
          // Tek pair → cycle yok, sadece restart.
          _ctrl.forward(from: 0);
        }
      });
    _ctrl.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    // Pair + thumbnails artık local asset (instant). Sadece designer avatar
    // network — onu warm cache'e al ki Phase D'de pop'larken jank olmasın.
    precacheImage(CachedNetworkImageProvider(_kDesignerAvatarUrl), context)
        .catchError((_) {});
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Phase fade helper: t değeri verilen aralıklarda 0→1→1→0 dönüşür.
  /// inS=fadeInStart, inE=fadeInEnd, outS=fadeOutStart, outE=fadeOutEnd
  double _phase(double t, double inS, double inE, double outS, double outE) {
    if (t < inS) return 0;
    if (t < inE) return ((t - inS) / (inE - inS)).clamp(0.0, 1.0);
    if (t < outS) return 1.0;
    if (t < outE) return (1 - (t - outS) / (outE - outS)).clamp(0.0, 1.0);
    return 0.0;
  }

  /// 0..1 master t değerinden slider pozisyonu üret.
  /// WIPE YÖNÜ: SAĞ → SOL. Empty top layer önce çoğu alanı kaplar (sağda
  /// görünür), slider sola doğru kayınca empty küçülür → designed reveal
  /// olur. Sonuç görsel: "boş → Koala dolduruyor" — natural transformation.
  /// Phase A (0-0.1875)   : slider sağda sabit (boş tüm sahneyi kaplar)
  /// Phase B (0.1875-0.425) : sağ → sol, easeInOutCubic
  /// Phase B-end bounce   : sol kenara hafif yaylanma
  /// Phase C-D-E          : solda sabit (designed tüm sahneyi kaplar)
  double _sliderPos(double t) {
    const left = 0.04;
    const right = 0.96;
    if (t < 0.1875) return right;
    if (t < 0.425) {
      final localT = (t - 0.1875) / (0.425 - 0.1875);
      return right -
          Curves.easeInOutCubic.transform(localT) * (right - left);
    }
    if (t < 0.4438) {
      final localT = (t - 0.425) / (0.4438 - 0.425);
      final b = math.sin(localT * math.pi) * 0.03;
      return left + b;
    }
    return left;
  }

  /// "After" — Koala dokunuşlu, mobilyalı, tasarımlı oda (asset).
  Widget _afterImage() {
    return SizedBox.expand(
      child: Image.asset(
        _kCuratedPair.after,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
  }

  /// "Before" — AYNI odanın boş hali (Gemini ile generate edildi).
  Widget _beforeImage() {
    return SizedBox.expand(
      child: Image.asset(
        _kCuratedPair.before,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final w = c.maxWidth;
        return Stack(
          fit: StackFit.expand,
          children: [
            // Bottom = AFTER (statik raster)
            RepaintBoundary(child: _afterImage()),

            // Wipe-dependent layer (clipped before + divider + handle)
            ListenableBuilder(
              listenable: _ctrl,
              builder: (ctx, _) {
                final pos = _sliderPos(_ctrl.value);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRect(
                      clipper: _LeftClipper(pos),
                      child: RepaintBoundary(child: _beforeImage()),
                    ),
                    // Divider line + handle (own RepaintBoundary)
                    RepaintBoundary(
                      child: Stack(
                        children: [
                          Positioned(
                            left: w * pos - 1,
                            top: 0,
                            bottom: 0,
                            width: 2,
                            child: Container(
                              color: Colors.white.withValues(alpha: 0.95),
                            ),
                          ),
                          Positioned(
                            left: w * pos - 16,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.18),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  LucideIcons.arrowLeftRight,
                                  size: 14,
                                  color: Color(0xFF222222),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),

            // Önce / Sonra labels (statik)
            const Positioned(
              top: 12,
              left: 12,
              child: _GlassBadge(icon: LucideIcons.image, label: 'Önce'),
            ),
            const Positioned(
              top: 12,
              right: 12,
              child: _GlassBadge(
                icon: LucideIcons.sparkles,
                label: 'Sonra',
              ),
            ),

            // Phase C: 3 ürün tag'ı + connector line + item dot.
            // Tag karşı-köşede sabit pozisyonda, image üzerindeki gerçek
            // mobilyada küçük accent dot, ikisi arasında yumuşak çizgi.
            // SnapHome'daki "ürün label'ı + pointer line" estetiğine yakın.
            ListenableBuilder(
              listenable: _ctrl,
              builder: (ctx, _) {
                final t = _ctrl.value;
                final t1 = _phase(t, 0.456, 0.494, 0.638, 0.663);
                final t2 = _phase(t, 0.494, 0.531, 0.638, 0.663);
                final t3 = _phase(t, 0.531, 0.569, 0.638, 0.663);
                if (t1 == 0 && t2 == 0 && t3 == 0) {
                  return const SizedBox.shrink();
                }
                return LayoutBuilder(
                  builder: (ctx, c) {
                    final w = c.maxWidth;
                    final h = c.maxHeight;
                    // Item dot pozisyonları — gerçek mobilyaların ratio'su
                    final lampItem = Offset(w * 0.86, h * 0.50);
                    final sofaItem = Offset(w * 0.50, h * 0.62);
                    final tableItem = Offset(w * 0.42, h * 0.85);
                    // Tag pozisyonları — item dot'a YAKIN (12-14px gap, kısa
                    // connector). Tag'lar item'ların dışına ofset edildi:
                    //   Lambader → dot'un solunda
                    //   Kanepe → dot'un üstünde
                    //   Sehpa → dot'un sağ-üstünde
                    final lampTagPos = Offset(
                      lampItem.dx - 134,
                      lampItem.dy - 18,
                    );
                    final sofaTagPos = Offset(
                      sofaItem.dx - 70,
                      sofaItem.dy - 56,
                    );
                    final tableTagPos = Offset(
                      tableItem.dx + 18,
                      tableItem.dy - 28,
                    );
                    // Tag'ın bağlantı noktası (kart bottom-center)
                    const tagW = 130.0;
                    const tagH = 42.0;
                    final lampAnchor = Offset(
                      lampTagPos.dx + tagW,
                      lampTagPos.dy + tagH / 2,
                    );
                    final sofaAnchor = Offset(
                      sofaTagPos.dx + tagW / 2,
                      sofaTagPos.dy + tagH,
                    );
                    final tableAnchor = Offset(
                      tableTagPos.dx,
                      tableTagPos.dy + tagH / 2,
                    );
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        // ── Connector lines (CustomPaint, RepaintBoundary)
                        RepaintBoundary(
                          child: CustomPaint(
                            painter: _ConnectorPainter(
                              connections: [
                                if (t1 > 0) (lampAnchor, lampItem, t1),
                                if (t2 > 0) (sofaAnchor, sofaItem, t2),
                                if (t3 > 0) (tableAnchor, tableItem, t3),
                              ],
                            ),
                          ),
                        ),
                        // ── Item dots
                        if (t1 > 0)
                          Positioned(
                            left: lampItem.dx - 5,
                            top: lampItem.dy - 5,
                            child: _ItemDot(opacity: t1),
                          ),
                        if (t2 > 0)
                          Positioned(
                            left: sofaItem.dx - 5,
                            top: sofaItem.dy - 5,
                            child: _ItemDot(opacity: t2),
                          ),
                        if (t3 > 0)
                          Positioned(
                            left: tableItem.dx - 5,
                            top: tableItem.dy - 5,
                            child: _ItemDot(opacity: t3),
                          ),
                        // ── Tag cards (dot'a yakın pozisyonda)
                        Positioned(
                          left: lampTagPos.dx,
                          top: lampTagPos.dy,
                          child: _ProductTagSnap(
                            product: _kProducts[0],
                            opacity: t1,
                          ),
                        ),
                        Positioned(
                          left: sofaTagPos.dx,
                          top: sofaTagPos.dy,
                          child: _ProductTagSnap(
                            product: _kProducts[1],
                            opacity: t2,
                          ),
                        ),
                        Positioned(
                          left: tableTagPos.dx,
                          top: tableTagPos.dy,
                          child: _ProductTagSnap(
                            product: _kProducts[2],
                            opacity: t3,
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),

            // Phase D: Designer match pill (warm reveal)
            ListenableBuilder(
              listenable: _ctrl,
              builder: (ctx, _) {
                final t = _ctrl.value;
                // Glow: 0.6625-0.7125, pill: 0.675-0.731, hold to 0.8875,
                // fade to 0.9125
                final glowT = _phase(t, 0.6625, 0.7125, 0.8875, 0.9125);
                final pillT = _phase(t, 0.675, 0.731, 0.8875, 0.9125);
                if (glowT == 0 && pillT == 0) {
                  return const SizedBox.shrink();
                }
                // Pill scale + slide-up
                final scale = 0.85 + 0.15 * Curves.easeOutBack.transform(
                  pillT.clamp(0.0, 1.0),
                );
                final dy = (1 - pillT) * 16;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Warm radial glow at bottom
                    IgnorePointer(
                      child: Opacity(
                        opacity: glowT * 0.55,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(0, 0.7),
                              radius: 0.9,
                              colors: [
                                KoalaColors.accent.withValues(alpha: 0.42),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: Opacity(
                        opacity: pillT,
                        child: Transform.translate(
                          offset: Offset(0, dy),
                          child: Transform.scale(
                            scale: scale,
                            alignment: Alignment.center,
                            child: const _DesignerMatchPill(),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// CustomPainter — tag anchor'dan item dot'a kadar yumuşak quadratic eğri
/// çizer. Stroke beyaz + accent gradient karışımı, opacity tag'in fade'ine
/// senkron. Path tag'tan başlayıp itemDot'a iner — pointer hissi.
class _ConnectorPainter extends CustomPainter {
  _ConnectorPainter({required this.connections});
  final List<(Offset, Offset, double)> connections;

  @override
  void paint(Canvas canvas, Size size) {
    for (final c in connections) {
      final (start, end, op) = c;
      if (op <= 0) continue;
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: 0.85 * op)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      // Yumuşak quadratic eğri — control point yarı yolda, başlangıca yakın
      final mid = Offset(
        (start.dx + end.dx) / 2,
        (start.dy + end.dy) / 2,
      );
      // Curve control: start tarafına bias, "tag'tan damlıyor" hissi
      final ctrl = Offset(
        start.dx + (mid.dx - start.dx) * 0.2,
        start.dy + (mid.dy - start.dy) * 0.85,
      );
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);
      // İnce dış kontur (gölge)
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.18 * op)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, shadowPaint);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ConnectorPainter old) =>
      old.connections.length != connections.length ||
      List.generate(connections.length, (i) {
        final a = old.connections[i];
        final b = connections[i];
        return a.$3 != b.$3 || a.$1 != b.$1 || a.$2 != b.$2;
      }).any((e) => e);
}

/// Image üzerindeki gerçek mobilyaya yerleştirilen küçük accent dot.
/// Beyaz dolu çember + accent halo + opacity bağlı pulse.
class _ItemDot extends StatelessWidget {
  const _ItemDot({required this.opacity});
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(
            color: KoalaColors.accentDeep,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: KoalaColors.accent.withValues(alpha: 0.55),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

/// SnapHome-style ürün tag'i — beyaz mini card + kare thumbnail + label/price.
/// Image üzerinde lokalize edilmiş "Koala bunun fiyatını biliyor" sinyali.
class _ProductTagSnap extends StatelessWidget {
  const _ProductTagSnap({required this.product, required this.opacity});
  final _Product product;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final scale = 0.85 + 0.15 * Curves.easeOutBack.transform(opacity);
    return RepaintBoundary(
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.fromLTRB(5, 5, 11, 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Thumbnail — local asset (after.webp'ten kırpıldı)
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: Image.asset(
                      product.thumbnail,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => Container(
                        color: KoalaColors.accent.withValues(alpha: 0.12),
                        alignment: Alignment.center,
                        child: const Icon(
                          LucideIcons.package,
                          size: 14,
                          color: KoalaColors.accentDeep,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: KoalaColors.text,
                        letterSpacing: -0.1,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      product.price,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: KoalaColors.textSec,
                        letterSpacing: -0.1,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ürün tespit tag'i — koyu pill, beyaz label + accent fiyat.
/// Image üzerinde lokalize edilmiş "biz bunun ne olduğunu biliyoruz" sinyali.
/// (Legacy — _ProductTagSnap ile değiştirildi 2026-04-27.)
// ignore: unused_element
class _ProductTag extends StatelessWidget {
  const _ProductTag({
    required this.label,
    required this.price,
    required this.opacity,
  });

  final String label;
  final String price;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final scale = 0.85 + 0.15 * Curves.easeOutBack.transform(opacity);
    return RepaintBoundary(
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xE61F1A24),
              borderRadius: BorderRadius.circular(99),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFB8FF6E),
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  price,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB8FF6E),
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Designer match pill — Koala'nın "uzmana bağla" vaadini görselleştiriyor.
/// Gerçek profesyonel headshot + isim + rating + eşleşme çentiği.
class _DesignerMatchPill extends StatelessWidget {
  const _DesignerMatchPill();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(99),
          boxShadow: [
            BoxShadow(
              color: KoalaColors.accent.withValues(alpha: 0.30),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 14,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Avatar — gerçek fotoğraf, accent gradient ring
            Container(
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: KoalaColors.accentGradientV,
              ),
              child: ClipOval(
                child: CachedNetworkImage(
                  imageUrl: _kDesignerAvatarUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(
                    color: const Color(0xFFEFEAE3),
                    alignment: Alignment.center,
                    child: const Text(
                      'E',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: KoalaColors.accentDeep,
                      ),
                    ),
                  ),
                  errorWidget: (_, _, _) => Container(
                    color: KoalaColors.accent.withValues(alpha: 0.2),
                    alignment: Alignment.center,
                    child: const Icon(
                      LucideIcons.userCheck,
                      size: 16,
                      color: KoalaColors.accentDeep,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Esra K. — Eşleşen İç Mimar',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: KoalaColors.text,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(height: 1),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.star,
                        size: 10, color: Color(0xFFE0A53A)),
                    SizedBox(width: 3),
                    Text(
                      '4.9 · İstanbul · 8 yıl',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: KoalaColors.textSec,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 10),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: KoalaColors.accentGradientV,
              ),
              child: const Icon(
                LucideIcons.check,
                size: 12,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeftClipper extends CustomClipper<Rect> {
  _LeftClipper(this.pos);
  final double pos;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, 0, size.width * pos, size.height);

  @override
  bool shouldReclip(_LeftClipper oldClipper) => oldClipper.pos != pos;
}

// ═══════════════════════════════════════════════════════════════════════
// SWIPE DECK SHOWCASE — Card 2
//
// 3 mini kart üst üste, en üstteki sürekli sağa rotate+translate+fade
// olur, alttaki yukarı çıkar. Tinder-tarzı swipe deck animasyonu.
// Her mini kart bir stil etiketi taşır (Modern/Bohem/...).
// Kullanıcı "tarz keşfi" feature'ının swipe-tabanlı olduğunu görür.
// ═══════════════════════════════════════════════════════════════════════

class _SwipeDeckShowcase extends StatefulWidget {
  const _SwipeDeckShowcase({required this.urls, required this.fallbackAsset});
  final List<String>? urls;
  final String fallbackAsset;

  @override
  State<_SwipeDeckShowcase> createState() => _SwipeDeckShowcaseState();
}

class _SwipeDeckShowcaseState extends State<_SwipeDeckShowcase>
    with SingleTickerProviderStateMixin {
  late final AnimationController _swipeCtrl;
  int _topIdx = 0;
  bool _disposed = false;

  static const _styles = <String>[
    'Modern',
    'Bohem',
    'İskandinav',
    'Minimal',
    'Rustik',
  ];

  @override
  void initState() {
    super.initState();
    _swipeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _scheduleNext();
  }

  Future<void> _scheduleNext() async {
    // Kullanıcının kartı görmesi için bekle
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (_disposed || !mounted) return;
    await _swipeCtrl.forward(from: 0);
    if (_disposed || !mounted) return;
    setState(() => _topIdx++);
    _swipeCtrl.reset();
    _scheduleNext();
  }

  @override
  void dispose() {
    _disposed = true;
    _swipeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final w = c.maxWidth;
        return AnimatedBuilder(
          animation: _swipeCtrl,
          builder: (ctx, _) {
            final t = Curves.easeOut.transform(_swipeCtrl.value);
            return Stack(
              alignment: Alignment.center,
              children: [
                _miniCard(idxOffset: 2, swipeT: t, parentWidth: w),
                _miniCard(idxOffset: 1, swipeT: t, parentWidth: w),
                _miniCard(idxOffset: 0, swipeT: t, parentWidth: w),
              ],
            );
          },
        );
      },
    );
  }

  Widget _miniCard({
    required int idxOffset,
    required double swipeT,
    required double parentWidth,
  }) {
    final urls = widget.urls;
    final hasUrls = urls != null && urls.isNotEmpty;
    final imgIdx = (_topIdx + idxOffset);
    final url = hasUrls ? urls[imgIdx % urls.length] : null;
    final style = _styles[imgIdx % _styles.length];

    // Layered transform values:
    //  idxOffset=0 → top, swipes out
    //  idxOffset=1 → middle, rises
    //  idxOffset=2 → bottom, rises slightly
    double dx, rot, opacity, scale, dy;
    if (idxOffset == 0) {
      // Top card animates out: rotate ~14°, slide right ~+(w*0.55), fade
      dx = (parentWidth * 0.6) * swipeT;
      rot = 0.24 * swipeT; // ~14°
      opacity = (1 - swipeT * 1.2).clamp(0.0, 1.0);
      scale = 1.0;
      dy = 0;
    } else {
      // Lower cards rise + scale up as top card exits
      // depth 1 → at swipeT=1 it becomes the new top (depth 0 visually)
      final eased = swipeT; // 0..1
      final effectiveDepth = (idxOffset - eased).clamp(0.0, 2.0);
      scale = (1.0 - effectiveDepth * 0.06).clamp(0.84, 1.0);
      dy = effectiveDepth * 10;
      dx = 0;
      rot = 0;
      opacity = 1.0;
    }

    final img = url != null
        ? CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (_, _) => Container(color: const Color(0xFFEFEAE3)),
            errorWidget: (_, _, _) =>
                Image.asset(widget.fallbackAsset, fit: BoxFit.cover),
          )
        : Image.asset(widget.fallbackAsset, fit: BoxFit.cover);

    return Transform.translate(
      offset: Offset(dx, dy),
      child: Transform.rotate(
        angle: rot,
        child: Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: parentWidth * 0.62,
              height: parentWidth * 0.46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  img,
                  // Subtle bottom gradient for chip readability
                  IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.35),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Style label chip — bottom-left
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        style,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: KoalaColors.text,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                  ),
                  // Right edge "swipe heart" hint on the top card
                  if (idxOffset == 0 && swipeT > 0.15)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Opacity(
                        opacity: (swipeT * 1.6).clamp(0.0, 1.0),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: KoalaColors.accent.withValues(alpha: 0.92),
                            boxShadow: [
                              BoxShadow(
                                color: KoalaColors.accent
                                    .withValues(alpha: 0.4),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: const Icon(
                            LucideIcons.heart,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
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

/// SnapHome'daki "Deneyin →" pill — koyu fill + beyaz label + chevron.
class _DenePill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: KoalaColors.text,
        borderRadius: BorderRadius.circular(99),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Deneyin',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: -0.1,
            ),
          ),
          SizedBox(width: 4),
          Icon(LucideIcons.arrowRight, size: 14, color: Colors.white),
        ],
      ),
    );
  }
}

/// True glassmorphism badge — BackdropFilter ile gerçek bulanıklaşmış arka
/// plan + yarı saydam beyaz + ince bright border + soft shadow. iOS 17 /
/// Vision Pro estetiği.
class _GlassBadge extends StatelessWidget {
  const _GlassBadge({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            // Beyaz cam: yarı saydam + ince üst kenar parlaklığı
            color: Colors.white.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.55),
              width: 0.7,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: KoalaColors.accentDeep),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: KoalaColors.accentDeep,
                  letterSpacing: 0.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card 2'deki style chip — staggered delay ile pop-in olur, 1s görünür kalır,
/// fade-out, sonra loop. Sıralı delay'le 4 chip ardarda canlanır.
class _PopInChip extends StatelessWidget {
  const _PopInChip({required this.label, required this.delayMs});
  final String label;
  final int delayMs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(99),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 10,
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: KoalaColors.text,
          letterSpacing: -0.1,
        ),
      ),
    )
        .animate(
          onPlay: (c) => c.repeat(),
          delay: Duration(milliseconds: delayMs),
        )
        .scaleXY(begin: 0.6, end: 1.0, duration: 280.ms, curve: Curves.easeOutBack)
        .fadeIn(duration: 240.ms)
        // Hold ~3.5s
        .then(delay: 3200.ms)
        .fadeOut(duration: 320.ms)
        // Loop boşluğu — 4 chip toplam ~5s'de bir cycle yapar
        .then(delay: 1200.ms);
  }
}


// ─── Pressable (Apple-style press scale) ───
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;
  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.96,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => _ctrl.forward(),
    onTapUp: (_) {
      _ctrl.reverse();
      HapticFeedback.lightImpact();
      widget.onTap();
    },
    onTapCancel: () => _ctrl.reverse(),
    child: ScaleTransition(scale: _scale, child: widget.child),
  );
}

// ─── Pick Button (bottom sheet) ───
class _PickBtn extends StatelessWidget {
  const _PickBtn(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: KoalaColors.accentSoft,
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: KoalaColors.accent),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: KoalaColors.textMed,
            ),
          ),
        ],
      ),
    ),
  );
}

// ─── Typewriter Input Bar ───
class _TypewriterInput extends StatefulWidget {
  const _TypewriterInput({
    super.key,
    required this.bottomPadding,
    required this.onSubmit,
    required this.onPickPhoto,
  });
  final double bottomPadding;
  final void Function(String text) onSubmit;
  final VoidCallback onPickPhoto;
  @override
  State<_TypewriterInput> createState() => _TypewriterInputState();
}

class _TypewriterInputState extends State<_TypewriterInput> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _hasText = false;
  bool _twRunning = true;
  int _twSession = 0;
  int _twIdx = 0;
  String _hint = 'Koala\'ya sor...';

  static const _hints = [
    'Koala\'ya sor...',
    'odamı analiz et...',
    'stilimi bul...',
    'renk önerisi al...',
    'ürün keşfet...',
    'salonumu aydınlat...',
  ];

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onTextChanged);
    _focus.addListener(_onFocusChanged);
    _runTypewriter();
  }

  void _onTextChanged() {
    final has = _ctrl.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
    if (has) {
      _twRunning = false;
      _twSession++;
    } else if (!_focus.hasFocus) {
      _resumeTw();
    }
  }

  void _onFocusChanged() {
    if (_focus.hasFocus) {
      _twRunning = false;
      _twSession++;
    } else if (_ctrl.text.trim().isEmpty) {
      _resumeTw();
    }
  }

  void _resumeTw() {
    if (_twRunning) return;
    _twRunning = true;
    _twIdx = 0;
    setState(() => _hint = _hints.first);
    _runTypewriter();
  }

  void _runTypewriter() async {
    final session = ++_twSession;
    while (mounted && _twRunning && _twSession == session) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted || !_twRunning || _twSession != session) break;
      for (int i = _hint.length; i >= 0; i--) {
        if (!mounted || !_twRunning || _twSession != session) return;
        setState(() => _hint = _hint.substring(0, i));
        await Future.delayed(const Duration(milliseconds: 25));
      }
      _twIdx = (_twIdx + 1) % _hints.length;
      final target = _hints[_twIdx];
      for (int i = 1; i <= target.length; i++) {
        if (!mounted || !_twRunning || _twSession != session) return;
        setState(() => _hint = target.substring(0, i));
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  void _submit() {
    final text = _ctrl.text.trim();
    widget.onSubmit(text);
    if (text.isNotEmpty) _ctrl.clear();
  }

  /// Clears leftover text and restarts typewriter animation.
  void clearAndReset() {
    _ctrl.clear();
    _hasText = false;
    _focus.unfocus();
    _resumeTw();
  }

  @override
  void dispose() {
    _twRunning = false;
    _twSession++;
    _ctrl.removeListener(_onTextChanged);
    _focus.removeListener(_onFocusChanged);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 2, 16, widget.bottomPadding + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 4),
        Container(
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: Colors.white.withValues(alpha: 0.8),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: widget.onPickPhoto,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.04),
                  ),
                  child: const Icon(
                    LucideIcons.image,
                    size: 18,
                    color: KoalaColors.textSec,
                  ),
                ),
              ),
            ),
            Expanded(
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: _hint,
                  hintStyle: const TextStyle(
                    fontSize: 14,
                    color: KoalaColors.textTer,
                    fontWeight: FontWeight.w400,
                  ),
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                ),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: KoalaColors.text,
                ),
              ),
            ),
            GestureDetector(
              onTap: _submit,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: _hasText
                        ? const LinearGradient(
                            colors: [KoalaColors.accent, KoalaColors.accentDark],
                          )
                        : null,
                    color: _hasText
                        ? null
                        : Colors.black.withValues(alpha: 0.04),
                  ),
                  child: Icon(
                    LucideIcons.arrowUp,
                    size: 18,
                    color: _hasText ? Colors.white : KoalaColors.textSec,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════
// SAVED PREVIEW ROW — son kaydedilen 5 öğe
// ═══════════════════════════════════════════════════════
class _SavedPreviewRow extends StatefulWidget {
  const _SavedPreviewRow({required this.onViewAll});
  final VoidCallback onViewAll;

  @override
  State<_SavedPreviewRow> createState() => _SavedPreviewRowState();
}

class _SavedPreviewRowState extends State<_SavedPreviewRow> {
  List<Map<String, dynamic>> _items = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await SavedItemsService.getAll(limit: 5);
      if (mounted) setState(() { _items = data; _loaded = true; });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Kaydettiklerin',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: KoalaColors.ink,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: widget.onViewAll,
                child: const Text(
                  'Tümünü Gör',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: KoalaColors.accentDeep,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = _items[index];
                return Container(
                  width: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white,
                    border: Border.all(color: KoalaColors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: item['image_url'] != null
                      ? Image.network(
                          item['image_url'] as String,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(
                            LucideIcons.image,
                            color: KoalaColors.textTer,
                            size: 24,
                          ),
                        )
                      : Center(
                          child: Text(
                            (item['title'] as String? ?? '?')[0].toUpperCase(),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: KoalaColors.accentDeep,
                            ),
                          ),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// ACTIVE CONVERSATIONS ROW — son 3 mesaj preview
// ═══════════════════════════════════════════════════════
// İlham Galerisi — ana sayfadaki boş alanı dolduran
// son projelerin küçük grid gösterimi
// ═══════════════════════════════════════════════════════
class _InspirationGallery extends StatefulWidget {
  const _InspirationGallery();
  @override
  State<_InspirationGallery> createState() => _InspirationGalleryState();
}

class _InspirationGalleryState extends State<_InspirationGallery> {
  List<Map<String, dynamic>> _projects = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (!EvlumbaLiveService.isReady) return;
      final data = await EvlumbaLiveService.getProjects(limit: 6);
      if (mounted) setState(() { _projects = data; _loaded = true; });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  String? _imageUrl(Map<String, dynamic> project) {
    final images = project['designer_project_images'] as List?;
    if (images != null && images.isNotEmpty) {
      final sorted = List<Map<String, dynamic>>.from(images)
        ..sort((a, b) => ((a['sort_order'] ?? 99) as int).compareTo((b['sort_order'] ?? 99) as int));
      return sorted.first['image_url'] as String?;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _projects.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ilham Al',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: KoalaColors.ink,
            ),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1.0,
            ),
            itemCount: _projects.length,
            itemBuilder: (context, index) {
              final project = _projects[index];
              final url = _imageUrl(project);
              final name = (project['project_name'] ?? '').toString();

              return GestureDetector(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const ProductEntryScreen(),
                  ));
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (url != null)
                        CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(color: KoalaColors.surfaceCool),
                          errorWidget: (_, _, _) => Container(
                            color: KoalaColors.surfaceCool,
                            child: const Icon(LucideIcons.image, color: KoalaColors.textTer),
                          ),
                        )
                      else
                        Container(
                          color: KoalaColors.surfaceCool,
                          child: const Icon(LucideIcons.image, color: KoalaColors.textTer),
                        ),
                      // Alt gradient + proje tipi
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Color(0xAA000000), Colors.transparent],
                            ),
                          ),
                          child: Text(
                            (project['project_type'] ?? name).toString(),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
