import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SavedPlan {
  final String id;
  final String type; // style_analysis, color_palette, product_grid, budget_plan, designer_card
  final String title;
  final Map<String, dynamic> data;
  final DateTime savedAt;

  SavedPlan({required this.id, required this.type, required this.title, required this.data, DateTime? savedAt})
    : savedAt = savedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id, 'type': type, 'title': title, 'data': data,
    'savedAt': savedAt.toIso8601String(),
  };

  factory SavedPlan.fromJson(Map<String, dynamic> m) => SavedPlan(
    id: m['id'] ?? '', type: m['type'] ?? '', title: m['title'] ?? '',
    data: m['data'] is Map ? Map<String, dynamic>.from(m['data']) : {},
    savedAt: DateTime.tryParse(m['savedAt'] ?? '') ?? DateTime.now(),
  );
}

class SavedPlansService {
  static const _key = 'koala_saved_plans';

  static Future<List<SavedPlan>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw.map((s) => SavedPlan.fromJson(jsonDecode(s))).toList()
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
  }

  static Future<void> save(SavedPlan plan) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    // Remove duplicate
    list.removeWhere((s) { final m = jsonDecode(s); return m['id'] == plan.id; });
    list.insert(0, jsonEncode(plan.toJson()));
    if (list.length > 100) list.removeRange(100, list.length);
    await prefs.setStringList(_key, list);
  }

  static Future<void> remove(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    list.removeWhere((s) { final m = jsonDecode(s); return m['id'] == id; });
    await prefs.setStringList(_key, list);
  }

  static Future<bool> isSaved(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    return list.any((s) { final m = jsonDecode(s); return m['id'] == id; });
  }
}
