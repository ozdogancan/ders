// Kullanıcının "+" (Paylaş) ile yüklediği IG-tarzı oda paylaşımları için
// veri katmanı. `koala_user_shared_designs` tablosunu okur/yazar.
//
// Profil ekranı "Paylaştıklarım" sekmesinin kaynağı.
//
// TODO[profile-agent]: profile_tab_screen.dart#_loadDesigns() içine
//   SharedDesignService.myShared() çağrısı eklenmeli — şu an liste
//   `const []` ile sabit boş döndürülüyor.

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, FileOptions, CountOption;
import 'package:uuid/uuid.dart';

import '../core/config/env.dart';
import 'auth_token_service.dart';

class SharedDesign {
  final String id;
  final String userId;
  final String imageUrl;
  final String? thumbUrl;
  final String? title;
  final String? description;
  final String? roomType;
  final List<String> tags;
  final String status;
  final String? moderationReason;
  final DateTime createdAt;
  final DateTime? publishedAt;

  const SharedDesign({
    required this.id,
    required this.userId,
    required this.imageUrl,
    this.thumbUrl,
    this.title,
    this.description,
    this.roomType,
    this.tags = const [],
    required this.status,
    this.moderationReason,
    required this.createdAt,
    this.publishedAt,
  });

  factory SharedDesign.fromRow(Map<String, dynamic> r) {
    final rawTags = r['tags'];
    final tags = rawTags is List
        ? rawTags.map((e) => e.toString()).toList(growable: false)
        : const <String>[];
    return SharedDesign(
      id: r['id'].toString(),
      userId: (r['user_id'] ?? '').toString(),
      imageUrl: (r['image_url'] ?? '').toString(),
      thumbUrl: r['thumb_url']?.toString(),
      title: r['title']?.toString(),
      description: r['description']?.toString(),
      roomType: r['room_type']?.toString(),
      tags: tags,
      status: (r['status'] ?? 'pending').toString(),
      moderationReason: r['moderation_reason']?.toString(),
      createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '') ??
          DateTime.now(),
      publishedAt: r['published_at'] != null
          ? DateTime.tryParse(r['published_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMapForProfileTab() => {
        'id': id,
        'image_url': imageUrl,
        'thumb_url': thumbUrl,
        'title': title ?? '',
        'description': description ?? '',
        'room_type': roomType,
        'tags': tags,
        'status': status,
        'created_at': createdAt.toIso8601String(),
        'published_at': publishedAt?.toIso8601String(),
      };
}

class ShareModerationResult {
  final bool ok;
  final String? reason;
  final String? detail;
  /// 2026-05-28 FIX 2: auto-detected room type (one of the closed enum
  /// returned by the moderation API — 'salon', 'yatak_odasi', etc).
  /// Empty when unsure or when ok==false.
  final String roomType;
  /// 2026-05-28 FIX 2: auto-detected style ('modern', 'minimal', ...).
  /// Empty when unsure or when ok==false.
  final String style;
  const ShareModerationResult({
    required this.ok,
    this.reason,
    this.detail,
    this.roomType = '',
    this.style = '',
  });
}

class SharedDesignService {
  SharedDesignService._();

  static const String _table = 'koala_user_shared_designs';

  /// 2026-06-02: Yeni bir tasarım yayınlandığında artar. Profil sekmesi bunu
  /// dinleyip grid'i anında tazeler ("Tasarımın yayında" → profilde görünür).
  static final ValueNotifier<int> publishedTick = ValueNotifier<int>(0);

  // Storage bucket — `design-uploads` zaten upload-image API'sinde kullanılıyor.
  // Ayrı `shared-designs` bucket'ı yok; aynı bucket'a `shared/{uid}/` prefix
  // ile yüklüyoruz (path ayrımı izolasyon için yeterli).
  static const String _bucket = 'design-uploads';

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // ─── Görseli yükle (Supabase Storage doğrudan) ───
  /// Optimize edilmiş bytes'ı Supabase Storage'a yükler. Public URL döner.
  static Future<String?> uploadImage(Uint8List bytes) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final id = const Uuid().v4();
      final path = 'shared/$uid/$id.jpg';
      await Supabase.instance.client.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );
      final url =
          Supabase.instance.client.storage.from(_bucket).getPublicUrl(path);
      return url;
    } catch (e) {
      debugPrint('[SharedDesignService] upload failed: $e');
      return null;
    }
  }

  // ─── Görüntülenme sayacı ───
  /// Detay görüntüleyici bir paylaşım tasarımını gösterince çağrılır.
  /// Var olmayan id (Evlumba projesi) zararsız (0 satır). Fire-and-forget.
  static Future<void> incrementView(String id) async {
    if (id.isEmpty) return;
    try {
      await Supabase.instance.client
          .rpc('koala_increment_design_view', params: {'p_id': id});
    } catch (_) {/* sessiz — vanity metrik */}
  }

  /// Bir kullanıcının yayınlanmış tasarımlarının toplam görüntülenmesi.
  /// Profil "İstatistikler" (owner-only) için.
  static Future<int> totalViews({String? ownerUid}) async {
    final uid = ownerUid ?? _uid;
    if (uid == null) return 0;
    try {
      final rows = await Supabase.instance.client
          .from(_table)
          .select('view_count')
          .eq('user_id', uid)
          .eq('status', 'published');
      var sum = 0;
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        sum += (r['view_count'] as num?)?.toInt() ?? 0;
      }
      return sum;
    } catch (e) {
      debugPrint('[SharedDesignService] totalViews failed: $e');
      return 0;
    }
  }

  // ─── AI moderation gate (koala-api) ───
  static Future<ShareModerationResult> moderate({
    required String imageUrl,
  }) async {
    final uid = _uid ?? 'anon';
    try {
      final res = await http
          .post(
            Uri.parse('${Env.koalaApiUrl}/api/share/moderate'),
            headers: {
              ...await AuthTokenService.authHeaders(),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'imageUrl': imageUrl, 'userId': uid}),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        return ShareModerationResult(
          ok: false,
          reason: 'http_${res.statusCode}',
          detail: res.body,
        );
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return ShareModerationResult(
        ok: j['ok'] == true,
        reason: j['reason']?.toString(),
        detail: j['detail']?.toString(),
        roomType: (j['room_type'] ?? '').toString(),
        style: (j['style'] ?? '').toString(),
      );
    } catch (e) {
      debugPrint('[SharedDesignService] moderate error: $e');
      return ShareModerationResult(ok: false, reason: 'network', detail: '$e');
    }
  }

  // ─── Yayınla (insert published row) ───
  static Future<SharedDesign?> publish({
    required String imageUrl,
    String? title,
    String? description,
    String? roomType,
    List<String> tags = const [],
  }) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final now = DateTime.now().toIso8601String();
      final row = {
        'user_id': uid,
        'image_url': imageUrl,
        'title': title,
        'description': description,
        'room_type': roomType,
        'tags': tags,
        'status': 'published',
        'published_at': now,
      };
      final inserted = await Supabase.instance.client
          .from(_table)
          .insert(row)
          .select()
          .single();
      // Profil sekmesi grid'ini tazelesin.
      publishedTick.value++;
      return SharedDesign.fromRow(Map<String, dynamic>.from(inserted));
    } catch (e) {
      debugPrint('[SharedDesignService] publish failed: $e');
      return null;
    }
  }

  // ─── Başka bir kullanıcının public paylaşımları ───
  /// Mini-profile sheet için. Yalnız published kayıtlar döner.
  static Future<List<SharedDesign>> publicByUid(String uid,
      {int limit = 40}) async {
    if (uid.isEmpty) return const [];
    try {
      final data = await Supabase.instance.client
          .from(_table)
          .select()
          .eq('user_id', uid)
          .eq('status', 'published')
          .order('published_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(data)
          .map(SharedDesign.fromRow)
          .toList();
    } catch (e) {
      debugPrint('[SharedDesignService] publicByUid failed: $e');
      return const [];
    }
  }

  // ─── Kullanıcının paylaşımları ───
  /// "Paylaştıklarım" sekmesi için. Sadece kendi published kayıtlarını döner.
  static Future<List<SharedDesign>> myShared({int limit = 40}) async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final data = await Supabase.instance.client
          .from(_table)
          .select()
          .eq('user_id', uid)
          .eq('status', 'published')
          .order('published_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(data)
          .map(SharedDesign.fromRow)
          .toList();
    } catch (e) {
      debugPrint('[SharedDesignService] myShared failed: $e');
      return const [];
    }
  }

  // ─── PAGINATED variants (cursor: published_at ISO string) ───
  /// Başka kullanıcının paylaşımları — paginated.
  static Future<({List<SharedDesign> items, bool hasMore, dynamic cursor})>
      publicByUidPaged(
    String uid, {
    int limit = 18,
    String? beforeCreatedAt,
  }) async {
    if (uid.isEmpty) {
      return (items: <SharedDesign>[], hasMore: false, cursor: null);
    }
    try {
      var q = Supabase.instance.client
          .from(_table)
          .select()
          .eq('user_id', uid)
          .eq('status', 'published');
      if (beforeCreatedAt != null && beforeCreatedAt.isNotEmpty) {
        q = q.lt('published_at', beforeCreatedAt);
      }
      final data = await q
          .order('published_at', ascending: false)
          .limit(limit);
      final rows = List<Map<String, dynamic>>.from(data);
      final items = rows.map(SharedDesign.fromRow).toList();
      final nextCursor =
          rows.isNotEmpty ? rows.last['published_at']?.toString() : null;
      debugPrint('[profile-grid] shared_designs uid=$uid returned=${rows.length} hasMore=${rows.length >= limit}');
      return (
        items: items,
        hasMore: rows.length >= limit,
        cursor: nextCursor,
      );
    } catch (e) {
      // Tablo henüz yok (koala_user_shared_designs migration apply edilmemiş)
      // → empty page döndür, AI fazına geçilebilsin.
      debugPrint('[SharedDesignService] publicByUidPaged failed: $e');
      return (items: <SharedDesign>[], hasMore: false, cursor: null);
    }
  }

  /// Kullanıcının kendi paylaşımları — paginated.
  static Future<({List<SharedDesign> items, bool hasMore, dynamic cursor})>
      mySharedPaged({
    int limit = 18,
    String? beforeCreatedAt,
  }) async {
    final uid = _uid;
    if (uid == null) {
      return (items: <SharedDesign>[], hasMore: false, cursor: null);
    }
    return publicByUidPaged(
      uid,
      limit: limit,
      beforeCreatedAt: beforeCreatedAt,
    );
  }

  /// Kullanıcının (kendi veya başkasının) published shared_designs sayısı.
  /// Header'da "N adet" göstermek için.
  static Future<int> totalCount({String? ownerUid}) async {
    final uid = ownerUid ?? _uid;
    if (uid == null) return 0;
    try {
      final res = await Supabase.instance.client
          .from(_table)
          .select('id')
          .eq('user_id', uid)
          .eq('status', 'published')
          .count(CountOption.exact);
      return res.count;
    } catch (e) {
      // Tablo henüz yok → 0 dön (defansif).
      debugPrint('[SharedDesignService] totalCount failed (table missing?): $e');
      return 0;
    }
  }

  /// Gizli/yayın toggle — owner-only. status='published' ↔ 'private'.
  /// Other users zaten sadece status='published' satırları görüyor.
  static Future<bool> setVisibility({
    required String id,
    required bool isPublic,
  }) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await Supabase.instance.client
          .from(_table)
          .update({
            'status': isPublic ? 'published' : 'private',
            if (isPublic) 'published_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id)
          .eq('user_id', uid);
      return true;
    } catch (e) {
      debugPrint('[SharedDesignService] setVisibility failed: $e');
      return false;
    }
  }

  static Future<bool> delete(String id) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await Supabase.instance.client
          .from(_table)
          .delete()
          .eq('id', id)
          .eq('user_id', uid);
      return true;
    } catch (e) {
      debugPrint('[SharedDesignService] delete failed: $e');
      return false;
    }
  }

  static Future<bool> update(
    String id, {
    String? title,
    String? description,
    String? roomType,
    List<String>? tags,
  }) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      final patch = <String, dynamic>{};
      if (title != null) patch['title'] = title;
      if (description != null) patch['description'] = description;
      if (roomType != null) patch['room_type'] = roomType;
      if (tags != null) patch['tags'] = tags;
      if (patch.isEmpty) return true;
      await Supabase.instance.client
          .from(_table)
          .update(patch)
          .eq('id', id)
          .eq('user_id', uid);
      return true;
    } catch (e) {
      debugPrint('[SharedDesignService] update failed: $e');
      return false;
    }
  }
}
