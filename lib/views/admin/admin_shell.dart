import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../core/config/env.dart';
import '../../core/theme/koala_tokens.dart';
import 'admin_dashboard.dart';
import 'admin_users_screen.dart';
import 'admin_messages_screen.dart';
import 'admin_broadcast_screen.dart';
import 'admin_analytics_screen.dart';
import 'admin_settings_screen.dart';

/// Admin panel shell — role='admin' guard + bottom nav
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _currentIndex = 0;
  bool _checking = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !Env.hasSupabaseConfig) {
      setState(() { _checking = false; _isAdmin = false; });
      return;
    }

    try {
      final res = await Supabase.instance.client
          .from('users')
          .select('role')
          .eq('id', uid)
          .maybeSingle();
      final role = res?['role'] as String? ?? 'user';
      setState(() { _checking = false; _isAdmin = role == 'admin'; });
    } catch (_) {
      setState(() { _checking = false; _isAdmin = false; });
    }
  }

  final List<Widget> _screens = const [
    AdminDashboard(),
    AdminUsersScreen(),
    AdminMessagesScreen(),
    AdminBroadcastScreen(),
    AdminAnalyticsScreen(),
    AdminSettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: KoalaColors.bg,
        body: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: KoalaColors.accent,
          ),
        ),
      );
    }

    if (!_isAdmin) {
      return Scaffold(
        backgroundColor: KoalaColors.bg,
        appBar: AppBar(
          backgroundColor: KoalaColors.bg,
          surfaceTintColor: KoalaColors.bg,
        ),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_rounded, size: 64, color: KoalaColors.textTer),
              SizedBox(height: KoalaSpacing.lg),
              Text('Yetkisiz Erişim', style: KoalaText.h2),
              SizedBox(height: KoalaSpacing.sm),
              Text(
                'Bu sayfaya erişim yetkiniz yok.',
                style: KoalaText.bodySec,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: KoalaColors.surface,
          border: Border(top: BorderSide(color: KoalaColors.border, width: 0.5)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KoalaSpacing.xs,
              vertical: KoalaSpacing.sm,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Tab(icon: Icons.dashboard_rounded, label: 'Panel', active: _currentIndex == 0, onTap: () => setState(() => _currentIndex = 0)),
                _Tab(icon: Icons.people_rounded, label: 'Kullanıcılar', active: _currentIndex == 1, onTap: () => setState(() => _currentIndex = 1)),
                _Tab(icon: Icons.chat_rounded, label: 'Mesajlar', active: _currentIndex == 2, onTap: () => setState(() => _currentIndex = 2)),
                _Tab(icon: Icons.campaign_rounded, label: 'Bildirim', active: _currentIndex == 3, onTap: () => setState(() => _currentIndex = 3)),
                _Tab(icon: Icons.analytics_rounded, label: 'Analitik', active: _currentIndex == 4, onTap: () => setState(() => _currentIndex = 4)),
                _Tab(icon: Icons.settings_rounded, label: 'Ayarlar', active: _currentIndex == 5, onTap: () => setState(() => _currentIndex = 5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.icon, required this.label, required this.active, required this.onTap});
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: active ? KoalaColors.accent : KoalaColors.textTer),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 9, fontWeight: active ? FontWeight.w600 : FontWeight.w500, color: active ? KoalaColors.accent : KoalaColors.textTer)),
          ],
        ),
      ),
    );
  }
}
