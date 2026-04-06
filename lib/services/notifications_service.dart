import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../core/config/env.dart';

/// Bildirim tipleri
enum NotificationType {
  newMessage,
  designerMatch,
  productRecommend,
  styleResult,
  budgetReady,
  collectionUpdate,
  system,
  promo,
}

/// Bildirime tiklaninca yapilacak aksiyon
enum NotificationAction {
  openConversation,
  openDesigner,
  openProduct,
  openCollection,
  openChat,
  openUrl,
}

/// Uygulama ici bildirim servisi.
/// Supabase koala_notifications tablosuyla CRUD + Realtime.
class NotificationsService {
  NotificationsService._();

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  static SupabaseClient get _db => Supabase.instance.client;

  // Realtime channel
  static RealtimeChannel? _channel;

  // ═══════════════════════════════════════════════════════
  // OKUMA
  // ═══════════════════════════════════════════════════════

  /// Tum bildirimleri getir (en yeniden, sayfalamali)
  static Future<List<Map<String, dynamic>>> getAll({
    int limit = 50,
    int offset = 0,
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return [];
    try {
      final res = await _db
          .from('koala_notifications')
          .select()
          .eq('user_id', _uid!)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('NotificationsService.getAll error: $e');
      rethrow;
    }
  }

  /// Sadece okunmamis bildirimleri getir
  static Future<List<Map<String, dynamic>>> getUnread({
    int limit = 50,
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return [];
    try {
      final res = await _db
          .from('koala_notifications')
          .select()
          .eq('user_id', _uid!)
          .eq('is_read', false)
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('NotificationsService.getUnread error: $e');
      rethrow;
    }
  }

  /// Okunmamis bildirim sayisi (badge icin)
  static Future<int> getUnreadCount() async {
    if (_uid == null || !Env.hasSupabaseConfig) return 0;
    try {
      final res = await _db
          .from('koala_notifications')
          .select('id')
          .eq('user_id', _uid!)
          .eq('is_read', false);
      return (res as List).length;
    } catch (e) {
      debugPrint('NotificationsService.getUnreadCount error: $e');
      return 0;
    }
  }

  /// Tipe gore bildirim getir
  static Future<List<Map<String, dynamic>>> getByType(
    NotificationType type, {
    int limit = 20,
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return [];
    try {
      final res = await _db
          .from('koala_notifications')
          .select()
          .eq('user_id', _uid!)
          .eq('type', _typeToString(type))
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('NotificationsService.getByType error: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════
  // YAZMA
  // ═══════════════════════════════════════════════════════

  /// Bildirim olustur (genelde backend yapar ama client test icin)
  static Future<bool> create({
    required String userId,
    required NotificationType type,
    required String title,
    String? body,
    String? imageUrl,
    NotificationAction? actionType,
    Map<String, dynamic>? actionData,
  }) async {
    if (!Env.hasSupabaseConfig) return false;
    try {
      await _db.from('koala_notifications').insert({
        'user_id': userId,
        'type': _typeToString(type),
        'title': title,
        'body': body,
        'image_url': imageUrl,
        if (actionType != null) 'action_type': _actionToString(actionType),
        if (actionData != null) 'action_data': actionData,
      });
      return true;
    } catch (e) {
      debugPrint('NotificationsService.create error: $e');
      return false;
    }
  }

  /// Tek bildirimi okundu isaretle
  static Future<bool> markAsRead(String notificationId) async {
    if (_uid == null || !Env.hasSupabaseConfig) return false;
    try {
      await _db
          .from('koala_notifications')
          .update({'is_read': true})
          .eq('id', notificationId)
          .eq('user_id', _uid!);
      return true;
    } catch (e) {
      debugPrint('NotificationsService.markAsRead error: $e');
      return false;
    }
  }

  /// Tum bildirimleri okundu isaretle
  static Future<bool> markAllAsRead() async {
    if (_uid == null || !Env.hasSupabaseConfig) return false;
    try {
      await _db
          .from('koala_notifications')
          .update({'is_read': true})
          .eq('user_id', _uid!)
          .eq('is_read', false);
      return true;
    } catch (e) {
      debugPrint('NotificationsService.markAllAsRead error: $e');
      return false;
    }
  }

  /// Tek bildirim sil
  static Future<bool> delete(String notificationId) async {
    if (_uid == null || !Env.hasSupabaseConfig) return false;
    try {
      await _db
          .from('koala_notifications')
          .delete()
          .eq('id', notificationId)
          .eq('user_id', _uid!);
      return true;
    } catch (e) {
      debugPrint('NotificationsService.delete error: $e');
      return false;
    }
  }

  /// Okunmus bildirimleri temizle
  static Future<bool> clearRead() async {
    if (_uid == null || !Env.hasSupabaseConfig) return false;
    try {
      await _db
          .from('koala_notifications')
          .delete()
          .eq('user_id', _uid!)
          .eq('is_read', true);
      return true;
    } catch (e) {
      debugPrint('NotificationsService.clearRead error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // REALTIME
  // ═══════════════════════════════════════════════════════

  /// Yeni bildirimleri canli dinle
  static void subscribe({
    required void Function(Map<String, dynamic> notification) onNotification,
  }) {
    if (_uid == null) return;

    unsubscribe();

    _channel = _db.channel('notifications:$_uid');

    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'koala_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: _uid!,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            if (record.isNotEmpty) {
              onNotification(Map<String, dynamic>.from(record));
            }
          },
        )
        .subscribe();

    debugPrint('NotificationsService: subscribed to realtime');
  }

  /// Realtime subscription'i kapat
  static void unsubscribe() {
    if (_channel != null) {
      _db.removeChannel(_channel!);
      _channel = null;
      debugPrint('NotificationsService: unsubscribed');
    }
  }

  // ═══════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════

  static String _typeToString(NotificationType type) {
    switch (type) {
      case NotificationType.newMessage:
        return 'new_message';
      case NotificationType.designerMatch:
        return 'designer_match';
      case NotificationType.productRecommend:
        return 'product_recommend';
      case NotificationType.styleResult:
        return 'style_result';
      case NotificationType.budgetReady:
        return 'budget_ready';
      case NotificationType.collectionUpdate:
        return 'collection_update';
      case NotificationType.system:
        return 'system';
      case NotificationType.promo:
        return 'promo';
    }
  }

  static String _actionToString(NotificationAction action) {
    switch (action) {
      case NotificationAction.openConversation:
        return 'open_conversation';
      case NotificationAction.openDesigner:
        return 'open_designer';
      case NotificationAction.openProduct:
        return 'open_product';
      case NotificationAction.openCollection:
        return 'open_collection';
      case NotificationAction.openChat:
        return 'open_chat';
      case NotificationAction.openUrl:
        return 'open_url';
    }
  }

  /// DB string'ini NotificationType'a cevir
  static NotificationType? parseType(String? value) {
    if (value == null) return null;
    switch (value) {
      case 'new_message':
        return NotificationType.newMessage;
      case 'designer_match':
        return NotificationType.designerMatch;
      case 'product_recommend':
        return NotificationType.productRecommend;
      case 'style_result':
        return NotificationType.styleResult;
      case 'budget_ready':
        return NotificationType.budgetReady;
      case 'collection_update':
        return NotificationType.collectionUpdate;
      case 'system':
        return NotificationType.system;
      case 'promo':
        return NotificationType.promo;
      default:
        return null;
    }
  }

  /// DB string'ini NotificationAction'a cevir
  static NotificationAction? parseAction(String? value) {
    if (value == null) return null;
    switch (value) {
      case 'open_conversation':
        return NotificationAction.openConversation;
      case 'open_designer':
        return NotificationAction.openDesigner;
      case 'open_product':
        return NotificationAction.openProduct;
      case 'open_collection':
        return NotificationAction.openCollection;
      case 'open_chat':
        return NotificationAction.openChat;
      case 'open_url':
        return NotificationAction.openUrl;
      default:
        return null;
    }
  }
}
