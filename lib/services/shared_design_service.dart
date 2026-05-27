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
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, FileOptions;
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
  const ShareModerationResult({required this.ok, this.reason, this.detail});
}

class SharedDesignService {
  SharedDesignService._();

  static const String _table = 'koala_user_shared_designs';

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
