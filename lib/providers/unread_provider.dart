import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/messaging_service.dart';
import '../services/notifications_service.dart';

/// Okunmamış mesaj sayısı — badge için
final unreadMessagesProvider = FutureProvider.autoDispose<int>((ref) async {
  return MessagingService.getTotalUnreadCount();
});

/// Okunmamış bildirim sayısı — badge için
final unreadNotificationsProvider = FutureProvider.autoDispose<int>((ref) async {
  return NotificationsService.getUnreadCount();
});
