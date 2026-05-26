// Takip / sessize alma servisi — koala_follows tablosuna karşılık.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

class FollowState {
  final bool following;
  final bool muted;
  const FollowState({required this.following, required this.muted});
  static const empty = FollowState(following: false, muted: false);
  factory FollowState.fromJson(Map<String, dynamic> j) => FollowState(
        following: j['following'] == true,
        muted: j['muted'] == true,
      );
}

class FollowService {
  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Tek tasarımcı için takip durumunu çek.
  static Future<FollowState> stateFor(String designerId) async {
    final uid = _uid;
    if (uid == null || designerId.isEmpty) return FollowState.empty;
    try {
      final row = await Supabase.instance.client
          .from('koala_follows')
          .select('muted')
          .eq('user_id', uid)
          .eq('designer_id', designerId)
          .maybeSingle();
      if (row == null) return FollowState.empty;
      return FollowState(following: true, muted: row['muted'] == true);
    } catch (e) {
      debugPrint('[follow] state failed: $e');
      return FollowState.empty;
    }
  }

  static Future<FollowState> toggle(String designerId) async {
    final uid = _uid;
    if (uid == null || designerId.isEmpty) return FollowState.empty;
    try {
      final res = await Supabase.instance.client.rpc(
        'koala_follow_toggle',
        params: {'p_user_id': uid, 'p_designer_id': designerId},
      );
      if (res is Map) return FollowState.fromJson(Map<String, dynamic>.from(res));
      return FollowState.empty;
    } catch (e) {
      debugPrint('[follow] toggle failed: $e');
      return FollowState.empty;
    }
  }

  static Future<FollowState> muteToggle(String designerId) async {
    final uid = _uid;
    if (uid == null || designerId.isEmpty) return FollowState.empty;
    try {
      final res = await Supabase.instance.client.rpc(
        'koala_mute_toggle',
        params: {'p_user_id': uid, 'p_designer_id': designerId},
      );
      if (res is Map) return FollowState.fromJson(Map<String, dynamic>.from(res));
      return FollowState.empty;
    } catch (e) {
      debugPrint('[follow] mute failed: $e');
      return FollowState.empty;
    }
  }

  /// Kullanıcının takip ettiği tüm tasarımcı id'leri.
  static Future<List<Map<String, dynamic>>> myFollows() async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final data = await Supabase.instance.client
          .from('koala_follows')
          .select('designer_id, muted, created_at')
          .eq('user_id', uid)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('[follow] myFollows failed: $e');
      return const [];
    }
  }
}

/// Tek tasarımcı için takip durumu provider'ı — sheet bunu watch'lar.
final followStateProvider =
    FutureProvider.family<FollowState, String>((ref, designerId) {
  return FollowService.stateFor(designerId);
});
