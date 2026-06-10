// Koala Pro paywall — purple, single-page (no scroll) redesign.
//
// Layout (top-to-bottom, fits ~770dp):
//   • Top bar (close X + Geri Yükle pill)
//   • Auto-rotating 3-slide value-prop carousel hero (~180dp)
//   • Title + tiny subtitle
//   • Compact value-prop bullet list
//   • Optional trial toggle (hidden if trial already used)
//   • Plan tiles (Haftalık / [Aylık] / Yıllık) — Aylık only if RC has it
//   • Purple CTA "Devam et"
//   • Cancel-anytime line + footer links
//
// Pricing path (P0.4 + P0.5 audit fix):
//   • On mount, fetch RevenueCat Offerings → resolve weekly/monthly/yearly
//     Packages via explicit Package.identifier map (NO substring matching).
//   • Render Package.storeProduct.priceString (already localized) everywhere.
//   • Savings % computed from real numeric prices, not hardcoded.
//   • On CTA tap, look up the resolved Package by selected plan — if missing,
//     show snackbar and DO NOT fall back to a different plan.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/theme/koala_ds.dart';
import '../../helpers/paywall_router.dart';
import '../legal_sheet.dart';
import '../../providers/pro_status_provider.dart';
import '../../services/analytics_service.dart';
import '../../services/billing_service.dart';
import '../../services/usage_limit_service.dart';

enum _PlanKind { weekly, monthly, yearly }

// Koala brand purple palette — V2 DS alias'ları (kaçak mor yok).
const _kPurple = KoalaDS.accent;
const _kPurpleSoft = KoalaDS.accentTint;
const _kBorder = KoalaDS.line;

// Carousel hero slides — bundled assets for instant first paint.
const _kSlideAssets = <String>[
  'assets/pro/hero_1.webp',
  'assets/pro/hero_2.webp',
  'assets/pro/hero_3.webp',
];

// Explicit Package.identifier candidates per plan kind. The first entry of each
// list is RevenueCat's built-in "Standard" package identifier; the rest are
// custom identifiers we may have used historically. Match against
// `Package.identifier` (RC package id) — NOT `storeProduct.identifier`.
const _kPackageIds = <_PlanKind, List<String>>{
  _PlanKind.weekly: [r'$rc_weekly', 'koala_pro_weekly', 'pro_weekly', 'weekly'],
  _PlanKind.monthly: [r'$rc_monthly', 'koala_pro_monthly', 'pro_monthly', 'monthly'],
  _PlanKind.yearly: [r'$rc_annual', 'koala_pro_yearly', 'pro_yearly', 'yearly', 'annual'],
};

class PaywallScreen extends ConsumerStatefulWidget {
  final String trigger;
  const PaywallScreen({super.key, required this.trigger});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  _PlanKind _selected = _PlanKind.weekly;
  bool _trialEnabled = true;
  bool _trialUsed = false;
  bool _purchasing = false;

  // Carousel state.
  final PageController _heroController = PageController(initialPage: 0);
  int _heroIndex = 0;
  Timer? _heroTimer;
  bool _precached = false;

  // Resolved RevenueCat packages (null until offerings load, or if RC does not
  // expose that plan kind). The UI shows a small shimmer placeholder while
  // these are null, and gracefully hides plan tiles that never resolve.
  Package? _weeklyPkg;
  Package? _monthlyPkg;
  Package? _yearlyPkg;
  bool _offeringsLoaded = false;
  // RC unavailable (web, init failed, no offering) → use display-only fallback
  // prices so the user is never staring at "—". These are estimates — the
  // backend is the source of truth for actual charge amounts.
  bool _useFallbackPrices = false;
  Timer? _offeringsTimeout;

  // Fallback price strings — kept in sync with Play Console SKUs as of v1.0.135.
  static const String _kFallbackWeekly = '₺79,99';
  static const String _kFallbackYearly = '₺999,99';

  @override
  void initState() {
    super.initState();
    Analytics.log('paywall_opened', {'trigger': widget.trigger});
    // Defensively check trial_used (field may not exist on ProStatus yet).
    try {
      final asyncPs = ref.read(proStatusProvider);
      final ps = asyncPs.value;
      if (ps != null) {
        final dynamic dps = ps;
        final used = dps.trialUsed;
        if (used is bool) _trialUsed = used;
      }
    } catch (_) {/* field absent → leave _trialUsed=false */}
    _trialEnabled = !_trialUsed;

    // Kick off RC offering fetch (non-blocking).
    _loadOfferings();

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

  Future<void> _loadOfferings() async {
    // Safety net: if RC never resolves (web / init failure / network), flip
    // to fallback prices after 3s so the UI is never empty.
    _offeringsTimeout = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (!_offeringsLoaded ||
          (_weeklyPkg == null && _yearlyPkg == null && _monthlyPkg == null)) {
        setState(() {
          _offeringsLoaded = true;
          _useFallbackPrices = true;
        });
      }
    });
    try {
      final pkgs = await BillingService.getOfferings();
      if (!mounted) return;
      // Diagnostic: log identifiers + priceStrings so we can debug missing
      // prices in production (priceString empty vs package missing).
      for (final p in pkgs) {
        debugPrint(
          '[paywall] package id=${p.identifier} '
          'productId=${p.storeProduct.identifier} '
          'price="${p.storeProduct.priceString}"',
        );
      }
      setState(() {
        _weeklyPkg = _findPackage(pkgs, _PlanKind.weekly);
        _monthlyPkg = _findPackage(pkgs, _PlanKind.monthly);
        _yearlyPkg = _findPackage(pkgs, _PlanKind.yearly);
        _offeringsLoaded = true;
        // If RC returned nothing useful, fall back to estimate strings.
        final wMissing = _weeklyPkg == null ||
            (_weeklyPkg?.storeProduct.priceString ?? '').isEmpty;
        final yMissing = _yearlyPkg == null ||
            (_yearlyPkg?.storeProduct.priceString ?? '').isEmpty;
        if (wMissing && yMissing) {
          _useFallbackPrices = true;
        }
        // If user's currently-selected plan kind is unavailable, fall back
        // visually to the first one that resolved — but never silently swap
        // an unrelated billing cycle during purchase. This is just initial UI.
        if (_packageFor(_selected) == null) {
          if (_weeklyPkg != null) {
            _selected = _PlanKind.weekly;
          } else if (_yearlyPkg != null) {
            _selected = _PlanKind.yearly;
          } else if (_monthlyPkg != null) {
            _selected = _PlanKind.monthly;
          }
        }
      });
    } catch (e) {
      debugPrint('[paywall] loadOfferings failed: $e');
      if (mounted) {
        setState(() {
          _offeringsLoaded = true;
          _useFallbackPrices = true;
        });
      }
    }
  }

  static Package? _findPackage(List<Package> pkgs, _PlanKind kind) {
    final candidates = _kPackageIds[kind] ?? const <String>[];
    for (final id in candidates) {
      for (final p in pkgs) {
        if (p.identifier == id) return p;
      }
    }
    return null;
  }

  Package? _packageFor(_PlanKind kind) {
    switch (kind) {
      case _PlanKind.weekly:
        return _weeklyPkg;
      case _PlanKind.monthly:
        return _monthlyPkg;
      case _PlanKind.yearly:
        return _yearlyPkg;
    }
  }

  /// Parse a numeric value out of a localized priceString like "₺79,99",
  /// "$9.99", or "9,99 €". Returns null on failure.
  static double? _parsePrice(String? s) {
    if (s == null || s.isEmpty) return null;
    // Keep digits, comma, dot, and minus.
    final cleaned = s.replaceAll(RegExp(r'[^0-9.,-]'), '');
    if (cleaned.isEmpty) return null;
    // Locales like "1.234,56" (TR) → drop thousands dot, swap comma to dot.
    // Locales like "1,234.56" (US) → drop thousands comma.
    String normalized = cleaned;
    final lastComma = normalized.lastIndexOf(',');
    final lastDot = normalized.lastIndexOf('.');
    if (lastComma > lastDot) {
      // Comma is the decimal separator.
      normalized = normalized.replaceAll('.', '').replaceAll(',', '.');
    } else {
      // Dot is the decimal separator (or no separators at all).
      normalized = normalized.replaceAll(',', '');
    }
    return double.tryParse(normalized);
  }

  /// Compute savings of yearly vs weekly as integer percent. Null if either
  /// price is unparseable.
  int? _yearlySavingsPercent() {
    final w = _parsePrice(_weeklyPkg?.storeProduct.priceString);
    final y = _parsePrice(_yearlyPkg?.storeProduct.priceString);
    if (w == null || y == null || w <= 0 || y <= 0) return null;
    final ratio = 1.0 - (y / (w * 52.0));
    if (ratio <= 0) return null;
    return (ratio * 100).round();
  }

  /// "Per week" price string for the yearly plan, computed from real price.
  /// Returns the same currency symbol the priceString already uses.
  String? _yearlyPerWeekText() {
    final s = _yearlyPkg?.storeProduct.priceString;
    final y = _parsePrice(s);
    if (s == null || y == null || y <= 0) return null;
    final perWeek = y / 52.0;
    // Extract non-numeric currency markers to re-decorate. Crude but safe.
    final currency = s.replaceAll(RegExp(r'[0-9.,\s-]'), '');
    // Use locale-ish formatting: 2 decimals, comma if priceString used comma.
    final usesComma = s.contains(',') &&
        (s.lastIndexOf(',') > s.lastIndexOf('.'));
    final formatted = perWeek.toStringAsFixed(2);
    final localized = usesComma ? formatted.replaceAll('.', ',') : formatted;
    // Re-apply currency: prefix if it appeared before any digit, else suffix.
    final firstDigit = s.indexOf(RegExp(r'[0-9]'));
    final currencyBefore =
        firstDigit > 0 && currency.isNotEmpty;
    if (currency.isEmpty) return localized;
    return currencyBefore ? '$currency$localized' : '$localized $currency';
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
    _offeringsTimeout?.cancel();
    _heroController.dispose();
    super.dispose();
  }

  Future<void> _onPurchase() async {
    if (_purchasing) return;
    final match = _packageFor(_selected);
    if (match == null) {
      // No silent fallback — fail loud per audit P0.5.
      final msg = _useFallbackPrices
          ? 'Pro satın alımı için Koala uygulamasını telefonundan aç'
          : 'Bu plan şu an mevcut değil';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _purchasing = true);
    Analytics.log('paywall_cta_tapped', {
      'trigger': widget.trigger,
      'plan': _selected.name,
      'package_id': match.identifier,
      'trial': _trialEnabled && !_trialUsed,
    });
    try {
      final ok = await BillingService.purchase(match);
      if (!mounted) return;
      if (ok) {
        await UsageLimitService.resetAll();
        notePaywallConverted(widget.trigger);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pro üyeliğin aktif!',
                style: TextStyle(fontWeight: FontWeight.w600)),
            backgroundColor: KoalaDS.cta,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      } else {
        if (BillingService.lastWasCancellation) return;
        await _showFailureDialog(detail: BillingService.lastErrorMessage);
      }
    } catch (e) {
      await _showFailureDialog(detail: e.toString());
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _showFailureDialog({String? detail}) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KoalaDS.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KoalaR.lg)),
        title: const Text('Satın alma tamamlanamadı', style: KoalaType.h3),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bir aksaklık oldu. Şunları denersen yardımcı olabilir:',
              style: TextStyle(fontSize: 14, color: KoalaDS.inkSoft),
            ),
            const SizedBox(height: 8),
            const Text(
              '• Cihazda Google Play hesabınla giriş yap\n'
              '• Uygulamayı Play Store üzerinden güncelle/yeniden kur\n'
              '• İnternet bağlantını kontrol et\n'
              '• Kart bilgilerin Play Store hesabında ekli mi bak',
              style: TextStyle(fontSize: 13, color: KoalaDS.inkSoft, height: 1.5),
            ),
            if (detail != null && detail.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: KoalaDS.surfaceMuted,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Teknik detay: $detail',
                  style: const TextStyle(
                    fontSize: 11,
                    color: KoalaDS.inkFaint,
                  ),
                ),
              ),
            ],
          ],
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaDS.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildHero(),
                            const SizedBox(height: 12),
                            _buildTitle(),
                            const SizedBox(height: 8),
                            _buildBulletsGrid(),
                            const SizedBox(height: 8),
                            if (!_trialUsed) ...[
                              _buildTrialToggle(),
                              const SizedBox(height: 8),
                            ],
                            _buildPlanCards(),
                            const Spacer(),
                            const SizedBox(height: 12),
                            _buildCta(),
                            const SizedBox(height: 10),
                            _buildFooter(),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ─── Hero (auto-rotating 3-slide value-prop carousel) ───
  Widget _buildHero() {
    return SizedBox(
      height: 170,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: _kPurple.withValues(alpha: 0.10),
              blurRadius: 28,
              offset: const Offset(0, 14),
              spreadRadius: -6,
            ),
            BoxShadow(
              color: KoalaDS.ink.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
              spreadRadius: -4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
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
                          color: KoalaDS.ink.withValues(alpha: 0.10),
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
                        color: KoalaDS.ink,
                      ),
                    ),
                  ),
                ),
              ),
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

  Widget _buildTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Pro Erişimi',
          textAlign: TextAlign.center,
          style: KoalaType.display3(),
        ),
        const SizedBox(height: 4),
        const Text(
          'AI tasarım, sınırsız ilham',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: KoalaDS.inkSoft,
          ),
        ),
      ],
    );
  }

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
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _kPurpleSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.workspace_premium,
                      color: _kPurple, size: 17),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    b,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: KoalaDS.ink,
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

  Widget _buildTrialToggle() {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _kPurpleSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Ücretsiz denemeyi etkinleştir',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: KoalaDS.ink,
              ),
            ),
          ),
          Transform.scale(
            scale: 0.85,
            child: Switch(
              value: _trialEnabled,
              onChanged: (v) => setState(() {
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

  Widget _buildPlanCards() {
    final canTrial = !_trialUsed && _trialEnabled;
    String? weeklyPrice = _weeklyPkg?.storeProduct.priceString;
    String? monthlyPrice = _monthlyPkg?.storeProduct.priceString;
    String? yearlyPrice = _yearlyPkg?.storeProduct.priceString;
    if (weeklyPrice == null || weeklyPrice.isEmpty) weeklyPrice = null;
    if (monthlyPrice == null || monthlyPrice.isEmpty) monthlyPrice = null;
    if (yearlyPrice == null || yearlyPrice.isEmpty) yearlyPrice = null;
    // Display-only fallback so the user is never staring at an em-dash.
    if (_useFallbackPrices) {
      weeklyPrice ??= _kFallbackWeekly;
      yearlyPrice ??= _kFallbackYearly;
    }
    final yearlyPerWeek = _yearlyPerWeekText() ??
        (_useFallbackPrices ? '₺19,23' : null);
    final savings = _yearlySavingsPercent() ??
        (_useFallbackPrices ? 76 : null);

    final tiles = <Widget>[];

    // Weekly tile (always shown — primary trial path). Skeleton until loaded.
    tiles.add(
      _PlanCard(
        selected: _selected == _PlanKind.weekly,
        onTap: () => setState(() {
          _selected = _PlanKind.weekly;
          _trialEnabled = !_trialUsed;
        }),
        topLabel: canTrial ? '7 Gün Tam Erişim' : 'Haftalık',
        subLabel: canTrial
            ? (weeklyPrice != null
                ? 'sonra $weeklyPrice/hafta'
                : 'sonra haftalık yenilenir')
            : 'haftalık yenilenir',
        priceMain: weeklyPrice,
        priceUnit: '/ hafta',
        priceLoaded: _offeringsLoaded,
        dimmed: _offeringsLoaded && _weeklyPkg == null && !_useFallbackPrices,
      ),
    );

    // Optional monthly tile — only if RC actually exposes a monthly package.
    if (_monthlyPkg != null) {
      tiles.add(const SizedBox(height: 12));
      tiles.add(
        _PlanCard(
          selected: _selected == _PlanKind.monthly,
          onTap: () => setState(() {
            _selected = _PlanKind.monthly;
            _trialEnabled = false;
          }),
          topLabel: 'Aylık',
          subLabel: monthlyPrice != null
              ? '$monthlyPrice / ay'
              : 'aylık yenilenir',
          priceMain: monthlyPrice,
          priceUnit: '/ ay',
          priceLoaded: _offeringsLoaded,
        ),
      );
    }

    tiles.add(const SizedBox(height: 12));
    tiles.add(
      _PlanCard(
        selected: _selected == _PlanKind.yearly,
        onTap: () => setState(() {
          _selected = _PlanKind.yearly;
          _trialEnabled = false;
        }),
        topLabel: 'Yıllık',
        subLabel: yearlyPrice != null ? '$yearlyPrice / yıl' : 'yıllık yenilenir',
        priceMain: yearlyPerWeek ?? yearlyPrice,
        priceUnit: yearlyPerWeek != null ? '/ hafta' : '/ yıl',
        priceLoaded: _offeringsLoaded,
        dimmed: _offeringsLoaded && _yearlyPkg == null && !_useFallbackPrices,
        badge: savings != null ? '%$savings TASARRUF' : 'EN AVANTAJLI',
      ),
    );

    return Column(children: tiles);
  }

  Widget _buildCta() {
    final button = Semantics(
      button: true,
      enabled: !_purchasing,
      label: _purchasing ? 'Satın alma işleniyor' : 'Devam et — Pro satın al',
      child: Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _kPurple.withValues(alpha: 0.34),
            blurRadius: 24,
            offset: const Offset(0, 10),
            spreadRadius: -4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: KoalaDS.accentGradient,
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
      ),
    );
    if (_purchasing) return button;
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
                color: KoalaDS.inkFaint,
              ),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shield_outlined,
                size: 13, color: KoalaDS.cta),
            const SizedBox(width: 6),
            Text(
              'İstediğin zaman iptal',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: KoalaDS.inkSoft,
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
              onTap: () => showLegalSheet(context, LegalDoc.privacy),
            ),
            const _FooterDot(),
            _FooterLink(
              label: 'Şartlar',
              onTap: () => showLegalSheet(context, LegalDoc.terms),
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
          boxShadow: [
            BoxShadow(
              color: KoalaDS.ink.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon, color: KoalaDS.ink, size: 20),
      ),
    );
  }
}


class _PlanCard extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final String topLabel;
  final String subLabel;
  final String? priceMain;
  final String priceUnit;
  final String? badge;
  final bool priceLoaded;
  final bool dimmed;

  const _PlanCard({
    required this.selected,
    required this.onTap,
    required this.topLabel,
    required this.subLabel,
    required this.priceMain,
    required this.priceUnit,
    this.badge,
    this.priceLoaded = true,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final priceLabel = priceMain != null
        ? '$priceMain $priceUnit'
        : 'Fiyat yükleniyor';
    return Semantics(
      button: true,
      selected: selected,
      enabled: !dimmed,
      label: '$topLabel, $subLabel, $priceLabel'
          '${badge != null ? ', $badge' : ''}',
      excludeSemantics: false,
      child: Opacity(
      opacity: dimmed ? 0.45 : 1.0,
      child: GestureDetector(
        onTap: dimmed ? null : onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
              decoration: BoxDecoration(
                color: selected ? _kPurpleSoft : KoalaDS.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected ? _kPurple : _kBorder,
                  width: selected ? 1.8 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: selected
                        ? _kPurple.withValues(alpha: 0.16)
                        : KoalaDS.ink.withValues(alpha: 0.05),
                    blurRadius: selected ? 18 : 12,
                    offset: const Offset(0, 6),
                    spreadRadius: -4,
                  ),
                ],
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
                            color: KoalaDS.ink,
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
                            color: KoalaDS.inkSoft,
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
                      if (priceMain != null)
                        Text(
                          priceMain!,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: KoalaDS.ink,
                            letterSpacing: -0.4,
                          ),
                        )
                      else
                        _PriceSkeleton(loaded: priceLoaded),
                      Text(
                        priceUnit,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: KoalaDS.inkSoft,
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
                left: 16,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: KoalaDS.accentGradient,
                    borderRadius: BorderRadius.circular(KoalaR.pill),
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
      ),
      ),
    );
  }
}

/// Small shimmer placeholder shown in the price slot until RC offerings load.
/// When `loaded` becomes true but priceMain is still null (offering missing),
/// renders an em dash so the UI is never empty.
class _PriceSkeleton extends StatelessWidget {
  final bool loaded;
  const _PriceSkeleton({required this.loaded});

  @override
  Widget build(BuildContext context) {
    if (loaded) {
      return const Text(
        '—',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: KoalaDS.inkFaint,
          letterSpacing: -0.4,
        ),
      );
    }
    final box = Container(
      width: 64,
      height: 18,
      decoration: BoxDecoration(
        color: _kPurpleSoft,
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return Animate(
      onPlay: (c) => c.repeat(),
      effects: [
        ShimmerEffect(
          duration: const Duration(milliseconds: 1400),
          color: Colors.white.withValues(alpha: 0.7),
        ),
      ],
      child: box,
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
          color: KoalaDS.inkFaint,
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
            style: TextStyle(fontSize: 12, color: KoalaDS.inkFaint)),
      );
}

// ═══════════════════════════════════════════════════════════
// Carousel slide — bundled asset background, instant first paint.
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
