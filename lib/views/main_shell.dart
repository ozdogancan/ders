import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/koala_tokens.dart';
import '../helpers/paywall_router.dart';
import '../providers/pro_status_provider.dart';
import '../services/background_gen.dart';
import '../widgets/coachmark_overlay.dart';
import '../widgets/free_consult_sheet.dart' show prewarmEvlumbaConversation;
import '../widgets/koala_bottom_nav.dart';
import 'chat_list_screen.dart';
import 'home_screen.dart';
import 'mekan/wizard/mekan_wizard_screen.dart';
import 'profile_tab_screen.dart';
import 'share/share_upload_screen.dart';
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

  // Coachmark anchor keys — KoalaBottomNav slot'larına attach edilir.
  final GlobalKey _kHome = GlobalKey(debugLabel: 'nav_home');
  final GlobalKey _kChat = GlobalKey(debugLabel: 'nav_chat');
  final GlobalKey _kPaylas = GlobalKey(debugLabel: 'nav_paylas');
  final GlobalKey _kAi = GlobalKey(debugLabel: 'nav_ai');
  final GlobalKey _kProfile = GlobalKey(debugLabel: 'nav_profile');

  // Lifetime-once shell coachmark — paywall geçilince ve key set değilse açılır.
  static const String _prefsCoachmarkKey = 'coachmark_shell_done_v1';
  bool _coachmarkTriggered = false;

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
    // 2026-05-26: Kullanıcı kararı — app-launch paywall'ı KALDIRILDI.
    // Açılışta otomatik Pro popup'ı çıkmasın; paywall yalnız belirli
    // aksiyonlarda (paylas FAB, wizard finish, vs.) gösterilsin.
    try {
      await ref.read(proStatusProvider.future).timeout(
            const Duration(seconds: 2),
            onTimeout: () => ProStatus.free,
          );
    } catch (_) {/* sessiz */}
    if (!mounted) return;
    setState(() => _gate = _GateState.passed);
    // App içine girer girmez Evlumba conv id ve free-consult bayrağını
    // arka planda ısıt — kullanıcı Mesajlar/Sor'dan tıkladığında 0ms.
    unawaited(prewarmEvlumbaConversation());
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

  /// Paylaş aksiyonu — IG-tarzı composer (foto + caption + AI moderation).
  /// Pro gate YOK; paylaşım tüm kullanıcılara açık. AI re-design ayrı bir
  /// feature (mekan wizard) — burada sadece feed'e post.
  Future<void> _onPaylasTap() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ShareUploadScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_gate != _GateState.passed) {
      return const SplashScreen();
    }
    // Gate geçildi — overlay'i bir kez kurmaya çalış (postFrame).
    _maybeScheduleCoachmark();
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
          HomeScreen(embedded: true),
          ProfileTabScreen(),
        ],
      ),
      bottomNavigationBar: _navVisible
          ? KoalaBottomNav(
              current: _indexToTab(_index),
              unreadMessages: _unread,
              onSelect: (tab) => switchTab(tab),
              onPaylasTap: _onPaylasTap,
              homeKey: _kHome,
              chatKey: _kChat,
              paylasKey: _kPaylas,
              aiKey: _kAi,
              profileKey: _kProfile,
            )
          : null,
    );
  }

  /// Lifetime-once shell coachmark — gate=passed olduktan sonra, 600ms idle
  /// bekleyip prefs flag set değilse overlay'i Overlay.of üzerinden push'lar.
  /// Bell ikonu için home tab aktifse [StyleDiscoveryLiveScreen.bellKeyNotifier]
  /// üzerinden ek bir step iliştirilir.
  void _maybeScheduleCoachmark() {
    if (_coachmarkTriggered) return;
    _coachmarkTriggered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool(_prefsCoachmarkKey) == true) return;
        // Coachmark SADECE kullanıcı swipe animasyonunu (veya ilk gerçek
        // swipe'ını) gördükten SONRA tetiklenir. Notifier henüz false ise
        // bir kez bekleyip true'ya dönüşünü dinleriz.
        if (!StyleDiscoveryLiveScreen.swipeDemoSeenNotifier.value) {
          final completer = Completer<void>();
          void listener() {
            if (StyleDiscoveryLiveScreen.swipeDemoSeenNotifier.value &&
                !completer.isCompleted) {
              completer.complete();
            }
          }
          StyleDiscoveryLiveScreen.swipeDemoSeenNotifier.addListener(listener);
          try {
            await completer.future
                .timeout(const Duration(minutes: 3), onTimeout: () {});
          } finally {
            StyleDiscoveryLiveScreen.swipeDemoSeenNotifier
                .removeListener(listener);
          }
          if (!StyleDiscoveryLiveScreen.swipeDemoSeenNotifier.value) {
            // Timeout — sonraki açılışta tekrar denesin.
            _coachmarkTriggered = false;
            return;
          }
        }
        // Swipe görüldü; küçük bir nefes payı bırakıp UI'a soluk al.
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (!mounted || _gate != _GateState.passed) {
          _coachmarkTriggered = false;
          return;
        }
        // Sadece Home tab'ında başlat — kullanıcı başka tab'a geçtiyse erteleme
        // basit tut: yine başlat, anchor görünmediği step'leri overlay otomatik
        // atlıyor. Ancak akış home odaklı olduğu için home'a switch ediyoruz.
        if (_index != 0) switchTab(KoalaTab.home);
        // İki frame bekle ki nav widget'ları layout edilmiş olsun.
        await Future<void>.delayed(const Duration(milliseconds: 80));
        if (!mounted) return;
        const coachmarkBase =
            'https://xgefjepaqnghaotqybpi.supabase.co/storage/v1/object/public/koala-seed/coachmark/';
        final steps = <CoachmarkStep>[
          CoachmarkStep(
            anchorKey: _kHome,
            icon: LucideIcons.home,
            imageUrl: '${coachmarkBase}home-v1.webp',
            title: 'Ana Sayfa',
            body:
                'Bu koalanın keşif evi. Sağa-sola kaydırarak tarzına uygun mekânları seç, beğen veya geç.',
          ),
          CoachmarkStep(
            anchorKey: _kChat,
            icon: LucideIcons.messageCircle,
            imageUrl: '${coachmarkBase}chat-v1.webp',
            title: 'Mesajlar',
            body:
                'Tasarımcılarla ve Evlumba Design ile sohbet ettiğin yer burası.',
          ),
          CoachmarkStep(
            anchorKey: _kPaylas,
            icon: LucideIcons.plus,
            imageUrl: '${coachmarkBase}paylas-v1.webp',
            title: 'Paylaş',
            body:
                'Kendi odanın fotoğrafını yükle, koala senin için yeniden tasarlasın ✨',
            padding: 14,
            radius: 28,
          ),
          CoachmarkStep(
            anchorKey: _kAi,
            icon: LucideIcons.sparkles,
            imageUrl: '${coachmarkBase}ai-v1.webp',
            title: 'AI araçların',
            body: 'AI araçların burada — boya, restyle, mood board, stil keşfi.',
          ),
          CoachmarkStep(
            anchorKey: _kProfile,
            icon: LucideIcons.user,
            imageUrl: '${coachmarkBase}profile-v1.webp',
            title: 'Profil',
            body:
                'Tasarımların, koleksiyonların ve hesabın. Avatarın burada görünür.',
          ),
        ];
        // Bell ikonu (StyleDiscoveryLiveScreen üstündeki zil) varsa son step.
        final bellKey = StyleDiscoveryLiveScreen.bellKeyNotifier.value;
        if (bellKey != null) {
          steps.add(CoachmarkStep(
            anchorKey: bellKey,
            icon: LucideIcons.bell,
            imageUrl: '${coachmarkBase}bell-v1.webp',
            title: 'Bildirimler',
            body: 'Önemli güncellemeler bu zilden düşer.',
            padding: 8,
          ));
        }
        if (!mounted) return;
        CoachmarkOverlay.show(
          context: context,
          steps: steps,
          onDone: () async {
            try {
              final p = await SharedPreferences.getInstance();
              await p.setBool(_prefsCoachmarkKey, true);
            } catch (_) {/* sessiz — bir sonraki açılışta tekrar görünebilir */}
          },
        );
      } catch (_) {
        // Prefs / overlay hatası: bir sonraki frame'de tekrar dene.
        _coachmarkTriggered = false;
      }
    });
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
