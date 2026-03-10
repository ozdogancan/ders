import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState, User;

import 'main_shell.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  String? _error;
  late final AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _syncToSupabase(User user) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('users').upsert({
        'id': user.uid,
        'email': user.email ?? '',
        'display_name': user.displayName ?? '',
        'photo_url': user.photoURL ?? '',
        'phone': '',
        'provider': 'google',
        'credits': 10,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'last_active_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Supabase sync error: $e');
    }
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell()),
      (_) => false,
    );
  }

  Future<void> _signInGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final provider = GoogleAuthProvider();
      provider.addScope('email');
      provider.addScope('profile');
      provider.setCustomParameters({'prompt': 'select_account'});

      final result = await FirebaseAuth.instance.signInWithPopup(provider);

      if (result.user != null) {
        await _syncToSupabase(result.user!);
        _goHome();
        return;
      }
      setState(() {
        _error = 'Giriş yapılamadı. Tekrar dene.';
        _loading = false;
      });
    } on FirebaseAuthException catch (e) {
      if (e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request') {
        setState(() { _loading = false; _error = null; });
        return;
      }
      setState(() { _error = _friendlyError(e.code); _loading = false; });
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('popup-closed') || msg.contains('cancelled')) {
        setState(() { _loading = false; _error = null; });
        return;
      }
      setState(() { _error = 'Bir hata oluştu. Tekrar dene.'; _loading = false; });
    }
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'account-exists-with-different-credential':
        return 'Bu e-posta başka bir yöntemle kayıtlı.';
      case 'popup-blocked':
        return 'Popup engellendi. Tarayıcı ayarlarını kontrol et.';
      case 'too-many-requests':
        return 'Çok fazla deneme. Biraz bekle.';
      case 'network-request-failed':
        return 'İnternet bağlantını kontrol et.';
      default:
        return 'Bir hata oluştu. Tekrar dene.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFD),
      body: SafeArea(
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withAlpha(50), blurRadius: 30, offset: const Offset(0, 10))],
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 28),
                const Text("Koala'ya Hoşgeldin",
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -0.5)),
                const SizedBox(height: 10),
                Text('Sorunun fotoğrafını çek, Koala adım adım çözsün.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade500, height: 1.6)),
                const SizedBox(height: 40),
                if (_error != null)
                  Container(
                    width: double.infinity, margin: const EdgeInsets.only(bottom: 20), padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withAlpha(10), borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFEF4444).withAlpha(20))),
                    child: Row(children: [
                      const Icon(Icons.error_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_error!, style: const TextStyle(fontSize: 13, color: Color(0xFFEF4444), fontWeight: FontWeight.w600))),
                    ]),
                  ),
                GestureDetector(
                  onTap: _loading ? null : _signInGoogle,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: double.infinity, height: 58,
                    decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [BoxShadow(color: Colors.black.withAlpha(6), blurRadius: 12, offset: const Offset(0, 4))]),
                    child: _loading
                        ? const Center(child: SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF6366F1))))
                        : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Text('G', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFFEA4335))),
                            const SizedBox(width: 12),
                            const Text('Google ile devam et', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                          ]),
                  ),
                ),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _Dot('10 ücretsiz kredi'), const SizedBox(width: 16),
                  _Dot('9 branş'), const SizedBox(width: 16),
                  _Dot('AI çözüm'),
                ]),
                const Spacer(flex: 2),
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen())),
                    child: RichText(text: TextSpan(style: TextStyle(fontSize: 14, color: Colors.grey.shade500), children: const [
                      TextSpan(text: 'Zaten hesabın var mı? '),
                      TextSpan(text: 'Giriş yap', style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.w700)),
                    ])),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF6366F1))),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
    ]);
  }
}
