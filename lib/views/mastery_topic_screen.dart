import 'package:flutter/material.dart';

import '../stores/mastery_store.dart';
import 'mastery_learn_screen.dart';

class MasteryTopicScreen extends StatefulWidget {
  const MasteryTopicScreen({super.key, required this.topicId});
  final String topicId;
  @override
  State<MasteryTopicScreen> createState() => _MasteryTopicScreenState();
}

class _MasteryTopicScreenState extends State<MasteryTopicScreen> {
  MasteryTopic? get _topic => MasteryStore.instance.getById(widget.topicId);

  @override
  void initState() {
    super.initState();
    MasteryStore.instance.addListener(_refresh);
  }

  @override
  void dispose() {
    MasteryStore.instance.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() { if (mounted) setState(() {}); }

  Color _levelColor(MasteryLevel l) {
    switch (l) {
      case MasteryLevel.cirak: return const Color(0xFFF59E0B);
      case MasteryLevel.kalfa: return const Color(0xFF6366F1);
      case MasteryLevel.usta: return const Color(0xFF22C55E);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _topic;
    if (t == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Konu bulunamad\u0131')));
    final lc = _levelColor(t.level);
    final isDone = t.status == TopicStatus.completed;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFD),
      body: SafeArea(
        child: CustomScrollView(slivers: [
          // Header
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(children: [
              GestureDetector(onTap: () => Navigator.pop(context),
                child: Container(width: 36, height: 36,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0xFFF1F5F9)),
                  child: const Icon(Icons.arrow_back_rounded, size: 18, color: Color(0xFF475569)))),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                Text('${t.teacherName} \u00b7 ${t.subject}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ])),
            ]))),

          // Progress card
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Container(padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFEEF2F7))),
              child: Column(children: [
                Row(children: [
                  Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(value: t.overallProgress,
                      backgroundColor: const Color(0xFFEEF2F7), valueColor: AlwaysStoppedAnimation(lc), minHeight: 10))),
                  const SizedBox(width: 14),
                  Text('${t.progressPercent}%', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: lc)),
                ]),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  _LevelDot(label: '\u00c7\u0131rak', done: t.level != MasteryLevel.cirak, active: t.level == MasteryLevel.cirak),
                  Container(width: 20, height: 1, color: const Color(0xFFE2E8F0)),
                  _LevelDot(label: 'Kalfa', done: t.level == MasteryLevel.usta, active: t.level == MasteryLevel.kalfa),
                  Container(width: 20, height: 1, color: const Color(0xFFE2E8F0)),
                  _LevelDot(label: 'Usta', done: false, active: t.level == MasteryLevel.usta),
                ]),
              ])))),

          // Phases
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Text('A\u015famalar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.grey.shade800)))),

          SliverList(delegate: SliverChildBuilderDelegate((_, i) {
            final phase = t.phases[i];
            final isLast = i == t.phases.length - 1;
            final phaseColor = phase.status == PhaseStatus.done ? const Color(0xFF22C55E)
              : phase.status == PhaseStatus.active ? const Color(0xFF6366F1) : const Color(0xFFCBD5E1);

            return Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Rail
                SizedBox(width: 40, child: Column(children: [
                  Container(width: 36, height: 36,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
                      gradient: phase.status == PhaseStatus.active
                        ? const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)])
                        : null,
                      color: phase.status != PhaseStatus.active ? phaseColor.withAlpha(phase.status == PhaseStatus.done ? 20 : 15) : null),
                    child: Center(child: phase.status == PhaseStatus.done
                      ? const Icon(Icons.check_rounded, size: 18, color: Color(0xFF22C55E))
                      : Text('${i + 1}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                          color: phase.status == PhaseStatus.active ? Colors.white : phaseColor)))),
                  if (!isLast) Container(width: 2, height: 32, margin: const EdgeInsets.symmetric(vertical: 4),
                    color: phase.status == PhaseStatus.done ? const Color(0xFF22C55E).withAlpha(40) : const Color(0xFFE2E8F0)),
                ])),
                const SizedBox(width: 12),
                // Content
                Expanded(child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: phase.status == PhaseStatus.active
                      ? const Color(0xFF6366F1).withAlpha(30) : const Color(0xFFEEF2F7)),
                    boxShadow: phase.status == PhaseStatus.active
                      ? [BoxShadow(color: const Color(0xFF6366F1).withAlpha(8), blurRadius: 12, offset: const Offset(0, 4))] : null),
                  child: Opacity(opacity: phase.status == PhaseStatus.locked ? 0.45 : 1,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(phase.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                      const SizedBox(height: 2),
                      Text(phase.description, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      const SizedBox(height: 8),
                      if (phase.status == PhaseStatus.done)
                        Text('Tamamland\u0131', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF22C55E)))
                      else if (phase.status == PhaseStatus.active)
                        Text('Devam ediyor \u2014 ${phase.questionsDone}/${phase.questionsTotal}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF6366F1)))
                      else
                        Text('Kilitli', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade400)),
                    ])))),
              ]));
          }, childCount: t.phases.length)),

          // Button
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
            child: SizedBox(width: double.infinity, height: 56,
              child: FilledButton(
                onPressed: isDone ? null : () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => MasteryLearnScreen(topicId: t.id)));
                },
                style: FilledButton.styleFrom(
                  backgroundColor: isDone ? const Color(0xFF22C55E) : const Color(0xFF6366F1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                child: Text(isDone ? 'Ustala\u015ft\u0131n!' : 'Devam Et',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)))))),
        ]),
      ),
    );
  }
}

class _LevelDot extends StatelessWidget {
  const _LevelDot({required this.label, required this.done, required this.active});
  final String label; final bool done; final bool active;

  @override
  Widget build(BuildContext context) {
    final color = done ? const Color(0xFF22C55E) : active ? const Color(0xFF6366F1) : const Color(0xFFCBD5E1);
    return Column(children: [
      Container(width: 10, height: 10,
        decoration: BoxDecoration(shape: BoxShape.circle,
          color: done || active ? color : Colors.transparent,
          border: Border.all(color: color, width: 2))),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    ]);
  }
}
