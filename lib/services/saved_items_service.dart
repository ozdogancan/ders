import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../core/config/env.dart';
import 'analytics_service.dart';
import 'auth_token_service.dart';
import 'cache_service.dart';

/// Kaydedilen öğe tipleri.
/// `project` — kullanıcının kendi mekanına AI ile uyguladığı before/after
/// tasarımları (Projelerim sekmesinde listelenir, item_type='project').
enum SavedItemType { design, designer, product, palette, project }

/// Supabase saved_items tablosuyla CRUD
class SavedItemsService {
  SavedItemsService._();

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static SupabaseClient get _db => Supabase.instance.client;

  /// UI'ın okuyabilmesi için son hata mesajı (isSaved/saveItem/removeItem).
  /// `MessagingService.lastConvError` pattern'iyle aynı.
  static String? lastError;

  // ─── PROXY: koala-api üzerinden CRUD (RLS bypass) ────
  // saved_items tablosunda anon policy yok; service_role gerekiyor.
  // koala-api `/api/saved-items` endpoint'i service_role kullanıp RLS'yi atlar.
  static Future<Map<String, dynamic>?> _callProxy(Map<String, dynamic> body) async {
    try {
      final resp = await http
          .post(
            Uri.parse('${Env.koalaApiUrl}/api/saved-items'),
            headers: {
              ...await AuthTokenService.authHeaders(),
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode >= 400) {
        lastError = (j['error'] ?? 'http_${resp.statusCode}').toString();
        return null;
      }
      return j;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

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
    if (_uid == null) return false;
    final res = await _callProxy({
      'op': 'save',
      'userId': _uid,
      'itemType': type.name,
      'itemId': itemId,
      if (title != null) 'title': title,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (subtitle != null) 'subtitle': subtitle,
      if (extraData != null) 'extraData': extraData,
      if (collectionId != null) 'collectionId': collectionId,
    });
    if (res == null) {
      debugPrint('SavedItemsService.saveItem error: $lastError');
      return false;
    }
    CacheService.invalidatePrefix('saved_counts_');
    unawaited(Analytics.log('save', {
      'item_type': type.name,
      'item_id': itemId,
      if (collectionId != null) 'collection_id': collectionId,
    }));
    return true;
  }

  // ─── SİL ─────────────────────────────────────────────
  static Future<bool> removeItem({
    required SavedItemType type,
    required String itemId,
  }) async {
    if (_uid == null) return false;
    final res = await _callProxy({
      'op': 'remove',
      'userId': _uid,
      'itemType': type.name,
      'itemId': itemId,
    });
    if (res == null) {
      debugPrint('SavedItemsService.removeItem error: $lastError');
      return false;
    }
    CacheService.invalidatePrefix('saved_counts_');
    unawaited(Analytics.log('unsave', {
      'item_type': type.name,
      'item_id': itemId,
    }));
    return true;
  }

  // ─── KAYITLI MI? ─────────────────────────────────────
  static Future<bool> isSaved({
    required SavedItemType type,
    required String itemId,
  }) async {
    if (_uid == null) return false;
    final res = await _callProxy({
      'op': 'isSaved',
      'userId': _uid,
      'itemType': type.name,
      'itemId': itemId,
    });
    if (res == null) return false;
    return res['saved'] == true;
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
          .select('id, item_id, item_type, title, image_url, subtitle, extra_data, created_at')
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
      return {
        'design': 0,
        'designer': 0,
        'product': 0,
        'palette': 0,
        'project': 0,
      };
    }
    final cached = CacheService.get<Map<String, int>>('saved_counts_$_uid');
    if (cached != null) return cached;
    try {
      // 5 COUNT sorgusu paralel — sequential'dan ~5x hızlı.
      // 'project' tipi: AI ile üretilen + tasarımcı portföyünden kaydedilen.
      final results = await Future.wait([
        _db
            .from('saved_items')
            .select()
            .eq('user_id', _uid!)
            .eq('item_type', 'design')
            .count(CountOption.exact),
        _db
            .from('saved_items')
            .select()
            .eq('user_id', _uid!)
            .eq('item_type', 'designer')
            .count(CountOption.exact),
        _db
            .from('saved_items')
            .select()
            .eq('user_id', _uid!)
            .eq('item_type', 'product')
            .count(CountOption.exact),
        _db
            .from('saved_items')
            .select()
            .eq('user_id', _uid!)
            .eq('item_type', 'palette')
            .count(CountOption.exact),
        _db
            .from('saved_items')
            .select()
            .eq('user_id', _uid!)
            .eq('item_type', 'project')
            .count(CountOption.exact),
      ]);
      final counts = {
        'design': results[0].count,
        'designer': results[1].count,
        'product': results[2].count,
        'palette': results[3].count,
        'project': results[4].count,
      };
      CacheService.set('saved_counts_$_uid', counts, duration: const Duration(minutes: 2));
      return counts;
    } catch (e) {
      return {
        'design': 0,
        'designer': 0,
        'product': 0,
        'palette': 0,
        'project': 0,
      };
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
