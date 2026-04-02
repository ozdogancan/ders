import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Chat içi beğeni/kaydetme aksiyonlarından profil sinyali toplar.
/// Style discovery profilini zenginleştirir, üzerine yazar değil.
class ProfileFeedbackService {
  ProfileFeedbackService._();

  static const _key = 'koala_style_profile';

  /// Kullanıcı bir ürünü/tasarımı kaydedince çağır.
  /// [style], [room], [colors] opsiyonel — varsa profili güçlendirir.
  static Future<void> recordSaveSignal({
    String? style,
    String? room,
    List<String>? colors,
    String? budget,
    String? itemTitle,
  }) async {
    final signal = <String, dynamic>{
      if (style != null) 'style': style,
      if (room != null) 'room': room,
      if (colors != null && colors.isNotEmpty) 'colors': colors,
      if (budget != null) 'budget': budget,
      if (itemTitle != null) 'item': itemTitle,
      'ts': DateTime.now().toIso8601String(),
    };
    if (signal.length <= 1) return; // sadece ts varsa sinyal yok

    await _appendSignal(signal);
  }

  /// Kullanıcı chat'te bir stil chip'ine tıkladığında çağır.
  static Future<void> recordStyleInterest(String styleName) async {
    await _appendSignal({
      'style': styleName,
      'source': 'chip',
      'ts': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> _appendSignal(Map<String, dynamic> signal) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      final profile = raw != null && raw.isNotEmpty
          ? jsonDecode(raw) as Map<String, dynamic>
          : <String, dynamic>{};

      final signals = (profile['chat_signals'] as List?)?.cast<Map<String, dynamic>>() ??
          <Map<String, dynamic>>[];
      signals.add(signal);
      // Son 30 sinyali tut (bellek dostu)
      if (signals.length > 30) {
        signals.removeRange(0, signals.length - 30);
      }
      profile['chat_signals'] = signals;

      // Sinyallerden aggregate güncelle
      _updateAggregates(profile, signals);

      await prefs.setString(_key, jsonEncode(profile));
    } catch (e) {
      debugPrint('ProfileFeedbackService error: $e');
    }
  }

  /// Sinyallerden stil/renk ağırlıklarını hesapla ve profile yaz.
  static void _updateAggregates(
    Map<String, dynamic> profile,
    List<Map<String, dynamic>> signals,
  ) {
    final styleCounts = <String, int>{};
    final colorCounts = <String, int>{};

    for (final s in signals) {
      final style = s['style'] as String?;
      if (style != null) {
        styleCounts.update(style, (v) => v + 1, ifAbsent: () => 1);
      }
      final colors = s['colors'] as List?;
      if (colors != null) {
        for (final c in colors) {
          colorCounts.update(c.toString(), (v) => v + 1, ifAbsent: () => 1);
        }
      }
    }

    // En çok etkileşim alan stili reinforced_style olarak kaydet
    if (styleCounts.isNotEmpty) {
      final sorted = styleCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      profile['reinforced_style'] = sorted.first.key;
      if (sorted.length > 1) {
        profile['reinforced_secondary'] = sorted[1].key;
      }
    }

    // En çok etkileşim alan renkleri kaydet
    if (colorCounts.isNotEmpty) {
      final sorted = colorCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      profile['reinforced_colors'] =
          sorted.take(3).map((e) => e.key).toList();
    }
  }
}
