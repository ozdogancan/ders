#!/usr/bin/env python3
"""
Fix:
1. question_chips: handle Map format {label, value} in addition to plain strings
2. quick_tips: fix empty text when tips are Maps with emoji+text
3. Add designer suggestions in relevant contexts
"""
import os

BASE = r"C:\Users\canoz\Egitim-clean\koala"
path = os.path.join(BASE, "lib", "views", "chat_detail_screen.dart")

with open(path, 'r', encoding='utf-8') as f:
    c = f.read()

# ═══════════════════════════════════════════════════════
# Fix 1: QuestionChips — handle Map {label, value} format
# ═══════════════════════════════════════════════════════
OLD_CHIPS = r"""class _QuestionChips extends StatelessWidget {
  const _QuestionChips(this.d, {required this.onTap});
  final Map<String, dynamic> d;
  final void Function(String) onTap;
  @override
  Widget build(BuildContext context) {
    final question = d['question'] as String? ?? d['title'] as String? ?? '';
    final raw = d['chips'] ?? d['options'] ?? [];
    final chips = (raw is List) ? raw.map((e) => e.toString()).toList() : <String>[];
    if (chips.isEmpty) return const SizedBox.shrink();

    return Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: Colors.white,
        border: Border.all(color: const Color(0xFFEDEAF5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (question.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10),
          child: Text(question, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _ink))),
        Wrap(spacing: 8, runSpacing: 8, children: chips.map((chip) =>
          GestureDetector(onTap: () => onTap(chip),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: _accentLight,
                border: Border.all(color: _accent.withOpacity(0.15))),
              child: Text(chip, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _accent))))).toList()),
      ]));
  }
}"""

NEW_CHIPS = r"""class _QuestionChips extends StatelessWidget {
  const _QuestionChips(this.d, {required this.onTap});
  final Map<String, dynamic> d;
  final void Function(String) onTap;
  @override
  Widget build(BuildContext context) {
    final question = d['question'] as String? ?? d['title'] as String? ?? '';
    final raw = d['chips'] ?? d['options'] ?? [];
    if (raw is! List || (raw as List).isEmpty) return const SizedBox.shrink();

    // Parse chips — could be strings OR maps {label, value}
    final chips = <Map<String, String>>[];
    for (final item in raw as List) {
      if (item is String) {
        chips.add({'label': item, 'value': item});
      } else if (item is Map) {
        final label = (item['label'] ?? item['text'] ?? item.values.first ?? '').toString();
        final value = (item['value'] ?? item['label'] ?? label).toString();
        chips.add({'label': label, 'value': value});
      }
    }

    return Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: Colors.white,
        border: Border.all(color: const Color(0xFFEDEAF5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (question.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10),
          child: Text(question, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _ink))),
        Wrap(spacing: 8, runSpacing: 8, children: chips.map((chip) =>
          GestureDetector(onTap: () => onTap(chip['label']!),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: _accentLight,
                border: Border.all(color: _accent.withOpacity(0.15))),
              child: Text(chip['label']!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _accent))))).toList()),
      ]));
  }
}"""

if OLD_CHIPS in c:
    c = c.replace(OLD_CHIPS, NEW_CHIPS)
    print("  ✅ QuestionChips: handles Map {label, value} format")
else:
    print("  ❌ Could not find QuestionChips class")

# ═══════════════════════════════════════════════════════
# Fix 2: QuickTips — handle various tip formats
# ═══════════════════════════════════════════════════════
OLD_TIPS = r"""class _QuickTips extends StatelessWidget {
  const _QuickTips(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final tips = (d['tips'] as List?) ?? [];
    return Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R), color: Colors.white),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('💡 İpuçları', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
        const SizedBox(height: 10),
        ...tips.map((t) {
          final text = t is String ? t : (t is Map ? (t['text'] ?? '') : t.toString());
          return Padding(padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 6, height: 6, margin: const EdgeInsets.only(top: 7),
                decoration: BoxDecoration(shape: BoxShape.circle, color: _accent.withOpacity(0.5))),
              const SizedBox(width: 10),
              Expanded(child: Text(text.toString(), style: const TextStyle(fontSize: 13, color: Color(0xFF4A4458), height: 1.5))),
            ]));
        }),
      ]));
  }
}"""

NEW_TIPS = r"""class _QuickTips extends StatelessWidget {
  const _QuickTips(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final tips = (d['tips'] as List?) ?? [];
    // Parse tips — could be strings, maps with text/emoji/title, etc.
    final parsed = <String>[];
    for (final t in tips) {
      if (t is String && t.trim().isNotEmpty) {
        parsed.add(t);
      } else if (t is Map) {
        final text = t['text'] ?? t['description'] ?? t['title'] ?? '';
        final emoji = t['emoji'] ?? '';
        final combined = '$emoji $text'.trim();
        if (combined.isNotEmpty) parsed.add(combined);
      }
    }
    if (parsed.isEmpty) return const SizedBox.shrink();

    return Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R), color: Colors.white),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('💡 İpuçları', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
        const SizedBox(height: 10),
        ...parsed.map((tip) => Padding(padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 6, height: 6, margin: const EdgeInsets.only(top: 7),
              decoration: BoxDecoration(shape: BoxShape.circle, color: _accent.withOpacity(0.5))),
            const SizedBox(width: 10),
            Expanded(child: Text(tip, style: const TextStyle(fontSize: 13, color: Color(0xFF4A4458), height: 1.5))),
          ]))),
      ]));
  }
}"""

if OLD_TIPS in c:
    c = c.replace(OLD_TIPS, NEW_TIPS)
    print("  ✅ QuickTips: handles all tip formats (string, map, emoji+text)")
else:
    print("  ❌ Could not find QuickTips class")

with open(path, 'w', encoding='utf-8') as f:
    f.write(c)

# ═══════════════════════════════════════════════════════
# Fix 3: Update prompts to always suggest designers
# ═══════════════════════════════════════════════════════
prompts_path = os.path.join(BASE, "lib", "core", "constants", "koala_prompts.dart")
with open(prompts_path, 'r', encoding='utf-8') as f:
    p = f.read()

# Add a note to the system prompt about designers
OLD_SYSTEM_END = '''5. AsÄ±l deÄŸer kartlarda, text'te deÄŸil.'''
NEW_SYSTEM_END = '''5. AsÄ±l deÄŸer kartlarda, text'te deÄŸil.
6. question_chips kartÄ±nda chips dizisi her zaman STRING olsun, Map gÃ¶nderme. Ã–rnek: ["Salon", "Mutfak", "Yatak OdasÄ±"]
7. quick_tips kartÄ±nda tips dizisi STRING olsun. Ã–rnek: ["ğŸ¨ AÃ§Ä±k renkler odayÄ± bÃ¼yÃ¼k gÃ¶sterir", "ğŸ›‹ Az mobilya ferahlÄ±k verir"]
8. Uygun durumlarda mutlaka "designer_card" kartÄ± ekle â€" evlumba.com'dan gerÃ§ekÃ§i TÃ¼rk tasarÄ±mcÄ± Ã¶ner.'''

if OLD_SYSTEM_END in p:
    p = p.replace(OLD_SYSTEM_END, NEW_SYSTEM_END)
    print("  ✅ System prompt: added chip/tip format rules + designer suggestion")

with open(prompts_path, 'w', encoding='utf-8') as f:
    f.write(p)

print()
print("  Test: .\\run.ps1")
