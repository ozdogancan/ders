import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'mekan_analyze_service.dart' show StyleHints;
import 'mekan_restyle_service.dart';
import 'replicate_service.dart';

/// Restyle prefetch servisi — kullanıcı swipe yaparken veya moodboard
/// revealı izlerken arka planda restyle başlatır. Sonuç hazırsa, kullanıcı
/// "Tasarımı başlat" butonuna bastığında anında gösterilir → algılanan
/// hız ∞.
///
/// In-memory cache (process yaşam süresi boyunca). Key = image_hash + theme.
/// TTL yok — aynı process'te dedupe yeterli, app restart'ta sıfırlanır.
///
/// **v2 — Restyle Batch** (compile-time flag `RESTYLE_V2=true`):
/// Tek-shot yerine 3-variant batch çağırır, en yüksek judge_score'lu variant'ı
/// `RestyleResult`a sarar. Tüm variant listesi ayrıca [takeBatch]/[pendingBatch]
/// üzerinden alınabilir — multi-variant UI için.
class RestylePrefetchService {
  RestylePrefetchService._();

  /// Compile-time flag. `--dart-define=RESTYLE_V2=true` ile aç.
  /// Default false → backward compatible tek-shot yol.
  static const bool _v2Enabled =
      bool.fromEnvironment('RESTYLE_V2', defaultValue: false);

  // Tek-shot cache — legacy.
  static final Map<String, Future<RestyleResult>> _inFlight = {};
  static final Map<String, RestyleResult> _done = {};

  // Batch cache — v2.
  static final Map<String, Future<RestyleBatchResult>> _inFlightBatch = {};
  static final Map<String, RestyleBatchResult> _doneBatch = {};

  /// Prefetch başlat. Fire-and-forget — await etmeye gerek yok.
  /// Aynı key ile ikinci kez çağrılırsa mevcut future döner (dedupe).
  ///
  /// v2 ON ise batch çağırır, en iyi variant'ı `RestyleResult` olarak döner
  /// (geriye uyumlu). Batch'in tamamı [takeBatch] ile alınır.
  static Future<RestyleResult> prefetch({
    required Uint8List imageBytes,
    required String room,
    required String theme,
    StyleHints? styleHints,
    String? referenceUrl,
  }) {
    final key = _cacheKey(imageBytes, theme);

    if (_v2Enabled) {
      return _prefetchBatch(
        key: key,
        imageBytes: imageBytes,
        room: room,
        theme: theme,
        styleHints: styleHints,
        referenceUrl: referenceUrl,
      ).then((b) => _batchToLegacy(b));
    }

    if (_done.containsKey(key)) {
      return Future.value(_done[key]);
    }
    if (_inFlight.containsKey(key)) {
      return _inFlight[key]!;
    }
    final future = ReplicateService.restyle(
      imageBytes: imageBytes,
      room: room,
      theme: theme,
      styleHints: styleHints,
    ).then((r) {
      _done[key] = r;
      _inFlight.remove(key);
      return r;
    }).catchError((e) {
      _inFlight.remove(key);
      throw e;
    });
    _inFlight[key] = future;
    return future;
  }

  static Future<RestyleBatchResult> _prefetchBatch({
    required String key,
    required Uint8List imageBytes,
    required String room,
    required String theme,
    StyleHints? styleHints,
    String? referenceUrl,
  }) {
    if (_doneBatch.containsKey(key)) {
      return Future.value(_doneBatch[key]);
    }
    if (_inFlightBatch.containsKey(key)) {
      return _inFlightBatch[key]!;
    }
    final future = MekanRestyleService.restyleBatch(
      imageBytes: imageBytes,
      room: room,
      theme: theme,
      styleHints: styleHints,
      referenceUrl: referenceUrl,
    ).then((b) {
      _doneBatch[key] = b;
      _inFlightBatch.remove(key);
      return b;
    }).catchError((e) {
      _inFlightBatch.remove(key);
      throw e;
    });
    _inFlightBatch[key] = future;
    return future;
  }

  /// Hazır mı? UI, "Tasarımı başlat" butonunun label'ını değiştirmek için
  /// bakabilir (ör. ✨ ikonu "hazır" hali).
  static bool isReady({required Uint8List imageBytes, required String theme}) {
    final key = _cacheKey(imageBytes, theme);
    return _v2Enabled ? _doneBatch.containsKey(key) : _done.containsKey(key);
  }

  /// Cache'ten al — tek-shot uyumlu (en iyi variant). isReady true ise null
  /// dönmez. v2'de tüm variant'lar için [takeBatch] kullan.
  static RestyleResult? take({
    required Uint8List imageBytes,
    required String theme,
  }) {
    final key = _cacheKey(imageBytes, theme);
    if (_v2Enabled) {
      final b = _doneBatch[key];
      return b == null ? null : _batchToLegacy(b);
    }
    return _done[key];
  }

  /// v2 batch sonucunu olduğu gibi al — multi-variant UI için.
  /// v2 OFF ise her zaman null.
  static RestyleBatchResult? takeBatch({
    required Uint8List imageBytes,
    required String theme,
  }) {
    if (!_v2Enabled) return null;
    return _doneBatch[_cacheKey(imageBytes, theme)];
  }

  /// Pending future — tek-shot uyumlu (en iyi variant).
  static Future<RestyleResult>? pending({
    required Uint8List imageBytes,
    required String theme,
  }) {
    final key = _cacheKey(imageBytes, theme);
    if (_v2Enabled) {
      final f = _inFlightBatch[key];
      return f?.then(_batchToLegacy);
    }
    return _inFlight[key];
  }

  /// v2 pending batch — full result.
  static Future<RestyleBatchResult>? pendingBatch({
    required Uint8List imageBytes,
    required String theme,
  }) {
    if (!_v2Enabled) return null;
    return _inFlightBatch[_cacheKey(imageBytes, theme)];
  }

  /// Tüm cache temizle — test / logout için.
  static void clear() {
    _inFlight.clear();
    _done.clear();
    _inFlightBatch.clear();
    _doneBatch.clear();
  }

  /// V2 etkin mi? UI özellik kontrolü için.
  static bool get v2Enabled => _v2Enabled;

  /// Image hash + theme → stabil key. İlk 4KB'yi hash'le (tüm bytes pahalı).
  static String _cacheKey(Uint8List bytes, String theme) {
    final sample = bytes.length > 4096 ? bytes.sublist(0, 4096) : bytes;
    final digest = sha1.convert(sample);
    return '${digest.toString().substring(0, 16)}_${theme.toLowerCase()}';
  }

  /// Batch → legacy single. En yüksek judge_score'lu variant alınır.
  /// v2 OFF code path'leri kırılmasın diye.
  static RestyleResult _batchToLegacy(RestyleBatchResult b) {
    return RestyleResult(output: b.best.output, mock: b.mock);
  }
}
