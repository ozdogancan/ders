// Evlumba hesabıyla giriş ekranı.
//
// Kullanıcı Evlumba'ya kayıtlı e-posta + şifresini girer → koala-api
// /api/auth/evlumba/login doğrular → Firebase custom token ile giriş yapılır.
// Evlumba ile giriş yapabilen kullanıcı OTOMATİK profesyoneldir (sunucu
// koala_user_profiles.mode='pro' yapar).
//
// "Şifremi unuttum" → /api/auth/evlumba/forgot (Evlumba sıfırlama e-postası).
// (Magic link sonraki adımda eklenecek.)

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/config/env.dart';
import '../core/theme/koala_tokens.dart';
import 'auth_common.dart';

class EvlumbaLoginScreen extends StatefulWidget {
  const EvlumbaLoginScreen({super.key, this.returnOnSuccess = false});

  final bool returnOnSuccess;

  static const String logoUrl =
      'https://xgefjepaqnghaotqybpi.supabase.co/storage/v1/object/public/koala-seed/icons/evlumba-logo-v1.png';

  @override
  State<EvlumbaLoginScreen> createState() => _EvlumbaLoginScreenState();
}

class _EvlumbaLoginScreenState extends State<EvlumbaLoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _setError(String? e) {
    if (mounted) setState(() => _error = e);
  }

  Future<void> _login() async {
    if (_busy) return;
    final email = _emailCtrl.text.trim().toLowerCase();
    final pass = _passCtrl.text;
    if (!email.contains('@') || pass.isEmpty) {
      _setError('E-posta ve şifreni gir.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await http
          .post(
            Uri.parse('${Env.koalaApiUrl}/api/auth/evlumba/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': pass}),
          )
          .timeout(const Duration(seconds: 25));
      if (res.statusCode == 401) {
        _setError('E-posta veya şifre hatalı.');
        setState(() => _busy = false);
        return;
      }
      if (res.statusCode != 200) {
        _setError('Giriş yapılamadı. Lütfen tekrar dene.');
        setState(() => _busy = false);
        return;
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final token = (j['custom_token'] ?? '').toString();
      if (token.isEmpty) {
        _setError('Giriş yapılamadı. Lütfen tekrar dene.');
        setState(() => _busy = false);
        return;
      }
      await FirebaseAuth.instance.signInWithCustomToken(token);
      if (!mounted) return;
      if (widget.returnOnSuccess) {
        Navigator.of(context).pop(true);
        return;
      }
      await AuthCoordinator.goToHome(context);
    } catch (_) {
      _setError('Bağlantı sorunu. Lütfen tekrar dene.');
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (!email.contains('@')) {
      _setError('Önce Evlumba e-postanı yaz, sonra "Şifremi unuttum"a dokun.');
      return;
    }
    HapticFeedback.selectionClick();
    try {
      await http
          .post(
            Uri.parse('${Env.koalaApiUrl}/api/auth/evlumba/forgot'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {/* enumeration koruması — yine de aynı mesaj */}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$email kayıtlıysa şifre sıfırlama e-postası gönderildi.'),
        backgroundColor: KoalaColors.accent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      appBar: AppBar(
        backgroundColor: KoalaColors.bg,
        surfaceTintColor: KoalaColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: KoalaColors.text),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 16,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(12),
                  child: CachedNetworkImage(
                    imageUrl: EvlumbaLoginScreen.logoUrl,
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) =>
                        const Icon(LucideIcons.building2, color: KoalaColors.brand),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Evlumba ile giriş',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: KoalaColors.text,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Evlumba hesabınla hızlıca giriş yap.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: KoalaColors.textSec,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              _label('E-posta'),
              const SizedBox(height: 6),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                style: KoalaText.body,
                decoration: _dec('ornek@evlumba.com'),
                onChanged: (_) => _setError(null),
              ),
              const SizedBox(height: 14),
              _label('Şifre'),
              const SizedBox(height: 6),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                style: KoalaText.body,
                onSubmitted: (_) => _login(),
                onChanged: (_) => _setError(null),
                decoration: _dec('Şifren').copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? LucideIcons.eye : LucideIcons.eyeOff,
                      size: 19,
                      color: KoalaColors.textSec,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy ? null : _forgot,
                  child: const Text(
                    'Şifremi unuttum',
                    style: TextStyle(
                      color: KoalaColors.accentDeep,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFC2410C),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _busy ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KoalaColors.accentDeep,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(KoalaRadius.pill),
                    ),
                    elevation: 0,
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Giriş yap',
                          style: TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(t, style: KoalaText.caption),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: KoalaText.hint,
        filled: true,
        fillColor: KoalaColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: KoalaColors.borderSolid, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: KoalaColors.borderSolid, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: KoalaColors.accentDeep, width: 1.2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      );
}
