import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/koala_tokens.dart';
import '../helpers/paywall_router.dart';
import '../providers/pro_status_provider.dart';
import '../services/background_gen.dart';
import '../widgets/koala_bottom_nav.dart';
import 'chat_list_screen.dart';
import 'home_screen.dart';
import 'projeler_screen.dart';
import 'splash_screen.dart';
import 'style_discovery_live_screen.dart';

/// Cold-start guard — entry paywall should appear at most once per app launch,
/// regardless of MainShell rebuilds, tab switches or remounts.
bool _entryPaywallShownThisLaunch = false;

/// Ana 4-tab kabuk — Ana Sayfa | Mesajlar | Swipe | Projeler.
/// Nav SABİT kalır, tab değişince sadece içerik IndexedStack ile değişir
/// (animasyon yok, sıçrama yok). Detay ekranları bu shell'in ÜSTÜNE
/// Navigator.push ile gelir; o sırada nav doğal olarak gizlenir.
class MainShell extends ConsumerStatefulWidget {
  final int initialIndex;
  const MainShell({super.key, this.initialIndex = 0});

  @override
  ConsumerState<MainShell> createState() => MainShellState();

  /// Singleton instance — pushed route'lar (mekan flow, project detail vs)
  /// için context ağacı üzerinden bulunamaz. initState/dispose'da set edilir.
  static MainShellState? _instance;

  /// MainShell state'ine globalden eriş — sekme değiştirmek, nav göster/gizle.
  /// Context şart değil; pushed route'tan da çağrılabilir.
  static MainShellState? of([BuildContext? _]) => _instance;

  /// Sekme değişimi olduğunda yayın yapan global notifier — ekranlar buna
  /// abone olup "ben az önce göründüm" anında state reset edebilir.
  static final ValueNotifier<KoalaTab> activeTab =
      ValueNotifier<KoalaTab>(KoalaTab.home);
}

enum _GateState { loading, gated, passed }

class MainShellState extends ConsumerState<MainShell> {
  late int _index = widget.initialIndex;
  int _unread = 0;
  bool _navVisible = true;
  _GateState _gate = _GateState.loading;

  @override
  void initState() {
    super.initState();
    MainShell._instance = this;
    BackgroundGen.completion.addListener(_onBgComplete);
    _resolveGate();
  }

  Future<void> _resolveGate() async {
    // Hard fail-safe: gate ne olursa olsun 5sn içinde açılır. Boş ekran takılı
    // kalmasın diye. Pro fetch / paywall render hata verirse bile home gelir.
    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      if (_gate != _GateState.passed) {
        setState(() => _gate = _GateState.passed);
      }
    });
    try {
      final status = await ref
          .read(proStatusProvider.future)
          .timeout(const Duration(seconds: 2), onTimeout: () => ProStatus.free);
      if (!mounted) return;
      if (status.isPro || _entryPaywallShownThisLaunch) {
        setState(() => _gate = _GateState.passed);
        return;
      }
      _entryPaywallShownThisLaunch = true;
      setState(() => _gate = _GateState.gated);
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        try {
          await showPaywall(context, trigger: 'app_launch');
        } catch (_) {/* paywall render hatası — yine de home'a düş */}
        if (!mounted) return;
        if (_gate != _GateState.passed) {
          setState(() => _gate = _GateState.passed);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _gate = _GateState.passed);
    }
  }

  @override
  void dispose() {
    if (MainShell._instance == this) MainShell._instance = null;
    BackgroundGen.completion.removeListener(_onBgComplete);
    super.dispose();
  }

  void _onBgComplete() {
    final c = BackgroundGen.completion.value;
    if (c == null) return;
    BackgroundGen.consumeCompletion();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.clearSnackBars();
    messenger?.showSnackBar(
      SnackBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        padding: EdgeInsets.zero,
        duration: const Duration(seconds: 4),
        content: GestureDetector(
          onTap: () {
            switchTab(KoalaTab.projeler);
            messenger?.hideCurrentSnackBar();
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: KoalaColors.text.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KoalaColors.accentDeep,
                  ),
                  child: const Icon(LucideIcons.sparkles,
                      size: 16, color: Colors.white),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tasarımın hazır ✨',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        'Görmek için dokun',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(LucideIcons.arrowRight,
                    color: Colors.white, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void switchTab(KoalaTab tab) {
    final next = _tabToIndex(tab);
    if (next == _index) return;
    // Visual change first — paint the new tab synchronously.
    setState(() => _index = next);
    // Notify global listeners on the next microtask so any expensive
    // "I just became active" listener work doesn't block the frame.
    Future<void>.delayed(Duration.zero, () {
      MainShell.activeTab.value = tab;
    });
  }

  void setUnread(int count) {
    if (count == _unread) return;
    setState(() => _unread = count);
  }

  /// Sekme nav'ı geçici olarak gizle (örn. select-mode bottom bar'a yer aç).
  void setNavVisible(bool visible) {
    if (visible == _navVisible) return;
    setState(() => _navVisible = visible);
  }

  int _tabToIndex(KoalaTab t) {
    switch (t) {
      case KoalaTab.home:
        return 0;
      case KoalaTab.chat:
        return 1;
      case KoalaTab.swipe:
        return 2;
      case KoalaTab.projeler:
        return 3;
    }
  }

  KoalaTab _indexToTab(int i) {
    switch (i) {
      case 1:
        return KoalaTab.chat;
      case 2:
        return KoalaTab.swipe;
      case 3:
        return KoalaTab.projeler;
      default:
        return KoalaTab.home;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_gate != _GateState.passed) {
      // Pro durumu çözülene kadar SplashScreen görünür kalır — SS1'in
      // progress'i kesintisiz akar, gate çözülünce paywall onun üstüne açılır.
      // Böylece splash ile Pro popup arasında boş/krem flaş olmaz.
      return const SplashScreen();
    }
    return _buildHome(context);
  }

  Widget _buildHome(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      extendBody: true,
      resizeToAvoidBottomInset: false,
      body: IndexedStack(
        index: _index,
        children: const [
          HomeScreen(),
          ChatListScreen(),
          StyleDiscoveryLiveScreen(),
          ProjelerScreen(),
        ],
      ),
      bottomNavigationBar: _navVisible
          ? KoalaBottomNav(
              current: _indexToTab(_index),
              unreadMessages: _unread,
              onSelect: (tab) => switchTab(tab),
            )
          : null,
    );
  }
}

