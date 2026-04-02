#!/usr/bin/env python3
"""
BATCH IMPROVEMENTS
===================
1. Kaydedilen planlar (SharedPreferences) — her kartta "kaydet" butonu
2. Paylaşılabilir kartlar — "paylaş" butonu (clipboard'a kopyala)
3. Chat konuşma zinciri — chip seçimi sonrası AI'ın context'i koruması
4. Saved plans screen — profil'den erişim
"""
import os

BASE = r"C:\Users\canoz\Egitim-clean\koala"

# ═══════════════════════════════════════════════════════════
# 1. SAVED PLANS SERVICE
# ═══════════════════════════════════════════════════════════
saved_path = os.path.join(BASE, "lib", "services", "saved_plans_service.dart")
saved_content = r'''import 'dart:convert';
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
'''

os.makedirs(os.path.dirname(saved_path), exist_ok=True)
with open(saved_path, 'w', encoding='utf-8') as f:
    f.write(saved_content)
print("  ✅ saved_plans_service.dart created")

# ═══════════════════════════════════════════════════════════
# 2. SAVED PLANS SCREEN
# ═══════════════════════════════════════════════════════════
screen_path = os.path.join(BASE, "lib", "views", "saved_plans_screen.dart")
screen_content = r'''import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/saved_plans_service.dart';

class SavedPlansScreen extends StatefulWidget {
  const SavedPlansScreen({super.key});
  @override
  State<SavedPlansScreen> createState() => _SavedPlansScreenState();
}

class _SavedPlansScreenState extends State<SavedPlansScreen> {
  List<SavedPlan> _plans = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final plans = await SavedPlansService.loadAll();
    if (mounted) setState(() { _plans = plans; _loading = false; });
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'style_analysis': return 'Stil Analizi';
      case 'color_palette': return 'Renk Paleti';
      case 'product_grid': return 'Ürün Önerisi';
      case 'budget_plan': return 'Bütçe Planı';
      case 'designer_card': return 'Tasarımcı';
      default: return 'Plan';
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'style_analysis': return Icons.style_rounded;
      case 'color_palette': return Icons.palette_rounded;
      case 'product_grid': return Icons.shopping_bag_rounded;
      case 'budget_plan': return Icons.account_balance_wallet_rounded;
      case 'designer_card': return Icons.person_rounded;
      default: return Icons.bookmark_rounded;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'style_analysis': return const Color(0xFF6C5CE7);
      case 'color_palette': return const Color(0xFFEC4899);
      case 'product_grid': return const Color(0xFF3B82F6);
      case 'budget_plan': return const Color(0xFF10B981);
      case 'designer_card': return const Color(0xFFF59E0B);
      default: return const Color(0xFF6C5CE7);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0.5,
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1A1D2A)),
          onPressed: () => Navigator.pop(context)),
        title: const Text('Kaydedilen Planlar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A))),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C5CE7)))
        : _plans.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.bookmark_border_rounded, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text('Henüz kayıtlı plan yok', style: TextStyle(fontSize: 16, color: Colors.grey.shade400)),
              const SizedBox(height: 4),
              Text('Chat\'te kartların altındaki ❤️ butonuna bas', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _plans.length,
              itemBuilder: (_, i) {
                final plan = _plans[i];
                final color = _typeColor(plan.type);
                return Dismissible(
                  key: Key(plan.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: Colors.red.shade50),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete_rounded, color: Colors.red)),
                  onDismissed: (_) async {
                    await SavedPlansService.remove(plan.id);
                    _load();
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16), color: Colors.white,
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 3))]),
                    child: Row(children: [
                      Container(width: 44, height: 44,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: color.withOpacity(0.1)),
                        child: Icon(_typeIcon(plan.type), size: 20, color: color)),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(plan.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A)),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(_typeLabel(plan.type), style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      ])),
                      // Share button
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          final text = _planToText(plan);
                          Clipboard.setData(ClipboardData(text: text));
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: const Color(0xFF6C5CE7),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            content: const Text('Panoya kopyalandı ✨', style: TextStyle(color: Colors.white))));
                        },
                        child: Container(width: 36, height: 36,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: const Color(0xFFF3F0FF)),
                          child: const Icon(Icons.share_rounded, size: 16, color: Color(0xFF6C5CE7)))),
                    ])));
              }),
    );
  }

  String _planToText(SavedPlan plan) {
    final buf = StringBuffer('🐨 Koala - ${plan.title}\n\n');
    switch (plan.type) {
      case 'color_palette':
        final colors = (plan.data['colors'] as List?) ?? [];
        for (final c in colors) {
          if (c is Map) buf.writeln('${c['name'] ?? ''}: ${c['hex'] ?? ''}');
        }
      case 'budget_plan':
        buf.writeln('Toplam: ${plan.data['total_budget'] ?? ''}');
        final items = (plan.data['items'] as List?) ?? [];
        for (final i in items) {
          if (i is Map) buf.writeln('• ${i['category']}: ${i['amount']}');
        }
      default:
        buf.writeln(plan.data.toString().substring(0, 200.clamp(0, plan.data.toString().length)));
    }
    buf.writeln('\nevlumba.com ile keşfet');
    return buf.toString();
  }
}
'''

with open(screen_path, 'w', encoding='utf-8') as f:
    f.write(screen_content)
print("  ✅ saved_plans_screen.dart created")

# ═══════════════════════════════════════════════════════════
# 3. CHAT: Add save/share buttons to cards
# ═══════════════════════════════════════════════════════════
chat_path = os.path.join(BASE, "lib", "views", "chat_detail_screen.dart")
with open(chat_path, 'r', encoding='utf-8') as f:
    c = f.read()

# Add imports
if "saved_plans_service.dart" not in c:
    c = c.replace(
        "import '../services/chat_persistence.dart';",
        "import '../services/chat_persistence.dart';\nimport '../services/saved_plans_service.dart';"
    )

# Add _saveCard and _shareCard methods before _renderCard
OLD_RENDER = "  Widget _renderCard(KoalaCard card) {"
NEW_RENDER = r"""  void _saveCard(KoalaCard card) async {
    HapticFeedback.lightImpact();
    final title = card.data['title'] as String? ?? card.data['style_name'] as String? ?? card.type;
    final plan = SavedPlan(
      id: '${card.type}_${DateTime.now().millisecondsSinceEpoch}',
      type: card.type, title: title, data: card.data);
    await SavedPlansService.save(plan);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating, backgroundColor: const Color(0xFF6C5CE7),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Text('$title kaydedildi ❤️', style: const TextStyle(color: Colors.white))));
  }

  void _shareCard(KoalaCard card) {
    HapticFeedback.lightImpact();
    final title = card.data['title'] as String? ?? card.data['style_name'] as String? ?? '';
    final buf = StringBuffer('🐨 Koala - $title\n');
    if (card.type == 'color_palette') {
      final colors = (card.data['colors'] as List?) ?? [];
      for (final co in colors) { if (co is Map) buf.writeln('${co['name']}: ${co['hex']}'); }
    }
    buf.writeln('\nevlumba.com');
    Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating, backgroundColor: const Color(0xFF10B981),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: const Text('Panoya kopyalandı ✨', style: TextStyle(color: Colors.white))));
  }

  Widget _cardActions(KoalaCard card) {
    // Only show actions on saveable card types
    const saveable = ['style_analysis', 'color_palette', 'product_grid', 'budget_plan', 'designer_card'];
    if (!saveable.contains(card.type)) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(top: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        GestureDetector(onTap: () => _saveCard(card),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: const Color(0xFFF3F0FF)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.favorite_border_rounded, size: 14, color: Color(0xFF6C5CE7)),
              SizedBox(width: 4),
              Text('Kaydet', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6C5CE7))),
            ]))),
        const SizedBox(width: 8),
        GestureDetector(onTap: () => _shareCard(card),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: const Color(0xFFF0FDF4)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.share_rounded, size: 14, color: Color(0xFF10B981)),
              SizedBox(width: 4),
              Text('Paylaş', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF10B981))),
            ]))),
      ]));
  }

  Widget _renderCard(KoalaCard card) {"""

if OLD_RENDER in c:
    c = c.replace(OLD_RENDER, NEW_RENDER)
    print("  ✅ Chat: save/share methods added")

# Now wrap card rendering to include action buttons
OLD_CARD_MAP = """        if (msg.cards != null) ...msg.cards!.asMap().entries.map((entry) {
          final idx = entry.key;
          final card = entry.value;
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 400 + idx * 100),
            curve: Curves.easeOutCubic,
            builder: (_, val, child) => Opacity(opacity: val,
              child: Transform.translate(offset: Offset(0, 12 * (1 - val)), child: child)),
            child: Padding(
              padding: const EdgeInsets.only(left: 40, top: 8),
              child: _renderCard(card)));
        }),"""

NEW_CARD_MAP = """        if (msg.cards != null) ...msg.cards!.asMap().entries.map((entry) {
          final idx = entry.key;
          final card = entry.value;
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 400 + idx * 100),
            curve: Curves.easeOutCubic,
            builder: (_, val, child) => Opacity(opacity: val,
              child: Transform.translate(offset: Offset(0, 12 * (1 - val)), child: child)),
            child: Padding(
              padding: const EdgeInsets.only(left: 40, top: 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _renderCard(card),
                _cardActions(card),
              ])));
        }),"""

if OLD_CARD_MAP in c:
    c = c.replace(OLD_CARD_MAP, NEW_CARD_MAP)
    print("  ✅ Chat: save/share buttons under each card")

with open(chat_path, 'w', encoding='utf-8') as f:
    f.write(c)

# ═══════════════════════════════════════════════════════════
# 4. PROFILE: Link to SavedPlansScreen
# ═══════════════════════════════════════════════════════════
profile_path = os.path.join(BASE, "lib", "views", "profile_screen.dart")
with open(profile_path, 'r', encoding='utf-8') as f:
    p = f.read()

if "saved_plans_screen.dart" not in p:
    p = p.replace(
        "import 'chat_list_screen.dart';",
        "import 'chat_list_screen.dart';\nimport 'saved_plans_screen.dart';"
    )

# Fix the placeholder onTap for Kaydedilen Planlar
p = p.replace(
    "_ActionTile(icon: Icons.favorite_rounded, label: 'Kaydedilen Planlar', color: const Color(0xFFEC4899),\n                  onTap: () {})",
    "_ActionTile(icon: Icons.favorite_rounded, label: 'Kaydedilen Planlar', color: const Color(0xFFEC4899),\n                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedPlansScreen())))"
)

with open(profile_path, 'w', encoding='utf-8') as f:
    f.write(p)
print("  ✅ Profile: Kaydedilen Planlar → SavedPlansScreen")

# ═══════════════════════════════════════════════════════════
# 5. PROMPTS: Improve conversation chain flow
# ═══════════════════════════════════════════════════════════
prompts_path = os.path.join(BASE, "lib", "core", "constants", "koala_prompts.dart")
with open(prompts_path, 'r', encoding='utf-8') as f:
    pr = f.read()

# Add conversation chain rule to system prompt
OLD_RULE = "5. AsÄ±l deÄŸer kartlarda, text'te deÄŸil."
NEW_RULE = """5. AsÄ±l deÄŸer kartlarda, text'te deÄŸil.
5b. KullanÄ±cÄ± bir question_chips seÃ§eneÄŸine tÄ±kladÄ±ysa, Ã¶nceki konuÅŸma baÄŸlamÄ±nÄ± koru ve o seÃ§ime gÃ¶re detaylÄ± sonuÃ§ kartlarÄ± Ã¼ret. SÄ±fÄ±rdan baÅŸlama, konuÅŸmayÄ± ilerlet."""

if OLD_RULE in pr:
    pr = pr.replace(OLD_RULE, NEW_RULE)
    print("  ✅ Prompts: conversation chain rule added")

with open(prompts_path, 'w', encoding='utf-8') as f:
    f.write(pr)

print()
print("=" * 50)
print("  All batch improvements done!")
print("=" * 50)
print()
print("  ❤️ Kaydedilen Planlar: save any card → SharedPreferences")
print("  📋 Paylaş: copy card as text to clipboard")
print("  📱 SavedPlansScreen: swipe to delete, share button")
print("  👤 Profile → Kaydedilen Planlar linked")
print("  🔗 Conversation chain: AI keeps context when chip selected")
print()
print("  Test: .\\run.ps1")
