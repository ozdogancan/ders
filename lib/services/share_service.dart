import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../core/config/env.dart';
import 'analytics_service.dart';
import 'messaging_service.dart';
import 'saved_items_service.dart';

/// Paylaşım servisi — tasarım/tasarımcı/ürünü chat, link veya sistem share
/// üzerinden paylaşır. Her paylaşım analytics + koala_shares tablosuna
/// log'lanır.
class ShareService {
  ShareService._();

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  static SupabaseClient get _db => Supabase.instance.client;

  /// Bir item için kanonik paylaşım URL'i. Evlumba domain'ine bağlı:
  ///   - design  → /proje/{id}
  ///   - designer → /tasarimci/{id}
  ///   - product → /urun/{id}
  static String publicUrl({
    required SavedItemType type,
    required String itemId,
  }) {
    switch (type) {
      case SavedItemType.design:
        return 'https://www.evlumba.com/proje/$itemId';
      case SavedItemType.designer:
        return 'https://www.evlumba.com/tasarimci/$itemId';
      case SavedItemType.product:
        return 'https://www.evlumba.com/urun/$itemId';
      case SavedItemType.palette:
        return 'https://www.evlumba.com/palet/$itemId';
      case SavedItemType.project:
        // Kullanıcının kendi projesi — kamuya açık URL yok, /proje/ fallback.
        return 'https://www.evlumba.com/proje/$itemId';
    }
  }

  /// Clipboard'a URL kopyala. UI snackbar'ı caller fire eder.
  static Future<void> copyLink({
    required SavedItemType type,
    required String itemId,
  }) async {
    final url = publicUrl(type: type, itemId: itemId);
    await Clipboard.setData(ClipboardData(text: url));
    await _log(type: type, itemId: itemId, channel: 'link', url: url);
  }

  /// OS native share sheet (iOS/Android sistem sheet'i; web → Web Share API
  /// fallback ile clipboard). share_plus tüm platformlarda çalışır.
  static Future<void> nativeShare({
    required SavedItemType type,
    required String itemId,
    String? title,
  }) async {
    final url = publicUrl(type: type, itemId: itemId);
    final text = title != null && title.isNotEmpty ? '$title\n$url' : url;
    try {
      await Share.share(text);
    } catch (e) {
      debugPrint('ShareService.nativeShare error: $e');
      // Fallback → clipboard
      await Clipboard.setData(ClipboardData(text: url));
    }
    await _log(type: type, itemId: itemId, channel: 'system', url: url);
  }

  /// Chat'te paylaş — mevcut bir sohbete tasarımı image mesajı olarak gönderir.
  /// imageUrl verilirse attachment olarak gider; yoksa sadece text + link.
  static Future<bool> shareInChat({
    required SavedItemType type,
    required String itemId,
    required String conversationId,
    String? designerId,
    String? title,
    String? imageUrl,
  }) async {
    final url = publicUrl(type: type, itemId: itemId);
    final caption = title != null && title.isNotEmpty ? '$title — $url' : url;
    try {
      Map<String, dynamic>? sent;
      if (imageUrl != null && imageUrl.isNotEmpty) {
        sent = await MessagingService.sendMessage(
          conversationId: conversationId,
          content: caption,
          type: MessageType.image,
          attachmentUrl: imageUrl,
        );
      } else {
        sent = await MessagingService.sendMessage(
          conversationId: conversationId,
          content: caption,
        );
      }
      if (sent == null) return false;
      await _log(
        type: type,
        itemId: itemId,
        channel: 'chat',
        url: url,
        conversationId: conversationId,
        designerId: designerId,
      );
      return true;
    } catch (e) {
      debugPrint('ShareService.shareInChat error: $e');
      return false;
    }
  }

  /// Design preview ile sohbete navigate eden yeni flow için public logging.
  /// Mesajı gönderen ConversationDetailScreen — bu fn sadece
  /// koala_shares + analytics'e "chat" kanalını kaydeder.
  static Future<void> logShareInChat({
    required SavedItemType type,
    required String itemId,
    required String conversationId,
    String? designerId,
  }) async {
    await _log(
      type: type,
      itemId: itemId,
      channel: 'chat',
      url: publicUrl(type: type, itemId: itemId),
      conversationId: conversationId,
      designerId: designerId,
    );
  }

  // DB + analytics çift log.
  static Future<void> _log({
    required SavedItemType type,
    required String itemId,
    required String channel,
    required String url,
    String? conversationId,
    String? designerId,
  }) async {
    // Analytics event (best-effort)
    unawaited(Analytics.log('share', {
      'item_type': type.name,
      'item_id': itemId,
      'channel': channel,
    }));
    // koala_shares tablosu (history + audit)
    if (_uid == null || !Env.hasSupabaseConfig) return;
    try {
      await _db.from('koala_shares').insert({
        'user_id': _uid,
        'item_type': type.name,
        'item_id': itemId,
        'channel': channel,
        'share_url': url,
        if (conversationId != null) 'target_conversation_id': conversationId,
        if (designerId != null) 'target_designer_id': designerId,
      });
    } catch (e) {
      debugPrint('ShareService._log DB error: $e');
    }
  }
}
