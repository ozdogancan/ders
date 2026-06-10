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
import '../core/theme/koala_ds.dart';
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

  Future<void> _sendMagicLink() async {
    if (_busy) return;
    final email = _emailCtrl.text.trim().toLowerCase();
    if (!email.contains('@')) {
      _setError('Önce Evlumba e-postanı yaz.');
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
            Uri.parse('${Env.koalaApiUrl}/api/auth/evlumba/magic/start'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 25));
      if (!mounted) return;
      setState(() => _busy = false);
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final masked = (j['masked_email'] ?? email).toString();
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: KoalaColors.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
            title: const Text('Giriş bağlantısı gönderildi 📬',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            content: Text(
              '$masked adresine bir giriş bağlantısı gönderdik. '
              'E-postandaki "Giriş yap" butonuna dokun — şifre gerekmez. '
              'Bağlantı 15 dakika geçerli.',
              style: const TextStyle(
                  fontSize: 14, height: 1.5, color: KoalaColors.textSec),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Tamam',
                    style: TextStyle(
                        color: KoalaColors.accentDeep,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
      } else {
        _setError('Bağlantı gönderilemedi. Lütfen tekrar dene.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _setError('Bağlantı sorunu. Lütfen tekrar dene.');
      }
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
                    borderRadius: BorderRadius.circular(KoalaR.lg),
                    border: Border.all(color: KoalaDS.line),
                    boxShadow: KoalaElev.card,
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
              // V2: serif display başlık — auth ekranlarıyla ortak dil.
              Text(
                'Evlumba ile giriş',
                textAlign: TextAlign.center,
                style: KoalaType.display3(),
              ),
              const SizedBox(height: 6),
              const Text(
                'Evlumba hesabınla hızlıca giriş yap.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: KoalaDS.inkSoft,
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
                    color: KoalaDS.danger,
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
              const SizedBox(height: 12),
              // Şifresiz: magic link gönder.
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _sendMagicLink,
                  icon: const Icon(LucideIcons.mail,
                      size: 18, color: KoalaColors.accentDeep),
                  label: const Text(
                    'Şifresiz giriş — e-postama bağlantı gönder',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: KoalaColors.accentDeep,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    side: const BorderSide(color: KoalaDS.line, width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(KoalaRadius.pill),
                    ),
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
          borderRadius: BorderRadius.circular(KoalaR.md),
          borderSide:
              const BorderSide(color: KoalaDS.line, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KoalaR.md),
          borderSide:
              const BorderSide(color: KoalaDS.line, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KoalaR.md),
          borderSide:
              const BorderSide(color: KoalaColors.accentDeep, width: 1.2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      );
}

/// Magic link hedef ekranı — e-postadaki bağlantı /evlumba-magic?token=...
/// açar; token'ı verify eder, custom token ile giriş yapar, ana sayfaya gider.
class EvlumbaMagicScreen extends StatefulWidget {
  const EvlumbaMagicScreen({super.key, required this.token});
  final String token;

  @override
  State<EvlumbaMagicScreen> createState() => _EvlumbaMagicScreenState();
}

class _EvlumbaMagicScreenState extends State<EvlumbaMagicScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
  }

  Future<void> _verify() async {
    if (widget.token.isEmpty) {
      setState(() => _error = 'Geçersiz bağlantı.');
      return;
    }
    try {
      final res = await http
          .post(
            Uri.parse('${Env.koalaApiUrl}/api/auth/evlumba/magic/verify'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'token': widget.token}),
          )
          .timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) {
        setState(() => _error =
            'Bağlantı geçersiz veya süresi dolmuş. Yeni bir bağlantı iste.');
        return;
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final token = (j['custom_token'] ?? '').toString();
      if (token.isEmpty) {
        setState(() => _error = 'Giriş yapılamadı. Tekrar dene.');
        return;
      }
      await FirebaseAuth.instance.signInWithCustomToken(token);
      if (!mounted) return;
      await AuthCoordinator.goToHome(context);
    } catch (_) {
      if (mounted) setState(() => _error = 'Bağlantı sorunu. Tekrar dene.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: _error == null
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                        color: KoalaColors.accentDeep, strokeWidth: 2.4),
                    SizedBox(height: 18),
                    Text('Giriş yapılıyor…',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: KoalaColors.textSec)),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.alertCircle,
                        size: 44, color: KoalaDS.clay),
                    const SizedBox(height: 14),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 15,
                            color: KoalaColors.text,
                            height: 1.45)),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      onPressed: () => AuthCoordinator.goToHome(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: KoalaColors.accentDeep,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(KoalaRadius.pill)),
                      ),
                      child: const Text('Giriş ekranına dön'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
