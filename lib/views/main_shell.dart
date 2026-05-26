import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/koala_tokens.dart';
import '../helpers/paywall_router.dart';
import '../providers/pro_status_provider.dart';
import '../services/background_gen.dart';
import '../widgets/koala_bottom_nav.dart';
import 'chat_detail_screen.dart';
import 'chat_list_screen.dart';
import 'mekan/wizard/mekan_wizard_screen.dart';
import 'projeler_screen.dart';
import 'splash_screen.dart';
import 'style_discovery_live_screen.dart';

/// Cold-start guard — entry paywall should appear at most once per app launch.
bool _entryPaywallShownThisLaunch = false;

/// Ana 4-sekme kabuk + ortada "Paylaş" FAB.
/// L→R: Ana Sayfa (swipe) | Mesajlar | [Paylaş] | AI | Projeler.
/// Paylaş bir sekme DEĞİL — bir aksiyon (foto yükle → MekanWizard).
class MainShell extends ConsumerStatefulWidget {
  final int initialIndex;
  const MainShell({super.key, this.initialIndex = 0});

  @override
  ConsumerState<MainShell> createState() => MainShellState();

  static MainShellState? _instance;

  static MainShellState? of([BuildContext? _]) => _instance;

  /// Sekme değişimi olduğunda yayın yapan global notifier.
  static final ValueNotifier<KoalaTab> activeTab =
      ValueNotifier<KoalaTab>(KoalaTab.home);
}

enum _GateState { loading, gated, passed }

class MainShellState extends ConsumerState<MainShell> {
  late int _index = widget.initialIndex;
  int _unread = 0;
  bool _navVisible = true;
  _GateState _gate = _GateState.loading;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    MainShell._instance = this;
    BackgroundGen.completion.addListener(_onBgComplete);
    _resolveGate();
  }

  Future<void> _resolveGate() async {
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
                  decoration: const BoxDecoration(
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
    setState(() => _index = next);
    Future<void>.delayed(Duration.zero, () {
      MainShell.activeTab.value = tab;
    });
  }

  void setUnread(int count) {
    if (count == _unread) return;
    setState(() => _unread = count);
  }

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
      case KoalaTab.ai:
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
        return KoalaTab.ai;
      case 3:
        return KoalaTab.projeler;
      default:
        return KoalaTab.home;
    }
  }

  /// Paylaş aksiyonu — Pro gate sonrası foto seçici → MekanWizardScreen.
  Future<void> _onPaylasTap() async {
    final pro = ref.read(proStatusProvider).value?.isPro ?? false;
    if (!pro) {
      await showPaywall(context, trigger: 'paylas_tab');
      return;
    }
    if (!mounted) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: KoalaColors.bg,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _PaylasSourceSheet(),
    );
    if (source == null || !mounted) return;
    try {
      final f = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        imageQuality: 60,
      );
      if (f == null || !mounted) return;
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MekanWizardScreen(photoBytes: bytes),
        ),
      );
    } catch (_) {/* swallow — kullanıcı iptal */}
  }

  @override
  Widget build(BuildContext context) {
    if (_gate != _GateState.passed) {
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
          StyleDiscoveryLiveScreen(),
          ChatListScreen(),
          ChatDetailScreen(),
          ProjelerScreen(),
        ],
      ),
      bottomNavigationBar: _navVisible
          ? KoalaBottomNav(
              current: _indexToTab(_index),
              unreadMessages: _unread,
              onSelect: (tab) => switchTab(tab),
              onPaylasTap: _onPaylasTap,
            )
          : null,
    );
  }
}

// ─── Paylaş source picker sheet ───
class _PaylasSourceSheet extends StatelessWidget {
  const _PaylasSourceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 18),
            const Text('Mekânını paylaş', style: KoalaText.h2),
            const SizedBox(height: 6),
            const Text(
              'Bir oda fotoğrafı yükle, AI senin için yeniden tasarlasın.',
              textAlign: TextAlign.center,
              style: KoalaText.bodySec,
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _SourceBtn(
                    icon: LucideIcons.camera,
                    label: 'Kamera',
                    onTap: () => Navigator.pop(context, ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SourceBtn(
                    icon: LucideIcons.image,
                    label: 'Galeri',
                    onTap: () => Navigator.pop(context, ImageSource.gallery),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _SourceBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SourceBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KoalaColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: KoalaColors.borderSolid),
          ),
          child: Column(
            children: [
              Icon(icon, size: 26, color: KoalaColors.accentDeep),
              const SizedBox(height: 8),
              Text(label, style: KoalaText.label),
            ],
          ),
        ),
      ),
    );
  }
}
