import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../../core/theme/koala_tokens.dart';
import '../../core/utils/format_utils.dart';
import '../../widgets/koala_widgets.dart';

/// Admin — Ayarlar ve sistem bilgisi
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  bool _loading = true;
  bool _supabaseOk = false;
  final Map<String, int> _tableCounts = {};
  List<Map<String, dynamic>> _recentLogs = [];

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    // Supabase health check
    try {
      await _db.from('users').select('id').limit(1);
      _supabaseOk = true;
    } catch (_) {
      _supabaseOk = false;
    }

    // Table counts
    final tables = [
      'users', 'koala_conversations', 'koala_direct_messages',
      'koala_notifications', 'koala_push_tokens', 'saved_items',
      'collections', 'analytics_events', 'koala_admin_logs',
    ];

    for (final t in tables) {
      try {
        final res = await _db.from(t).select('id');
        _tableCounts[t] = (res as List).length;
      } catch (_) {
        _tableCounts[t] = -1; // error
      }
    }

    // Recent admin logs
    try {
      final logs = await _db
          .from('koala_admin_logs')
          .select()
          .order('created_at', ascending: false)
          .limit(20);
      _recentLogs = List<Map<String, dynamic>>.from(logs);
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _cleanupNotifications() async {
    try {
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
      await _db.from('koala_notifications').delete().eq('is_read', true).lt('created_at', thirtyDaysAgo);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Okunmuş bildirimler temizlendi')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Future<void> _cleanupAnalytics() async {
    try {
      final ninetyDaysAgo = DateTime.now().subtract(const Duration(days: 90)).toIso8601String();
      await _db.from('analytics_events').delete().lt('created_at', ninetyDaysAgo);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Eski analytics verileri temizlendi')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
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
        title: const Text('Ayarlar', style: KoalaText.h2),
        automaticallyImplyLeading: false,
      ),
      body: _loading
          ? const LoadingState()
          : RefreshIndicator(
              onRefresh: _load,
              color: KoalaColors.accent,
              child: ListView(
                padding: const EdgeInsets.all(KoalaSpacing.lg),
                children: [
                  // System status
                  const Text('Sistem Durumu', style: KoalaText.caption),
                  const SizedBox(height: KoalaSpacing.sm),
                  _StatusRow('Supabase', _supabaseOk),
                  _StatusRow('App Versiyon', null, value: '1.0.0'),

                  const SizedBox(height: KoalaSpacing.xl),

                  // Table sizes
                  const Text('Tablo Boyutları', style: KoalaText.caption),
                  const SizedBox(height: KoalaSpacing.sm),
                  ..._tableCounts.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: KoalaSpacing.xs),
                    child: Row(
                      children: [
                        Expanded(child: Text(e.key, style: KoalaText.bodySmall)),
                        Text(
                          e.value < 0 ? 'Hata' : '${e.value} satır',
                          style: KoalaText.label.copyWith(
                            color: e.value > 100000 ? KoalaColors.error : KoalaColors.text,
                          ),
                        ),
                      ],
                    ),
                  )),

                  const SizedBox(height: KoalaSpacing.xl),

                  // Cleanup actions
                  const Text('Temizlik', style: KoalaText.caption),
                  const SizedBox(height: KoalaSpacing.sm),
                  _ActionButton('Okunmuş Bildirimleri Temizle (30g+)', _cleanupNotifications),
                  const SizedBox(height: KoalaSpacing.sm),
                  _ActionButton('Analytics Temizle (90g+)', _cleanupAnalytics),

                  const SizedBox(height: KoalaSpacing.xl),

                  // Recent admin logs
                  const Text('Son Admin İşlemleri', style: KoalaText.caption),
                  const SizedBox(height: KoalaSpacing.sm),
                  if (_recentLogs.isEmpty)
                    const Text('Henüz işlem yok', style: KoalaText.bodySec),
                  ..._recentLogs.take(10).map((log) {
                    final action = log['action'] as String? ?? '';
                    final createdAt = DateTime.tryParse(log['created_at']?.toString() ?? '');
                    return Container(
                      margin: const EdgeInsets.only(bottom: KoalaSpacing.xs),
                      padding: const EdgeInsets.all(KoalaSpacing.sm),
                      decoration: BoxDecoration(
                        color: KoalaColors.surface,
                        borderRadius: BorderRadius.circular(KoalaRadius.sm),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(action, style: KoalaText.bodySmall)),
                          if (createdAt != null)
                            Text(
                              formatDMHM(createdAt),
                              style: KoalaText.labelSmall,
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }

  Widget _StatusRow(String label, bool? ok, {String? value}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KoalaSpacing.sm),
      child: Row(
        children: [
          if (ok != null)
            Container(
              width: 8, height: 8,
              margin: const EdgeInsets.only(right: KoalaSpacing.sm),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ok ? KoalaColors.green : KoalaColors.error,
              ),
            ),
          Text(label, style: KoalaText.label),
          const Spacer(),
          Text(value ?? (ok == true ? 'Bağlı' : 'Bağlantı yok'), style: KoalaText.bodySec),
        ],
      ),
    );
  }

  Widget _ActionButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: KoalaSpacing.md, horizontal: KoalaSpacing.lg),
        decoration: BoxDecoration(
          color: KoalaColors.surface,
          borderRadius: BorderRadius.circular(KoalaRadius.md),
          border: Border.all(color: KoalaColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.cleaning_services_rounded, size: 18, color: KoalaColors.warning),
            const SizedBox(width: KoalaSpacing.md),
            Expanded(child: Text(label, style: KoalaText.label)),
            const Icon(Icons.chevron_right_rounded, size: 18, color: KoalaColors.textTer),
          ],
        ),
      ),
    );
  }
}
