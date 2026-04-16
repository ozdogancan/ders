import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/env.dart';
import '../models/koala_card.dart';
import 'swipe_queue.dart';

/// Thin HTTP client for the swipe feed + ingest endpoints on koala-api.
///
/// Responsibility split:
///   - Network I/O + envelope parsing lives here.
///   - State (current deck, dwell timers, undo stack) lives in the Riverpod
///     provider that wraps this service.
///   - Offline retry is delegated to [SwipeQueue]; this service only exposes
///     the single-shot send primitive the queue calls back into.
class KoalaFeedService {
  KoalaFeedService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Null when the user is signed out. Firebase anon sign-in is handled
  /// elsewhere in the app — we don't fabricate an id here.
  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Uri _endpoint(String path, [Map<String, String>? query]) {
    final base = Env.koalaApiUrl;
    return Uri.parse('$base$path').replace(
      queryParameters: query?.isEmpty ?? true ? null : query,
    );
  }

  Map<String, String> _authHeaders(String uid, {bool jsonBody = false}) => {
        'x-user-id': uid,
        if (jsonBody) 'content-type': 'application/json',
      };

  /// Fetch the next batch from `/api/feed`. Returns an empty list when the
  /// backend has nothing to show (e.g. first-run with zero enriched cards,
  /// or every card swiped inside the 90-day no-repeat window).
  ///
  /// [limit] is clamped server-side to [1, 50]; we pass it through.
  Future<List<KoalaCard>> fetchFeed({int limit = 30}) async {
    final uid = _uid;
    if (uid == null) return const <KoalaCard>[];

    final uri = _endpoint('/api/feed', {'limit': limit.toString()});
    final res = await _client
        .get(uri, headers: _authHeaders(uid))
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw KoalaFeedException(
        'feed ${res.statusCode}',
        statusCode: res.statusCode,
      );
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = body['cards'];
    if (raw is! List) return const <KoalaCard>[];

    return raw
        .whereType<Map>()
        .map((m) => KoalaCard.fromJson(Map<String, dynamic>.from(m)))
        .toList(growable: false);
  }

  /// Record a swipe.
  ///
  /// Writes to the [SwipeQueue] immediately so a network failure mid-gesture
  /// doesn't lose the signal, then attempts a best-effort flush. The return
  /// value is `true` when the event was delivered within this call; `false`
  /// means it is safely persisted and will drain on the next flush.
  ///
  /// Callers generally don't await the result — the UX is fire-and-forget.
  Future<bool> recordSwipe({
    required String cardId,
    required SwipeDirection direction,
    String context = 'feed',
    double? swipeVelocity,
    int? dwellTimeMs,
    String? idempotencyKey,
  }) async {
    final entry = SwipeQueueEntry(
      idempotencyKey: idempotencyKey ?? SwipeQueue.newIdempotencyKey(),
      cardId: cardId,
      direction: direction.wire,
      context: context,
      queuedAt: DateTime.now().toUtc(),
      swipeVelocity: swipeVelocity,
      dwellTimeMs: dwellTimeMs,
    );

    await SwipeQueue.enqueue(entry);
    final sent = await SwipeQueue.flush(sendOne);
    return sent > 0;
  }

  /// Force a drain — call on app resume or connectivity recovery.
  Future<int> drainQueue() => SwipeQueue.flush(sendOne);

  /// Transport used by [SwipeQueue.flush]. Exposed as a method (not a
  /// closure over `this`) so it remains testable and so the queue never
  /// captures a dangling service instance.
  Future<bool> sendOne(SwipeQueueEntry entry) async {
    final uid = _uid;
    if (uid == null) return false;

    final body = <String, dynamic>{
      'card_id': entry.cardId,
      'direction': entry.direction,
      'context': entry.context,
      'idempotency_key': entry.idempotencyKey,
      if (entry.swipeVelocity != null) 'swipe_velocity': entry.swipeVelocity,
      if (entry.dwellTimeMs != null) 'dwell_time_ms': entry.dwellTimeMs,
    };

    http.Response res;
    try {
      res = await _client
          .post(
            _endpoint('/api/swipe'),
            headers: _authHeaders(uid, jsonBody: true),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      debugPrint('KoalaFeedService: swipe POST timed out, keeping queued');
      return false;
    } catch (e) {
      debugPrint('KoalaFeedService: swipe POST failed: $e');
      return false;
    }

    // 2xx → delivered. 4xx validation errors are terminal: drop the entry
    // so we don't retry forever (auth issues return 401 which we also drop;
    // a re-authed user will not replay stale keys — queue is user-scoped in
    // practice since it lives on that device's SharedPreferences).
    if (res.statusCode >= 200 && res.statusCode < 300) return true;
    if (res.statusCode >= 400 && res.statusCode < 500) {
      debugPrint(
        'KoalaFeedService: swipe rejected ${res.statusCode} '
        '(dropping from queue): ${res.body}',
      );
      return true;
    }

    // 5xx — keep for retry.
    debugPrint('KoalaFeedService: swipe server error ${res.statusCode}');
    return false;
  }

  void dispose() => _client.close();
}

class KoalaFeedException implements Exception {
  KoalaFeedException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'KoalaFeedException($message)';
}
