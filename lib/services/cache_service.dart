/// Basit in-memory cache servisi.
/// Sık çağrılan Supabase sorgularını cache'ler.
class CacheService {
  CacheService._();

  static final Map<String, _CacheEntry> _cache = {};

  /// Cache'ten oku. Expire olduysa veya yoksa null döner.
  static T? get<T>(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (DateTime.now().isAfter(entry.expiry)) {
      _cache.remove(key);
      return null;
    }
    return entry.data as T;
  }

  /// Cache'e yaz.
  static void set(String key, dynamic data, {Duration duration = const Duration(minutes: 5)}) {
    _cache[key] = _CacheEntry(data: data, expiry: DateTime.now().add(duration));
  }

  /// Tek key invalidate.
  static void invalidate(String key) => _cache.remove(key);

  /// Prefix ile eşleşen tüm key'leri invalidate.
  static void invalidatePrefix(String prefix) {
    _cache.removeWhere((k, _) => k.startsWith(prefix));
  }

  /// Tüm cache'i temizle.
  static void clearAll() => _cache.clear();
}

class _CacheEntry {
  final dynamic data;
  final DateTime expiry;
  _CacheEntry({required this.data, required this.expiry});
}
