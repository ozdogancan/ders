import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../../core/theme/koala_tokens.dart';
import '../../widgets/koala_widgets.dart';

/// Admin Dashboard — temel metrikler
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  bool _loading = true;
  final Map<String, int> _stats = {};
  List<Map<String, dynamic>> _recentUsers = [];

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();
      final weekAgo = now.subtract(const Duration(days: 7)).toIso8601String();

      // Count queries — supabase_flutter ^2 kullanır .select('id') sonra length
      final results = await Future.wait([
        _db.from('users').select('id'),
        _db.from('users').select('id').gte('created_at', todayStart),
        _db.from('koala_conversations').select('id'),
        _db.from('koala_direct_messages').select('id').gte('created_at', todayStart),
        _db.from('saved_items').select('id'),
        _db.from('users').select('id, email, display_name, created_at').order('created_at', ascending: false).limit(7),
      ]);

      if (mounted) {
        setState(() {
          _stats['total_users'] = (results[0] as List).length;
          _stats['today_signups'] = (results[1] as List).length;
          _stats['total_conversations'] = (results[2] as List).length;
          _stats['today_messages'] = (results[3] as List).length;
          _stats['total_saves'] = (results[4] as List).length;
          _recentUsers = List<Map<String, dynamic>>.from(results[5] as List);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('AdminDashboard error: $e');
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
        title: const Text('Admin Panel', style: KoalaText.h2),
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
                  // Metric cards grid
                  GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: KoalaSpacing.md,
                    crossAxisSpacing: KoalaSpacing.md,
                    childAspectRatio: 1.6,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _MetricCard(label: 'Toplam Kullanıcı', value: _stats['total_users'] ?? 0, icon: Icons.people_rounded, color: KoalaColors.accent),
                      _MetricCard(label: 'Bugün Kayıt', value: _stats['today_signups'] ?? 0, icon: Icons.person_add_rounded, color: KoalaColors.green),
                      _MetricCard(label: 'Konuşmalar', value: _stats['total_conversations'] ?? 0, icon: Icons.chat_rounded, color: KoalaColors.star),
                      _MetricCard(label: 'Bugün Mesaj', value: _stats['today_messages'] ?? 0, icon: Icons.message_rounded, color: KoalaColors.pink),
                      _MetricCard(label: 'Toplam Kayıt', value: _stats['total_saves'] ?? 0, icon: Icons.bookmark_rounded, color: KoalaColors.accentMuted),
                    ],
                  ),

                  const SizedBox(height: KoalaSpacing.xl),

                  // Recent signups
                  const Text('Son Kayıtlar (7 gün)', style: KoalaText.caption),
                  const SizedBox(height: KoalaSpacing.md),
                  ..._recentUsers.map((u) => Container(
                    margin: const EdgeInsets.only(bottom: KoalaSpacing.sm),
                    padding: const EdgeInsets.all(KoalaSpacing.md),
                    decoration: KoalaDeco.card,
                    child: Row(
                      children: [
                        Container(
                          width: 36, height: 36,
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: KoalaColors.accentSoft),
                          child: const Icon(Icons.person_rounded, size: 18, color: KoalaColors.accent),
                        ),
                        const SizedBox(width: KoalaSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(u['display_name'] as String? ?? 'İsimsiz', style: KoalaText.label),
                              Text(u['email'] as String? ?? '', style: KoalaText.bodySmall),
                            ],
                          ),
                        ),
                        Text(
                          _formatDate(u['created_at'] as String?),
                          style: KoalaText.labelSmall,
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    return '${dt.day}/${dt.month}';
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.icon, required this.color});
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KoalaSpacing.lg),
      decoration: KoalaDeco.cardElevated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, size: 22, color: color),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$value', style: KoalaText.h1.copyWith(color: color)),
              Text(label, style: KoalaText.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}
