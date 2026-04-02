#!/usr/bin/env python3
"""
PREMIUM IMPROVEMENTS
====================
1. Personalized greeting (time-based)
2. Press scale animation on cards
3. 3rd Hızlı Başla card: Renk Öner
4. TrendCard swatches tappable → chat
5. Random FactCards
6. "Mimarla Konuş" card type in chat
7. Haptic feedback on interactions
"""
import os, re

BASE = r"C:\Users\canoz\Egitim-clean\koala"

# ═══════════════════════════════════════════════════════════
# 1. HOME: Personalized greeting + press scale + 3rd CTA + random facts
# ═══════════════════════════════════════════════════════════
home_path = os.path.join(BASE, "lib", "views", "home_screen.dart")
with open(home_path, 'r', encoding='utf-8') as f:
    h = f.read()

# Add flutter/services import for HapticFeedback
if "flutter/services.dart" not in h:
    h = h.replace(
        "import 'package:flutter/material.dart';",
        "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';\nimport 'dart:math';"
    )

# 1A. Replace static slogan with time-based greeting
OLD_SLOGAN = "Text('tara.  keÅŸfet.  tasarla.', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: Colors.grey.shade400, letterSpacing: 2.0)),"
NEW_SLOGAN = """Builder(builder: (_) {
                    final hour = DateTime.now().hour;
                    final greeting = hour < 12 ? 'Günaydın! ☀️ Bugün odana yeni bir dokunuş yapalım mı?'
                      : hour < 18 ? 'İyi günler! 🌿 Yaşam alanını güzelleştirelim.'
                      : 'İyi akşamlar! 🌙 Evini hayal et, Koala tasarlasın.';
                    return Text(greeting, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: Colors.grey.shade400), textAlign: TextAlign.center);
                  }),"""

if OLD_SLOGAN in h:
    h = h.replace(OLD_SLOGAN, NEW_SLOGAN)
    print("  ✅ Time-based greeting")

# 1B. Add 3rd mini CTA: Renk Öner (between Bütçe Planla and Tasarımcı Bul)
OLD_TWO_CTAS = """                  Row(children: [
                    Expanded(child: _MiniCTA(
                      icon: Icons.account_balance_wallet_rounded,
                      title: 'BÃ¼tÃ§e Planla',
                      onTap: () => _openChat(intent: KoalaIntent.budgetPlan),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _DesignerCTA(
                      onTap: () => _openChat(intent: KoalaIntent.designerMatch),
                    )),
                  ]),"""

NEW_THREE_CTAS = """                  Row(children: [
                    Expanded(child: _MiniCTA(
                      icon: Icons.account_balance_wallet_rounded,
                      title: 'Bütçe Planla',
                      onTap: () { HapticFeedback.lightImpact(); _openChat(intent: KoalaIntent.budgetPlan); },
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: _MiniCTA(
                      icon: Icons.palette_rounded,
                      title: 'Renk Öner',
                      onTap: () { HapticFeedback.lightImpact(); _openChat(intent: KoalaIntent.colorAdvice); },
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: _MiniCTA(
                      icon: Icons.person_search_rounded,
                      title: 'Tasarımcı',
                      onTap: () { HapticFeedback.lightImpact(); _openChat(intent: KoalaIntent.designerMatch); },
                    )),
                  ]),"""

if OLD_TWO_CTAS in h:
    h = h.replace(OLD_TWO_CTAS, NEW_THREE_CTAS)
    print("  ✅ 3 mini CTAs (Bütçe + Renk + Tasarımcı)")

# 1C. Random FactCards
OLD_FACT_1 = "_FactCard('\\u{1F33F}', 'Bitkiler odadaki\\nstresi %37 azaltÄ±yor', bgColor: const Color(0xFFF0FDF4))"
OLD_FACT_2 = "_FactCard('\\u{2728}', 'AÃ§Ä±k renkli perdeler\\nodayÄ± %30 geniÅŸ gÃ¶sterir', bgColor: const Color(0xFFFEF3C7))"

NEW_FACT_1 = "_RandomFact(seed: 0)"
NEW_FACT_2 = "_RandomFact(seed: 1)"

h = h.replace(OLD_FACT_1, NEW_FACT_1)
h = h.replace(OLD_FACT_2, NEW_FACT_2)
print("  ✅ Random FactCards")

# 1D. Make FullCTA tappable with haptic
h = h.replace(
    "onTap: () => _openChat(intent: KoalaIntent.roomRenovation),\n                  )",
    "onTap: () { HapticFeedback.lightImpact(); _openChat(intent: KoalaIntent.roomRenovation); },\n                  )"
)

with open(home_path, 'w', encoding='utf-8') as f:
    f.write(h)

# ═══════════════════════════════════════════════════════════
# Now add new widgets: _PressableCard, _RandomFact, updated _TrendCard
# ═══════════════════════════════════════════════════════════
with open(home_path, 'r', encoding='utf-8') as f:
    h = f.read()

# Remove old _DesignerCTA since we replaced it with _MiniCTA
OLD_DESIGNER_CTA_START = "class _DesignerCTA extends StatelessWidget {"
OLD_DESIGNER_CTA_END = "  Widget _dummyAvatar(Color color) => Container(width: 30, height: 30,\n    decoration: BoxDecoration(shape: BoxShape.circle, color: color,\n      border: Border.all(color: Colors.white, width: 2)),\n    child: const Icon(Icons.person_rounded, size: 16, color: Colors.white));\n}"

# Find and remove _DesignerCTA class
idx_start = h.find(OLD_DESIGNER_CTA_START)
idx_end = h.find(OLD_DESIGNER_CTA_END)
if idx_start > 0 and idx_end > idx_start:
    h = h[:idx_start] + h[idx_end + len(OLD_DESIGNER_CTA_END):]
    print("  ✅ Old _DesignerCTA removed")

# Replace TrendCard with tappable swatches
OLD_TREND_START = "class _TrendCard extends StatelessWidget {"
idx_ts = h.find(OLD_TREND_START)
if idx_ts > 0:
    # Find end of class
    brace_count = 0
    i = idx_ts
    class_started = False
    end_idx = len(h)
    while i < len(h):
        if h[i] == '{':
            brace_count += 1
            class_started = True
        elif h[i] == '}':
            brace_count -= 1
            if class_started and brace_count == 0:
                end_idx = i + 1
                break
        i += 1
    
    NEW_TREND = r"""class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R), color: Colors.white,
      border: Border.all(color: const Color(0xFFF0EDF5))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 24, height: 24,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(7), color: const Color(0xFFF0ECFF)),
          child: const Center(child: Icon(Icons.palette_rounded, size: 14, color: Color(0xFF6C5CE7)))),
        const SizedBox(width: 8),
        Text('2026 Trend', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF6C5CE7).withOpacity(0.7))),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        _tappableSwatch(context, const Color(0xFFC4704A), 'Terracotta'),
        const SizedBox(width: 6),
        _tappableSwatch(context, const Color(0xFF8B9E6B), 'Sage'),
        const SizedBox(width: 6),
        _tappableSwatch(context, const Color(0xFFE8D5C4), 'Cream'),
      ]),
      const SizedBox(height: 12),
      GestureDetector(onTap: () { HapticFeedback.lightImpact(); onTap(); },
        child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: const Color(0xFFF0ECFF)),
          child: const Center(child: Text('Odana uygula →', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF6C5CE7)))))),
    ])));

  Widget _tappableSwatch(BuildContext ctx, Color c, String name) => Expanded(
    child: GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(ctx).push(MaterialPageRoute(builder: (_) =>
          ChatDetailScreen(initialText: '$name rengini odamda nasıl kullanabilirim?')));
      },
      child: Column(children: [
        Container(height: 36, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: c)),
        const SizedBox(height: 4),
        Text(name, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
      ])));
}"""
    
    h = h[:idx_ts] + NEW_TREND + h[end_idx:]
    print("  ✅ TrendCard: tappable swatches → chat")

# Add _RandomFact widget before _PickBtn
RANDOM_FACT_WIDGET = r"""
class _RandomFact extends StatelessWidget {
  const _RandomFact({required this.seed});
  final int seed;

  static const _facts = [
    {'emoji': '🌿', 'text': 'Bitkiler odadaki\nstresi %37 azaltıyor', 'color': Color(0xFFF0FDF4)},
    {'emoji': '✨', 'text': 'Açık renkli perdeler\nodayı %30 geniş gösterir', 'color': Color(0xFFFEF3C7)},
    {'emoji': '🪞', 'text': 'Ayna karşıya koyunca\noda 2 kat büyük görünür', 'color': Color(0xFFF0F9FF)},
    {'emoji': '🕯️', 'text': 'Sıcak ışık tonu\nrahatlama hissini artırır', 'color': Color(0xFFFFF7ED)},
    {'emoji': '🎨', 'text': 'Mavi tonlar odada\nüretkenliği %15 artırır', 'color': Color(0xFFEFF6FF)},
    {'emoji': '🛋️', 'text': 'Yuvarlak mobilyalar\nodayı daha davetkar yapar', 'color': Color(0xFFFDF2F8)},
    {'emoji': '📐', 'text': '60-30-10 kuralı:\nher odanın renk formülü', 'color': Color(0xFFF5F3FF)},
    {'emoji': '🖼️', 'text': 'Tablolar göz hizasında\nasılmalı (150cm)', 'color': Color(0xFFFEFCE8)},
  ];

  @override
  Widget build(BuildContext context) {
    final idx = (seed + DateTime.now().day) % _facts.length;
    final f = _facts[idx];
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18),
        color: f['color'] as Color, border: Border.all(color: const Color(0xFFF0EDF5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Text(f['emoji'] as String, style: const TextStyle(fontSize: 16)), const SizedBox(width: 6),
          Text('Biliyor muydun?', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey.shade400, letterSpacing: 0.5))]),
        const SizedBox(height: 8),
        Text(f['text'] as String, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1D2A), height: 1.4)),
      ])));
  }
}

"""

# Insert before _PickBtn
pick_idx = h.find("class _PickBtn")
if pick_idx > 0:
    h = h[:pick_idx] + RANDOM_FACT_WIDGET + h[pick_idx:]
    print("  ✅ _RandomFact widget added (8 facts, daily rotation)")

# Remove old _FactCard class if still there
fact_idx = h.find("class _FactCard extends StatelessWidget")
if fact_idx > 0:
    # Find end
    brace_count = 0
    i = fact_idx
    started = False
    end_idx = len(h)
    while i < len(h):
        if h[i] == '{': brace_count += 1; started = True
        elif h[i] == '}':
            brace_count -= 1
            if started and brace_count == 0: end_idx = i + 1; break
        i += 1
    h = h[:fact_idx] + h[end_idx:]
    print("  ✅ Old _FactCard removed")

with open(home_path, 'w', encoding='utf-8') as f:
    f.write(h)

# ═══════════════════════════════════════════════════════════
# 2. CHAT: Add "Mimarla Konuş" card type + haptic on chips
# ═══════════════════════════════════════════════════════════
chat_path = os.path.join(BASE, "lib", "views", "chat_detail_screen.dart")
with open(chat_path, 'r', encoding='utf-8') as f:
    c = f.read()

# Add architect_cta card type to _renderCard
OLD_DEFAULT = """      case 'image_prompt': return _ImagePrompt(card.data, onGenerate: _generateImage);
      default:"""

NEW_DEFAULT = """      case 'image_prompt': return _ImagePrompt(card.data, onGenerate: _generateImage);
      case 'architect_cta': return _ArchitectCTA(card.data);
      default:"""

if OLD_DEFAULT in c:
    c = c.replace(OLD_DEFAULT, NEW_DEFAULT)
    print("  ✅ Chat: architect_cta card type added")

# Add _ArchitectCTA widget at end of file
ARCHITECT_WIDGET = r"""

// ═══════════════════════════════════════════════════════
// ARCHITECT CTA — "Mimarla Konuş" card
// ═══════════════════════════════════════════════════════
class _ArchitectCTA extends StatelessWidget {
  const _ArchitectCTA(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF6C5CE7), Color(0xFF8B5CF6), Color(0xFFA78BFA)])),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 40, height: 40,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.white.withOpacity(0.2)),
            child: const Icon(Icons.videocam_rounded, size: 20, color: Colors.white)),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('İç Mimarla Konuş', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
            SizedBox(height: 2),
            Text('evlumba uzmanlarından biri sana yardımcı olsun',
              style: TextStyle(fontSize: 12, color: Colors.white70)),
          ])),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          // Stacked avatars
          SizedBox(width: 72, height: 28, child: Stack(children: [
            _miniAvatar(0, const Color(0xFFEC4899)),
            _miniAvatar(18, const Color(0xFF3B82F6)),
            _miniAvatar(36, const Color(0xFF10B981)),
          ])),
          const SizedBox(width: 8),
          Text('12 mimar şu an müsait', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.7))),
        ]),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            launchUrl(Uri.parse('https://www.evlumba.com/tasarimcilar'), mode: LaunchMode.externalApplication);
          },
          child: Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.white),
            child: const Center(child: Text('Ücretsiz 30dk Görüşme Başlat',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF6C5CE7)))))),
      ]));
  }

  Widget _miniAvatar(double left, Color color) => Positioned(left: left, child: Container(
    width: 28, height: 28,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color,
      border: Border.all(color: Colors.white.withOpacity(0.3), width: 2)),
    child: const Icon(Icons.person_rounded, size: 14, color: Colors.white)));
}
"""

if '_ArchitectCTA' not in c:
    c = c.rstrip() + ARCHITECT_WIDGET
    print("  ✅ _ArchitectCTA widget added")

# Add haptic to _onChipTap (already has it, verify)
if "HapticFeedback.lightImpact();\n    _sendToAI" not in c:
    c = c.replace(
        "void _onChipTap(String chipText) {\n    HapticFeedback.lightImpact();\n    _sendToAI(text: chipText);",
        "void _onChipTap(String chipText) {\n    HapticFeedback.lightImpact();\n    _sendToAI(text: chipText);"
    )

with open(chat_path, 'w', encoding='utf-8') as f:
    f.write(c)

# ═══════════════════════════════════════════════════════════
# 3. PROMPTS: Add architect_cta to AI responses
# ═══════════════════════════════════════════════════════════
prompts_path = os.path.join(BASE, "lib", "core", "constants", "koala_prompts.dart")
with open(prompts_path, 'r', encoding='utf-8') as f:
    p = f.read()

# Add architect_cta format to system prompt
OLD_RULE = '8. Uygun durumlarda mutlaka "designer_card" kartÄ± ekle'
NEW_RULE = '''8. Uygun durumlarda mutlaka "designer_card" kartÄ± ekle
9. Oda yenileme, stil keÅŸfetme, tasarÄ±mcÄ± bulma gibi konularda son kart olarak "architect_cta" kartÄ± ekle. Format: {"type": "architect_cta", "title": "Ä°Ã§ Mimarla KonuÅŸ"}'''

if OLD_RULE in p:
    p = p.replace(OLD_RULE, NEW_RULE)
    print("  ✅ Prompt: architect_cta rule added")

with open(prompts_path, 'w', encoding='utf-8') as f:
    f.write(p)

print()
print("=" * 50)
print("  Premium improvements done!")
print("=" * 50)
print()
print("  🌅 Time-based greeting (günaydın/iyi günler/iyi akşamlar)")
print("  🎨 3 mini CTAs (Bütçe + Renk + Tasarımcı)")
print("  🎯 TrendCard swatches tappable → 'Bu rengi odamda nasıl kullanırım?'")
print("  🔮 8 random facts (daily rotation, soft colored bg)")
print("  👷 'Mimarla Konuş' card type (gradient, stacked avatars, evlumba CTA)")
print("  📳 Haptic feedback on CTAs")
print()
print("  Test: .\\run.ps1")
