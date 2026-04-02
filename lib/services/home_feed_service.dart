import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../core/config/env.dart';
import 'cache_service.dart';

/// Home feed — tek Supabase RPC ile ana sayfa verisi.
/// 4-5 ayri API cagrisini tek sorguya indirir.
class HomeFeedService {
  HomeFeedService._();

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Ana sayfa verisi (saved_items, conversations, unread counts)
  static Future<HomeFeed> getHomeFeed() async {
    if (_uid == null || !Env.hasSupabaseConfig) return HomeFeed.empty();

    // Cache kontrol (1 dakika)
    final cached = CacheService.get<HomeFeed>('home_feed_$_uid');
    if (cached != null) return cached;

    try {
      final result = await Supabase.instance.client.rpc(
        'get_home_feed',
        params: {'p_user_id': _uid},
      );

      final data = result as Map<String, dynamic>;
      final feed = HomeFeed(
        savedItems: List<Map<String, dynamic>>.from(data['saved_items'] ?? []),
        conversations: List<Map<String, dynamic>>.from(data['conversations'] ?? []),
        unreadMessages: (data['unread_messages'] as num?)?.toInt() ?? 0,
        unreadNotifications: (data['unread_notifications'] as num?)?.toInt() ?? 0,
      );

      CacheService.set('home_feed_$_uid', feed, duration: const Duration(minutes: 1));
      return feed;
    } catch (e) {
      debugPrint('HomeFeedService error: $e');
      return HomeFeed.empty();
    }
  }

  /// Cache invalidate (mesaj gonderme, kaydetme sonrasi)
  static void invalidate() {
    CacheService.invalidatePrefix('home_feed_');
  }
}

class HomeFeed {
  final List<Map<String, dynamic>> savedItems;
  final List<Map<String, dynamic>> conversations;
  final int unreadMessages;
  final int unreadNotifications;

  HomeFeed({
    required this.savedItems,
    required this.conversations,
    required this.unreadMessages,
    required this.unreadNotifications,
  });

  factory HomeFeed.empty() => HomeFeed(
    savedItems: [],
    conversations: [],
    unreadMessages: 0,
    unreadNotifications: 0,
  );
}
