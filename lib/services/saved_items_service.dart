import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../core/config/env.dart';
import 'analytics_service.dart';
import 'auth_token_service.dart';
import 'cache_service.dart';
import 'quota_service.dart';

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

  /// Boot-time'da disk cache'den warm edilen projects snapshot. Projelerim
  /// sekmesi initState'te bunu sync olarak okuyup skeleton flicker'sız
  /// anında grid'i çizebilir. Network fetch gelince üzerine yazılır.
  static List<Map<String, dynamic>>? prefetchedProjects;

  /// `prefetchedProjects` her güncellendiğinde bump edilir. Projeler ekranı
  /// bu notifier'a subscribe olup yeni tasarım eklendiğinde anında rebuild
  /// edebilir — kullanıcı result_stage'den döndüğünde save async bitmiş
  /// olsa bile UI gecikmesiz güncellenir.
  static final ValueNotifier<int> projectsTick = ValueNotifier<int>(0);

  static const String _prefsProjectsCacheKey = 'projeler_disk_cache_v1';
  static const int _projectsCacheMax = 24;

  /// main.dart boot sırasında çağrılır — disk'ten önceki oturumun
  /// projects listesini RAM'e alır. Hızlı (~5-15ms), JSON decode dahil.
  static Future<void> warmFromDiskCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsProjectsCacheKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      if (list.isNotEmpty) prefetchedProjects = list;
    } catch (_) {}
  }

  /// Fresh fetch sonrası projelerim disk cache'ini günceller.
  static Future<void> persistProjectsCache(
      List<Map<String, dynamic>> rows) async {
    try {
      final snap = rows.take(_projectsCacheMax).toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsProjectsCacheKey, jsonEncode(snap));
      prefetchedProjects = snap;
      projectsTick.value++;
    } catch (_) {}
  }

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
          .timeout(const Duration(seconds: 45));
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 402 && j['feature'] == 'save') {
        lastError = 'QUOTA_EXCEEDED';
        QuotaService.onQuotaExceeded?.call('save_quota');
        return null;
      }
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
  /// Bir string `data:` URL ise (base64 image, 1-3MB olabilir) → boş string dön.
  /// Yoksa olduğu gibi. Vercel function 4.5MB body limiti var; data URL'ler
  /// gönderirsek FUNCTION_PAYLOAD_TOO_LARGE alıyoruz (kullanıcı bug raporu).
  static String _stripDataUrl(String? v) {
    if (v == null || v.isEmpty) return '';
    if (v.startsWith('data:')) return '';
    return v;
  }

  static Map<String, dynamic> _stripDataUrlsFromMap(Map<String, dynamic> m) {
    final out = <String, dynamic>{};
    m.forEach((k, val) {
      if (val is String && val.startsWith('data:')) {
        // data URL — atla (image_url field'ı zaten ayrı stripleniyor).
        return;
      }
      out[k] = val;
    });
    return out;
  }

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
    // CRITICAL: data URL'leri body'den çıkar. 3MB base64 image → Vercel
    // function payload too large → save tamamen başarısız oluyor.
    // Image kayıp olarak işaretleniyor, ileride uploadAfter patch eder.
    final cleanImageUrl =
        imageUrl != null ? _stripDataUrl(imageUrl) : null;
    final cleanExtra =
        extraData != null ? _stripDataUrlsFromMap(extraData) : null;
    final res = await _callProxy({
      'op': 'save',
      'userId': _uid,
      'itemType': type.name,
      'itemId': itemId,
      if (title != null) 'title': title,
      if (cleanImageUrl != null) 'imageUrl': cleanImageUrl,
      if (subtitle != null) 'subtitle': subtitle,
      if (cleanExtra != null) 'extraData': cleanExtra,
      if (collectionId != null) 'collectionId': collectionId,
    });
    if (res == null) {
      debugPrint('SavedItemsService.saveItem error: $lastError');
      return false;
    }
    CacheService.invalidatePrefix('saved_counts_');
    // Projeler için: yeni satırı warm cache'e ekle ki Projelerim refresh
    // beklemeden anında yeni tasarımı göstersin (kullanıcı bug raporu —
    // "analiz yapıyorum projelerim ekranına otomatik gelmedi").
    if (type == SavedItemType.project) {
      // Cache'e de strip edilmiş halini koy — disk cache'in 3MB string ile
      // şişmesini engelle (localStorage quota 5MB).
      final newRow = <String, dynamic>{
        'id': '',
        'item_id': itemId,
        'item_type': 'project',
        if (title != null) 'title': title,
        'image_url': cleanImageUrl ?? '',
        if (subtitle != null) 'subtitle': subtitle,
        if (cleanExtra != null) 'extra_data': cleanExtra,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };
      final existing = prefetchedProjects ?? const <Map<String, dynamic>>[];
      // itemId duplicate ise eski satırı çıkar, yenisini başa koy.
      final filtered = existing
          .where((row) => (row['item_id'] ?? '').toString() != itemId)
          .toList();
      filtered.insert(0, newRow);
      await persistProjectsCache(filtered);
    }
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
    // Projeler için disk cache + RAM static'i de güncelle, yoksa refresh
    // sonrası warm cache'ten silinen tasarım geri gelir (kullanıcı bug
    // raporu — "siliyorum refresh atınca yine geliyor").
    if (type == SavedItemType.project && prefetchedProjects != null) {
      final updated = prefetchedProjects!
          .where((row) => (row['item_id'] ?? '').toString() != itemId)
          .toList(growable: false);
      await persistProjectsCache(updated);
    }
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

  /// API tarafında uygulanan tip rewrite'larıyla aynı (route.ts ile senkron).
  /// `design` → `style`, `palette` → `product`. saved_items check constraint
  /// `product|project|designer|style` izin veriyor.
  static String _serverItemType(SavedItemType type) {
    switch (type) {
      case SavedItemType.design:
        return 'style';
      case SavedItemType.palette:
        return 'product';
      default:
        return type.name;
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
          .select('id, item_id, item_type, title, image_url, subtitle, extra_data, created_at')
          .eq('user_id', _uid!)
          .eq('item_type', _serverItemType(type))
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
      // 'project' tipi: AI ile üretilen mekan tasarımları (Projelerim).
      // 'style' tipi: style_discovery swipe-likes (eski 'design' → 'style' map).
      final results = await Future.wait([
        _db
            .from('saved_items')
            .select()
            .eq('user_id', _uid!)
            .eq('item_type', 'style')
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
