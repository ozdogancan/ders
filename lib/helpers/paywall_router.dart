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

import 'package:flutter/material.dart';

import '../services/analytics_service.dart';
import '../views/pro/paywall_screen.dart';

Future<void> showPaywall(
  BuildContext context, {
  required String trigger,
}) async {
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
}
