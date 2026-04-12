import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../views/auth_common.dart';
import '../views/auth_entry_screen.dart';

/// Kullanıcının gerçek (anonim olmayan) hesapla giriş yapıp yapmadığını kontrol eder.
/// Giriş yapmamışsa auth ekranına yönlendirir.
/// Giriş başarılıysa true döner, kullanıcı geri dönerse false.
Future<bool> ensureAuthenticated(
  BuildContext context, {
  String? toastMessage,
}) async {
  final user = FirebaseAuth.instance.currentUser;

  // Gerçek kullanıcı varsa (anonim değil) → OK
  if (user != null && !user.isAnonymous) return true;

  if (!context.mounted) return false;

  // Auth ekranına yönlendir
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => AuthEntryScreen(
        mode: AuthFlowMode.login,
        showGuestOption: false, // mesajlaşma için misafir yeterli değil
        showCloseButton: true, // X ile kapatabilsin
        returnOnSuccess: true, // pop ile dön
        toastMessage: toastMessage ?? 'Tasarımcıya mesaj atmak için giriş yapın.',
      ),
    ),
  );

  return result == true;
}

/// Kullanıcı gerçek (anonim olmayan) hesapla giriş yapmış mı?
bool isRealUser() {
  final user = FirebaseAuth.instance.currentUser;
  return user != null && !user.isAnonymous;
}
