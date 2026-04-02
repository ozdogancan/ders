import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../core/config/env.dart';

/// Push token platformlari
enum TokenPlatform { ios, android, web }

/// FCM push token yonetim servisi.
/// Login sonrasi token kayit, logout'ta silme.
class PushTokenService {
  PushTokenService._();

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  static SupabaseClient get _db => Supabase.instance.client;

  // ─── TOKEN KAYDET / GÜNCELLE ─────────────────────────
  /// Login sonrasi veya token yenilendiginde cagir.
  /// Ayni user+token cifti varsa last_used_at gunceller.
  static Future<bool> registerToken({
    required String deviceToken,
    TokenPlatform platform = TokenPlatform.web,
    String? deviceInfo,
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return false;
    try {
      await _db.from('koala_push_tokens').upsert({
        'user_id': _uid,
        'device_token': deviceToken,
        'platform': platform.name,
        'device_info': deviceInfo,
        'is_active': true,
        'last_used_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,device_token');
      return true;
    } catch (e) {
      debugPrint('PushTokenService.registerToken error: $e');
      return false;
    }
  }

  // ─── TOKEN SİL ───────────────────────────────────────
  /// Logout'ta mevcut cihazin token'ini sil.
  static Future<bool> removeToken(String deviceToken) async {
    if (_uid == null || !Env.hasSupabaseConfig) return false;
    try {
      await _db
          .from('koala_push_tokens')
          .delete()
          .eq('user_id', _uid!)
          .eq('device_token', deviceToken);
      return true;
    } catch (e) {
      debugPrint('PushTokenService.removeToken error: $e');
      return false;
    }
  }

  // ─── TOKEN PASİFLE ──────────────────────────────────
  /// Gecersiz token'i pasifle (push fail oldugunda).
  static Future<bool> deactivateToken(String deviceToken) async {
    if (_uid == null || !Env.hasSupabaseConfig) return false;
    try {
      await _db
          .from('koala_push_tokens')
          .update({
            'is_active': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', _uid!)
          .eq('device_token', deviceToken);
      return true;
    } catch (e) {
      debugPrint('PushTokenService.deactivateToken error: $e');
      return false;
    }
  }

  // ─── AKTİF TOKEN'LAR ────────────────────────────────
  /// Bir kullanicinin aktif token'larini getir (push gondermek icin).
  /// Genelde backend kullanir ama client'tan da cagrilabilir.
  static Future<List<Map<String, dynamic>>> getActiveTokens({
    String? userId,
  }) async {
    final targetUid = userId ?? _uid;
    if (targetUid == null || !Env.hasSupabaseConfig) return [];
    try {
      final res = await _db
          .from('koala_push_tokens')
          .select()
          .eq('user_id', targetUid)
          .eq('is_active', true)
          .order('last_used_at', ascending: false);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('PushTokenService.getActiveTokens error: $e');
      return [];
    }
  }

  // ─── TÜM TOKEN'LARI TEMİZLE ─────────────────────────
  /// Kullanicinin tum token'larini sil (hesap silme, vb.).
  static Future<bool> removeAllTokens() async {
    if (_uid == null || !Env.hasSupabaseConfig) return false;
    try {
      await _db
          .from('koala_push_tokens')
          .delete()
          .eq('user_id', _uid!);
      return true;
    } catch (e) {
      debugPrint('PushTokenService.removeAllTokens error: $e');
      return false;
    }
  }
}
