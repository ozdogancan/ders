import 'package:flutter/material.dart';

import '../stores/mastery_store.dart';
import '../widgets/koala_logo.dart';
import 'mastery_topic_screen.dart';
import 'mastery_new_topic_screen.dart';

class MasteryTab extends StatefulWidget {
  const MasteryTab({super.key});
  @override
  State<MasteryTab> createState() => _MasteryTabState();
}

class _MasteryTabState extends State<MasteryTab> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String? _fSubject;
  String? _fLevel;
  String? _fStatus;

  @override
  void initState() {
    super.initState();
    MasteryStore.instance.addListener(_refresh);
  }

  @override
  void dispose() {
    MasteryStore.instance.removeListener(_refresh);
    _search.dispose();
    super.dispose();
  }

  void _refresh() { if (mounted) setState(() {}); }

  List<MasteryTopic> _filtered() {
    var list = MasteryStore.instance.topics.toList();
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((t) => t.title.toLowerCase().contains(q) || t.subject.toLowerCase().contains(q)).toList();
    }
    if (_fSubject != null) list = list.where((t) => t.subject == _fSubject).toList();
    if (_fLevel != null) {
      list = list.where((t) {
        switch (_fLevel) {
          case 'cirak': return t.level == MasteryLevel.cirak;
          case 'kalfa': return t.level == MasteryLevel.kalfa;
          case 'usta': return t.level == MasteryLevel.usta;
          default: return true;
        }
      }).toList();
    }
    if (_fStatus == 'inProgress') list = list.where((t) => t.status == TopicStatus.inProgress).toList();
    else if (_fStatus == 'completed') list = list.where((t) => t.status == TopicStatus.completed).toList();
    return list;
  }

  void _showFilter() {
    final subjects = MasteryStore.instance.topics.map((t) => t.subject).toSet().toList();
    showModalBottomSheet(context: context, showDragHandle: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => SafeArea(
        child: Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('Filtrele', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
              const Spacer(),
              if (_fSubject != null || _fLevel != null || _fStatus != null)
                TextButton(onPressed: () { setState(() { _fSubject = null; _fLevel = null; _fStatus = null; }); Navigator.pop(ctx); },
                  child: const Text('Temizle', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 20),
            _sec('SEV\u0130YE', [
              _fc('T\u00fcm\u00fc', _fLevel == null, () { ss(() {}); setState(() => _fLevel = null); }),
              _fc('\u00c7\u0131rak', _fLevel == 'cirak', () { ss(() {}); setState(() => _fLevel = 'cirak'); }),
              _fc('Kalfa', _fLevel == 'kalfa', () { ss(() {}); setState(() => _fLevel = 'kalfa'); }),
              _fc('Usta', _fLevel == 'usta', () { ss(() {}); setState(() => _fLevel = 'usta'); }),
            ]),
            const SizedBox(height: 16),
            _sec('DURUM', [
              _fc('T\u00fcm\u00fc', _fStatus == null, () { ss(() {}); setState(() => _fStatus = null); }),
              _fc('Devam Ediyor', _fStatus == 'inProgress', () { ss(() {}); setState(() => _fStatus = 'inProgress'); }),
              _fc('Tamamland\u0131', _fStatus == 'completed', () { ss(() {}); setState(() => _fStatus = 'completed'); }),
            ]),
            if (subjects.isNotEmpty) ...[
              const SizedBox(height: 16),
              _sec('DERS', [
                _fc('T\u00fcm\u00fc', _fSubject == null, () { ss(() {}); setState(() => _fSubject = null); }),
                ...subjects.map((s) => _fc(s, _fSubject == s, () { ss(() {}); setState(() => _fSubject = s); })),
              ]),
            ],
            const SizedBox(height: 28),
            SizedBox(width: double.infinity, height: 50,
              child: FilledButton(onPressed: () => Navigator.pop(ctx),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6366F1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: const Text('Uygula', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
          ]))))));
  }

  Widget _sec(String t, List<Widget> c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey.shade400, letterSpacing: 1)),
    const SizedBox(height: 10), Wrap(spacing: 8, runSpacing: 8, children: c)]);

  Widget _fc(String l, bool on, VoidCallback t) => GestureDetector(onTap: t,
    child: AnimatedContainer(duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(color: on ? const Color(0xFF6366F1) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12), border: Border.all(color: on ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0))),
      child: Text(l, style: TextStyle(color: on ? Colors.white : const Color(0xFF475569), fontWeight: FontWeight.w600, fontSize: 13))));

  Color _levelColor(MasteryLevel l) {
    switch (l) {
      case MasteryLevel.cirak: return const Color(0xFFF59E0B);
      case MasteryLevel.kalfa: return const Color(0xFF6366F1);
      case MasteryLevel.usta: return const Color(0xFF22C55E);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered();
    final store = MasteryStore.instance;
    final hasFilter = _fSubject != null || _fLevel != null || _fStatus != null;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFD),
      body: SafeArea(
        child: CustomScrollView(slivers: [
          // Header — same language as Sorularım (KoalaLogo + subtitle)
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const KoalaLogo(size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ustala\u015f',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -0.8)),
                      Text('\u00d6\u011frenmenin en tatl\u0131 yolu',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                // Stats pills (inline, matching Sorularım credit badge style)
                if (store.topics.isNotEmpty)
                  Row(children: [
                    _HeaderPill(
                      icon: Icons.auto_awesome_rounded,
                      label: '${store.completedCount}',
                      color: const Color(0xFF22C55E)),
                    const SizedBox(width: 6),
                    _HeaderPill(
                      icon: Icons.menu_book_rounded,
                      label: '${store.topics.length}',
                      color: const Color(0xFF6366F1)),
                  ]),
              ],
            ),
          )),

          // Hero CTA Card — professional gradient, no emoji
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF6366F1), Color(0xFF7C3AED), Color(0xFFA855F7)]),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withAlpha(40), blurRadius: 24, offset: const Offset(0, 8))]),
              child: Row(children: [
                // Gradient icon container (no emoji)
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.white.withAlpha(25),
                    border: Border.all(color: Colors.white.withAlpha(40))),
                  child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 24)),
                const SizedBox(width: 16),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Yeni konu ba\u015flat',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                    const SizedBox(height: 2),
                    Text('Foto \u00e7ek, y\u00fckle veya yaz',
                      style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(190))),
                  ],
                )),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MasteryNewTopicScreen())),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 8)]),
                    child: const Text('Ba\u015fla',
                      style: TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.w800, fontSize: 13))),
                ),
              ])),
          )),

          // Search — identical to Sorularım
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(children: [
              Expanded(child: Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFEEF2F7)),
                  boxShadow: [BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 8, offset: const Offset(0, 2))]),
                child: Row(children: [
                  Icon(Icons.search_rounded, size: 20, color: Colors.grey.shade400),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(
                    controller: _search,
                    onChanged: (v) => setState(() => _query = v),
                    style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
                    decoration: InputDecoration(
                      hintText: 'Konular\u0131nda ara...',
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                      border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero, isDense: true))),
                  if (_query.isNotEmpty)
                    GestureDetector(
                      onTap: () { _search.clear(); setState(() => _query = ''); },
                      child: Icon(Icons.close_rounded, size: 18, color: Colors.grey.shade400)),
                ]))),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _showFilter,
                child: Container(
                  width: 50, height: 50,
                  decoration: BoxDecoration(
                    color: hasFilter ? const Color(0xFF6366F1) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: hasFilter ? const Color(0xFF6366F1) : const Color(0xFFEEF2F7)),
                    boxShadow: [BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 8, offset: const Offset(0, 2))]),
                  child: Icon(Icons.tune_rounded, size: 20, color: hasFilter ? Colors.white : Colors.grey.shade500))),
            ]))),

          // Section header
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Row(children: [
              Text('Konular\u0131n',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
              const Spacer(),
              if (filtered.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withAlpha(10),
                    borderRadius: BorderRadius.circular(99)),
                  child: Text('${filtered.length}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF6366F1)))),
            ]))),

          // Empty states
          if (filtered.isEmpty && store.topics.isEmpty)
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              child: Column(children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [const Color(0xFF6366F1).withAlpha(12), const Color(0xFF8B5CF6).withAlpha(8)])),
                  child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF6366F1), size: 34)),
                const SizedBox(height: 18),
                const Text('Hen\u00fcz konu yok',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                const SizedBox(height: 8),
                Text('Bir konu se\u00e7 ve ustala\u015fmaya ba\u015fla', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
              ])))
          else if (filtered.isEmpty)
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              child: Column(children: [
                Icon(Icons.filter_list_off_rounded, color: Colors.grey.shade300, size: 40),
                const SizedBox(height: 12),
                const Text('Sonu\u00e7 bulunamad\u0131',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
              ])))
          else
            SliverList(delegate: SliverChildBuilderDelegate((_, i) {
              final t = filtered[i];
              final lc = _levelColor(t.level);
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: _TopicCard(
                  topic: t, levelColor: lc,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MasteryTopicScreen(topicId: t.id)))));
            }, childCount: filtered.length)),

          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════
// HEADER PILL (matches Sorularım credit badge)
// ═══════════════════════════════════════════

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════
// TOPIC CARD (same design language as Sorularım question cards)
// ═══════════════════════════════════════════

class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.topic, required this.levelColor, required this.onTap});
  final MasteryTopic topic;
  final Color levelColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDone = topic.status == TopicStatus.completed;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFEEF2F7)),
            boxShadow: [BoxShadow(color: levelColor.withAlpha(8), blurRadius: 16, offset: const Offset(0, 4))]),
          child: Row(children: [
            // Gradient icon (professional, no emoji)
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [levelColor.withAlpha(20), levelColor.withAlpha(8)])),
              child: Icon(
                isDone ? Icons.workspace_premium_rounded : Icons.menu_book_rounded,
                color: levelColor, size: 24)),
            const SizedBox(width: 16),
            // Info
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(topic.title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                const SizedBox(height: 3),
                Text('${topic.teacherName} \u00b7 ${topic.subject}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: topic.overallProgress,
                    backgroundColor: const Color(0xFFEEF2F7),
                    valueColor: AlwaysStoppedAnimation(levelColor),
                    minHeight: 5)),
                const SizedBox(height: 6),
                // Level + streak
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: levelColor.withAlpha(15),
                      borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      isDone ? 'Ustala\u015ft\u0131n' : topic.levelLabel,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: levelColor))),
                  if (topic.streak > 1) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFFF6B6B), Color(0xFFEE5A24)]),
                        borderRadius: BorderRadius.circular(8)),
                      child: Text('${topic.streak} seri',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white))),
                  ],
                ]),
              ],
            )),
            // Percentage
            Text('${topic.progressPercent}%',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: levelColor)),
          ])),
      ),
    );
  }
}
