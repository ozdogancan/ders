import 'package:firebase_auth/firebase_auth.dart';

/// Firebase ID Token helper — koala-api isteklerine `Authorization: Bearer ...`
/// header eklemek için tek nokta. Server bu token'ı `firebase-admin` ile
/// doğrular ve body içindeki `userId` / `firebaseUid` ile eşleştirir.
///
/// Token alınamazsa (currentUser=null veya getIdToken hata) header eklenmez;
/// server tarafı dual-mode olduğu için legacy davranışla isteği geçirir.
class AuthTokenService {
  AuthTokenService._();

  /// Şu anki kullanıcının ID token'ı. null = oturum yok ya da fetch hatası.
  static Future<String?> getIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      return await user.getIdToken();
    } catch (_) {
      return null;
    }
  }

  /// Bearer header map. Token yoksa boş map döner — caller spread ile kullanır:
  /// ```dart
  /// final headers = {
  ///   ...await AuthTokenService.authHeaders(),
  ///   'Content-Type': 'application/json',
  /// };
  /// ```
  static Future<Map<String, String>> authHeaders() async {
    final t = await getIdToken();
    return t == null ? <String, String>{} : {'Authorization': 'Bearer $t'};
  }
}
