import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../core/config/env.dart';
import '../../core/theme/koala_ds.dart';
import '../../core/theme/koala_tokens.dart';
import '../../widgets/koala_widgets.dart';
import '../auth_common.dart';
import 'admin_dashboard.dart';
import 'admin_users_screen.dart';
import 'admin_messages_screen.dart';
import 'admin_sla_screen.dart';
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
  // 2026-06-02: admin.koalatutor.com portalı — sadece bu e-posta süper admin.
  static const String _superAdminEmail = 'info@evlumba.com';

  int _currentIndex = 0;
  bool _checking = true;
  bool _isAdmin = false;
  bool _loggingIn = false;
  String? _loginError;

  bool get _loggedIn => FirebaseAuth.instance.currentUser != null;

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    final email = (user?.email ?? '').toLowerCase();
    if (uid == null) {
      setState(() { _checking = false; _isAdmin = false; });
      return;
    }
    // Süper admin: info@evlumba.com her zaman yetkili.
    if (email == _superAdminEmail) {
      setState(() { _checking = false; _isAdmin = true; });
      return;
    }
    if (!Env.hasSupabaseConfig) {
      setState(() { _checking = false; _isAdmin = false; });
      return;
    }
    try {
      final res = await Supabase.instance.client
          .from('koala_admins')
          .select('uid')
          .eq('uid', uid)
          .maybeSingle();
      setState(() { _checking = false; _isAdmin = res != null; });
    } catch (_) {
      setState(() { _checking = false; _isAdmin = false; });
    }
  }

  /// admin.koalatutor.com'da Google ile giriş — yalnız info@evlumba.com kabul.
  Future<void> _loginAsAdmin() async {
    if (_loggingIn) return;
    setState(() { _loggingIn = true; _loginError = null; });
    try {
      final cred = await AuthCoordinator.signInWithGoogle();
      final email = (cred.user?.email ?? '').toLowerCase();
      if (email != _superAdminEmail) {
        await FirebaseAuth.instance.signOut();
        setState(() {
          _loggingIn = false;
          _loginError = 'Bu portala yalnızca $_superAdminEmail giriş yapabilir.';
        });
        return;
      }
      setState(() { _loggingIn = false; _checking = true; });
      await _checkAdmin();
    } catch (e) {
      setState(() {
        _loggingIn = false;
        _loginError = 'Giriş yapılamadı. Tekrar dene.';
      });
    }
  }

  Widget _adminLoginScreen() {
    return Scaffold(
      backgroundColor: KoalaDS.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shield_rounded,
                  size: 56, color: KoalaDS.accentDeep),
              const SizedBox(height: 16),
              const Text('Koala Admin', style: KoalaText.h2),
              const SizedBox(height: 6),
              const Text(
                'Yönetim paneline yalnızca yetkili hesap girebilir.',
                textAlign: TextAlign.center,
                style: KoalaText.bodySec,
              ),
              const SizedBox(height: 24),
              if (_loginError != null) ...[
                Text(
                  _loginError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: KoalaDS.danger,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
              ],
              SizedBox(
                width: 280,
                child: ElevatedButton.icon(
                  onPressed: _loggingIn ? null : _loginAsAdmin,
                  icon: _loggingIn
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.login_rounded, size: 18),
                  label: Text(_loggingIn ? 'Giriş yapılıyor…' : 'Google ile giriş yap'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KoalaDS.accentDeep,
                    foregroundColor: KoalaDS.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(KoalaR.md)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: KoalaDS.bg,
        body: const LoadingState(),
      );
    }

    // Giriş yapılmamışsa → admin giriş ekranı (yalnız info@evlumba.com).
    if (!_loggedIn) {
      return _adminLoginScreen();
    }

    if (!_isAdmin) {
      return Scaffold(
        backgroundColor: KoalaDS.bg,
        appBar: AppBar(
          backgroundColor: KoalaDS.bg,
          surfaceTintColor: KoalaDS.bg,
        ),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_rounded, size: 64, color: KoalaDS.inkFaint),
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

    final screens = <Widget>[
      AdminDashboard(onNavigate: (i) => setState(() => _currentIndex = i)),
      const AdminUsersScreen(),
      const AdminMessagesScreen(),
      const AdminSlaScreen(),
      const AdminBroadcastScreen(),
      const AdminAnalyticsScreen(),
      const AdminSettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: KoalaDS.surface,
          border: Border(top: BorderSide(color: KoalaDS.line, width: 0.5)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KoalaSpacing.xs,
              vertical: KoalaSpacing.sm,
            ),
            child: Row(
              children: [
                _Tab(icon: Icons.dashboard_rounded, label: 'Özet', active: _currentIndex == 0, onTap: () => setState(() => _currentIndex = 0)),
                _Tab(icon: Icons.people_rounded, label: 'Kullanıcılar', active: _currentIndex == 1, onTap: () => setState(() => _currentIndex = 1)),
                _Tab(icon: Icons.chat_rounded, label: 'Mesajlar', active: _currentIndex == 2, onTap: () => setState(() => _currentIndex = 2)),
                _Tab(icon: Icons.timer_rounded, label: 'Yanıt Süresi', active: _currentIndex == 3, onTap: () => setState(() => _currentIndex = 3)),
                _Tab(icon: Icons.campaign_rounded, label: 'Duyuru', active: _currentIndex == 4, onTap: () => setState(() => _currentIndex = 4)),
                _Tab(icon: Icons.analytics_rounded, label: 'İstatistik', active: _currentIndex == 5, onTap: () => setState(() => _currentIndex = 5)),
                _Tab(icon: Icons.settings_rounded, label: 'Ayarlar', active: _currentIndex == 6, onTap: () => setState(() => _currentIndex = 6)),
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
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: active ? KoalaDS.accent : KoalaDS.inkFaint),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9, fontWeight: active ? FontWeight.w600 : FontWeight.w500, color: active ? KoalaDS.accent : KoalaDS.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}
