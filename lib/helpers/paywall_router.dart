// Paywall router — single entry point for opening the Pro paywall from
// anywhere in the app. Logs the trigger to Analytics for funnel analysis.
//
// Trigger taxonomy (keep in sync with paywall analytics):
//   restyle_quota         — user hit the 2/month restyle cap
//   save_quota            — user hit the 3 lifetime saved-items cap
//   chat_quota            — user hit the 5/day chat cap
//   designer_dm_quota     — user tried a 2nd DM to same designer
//   hi_res_download       — user requested 4K download (free → blocked)
//   multi_variant         — user requested 2nd/3rd variant
//   realize_request       — user opened "gerçekleştir" pro flow
//   manual_upgrade        — generic upgrade button
//   profile_upgrade_button — Pro tile / pill in profile
//
// Guards added in P1.4:
//   • _flowGuard           — within a single user flow (e.g. wizard → restyle
//                            result) prevents the paywall from opening twice.
//                            Call resetFlowGuard() at the start of a new flow.
//   • _cooldownUntil       — once a paywall is dismissed without purchase, we
//                            suppress re-prompts for the next 30 minutes
//                            in-memory. App restart resets the cooldown.

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/analytics_service.dart';
import '../services/billing_service.dart';
import '../views/pro/paywall_screen.dart';

DateTime? _cooldownUntil;
bool _flowGuard = false;
bool _purchasedInLastShow = false;

/// Triggers that BYPASS both the cooldown and the flow guard. These are
/// explicit user gestures (tapping "Pro'ya Geç" / restore) where suppressing
/// the sheet would feel broken.
const Set<String> _kAlwaysShowTriggers = {
  'manual_upgrade',
  'profile_upgrade_button',
  'first_restyle_celebration',
  // Hard quota walls — the user has literally hit a gate and the CTA is the
  // only path forward. Suppressing these makes the button look broken.
  'swipe_quota_end',
  'quota_end',
  'daily_limit',
  'restyle_limit',
  'restyle_quota',
  'save_quota',
  'chat_quota',
};

/// Reset the per-flow guard. Call at the start of a wizard / new restyle so
/// the flow can legitimately show its own paywall once.
void resetPaywallFlowGuard() {
  _flowGuard = false;
}

/// True iff a paywall sheet is currently being suppressed by cooldown.
bool get isPaywallInCooldown =>
    _cooldownUntil != null && DateTime.now().isBefore(_cooldownUntil!);

/// Mark that a paywall was just dismissed without purchase. Starts the 30-min
/// cooldown. Called by `PaywallScreen` on dispose if no purchase happened.
void notePaywallDismissedNoPurchase(String trigger) {
  _cooldownUntil = DateTime.now().add(const Duration(minutes: 30));
  try {
    Analytics.log('paywall_dismissed_no_purchase', {
      'trigger': trigger,
      'cooldown_until': _cooldownUntil!.toIso8601String(),
    });
  } catch (_) {/* best-effort */}
}

/// Mark that the user purchased. Clears cooldown + guard so any post-purchase
/// flow (e.g. realize) is unblocked.
void notePaywallConverted(String trigger) {
  _cooldownUntil = null;
  _flowGuard = false;
  _purchasedInLastShow = true;
  try {
    Analytics.log('paywall_converted', {'trigger': trigger});
  } catch (_) {/* best-effort */}
}

Future<void> showPaywall(
  BuildContext context, {
  required String trigger,
}) async {
  // Magaza yapilandirilmamissa (ör. iOS'ta RevenueCat anahtari yok) paywall
  // HIC acilmaz: fiyat gosterip satin alamamak App Review reddi demektir
  // (2.1 / 3.1.1). Kibar bir "yakinda" mesaji goster ve cik.
  if (!BillingService.purchasesConfigured) {
    try {
      await Analytics.log('paywall_suppressed', {
        'trigger': trigger,
        'reason': 'billing_unconfigured',
      });
    } catch (_) {}
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('Koala Pro yakında!'),
          content: const Text(
            'Pro üyelik bu platformda çok yakında aktif olacak. '
            'Şimdilik Koala\'yı keşfetmeye devam edebilirsin.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
    }
    return;
  }

  // Explicit-gesture triggers always go through.
  final bypass = _kAlwaysShowTriggers.contains(trigger);

  if (!bypass) {
    if (_flowGuard) {
      try {
        await Analytics.log('paywall_suppressed', {
          'trigger': trigger,
          'reason': 'flow_guard',
        });
      } catch (_) {}
      return;
    }
    if (isPaywallInCooldown) {
      try {
        await Analytics.log('paywall_suppressed', {
          'trigger': trigger,
          'reason': 'cooldown',
        });
      } catch (_) {}
      return;
    }
  }

  _flowGuard = true;
  _purchasedInLastShow = false;

  try {
    await Analytics.log('paywall_shown', {'trigger': trigger});
  } catch (_) {
    /* analytics best-effort */
  }
  if (!context.mounted) return;
  await Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PaywallScreen(trigger: trigger),
    ),
  );

  // If no purchase happened, start the cooldown. PaywallScreen calls
  // notePaywallConverted on success — which flips _purchasedInLastShow.
  if (!_purchasedInLastShow) {
    notePaywallDismissedNoPurchase(trigger);
  }
}
