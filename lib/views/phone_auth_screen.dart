import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/koala_tokens.dart';
import 'auth_common.dart';

enum _PhoneAuthStage { enterPhone, verifyCode }

class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({
    super.key,
    required this.mode,
    this.returnOnSuccess = false,
  });
  final AuthFlowMode mode;
  final bool returnOnSuccess;
  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final List<TextEditingController> _otpControllers =
      List<TextEditingController>.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List<FocusNode>.generate(6, (_) => FocusNode());

  ConfirmationResult? _confirmationResult;
  RecaptchaVerifier? _recaptchaVerifier;
  Timer? _resendTimer;

  _PhoneAuthStage _stage = _PhoneAuthStage.enterPhone;
  bool _isSendingSms = false;
  bool _isVerifyingCode = false;
  String? _verificationId;
  int? _forceResendingToken;
  String _submittedPhoneNumber = '';
  String? _error;
  int _secondsRemaining = 0;

  bool get _isBusy => _isSendingSms || _isVerifyingCode;
  String get _phoneDigits => _phoneController.text.replaceAll(RegExp(r'\D'), '');
  String get _otpCode => _otpControllers.map((c) => c.text).join();

  @override
  void initState() {
    super.initState();
    for (final node in _otpFocusNodes) {
      node.addListener(() => _safeSetState(() {}));
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _recaptchaVerifier?.clear();
    _phoneController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final n in _otpFocusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) { if (mounted) setState(fn); }

  void _handleBackPressed() {
    if (_stage == _PhoneAuthStage.verifyCode && !_isVerifyingCode) {
      _goBackToPhoneEntry();
      return;
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  void _goBackToPhoneEntry() {
    _resendTimer?.cancel();
    _safeSetState(() { _stage = _PhoneAuthStage.enterPhone; _isVerifyingCode = false; _error = null; _secondsRemaining = 0; });
    _clearOtpFields();
  }

  Future<void> _submitPhoneNumber({bool isResend = false}) async {
    final digits = _phoneDigits;
    if (digits.length != 10 || !digits.startsWith('5')) {
      _safeSetState(() { _error = 'Telefon numaranı 5XX XXX XX XX formatında gir.'; });
      return;
    }

    final fullPhoneNumber = '+90$digits';
    _submittedPhoneNumber = fullPhoneNumber;
    _safeSetState(() { _isSendingSms = true; _error = null; });

    try {
      if (kIsWeb) {
        _resetRecaptchaVerifier();
        _confirmationResult = await FirebaseAuth.instance.signInWithPhoneNumber(fullPhoneNumber, _recaptchaVerifier);
        _enterOtpStage();
        return;
      }

      final platform = defaultTargetPlatform;
      if (platform != TargetPlatform.android && platform != TargetPlatform.iOS) {
        throw UnsupportedError('Telefon ile giriş bu cihazda desteklenmiyor.');
      }

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: fullPhoneNumber,
        timeout: const Duration(seconds: 60),
        forceResendingToken: isResend ? _forceResendingToken : null,
        verificationCompleted: (PhoneAuthCredential credential) async {
          _safeSetState(() { _isSendingSms = false; _isVerifyingCode = true; _error = null; });
          try {
            final result = await FirebaseAuth.instance.signInWithCredential(credential);
            await _completeAuth(result.user);
          } catch (error) {
            _safeSetState(() { _error = AuthCoordinator.mapError(error); });
          } finally {
            _safeSetState(() { _isVerifyingCode = false; });
          }
        },
        verificationFailed: (FirebaseAuthException error) {
          _safeSetState(() { _isSendingSms = false; _isVerifyingCode = false; _error = AuthCoordinator.mapError(error, fallback: 'Kod gönderilemedi. Lütfen tekrar dene.'); });
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _forceResendingToken = resendToken;
          _enterOtpStage();
        },
        codeAutoRetrievalTimeout: (String verificationId) { _verificationId = verificationId; },
      );
    } catch (error) {
      if (AuthCoordinator.isCancellation(error)) {
        _safeSetState(() { _isSendingSms = false; _error = null; });
        return;
      }
      _safeSetState(() { _isSendingSms = false; _error = AuthCoordinator.mapError(error, fallback: 'Kod gönderilemedi. Lütfen tekrar dene.'); });
    }
  }

  Future<void> _resendCode() async {
    if (_secondsRemaining > 0 || _isBusy) return;
    await _submitPhoneNumber(isResend: true);
  }

  void _enterOtpStage() {
    _clearOtpFields();
    _startResendTimer();
    _safeSetState(() { _stage = _PhoneAuthStage.verifyCode; _isSendingSms = false; _isVerifyingCode = false; _error = null; });
    if (mounted) FocusScope.of(context).requestFocus(_otpFocusNodes.first);
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    _safeSetState(() { _secondsRemaining = 60; });
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 1) { timer.cancel(); _safeSetState(() { _secondsRemaining = 0; }); return; }
      _safeSetState(() { _secondsRemaining -= 1; });
    });
  }

  void _resetRecaptchaVerifier() {
    _recaptchaVerifier?.clear();
    _recaptchaVerifier = RecaptchaVerifier(
      auth: FirebaseAuthPlatform.instance,
      onError: (error) { _safeSetState(() { _isSendingSms = false; _error = AuthCoordinator.mapError(error); }); },
      onExpired: () { _safeSetState(() { _error = 'Güvenlik doğrulaması yenilendi. Lütfen tekrar dene.'; }); },
    );
  }

  Future<void> _verifyOtp() async {
    if (_otpCode.length != 6 || _isVerifyingCode) return;
    _safeSetState(() { _isVerifyingCode = true; _error = null; });

    try {
      UserCredential result;
      if (kIsWeb) {
        if (_confirmationResult == null) throw StateError('Doğrulama oturumu yenilendi. Kodu tekrar iste.');
        result = await _confirmationResult!.confirm(_otpCode);
      } else {
        if (_verificationId == null || _verificationId!.isEmpty) throw StateError('Doğrulama oturumu yenilendi. Kodu tekrar iste.');
        final credential = PhoneAuthProvider.credential(verificationId: _verificationId!, smsCode: _otpCode);
        result = await FirebaseAuth.instance.signInWithCredential(credential);
      }
      await _completeAuth(result.user);
    } catch (error) {
      _safeSetState(() { _isVerifyingCode = false; _error = AuthCoordinator.mapError(error, fallback: 'Kod doğrulanamadı. Lütfen tekrar dene.'); });
      _clearOtpFields();
      if (mounted) FocusScope.of(context).requestFocus(_otpFocusNodes.first);
      return;
    }
    _safeSetState(() { _isVerifyingCode = false; });
  }

  Future<void> _completeAuth(User? user) async {
    if (user == null) throw StateError('Telefon doğrulaması tamamlanamadı.');
    if (widget.mode == AuthFlowMode.signup) {
      await AuthCoordinator.syncSignup(user, provider: 'phone', phoneOverride: _submittedPhoneNumber);
    } else {
      await AuthCoordinator.touchLogin(user);
    }
    if (!mounted) return;
    if (widget.returnOnSuccess) {
      Navigator.of(context).pop(true); // AuthEntryScreen'e true dön
      return;
    }
    await AuthCoordinator.goToHome(context);
  }

  void _clearOtpFields() { for (final c in _otpControllers) {
    c.clear();
  } }

  void _onPhoneChanged(String value) { if (_error != null) _safeSetState(() { _error = null; }); }

  void _onOtpChanged(int index, String value) {
    final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
    if (_error != null) _safeSetState(() { _error = null; });

    if (digitsOnly.length > 1) { _distributeOtp(index, digitsOnly); return; }
    if (digitsOnly.isEmpty) {
      _otpControllers[index].clear();
      if (index > 0) _otpFocusNodes[index - 1].requestFocus();
      return;
    }

    _otpControllers[index].text = digitsOnly;
    _otpControllers[index].selection = const TextSelection.collapsed(offset: 1);
    if (index < _otpFocusNodes.length - 1) { _otpFocusNodes[index + 1].requestFocus(); }
    else { FocusScope.of(context).unfocus(); }
    if (_otpCode.length == 6) Future<void>.microtask(_verifyOtp);
  }

  void _distributeOtp(int startIndex, String digits) {
    int idx = startIndex;
    for (final digit in digits.split('')) {
      if (idx >= _otpControllers.length) break;
      _otpControllers[idx].text = digit;
      _otpControllers[idx].selection = const TextSelection.collapsed(offset: 1);
      idx++;
    }
    if (idx < _otpFocusNodes.length) {
      _otpFocusNodes[idx].requestFocus();
    } else {
      FocusScope.of(context).unfocus();
    }
    if (_otpCode.length == 6) Future<void>.microtask(_verifyOtp);
  }

  KeyEventResult _handleOtpKeyEvent(int index, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.backspace) return KeyEventResult.ignored;
    if (_otpControllers[index].text.isNotEmpty) { _otpControllers[index].clear(); return KeyEventResult.handled; }
    if (index == 0) return KeyEventResult.handled;
    _otpControllers[index - 1].clear();
    _otpFocusNodes[index - 1].requestFocus();
    return KeyEventResult.handled;
  }

  String _formattedPhone() {
    final digits = _submittedPhoneNumber.replaceFirst('+90', '');
    return '0 ${_TurkishPhoneFormatter.formatDigits(digits)}';
  }

  String _formatCountdown(int s) => '0:${s.remainder(60).toString().padLeft(2, '0')}';

  // ═══════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: _stage == _PhoneAuthStage.enterPhone,
      onPopInvokedWithResult: (bool didPop, void result) {
        if (!didPop && _stage == _PhoneAuthStage.verifyCode && !_isVerifyingCode) _goBackToPhoneEntry();
      },
      child: AuthScene(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 4, 28, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 34),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // Geri butonu
                        IconButton(
                          onPressed: _isVerifyingCode ? null : _handleBackPressed,
                          icon: const Icon(Icons.arrow_back_rounded),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: KoalaColors.inkSoft,
                            minimumSize: const Size(48, 48),
                          ),
                        ),
                        const SizedBox(height: 16),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 360),
                          switchInCurve: Curves.easeOutCubic,
                          transitionBuilder: (child, animation) {
                            final slide = Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero)
                                .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
                            return FadeTransition(opacity: animation, child: SlideTransition(position: slide, child: child));
                          },
                          child: _stage == _PhoneAuthStage.enterPhone ? _buildPhoneEntry() : _buildOtpStage(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // PHONE ENTRY — temiz, minimal
  // ═══════════════════════════════════════════════════

  Widget _buildPhoneEntry() {
    return Column(
      key: const ValueKey('phone-entry'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Başlık
        const Text(
          'Telefon numaranı gir',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: KoalaColors.inkDeep, letterSpacing: -0.8, height: 1.1),
        ),
        const SizedBox(height: 10),
        Text(
          'Doğrulama kodu içeren bir SMS göndereceğiz.',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: KoalaColors.textMuted, height: 1.5),
        ),
        const SizedBox(height: 28),

        // Hata
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _error == null
              ? const SizedBox.shrink()
              : Padding(
                  key: ValueKey(_error),
                  padding: const EdgeInsets.only(bottom: 16),
                  child: AuthErrorBanner(message: _error!),
                ),
        ),

        // Telefon input
        Row(
          children: <Widget>[
            // Ülke kodu
            Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: KoalaColors.borderSolid),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text('🇹🇷', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Text('+90', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: KoalaColors.inkSoft)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Numara input
            Expanded(
              child: TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.telephoneNumberNational],
                inputFormatters: [_TurkishPhoneFormatter()],
                onChanged: _onPhoneChanged,
                onSubmitted: (_) => _submitPhoneNumber(),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: KoalaColors.inkDeep, letterSpacing: 0.5),
                decoration: InputDecoration(
                  hintText: '5XX XXX XX XX',
                  hintStyle: TextStyle(color: KoalaColors.hintBorder, fontSize: 18, fontWeight: FontWeight.w500),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: KoalaColors.borderSolid)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: KoalaColors.borderSolid)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: KoalaColors.brand, width: 1.5)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // SMS Gönder butonu
        SizedBox(
          width: double.infinity,
          height: 58,
          child: ElevatedButton(
            onPressed: _isSendingSms ? null : () => _submitPhoneNumber(),
            style: ElevatedButton.styleFrom(
              backgroundColor: KoalaColors.brand,
              foregroundColor: Colors.white,
              disabledBackgroundColor: KoalaColors.brand.withValues(alpha: 0.6),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: _isSendingSms
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Text('SMS Gönder', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 16),

        // Legal
        const AuthLegalText(),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  // OTP STAGE — temiz, minimal
  // ═══════════════════════════════════════════════════

  Widget _buildOtpStage() {
    return Column(
      key: const ValueKey('otp-stage'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Başlık
        const Text(
          'Doğrulama kodu',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: KoalaColors.inkDeep, letterSpacing: -0.8, height: 1.1),
        ),
        const SizedBox(height: 10),
        Text(
          '${_formattedPhone()} numarasına gönderilen 6 haneli kodu gir.',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: KoalaColors.textMuted, height: 1.5),
        ),
        const SizedBox(height: 28),

        // Hata
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _error == null
              ? const SizedBox.shrink()
              : Padding(
                  key: ValueKey(_error),
                  padding: const EdgeInsets.only(bottom: 16),
                  child: AuthErrorBanner(message: _error!),
                ),
        ),

        // OTP kutucukları
        AbsorbPointer(
          absorbing: _isVerifyingCode,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, _buildOtpField),
          ),
        ),
        const SizedBox(height: 20),

        // Doğrulanıyor spinner
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _isVerifyingCode
              ? const Row(
                  key: ValueKey('verifying'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.3, color: KoalaColors.brand)),
                    SizedBox(width: 10),
                    Text('Doğrulanıyor...', style: TextStyle(color: KoalaColors.textMuted, fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                )
              : const SizedBox(key: ValueKey('idle'), height: 18),
        ),
        const SizedBox(height: 16),

        // Tekrar gönder
        Center(
          child: TextButton(
            onPressed: _secondsRemaining == 0 && !_isBusy ? _resendCode : null,
            style: TextButton.styleFrom(
              foregroundColor: KoalaColors.brand,
              disabledForegroundColor: KoalaColors.hintBorder,
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            child: Text(
              _secondsRemaining > 0
                  ? 'Tekrar gönder (${_formatCountdown(_secondsRemaining)})'
                  : 'Kodu tekrar gönder',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpField(int index) {
    final focused = _otpFocusNodes[index].hasFocus;
    final hasValue = _otpControllers[index].text.isNotEmpty;

    return Focus(
      focusNode: _otpFocusNodes[index],
      onKeyEvent: (node, event) => _handleOtpKeyEvent(index, event),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 50,
        height: 60,
        decoration: BoxDecoration(
          color: _isVerifyingCode
              ? KoalaColors.surfaceCool
              : hasValue
                  ? KoalaColors.accentSoft
                  : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: focused
                ? KoalaColors.brand
                : hasValue
                    ? KoalaColors.accentLight
                    : KoalaColors.borderSolid,
            width: focused ? 2 : 1.2,
          ),
        ),
        alignment: Alignment.center,
        child: TextField(
          controller: _otpControllers[index],
          focusNode: _otpFocusNodes[index],
          enabled: !_isVerifyingCode,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          textInputAction: index == 5 ? TextInputAction.done : TextInputAction.next,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (v) => _onOtpChanged(index, v),
          decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: KoalaColors.inkDeep, letterSpacing: -0.5),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// PHONE FORMATTER
// ═══════════════════════════════════════════════════

class _TurkishPhoneFormatter extends TextInputFormatter {
  static String formatDigits(String digits) {
    final trimmed = digits.length > 10 ? digits.substring(0, 10) : digits;
    if (trimmed.isEmpty) return '';
    final buf = StringBuffer();
    for (int i = 0; i < trimmed.length; i++) {
      if (i == 3 || i == 6 || i == 8) buf.write(' ');
      buf.write(trimmed[i]);
    }
    return buf.toString();
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final formatted = formatDigits(digits);
    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}
