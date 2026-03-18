import 'dart:async';
import 'dart:ui';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState, User;

import '../core/config/env.dart';
import 'main_shell.dart';

const String _kTermsUrl = 'https://www.koalatutor.com/terms';
const String _kPrivacyUrl = 'https://www.koalatutor.com/privacy';
const Color _kBrandPrimary = Color(0xFF6C63FF);
const Color _kTextSecondary = Color(0xFF94A3B8);
const Color _kBackground = Color(0xFFFAFBFD);

// ═══════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════

enum AuthFlowMode { signup, login }
enum AuthActionType { google, phone, apple }

// ═══════════════════════════════════════════════════
// AUTH COORDINATOR (business logic — unchanged)
// ═══════════════════════════════════════════════════

class AuthCoordinator {
  AuthCoordinator._();

  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  static Future<void>? _googleInitFuture;

  static Future<void> _ensureGoogleInitialized() {
    return _googleInitFuture ??= _googleSignIn.initialize(
      clientId: Env.googleClientId.isEmpty ? null : Env.googleClientId,
      serverClientId: Env.googleServerClientId.isEmpty ? null : Env.googleServerClientId,
    );
  }

  static Future<UserCredential> signInWithGoogle() async {
    if (kIsWeb) {
      final GoogleAuthProvider provider = GoogleAuthProvider()
        ..addScope('email')
        ..addScope('profile')
        ..setCustomParameters(<String, String>{'prompt': 'select_account'});
      return _auth.signInWithPopup(provider);
    }

    final TargetPlatform platform = defaultTargetPlatform;
    if (platform != TargetPlatform.android &&
        platform != TargetPlatform.iOS &&
        platform != TargetPlatform.macOS) {
      throw UnsupportedError('Google ile giriş bu cihazda desteklenmiyor.');
    }

    await _ensureGoogleInitialized();
    final GoogleSignInAccount account = await _googleSignIn.authenticate();
    final GoogleSignInAuthentication authentication = account.authentication;

    if (authentication.idToken == null || authentication.idToken!.isEmpty) {
      throw StateError('Google kimliği doğrulanamadı.');
    }

    final OAuthCredential credential = GoogleAuthProvider.credential(
      idToken: authentication.idToken,
    );
    return _auth.signInWithCredential(credential);
  }

  static Future<UserCredential> signInWithApple() async {
    final AppleAuthProvider provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');

    if (kIsWeb) {
      return _auth.signInWithPopup(provider);
    }

    final TargetPlatform platform = defaultTargetPlatform;
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      final String rawNonce = _generateNonce();
      final String hashedNonce = _sha256ofString(rawNonce);
      final AuthorizationCredentialAppleID appleCredential =
          await SignInWithApple.getAppleIDCredential(
        scopes: const <AppleIDAuthorizationScopes>[
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final String? identityToken = appleCredential.identityToken;
      if (identityToken == null || identityToken.isEmpty) {
        throw StateError('Apple kimliği doğrulanamadı.');
      }

      final OAuthCredential credential = AppleAuthProvider.credentialWithIDToken(
        identityToken,
        rawNonce,
        AppleFullPersonName(
          givenName: appleCredential.givenName,
          familyName: appleCredential.familyName,
        ),
      );

      final UserCredential result = await _auth.signInWithCredential(credential);
      final String fullName = _buildAppleFullName(appleCredential);
      if (fullName.isNotEmpty &&
          (result.user?.displayName == null || result.user!.displayName!.trim().isEmpty)) {
        await result.user?.updateDisplayName(fullName);
        await result.user?.reload();
      }
      return result;
    }

    if (platform == TargetPlatform.android) {
      return _auth.signInWithProvider(provider);
    }

    throw UnsupportedError('Apple ile giriş bu cihazda desteklenmiyor.');
  }

  static Future<void> syncSignup(User user, {required String provider, String? phoneOverride}) async {
    if (!Env.hasSupabaseConfig) return;

    final SupabaseClient supabase = Supabase.instance.client;
    final String now = DateTime.now().toIso8601String();
    Map<String, dynamic>? existing;

    try {
      existing = await supabase.from('users').select('credits, created_at').eq('id', user.uid).maybeSingle();
    } catch (_) {
      existing = null;
    }

    await supabase.from('users').upsert(<String, dynamic>{
      'id': user.uid,
      'email': user.email ?? '',
      'display_name': user.displayName ?? '',
      'photo_url': user.photoURL ?? '',
      'phone': phoneOverride ?? user.phoneNumber ?? '',
      'provider': provider,
      'credits': existing?['credits'] ?? 10,
      'created_at': existing?['created_at'] ?? now,
      'updated_at': now,
      'last_active_at': now,
    }, onConflict: 'id');
  }

  static Future<void> touchLogin(User user) async {
    if (!Env.hasSupabaseConfig) return;
    final SupabaseClient supabase = Supabase.instance.client;
    await supabase.from('users').update(<String, dynamic>{
      'last_active_at': DateTime.now().toIso8601String(),
    }).eq('id', user.uid);
  }

  static Future<void> goToHome(BuildContext context) async {
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => const MainShell(),
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        transitionsBuilder: (_, Animation<double> animation, __, Widget child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            child: child,
          );
        },
      ),
      (_) => false,
    );
  }

  static Future<void> openLegalUrl(BuildContext context, String rawUrl) async {
    if (!context.mounted) return;
    
    final bool isTerms = rawUrl.contains('terms');
    final String title = isTerms ? 'Kullanım Koşulları' : 'Gizlilik Politikası';
    
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (BuildContext context, ScrollController scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: <Widget>[
                  // Drag handle + başlık + kapat butonu
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
                    child: Column(
                      children: <Widget>[
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: <Widget>[
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F0FF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isTerms ? Icons.description_outlined : Icons.shield_outlined,
                                color: const Color(0xFF6C63FF),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded),
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFFF1F5F9),
                                foregroundColor: const Color(0xFF64748B),
                                minimumSize: const Size(36, 36),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(color: Color(0xFFF1F5F9), height: 1),
                      ],
                    ),
                  ),
                  // İçerik
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                      child: isTerms
                          ? const _TermsContent()
                          : const _PrivacyContent(),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static bool isCancellation(Object error) {
    if (error is TimeoutException) return false;
    
    if (error is GoogleSignInException) {
      return error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted;
    }
    if (error is FirebaseAuthException) {
      return error.code == 'popup-closed-by-user' || error.code == 'cancelled-popup-request';
    }
    final String message = error.toString().toLowerCase();
    return message.contains('popup-closed') || message.contains('cancelled') || message.contains('canceled');
  }

  static String mapError(Object error, {String fallback = 'Bir şey ters gitti. Lütfen tekrar dene.'}) {
    if (error is UnsupportedError) return error.message?.toString() ?? fallback;

    if (error is GoogleSignInException) {
      switch (error.code) {
        case GoogleSignInExceptionCode.clientConfigurationError:
        case GoogleSignInExceptionCode.providerConfigurationError:
          return 'Google giriş ayarları eksik görünüyor.';
        case GoogleSignInExceptionCode.uiUnavailable:
          return 'Google giriş penceresi şu anda açılamıyor.';
        case GoogleSignInExceptionCode.userMismatch:
          return 'Seçilen Google hesabı doğrulanamadı.';
        case GoogleSignInExceptionCode.canceled:
        case GoogleSignInExceptionCode.interrupted:
          return 'Google girişi iptal edildi.';
        case GoogleSignInExceptionCode.unknownError:
          return error.description ?? fallback;
      }
    }

    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'account-exists-with-different-credential':
          return 'Bu e-posta başka bir giriş yöntemiyle kayıtlı.';
        case 'popup-blocked':
          return 'Giriş penceresi engellendi. Tarayıcı ayarlarını kontrol et.';
        case 'network-request-failed':
          return 'İnternet bağlantını kontrol edip tekrar dene.';
        case 'too-many-requests':
          return 'Çok fazla deneme yapıldı. Lütfen biraz bekle.';
        case 'invalid-phone-number':
          return 'Telefon numarasını kontrol edip yeniden dene.';
        case 'invalid-verification-code':
          return 'Girdiğin kod doğru görünmüyor. Tekrar dene.';
        case 'invalid-verification-id':
          return 'Doğrulama oturumu yenilendi. Kodu tekrar iste.';
        case 'session-expired':
          return 'Kodun süresi doldu. Yeni bir kod iste.';
        case 'captcha-check-failed':
          return 'Güvenlik doğrulaması tamamlanamadı. Tekrar dene.';
        case 'missing-verification-code':
          return 'Lütfen SMS kodunu eksiksiz gir.';
        case 'app-not-authorized':
          return 'Telefon doğrulama bu uygulama için henüz hazır değil.';
        case 'operation-not-allowed':
          return 'Bu giriş yöntemi şu anda aktif değil. Lütfen farklı bir yöntem dene.';
        default:
          final msg = error.message?.trim() ?? '';
          if (msg.contains('provider is disabled') || msg.contains('not-allowed')) {
            return 'Bu giriş yöntemi şu anda aktif değil. Lütfen farklı bir yöntem dene.';
          }
          if (msg.contains('network')) {
            return 'İnternet bağlantını kontrol edip tekrar dene.';
          }
          return fallback;
      }
    }

    if (error is StateError) return error.message.toString();

    final String message = error.toString().trim();
    if (message.isNotEmpty && message != "Instance of 'Error'") return message;
    return fallback;
  }

  static String _generateNonce([int length = 32]) {
    const String charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final Random random = Random.secure();
    return List<String>.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  static String _sha256ofString(String input) => sha256.convert(utf8.encode(input)).toString();

  static String _buildAppleFullName(AuthorizationCredentialAppleID credential) {
    final List<String> parts = <String>[
      credential.givenName ?? '',
      credential.familyName ?? '',
    ].where((String v) => v.trim().isNotEmpty).toList();
    return parts.join(' ').trim();
  }
}

// ═══════════════════════════════════════════════════
// ROUTE HELPER
// ═══════════════════════════════════════════════════

PageRouteBuilder<T> buildAuthRoute<T>(Widget child, {Offset begin = const Offset(0.08, 0)}) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => child,
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (_, Animation<double> animation, __, Widget page) {
      final Animation<double> fade = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      final Animation<Offset> slide = Tween<Offset>(begin: begin, end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
      return FadeTransition(opacity: fade, child: SlideTransition(position: slide, child: page));
    },
  );
}

// ═══════════════════════════════════════════════════
// UI WIDGETS
// ═══════════════════════════════════════════════════

/// Arka plan sahnesi — beyaz + çok subtle glow
class AuthScene extends StatelessWidget {
  const AuthScene({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackground,
      body: Stack(
        children: <Widget>[
          // Çok subtle arka plan glow'ları
          Positioned(
            top: -80,
            left: -40,
            child: _SubtleGlow(size: 240, color: _kBrandPrimary.withValues(alpha: 0.06)),
          ),
          Positioned(
            top: 60,
            right: -100,
            child: _SubtleGlow(size: 280, color: const Color(0xFFE0D4FF).withValues(alpha: 0.12)),
          ),
          Positioned(
            bottom: -100,
            left: 40,
            child: _SubtleGlow(size: 220, color: const Color(0xFFD4EAFF).withValues(alpha: 0.10)),
          ),
          SafeArea(child: child),
        ],
      ),
    );
  }
}

class _SubtleGlow extends StatelessWidget {
  const _SubtleGlow({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// Koala logosu — mor gradient rounded square + sparkle icon
class KoalaHeroLogo extends StatelessWidget {
  const KoalaHeroLogo({super.key, this.size = 80, this.heroTag = 'koala-auth-logo'});
  final double size;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: heroTag,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF6C63FF), Color(0xFF9B5CFF)],
          ),
          borderRadius: BorderRadius.circular(size * 0.28),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: _kBrandPrimary.withValues(alpha: 0.25),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: size * 0.42),
      ),
    );
  }
}

/// Auth butonu — varsayılan beyaz stil, opsiyonel gradient desteği
class AuthActionButton extends StatelessWidget {
  const AuthActionButton({
    super.key,
    required this.label,
    required this.leading,
    required this.onPressed,
    required this.loading,
    this.foregroundColor,
    this.spinnerColor,
    this.backgroundColor,
    this.gradient,
    this.borderColor,
    this.shadowColor,
  });

  final String label;
  final Widget leading;
  final VoidCallback? onPressed;
  final bool loading;
  final Color? foregroundColor;
  final Color? spinnerColor;
  final Color? backgroundColor;
  final List<Color>? gradient;
  final Color? borderColor;
  final Color? shadowColor;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !loading;
    final BorderRadius br = BorderRadius.circular(16);
    final bool hasGradient = gradient != null;
    final Color fg = foregroundColor ?? const Color(0xFF1E293B);
    final Color sp = spinnerColor ?? _kBrandPrimary;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled || loading ? 1 : 0.6,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: 58,
          decoration: BoxDecoration(
            color: hasGradient ? null : (backgroundColor ?? Colors.white),
            gradient: hasGradient ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: gradient!) : null,
            borderRadius: br,
            border: hasGradient ? null : Border.all(color: borderColor ?? const Color(0xFFE2E8F0), width: 1.2),
            boxShadow: <BoxShadow>[
              if (shadowColor != null)
                BoxShadow(color: shadowColor!.withValues(alpha: 0.22), blurRadius: 22, offset: const Offset(0, 14))
              else
                BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: InkWell(
            borderRadius: br,
            onTap: enabled ? onPressed : null,
            splashColor: (hasGradient ? Colors.white : _kBrandPrimary).withValues(alpha: 0.06),
            highlightColor: (hasGradient ? Colors.white : _kBrandPrimary).withValues(alpha: 0.03),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 140),
                    opacity: loading ? 0 : 1,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        SizedBox(width: 24, child: Center(child: leading)),
                        const SizedBox(width: 12),
                        Text(label, style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
                      ],
                    ),
                  ),
                  if (loading)
                    SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: sp)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hata banner'ı
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13, fontWeight: FontWeight.w600, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Feature strip — çerçevesiz, sadece dot + text
class AuthFeatureStrip extends StatelessWidget {
  const AuthFeatureStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const <Widget>[
        _FeatureDot(label: '10 ücretsiz kredi'),
        SizedBox(width: 16),
        _FeatureDot(label: '9 branş'),
        SizedBox(width: 16),
        _FeatureDot(label: 'AI çözüm'),
      ],
    );
  }
}

class _FeatureDot extends StatelessWidget {
  const _FeatureDot({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: _kBrandPrimary,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: _kTextSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Kullanım koşulları metni
class AuthLegalText extends StatelessWidget {
  const AuthLegalText({super.key});

  @override
  Widget build(BuildContext context) {
    final TextStyle baseStyle = TextStyle(
      color: _kTextSecondary.withValues(alpha: 0.8),
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.4,
    );

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: <InlineSpan>[
          const TextSpan(text: 'Devam ederek '),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: () => AuthCoordinator.openLegalUrl(context, _kTermsUrl),
              child: Text('Kullanım Koşulları', style: baseStyle.copyWith(color: _kBrandPrimary, fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
            ),
          ),
          const TextSpan(text: ' ve '),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: () => AuthCoordinator.openLegalUrl(context, _kPrivacyUrl),
              child: Text('Gizlilik Politikası', style: baseStyle.copyWith(color: _kBrandPrimary, fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
            ),
          ),
          const TextSpan(text: "'nı kabul etmiş olursunuz."),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

/// Fade + slide animasyon wrapper
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.animation, required this.child, this.beginOffset = const Offset(0, 0.08)});
  final Animation<double> animation;
  final Widget child;
  final Offset beginOffset;

  @override
  Widget build(BuildContext context) {
    final Animation<Offset> slide = Tween<Offset>(begin: beginOffset, end: Offset.zero)
        .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
    return FadeTransition(opacity: animation, child: SlideTransition(position: slide, child: child));
  }
}

/// Glassmorphism panel — phone_auth_screen'de kullanılıyor
class AuthPanel extends StatelessWidget {
  const AuthPanel({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.2),
            boxShadow: <BoxShadow>[
              BoxShadow(color: const Color(0xFF111827).withValues(alpha: 0.06), blurRadius: 36, offset: const Offset(0, 18)),
            ],
          ),
          child: Padding(
            padding: padding ?? const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// LEGAL CONTENT (in-app popup)
// ═══════════════════════════════════════════════════

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A), letterSpacing: -0.3)),
    );
  }
}

class _Para extends StatelessWidget {
  const _Para(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: Color(0xFF475569), height: 1.65)),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Icon(Icons.circle, size: 5, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, color: Color(0xFF475569), height: 1.6))),
        ],
      ),
    );
  }
}

class _PrivacyContent extends StatelessWidget {
  const _PrivacyContent();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const <Widget>[
        _Para('Koala ("biz", "uygulama"), Evlumba Software tarafından geliştirilen yapay zeka destekli bir eğitim uygulamasıdır. Kullanıcılarımızın gizliliğine saygı duyuyor ve kişisel verilerin korunmasını önemsiyoruz.'),
        _Para('Son güncelleme: 16 Mart 2026'),

        _SectionTitle('Toplanan Veriler'),
        _Bullet('Hesap bilgileri: Google hesabı ile giriş yapıldığında ad, e-posta adresi ve profil fotoğrafı'),
        _Bullet('Telefon numarası: Telefon ile giriş yapıldığında'),
        _Bullet('Soru fotoğrafları: Çözüm için gönderdiğiniz soru fotoğrafları'),
        _Bullet('Sohbet mesajları: AI öğretmen ile yaptığınız yazışmalar'),
        _Bullet('Kullanım verileri: Uygulama kullanım istatistikleri ve tercihler'),

        _SectionTitle('Verilerin Kullanımı'),
        _Bullet('Soru çözüm hizmeti sunmak ve AI destekli öğretim sağlamak'),
        _Bullet('Kullanıcı hesabınızı yönetmek ve kişiselleştirilmiş deneyim sunmak'),
        _Bullet('Uygulama performansını izlemek ve iyileştirmek'),
        _Bullet('Kredi sistemi ve satın alma işlemlerini yönetmek'),
        _Para('Verilerinizi hiçbir koşulda üçüncü taraf reklam ağlarıyla paylaşmıyoruz.'),

        _SectionTitle('Kamera Kullanımı'),
        _Para('Uygulamamız, soru fotoğrafı çekmeniz için cihazınızın kamerasına erişim izni ister. Kamera yalnızca siz aktif olarak fotoğraf çektiğinizde kullanılır. Kamera izni olmadan da galeriden fotoğraf seçerek soru gönderebilirsiniz.'),

        _SectionTitle('Veri Güvenliği'),
        _Bullet('Tüm veri iletişimi SSL/TLS şifreleme ile korunur'),
        _Bullet('Kullanıcı verileri güvenli bulut sunucularında saklanır'),
        _Bullet('Kimlik doğrulama Google OAuth 2.0 ve Firebase ile sağlanır'),

        _SectionTitle('Üçüncü Taraf Hizmetler'),
        _Bullet('Google Firebase: Kimlik doğrulama ve analitik'),
        _Bullet('Supabase: Veritabanı ve dosya depolama'),
        _Bullet('Google Gemini AI: Yapay zeka destekli soru çözüm motoru'),

        _SectionTitle('Kullanıcı Hakları'),
        _Bullet('Erişim: Hakkınızda sakladığımız verileri talep edebilirsiniz'),
        _Bullet('Düzeltme: Yanlış verilerin düzeltilmesini isteyebilirsiniz'),
        _Bullet('Silme: Hesabınızın ve tüm verilerinizin silinmesini talep edebilirsiniz'),
        _Para('Bu haklarınızı kullanmak için info@koalatutor.com adresine e-posta gönderebilirsiniz.'),

        _SectionTitle('Çocukların Gizliliği'),
        _Para('Uygulamamız 13 yaş ve üzeri kullanıcılar için tasarlanmıştır. 13 yaşın altındaki çocuklardan bilerek kişisel veri toplamıyoruz.'),

        _SectionTitle('İletişim'),
        _Para('Gizlilik politikamızla ilgili sorularınız için:\nE-posta: info@koalatutor.com\nWeb: koalatutor.com\nGeliştirici: Evlumba Software'),
        _Para('© 2026 Koala - AI Öğretmen. Tüm hakları saklıdır.'),
      ],
    );
  }
}

class _TermsContent extends StatelessWidget {
  const _TermsContent();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const <Widget>[
        _Para('Bu kullanım koşulları, Koala - AI Öğretmen uygulamasını ("Uygulama") kullanımınızı düzenler. Uygulamayı kullanarak bu koşulları kabul etmiş sayılırsınız.'),
        _Para('Son güncelleme: 18 Mart 2026'),

        _SectionTitle('Hizmet Tanımı'),
        _Para('Koala, yapay zeka destekli bir eğitim uygulamasıdır. Kullanıcılar soru fotoğrafı çekerek adım adım çözüm alabilir. Uygulama 9 farklı branşta AI destekli öğretim hizmeti sunar.'),

        _SectionTitle('Hesap ve Kayıt'),
        _Bullet('Uygulamayı kullanmak için Google, Apple veya telefon numarası ile hesap oluşturmanız gerekir'),
        _Bullet('Hesap bilgilerinizin doğru ve güncel olmasından siz sorumlusunuz'),
        _Bullet('Hesabınızın güvenliğinden siz sorumlusunuz'),

        _SectionTitle('Kredi Sistemi'),
        _Bullet('Her yeni kullanıcıya 10 ücretsiz kredi verilir'),
        _Bullet('Her soru çözümü 1 kredi harcar'),
        _Bullet('Ek kredi uygulama içi satın alma ile edinilebilir'),
        _Bullet('Satın alınan krediler iade edilemez'),

        _SectionTitle('Kabul Edilebilir Kullanım'),
        _Para('Uygulamayı yalnızca eğitim amaçlı kullanabilirsiniz. Aşağıdaki davranışlar yasaktır:'),
        _Bullet('Uygulamayı kötüye kullanmak veya başkalarının kullanımını engellemek'),
        _Bullet('Otomatik botlar veya scraper kullanmak'),
        _Bullet('Uygulamayı sınav sırasında kopya çekmek için kullanmak'),
        _Bullet('Yasalara aykırı içerik göndermek'),

        _SectionTitle('Fikri Mülkiyet'),
        _Para('Uygulama ve içeriği Evlumba Software\'a aittir. AI tarafından üretilen çözümler eğitim amaçlıdır ve doğruluğu garanti edilmez.'),

        _SectionTitle('Sorumluluk Sınırlaması'),
        _Para('Koala bir eğitim yardımcısıdır, profesyonel öğretmenin yerini almaz. AI çözümlerinin doğruluğu garanti edilmez. Uygulama "olduğu gibi" sunulur.'),

        _SectionTitle('Değişiklikler'),
        _Para('Bu koşulları zaman zaman güncelleyebiliriz. Önemli değişikliklerde uygulama içi bildirim yapacağız.'),

        _SectionTitle('İletişim'),
        _Para('Kullanım koşullarıyla ilgili sorularınız için:\nE-posta: info@koalatutor.com\nWeb: koalatutor.com\nGeliştirici: Evlumba Software'),
        _Para('© 2026 Koala - AI Öğretmen. Tüm hakları saklıdır.'),
      ],
    );
  }
}
