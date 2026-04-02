import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../core/config/env.dart';

/// Supabase collections tablosuyla CRUD
class CollectionsService {
  CollectionsService._();

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  static SupabaseClient get _db => Supabase.instance.client;

  // ─── OLUŞTUR ─────────────────────────────────────────
  static Future<String?> create({
    required String name,
    String? description,
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return null;
    try {
      final res = await _db.from('collections').insert({
        'user_id': _uid,
        'name': name,
        'description': description,
      }).select('id').single();
      return res['id'] as String;
    } catch (e) {
      debugPrint('CollectionsService.create error: $e');
      return null;
    }
  }

  // ─── GÜNCELLE ────────────────────────────────────────
  static Future<bool> update({
    required String id,
    String? name,
    String? description,
    String? coverImageUrl,
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return false;
    try {
      final data = <String, dynamic>{};
      if (name != null) data['name'] = name;
      if (description != null) data['description'] = description;
      if (coverImageUrl != null) data['cover_image_url'] = coverImageUrl;
      if (data.isEmpty) return false;

      await _db.from('collections').update(data).eq('id', id).eq('user_id', _uid!);
      return true;
    } catch (e) {
      debugPrint('CollectionsService.update error: $e');
      return false;
    }
  }

  // ─── SİL ─────────────────────────────────────────────
  static Future<bool> delete(String id) async {
    if (_uid == null || !Env.hasSupabaseConfig) return false;
    try {
      await _db.from('collections').delete().eq('id', id).eq('user_id', _uid!);
      return true;
    } catch (e) {
      debugPrint('CollectionsService.delete error: $e');
      return false;
    }
  }

  // ─── LİSTELE ─────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getAll({int limit = 50}) async {
    if (_uid == null || !Env.hasSupabaseConfig) return [];
    try {
      final res = await _db
          .from('collections')
          .select()
          .eq('user_id', _uid!)
          .order('updated_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('CollectionsService.getAll error: $e');
      return [];
    }
  }

  // ─── TEK KOLEKSİYON ─────────────────────────────────
  static Future<Map<String, dynamic>?> getById(String id) async {
    if (_uid == null || !Env.hasSupabaseConfig) return null;
    try {
      final res = await _db
          .from('collections')
          .select()
          .eq('id', id)
          .eq('user_id', _uid!)
          .single();
      return res;
    } catch (e) {
      return null;
    }
  }

  // ─── ÖĞEYE KOLEKSİYON ATA ───────────────────────────
  static Future<bool> addItemToCollection({
    required String savedItemId,
    required String collectionId,
  }) async {
    if (!Env.hasSupabaseConfig) return false;
    try {
      await _db
          .from('saved_items')
          .update({'collection_id': collectionId})
          .eq('id', savedItemId);
      return true;
    } catch (e) {
      debugPrint('CollectionsService.addItemToCollection error: $e');
      return false;
    }
  }

  // ─── ÖĞEDEN KOLEKSİYONU KALDIR ──────────────────────
  static Future<bool> removeItemFromCollection(String savedItemId) async {
    if (!Env.hasSupabaseConfig) return false;
    try {
      await _db
          .from('saved_items')
          .update({'collection_id': null})
          .eq('id', savedItemId);
      return true;
    } catch (e) {
      debugPrint('CollectionsService.removeItemFromCollection error: $e');
      return false;
    }
  }
}
