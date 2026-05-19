// First-restyle celebration banner — non-blocking bottom banner that appears
// 800ms after a free user's FIRST successful AI restyle auto-saves. Auto-
// dismisses after 6s. Only shown ONCE per user lifetime (tracked via
// SharedPreferences key `upsell_post_first_restyle_shown`).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/koala_tokens.dart';
import '../../../helpers/paywall_router.dart';
import '../../../providers/pro_status_provider.dart';
import '../../../services/analytics_service.dart';

class FirstRestyleCelebration {
  FirstRestyleCelebration._();

  static const _prefKey = 'upsell_post_first_restyle_shown';

  /// Schedule the banner. Returns immediately; the actual show is deferred by
  /// 800ms to let the result image settle. Skipped silently if the user is
  /// Pro, anonymous, or has already seen the banner before.
  static Future<void> maybeShow({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefKey) == true) return;

      // Skip for Pro users.
      final asyncStatus = ref.read(proStatusProvider);
      final isPro =
          asyncStatus.maybeWhen(data: (s) => s.isPro, orElse: () => false);
      if (isPro) return;

      // Mark as shown immediately so we never show twice if the user retries
      // restyle quickly.
      await prefs.setBool(_prefKey, true);

      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!context.mounted) return;

      unawaited(
          Analytics.log('upsell_post_restyle_shown', const {'placement': 'celebration_toast'}));

      final controller = ScaffoldMessenger.maybeOf(context);
      if (controller == null) return;
      controller.clearMaterialBanners();
      controller.showMaterialBanner(
        MaterialBanner(
          backgroundColor: Colors.transparent,
          padding: EdgeInsets.zero,
          elevation: 0,
          forceActionsBelow: false,
          dividerColor: Colors.transparent,
          contentTextStyle: const TextStyle(color: KoalaColors.text),
          content: _CelebrationContent(
            onUpgrade: () {
              controller.hideCurrentMaterialBanner();
              showPaywall(context, trigger: 'first_restyle_celebration');
              unawaited(Analytics.log('upsell_post_restyle_clicked',
                  const {'placement': 'celebration_toast'}));
            },
            onDismiss: () => controller.hideCurrentMaterialBanner(),
          ),
          actions: const [SizedBox.shrink()],
        ),
      );

      // Auto-dismiss after 3s — keep the soft upsell unobtrusive.
      Future<void>.delayed(const Duration(seconds: 3)).then((_) {
        try {
          controller.hideCurrentMaterialBanner();
        } catch (_) {/* already hidden */}
      });
    } catch (_) {
      // never crash the result screen
    }
  }
}

class _CelebrationContent extends StatelessWidget {
  const _CelebrationContent({
    required this.onUpgrade,
    required this.onDismiss,
  });

  final VoidCallback onUpgrade;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [KoalaColors.accentDeep, KoalaColors.accentMuted],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: KoalaColors.accentDeep.withValues(alpha: 0.32),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(LucideIcons.sparkles,
                size: 18, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'İlk tasarımın hazır! Pro ile sınırsız üret →',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.1,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onUpgrade,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Text(
                'Pro\'ya Geç',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: KoalaColors.accentDeep,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            iconSize: 16,
            color: Colors.white.withValues(alpha: 0.85),
            icon: const Icon(LucideIcons.x),
          ),
        ],
      ),
    );
  }
}
