#!/usr/bin/env python3
"""Fix compile errors from premium_improvements"""
import os, re

BASE = r"C:\Users\canoz\Egitim-clean\koala"

# ═══════════════════════════════════════════════════════════
# 1. HOME: Fix _DesignerCTA and _FactCard references
# ═══════════════════════════════════════════════════════════
home_path = os.path.join(BASE, "lib", "views", "home_screen.dart")
with open(home_path, 'r', encoding='utf-8') as f:
    h = f.read()

# Find line 167 area — there's still an old _DesignerCTA call
# Replace any remaining _DesignerCTA with _MiniCTA
h = re.sub(
    r"Expanded\(child: _DesignerCTA\(\s*onTap: \(\) => _openChat\(intent: KoalaIntent\.designerMatch\),\s*\)\)",
    "Expanded(child: _MiniCTA(\n                      icon: Icons.person_search_rounded,\n                      title: 'Tasarımcı',\n                      onTap: () { HapticFeedback.lightImpact(); _openChat(intent: KoalaIntent.designerMatch); },\n                    ))",
    h,
    flags=re.DOTALL
)
print("  ✅ _DesignerCTA → _MiniCTA")

# Fix _FactCard references — replace with _RandomFact
h = re.sub(r"_FactCard\([^)]+\)", "_RandomFact(seed: 0)", h, count=1)
h = re.sub(r"_FactCard\([^)]+\)", "_RandomFact(seed: 1)", h, count=1)
print("  ✅ _FactCard → _RandomFact")

# Verify _RandomFact class exists
if "class _RandomFact" not in h:
    print("  ⚠️  _RandomFact missing, adding...")
    RANDOM_FACT = r"""
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
    # Add before _PickBtn or at end
    pick_idx = h.find("class _PickBtn")
    if pick_idx > 0:
        h = h[:pick_idx] + RANDOM_FACT + "\n" + h[pick_idx:]
    else:
        h += RANDOM_FACT

# Remove old _FactCard class if still there
fact_idx = h.find("class _FactCard")
while fact_idx > 0:
    brace = 0; i = fact_idx; started = False; end = len(h)
    while i < len(h):
        if h[i] == '{': brace += 1; started = True
        elif h[i] == '}':
            brace -= 1
            if started and brace == 0: end = i + 1; break
        i += 1
    h = h[:fact_idx] + h[end:]
    fact_idx = h.find("class _FactCard")
    print("  ✅ Old _FactCard class removed")

# Remove old _DesignerCTA class if still there
des_idx = h.find("class _DesignerCTA")
while des_idx > 0:
    brace = 0; i = des_idx; started = False; end = len(h)
    while i < len(h):
        if h[i] == '{': brace += 1; started = True
        elif h[i] == '}':
            brace -= 1
            if started and brace == 0: end = i + 1; break
        i += 1
    h = h[:des_idx] + h[end:]
    des_idx = h.find("class _DesignerCTA")
    print("  ✅ Old _DesignerCTA class removed")

with open(home_path, 'w', encoding='utf-8') as f:
    f.write(h)

# ═══════════════════════════════════════════════════════════
# 2. CHAT: Ensure _ArchitectCTA class exists
# ═══════════════════════════════════════════════════════════
chat_path = os.path.join(BASE, "lib", "views", "chat_detail_screen.dart")
with open(chat_path, 'r', encoding='utf-8') as f:
    c = f.read()

if "class _ArchitectCTA" not in c:
    ARCHITECT = r"""

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
          SizedBox(width: 72, height: 28, child: Stack(children: [
            _dot(0, const Color(0xFFEC4899)),
            _dot(18, const Color(0xFF3B82F6)),
            _dot(36, const Color(0xFF10B981)),
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

  Widget _dot(double left, Color color) => Positioned(left: left, child: Container(
    width: 28, height: 28,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color,
      border: Border.all(color: Colors.white.withOpacity(0.3), width: 2)),
    child: const Icon(Icons.person_rounded, size: 14, color: Colors.white)));
}
"""
    c = c.rstrip() + ARCHITECT
    print("  ✅ _ArchitectCTA added to chat")
else:
    print("  ✅ _ArchitectCTA already exists")

with open(chat_path, 'w', encoding='utf-8') as f:
    f.write(c)

print("\n  Test: .\\run.ps1")
