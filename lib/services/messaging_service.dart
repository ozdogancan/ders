import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../core/config/env.dart';

/// Mesaj tipi
enum MessageType { text, image, file, system }

/// Kullanici <-> Tasarimci direct messaging servisi.
/// AI chat degil — gercek kisiler arasi mesajlasma.
/// Supabase Realtime ile canli dinleme destekli.
class MessagingService {
  MessagingService._();

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  static SupabaseClient get _db => Supabase.instance.client;

  /// Public getter — UI'da unread count hesabi icin
  static String? get currentUserId => _uid;

  // Aktif realtime subscription'lar
  static final Map<String, RealtimeChannel> _channels = {};

  // ═══════════════════════════════════════════════════════
  // CONVERSATIONS (sohbet odalari)
  // ═══════════════════════════════════════════════════════

  /// Sohbet baslat veya mevcut olani getir (upsert).
  /// [contextType]: hangi ekrandan gelindi (project, product, designer, ai_chat)
  /// [contextId]: ilgili kaynak ID'si
  /// [contextTitle]: ilgili kaynak basligi (inquiry mesajinda kullanilir)
  static Future<Map<String, dynamic>?> getOrCreateConversation({
    required String designerId,
    String? contextType,
    String? contextId,
    String? contextTitle,
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return null;
    try {
      // Onceden var mi kontrol et
      final existing = await _db
          .from('koala_conversations')
          .select()
          .eq('user_id', _uid!)
          .eq('designer_id', designerId)
          .maybeSingle();

      if (existing != null) return existing;

      // Yeni olustur
      final res = await _db.from('koala_conversations').insert({
        'user_id': _uid,
        'designer_id': designerId,
        'title': contextTitle,
      }).select().single();

      // Context varsa otomatik inquiry system mesaji gonder
      if (contextType != null && res != null) {
        final inquiryText = contextTitle != null
            ? '🏠 $contextTitle hakkında bilgi almak istiyorum'
            : '🏠 Merhaba, sizinle çalışmak istiyorum';

        await _db.from('koala_direct_messages').insert({
          'conversation_id': res['id'],
          'sender_id': _uid,
          'content': inquiryText,
          'message_type': 'system',
          'metadata': {
            if (contextType != null) 'context_type': contextType,
            if (contextId != null) 'context_id': contextId,
            if (contextTitle != null) 'context_title': contextTitle,
            'source': 'inquiry',
          },
        });

        // last_message guncelle
        await _db.from('koala_conversations').update({
          'last_message': inquiryText,
          'last_message_at': DateTime.now().toIso8601String(),
        }).eq('id', res['id']);
      }

      return res;
    } catch (e) {
      debugPrint('MessagingService.getOrCreateConversation error: $e');
      return null;
    }
  }

  /// Eski API uyumluluk alias
  static Future<Map<String, dynamic>?> startConversation({
    required String designerId,
    String? title,
  }) => getOrCreateConversation(designerId: designerId, contextTitle: title);

  /// Kullanicinin tum sohbetlerini getir (son mesaja gore sirali)
  static Future<List<Map<String, dynamic>>> getConversations({
    int limit = 50,
    int offset = 0,
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return [];
    try {
      final res = await _db
          .from('koala_conversations')
          .select('id, user_id, designer_id, title, last_message, last_message_at, unread_count_user, unread_count_designer, status')
          .or('user_id.eq.$_uid,designer_id.eq.$_uid')
          .eq('status', 'active')
          .order('last_message_at', ascending: false)
          .range(offset, offset + limit - 1);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('MessagingService.getConversations error: $e');
      rethrow;
    }
  }

  /// Tek conversation detay
  static Future<Map<String, dynamic>?> getConversation(String id) async {
    if (_uid == null || !Env.hasSupabaseConfig) return null;
    try {
      final res = await _db
          .from('koala_conversations')
          .select()
          .eq('id', id)
          .or('user_id.eq.$_uid,designer_id.eq.$_uid')
          .single();
      return res;
    } catch (e) {
      debugPrint('MessagingService.getConversation error: $e');
      return null;
    }
  }

  /// Sohbeti arsivle
  static Future<bool> archiveConversation(String conversationId) async {
    if (_uid == null || !Env.hasSupabaseConfig) return false;
    try {
      await _db
          .from('koala_conversations')
          .update({'status': 'archived', 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', conversationId)
          .or('user_id.eq.$_uid,designer_id.eq.$_uid');
      return true;
    } catch (e) {
      debugPrint('MessagingService.archiveConversation error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // MESSAGES (mesajlar)
  // ═══════════════════════════════════════════════════════

  /// Mesaj gonder
  static Future<Map<String, dynamic>?> sendMessage({
    required String conversationId,
    required String content,
    MessageType type = MessageType.text,
    String? attachmentUrl,
    Map<String, dynamic>? metadata,
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return null;
    try {
      // 1. Mesaji ekle
      final msg = await _db.from('koala_direct_messages').insert({
        'conversation_id': conversationId,
        'sender_id': _uid,
        'content': content,
        'message_type': type.name,
        if (attachmentUrl != null) 'attachment_url': attachmentUrl,
        if (metadata != null) 'metadata': metadata,
      }).select().single();

      // 2. Conversation'i guncelle (son mesaj + unread count)
      final conv = await _db
          .from('koala_conversations')
          .select('user_id, designer_id')
          .eq('id', conversationId)
          .single();

      final isUser = conv['user_id'] == _uid;
      final unreadField = isUser ? 'unread_count_designer' : 'unread_count_user';

      // RPC ile unread artır (yoksa sessizce geç)
      try {
        await _db.rpc('increment_unread', params: {
          'conv_id': conversationId,
          'field_name': unreadField,
        });
      } catch (_) {
        // RPC henuz kurulu degil — devam et
      }

      // last_message guncelle
      await _db.from('koala_conversations').update({
        'last_message': content,
        'last_message_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', conversationId);

      return msg;
    } catch (e) {
      debugPrint('MessagingService.sendMessage error: $e');
      return null;
    }
  }

  /// Bir sohbetin mesajlarini getir (sayfalamali, en yeniden).
  /// [beforeId] verilirse o mesajdan onceki mesajlari getirir (cursor pagination).
  static Future<List<Map<String, dynamic>>> getMessages({
    required String conversationId,
    int limit = 30,
    int offset = 0,
    String? beforeId,
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return [];
    try {
      var query = _db
          .from('koala_direct_messages')
          .select()
          .eq('conversation_id', conversationId);

      if (beforeId != null) {
        // Cursor-based: o ID'nin created_at'inden onceki mesajlar
        final pivot = await _db
            .from('koala_direct_messages')
            .select('created_at')
            .eq('id', beforeId)
            .maybeSingle();
        if (pivot != null) {
          query = query.lt('created_at', pivot['created_at']);
        }
      }

      final res = await query
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('MessagingService.getMessages error: $e');
      return [];
    }
  }

  /// Mesajlari okundu olarak isaretle
  static Future<bool> markAsRead(String conversationId) async {
    if (_uid == null || !Env.hasSupabaseConfig) return false;
    try {
      // Karsi tarafin gonderdigi okunmamis mesajlari isaretle
      await _db
          .from('koala_direct_messages')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('conversation_id', conversationId)
          .neq('sender_id', _uid!)
          .isFilter('read_at', null);

      // Unread count'u sifirla
      final conv = await _db
          .from('koala_conversations')
          .select('user_id, designer_id')
          .eq('id', conversationId)
          .single();

      final isUser = conv['user_id'] == _uid;
      final unreadField = isUser ? 'unread_count_user' : 'unread_count_designer';

      await _db.from('koala_conversations').update({
        unreadField: 0,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', conversationId);

      return true;
    } catch (e) {
      debugPrint('MessagingService.markAsRead error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // REALTIME (canli dinleme)
  // ═══════════════════════════════════════════════════════

  /// Bir sohbetin mesajlarini canli dinle
  /// Yeni mesaj geldiginde [onMessage] callback cagirilir.
  static void subscribeToMessages({
    required String conversationId,
    required void Function(Map<String, dynamic> message) onMessage,
  }) {
    // Onceki subscription varsa kapat
    unsubscribeFromMessages(conversationId);

    final channelName = 'messages:$conversationId';
    final channel = _db.channel(channelName);

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'koala_direct_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            final newRecord = payload.newRecord;
            if (newRecord.isNotEmpty) {
              onMessage(Map<String, dynamic>.from(newRecord));
            }
          },
        )
        .subscribe();

    _channels[conversationId] = channel;
    debugPrint('MessagingService: subscribed to $channelName');
  }

  /// Conversations listesini canli dinle (son mesaj degisiklikleri)
  static void subscribeToConversations({
    required void Function(Map<String, dynamic> conversation) onUpdate,
  }) {
    if (_uid == null) return;

    unsubscribeFromConversations();

    final channel = _db.channel('conversations:$_uid');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'koala_conversations',
          callback: (payload) {
            final record = payload.newRecord;
            if (record.isNotEmpty) {
              // Sadece kendi sohbetlerimizi dinle
              final userId = record['user_id'];
              final designerId = record['designer_id'];
              if (userId == _uid || designerId == _uid) {
                onUpdate(Map<String, dynamic>.from(record));
              }
            }
          },
        )
        .subscribe();

    _channels['_conversations'] = channel;
    debugPrint('MessagingService: subscribed to conversations');
  }

  /// Mesaj subscription'i kapat
  static void unsubscribeFromMessages(String conversationId) {
    final channel = _channels.remove(conversationId);
    if (channel != null) {
      _db.removeChannel(channel);
      debugPrint('MessagingService: unsubscribed from messages:$conversationId');
    }
  }

  /// Conversations subscription'i kapat
  static void unsubscribeFromConversations() {
    final channel = _channels.remove('_conversations');
    if (channel != null) {
      _db.removeChannel(channel);
    }
  }

  /// Tum subscription'lari kapat (dispose)
  static void disposeAll() {
    for (final channel in _channels.values) {
      _db.removeChannel(channel);
    }
    _channels.clear();
    debugPrint('MessagingService: all channels disposed');
  }

  // ═══════════════════════════════════════════════════════
  // BADGE & COUNTS
  // ═══════════════════════════════════════════════════════

  /// Toplam okunmamis mesaj sayisi (bildirim badge icin)
  static Future<int> getUnreadCount() async {
    if (_uid == null || !Env.hasSupabaseConfig) return 0;
    try {
      final res = await _db
          .from('koala_conversations')
          .select('user_id, designer_id, unread_count_user, unread_count_designer')
          .or('user_id.eq.$_uid,designer_id.eq.$_uid')
          .eq('status', 'active');

      final list = List<Map<String, dynamic>>.from(res);
      int total = 0;
      for (final conv in list) {
        if (conv['user_id'] == _uid) {
          total += (conv['unread_count_user'] as int?) ?? 0;
        } else {
          total += (conv['unread_count_designer'] as int?) ?? 0;
        }
      }
      return total;
    } catch (e) {
      debugPrint('MessagingService.getUnreadCount error: $e');
      return 0;
    }
  }

  /// Tek conversation icin okunmamis mesaj sayisi
  static Future<int> getConversationUnreadCount(String conversationId) async {
    if (_uid == null || !Env.hasSupabaseConfig) return 0;
    try {
      final conv = await _db
          .from('koala_conversations')
          .select('user_id, designer_id, unread_count_user, unread_count_designer')
          .eq('id', conversationId)
          .single();

      if (conv['user_id'] == _uid) {
        return (conv['unread_count_user'] as int?) ?? 0;
      }
      return (conv['unread_count_designer'] as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Alias — badge icin toplam okunmamis
  static Future<int> getTotalUnreadCount() => getUnreadCount();
}
