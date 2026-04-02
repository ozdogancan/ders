#!/usr/bin/env python3
"""
HOME SCREEN IMPROVEMENTS
=========================
1. Son Sohbetler bölümü (Hızlı Başla'dan önce)
2. İlham Al görselleri büyütüldü
3. Trend kartı swatchları büyütüldü + renk isimleri
4. Fact kartlarına soft arka plan rengi
5. Bölümler arası spacing artırıldı
6. "Senin İçin" bölümü eklendi (Daha Fazla yerine)
7. Section başlıklarına "Tümü" linki
8. KoalaLogoPainter boş sınıf temizliği
"""
import os

BASE = r"C:\Users\canoz\Egitim-clean\koala"
path = os.path.join(BASE, "lib", "views", "home_screen.dart")

with open(path, 'r', encoding='utf-8') as f:
    c = f.read()

# ═══════════════════════════════════════════════════════════
# 1. Add "Son Sohbetler" section before Hızlı Başla
# ═══════════════════════════════════════════════════════════
OLD_HIZLI = """              // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
              // SECTION 1: HÄ±zlÄ± BaÅŸla (guided flow'lara yÃ¶nlendir)
              // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
              SliverToBoxAdapter(child: _section('HÄ±zlÄ± BaÅŸla')),"""

NEW_HIZLI = """              // ═══════════════════════════════════════════
              // SECTION 0: Son Sohbetler (chat history)
              // ═══════════════════════════════════════════
              SliverToBoxAdapter(child: _RecentChats(
                onViewAll: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatListScreen())),
                onOpenChat: (id) => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatDetailScreen(chatId: id))))),

              // ═══════════════════════════════════════════
              // SECTION 1: Hızlı Başla
              // ═══════════════════════════════════════════
              SliverToBoxAdapter(child: _section('Hızlı Başla')),"""

if OLD_HIZLI in c:
    c = c.replace(OLD_HIZLI, NEW_HIZLI)
    print("  ✅ Son Sohbetler section added")
else:
    print("  ⚠️  Could not find Hızlı Başla marker")

# ═══════════════════════════════════════════════════════════
# 2. Bigger inspo images (h: 190/150/160/180 → 220/170/180/210)
# ═══════════════════════════════════════════════════════════
c = c.replace("label: 'Japandi Salon', h: 190,", "label: 'Japandi Salon', h: 220,")
c = c.replace("label: 'Modern Mutfak', h: 150,", "label: 'Modern Mutfak', h: 170,")
c = c.replace("label: 'Skandinav Oturma', h: 160,", "label: 'Skandinav Oturma', h: 180,")
c = c.replace("label: 'Bohem Yatak OdasÄ±', h: 180,", "label: 'Bohem Yatak Odası', h: 210,")
print("  ✅ Inspo images bigger")

# ═══════════════════════════════════════════════════════════
# 3. Better section title with "Tümü" link
# ═══════════════════════════════════════════════════════════
OLD_SECTION = """  Widget _section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 24, 18, 8),
    child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
  );"""

NEW_SECTION = """  Widget _section(String title, {VoidCallback? onMore}) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 28, 18, 10),
    child: Row(children: [
      Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1A1D2A))),
      const Spacer(),
      if (onMore != null) GestureDetector(onTap: onMore,
        child: Text('Tümü', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF6C5CE7).withOpacity(0.7)))),
    ]));"""

if OLD_SECTION in c:
    c = c.replace(OLD_SECTION, NEW_SECTION)
    print("  ✅ Section title with 'Tümü' link")

# ═══════════════════════════════════════════════════════════
# 4. Better Trend Card — bigger swatches + color names
# ═══════════════════════════════════════════════════════════
OLD_TREND = """class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: GestureDetector(onTap: onTap,
    child: Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R), color: const Color(0xFFFAF8FF),
        border: Border.all(color: const Color(0xFFF0EDF5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('\\u{1F3A8}  2026 Trend', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF6C5CE7).withOpacity(0.6))),
        const SizedBox(height: 10),
        Row(children: [_sw(const Color(0xFFC4704A)), const SizedBox(width: 5), _sw(const Color(0xFF8B9E6B)), const SizedBox(width: 5), _sw(const Color(0xFFE8D5C4))]),
        const SizedBox(height: 8),
        Text('Odana uygula \\u{2192}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF6C5CE7).withOpacity(0.7))),
      ]))));
  Widget _sw(Color c) => Expanded(child: Container(height: 24, decoration: BoxDecoration(borderRadius: BorderRadius.circular(7), color: c)));
}"""

NEW_TREND = r"""class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: GestureDetector(onTap: onTap,
    child: Container(padding: const EdgeInsets.all(16),
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
          _colorSwatch(const Color(0xFFC4704A), 'Terracotta'),
          const SizedBox(width: 6),
          _colorSwatch(const Color(0xFF8B9E6B), 'Sage'),
          const SizedBox(width: 6),
          _colorSwatch(const Color(0xFFE8D5C4), 'Cream'),
        ]),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: const Color(0xFFF0ECFF)),
          child: const Center(child: Text('Odana uygula →', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF6C5CE7))))),
      ]))));

  Widget _colorSwatch(Color c, String name) => Expanded(child: Column(children: [
    Container(height: 36, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: c)),
    const SizedBox(height: 4),
    Text(name, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
  ]));
}"""

if OLD_TREND in c:
    c = c.replace(OLD_TREND, NEW_TREND)
    print("  ✅ Trend card: bigger swatches + color names + CTA button")
else:
    print("  ⚠️  Could not find TrendCard")

# ═══════════════════════════════════════════════════════════
# 5. Fact cards with soft colored backgrounds
# ═══════════════════════════════════════════════════════════
OLD_FACT = """class _FactCard extends StatelessWidget {
  const _FactCard(this.emoji, this.fact);
  final String emoji, fact;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R),
      color: const Color(0xFFFAF8FF), border: Border.all(color: const Color(0xFFF0EDF5))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Text(emoji, style: const TextStyle(fontSize: 16)), const SizedBox(width: 6),
        Text('Biliyor muydun?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade400))]),
      const SizedBox(height: 8),
      Text(fact, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1D2A), height: 1.4)),
    ])));
}"""

NEW_FACT = r"""class _FactCard extends StatelessWidget {
  const _FactCard(this.emoji, this.fact, {this.bgColor});
  final String emoji, fact;
  final Color? bgColor;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R),
      color: bgColor ?? Colors.white, border: Border.all(color: const Color(0xFFF0EDF5))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Text(emoji, style: const TextStyle(fontSize: 16)), const SizedBox(width: 6),
        Text('Biliyor muydun?', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey.shade400, letterSpacing: 0.5))]),
      const SizedBox(height: 8),
      Text(fact, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1D2A), height: 1.4)),
    ])));
}"""

if OLD_FACT in c:
    c = c.replace(OLD_FACT, NEW_FACT)
    print("  ✅ FactCard: optional bgColor + cleaner label")
    # Update fact card usages with soft colors
    c = c.replace(
        "_FactCard('\\u{1F33F}', 'Bitkiler odadaki\\nstresi %37 azaltÄ±yor')",
        "_FactCard('\\u{1F33F}', 'Bitkiler odadaki\\nstresi %37 azaltÄ±yor', bgColor: const Color(0xFFF0FDF4))")
    c = c.replace(
        "_FactCard('\\u{2728}', 'AÃ§Ä±k renkli perdeler\\nodayÄ± %30 geniÅŸ gÃ¶sterir')",
        "_FactCard('\\u{2728}', 'AÃ§Ä±k renkli perdeler\\nodayÄ± %30 geniÅŸ gÃ¶sterir', bgColor: const Color(0xFFFEF3C7))")

# ═══════════════════════════════════════════════════════════
# 6. Add "Senin İçin" section after Keşfet
# ═══════════════════════════════════════════════════════════
OLD_END = """              const SliverToBoxAdapter(child: SizedBox(height: 24)),"""

NEW_END = """              // ═══════════════════════════════════════════
              // SECTION 4: Senin İçin (personalized)
              // ═══════════════════════════════════════════
              SliverToBoxAdapter(child: _section('Senin İçin')),
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(children: [
                  // Before/After CTA
                  GestureDetector(
                    onTap: () => _openChat(intent: KoalaIntent.beforeAfter),
                    child: Container(padding: const EdgeInsets.all(16), margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R),
                        gradient: const LinearGradient(colors: [Color(0xFFF0ECFF), Color(0xFFE8F5E9)])),
                      child: Row(children: [
                        Container(width: 44, height: 44,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.white.withOpacity(0.7)),
                          child: const Icon(Icons.compare_rounded, size: 22, color: Color(0xFF6C5CE7))),
                        const SizedBox(width: 14),
                        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Önce → Sonra', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A))),
                          SizedBox(height: 2),
                          Text('Gerçek dönüşüm hikayeleri', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                        ])),
                        const Icon(Icons.arrow_forward_rounded, size: 18, color: Color(0xFF6C5CE7)),
                      ]))),
                  // Quick style quiz
                  GestureDetector(
                    onTap: () => _openChat(text: 'Stil testini başlat'),
                    child: Container(padding: const EdgeInsets.all(16), margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(_R), color: Colors.white,
                        border: Border.all(color: const Color(0xFFEDEAF5))),
                      child: Row(children: [
                        Container(width: 44, height: 44,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0xFFFFF1F2)),
                          child: const Icon(Icons.quiz_rounded, size: 22, color: Color(0xFFEC4899))),
                        const SizedBox(width: 14),
                        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Stil Testini Çöz', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1D2A))),
                          SizedBox(height: 2),
                          Text('Tarzını 30 saniyede öğren', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                        ])),
                        const Icon(Icons.arrow_forward_rounded, size: 18, color: Color(0xFFEC4899)),
                      ]))),
                ]))),

              const SliverToBoxAdapter(child: SizedBox(height: 32)),"""

if OLD_END in c:
    c = c.replace(OLD_END, NEW_END)
    print("  ✅ 'Senin İçin' section added")

# ═══════════════════════════════════════════════════════════
# 7. Clean up empty KoalaLogoPainter section
# ═══════════════════════════════════════════════════════════
c = c.replace("""// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// KOALA LOGO PAINTER â€" Line-art koala face
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•



""", "")
print("  ✅ Empty KoalaLogoPainter removed")

# ═══════════════════════════════════════════════════════════
# 8. Add import for ChatListScreen and ChatDetailScreen if missing
# ═══════════════════════════════════════════════════════════
if "chat_list_screen.dart" not in c:
    c = c.replace("import 'chat_detail_screen.dart';", "import 'chat_detail_screen.dart';\nimport 'chat_list_screen.dart';")
if "chat_persistence.dart" not in c:
    c = c.replace("import '../services/koala_ai_service.dart';", "import '../services/koala_ai_service.dart';\nimport '../services/chat_persistence.dart';")

# ═══════════════════════════════════════════════════════════
# 9. Add _RecentChats widget at end of file
# ═══════════════════════════════════════════════════════════
RECENT_CHATS_WIDGET = r"""

class _RecentChats extends StatefulWidget {
  const _RecentChats({required this.onViewAll, required this.onOpenChat});
  final VoidCallback onViewAll;
  final void Function(String) onOpenChat;
  @override
  State<_RecentChats> createState() => _RecentChatsState();
}

class _RecentChatsState extends State<_RecentChats> {
  List<ChatSummary> _chats = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final chats = await ChatPersistence.loadConversations();
    if (mounted) setState(() => _chats = chats.take(3).toList());
  }

  @override
  Widget build(BuildContext context) {
    if (_chats.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Son Sohbetler', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1A1D2A))),
          const Spacer(),
          GestureDetector(onTap: widget.onViewAll,
            child: Text('Tümü', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF6C5CE7).withOpacity(0.7)))),
        ]),
        const SizedBox(height: 10),
        ..._chats.map((chat) => GestureDetector(
          onTap: () => widget.onOpenChat(chat.id),
          child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Colors.white,
              border: Border.all(color: const Color(0xFFF0EDF5))),
            child: Row(children: [
              Container(width: 36, height: 36,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: const Color(0xFFF0ECFF)),
                child: const Icon(Icons.chat_rounded, size: 16, color: Color(0xFF6C5CE7))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(chat.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1D2A)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                if (chat.lastMessage != null) Text(chat.lastMessage!,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey.shade300),
            ])))),
      ]));
  }
}
"""

if '_RecentChats' not in c:
    c = c.rstrip() + RECENT_CHATS_WIDGET
    print("  ✅ _RecentChats widget added")

with open(path, 'w', encoding='utf-8') as f:
    f.write(c)

print()
print("=" * 50)
print("  Home improvements done!")
print("=" * 50)
print()
print("  ✅ Son Sohbetler: last 3 chats on home (hidden if empty)")
print("  ✅ İlham Al: bigger images (220/170/180/210)")
print("  ✅ Trend Card: bigger swatches + color names + CTA")
print("  ✅ Fact Cards: soft green/yellow backgrounds")
print("  ✅ Senin İçin: Önce→Sonra + Stil Testi cards")
print("  ✅ Section titles: bolder + 'Tümü' link")
print("  ✅ More spacing between sections")
print("  ✅ Dead KoalaLogoPainter removed")
print()
print("  Test: .\\run.ps1")
