import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ai_chat_history_service.dart';

/// Chat persistence — Supabase first, SharedPreferences fallback.
/// Mevcut API'yi bozmadan Supabase entegrasyonu.
class ChatPersistence {
  static const _listKey = 'koala_chat_list';

  // ── Conversation list ──

  static Future<List<ChatSummary>> loadConversations() async {
    // Supabase'den dene
    try {
      final sessions = await AIChatHistoryService.getSessions();
      if (sessions.isNotEmpty) {
        return sessions.map((s) => ChatSummary(
          id: s['id'] as String,
          title: s['title'] as String? ?? 'Sohbet',
          intent: s['intent'] as String?,
          createdAt: DateTime.tryParse(s['created_at']?.toString() ?? ''),
          updatedAt: DateTime.tryParse(s['updated_at']?.toString() ?? ''),
        )).toList();
      }
    } catch (e) {
      debugPrint('ChatPersistence: Supabase load failed, falling back: $e');
    }

    // Fallback: SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_listKey) ?? [];
    return raw.map((json) {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return ChatSummary.fromJson(m);
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  static Future<void> saveConversationSummary(ChatSummary summary) async {
    // SharedPreferences (her zaman — offline fallback)
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_listKey) ?? [];
    list.removeWhere((json) {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return m['id'] == summary.id;
    });
    list.insert(0, jsonEncode(summary.toJson()));
    if (list.length > 50) list.removeRange(50, list.length);
    await prefs.setStringList(_listKey, list);

    // Supabase (fire and forget)
    try {
      await AIChatHistoryService.updateSessionTitle(summary.id, summary.title);
    } catch (_) {}
  }

  static Future<void> deleteConversation(String id) async {
    // SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_listKey) ?? [];
    list.removeWhere((json) {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return m['id'] == id;
    });
    await prefs.setStringList(_listKey, list);
    await prefs.remove('koala_msgs_$id');

    // Supabase
    try {
      await AIChatHistoryService.deleteSession(id);
    } catch (_) {}
  }

  // ── Messages ──

  static Future<List<Map<String, dynamic>>> loadMessages(String chatId) async {
    // Supabase'den dene
    try {
      final messages = await AIChatHistoryService.getMessages(chatId);
      if (messages.isNotEmpty) return messages;
    } catch (e) {
      debugPrint('ChatPersistence: Supabase messages load failed: $e');
    }

    // Fallback: SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('koala_msgs_$chatId');
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  static Future<void> saveMessages(String chatId, List<Map<String, dynamic>> messages) async {
    // SharedPreferences (her zaman)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('koala_msgs_$chatId', jsonEncode(messages));

    // Supabase'e son mesajı kaydet (tüm listeyi değil, sadece yeni olanları)
    // Not: tam senkronizasyon B.4'te migration ile yapılacak
  }

  // ── Migration ──

  /// Mevcut lokal chat'leri Supabase'e yükle (bir kez çalışır)
  static Future<void> migrateLocalToSupabase() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('chats_migrated') == true) return;

    try {
      final raw = prefs.getStringList(_listKey) ?? [];
      if (raw.isEmpty) {
        await prefs.setBool('chats_migrated', true);
        return;
      }

      for (final json in raw) {
        final m = jsonDecode(json) as Map<String, dynamic>;
        final localId = m['id'] as String? ?? '';
        final title = m['title'] as String? ?? 'Sohbet';
        final intent = m['intent'] as String? ?? 'general';

        // Session oluştur
        final sessionId = await AIChatHistoryService.createSession(
          title: title,
          intent: intent,
        );
        if (sessionId == null) continue;

        // Mesajları yükle
        final msgsRaw = prefs.getString('koala_msgs_$localId');
        if (msgsRaw != null) {
          final msgs = jsonDecode(msgsRaw) as List<dynamic>;
          for (final msg in msgs) {
            final msgMap = msg as Map<String, dynamic>;
            await AIChatHistoryService.addMessage(
              sessionId: sessionId,
              role: msgMap['role'] as String? ?? 'user',
              content: msgMap['content'] as String? ?? msgMap['text'] as String?,
              cards: (msgMap['cards'] as List?)?.cast<Map<String, dynamic>>(),
              imageUrl: msgMap['imageUrl'] as String? ?? msgMap['image_url'] as String?,
            );
          }
        }
      }

      await prefs.setBool('chats_migrated', true);
      debugPrint('ChatPersistence: Migration completed (${raw.length} chats)');
    } catch (e) {
      debugPrint('ChatPersistence: Migration failed: $e');
    }
  }
}

/// Lightweight summary for the conversation list
class ChatSummary {
  final String id;
  final String title;
  final String? lastMessage;
  final String? intent;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatSummary({
    required this.id,
    required this.title,
    this.lastMessage,
    this.intent,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'lastMessage': lastMessage,
    'intent': intent,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory ChatSummary.fromJson(Map<String, dynamic> m) => ChatSummary(
    id: m['id'] as String? ?? '',
    title: m['title'] as String? ?? 'Sohbet',
    lastMessage: m['lastMessage'] as String?,
    intent: m['intent'] as String?,
    createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(m['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );
}
