// Client-side quota cache — UI hint only. Server is authoritative; on a 402
// response from any gated route the paywall opens regardless of what we cached
// here. Used by Profile + Paywall to display "1/2 restyle kullandın" etc.

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/env.dart';
import 'auth_token_service.dart';

class QuotaSnapshot {
  final bool isPro;
  final int restyleUsed;
  final int restyleLimit;
  final int saveUsed;
  final int saveLimit;
  final int chatUsed;
  final int chatLimit;

  const QuotaSnapshot({
    required this.isPro,
    required this.restyleUsed,
    required this.restyleLimit,
    required this.saveUsed,
    required this.saveLimit,
    required this.chatUsed,
    required this.chatLimit,
  });

  static const empty = QuotaSnapshot(
    isPro: false,
    restyleUsed: 0,
    restyleLimit: 2,
    saveUsed: 0,
    saveLimit: 3,
    chatUsed: 0,
    chatLimit: 5,
  );

  factory QuotaSnapshot.fromJson(Map<String, dynamic> j) {
    int n(dynamic v, int d) =>
        v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? d : d);
    final r = (j['restyle'] as Map?) ?? const {};
    final s = (j['save'] as Map?) ?? const {};
    final c = (j['chat'] as Map?) ?? const {};
    return QuotaSnapshot(
      isPro: j['isPro'] == true,
      restyleUsed: n(r['used'], 0),
      restyleLimit: n(r['limit'], 2),
      saveUsed: n(s['used'], 0),
      saveLimit: n(s['limit'], 3),
      chatUsed: n(c['used'], 0),
      chatLimit: n(c['limit'], 5),
    );
  }
}

class QuotaService {
  QuotaService._();

  static QuotaSnapshot? _cached;
  static DateTime? _fetchedAt;
  static const _ttl = Duration(seconds: 30);

  static Future<QuotaSnapshot> fetch({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _cached != null &&
        _fetchedAt != null &&
        now.difference(_fetchedAt!) < _ttl) {
      return _cached!;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return QuotaSnapshot.empty;
    try {
      final headers = {
        ...await AuthTokenService.authHeaders(),
        'X-User-Id': user.uid,
      };
      final res = await http
          .get(Uri.parse('${Env.koalaApiUrl}/api/quota/usage'),
              headers: headers)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        debugPrint('[quota] ${res.statusCode}: ${res.body}');
        return _cached ?? QuotaSnapshot.empty;
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final snap = QuotaSnapshot.fromJson(j);
      _cached = snap;
      _fetchedAt = now;
      return snap;
    } catch (e) {
      debugPrint('[quota] fetch error: $e');
      return _cached ?? QuotaSnapshot.empty;
    }
  }

  static Future<int> usedThisMonth(String feature) async {
    final s = await fetch();
    switch (feature) {
      case 'restyle':
        return s.restyleUsed;
      case 'save':
        return s.saveUsed;
      case 'chat':
        return s.chatUsed;
      default:
        return 0;
    }
  }

  /// Invalidate the cache after an action that could change usage (e.g.
  /// successful save, restyle, paywall purchase).
  static void invalidate() {
    _cached = null;
    _fetchedAt = null;
  }

  // ─── 402 handling — global callback wired from main.dart ───
  // Services (saved_items, mekan_restyle, chat) call this when API returns
  // 402 quota_exceeded. main.dart sets the implementation that pushes the
  // paywall via the active navigatorKey.
  static void Function(String trigger)? onQuotaExceeded;
}
