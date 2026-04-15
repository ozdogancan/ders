import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:go_router/go_router.dart';
import '../core/theme/koala_tokens.dart';
import '../services/chat_persistence.dart';
import '../services/analytics_service.dart';
import '../services/koala_ai_service.dart';
import '../services/messaging_service.dart';
import '../services/notifications_service.dart';
import '../services/push_token_service.dart';
import '../services/saved_items_service.dart';
import '../services/evlumba_live_service.dart';
import 'chat_detail_screen.dart';
import 'chat_list_screen.dart';
import 'style_discovery_screen.dart';
import 'designers_screen.dart';
import 'profile_screen.dart';
import 'product_entry_screen.dart';
import 'saved_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}


class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  final GlobalKey<_TypewriterInputState> _inputKey = GlobalKey();
  int _notifCount = 0;
  int _unreadMsgCount = 0;
  Timer? _inboundPollTimer;

  late final AnimationController _staggerCtrl;

  @override
  void initState() {
    super.initState();
    Analytics.screenViewed('home');
    WidgetsBinding.instance.addObserver(this);
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
    _loadNotifCount();
    _loadUnreadMsgCount();
    _migrateChatsOnce();
    _requestNotificationPermission();
    _kickInboundSync();
    // Her 30 sn'de bir arka planda inbound sync — designer mesajları için
    _inboundPollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _kickInboundSync(),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeOpenStyleDiscovery(),
    );
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
    // Style discovery is now triggered on first chat interaction, not on home load.
  }

  /// Shows style discovery if not completed yet.
  /// Returns true only if user skipped (caller should abort navigation).
  /// Returns false if completed or already done (caller should continue).
  Future<bool> _showStyleDiscoveryIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool('style_discovery_completed') ?? false;
    if (completed) return false;
    if (!mounted) return false;
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const StyleDiscoveryScreen(entryPoint: 'first_chat'),
      ),
    );
    if (!mounted) return true;
    if (result == 'skipped') {
      // Atla'ya basıldığında da chat'e devam et, engelleme
      return false;
    }
    // completed — continue to original destination
    _justCompletedDiscovery = true;
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

  Future<void> _loadNotifCount() async {
    final count = await NotificationsService.getUnreadCount();
    if (mounted) setState(() => _notifCount = count);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      // App foreground'a gelince anında inbound sync + unread refresh
      _kickInboundSync();
      _loadNotifCount();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inboundPollTimer?.cancel();
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
        builder: (_) => ChatDetailScreen(
          intent: KoalaIntent.photoAnalysis,
          initialPhoto: bytes,
        ),
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
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ─── Scrollable content ───
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
            // ─── Top bar ───
            _staggered(
              0,
              Padding(
                padding: const EdgeInsets.only(top: 12, left: 20, right: 20),
                child: Row(
                  children: [
                    // Greeting
                    Expanded(
                      child: Text(
                        'Merhaba${currentUser?.displayName != null ? ', ${currentUser!.displayName!.split(' ').first}' : ''} 👋',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: KoalaColors.ink,
                        ),
                      ),
                    ),
                    // Bildirim zili
                    _Pressable(
                      onTap: () async {
                        await context.push('/notifications');
                        _loadNotifCount();
                        _inputKey.currentState?.clearAndReset();
                      },
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
                              LucideIcons.bell,
                              size: 18,
                              color: KoalaColors.accentDeep,
                            ),
                          ),
                          if (_notifCount > 0)
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
                                child: Text(
                                  _notifCount > 9 ? '9+' : '$_notifCount',
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

            // ─── Action cards section ───
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // Mekanını Çek
                  _staggered(
                    2,
                    _Pressable(
                      onTap: _showPicker,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: KoalaColors.accentGradientV,
                          boxShadow: [
                            BoxShadow(
                              color: KoalaColors.accentDark.withValues(alpha: 0.25),
                              blurRadius: 32,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: Colors.white.withValues(alpha: 0.18),
                              ),
                              child: const Icon(
                                LucideIcons.camera,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Mekanını Çek',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    'AI stil analizi, ürün ve renk önerileri',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                              child: const Icon(
                                LucideIcons.arrowRight,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Ürün Bul + Uzman Bul
                  _staggered(
                    3,
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _ServiceCard(
                              icon: LucideIcons.shoppingBag,
                              title: 'Ürün Bul',
                              sub: 'AI ile oda, stil ve bütçeye göre keşif',
                              onTap: () async {
                                final intercepted =
                                    await _showStyleDiscoveryIfNeeded();
                                if (intercepted || !mounted) return;
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const ProductEntryScreen(),
                                  ),
                                ).then((_) => _inputKey.currentState?.clearAndReset());
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _ServiceCard(
                              icon: LucideIcons.userCheck,
                              title: 'Uzman Bul',
                              sub: 'İç mimar ve tasarımcı eşleştir',
                              onTap: () async {
                                final intercepted =
                                    await _showStyleDiscoveryIfNeeded();
                                if (intercepted || !mounted) return;
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const DesignersScreen(),
                                  ),
                                ).then((_) => _inputKey.currentState?.clearAndReset());
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ─── Kaydedilenlerim kısayol ───
            _staggered(
              4,
              _SavedPreviewRow(
                onViewAll: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SavedScreen()),
                ),
              ),
            ),

            const SizedBox(height: 12),

            const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // ─── Input bar (sabit, scroll dışında) ───
            _staggered(
              7,
              _TypewriterInput(
                key: _inputKey,
                bottomPadding: btm,
                onSubmit: (text) => _openChat(text: text.isEmpty ? null : text),
                onPickPhoto: _showPicker,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Service Card (frosted glass style) ───
class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.icon,
    required this.title,
    required this.sub,
    required this.onTap,
  });
  final IconData icon;
  final String title, sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 152),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.05),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: KoalaColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: 20, color: KoalaColors.accent),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: KoalaColors.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              sub,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: KoalaColors.textSec,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
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
              separatorBuilder: (_, __) => const SizedBox(width: 8),
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
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.image_rounded,
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
                          placeholder: (_, __) => Container(color: KoalaColors.surfaceCool),
                          errorWidget: (_, __, ___) => Container(
                            color: KoalaColors.surfaceCool,
                            child: const Icon(Icons.image_outlined, color: KoalaColors.textTer),
                          ),
                        )
                      else
                        Container(
                          color: KoalaColors.surfaceCool,
                          child: const Icon(Icons.image_outlined, color: KoalaColors.textTer),
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
