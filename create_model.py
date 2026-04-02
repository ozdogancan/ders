# -*- coding: utf-8 -*-
p = 'lib/models/scan_analysis.dart'
content = r'''class ScanAnalysis {
  const ScanAnalysis({
    required this.roomType,
    required this.detectedStyle,
    required this.styleConfidence,
    required this.colorPalette,
    required this.mood,
    required this.summary,
    this.estimatedSize,
    this.furnitureDetected = const [],
    this.strengths = const [],
    this.improvements = const [],
    this.quickWins = const [],
    this.styleTags = const [],
    this.evlumbaSearchQuery,
  });

  final String roomType;
  final String detectedStyle;
  final double styleConfidence;
  final List<ColorInfo> colorPalette;
  final String mood;
  final String summary;
  final String? estimatedSize;
  final List<String> furnitureDetected;
  final List<String> strengths;
  final List<String> improvements;
  final List<QuickWin> quickWins;
  final List<String> styleTags;
  final String? evlumbaSearchQuery;

  factory ScanAnalysis.fromJson(Map<String, dynamic> json) {
    // Renk paleti
    final rawColors = json['color_palette'] as List<dynamic>? ?? [];
    final colors = rawColors.map((c) {
      if (c is Map<String, dynamic>) {
        return ColorInfo(
          hex: (c['hex'] as String? ?? '#000000').trim(),
          name: (c['name'] as String? ?? '').trim(),
        );
      }
      if (c is String) return ColorInfo(hex: c.trim(), name: '');
      return ColorInfo(hex: '#000000', name: '');
    }).toList();

    // Quick wins
    final rawWins = json['quick_wins'] as List<dynamic>? ?? [];
    final wins = rawWins.map((w) {
      if (w is Map<String, dynamic>) {
        return QuickWin(
          title: (w['title'] as String? ?? '').trim(),
          description: (w['description'] as String? ?? '').trim(),
          estimatedBudget: (w['estimated_budget'] as String?)?.trim(),
          impact: (w['impact'] as String? ?? 'medium').trim(),
        );
      }
      return QuickWin(title: w.toString(), description: '');
    }).toList();

    return ScanAnalysis(
      roomType: (json['room_type'] as String? ?? 'salon').trim(),
      detectedStyle: (json['detected_style'] as String? ?? 'Bilinmiyor').trim(),
      styleConfidence: (json['style_confidence'] as num? ?? 0.0).toDouble(),
      colorPalette: colors,
      mood: (json['mood'] as String? ?? '').trim(),
      summary: (json['summary'] as String? ?? '').trim(),
      estimatedSize: (json['estimated_size'] as String?)?.trim(),
      furnitureDetected: _toStringList(json['furniture_detected']),
      strengths: _toStringList(json['strengths']),
      improvements: _toStringList(json['improvements']),
      quickWins: wins,
      styleTags: _toStringList(json['style_tags']),
      evlumbaSearchQuery: (json['evlumba_search_query'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toJson() => {
    'room_type': roomType,
    'detected_style': detectedStyle,
    'style_confidence': styleConfidence,
    'color_palette': colorPalette.map((c) => c.toJson()).toList(),
    'mood': mood,
    'summary': summary,
    'estimated_size': estimatedSize,
    'furniture_detected': furnitureDetected,
    'strengths': strengths,
    'improvements': improvements,
    'quick_wins': quickWins.map((w) => w.toJson()).toList(),
    'style_tags': styleTags,
    'evlumba_search_query': evlumbaSearchQuery,
  };

  static List<String> _toStringList(dynamic raw) {
    if (raw is List) return raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    return [];
  }
}

class ColorInfo {
  const ColorInfo({required this.hex, this.name = ''});
  final String hex;
  final String name;

  Map<String, dynamic> toJson() => {'hex': hex, 'name': name};

  int get colorValue {
    final clean = hex.replaceAll('#', '');
    return int.tryParse('FF', radix: 16) ?? 0xFF000000;
  }
}

class QuickWin {
  const QuickWin({required this.title, required this.description, this.estimatedBudget, this.impact = 'medium'});
  final String title;
  final String description;
  final String? estimatedBudget;
  final String impact;

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'estimated_budget': estimatedBudget,
    'impact': impact,
  };
}
'''

with open(p, 'w', encoding='utf-8') as f:
    f.write(content)
print('Done - scan_analysis.dart olusturuldu')
