#!/usr/bin/env python3
"""
FAZ 2 — Chat-first architecture
================================
1. Fix question_chips to handle both 'chips' and 'options' keys
2. Add image_prompt card renderer (triggers Gemini image gen)
3. Update home_screen to route everything to ChatDetailScreen (no more guided_flow_screen)
4. Add unknown card fallback (no more raw JSON)
"""
import os, re

BASE = r"C:\Users\canoz\Egitim-clean\koala"

# ═══════════════════════════════════════════════════════════
# 1. FIX CHAT DETAIL SCREEN — card parsing + image_prompt
# ═══════════════════════════════════════════════════════════
path = os.path.join(BASE, "lib", "views", "chat_detail_screen.dart")
with open(path, 'r', encoding='utf-8') as f:
    c = f.read()

# --- Fix 1: Add image_prompt and unknown card to _renderCard ---
OLD_RENDER = """  Widget _renderCard(KoalaCard card) {
    switch (card.type) {
      case 'question_chips': return _QuestionChipsCard(card.data, onChipTap: _onChipTap);
      case 'style_analysis': return _StyleCard(card.data);
      case 'product_grid': return _ProductGrid(card.data);
      case 'color_palette': return _ColorPaletteCard(card.data);
      case 'designer_card': return _DesignerCard(card.data);
      case 'budget_plan': return _BudgetCard(card.data);
      case 'quick_tips': return _TipsCard(card.data);
      case 'before_after': return _BeforeAfterCard(card.data);
      default: return const SizedBox.shrink();
    }
  }"""

NEW_RENDER = """  Widget _renderCard(KoalaCard card) {
    switch (card.type) {
      case 'question_chips': return _QuestionChipsCard(card.data, onChipTap: _onChipTap);
      case 'style_analysis': return _StyleCard(card.data);
      case 'product_grid': return _ProductGrid(card.data);
      case 'color_palette': return _ColorPaletteCard(card.data);
      case 'designer_card': return _DesignerCard(card.data);
      case 'budget_plan': return _BudgetCard(card.data);
      case 'quick_tips': return _TipsCard(card.data);
      case 'before_after': return _BeforeAfterCard(card.data);
      case 'image_prompt': return _ImagePromptCard(card.data, onGenerate: _generateImage);
      default:
        // Unknown card — show as info text instead of raw JSON
        final title = card.data['title'] as String? ?? card.data['question'] as String? ?? '';
        final desc = card.data['description'] as String? ?? card.data['prompt'] as String? ?? '';
        if (title.isEmpty && desc.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: const Color(0xFFF8F6FF),
            border: Border.all(color: const Color(0xFFEDEAF5))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title.isNotEmpty) Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1D2A))),
            if (desc.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4),
              child: Text(desc, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4))),
          ]));
    }
  }

  // ── Image generation ──
  Future<void> _generateImage(String prompt) async {
    setState(() {
      _msgs.add(_Msg(role: 'koala', text: '🎨 Tasarım oluşturuluyor...'));
      _loading = true;
    });
    _scrollDown();

    try {
      final imageService = KoalaImageService();
      final bytes = await imageService.generateRoomDesign(
        roomType: 'salon', style: 'modern', additionalDetails: prompt);
      
      setState(() {
        // Remove "oluşturuluyor" message
        if (_msgs.isNotEmpty && _msgs.last.text == '🎨 Tasarım oluşturuluyor...') {
          _msgs.removeLast();
        }
        if (bytes != null) {
          _msgs.add(_Msg(role: 'koala', text: '🏠 İşte tasarım önerim:', photo: bytes));
        } else {
          _msgs.add(_Msg(role: 'koala', text: 'Görsel oluşturulamadı, ama metin önerilerimi kullanabilirsin 🐨'));
        }
        _loading = false;
      });
    } catch (e) {
      setState(() {
        if (_msgs.isNotEmpty && _msgs.last.text == '🎨 Tasarım oluşturuluyor...') {
          _msgs.removeLast();
        }
        _msgs.add(_Msg(role: 'koala', text: 'Görsel oluşturma şu an çalışmıyor, ama önerilerimi deneyebilirsin 🐨'));
        _loading = false;
      });
    }
    _scrollDown();
    _persistMessages();
  }"""

if OLD_RENDER in c:
    c = c.replace(OLD_RENDER, NEW_RENDER)
    print("  ✅ _renderCard updated (image_prompt + fallback)")
else:
    print("  ❌ Could not find _renderCard")

# --- Fix 2: Add KoalaImageService import ---
if "koala_image_service.dart" not in c:
    c = c.replace(
        "import '../services/koala_ai_service.dart';",
        "import '../services/koala_ai_service.dart';\nimport '../services/koala_image_service.dart';"
    )
    print("  ✅ Added koala_image_service import")

# --- Fix 3: Fix _QuestionChipsCard to handle 'options' key too ---
OLD_CHIPS = """    final question = d['question'] as String? ?? '';
    final chips = (d['chips'] as List?)?.cast<String>() ?? [];"""

NEW_CHIPS = """    final question = d['question'] as String? ?? d['title'] as String? ?? '';
    // AI sometimes sends 'chips', sometimes 'options'
    final rawChips = d['chips'] ?? d['options'] ?? [];
    final chips = (rawChips is List) ? rawChips.map((e) => e.toString()).toList() : <String>[];"""

if OLD_CHIPS in c:
    c = c.replace(OLD_CHIPS, NEW_CHIPS)
    print("  ✅ _QuestionChipsCard handles 'options' key too")
else:
    print("  ❌ Could not find QuestionChipsCard chips parsing")

with open(path, 'w', encoding='utf-8') as f:
    f.write(c)

# ═══════════════════════════════════════════════════════════
# 2. ADD IMAGE PROMPT CARD WIDGET (before the closing of file)
# ═══════════════════════════════════════════════════════════
with open(path, 'r', encoding='utf-8') as f:
    c = f.read()

# Add _ImagePromptCard before the last card widget
IMAGE_PROMPT_CARD = r'''

// ═══════════════════════════════════════════════════════════
// IMAGE PROMPT CARD — AI görsel üretme önerisi
// ═══════════════════════════════════════════════════════════

class _ImagePromptCard extends StatelessWidget {
  const _ImagePromptCard(this.d, {required this.onGenerate});
  final Map<String, dynamic> d;
  final void Function(String) onGenerate;

  @override
  Widget build(BuildContext context) {
    final title = d['title'] as String? ?? 'Tasarım Görseli';
    final prompt = d['prompt'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFFF0ECFF), Color(0xFFE8F4FD)])),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 32, height: 32,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: const Color(0xFF6C5CE7).withOpacity(0.1)),
            child: const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF6C5CE7))),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A)))),
        ]),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, height: 44,
          child: ElevatedButton.icon(
            onPressed: () => onGenerate(prompt),
            icon: const Icon(Icons.brush_rounded, size: 18),
            label: const Text('Görseli Oluştur', style: TextStyle(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C5CE7), foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0))),
      ]));
  }
}
'''

# Insert before the last class in the file
if '_ImagePromptCard' not in c:
    # Insert before _BeforeAfterCard class
    insert_point = c.rfind("class _BeforeAfterCard")
    if insert_point > 0:
        c = c[:insert_point] + IMAGE_PROMPT_CARD + "\n" + c[insert_point:]
        print("  ✅ _ImagePromptCard added")
    else:
        # Append at end
        c += IMAGE_PROMPT_CARD
        print("  ✅ _ImagePromptCard appended")

with open(path, 'w', encoding='utf-8') as f:
    f.write(c)

# ═══════════════════════════════════════════════════════════
# 3. UPDATE HOME SCREEN — route to ChatDetailScreen instead of GuidedFlowScreen
# ═══════════════════════════════════════════════════════════
home_path = os.path.join(BASE, "lib", "views", "home_screen.dart")
with open(home_path, 'r', encoding='utf-8') as f:
    h = f.read()

# Remove guided_flow_screen import
h = h.replace("import 'guided_flow_screen.dart';\n", "")
h = h.replace("import 'guided_flow_screen.dart';", "")

# Ensure KoalaIntent import (from koala_ai_service)
if "KoalaIntent" not in h and "koala_ai_service.dart" not in h:
    h = h.replace(
        "import 'chat_detail_screen.dart';",
        "import 'chat_detail_screen.dart';\nimport '../services/koala_ai_service.dart';"
    )

# Replace _startFlow method to open ChatDetailScreen with intent
OLD_START = "  void _startFlow(FlowState flow) =>\n    Navigator.of(context).push(MaterialPageRoute(builder: (_) => GuidedFlowScreen(flow: flow)));"
NEW_START = """  void _openChat({KoalaIntent? intent, Map<String, String>? params, String? text}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatDetailScreen(
      intent: intent, intentParams: params, initialText: text)));"""

if OLD_START in h:
    h = h.replace(OLD_START, NEW_START)
    print("  ✅ _startFlow → _openChat")
else:
    print("  ⚠️  Could not find _startFlow, trying regex...")
    h = re.sub(
        r"void _startFlow\(FlowState flow\)[^;]*;",
        """void _openChat({KoalaIntent? intent, Map<String, String>? params, String? text}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatDetailScreen(
      intent: intent, intentParams: params, initialText: text)));""",
        h
    )
    print("  ✅ _startFlow → _openChat (regex)")

# Replace all _startFlow calls with _openChat
# FlowBuilder.buildRoomRenovation() → intent: KoalaIntent.roomRenovation
h = h.replace(
    "_startFlow(FlowBuilder.buildRoomRenovation())",
    "_openChat(intent: KoalaIntent.roomRenovation)"
)
h = h.replace(
    "_startFlow(FlowBuilder.buildBudgetPlan())",
    "_openChat(intent: KoalaIntent.budgetPlan)"
)
h = h.replace(
    "_startFlow(FlowBuilder.buildDesignerMatch())",
    "_openChat(intent: KoalaIntent.designerMatch)"
)
h = h.replace(
    "_startFlow(FlowBuilder.buildColorAdvice())",
    "_openChat(intent: KoalaIntent.colorAdvice)"
)

# Style explore calls: _startFlow(FlowBuilder.buildStyleExplore('Japandi'))
# These need to become: _openChat(intent: KoalaIntent.styleExplore, params: {'style': 'Japandi'})
styles = ['Japandi', 'Modern', 'Skandinav', 'Bohem', 'Minimalist', 'Rustik', 'Klasik', 'Endüstriyel']
for style in styles:
    h = h.replace(
        f"_startFlow(FlowBuilder.buildStyleExplore('{style}'))",
        f"_openChat(intent: KoalaIntent.styleExplore, params: {{'style': '{style}'}})"
    )

# Remove flow_models import if no longer needed
if "FlowBuilder" not in h and "FlowState" not in h:
    h = h.replace("import '../models/flow_models.dart';\n", "")

# Fix _doPick to open chat with photo intent
h = h.replace(
    "_startFlow(FlowBuilder.buildRoomRenovation());",
    "_openChat(intent: KoalaIntent.roomRenovation);"
)

with open(home_path, 'w', encoding='utf-8') as f:
    f.write(h)
print("  ✅ home_screen.dart — all routes go to ChatDetailScreen")

# ═══════════════════════════════════════════════════════════
# 4. VERIFY — print remaining FlowBuilder/GuidedFlow references
# ═══════════════════════════════════════════════════════════
with open(home_path, 'r', encoding='utf-8') as f:
    h2 = f.read()

remaining_flow = []
for i, line in enumerate(h2.split('\n'), 1):
    if 'FlowBuilder' in line or 'GuidedFlow' in line or '_startFlow' in line:
        remaining_flow.append(f"  Line {i}: {line.strip()}")

if remaining_flow:
    print(f"\n  ⚠️  Remaining flow references in home_screen.dart:")
    for r in remaining_flow:
        print(r)
else:
    print("  ✅ No remaining FlowBuilder/GuidedFlow references")

print()
print("=" * 50)
print("  Faz 2 Part A complete!")
print("=" * 50)
print()
print("  Changes:")
print("  🔧 question_chips: handles both 'chips' and 'options' keys")
print("  🎨 image_prompt: card with 'Generate' button → Gemini image gen")
print("  🚫 Unknown cards: show as info text, not raw JSON")
print("  🏠 Home: all buttons → ChatDetailScreen with intent")
print("  🗑️  GuidedFlowScreen removed from routing")
print()
print("  Test: .\\run.ps1")
