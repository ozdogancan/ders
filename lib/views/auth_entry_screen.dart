import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/theme/koala_tokens.dart';
import 'auth_common.dart';
import 'phone_auth_screen.dart';

class AuthEntryScreen extends StatefulWidget {
  const AuthEntryScreen({
    super.key,
    required this.mode,
    this.showGuestOption = true,
    this.showCloseButton = false,
    this.returnOnSuccess = false,
    this.toastMessage,
  });

  final AuthFlowMode mode;

  /// Misafir girişi gösterilsin mi? (mesajlaşma akışından geliyorsa false)
  final bool showGuestOption;

  /// Sağ üstte X butonu gösterilsin mi? (misafirken yönlendirilenlerde true)
  final bool showCloseButton;

  /// Login sonrası ana sayfaya git mi (false) yoksa pop mu (true)?
  final bool returnOnSuccess;

  /// Giriş sayfasında gösterilecek toast mesajı
  final String? toastMessage;

  @override
  State<AuthEntryScreen> createState() => _AuthEntryScreenState();
}

class _AuthEntryScreenState extends State<AuthEntryScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _staggerController;
  AuthActionType? _loadingAction;
  String? _error;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();

    // Toast mesajı varsa göster
    if (widget.toastMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: KoalaColors.accentDeep,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 4),
            content: Row(
              children: [
                const Icon(Icons.login_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(widget.toastMessage!, style: const TextStyle(color: Colors.white, fontSize: 13))),
              ],
            ),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _staggerController.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<void> _handleGoogle() async {
    await _runAuthAction(
      action: AuthActionType.google,
      provider: 'google',
      runner: AuthCoordinator.signInWithGoogle,
    );
  }

  // _handleApple kaldırıldı — Apple sign-in devre dışı

  Future<void> _runAuthAction({
    required AuthActionType action,
    required String provider,
    required Future<UserCredential> Function() runner,
  }) async {
    _safeSetState(() {
      _loadingAction = action;
      _error = null;
    });

    try {
      final UserCredential result = await runner().timeout(
        const Duration(seconds: 120),
        onTimeout: () => throw TimeoutException('İşlem zaman aşımına uğradı. Tekrar dene.'),
      );
      final User? user = result.user;
      if (user == null) {
        throw StateError('Giriş tamamlanamadı. Lütfen tekrar dene.');
      }

      if (widget.mode == AuthFlowMode.signup) {
        await AuthCoordinator.syncSignup(user, provider: provider);
      } else {
        await AuthCoordinator.touchLogin(user);
      }

      if (!mounted) return;
      if (widget.returnOnSuccess) {
        Navigator.of(context).pop(true);
        return;
      }
      await AuthCoordinator.goToHome(context);
    } catch (error) {
      if (!mounted) return;
      if (AuthCoordinator.isCancellation(error)) {
        _safeSetState(() {
          _loadingAction = null;
          _error = null;
        });
        return;
      }
      _safeSetState(() {
        _error = AuthCoordinator.mapError(error);
        _loadingAction = null;
      });
      return;
    }

    _safeSetState(() {
      _loadingAction = null;
    });
  }

  Future<void> _openPhoneAuth() async {
    if (_loadingAction != null) return;
    if (!mounted) return;

    final phoneResult = await Navigator.of(context).push<bool>(
      buildAuthRoute<bool>(
        PhoneAuthScreen(
          mode: widget.mode,
          returnOnSuccess: widget.returnOnSuccess,
        ),
        begin: const Offset(0.1, 0),
      ),
    );
    // Telefon auth başarılıysa ve returnOnSuccess aktifse → AuthEntryScreen'i de kapat
    if (phoneResult == true && widget.returnOnSuccess && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _handleGuestLogin() async {
    if (_loadingAction != null) return;
    _safeSetState(() => _loadingAction = AuthActionType.google);
    try {
      // Zaten bir kullanıcı varsa (anonim dahil) tekrar sign-in deneme
      final existing = FirebaseAuth.instance.currentUser;
      if (existing == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      if (!mounted) return;
      if (widget.returnOnSuccess) {
        Navigator.of(context).pop(false); // false = guest, not real login
        return;
      }
      await AuthCoordinator.goToHome(context);
    } catch (e) {
      debugPrint('Guest login error: $e');
      // Hata olsa bile devam et — REQUIRE_LOGIN=false ise auth olmadan da çalışır
      if (!mounted) return;
      if (widget.returnOnSuccess) {
        Navigator.of(context).pop(false);
        return;
      }
      await AuthCoordinator.goToHome(context);
    }
    if (mounted) _safeSetState(() => _loadingAction = null);
  }


  @override
  Widget build(BuildContext context) {
    final bool signupMode = widget.mode == AuthFlowMode.signup;

    final Animation<double> logoAnim = CurvedAnimation(
      parent: _staggerController,
      curve: const Interval(0, 0.26, curve: Curves.easeOutCubic),
    );
    final Animation<double> headerAnim = CurvedAnimation(
      parent: _staggerController,
      curve: const Interval(0.16, 0.42, curve: Curves.easeOutCubic),
    );
    final Animation<double> buttonsAnim = CurvedAnimation(
      parent: _staggerController,
      curve: const Interval(0.3, 0.7, curve: Curves.easeOutCubic),
    );
    final Animation<double> featureAnim = CurvedAnimation(
      parent: _staggerController,
      curve: const Interval(0.58, 0.86, curve: Curves.easeOutCubic),
    );

    return AuthScene(
      child: Stack(
        children: [
          // Close button (sadece misafirken yönlendirilenlerde)
          if (widget.showCloseButton)
            Positioned(
              top: 12,
              right: 12,
              child: SafeArea(
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: IconButton.styleFrom(
                    backgroundColor: KoalaColors.surfaceCool,
                    foregroundColor: KoalaColors.textMed,
                    minimumSize: const Size(40, 40),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ),
            ),
          LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 36,
              ),
              child: IntrinsicHeight(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      children: <Widget>[
                        const SizedBox(height: 32),

                        // Logo
                        FadeSlideIn(
                          animation: logoAnim,
                          beginOffset: const Offset(0, 0.12),
                          child: const KoalaHeroLogo(),
                        ),
                        const SizedBox(height: 32),

                        // Başlık + açıklama
                        FadeSlideIn(
                          animation: headerAnim,
                          beginOffset: const Offset(0, 0.08),
                          child: Column(
                            children: <Widget>[
                              Text(
                                signupMode
                                    ? "Koala'ya Hoşgeldin"
                                    : 'Tekrar Hoşgeldin!',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                  color: KoalaColors.inkDeep,
                                  letterSpacing: -0.8,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                signupMode
                                    ? 'Mekanını tara, stilini keşfet, doğru tasarımcıyla eşleş.'
                                    : 'Mekan analizine kaldığın yerden devam et.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: KoalaColors.textMuted,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Feature dots — butonlardan önce value prop
                        FadeSlideIn(
                          animation: featureAnim,
                          child: const AuthFeatureStrip(),
                        ),
                        const SizedBox(height: 24),

                        // Error banner
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: _error == null
                              ? const SizedBox.shrink()
                              : Padding(
                                  key: ValueKey<String>(_error!),
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: AuthErrorBanner(message: _error!),
                                ),
                        ),

                        // Auth butonları
                        FadeSlideIn(
                          animation: buttonsAnim,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              // Google
                              AuthActionButton(
                                label: 'Google ile devam et',
                                leading: const _GoogleIcon(),
                                onPressed: _loadingAction == null ? _handleGoogle : null,
                                loading: _loadingAction == AuthActionType.google,
                              ),
                              const SizedBox(height: 16),

                              // Ayırıcı
                              const _OrDivider(),
                              const SizedBox(height: 16),

                              // Telefon
                              AuthActionButton(
                                label: 'Telefon ile devam et',
                                leading: const Icon(
                                  Icons.smartphone_rounded,
                                  color: KoalaColors.brand,
                                  size: 20,
                                ),
                                onPressed: _openPhoneAuth,
                                loading: false,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Misafir girişi (sadece izin verildiğinde)
                        if (widget.showGuestOption)
                          FadeSlideIn(
                            animation: buttonsAnim,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: TextButton(
                                onPressed: _handleGuestLogin,
                                style: TextButton.styleFrom(
                                  foregroundColor: KoalaColors.textMuted,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                                child: const Text(
                                  'Misafir olarak göz at',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    decoration: TextDecoration.underline,
                                    decorationColor: KoalaColors.textMuted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),

                        // Legal text
                        FadeSlideIn(
                          animation: buttonsAnim,
                          child: const AuthLegalText(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
        ],
      ),
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'G',
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Color(0xFFEA4335),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: Divider(color: KoalaColors.borderSolid, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'veya',
            style: TextStyle(
              color: KoalaColors.textMuted.withValues(alpha: 0.8),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(child: Divider(color: KoalaColors.borderSolid, thickness: 1)),
      ],
    );
  }
}


