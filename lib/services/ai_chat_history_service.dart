import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../core/config/env.dart';

/// AI chat geçmişi Supabase servisi.
/// SharedPreferences yerine cloud-first, offline fallback ile.
class AIChatHistoryService {
  AIChatHistoryService._();

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  static SupabaseClient get _db => Supabase.instance.client;

  // ═══════════════════════════════════════════════════════
  // SESSIONS
  // ═══════════════════════════════════════════════════════

  /// Yeni session oluştur, id döndür
  static Future<String?> createSession({
    String title = 'Yeni Sohbet',
    String intent = 'general',
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return null;
    try {
      final res = await _db.from('ai_chat_sessions').insert({
        'user_id': _uid,
        'title': title,
        'intent': intent,
      }).select('id').single();
      return res['id'] as String;
    } catch (e) {
      debugPrint('AIChatHistoryService.createSession error: $e');
      return null;
    }
  }

  /// Session listesi (son güncellenen önce)
  static Future<List<Map<String, dynamic>>> getSessions({
    int limit = 20,
    int offset = 0,
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return [];
    try {
      // perf: full row → 5 cols actually consumed by ChatPersistence
      final res = await _db
          .from('ai_chat_sessions')
          .select('id, title, intent, created_at, updated_at')
          .eq('user_id', _uid!)
          .order('updated_at', ascending: false)
          .range(offset, offset + limit - 1);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('AIChatHistoryService.getSessions error: $e');
      return [];
    }
  }

  /// Başlık güncelle
  static Future<bool> updateSessionTitle(String sessionId, String title) async {
    if (_uid == null || !Env.hasSupabaseConfig) return false;
    try {
      await _db.from('ai_chat_sessions').update({
        'title': title,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', sessionId).eq('user_id', _uid!);
      return true;
    } catch (e) {
      debugPrint('AIChatHistoryService.updateSessionTitle error: $e');
      return false;
    }
  }

  /// Session ve mesajlarını sil
  static Future<bool> deleteSession(String sessionId) async {
    if (_uid == null || !Env.hasSupabaseConfig) return false;
    try {
      await _db.from('ai_chat_sessions')
          .delete()
          .eq('id', sessionId)
          .eq('user_id', _uid!);
      return true;
    } catch (e) {
      debugPrint('AIChatHistoryService.deleteSession error: $e');
      return false;
    }
  }

  /// ILIKE wildcard karakterlerini escape et (SQL injection koruması)
  static String _escapeIlike(String input) {
    return input
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }

  /// Content ILIKE arama
  static Future<List<Map<String, dynamic>>> searchSessions(String query) async {
    if (_uid == null || !Env.hasSupabaseConfig || query.trim().isEmpty) return [];
    try {
      final safeQuery = _escapeIlike(query.trim());

      // Session'larda başlık ara
      // perf: full row → 5 cols actually consumed by ChatSummary
      final titleResults = await _db
          .from('ai_chat_sessions')
          .select('id, title, intent, created_at, updated_at')
          .eq('user_id', _uid!)
          .ilike('title', '%$safeQuery%')
          .order('updated_at', ascending: false)
          .limit(10);

      // Mesaj içeriğinde ara → session_id'leri getir
      // user_id filtresi: sadece kendi session'larımızın mesajlarını ara
      final userSessions = await _db
          .from('ai_chat_sessions')
          .select('id')
          .eq('user_id', _uid!);
      final userSessionIds = (userSessions as List)
          .map((s) => s['id'] as String)
          .toList();

      if (userSessionIds.isEmpty) {
        return List<Map<String, dynamic>>.from(titleResults);
      }

      final msgResults = await _db
          .from('ai_chat_messages')
          .select('session_id')
          .inFilter('session_id', userSessionIds)
          .ilike('content', '%$safeQuery%')
          .limit(20);

      final sessionIds = (msgResults as List)
          .map((m) => m['session_id'] as String)
          .toSet();

      // Eğer mesaj aramasından yeni session'lar bulduysa onları da getir
      if (sessionIds.isNotEmpty) {
        // perf: full row → 5 cols actually consumed
        final extraSessions = await _db
            .from('ai_chat_sessions')
            .select('id, title, intent, created_at, updated_at')
            .eq('user_id', _uid!)
            .inFilter('id', sessionIds.toList())
            .order('updated_at', ascending: false);

        // Birleştir, tekrarları kaldır
        final all = <String, Map<String, dynamic>>{};
        for (final s in titleResults) {
          all[s['id'] as String] = Map<String, dynamic>.from(s);
        }
        for (final s in extraSessions) {
          all[s['id'] as String] = Map<String, dynamic>.from(s);
        }
        return all.values.toList();
      }

      return List<Map<String, dynamic>>.from(titleResults);
    } catch (e) {
      debugPrint('AIChatHistoryService.searchSessions error: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════
  // MESSAGES
  // ═══════════════════════════════════════════════════════

  /// Mesaj ekle
  static Future<bool> addMessage({
    required String sessionId,
    required String role,
    String? content,
    List<Map<String, dynamic>>? cards,
    String? imageUrl,
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return false;
    try {
      await _db.from('ai_chat_messages').insert({
        'session_id': sessionId,
        'role': role,
        'content': content,
        if (cards != null) 'cards': cards,
        if (imageUrl != null) 'image_url': imageUrl,
      });

      // Session updated_at güncelle
      await _db.from('ai_chat_sessions').update({
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', sessionId);

      return true;
    } catch (e) {
      debugPrint('AIChatHistoryService.addMessage error: $e');
      return false;
    }
  }

  /// Bir session'ın mesajları (kronolojik)
  static Future<List<Map<String, dynamic>>> getMessages(
    String sessionId, {
    int limit = 50,
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return [];
    try {
      final res = await _db
          .from('ai_chat_messages')
          .select()
          .eq('session_id', sessionId)
          .order('created_at', ascending: true)
          .limit(limit);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('AIChatHistoryService.getMessages error: $e');
      return [];
    }
  }
}
