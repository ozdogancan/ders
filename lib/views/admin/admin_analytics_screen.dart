import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../../core/theme/koala_tokens.dart';
import '../../widgets/koala_widgets.dart';

/// Admin — Analytics event özeti
class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  int _days = 7;
  bool _loading = true;
  List<_EventStat> _stats = [];

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final since = DateTime.now().subtract(Duration(days: _days)).toIso8601String();
      final data = await _db
          .from('analytics_events')
          .select('event_name')
          .gte('created_at', since);

      final list = List<Map<String, dynamic>>.from(data);

      // Count by event_name
      final counts = <String, int>{};
      for (final row in list) {
        final name = row['event_name'] as String? ?? 'unknown';
        counts[name] = (counts[name] ?? 0) + 1;
      }

      // Sort by count desc
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      if (mounted) {
        setState(() {
          _stats = sorted.map((e) => _EventStat(e.key, e.value)).toList();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('AdminAnalytics error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      appBar: AppBar(
        backgroundColor: KoalaColors.bg,
        surfaceTintColor: KoalaColors.bg,
        elevation: 0,
        title: const Text('Analytics', style: KoalaText.h2),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // Period selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.lg, vertical: KoalaSpacing.sm),
            child: Row(
              children: [
                _PeriodChip('7 Gün', 7),
                const SizedBox(width: KoalaSpacing.sm),
                _PeriodChip('30 Gün', 30),
                const SizedBox(width: KoalaSpacing.sm),
                _PeriodChip('90 Gün', 90),
                const Spacer(),
                Text('${_stats.fold(0, (sum, s) => sum + s.count)} toplam', style: KoalaText.bodySec),
              ],
            ),
          ),

          // Table
          Expanded(
            child: _loading
                ? const LoadingState()
                : _stats.isEmpty
                    ? const Center(child: Text('Bu dönemde event yok', style: KoalaText.bodySec))
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: KoalaColors.accent,
                        child: ListView(
                          padding: const EdgeInsets.all(KoalaSpacing.lg),
                          children: [
                            // Header
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.md, vertical: KoalaSpacing.sm),
                              decoration: BoxDecoration(
                                color: KoalaColors.surfaceAlt,
                                borderRadius: BorderRadius.circular(KoalaRadius.sm),
                              ),
                              child: Row(
                                children: [
                                  Expanded(flex: 3, child: Text('Event', style: KoalaText.caption)),
                                  Expanded(child: Text('Sayı', style: KoalaText.caption, textAlign: TextAlign.right)),
                                ],
                              ),
                            ),
                            const SizedBox(height: KoalaSpacing.xs),

                            // Rows
                            ..._stats.map((stat) {
                              final maxCount = _stats.isNotEmpty ? _stats.first.count : 1;
                              final ratio = stat.count / maxCount;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 2),
                                padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.md, vertical: KoalaSpacing.md),
                                decoration: KoalaDeco.card,
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(stat.name, style: KoalaText.label),
                                          const SizedBox(height: 4),
                                          // Mini bar chart
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(2),
                                            child: LinearProgressIndicator(
                                              value: ratio,
                                              backgroundColor: KoalaColors.surfaceAlt,
                                              color: KoalaColors.accent,
                                              minHeight: 4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: KoalaSpacing.md),
                                    Text('${stat.count}', style: KoalaText.h3),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _PeriodChip(String label, int days) {
    final active = _days == days;
    return GestureDetector(
      onTap: () {
        setState(() => _days = days);
        _load();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.md, vertical: KoalaSpacing.sm),
        decoration: BoxDecoration(
          color: active ? KoalaColors.accent : KoalaColors.surface,
          borderRadius: BorderRadius.circular(KoalaRadius.pill),
          border: Border.all(color: active ? KoalaColors.accent : KoalaColors.border),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: active ? Colors.white : KoalaColors.text,
        )),
      ),
    );
  }
}

class _EventStat {
  final String name;
  final int count;
  _EventStat(this.name, this.count);
}
