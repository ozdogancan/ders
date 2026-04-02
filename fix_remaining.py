#!/usr/bin/env python3
import os, re

BASE = r"C:\Users\canoz\Egitim-clean\koala"

# ═══════════════════════════════════════════════════════════
# Fix 1: PollCard _startFlow → _openChat
# ═══════════════════════════════════════════════════════════
home_path = os.path.join(BASE, "lib", "views", "home_screen.dart")
with open(home_path, 'r', encoding='utf-8') as f:
    h = f.read()

# The PollCard passes a dynamic style name: _startFlow(FlowBuilder.buildStyleExplore(s))
h = h.replace(
    "_startFlow(FlowBuilder.buildStyleExplore(s))",
    "_openChat(intent: KoalaIntent.styleExplore, params: {'style': s})"
)

# Also catch any remaining _startFlow calls
h = re.sub(
    r"_startFlow\(FlowBuilder\.buildStyleExplore\((\w+)\)\)",
    r"_openChat(intent: KoalaIntent.styleExplore, params: {'style': \1})",
    h
)

# Remove FlowBuilder/flow_models import if not needed
if "FlowBuilder" not in h and "FlowState" not in h and "flow_models" in h:
    h = h.replace("import '../models/flow_models.dart';\n", "")

with open(home_path, 'w', encoding='utf-8') as f:
    f.write(h)
print("  ✅ PollCard _startFlow fixed")

# Verify no remaining _startFlow
remaining = [l.strip() for l in h.split('\n') if '_startFlow' in l]
if remaining:
    print(f"  ⚠️  Still found: {remaining}")
else:
    print("  ✅ No remaining _startFlow calls")

# ═══════════════════════════════════════════════════════════
# Fix 2: Ensure _ImagePromptCard class is properly placed
# ═══════════════════════════════════════════════════════════
chat_path = os.path.join(BASE, "lib", "views", "chat_detail_screen.dart")
with open(chat_path, 'r', encoding='utf-8') as f:
    c = f.read()

# Check if _ImagePromptCard class exists as a top-level class
if "class _ImagePromptCard extends StatelessWidget" not in c:
    # It might have been inserted inside another class — remove and re-add at end
    
    CARD_CLASS = r'''
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
    # Append at the very end
    c = c.rstrip() + "\n" + CARD_CLASS
    print("  ✅ _ImagePromptCard class added at end of file")
else:
    print("  ✅ _ImagePromptCard class already exists")

with open(chat_path, 'w', encoding='utf-8') as f:
    f.write(c)

print("\n  Test: .\\run.ps1")
