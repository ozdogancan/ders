import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/env.dart';

/// Lightweight singleton that tracks internet connectivity via HTTP head request.
/// Works on both mobile and web (no dart:io dependency).
class ConnectivityService {
  ConnectivityService._();

  static bool isOnline = true;
  static final ValueNotifier<bool> status = ValueNotifier(true);
  static Timer? _timer;
  static int _consecutiveFails = 0;

  /// Run once at app start.
  static Future<void> init() async {
    await check();
    _startPolling();
  }

  /// Returns true if device can reach the internet.
  /// Uses Supabase REST endpoint which has proper CORS headers for web.
  static Future<bool> check() async {
    bool reachable = false;

    // Primary: check Koala API health endpoint (CORS-safe, tests both API + services)
    if (Env.koalaApiUrl.isNotEmpty) {
      try {
        final resp = await http.get(
          Uri.parse('${Env.koalaApiUrl}/api/health'),
        ).timeout(const Duration(seconds: 5));
        if (resp.statusCode < 500) {
          reachable = true;
        }
      } catch (_) {}
    }

    // Fallback: check Supabase endpoint
    if (!reachable && Env.supabaseUrl.isNotEmpty) {
      try {
        final resp = await http.get(
          Uri.parse('${Env.supabaseUrl}/rest/v1/'),
          headers: {
            'apikey': Env.supabaseAnonKey,
          },
        ).timeout(const Duration(seconds: 5));
        if (resp.statusCode < 500) {
          reachable = true;
        }
      } catch (_) {}
    }

    if (reachable) {
      _consecutiveFails = 0;
      _setOnline(true);
    } else {
      _consecutiveFails++;
      if (_consecutiveFails >= 2) {
        _setOnline(false);
      }
    }
    return isOnline;
  }

  /// Periodic stream: 15 s when offline, 60 s when online.
  static Stream<bool> get onStatusChange => status.toStream();

  // ── internals ──

  static void _setOnline(bool value) {
    if (isOnline != value) {
      isOnline = value;
      status.value = value;
      _startPolling(); // adjust interval
    }
  }

  static void _startPolling() {
    _timer?.cancel();
    final interval = isOnline
        ? const Duration(seconds: 60)
        : const Duration(seconds: 15);
    _timer = Timer.periodic(interval, (_) => check());
  }

  /// Timer ve listener temizliği (app lifecycle dispose)
  static void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Helper to expose ValueNotifier as a stream.
extension _ValueNotifierStream<T> on ValueNotifier<T> {
  Stream<T> toStream() {
    final ctrl = StreamController<T>();
    void listener() => ctrl.add(value);
    addListener(listener);
    ctrl.onCancel = () => removeListener(listener);
    return ctrl.stream;
  }
}
