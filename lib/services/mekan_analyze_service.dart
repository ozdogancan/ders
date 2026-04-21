import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;
import 'package:http/http.dart' as http;

/// Moondream tarafından üretilen renk — "cream (#F5F1EA)" gibi stringlerden
/// parse edilir.
class MekanColor {
  final String name;
  final Color color;
  final String hex;
  const MekanColor({required this.name, required this.color, required this.hex});
}

class AnalyzeResult {
  final String roomType;  // ör. "living_room", "bedroom", "other"
  final String style;     // ör. "minimalist"
  final List<MekanColor> colors;
  final String caption;   // kısa sahne açıklaması
  final String mood;      // ör. "calm, warm"

  const AnalyzeResult({
    required this.roomType,
    required this.style,
    required this.colors,
    required this.caption,
    required this.mood,
  });

  /// Fotoğraf mekan değilse (other / selfie / portre) ipucu ver.
  bool get isNotMekan {
    final rt = roomType.toLowerCase();
    if (rt.contains('other') || rt.isEmpty || rt == 'unknown') return true;
    final cap = caption.toLowerCase();
    const bad = ['selfie', 'portrait', 'person', 'man ', 'woman ', 'face', 'people'];
    for (final b in bad) {
      if (cap.contains(b)) return true;
    }
    return false;
  }

  /// UI'da kullanılacak kısa Türkçe etiket.
  String get roomLabelTr {
    final rt = roomType.toLowerCase().replaceAll('_', ' ');
    if (rt.contains('living')) return 'Salon';
    if (rt.contains('bed')) return 'Yatak odası';
    if (rt.contains('kitchen')) return 'Mutfak';
    if (rt.contains('bath')) return 'Banyo';
    if (rt.contains('dining')) return 'Yemek odası';
    if (rt.contains('office') || rt.contains('study')) return 'Çalışma';
    if (rt.contains('hall') || rt.contains('entry')) return 'Giriş';
    if (rt.contains('kids') || rt.contains('child')) return 'Çocuk odası';
    if (rt.isEmpty) return 'Mekan';
    // ilk harf büyük
    return rt[0].toUpperCase() + rt.substring(1);
  }
}

class MekanAnalyzeException implements Exception {
  final String code;
  final String detail;
  MekanAnalyzeException(this.code, this.detail);
  @override
  String toString() => 'MekanAnalyzeException($code): $detail';
}

class MekanAnalyzeService {
  static const String _apiBase = String.fromEnvironment(
    'KOALA_API_URL',
    defaultValue: 'https://koala-api-olive.vercel.app',
  );

  static Future<AnalyzeResult> analyze(Uint8List imageBytes) async {
    final b64 = base64Encode(imageBytes);
    final dataUrl = 'data:image/jpeg;base64,$b64';

    final resp = await http.post(
      Uri.parse('$_apiBase/api/analyze-room'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'image': dataUrl}),
    );

    Map<String, dynamic> j;
    try {
      j = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw MekanAnalyzeException('bad_response', 'HTTP ${resp.statusCode}');
    }

    if (resp.statusCode >= 400) {
      throw MekanAnalyzeException(
        (j['error'] ?? 'http_${resp.statusCode}').toString(),
        (j['detail'] ?? resp.body).toString(),
      );
    }

    return AnalyzeResult(
      roomType: (j['room_type'] ?? '').toString(),
      style: (j['style'] ?? '').toString(),
      caption: (j['caption'] ?? '').toString(),
      mood: (j['mood'] ?? '').toString(),
      colors: parseColors((j['colors'] ?? '').toString()),
    );
  }

  /// "cream (#F5F1EA), oak (#C4A27B)" -> `List<MekanColor>`
  static List<MekanColor> parseColors(String raw) {
    if (raw.isEmpty) return const [];
    final re = RegExp(r'([A-Za-z][A-Za-z\s\-]*?)\s*\(#([0-9a-fA-F]{3,8})\)');
    final out = <MekanColor>[];
    for (final m in re.allMatches(raw)) {
      final name = (m.group(1) ?? '').trim();
      final hex = (m.group(2) ?? '').trim();
      final c = _hexToColor(hex);
      if (c != null && name.isNotEmpty) {
        out.add(MekanColor(name: name, color: c, hex: '#${hex.toUpperCase()}'));
      }
    }
    return out;
  }

  static Color? _hexToColor(String hex) {
    var h = hex.replaceAll('#', '');
    if (h.length == 3) {
      h = h.split('').map((c) => '$c$c').join();
    }
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    final v = int.tryParse(h, radix: 16);
    if (v == null) return null;
    return Color(v);
  }
}
