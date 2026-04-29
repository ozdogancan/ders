import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'restyle_prefetch_service.dart';

/// Background generation tracker — kullanıcı "Süreci Küçült" basıp Projeler'e
/// geçtiğinde, üretim bilgisini global bir notifier'da tut. Projeler sayfası
/// bunu dinler, pending bir kart gösterir.
///
/// **Bağımsız watchdog**: handoff'ta verilen image+theme cache key'i ile
/// `RestylePrefetchService` cache'ini periyodik kontrol eder. Cache'te sonuç
/// göründüğü an `complete()` kendi tetikler — mekan_flow_screen disposed olsa
/// bile takılmaz.
class BackgroundGen {
  BackgroundGen._();

  static final ValueNotifier<BackgroundGenState?> notifier =
      ValueNotifier<BackgroundGenState?>(null);

  /// Tamamlanma bilgilendirmesi — Projeler ekranı toast / push tetiklemek için
  /// bunu dinleyebilir. Tamamlanan tasarımın afterSrc'sini içerir.
  static final ValueNotifier<BackgroundGenCompletion?> completion =
      ValueNotifier<BackgroundGenCompletion?>(null);

  static Timer? _ticker;
  static Timer? _watchdog;
  static Uint8List? _watchBytes;
  static String? _watchTheme;
  static const _maxDuration = Duration(seconds: 180);

  static void handoff({
    required Uint8List sourceBytes,
    required String room,
    required String theme,
    Uint8List? imageBytes,
    String? themeKey,
  }) {
    _ticker?.cancel();
    _watchdog?.cancel();
    _watchBytes = imageBytes ?? sourceBytes;
    _watchTheme = themeKey ?? theme;
    final state = BackgroundGenState(
      sourceBytes: sourceBytes,
      room: room,
      theme: theme,
      startedAt: DateTime.now(),
      progress: 0.0,
      completed: false,
    );
    notifier.value = state;
    _startTicker();
    _startWatchdog();
  }

  static void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 280), (_) {
      final s = notifier.value;
      if (s == null || s.completed || s.error != null) {
        _ticker?.cancel();
        return;
      }
      final secs =
          DateTime.now().difference(s.startedAt).inMilliseconds / 1000.0;
      // 5s→%38, 15s→%75, 30s→%88
      final p = (1 - 1 / (1 + secs / 3.5)).clamp(0.0, 0.94);
      if ((p - s.progress).abs() > 0.005) {
        notifier.value = s.copyWith(progress: p);
      }
    });
  }

  /// Periyodik prefetch cache check — `_done` veya `_inFlight` resolve olunca
  /// otomatik complete tetikle. Mekan flow screen disposed olsa bile takılmaz.
  static void _startWatchdog() {
    _watchdog?.cancel();
    final bytes = _watchBytes;
    final theme = _watchTheme;
    if (bytes == null || theme == null) return;
    _watchdog = Timer.periodic(const Duration(milliseconds: 500), (t) {
      final s = notifier.value;
      if (s == null || s.completed || s.error != null) {
        t.cancel();
        return;
      }
      // Timeout — 180s sonra hata olarak işaretle.
      if (DateTime.now().difference(s.startedAt) > _maxDuration) {
        t.cancel();
        fail('zaman aşımı');
        Future.delayed(const Duration(milliseconds: 1500), clear);
        return;
      }
      // Prefetch cache'te sonuç var mı?
      final cached = RestylePrefetchService.take(
        imageBytes: bytes,
        theme: theme,
      );
      if (cached != null && cached.output.isNotEmpty) {
        t.cancel();
        complete(afterUrl: cached.output);
      }
    });
  }

  static void complete({String? afterUrl}) {
    final s = notifier.value;
    if (s == null) return;
    _ticker?.cancel();
    _watchdog?.cancel();
    notifier.value = s.copyWith(
      progress: 1.0,
      completed: true,
      afterUrl: afterUrl,
    );
    // Toast/push için tek-seferlik bildirim emit et.
    completion.value = BackgroundGenCompletion(
      afterUrl: afterUrl,
      room: s.room,
      theme: s.theme,
      ts: DateTime.now(),
    );
    Future.delayed(const Duration(milliseconds: 1500), () {
      final cur = notifier.value;
      if (cur != null && cur.completed) {
        notifier.value = null;
      }
    });
  }

  static void fail(String reason) {
    final s = notifier.value;
    if (s == null) return;
    _ticker?.cancel();
    _watchdog?.cancel();
    notifier.value = s.copyWith(error: reason);
  }

  static void clear() {
    _ticker?.cancel();
    _watchdog?.cancel();
    _watchBytes = null;
    _watchTheme = null;
    notifier.value = null;
  }

  /// Toast emit edildikten sonra completion'ı temizle (tek seferlik).
  static void consumeCompletion() {
    completion.value = null;
  }
}

@immutable
class BackgroundGenCompletion {
  final String? afterUrl;
  final String room;
  final String theme;
  final DateTime ts;
  const BackgroundGenCompletion({
    required this.afterUrl,
    required this.room,
    required this.theme,
    required this.ts,
  });
}

@immutable
class BackgroundGenState {
  final Uint8List sourceBytes;
  final String room;
  final String theme;
  final DateTime startedAt;
  final double progress;
  final bool completed;
  final String? afterUrl;
  final String? error;

  const BackgroundGenState({
    required this.sourceBytes,
    required this.room,
    required this.theme,
    required this.startedAt,
    required this.progress,
    required this.completed,
    this.afterUrl,
    this.error,
  });

  BackgroundGenState copyWith({
    double? progress,
    bool? completed,
    String? afterUrl,
    String? error,
  }) {
    return BackgroundGenState(
      sourceBytes: sourceBytes,
      room: room,
      theme: theme,
      startedAt: startedAt,
      progress: progress ?? this.progress,
      completed: completed ?? this.completed,
      afterUrl: afterUrl ?? this.afterUrl,
      error: error ?? this.error,
    );
  }
}
