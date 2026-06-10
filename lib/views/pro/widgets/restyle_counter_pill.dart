// Restyle counter pill — small chip showing "Bu ay X/2 tasarım kullanıldı"
// for free users. When 0 left, becomes gold + tappable → opens paywall.
// Hidden entirely for Pro users. Hidden silently if quota fetch fails.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/koala_ds.dart';
import '../../../helpers/paywall_router.dart';
import '../../../providers/pro_status_provider.dart';
import '../../../services/quota_service.dart';

class RestyleCounterPill extends ConsumerStatefulWidget {
  const RestyleCounterPill({super.key});

  @override
  ConsumerState<RestyleCounterPill> createState() =>
      _RestyleCounterPillState();
}

class _RestyleCounterPillState extends ConsumerState<RestyleCounterPill> {
  QuotaSnapshot? _snap;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await QuotaService.fetch();
    if (!mounted) return;
    setState(() => _snap = s);
  }

  @override
  Widget build(BuildContext context) {
    final asyncStatus = ref.watch(proStatusProvider);
    final isPro =
        asyncStatus.maybeWhen(data: (s) => s.isPro, orElse: () => false);
    if (isPro) return const SizedBox.shrink();
    final s = _snap;
    if (s == null) return const SizedBox.shrink();
    final used = s.restyleUsed;
    final limit = s.restyleLimit;
    final remaining = (limit - used).clamp(0, limit);
    final exhausted = remaining <= 0;
    // 2026-04-30: pill'i ancak son hak kalınca veya bittiğinde göster.
    // 2/2 hâlâ varken pill = gereksiz görsel kirlilik.
    if (remaining > 1) return const SizedBox.shrink();

    final bg = exhausted ? KoalaDS.clayTint : KoalaDS.accentTint;
    final fg = exhausted ? KoalaDS.clay : KoalaDS.accentDeep;
    final iconColor = exhausted ? KoalaDS.clay : KoalaDS.accentDeep;

    return GestureDetector(
      onTap: exhausted
          ? () => showPaywall(context, trigger: 'restyle_counter_pill')
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: exhausted
                ? KoalaDS.clay.withValues(alpha: 0.45)
                : KoalaDS.accentDeep.withValues(alpha: 0.15),
            width: 0.6,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              exhausted ? LucideIcons.crown : LucideIcons.sparkles,
              size: 12,
              color: iconColor,
            ),
            const SizedBox(width: 5),
            Text(
              exhausted
                  ? 'Pro\'ya geç → sınırsız'
                  : 'Bu ay $used/$limit tasarım',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: fg,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
