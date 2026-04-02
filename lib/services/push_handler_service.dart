import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Push notification deep link handler.
/// FCM mesajlarından uygulama içi navigasyon.
class PushHandlerService {
  PushHandlerService._();

  static GoRouter? _router;
  static GlobalKey<ScaffoldMessengerState>? _messengerKey;

  /// App başlangıcında çağır (main.dart veya app.dart)
  static void initialize(GoRouter router, {GlobalKey<ScaffoldMessengerState>? messengerKey}) {
    _router = router;
    _messengerKey = messengerKey;

    // Foreground mesajları dinle
    FirebaseMessaging.onMessage.listen(_handleForeground);

    // Background'dan açılma (uygulama minimized iken tap)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

    // Terminated state (uygulama kapalıyken tap)
    _checkInitialMessage();
  }

  static Future<void> _checkInitialMessage() async {
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _navigateFromPayload(initial.data);
    } catch (_) {}
  }

  static void _handleTap(RemoteMessage message) {
    _navigateFromPayload(message.data);
  }

  static void _handleForeground(RemoteMessage message) {
    debugPrint('PushHandler: foreground message: ${message.data}');
    final notification = message.notification;
    if (notification == null || _messengerKey?.currentState == null) return;

    final title = notification.title ?? '';
    final body = notification.body ?? '';
    final data = message.data;

    _messengerKey!.currentState!.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1A1D2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
            if (body.isNotEmpty)
              Text(body, style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 2),
          ],
        ),
        action: SnackBarAction(
          label: 'Aç',
          textColor: const Color(0xFF7C6EF2),
          onPressed: () => _navigateFromPayload(data),
        ),
      ),
    );
  }

  static void _navigateFromPayload(Map<String, dynamic> data) {
    if (_router == null) return;

    final actionType = data['action_type'] as String? ?? data['type'] as String?;
    final conversationId = data['conversation_id'] as String?;
    final designerName = data['sender_name'] as String?;

    switch (actionType) {
      case 'open_conversation':
      case 'new_message':
        if (conversationId != null) {
          _router!.push('/chat/dm/$conversationId', extra: {
            'designerName': designerName ?? 'Tasarımcı',
          });
        }
        break;
      case 'open_chat':
        _router!.push('/chat/ai');
        break;
      case 'designer_match':
        _router!.push('/designers');
        break;
      case 'open_collection':
        _router!.push('/collections');
        break;
      default:
        // Bilinmeyen tip — notifications ekranına git
        _router!.push('/notifications');
        break;
    }
  }
}
