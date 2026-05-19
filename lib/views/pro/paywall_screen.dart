// Koala Pro paywall — feature-rich edition.
//
// Top-to-bottom layout:
//   • CustomScrollView with collapsing SliverAppBar hero (gradient + logo)
//   • Headline block ("Tüm potansiyeli aç")
//   • Feature highlights card (5 crown bullets, revised copy)
//   • Free vs Pro comparison table
//   • Free trial toggle row
//   • Two pricing tiles (weekly + yearly w/ savings badge)
//   • Trust row (3 micro-icons)
//   • FAQ ExpansionTile section (4 items)
//   • Sticky bottom CTA (BottomAppBar w/ shimmer via flutter_animate)
//   • Footer links row
//
// Billing path identical to prior version: BillingService.getOfferings() →
// substring match ('week'/'month'/'year') → BillingService.purchase().

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
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

  // Live prices from RevenueCat offerings (fallback shown until loaded).
  String _weeklyPrice = '₺149,99';
  String _yearlyPrice = '₺999,99';
  // ₺999,99 / 52 ≈ ₺19,23
  String _yearlyPerWeek = '₺19,23';

  @override
  void initState() {
    super.initState();
    Analytics.log('paywall_opened', {'trigger': widget.trigger});
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    try {
      final pkgs = await BillingService.getOfferings();
      for (final p in pkgs) {
        final id = p.storeProduct.identifier.toLowerCase();
        if (id.contains('week')) {
          _weeklyPrice = p.storeProduct.priceString;
        } else if (id.contains('year')) {
          _yearlyPrice = p.storeProduct.priceString;
          final price = p.storeProduct.price;
          if (price > 0) {
            final perWeek = price / 52.0;
            _yearlyPerWeek =
                '${p.storeProduct.currencyCode} ${perWeek.toStringAsFixed(2)}';
          }
        }
      }
      if (mounted) setState(() {});
    } catch (_) {
      // Keep fallbacks.
    }
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
      extendBodyBehindAppBar: false,
      body: CustomScrollView(
        slivers: [
          _buildSliverHero(context),
          SliverList(
            delegate: SliverChildListDelegate.fixed([
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _buildHeadline(),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildFeatureCard(),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildComparisonTable(),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildTrialToggle(),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildPlanCards(),
              ),
              const SizedBox(height: 26),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildTrustRow(),
              ),
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildFaqSection(),
              ),
              const SizedBox(height: 28),
              // Spacer for sticky bottom CTA.
              const SizedBox(height: 120),
            ]),
          ),
        ],
      ),
      bottomNavigationBar: _StickyBottomCta(
        trialEnabled: _trialEnabled,
        purchasing: _purchasing,
        onPressed: _onPurchase,
        onFooterLinkTap: (kind) {
          switch (kind) {
            case _FooterKind.privacy:
              _openLink('https://www.koalatutor.com/privacy');
              break;
            case _FooterKind.terms:
              _openLink('https://www.koalatutor.com/terms');
              break;
            case _FooterKind.restore:
              _onRestore();
              break;
          }
        },
      ),
    );
  }

  // ─── Sliver hero ─────────────────────────────────────────
  Widget _buildSliverHero(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      backgroundColor: _kGradTop,
      elevation: 0,
      automaticallyImplyLeading: false,
      title: const Text(
        'Pro Erişimi',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      centerTitle: true,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: _CircleIconButton(
          icon: Icons.close,
          onTap: () => Navigator.of(context).pop(),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
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
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_kGradTop, _kGradBot],
            ),
          ),
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
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
      ),
    );
  }

  // ─── Headline ────────────────────────────────────────────
  Widget _buildHeadline() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tüm potansiyeli aç',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: KoalaColors.text,
            letterSpacing: -0.6,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Koala'nın sınırsız tasarım gücüyle hayalindeki mekana ulaş.",
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: KoalaColors.textMed,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // ─── Feature highlights card ─────────────────────────────
  Widget _buildFeatureCard() {
    const features = <_FeatureItem>[
      _FeatureItem(
        title: 'Sınırsız Koala AI sohbet',
        desc: 'Tasarım danışmanından gün boyu fikir al, kısıtlama yok.',
      ),
      _FeatureItem(
        title: 'Mekanını AI ile dönüştür',
        desc:
            'Fotoğrafından sınırsız stil — modern, İskandinav, bohem, klasik.',
      ),
      _FeatureItem(
        title: 'Profesyonellerle anında bağlan',
        desc:
            'Evlumba tasarımcılarından öncelikli, hızlı dönüş garantisi.',
      ),
      _FeatureItem(
        title: 'Tasarımları kendi mekanında dene',
        desc:
            'Beğendiğin tasarımı kendi odana AI ile uygula, gerçeğe dönüştür.',
      ),
      _FeatureItem(
        title: 'Akıllı tarz keşfi',
        desc:
            'Sana özel öneri sistemi, sınırsız swipe, ilham hiç bitmesin.',
      ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pro ile ne kazanırsın?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: KoalaColors.text,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 14),
          for (final f in features) _FeatureRow(item: f),
        ],
      ),
    );
  }

  // ─── Comparison table ────────────────────────────────────
  Widget _buildComparisonTable() {
    const rows = <_ComparisonRow>[
      _ComparisonRow(
        label: 'Koala AI sohbet',
        free: 'Günde 3 mesaj',
        pro: 'Sınırsız',
      ),
      _ComparisonRow(
        label: 'Mekan AI tasarım',
        free: 'Ayda 2',
        pro: 'Sınırsız',
      ),
      _ComparisonRow(
        label: 'Evlumba tasarımcılar',
        free: '1 yanıt',
        pro: 'Öncelikli & sınırsız',
      ),
      _ComparisonRow(
        label: 'Tarz keşfi (swipe)',
        free: 'Sınırsız',
        pro: 'Sınırsız + AI öneri',
      ),
      _ComparisonRow(
        label: 'Reklamlar',
        free: 'Var',
        pro: 'Yok',
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          // Header.
          Row(
            children: const [
              Expanded(flex: 5, child: SizedBox()),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    'Ücretsiz',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: KoalaColors.textMed,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _kKoralSoft,
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      'Pro',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _kKoral,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 1, color: _kBorder),
          for (int i = 0; i < rows.length; i++) ...[
            _ComparisonRowWidget(
              row: rows[i],
              isLast: i == rows.length - 1,
            ),
            if (i != rows.length - 1)
              const Divider(height: 1, color: _kBorder),
          ],
        ],
      ),
    );
  }

  // ─── Trial toggle row ────────────────────────────────────
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

  // ─── Plan cards ──────────────────────────────────────────
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

  // ─── Trust row ───────────────────────────────────────────
  Widget _buildTrustRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: const [
        _TrustChip(icon: Icons.shield_outlined, label: 'Güvenli ödeme'),
        _TrustChip(icon: Icons.refresh, label: 'İstediğin zaman iptal'),
        _TrustChip(icon: Icons.star_outline, label: '10.000+ kullanıcı'),
      ],
    );
  }

  // ─── FAQ section ─────────────────────────────────────────
  Widget _buildFaqSection() {
    const faqs = <_FaqItem>[
      _FaqItem(
        q: 'Aboneliğimi nasıl iptal ederim?',
        a:
            'App Store / Play Store ayarlarından tek tıkla istediğin an iptal edebilirsin.',
      ),
      _FaqItem(
        q: 'Ücretsiz deneme nasıl çalışır?',
        a:
            'İlk 7 gün boyunca tüm Pro özelliklere erişimin var. Dilersen kayıtlı kartın olmadan iptal edebilirsin.',
      ),
      _FaqItem(
        q: 'Ödeme bilgilerim güvende mi?',
        a:
            "Tüm ödemeler Apple ve Google'ın güvenli ödeme sistemleriyle yapılır. Koala kart bilgilerini saklamaz.",
      ),
      _FaqItem(
        q: 'Pro üyeliğim ne zaman başlar?',
        a: 'Deneme bitiminde otomatik başlar. Erken iptal edersen sıfır ücret.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Sıkça sorulanlar',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: KoalaColors.text,
              letterSpacing: -0.3,
            ),
          ),
        ),
        for (final f in faqs) _FaqTile(item: f),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Helper data classes
// ═══════════════════════════════════════════════════════════
class _FeatureItem {
  final String title;
  final String desc;
  const _FeatureItem({required this.title, required this.desc});
}

class _ComparisonRow {
  final String label;
  final String free;
  final String pro;
  const _ComparisonRow({
    required this.label,
    required this.free,
    required this.pro,
  });
}

class _FaqItem {
  final String q;
  final String a;
  const _FaqItem({required this.q, required this.a});
}

enum _FooterKind { privacy, terms, restore }

// ═══════════════════════════════════════════════════════════
// Helper widgets
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

class _FeatureRow extends StatelessWidget {
  final _FeatureItem item;
  const _FeatureRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.workspace_premium, color: _kKoral, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: KoalaColors.text,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.desc,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: KoalaColors.textMed,
                    height: 1.35,
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

class _ComparisonRowWidget extends StatelessWidget {
  final _ComparisonRow row;
  final bool isLast;
  const _ComparisonRowWidget({required this.row, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final proBg = BoxDecoration(
      color: _kKoralSoft,
      borderRadius: BorderRadius.only(
        bottomRight: isLast ? const Radius.circular(20) : Radius.zero,
      ),
    );
    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Text(
                row.label,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: KoalaColors.text,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
              child: Text(
                row.free,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: KoalaColors.textTer,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: DecoratedBox(
              decoration: proBg,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                child: Text(
                  row.pro,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _kKoral,
                  ),
                ),
              ),
            ),
          ),
        ],
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

class _TrustChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _TrustChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22, color: _kKoral),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: KoalaColors.textMed,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _FaqTile extends StatelessWidget {
  final _FaqItem item;
  const _FaqTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            iconColor: _kKoral,
            collapsedIconColor: KoalaColors.textMed,
            title: Text(
              item.q,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: KoalaColors.text,
              ),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  item.a,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: KoalaColors.textMed,
                    height: 1.45,
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

class _StickyBottomCta extends StatelessWidget {
  final bool trialEnabled;
  final bool purchasing;
  final VoidCallback onPressed;
  final ValueChanged<_FooterKind> onFooterLinkTap;

  const _StickyBottomCta({
    required this.trialEnabled,
    required this.purchasing,
    required this.onPressed,
    required this.onFooterLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = trialEnabled ? '7 Gün Ücretsiz Başlat' : "Pro'ya Yükselt";
    return Container(
      decoration: BoxDecoration(
        color: KoalaColors.bg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: Stack(
                    children: [
                      FilledButton(
                        onPressed: purchasing ? null : onPressed,
                        style: FilledButton.styleFrom(
                          backgroundColor: _kKoral,
                          disabledBackgroundColor:
                              _kKoral.withValues(alpha: 0.6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: purchasing
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                label,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.2,
                                ),
                              ),
                      ),
                      if (!purchasing)
                        IgnorePointer(
                          child: Animate(
                            onPlay: (c) => c.repeat(),
                            effects: [
                              ShimmerEffect(
                                duration: 1800.ms,
                                color: Colors.white.withValues(alpha: 0.45),
                                size: 0.6,
                              ),
                            ],
                            child: const SizedBox.expand(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'İstediğin zaman iptal edebilirsin',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: KoalaColors.textMed,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _FooterLink(
                    label: 'Gizlilik',
                    onTap: () => onFooterLinkTap(_FooterKind.privacy),
                  ),
                  const _FooterDot(),
                  _FooterLink(
                    label: 'Kullanım Şartları',
                    onTap: () => onFooterLinkTap(_FooterKind.terms),
                  ),
                  const _FooterDot(),
                  _FooterLink(
                    label: 'Geri Yükle',
                    onTap: () => onFooterLinkTap(_FooterKind.restore),
                  ),
                ],
              ),
            ],
          ),
        ),
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
