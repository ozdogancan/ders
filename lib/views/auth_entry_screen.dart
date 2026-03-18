import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'auth_common.dart';
import 'phone_auth_screen.dart';

class AuthEntryScreen extends StatefulWidget {
  const AuthEntryScreen({super.key, required this.mode});

  final AuthFlowMode mode;

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

  Future<void> _handleApple() async {
    await _runAuthAction(
      action: AuthActionType.apple,
      provider: 'apple',
      runner: AuthCoordinator.signInWithApple,
    );
  }

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

    await Navigator.of(context).push<void>(
      buildAuthRoute<void>(
        PhoneAuthScreen(mode: widget.mode),
        begin: const Offset(0.1, 0),
      ),
    );
  }

  void _switchMode() {
    if (!mounted) return;

    Navigator.of(context).pushReplacement<void, void>(
      buildAuthRoute<void>(
        AuthEntryScreen(
          mode: widget.mode == AuthFlowMode.signup
              ? AuthFlowMode.login
              : AuthFlowMode.signup,
        ),
      ),
    );
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
    final Animation<double> footerAnim = CurvedAnimation(
      parent: _staggerController,
      curve: const Interval(0.72, 1, curve: Curves.easeOutCubic),
    );

    return AuthScene(
      child: LayoutBuilder(
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
                                  color: Color(0xFF0F172A),
                                  letterSpacing: -0.8,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                signupMode
                                    ? 'Sorunun fotoğrafını çek, Koala adım adım çözsün.'
                                    : 'Kaldığın yerden devam et.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

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

                        // Auth butonları — hepsi aynı stil
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
                                  color: Color(0xFF6C63FF),
                                  size: 20,
                                ),
                                onPressed: _openPhoneAuth,
                                loading: false,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Legal text
                        FadeSlideIn(
                          animation: buttonsAnim,
                          child: const AuthLegalText(),
                        ),

                        const Spacer(),

                        // Feature dots
                        FadeSlideIn(
                          animation: featureAnim,
                          child: const AuthFeatureStrip(),
                        ),
                        const SizedBox(height: 18),

                        // Switch mode
                        FadeSlideIn(
                          animation: footerAnim,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Text(
                                signupMode
                                    ? 'Zaten hesabın var mı?'
                                    : 'Hesabın yok mu?',
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              TextButton(
                                onPressed: _loadingAction == null ? _switchMode : null,
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF6C63FF),
                                  textStyle: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                child: Text(signupMode ? 'Giriş yap' : 'Kayıt ol'),
                              ),
                            ],
                          ),
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
        const Expanded(child: Divider(color: Color(0xFFE2E8F0), thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'veya',
            style: TextStyle(
              color: const Color(0xFF94A3B8).withValues(alpha: 0.8),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const Expanded(child: Divider(color: Color(0xFFE2E8F0), thickness: 1)),
      ],
    );
  }
}


