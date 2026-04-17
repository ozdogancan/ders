import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../core/config/env.dart';
import 'analytics_service.dart';
import 'saved_items_service.dart';

/// Beğen (like) için Supabase koala_likes CRUD.
///
/// NEDEN saved_items'tan ayrı?
///   - Save = "sonra geri dönmek için" (yer imi). Collection'a eklenebilir.
///   - Like = "anlık beğeni" sinyali. Analytics + profil recommend ağırlığı.
///   Aynı tabloyu kullanırsak iki sinyali karıştırırız; ayrı tutuyoruz.
class LikesService {
  LikesService._();

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  static SupabaseClient get _db => Supabase.instance.client;

  static Future<bool> like({
    required SavedItemType type,
    required String itemId,
    String? title,
    String? imageUrl,
    String? subtitle,
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return false;
    try {
      await _db.from('koala_likes').upsert({
        'user_id': _uid,
        'item_type': type.name,
        'item_id': itemId,
        'title': title,
        'image_url': imageUrl,
        'subtitle': subtitle,
      }, onConflict: 'user_id,item_type,item_id');
      // Analytics: beğeni sinyali
      unawaited(Analytics.log('like', {
        'item_type': type.name,
        'item_id': itemId,
      }));
      return true;
    } catch (e) {
      debugPrint('LikesService.like error: $e');
      return false;
    }
  }

  static Future<bool> unlike({
    required SavedItemType type,
    required String itemId,
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return false;
    try {
      await _db
          .from('koala_likes')
          .delete()
          .eq('user_id', _uid!)
          .eq('item_type', type.name)
          .eq('item_id', itemId);
      unawaited(Analytics.log('unlike', {
        'item_type': type.name,
        'item_id': itemId,
      }));
      return true;
    } catch (e) {
      debugPrint('LikesService.unlike error: $e');
      return false;
    }
  }

  static Future<bool> isLiked({
    required SavedItemType type,
    required String itemId,
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return false;
    try {
      final res = await _db
          .from('koala_likes')
          .select('id')
          .eq('user_id', _uid!)
          .eq('item_type', type.name)
          .eq('item_id', itemId)
          .limit(1);
      return (res as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> toggle({
    required SavedItemType type,
    required String itemId,
    String? title,
    String? imageUrl,
    String? subtitle,
  }) async {
    final liked = await isLiked(type: type, itemId: itemId);
    if (liked) return unlike(type: type, itemId: itemId);
    return like(
      type: type,
      itemId: itemId,
      title: title,
      imageUrl: imageUrl,
      subtitle: subtitle,
    );
  }

  static Future<List<Map<String, dynamic>>> getByType(
    SavedItemType type, {
    int limit = 50,
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return [];
    try {
      final res = await _db
          .from('koala_likes')
          .select()
          .eq('user_id', _uid!)
          .eq('item_type', type.name)
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('LikesService.getByType error: $e');
      return [];
    }
  }
}
