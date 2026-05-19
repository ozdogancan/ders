// Koala Pro paywall — SnapHome-inspired clean redesign.
//
// Top-to-bottom layout:
//   • Hero image area (gradient fallback, top-left X, top-right "Geri Yükle")
//   • Title + 4 feature bullets with crown icons
//   • "Ücretsiz Denemeyi Etkinleştir" toggle row
//   • Two plan cards (weekly with free trial, yearly with savings badge)
//   • Primary CTA "Devam et" (#FF5A5F)
//   • Footer: cancel-anytime line + tiny links row
//
// Billing path identical to prior version: BillingService.getOfferings() →
// substring match ('week'/'month'/'year') → BillingService.purchase().

import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/koala_tokens.dart';
import '../../services/analytics_service.dart';
import '../../services/billing_service.dart';
import '../../services/usage_limit_service.dart';

enum _PlanKind { weekly, yearly }

// SnapHome-inspired palette.
const _kKoral = Color(0xFFFF5A5F);
const _kKoralSoft = Color(0xFFFFF1F2);
const _kBorder = Color(0xFFE5E7EB);
const _kGradTop = Color(0xFF6C63FF);
const _kGradBot = Color(0xFF9B5CFF);

class PaywallScreen extends StatefulWidget {
  final String trigger;
  const PaywallScreen({super.key, required this.trigger});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  _PlanKind _selected = _PlanKind.weekly;
  bool _trialEnabled = true;
  bool _purchasing = false;

  // TR pricing fallback (used until offerings load).
  static const _weeklyPrice = '₺149,99';
  static const _yearlyPrice = '₺999,99';
  // ₺999,99 / 52 ≈ ₺19,23
  static const _yearlyPerWeek = '₺19,23';

  @override
  void initState() {
    super.initState();
    Analytics.log('paywall_opened', {'trigger': widget.trigger});
  }

  Future<void> _onPurchase() async {
    if (_purchasing) return;
    setState(() => _purchasing = true);
    Analytics.log('paywall_cta_tapped', {
      'trigger': widget.trigger,
      'plan': _selected.name,
      'trial': _trialEnabled,
    });
    try {
      final pkgs = await BillingService.getOfferings();
      Package? match;
      for (final p in pkgs) {
        final id = p.storeProduct.identifier.toLowerCase();
        if (_selected == _PlanKind.weekly && id.contains('week')) match = p;
        if (_selected == _PlanKind.yearly && id.contains('year')) match = p;
        // Fallback to monthly if yearly not configured.
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
            style: FilledButton.styleFrom(backgroundColor: _kKoral),
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
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHero(context),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _buildTitleAndBullets(),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildTrialToggle(),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildPlanCards(),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildCta(),
              ),
              const SizedBox(height: 14),
              _buildFooter(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Hero ────────────────────────────────────────────────
  Widget _buildHero(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final h = MediaQuery.of(context).size.height * 0.40;
    // TODO: replace with Gemini-generated cozy interior hero
    // (asset path: assets/images/koala_pro_hero.jpg — not present yet,
    // using gradient fallback for now).
    return SizedBox(
      height: h,
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_kGradTop, _kGradBot],
              ),
            ),
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Image.asset(
                'assets/images/koala_logo.webp',
                width: 120,
                height: 120,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.workspace_premium,
                  color: Colors.white,
                  size: 88,
                ),
              ),
            ),
          ),
          Positioned(
            top: topPad + 12,
            left: 16,
            child: _CircleIconButton(
              icon: Icons.close,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            top: topPad + 14,
            right: 16,
            child: GestureDetector(
              onTap: _onRestore,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
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
          ),
        ],
      ),
    );
  }

  // ─── Title + bullets ────────────────────────────────────
  Widget _buildTitleAndBullets() {
    const bullets = [
      'Sınırsız Koala AI tasarım sohbeti',
      'Mekanını AI ile sınırsız dönüştür',
      'Profesyonel tasarımları kendi mekanına uygula',
      'Evlumba uzmanlarından öncelikli, hızlı yanıt',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Pro Erişimi',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: KoalaColors.text,
            letterSpacing: -0.5,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 16),
        for (final b in bullets) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.workspace_premium, color: _kKoral, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  b,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: KoalaColors.text,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  // ─── Trial toggle row ───────────────────────────────────
  Widget _buildTrialToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: KoalaColors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Ücretsiz Denemeyi Etkinleştir',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: KoalaColors.text,
              ),
            ),
          ),
          Switch(
            value: _trialEnabled,
            onChanged: (v) => setState(() {
              _trialEnabled = v;
              if (v) _selected = _PlanKind.weekly;
            }),
            activeThumbColor: Colors.white,
            activeTrackColor: _kKoral,
          ),
        ],
      ),
    );
  }

  // ─── Plan cards ─────────────────────────────────────────
  Widget _buildPlanCards() {
    return Column(
      children: [
        _PlanCard(
          selected: _selected == _PlanKind.weekly,
          onTap: () => setState(() => _selected = _PlanKind.weekly),
          topLabel: _trialEnabled ? '7 GÜN ÜCRETSİZ' : 'HAFTALIK ERİŞİM',
          subLabel: _trialEnabled
              ? 'sonra haftalık ücretlendirilir'
              : 'haftalık yenilenir',
          priceMain: _weeklyPrice,
          priceUnit: '/ hafta',
        ),
        const SizedBox(height: 22),
        _PlanCard(
          selected: _selected == _PlanKind.yearly,
          onTap: () => setState(() => _selected = _PlanKind.yearly),
          topLabel: 'YILLIK ERİŞİM',
          subLabel: '$_yearlyPrice / yıl',
          priceMain: _yearlyPerWeek,
          priceUnit: '/ haftada',
          badge: '%70 tasarruf et',
        ),
      ],
    );
  }

  // ─── CTA ────────────────────────────────────────────────
  Widget _buildCta() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: _purchasing ? null : _onPurchase,
        style: FilledButton.styleFrom(
          backgroundColor: _kKoral,
          disabledBackgroundColor: _kKoral.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
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
    );
  }

  // ─── Footer ─────────────────────────────────────────────
  Widget _buildFooter() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shield_outlined,
                size: 14, color: KoalaColors.greenAlt),
            const SizedBox(width: 6),
            Text(
              'İstediğiniz zaman iptal edin',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: KoalaColors.textMed,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _FooterLink(
              label: 'Gizlilik',
              onTap: () => _openLink('https://www.koalatutor.com/privacy'),
            ),
            const _FooterDot(),
            _FooterLink(
              label: 'Kullanım Şartları',
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
          color: Colors.white.withValues(alpha: 0.28),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
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
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(
              color: selected ? _kKoralSoft : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? _kKoral : _kBorder,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        topLabel,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: KoalaColors.text,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subLabel,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: KoalaColors.textMed,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      priceMain,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: KoalaColors.text,
                        letterSpacing: -0.4,
                      ),
                    ),
                    Text(
                      priceUnit,
                      style: const TextStyle(
                        fontSize: 11.5,
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
              top: -12,
              left: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _kKoral,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.4,
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
          fontSize: 11.5,
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
