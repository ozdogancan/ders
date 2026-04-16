import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Offline-safe queue for outgoing swipe events.
///
/// Why this exists: the swipe action is the user's most expensive implicit
/// signal — losing one to a flaky network silently corrupts the taste
/// profile. Network failures enqueue the event to disk; a background flush
/// drains them with at-least-once delivery. The server-side
/// `ingest_swipe_v2` RPC is idempotent via `p_idempotency_key`, so replays
/// can never double-count.
///
/// Contract:
///   - `enqueue()` writes synchronously to disk before returning. A crash
///     between UI and network will not lose the event.
///   - `flush()` drains in insertion order; successes drop from disk, the
///     first failure stops the batch (preserving order for the retry loop).
///   - Every event carries a v4 UUID idempotency key so the backend dedupes
///     network retries, app relaunches, and multi-device edge cases.
class SwipeQueueEntry {
  SwipeQueueEntry({
    required this.idempotencyKey,
    required this.cardId,
    required this.direction,
    required this.context,
    required this.queuedAt,
    this.swipeVelocity,
    this.dwellTimeMs,
  });

  final String idempotencyKey;
  final String cardId;
  final String direction;
  final String context;
  final DateTime queuedAt;
  final double? swipeVelocity;
  final int? dwellTimeMs;

  Map<String, dynamic> toJson() => {
        'k': idempotencyKey,
        'c': cardId,
        'd': direction,
        'ctx': context,
        't': queuedAt.toIso8601String(),
        if (swipeVelocity != null) 'v': swipeVelocity,
        if (dwellTimeMs != null) 'w': dwellTimeMs,
      };

  factory SwipeQueueEntry.fromJson(Map<String, dynamic> json) => SwipeQueueEntry(
        idempotencyKey: json['k'] as String,
        cardId: json['c'] as String,
        direction: json['d'] as String,
        context: (json['ctx'] as String?) ?? 'feed',
        queuedAt:
            DateTime.tryParse(json['t'] as String? ?? '') ?? DateTime.now(),
        swipeVelocity: (json['v'] as num?)?.toDouble(),
        dwellTimeMs: (json['w'] as num?)?.toInt(),
      );
}

/// Pluggable transport so tests can simulate failure without hitting the
/// real backend. The concrete implementation lives in [KoalaFeedService].
typedef SwipeSender = Future<bool> Function(SwipeQueueEntry entry);

class SwipeQueue {
  SwipeQueue._();

  static const _storageKey = 'koala.swipe_queue.v1';
  static final _uuid = const Uuid();

  // In-flight guard: prevents interleaved flush() calls from posting the
  // same entry twice. The server dedupes, but we also save bandwidth.
  static bool _flushing = false;

  /// Generate a fresh idempotency key for a brand-new swipe.
  ///
  /// Callers that already have an id (e.g. for offline replay) reuse it
  /// instead of calling this.
  static String newIdempotencyKey() => _uuid.v4();

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  static Future<List<SwipeQueueEntry>> _read() async {
    final prefs = await _prefs;
    final raw = prefs.getStringList(_storageKey);
    if (raw == null || raw.isEmpty) return <SwipeQueueEntry>[];
    final out = <SwipeQueueEntry>[];
    for (final s in raw) {
      try {
        out.add(SwipeQueueEntry.fromJson(
          jsonDecode(s) as Map<String, dynamic>,
        ));
      } catch (e) {
        // Corrupt row — drop it rather than block the whole queue.
        debugPrint('SwipeQueue: dropping corrupt entry: $e');
      }
    }
    return out;
  }

  static Future<void> _write(List<SwipeQueueEntry> entries) async {
    final prefs = await _prefs;
    if (entries.isEmpty) {
      await prefs.remove(_storageKey);
      return;
    }
    await prefs.setStringList(
      _storageKey,
      entries.map((e) => jsonEncode(e.toJson())).toList(growable: false),
    );
  }

  /// Append an entry and persist atomically. Returns after the write is
  /// durable on disk.
  static Future<void> enqueue(SwipeQueueEntry entry) async {
    final current = await _read();
    current.add(entry);
    await _write(current);
  }

  /// Snapshot (read-only) of currently pending entries. Useful for telemetry
  /// and the offline banner.
  static Future<int> pendingCount() async {
    final entries = await _read();
    return entries.length;
  }

  /// Drain the queue by calling [send] in insertion order. Stops at the
  /// first failure to preserve ordering; the remainder sits on disk for the
  /// next flush.
  ///
  /// Returns the number of entries successfully delivered this call.
  static Future<int> flush(SwipeSender send) async {
    if (_flushing) return 0;
    _flushing = true;
    try {
      final entries = await _read();
      if (entries.isEmpty) return 0;

      var sent = 0;
      while (entries.isNotEmpty) {
        final head = entries.first;
        bool ok;
        try {
          ok = await send(head);
        } catch (e) {
          debugPrint('SwipeQueue: send threw for ${head.idempotencyKey}: $e');
          ok = false;
        }
        if (!ok) break;
        entries.removeAt(0);
        sent++;
      }

      await _write(entries);
      return sent;
    } finally {
      _flushing = false;
    }
  }

  /// Test-only. Wipes all pending entries.
  @visibleForTesting
  static Future<void> clearForTest() async {
    final prefs = await _prefs;
    await prefs.remove(_storageKey);
  }
}
