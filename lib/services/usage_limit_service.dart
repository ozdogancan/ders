// Client-side usage limit tracker — UI hint only. Tracks daily counters
// (swipe, koala AI) and per-conversation lifetime counters (Evlumba designer
// replies) for Koala's free-tier gating. Server is authoritative; this exists
// to drive paywall affordances locally without a round-trip.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UsageLimits {
  static const int dailySwipeLimit = 10;
  static const int dailyKoalaAiLimit = 3;
  // 2026-06-03 (#3): İlk ücretsiz danışma gerçek bir sohbet olabilsin diye
  // 1 → 3. Tek bir "selam" mesajı tüm ücretsiz danışmayı tüketmesin.
  static const int evlumbaFreeRepliesPerConversation = 3;
}

class UsageLimitService {
  static const String _kStoreKey = 'usage_limits_v1';
  static const String _kDate = 'date';
  static const String _kSwipe = 'swipe';
  static const String _kKoalaAi = 'koala_ai';
  static const String _kEvlumba = 'evlumba_replies';

  static String _today() {
    final n = DateTime.now();
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '${n.year}-$m-$d';
  }

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  static Future<Map<String, dynamic>> _load() async {
    try {
      final prefs = await _prefs();
      final raw = prefs.getString(_kStoreKey);
      if (raw == null || raw.isEmpty) return _fresh();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return _fresh();
      final map = Map<String, dynamic>.from(decoded);
      // Normalize evlumba_replies shape.
      final ev = map[_kEvlumba];
      if (ev is Map) {
        map[_kEvlumba] = Map<String, dynamic>.from(ev);
      } else {
        map[_kEvlumba] = <String, dynamic>{};
      }
      map[_kDate] ??= _today();
      map[_kSwipe] = (map[_kSwipe] is num) ? (map[_kSwipe] as num).toInt() : 0;
      map[_kKoalaAi] =
          (map[_kKoalaAi] is num) ? (map[_kKoalaAi] as num).toInt() : 0;
      return map;
    } catch (e) {
      debugPrint('UsageLimitService._load failed: $e');
      return _fresh();
    }
  }

  static Map<String, dynamic> _fresh() => {
        _kDate: _today(),
        _kSwipe: 0,
        _kKoalaAi: 0,
        _kEvlumba: <String, dynamic>{},
      };

  static Future<void> _save(Map<String, dynamic> data) async {
    try {
      final prefs = await _prefs();
      await prefs.setString(_kStoreKey, jsonEncode(data));
    } catch (e) {
      debugPrint('UsageLimitService._save failed: $e');
    }
  }

  static Map<String, dynamic> _rolloverIfNeeded(Map<String, dynamic> data) {
    final today = _today();
    if (data[_kDate] != today) {
      data[_kDate] = today;
      data[_kSwipe] = 0;
      data[_kKoalaAi] = 0;
      // evlumba_replies is intentionally preserved across day rollover.
    }
    return data;
  }

  /// Ensures the stored day stamp matches today, resetting daily counters.
  static Future<void> ensureToday() async {
    final data = await _load();
    final today = _today();
    if (data[_kDate] != today) {
      _rolloverIfNeeded(data);
      await _save(data);
    }
  }

  /// Returns the current day's swipe count.
  static Future<int> swipeUsed() async {
    final data = _rolloverIfNeeded(await _load());
    return (data[_kSwipe] as int?) ?? 0;
  }

  /// True when the user has remaining swipes for today.
  static Future<bool> canSwipe() async {
    return (await swipeUsed()) < UsageLimits.dailySwipeLimit;
  }

  /// Records one swipe against today's counter.
  static Future<void> incrementSwipe() async {
    final data = _rolloverIfNeeded(await _load());
    data[_kSwipe] = ((data[_kSwipe] as int?) ?? 0) + 1;
    await _save(data);
  }

  /// Returns the current day's Koala AI message count.
  static Future<int> koalaAiUsed() async {
    final data = _rolloverIfNeeded(await _load());
    return (data[_kKoalaAi] as int?) ?? 0;
  }

  /// True when the user can still send a Koala AI message today.
  static Future<bool> canSendKoalaAi() async {
    return (await koalaAiUsed()) < UsageLimits.dailyKoalaAiLimit;
  }

  /// Records one Koala AI message against today's counter.
  static Future<void> incrementKoalaAi() async {
    final data = _rolloverIfNeeded(await _load());
    data[_kKoalaAi] = ((data[_kKoalaAi] as int?) ?? 0) + 1;
    await _save(data);
  }

  /// Returns lifetime Evlumba reply count for a given conversation.
  static Future<int> evlumbaRepliesUsed(String conversationId) async {
    final data = _rolloverIfNeeded(await _load());
    final ev = Map<String, dynamic>.from(data[_kEvlumba] as Map);
    final v = ev[conversationId];
    return v is num ? v.toInt() : 0;
  }

  /// True when the user can still reply to this Evlumba conversation for free.
  static Future<bool> canSendEvlumbaReply(String conversationId) async {
    return (await evlumbaRepliesUsed(conversationId)) <
        UsageLimits.evlumbaFreeRepliesPerConversation;
  }

  /// Records one Evlumba reply for the given conversation (lifetime counter).
  static Future<void> incrementEvlumbaReply(String conversationId) async {
    final data = _rolloverIfNeeded(await _load());
    final ev = Map<String, dynamic>.from(data[_kEvlumba] as Map);
    final current = ev[conversationId];
    final n = current is num ? current.toInt() : 0;
    ev[conversationId] = n + 1;
    data[_kEvlumba] = ev;
    await _save(data);
  }

  /// Lifetime restyle count for a user, summed across all monthly periods in
  /// `billing_quota_usage` (server-authoritative table). Used by the wizard
  /// to decide whether to gift a FREE first restyle (loss-leader / wow moment)
  /// vs. show the paywall.
  ///
  /// Defensive: any failure (network, schema mismatch, auth) returns 0 — i.e.
  /// we assume the user has NEVER restyled, so they get the free one. The
  /// server still enforces the hard 2/month gate on the API side, so being
  /// overly generous here cannot grant unlimited generations.
  static Future<int> userRestyleCount(String uid) async {
    if (uid.isEmpty) return 0;
    try {
      final rows = await Supabase.instance.client
          .from('billing_quota_usage')
          .select('count')
          .eq('user_id', uid)
          .eq('feature', 'restyle');
      if (rows is! List) return 0;
      var total = 0;
      for (final row in rows) {
        if (row is Map) {
          final c = row['count'];
          if (c is num) total += c.toInt();
        }
      }
      return total;
    } catch (e) {
      debugPrint('UsageLimitService.userRestyleCount failed: $e');
      return 0; // fail-open → user gets the free first restyle
    }
  }

  /// Wipes all usage counters. Call after a successful Pro upgrade.
  static Future<void> resetAll() async {
    try {
      final prefs = await _prefs();
      await prefs.remove(_kStoreKey);
    } catch (e) {
      debugPrint('UsageLimitService.resetAll failed: $e');
    }
  }
}
