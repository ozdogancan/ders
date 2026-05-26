// Kullanıcı profili (ev sahibi / profesyonel) — koala_user_profiles + RPC'ler.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'dart:convert';

import '../core/config/env.dart';

class KoalaUserProfile {
  final String uid;
  final String? displayName;
  final String? about;
  final Map<String, dynamic> contact;
  final String mode; // 'homeowner' | 'pro'
  final bool verified;

  const KoalaUserProfile({
    required this.uid,
    this.displayName,
    this.about,
    this.contact = const {},
    this.mode = 'homeowner',
    this.verified = false,
  });

  bool get isPro => mode == 'pro';

  factory KoalaUserProfile.fromRow(Map<String, dynamic> r) => KoalaUserProfile(
        uid: r['uid'].toString(),
        displayName: r['display_name']?.toString(),
        about: r['about']?.toString(),
        contact: r['contact_info'] is Map
            ? Map<String, dynamic>.from(r['contact_info'])
            : const {},
        mode: (r['mode'] ?? 'homeowner').toString(),
        verified: r['verified'] == true,
      );

  static const empty = KoalaUserProfile(uid: '');
}

class ProApplicationStatus {
  final String? id;
  final String status; // 'none' | 'pending' | 'approved' | 'rejected'
  final String? reviewNotes;
  const ProApplicationStatus({
    this.id,
    this.status = 'none',
    this.reviewNotes,
  });
  static const none = ProApplicationStatus();
  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}

class UserProfileService {
  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static Future<KoalaUserProfile?> get() async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final row = await Supabase.instance.client
          .from('koala_user_profiles')
          .select()
          .eq('uid', uid)
          .maybeSingle();
      if (row == null) return KoalaUserProfile(uid: uid);
      return KoalaUserProfile.fromRow(Map<String, dynamic>.from(row));
    } catch (e) {
      debugPrint('[user_profile] get failed: $e');
      return null;
    }
  }

  static Future<bool> upsert({
    String? displayName,
    String? about,
    Map<String, dynamic>? contact,
  }) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await Supabase.instance.client.rpc(
        'koala_user_profile_upsert',
        params: {
          'p_uid': uid,
          'p_display_name': displayName,
          'p_about': about,
          'p_contact': contact ?? const {},
        },
      );
      return true;
    } catch (e) {
      debugPrint('[user_profile] upsert failed: $e');
      return false;
    }
  }

  static Future<ProApplicationStatus> latestApplication() async {
    final uid = _uid;
    if (uid == null) return ProApplicationStatus.none;
    try {
      final row = await Supabase.instance.client
          .from('koala_pro_applications')
          .select('id, status, review_notes, created_at')
          .eq('uid', uid)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row == null) return ProApplicationStatus.none;
      return ProApplicationStatus(
        id: row['id']?.toString(),
        status: (row['status'] ?? 'none').toString(),
        reviewNotes: row['review_notes']?.toString(),
      );
    } catch (e) {
      debugPrint('[user_profile] latestApplication failed: $e');
      return ProApplicationStatus.none;
    }
  }

  /// Profesyonel başvurusu — koala-api'ye gönder, Telegram'a düşsün.
  static Future<bool> applyForPro({
    required String fullName,
    required String profession,
    String? city,
    String? igUrl,
    String? portfolioUrl,
    String? reason,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final idToken = await user.getIdToken();
      final res = await http.post(
        Uri.parse('${Env.koalaApiUrl}/api/pro/apply'),
        headers: {
          'Content-Type': 'application/json',
          if (idToken != null) 'Authorization': 'Bearer $idToken',
          'X-User-Id': user.uid,
        },
        body: jsonEncode({
          'full_name': fullName,
          'profession': profession,
          'city': city,
          'ig_url': igUrl,
          'portfolio_url': portfolioUrl,
          'reason': reason,
        }),
      );
      if (res.statusCode != 200) {
        debugPrint('[user_profile] apply ${res.statusCode}: ${res.body}');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[user_profile] apply error: $e');
      return false;
    }
  }
}

/// Riverpod provider — profil + son başvuru durumu birlikte.
class UserProfileBundle {
  final KoalaUserProfile profile;
  final ProApplicationStatus application;
  const UserProfileBundle(this.profile, this.application);
}

final userProfileProvider =
    FutureProvider<UserProfileBundle>((ref) async {
  final profileF = UserProfileService.get();
  final appF = UserProfileService.latestApplication();
  final results = await Future.wait([profileF, appF]);
  final profile = results[0] as KoalaUserProfile?;
  final app = results[1] as ProApplicationStatus;
  return UserProfileBundle(
    profile ?? const KoalaUserProfile(uid: ''),
    app,
  );
});
