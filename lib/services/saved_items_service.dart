import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../core/config/env.dart';
import 'cache_service.dart';

/// Kaydedilen öğe tipleri
enum SavedItemType { design, designer, product }

/// Supabase saved_items tablosuyla CRUD
class SavedItemsService {
  SavedItemsService._();

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static SupabaseClient get _db => Supabase.instance.client;

  // ─── KAYDET ──────────────────────────────────────────
  static Future<bool> saveItem({
    required SavedItemType type,
    required String itemId,
    String? title,
    String? imageUrl,
    String? subtitle,
    Map<String, dynamic>? extraData,
    String? collectionId,
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return false;
    try {
      await _db.from('saved_items').upsert({
        'user_id': _uid,
        'item_type': type.name,
        'item_id': itemId,
        'title': title,
        'image_url': imageUrl,
        'subtitle': subtitle,
        'extra_data': extraData,
        if (collectionId != null) 'collection_id': collectionId,
      }, onConflict: 'user_id,item_type,item_id');
      CacheService.invalidatePrefix('saved_counts_');
      return true;
    } catch (e) {
      debugPrint('SavedItemsService.saveItem error: $e');
      return false;
    }
  }

  // ─── SİL ─────────────────────────────────────────────
  static Future<bool> removeItem({
    required SavedItemType type,
    required String itemId,
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return false;
    try {
      await _db
          .from('saved_items')
          .delete()
          .eq('user_id', _uid!)
          .eq('item_type', type.name)
          .eq('item_id', itemId);
      return true;
    } catch (e) {
      debugPrint('SavedItemsService.removeItem error: $e');
      return false;
    }
  }

  // ─── KAYITLI MI? ─────────────────────────────────────
  static Future<bool> isSaved({
    required SavedItemType type,
    required String itemId,
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return false;
    try {
      final res = await _db
          .from('saved_items')
          .select('id')
          .eq('user_id', _uid!)
          .eq('item_type', type.name)
          .eq('item_id', itemId)
          .limit(1);
      return (res as List).isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // ─── TİPE GÖRE LİSTELE ──────────────────────────────
  static Future<List<Map<String, dynamic>>> getByType(
    SavedItemType type, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return [];
    try {
      final res = await _db
          .from('saved_items')
          .select('id, item_id, item_type, title, image_url, subtitle, created_at')
          .eq('user_id', _uid!)
          .eq('item_type', type.name)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('SavedItemsService.getByType error: $e');
      rethrow;
    }
  }

  // ─── TÜM KAYDEDİLENLER ──────────────────────────────
  static Future<List<Map<String, dynamic>>> getAll({
    int limit = 50,
    int offset = 0,
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return [];
    try {
      final res = await _db
          .from('saved_items')
          .select('id, item_id, item_type, title, image_url, subtitle, created_at')
          .eq('user_id', _uid!)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('SavedItemsService.getAll error: $e');
      rethrow;
    }
  }

  // ─── KOLEKSİYONA GÖRE LİSTELE ───────────────────────
  static Future<List<Map<String, dynamic>>> getByCollection(
    String collectionId, {
    int limit = 50,
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return [];
    try {
      final res = await _db
          .from('saved_items')
          .select()
          .eq('user_id', _uid!)
          .eq('collection_id', collectionId)
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('SavedItemsService.getByCollection error: $e');
      return [];
    }
  }

  // ─── SAYILAR (profil sayfası için) ───────────────────
  static Future<Map<String, int>> getCounts() async {
    if (_uid == null || !Env.hasSupabaseConfig) {
      return {'design': 0, 'designer': 0, 'product': 0};
    }
    final cached = CacheService.get<Map<String, int>>('saved_counts_$_uid');
    if (cached != null) return cached;
    try {
      // Her tip için ayrı count sorgusu — tüm veriyi çekmekten çok daha verimli
      final designCount = await _db
          .from('saved_items')
          .select()
          .eq('user_id', _uid!)
          .eq('item_type', 'design')
          .count(CountOption.exact);
      final designerCount = await _db
          .from('saved_items')
          .select()
          .eq('user_id', _uid!)
          .eq('item_type', 'designer')
          .count(CountOption.exact);
      final productCount = await _db
          .from('saved_items')
          .select()
          .eq('user_id', _uid!)
          .eq('item_type', 'product')
          .count(CountOption.exact);
      final counts = {
        'design': designCount.count,
        'designer': designerCount.count,
        'product': productCount.count,
      };
      CacheService.set('saved_counts_$_uid', counts, duration: const Duration(minutes: 2));
      return counts;
    } catch (e) {
      return {'design': 0, 'designer': 0, 'product': 0};
    }
  }

  // ─── TOGGLE (kaydet/kaldır) ──────────────────────────
  static Future<bool> toggle({
    required SavedItemType type,
    required String itemId,
    String? title,
    String? imageUrl,
    String? subtitle,
    Map<String, dynamic>? extraData,
  }) async {
    final saved = await isSaved(type: type, itemId: itemId);
    if (saved) {
      return removeItem(type: type, itemId: itemId);
    } else {
      return saveItem(
        type: type,
        itemId: itemId,
        title: title,
        imageUrl: imageUrl,
        subtitle: subtitle,
        extraData: extraData,
      );
    }
  }
}
