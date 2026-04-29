import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/html.dart' as html;

/// Dev mode mock toggle — Gemini'ye gitmeden restyle ekranını test etmek için.
/// Açma yolları:
///   • URL query: `?mock=1` (web)  → açar
///   • URL query: `?mock=0` (web)  → kapatır
///   • Build-time:  --dart-define=MOCK_MEKAN=true → daima açık
/// State sharedprefs'te kalıcı tutulur — bir kez ?mock=1 ile açtıysan
/// sonraki ziyaretlerde de mock mode aktif kalır.
class MockMode {
  MockMode._();

  static const String _kPrefsKey = 'koala_mock_restyle';
  static const bool _compileTimeFlag =
      bool.fromEnvironment('MOCK_MEKAN', defaultValue: false);

  static bool _runtimeFlag = false;
  static bool _initialized = false;

  /// Uygulama başlangıcında çağrılmalı (main.dart). URL query'i okur, prefs'i
  /// senkronize eder ve _runtimeFlag'i ayarlar.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    bool flag = prefs.getBool(_kPrefsKey) ?? false;

    // Web tarafında URL query override
    if (kIsWeb) {
      try {
        final params = Uri.parse(html.window.location.href).queryParameters;
        if (params['mock'] == '1') {
          flag = true;
          await prefs.setBool(_kPrefsKey, true);
        } else if (params['mock'] == '0') {
          flag = false;
          await prefs.setBool(_kPrefsKey, false);
        }
      } catch (_) {}
    }
    _runtimeFlag = flag;
    debugPrint('[MockMode] enabled=$enabled (compile=$_compileTimeFlag runtime=$_runtimeFlag)');
  }

  /// Mock mode aktif mi? Compile-time veya runtime flag birinden biri açıksa.
  static bool get enabled => _compileTimeFlag || _runtimeFlag;

  /// Runtime'da aç/kapat (debug menüsünden ya da gizli gesture'dan).
  static Future<void> set(bool v) async {
    _runtimeFlag = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefsKey, v);
  }

  /// Mock için kullanılacak after image URL'i — `style-previews-sm` bucket'ında
  /// 720px JPG q72 olarak optimize edilmiş ~30KB görseller. Performans testi
  /// için ideal — orijinal 1.4MB PNG yerine.
  static String mockAfterUrl({required String room, required String theme}) {
    const base =
        'https://xgefjepaqnghaotqybpi.supabase.co/storage/v1/object/public/style-previews-sm';
    final styleSlug = _styleSlug(theme);
    final roomSlug = _roomSlug(room);
    return '$base/$styleSlug-$roomSlug.jpg';
  }

  static String _styleSlug(String theme) {
    final t = theme.toLowerCase();
    if (t.contains('skand')) return 'scandinavian';
    if (t.contains('japa')) return 'japandi';
    if (t.contains('mode')) return 'modern';
    if (t.contains('boh')) return 'bohemian';
    if (t.contains('end') || t.contains('ind')) return 'industrial';
    return 'minimalist';
  }

  static String _roomSlug(String room) {
    final r = room.toLowerCase();
    if (r.contains('yatak') || r.contains('bedroom')) return 'bedroom';
    if (r.contains('mutf') || r.contains('kitchen')) return 'kitchen';
    if (r.contains('banyo') || r.contains('bath')) return 'bathroom';
    if (r.contains('yemek') || r.contains('dining')) return 'dining_room';
    if (r.contains('çal') || r.contains('cal') || r.contains('office')) {
      return 'office';
    }
    return 'living_room';
  }
}
