import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Lightweight singleton that tracks internet connectivity via HTTP head request.
/// Works on both mobile and web (no dart:io dependency).
class ConnectivityService {
  ConnectivityService._();

  static bool isOnline = true;
  static final ValueNotifier<bool> status = ValueNotifier(true);
  static Timer? _timer;

  /// Run once at app start.
  static Future<void> init() async {
    await check();
    _startPolling();
  }

  /// Returns true if device can reach the internet.
  static Future<bool> check() async {
    try {
      final resp = await http.head(Uri.parse('https://www.google.com'))
          .timeout(const Duration(seconds: 5));
      _setOnline(resp.statusCode < 500);
    } catch (_) {
      _setOnline(false);
    }
    return isOnline;
  }

  /// Periodic stream: 10 s when offline, 30 s when online.
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
        ? const Duration(seconds: 30)
        : const Duration(seconds: 10);
    _timer = Timer.periodic(interval, (_) => check());
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
