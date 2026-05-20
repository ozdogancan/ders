// Koala Pro paywall — purple, single-page (no scroll) redesign.
//
// Layout (top-to-bottom, fits ~770dp):
//   • Top bar (close X + Geri Yükle pill)
//   • Auto-rotating 3-slide value-prop carousel hero (~180dp)
//   • Title + tiny subtitle
//   • Compact 2x2 feature bullet grid
//   • Optional trial toggle (hidden if trial already used)
//   • Plan A (Haftalık) + Plan B (Yıllık, savings badge) cards
//   • Purple CTA "Devam et"
//   • Cancel-anytime line + footer links
//
// Billing path identical to prior version: BillingService.getOfferings() →
// substring match ('week'/'month'/'year') → BillingService.purchase().

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/koala_tokens.dart';
import '../../providers/pro_status_provider.dart';
import '../../services/analytics_service.dart';
import '../../services/billing_service.dart';
import '../../services/usage_limit_service.dart';

enum _PlanKind { weekly, yearly }

// Koala brand purple palette.
const _kPurple = Color(0xFF6C63FF);
const _kPurpleDeep = Color(0xFF9B5CFF);
const _kPurpleSoft = Color(0xFFF3F0FF);
const _kBorder = Color(0xFFE0DAFF);

// Carousel hero slides — bundled assets for instant first paint.
// TODO: Upload animated variants to Supabase Storage and swap to Image.network
// with these URLs as drop-in replacements (no other code change needed):
//   - pro-assets/paywall-slide-1.webp
//   - pro-assets/paywall-slide-2.webp
//   - pro-assets/paywall-slide-3.webp
const _kSlideAssets = <String>[
  'assets/pro/hero_1.png',
  'assets/pro/hero_2.png',
  'assets/pro/hero_3.png',
];

class PaywallScreen extends ConsumerStatefulWidget {
  final String trigger;
  const PaywallScreen({super.key, required this.trigger});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  _PlanKind _selected = _PlanKind.yearly;
  bool _trialEnabled = true;
  bool _trialUsed = false;
  bool _purchasing = false;

  // Carousel state.
  final PageController _heroController = PageController(initialPage: 0);
  int _heroIndex = 0;
  Timer? _heroTimer;
  bool _precached = false;

  // TR pricing fallback (used until offerings load).
  static const _weeklyPrice = '₺79,99';
  static const _yearlyPrice = '₺999,99';
  // ₺999,99 / 52 ≈ ₺19,23
  static const _yearlyPerWeek = '₺19,23';

  @override
  void initState() {
    super.initState();
    Analytics.log('paywall_opened', {'trigger': widget.trigger});
    // Defensively check trial_used (field may not exist on ProStatus yet).
    try {
      final asyncPs = ref.read(proStatusProvider);
      final ps = asyncPs.value;
      if (ps != null) {
        // Dynamic access so this compiles whether or not trialUsed exists.
        final dynamic dps = ps;
        final used = dps.trialUsed;
        if (used is bool) _trialUsed = used;
      }
    } catch (_) {/* field absent → leave _trialUsed=false */}
    _trialEnabled = !_trialUsed;

    // Auto-advance the hero carousel every 3500ms (no user swipe).
    _heroTimer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
      if (!mounted) return;
      final next = (_heroIndex + 1) % _kSlideAssets.length;
      _heroIndex = next;
      if (_heroController.hasClients) {
        _heroController.animateToPage(
          next,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    for (final p in _kSlideAssets) {
      precacheImage(AssetImage(p), context);
    }
  }

  @override
  void dispose() {
    _heroTimer?.cancel();
    _heroController.dispose();
    super.dispose();
  }

  Future<void> _onPurchase() async {
    if (_purchasing) return;
    setState(() => _purchasing = true);
    Analytics.log('paywall_cta_tapped', {
      'trigger': widget.trigger,
      'plan': _selected.name,
      'trial': _trialEnabled && !_trialUsed,
    });
    try {
      final pkgs = await BillingService.getOfferings();
      Package? match;
      for (final p in pkgs) {
        final id = p.storeProduct.identifier.toLowerCase();
        if (_selected == _PlanKind.weekly && id.contains('week')) match = p;
        if (_selected == _PlanKind.yearly && id.contains('year')) match = p;
        if (match == null &&
            _selected == _PlanKind.yearly &&
            id.contains('month')) {
          match = p;
        }
      }
      if (match == null) {
        await _showFailureDialog();
        return;
      }
      final ok = await BillingService.purchase(match);
      if (!mounted) return;
      if (ok) {
        await UsageLimitService.resetAll();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pro üyeliğin aktif!',
                style: TextStyle(fontWeight: FontWeight.w600)),
            backgroundColor: KoalaColors.greenBright,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      } else {
        await _showFailureDialog();
      }
    } catch (_) {
      await _showFailureDialog();
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _showFailureDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KoalaColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KoalaRadius.lg)),
        title: const Text('Bir sorun oluştu', style: KoalaText.h3),
        content: const Text(
          'Satın alma şu an tamamlanamadı. Lütfen biraz sonra tekrar deneyin.',
          style: TextStyle(fontSize: 14, color: KoalaColors.textMed),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: FilledButton.styleFrom(backgroundColor: _kPurple),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  Future<void> _onRestore() async {
    Analytics.log('paywall_restore_tapped', {'trigger': widget.trigger});
    final ok = await BillingService.restorePurchases();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Satın alımlar geri yüklendi'
            : 'Geri yüklenecek satın alma bulunamadı'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      body: Container(
        decoration: const BoxDecoration(color: KoalaColors.bg),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHero(),
                const SizedBox(height: 14),
                _buildTitle(),
                const SizedBox(height: 10),
                _buildBulletsGrid(),
                const SizedBox(height: 10),
                if (!_trialUsed) ...[
                  _buildTrialToggle(),
                  const SizedBox(height: 8),
                ],
                _buildPlanCards(),
                const Spacer(),
                const SizedBox(height: 8),
                _buildCta(),
                const SizedBox(height: 8),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Top bar ─────────────────────────────────────────────
  Widget _buildTopBar() {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          _CircleIconButton(
            icon: Icons.close,
            onTap: () => Navigator.of(context).pop(),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _onRestore,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kBorder),
              ),
              child: const Text(
                'Geri Yükle',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: KoalaColors.text,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Hero (auto-rotating 3-slide value-prop carousel) ───
  Widget _buildHero() {
    return SizedBox(
      height: 170,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: _kPurple.withValues(alpha: 0.18),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _heroController,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _kSlideAssets.length,
                onPageChanged: (i) {
                  if (mounted) setState(() => _heroIndex = i);
                },
                itemBuilder: (_, i) => _CarouselSlide(
                  assetPath: _kSlideAssets[i],
                ),
              ),
              // Top-left close + top-right Geri Yükle pill, overlay-style.
              Positioned(
                top: 10,
                left: 10,
                child: _CircleIconButton(
                  icon: Icons.close,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: GestureDetector(
                  onTap: _onRestore,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Text(
                      'Geri Yükle',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: KoalaColors.text,
                      ),
                    ),
                  ),
                ),
              ),
              // Page dots — center-bottom.
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_kSlideAssets.length, (i) {
                    final active = i == _heroIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.white
                            .withValues(alpha: active ? 1.0 : 0.4),
                        shape: BoxShape.circle,
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Title + subtitle — centered SnapHome-style ─────────
  Widget _buildTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: const [
        Text(
          'Pro Erişimi',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: KoalaColors.text,
            letterSpacing: -0.5,
            height: 1.1,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'AI tasarım, sınırsız ilham',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: KoalaColors.textMed,
          ),
        ),
      ],
    );
  }

  // ─── 3 stacked value bullets — SnapHome-style ───────────
  Widget _buildBulletsGrid() {
    const bullets = [
      'Sınırsız AI tasarım sohbeti',
      'Fotoğrafından sınırsız mekan dönüşümü',
      'Uzmanlardan öncelikli, hızlı yanıt',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final b in bullets)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.workspace_premium,
                    color: _kPurple, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    b,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: KoalaColors.text,
                      height: 1.25,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ─── Trial toggle row ───────────────────────────────────
  Widget _buildTrialToggle() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _kPurpleSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Ücretsiz denemeyi etkinleştir',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: KoalaColors.text,
              ),
            ),
          ),
          Transform.scale(
            scale: 0.85,
            child: Switch(
              value: _trialEnabled,
              onChanged: (v) => setState(() {
                // Trial ON → weekly (7-day trial), OFF → yearly.
                _trialEnabled = v && !_trialUsed;
                _selected = _trialEnabled ? _PlanKind.weekly : _PlanKind.yearly;
              }),
              activeThumbColor: Colors.white,
              activeTrackColor: _kPurple,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Plan cards ─────────────────────────────────────────
  Widget _buildPlanCards() {
    final canTrial = !_trialUsed && _trialEnabled;
    return Column(
      children: [
        _PlanCard(
          selected: _selected == _PlanKind.weekly,
          onTap: () => setState(() {
            _selected = _PlanKind.weekly;
            // Selecting weekly re-enables trial (if eligible).
            _trialEnabled = !_trialUsed;
          }),
          topLabel: canTrial ? '7 Gün Tam Erişim' : 'Haftalık',
          subLabel: canTrial
              ? 'sonra $_weeklyPrice/hafta'
              : 'haftalık yenilenir',
          priceMain: _weeklyPrice,
          priceUnit: '/ hafta',
        ),
        const SizedBox(height: 12),
        _PlanCard(
          selected: _selected == _PlanKind.yearly,
          onTap: () => setState(() {
            _selected = _PlanKind.yearly;
            // Selecting yearly auto-disables trial.
            _trialEnabled = false;
          }),
          topLabel: 'Yıllık',
          subLabel: '$_yearlyPrice / yıl',
          priceMain: _yearlyPerWeek,
          priceUnit: '/ haftada',
          badge: '%76 TASARRUF',
        ),
      ],
    );
  }

  // ─── CTA — purple gradient + looping shimmer sweep ──────
  Widget _buildCta() {
    final button = SizedBox(
      width: double.infinity,
      height: 52,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_kPurple, _kPurpleDeep],
            ),
            boxShadow: [
              BoxShadow(
                color: _kPurple.withValues(alpha: 0.32),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _purchasing ? null : _onPurchase,
              child: Center(
                child: _purchasing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Devam et',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    if (_purchasing) return button;
    // Looping shimmer sweep — every ~2.4s, white glaze passes across.
    return Animate(
      onPlay: (c) => c.repeat(),
      effects: [
        ShimmerEffect(
          duration: const Duration(milliseconds: 2400),
          delay: const Duration(milliseconds: 600),
          color: Colors.white.withValues(alpha: 0.55),
        ),
      ],
      child: button,
    );
  }

  // ─── Footer ─────────────────────────────────────────────
  Widget _buildFooter() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_trialUsed)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Deneme bu hesapta kullanıldı',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: KoalaColors.textTer,
              ),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shield_outlined,
                size: 13, color: KoalaColors.greenAlt),
            const SizedBox(width: 6),
            Text(
              'İstediğin zaman iptal',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: KoalaColors.textMed,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _FooterLink(
              label: 'Gizlilik',
              onTap: () => _openLink('https://www.koalatutor.com/privacy'),
            ),
            const _FooterDot(),
            _FooterLink(
              label: 'Şartlar',
              onTap: () => _openLink('https://www.koalatutor.com/terms'),
            ),
            const _FooterDot(),
            _FooterLink(label: 'Geri Yükle', onTap: _onRestore),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Small UI pieces
// ═══════════════════════════════════════════════════════════
class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: _kBorder),
        ),
        child: Icon(icon, color: KoalaColors.text, size: 20),
      ),
    );
  }
}


class _PlanCard extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final String topLabel;
  final String subLabel;
  final String priceMain;
  final String priceUnit;
  final String? badge;

  const _PlanCard({
    required this.selected,
    required this.onTap,
    required this.topLabel,
    required this.subLabel,
    required this.priceMain,
    required this.priceUnit,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: selected ? _kPurpleSoft : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? _kPurple : _kBorder,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        topLabel,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: KoalaColors.text,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: KoalaColors.textMed,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      priceMain,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: KoalaColors.text,
                        letterSpacing: -0.4,
                      ),
                    ),
                    Text(
                      priceUnit,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: KoalaColors.textMed,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (badge != null)
            Positioned(
              top: -10,
              left: 14,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [_kPurple, _kPurpleDeep]),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: _kPurple.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _FooterLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: KoalaColors.textTer,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}

class _FooterDot extends StatelessWidget {
  const _FooterDot();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Text('·',
            style: TextStyle(fontSize: 12, color: KoalaColors.textTer)),
      );
}

// ═══════════════════════════════════════════════════════════
// Carousel slide — bundled asset background, dark gradient,
// bottom-left tagline. Instant first paint (no async load).
// ═══════════════════════════════════════════════════════════
class _CarouselSlide extends StatelessWidget {
  final String assetPath;
  const _CarouselSlide({required this.assetPath});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }
}
