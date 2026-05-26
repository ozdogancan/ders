// Uygulama içi bildirim feed'i — koala_notifications.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

class KoalaNotification {
  final String id;
  final String type;
  final String title;
  final String? body;
  final String? imageUrl;
  final String? actionType;
  final Map<String, dynamic>? actionData;
  final bool read;
  final DateTime createdAt;

  const KoalaNotification({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.imageUrl,
    this.actionType,
    this.actionData,
    required this.read,
    required this.createdAt,
  });

  factory KoalaNotification.fromRow(Map<String, dynamic> r) {
    return KoalaNotification(
      id: r['id'].toString(),
      type: (r['type'] ?? '').toString(),
      title: (r['title'] ?? '').toString(),
      body: r['body']?.toString(),
      imageUrl: r['image_url']?.toString(),
      actionType: r['action_type']?.toString(),
      actionData:
          r['action_data'] is Map ? Map<String, dynamic>.from(r['action_data']) : null,
      read: r['is_read'] == true,
      createdAt:
          DateTime.tryParse(r['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  String? get designerId =>
      actionData?['designer_id']?.toString();
  String? get cardId => actionData?['card_id']?.toString();
}

class NotificationsFeedService {
  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static Future<List<KoalaNotification>> list({int limit = 50}) async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final data = await Supabase.instance.client
          .from('koala_notifications')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(data)
          .map(KoalaNotification.fromRow)
          .toList();
    } catch (e) {
      debugPrint('[notif] list failed: $e');
      return const [];
    }
  }

  static Future<int> unreadCount() async {
    final uid = _uid;
    if (uid == null) return 0;
    try {
      final res = await Supabase.instance.client
          .from('koala_notifications')
          .select('id')
          .eq('user_id', uid)
          .eq('is_read', false);
      return (res as List).length;
    } catch (e) {
      debugPrint('[notif] unread failed: $e');
      return 0;
    }
  }

  static Future<void> markRead(String id) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await Supabase.instance.client.rpc(
        'koala_notif_mark_read',
        params: {'p_user_id': uid, 'p_id': id},
      );
    } catch (e) {
      debugPrint('[notif] mark read failed: $e');
    }
  }

  static Future<void> markAllRead() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await Supabase.instance.client.rpc(
        'koala_notif_mark_all_read',
        params: {'p_user_id': uid},
      );
    } catch (e) {
      debugPrint('[notif] mark all read failed: $e');
    }
  }
}

/// Unread sayısı — AppBar çan rozetinde watch'lanır. Her 60sn yenilenir.
class UnreadNotificationsNotifier extends AsyncNotifier<int> {
  Timer? _timer;

  @override
  Future<int> build() async {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
    return NotificationsFeedService.unreadCount();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(NotificationsFeedService.unreadCount);
  }

  /// Optimistic decrement — bildirim okundu işaretlenince UI'yi anında güncelle.
  void decrement([int by = 1]) {
    final current = state.asData?.value ?? 0;
    final next = (current - by).clamp(0, 1 << 30);
    state = AsyncValue.data(next);
  }

  void zero() {
    state = const AsyncValue.data(0);
  }
}

final unreadNotificationsProvider =
    AsyncNotifierProvider<UnreadNotificationsNotifier, int>(
  UnreadNotificationsNotifier.new,
);
