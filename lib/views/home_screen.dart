import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/credit_service.dart';
import '../stores/question_store.dart';
import '../widgets/koala_logo.dart';
import 'chat_screen.dart';
import 'question_share_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final CreditService _creditService = CreditService();
  String _search = '';
  String? _fSubject;
  String? _fDate;
  String? _fStatus;
  int _visCount = 15;
  int _credits = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    QuestionStore.instance.addListener(_onStore);
    _scrollCtrl.addListener(_onScroll);
    _loadCredits();
    _initLoad();
  }

  @override
  void dispose() {
    QuestionStore.instance.removeListener(_onStore);
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  final Set<String> _notified = {};

  Future<void> _initLoad() async {
    setState(() => _isLoading = true);
    await QuestionStore.instance.loadFromSupabase(force: true);
    for (final q in QuestionStore.instance.questions) {
      _notified.add(q.id);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadCredits() async {
    final c = await _creditService.getCredits();
    if (mounted) setState(() => _credits = c);
  }

  void _onStore() {
    if (!mounted) return;
    _loadCredits();
    setState(() {});
    if (_isLoading) return;
    for (final q in QuestionStore.instance.questions) {
      if (q.status == QStatus.solved && q.answer != null && !_notified.contains(q.id)) {
        _notified.add(q.id);
        _toast(q);
      }
    }
  }
  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 100) {
      final f = _filtered();
      if (_visCount < f.length) setState(() => _visCount += 15);
    }
  }

  void _toast(LocalQuestion q) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating, backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16), duration: const Duration(seconds: 2),
      content: Row(children: [
        Container(width: 26, height: 26, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF22C55E).withAlpha(30)),
          child: const Icon(Icons.check_rounded, color: Color(0xFF22C55E), size: 14)),
        const SizedBox(width: 10),
        Expanded(child: Text('${q.subject} sorun çözüldü!',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14))),
      ]),
      action: SnackBarAction(label: 'Gör', textColor: const Color(0xFF818CF8),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(questionId: q.id))))));
  }

  List<LocalQuestion> _filtered() {
    var list = QuestionStore.instance.questions.toList();
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((i) => i.subject.toLowerCase().contains(q) || (i.answer ?? '').toLowerCase().contains(q)).toList();
    }
    if (_fSubject != null) list = list.where((i) => i.subject == _fSubject).toList();
    if (_fStatus == 'solving') list = list.where((i) => i.status == QStatus.solving).toList();
    else if (_fStatus == 'solved') list = list.where((i) => i.status == QStatus.solved).toList();
    if (_fDate != null) {
      final now = DateTime.now(); final today = DateTime(now.year, now.month, now.day);
      list = list.where((i) {
        switch (_fDate) {
          case 'today': return i.createdAt.isAfter(today);
          case 'yesterday': return i.createdAt.isAfter(today.subtract(const Duration(days: 1))) && i.createdAt.isBefore(today);
          case '7days': return i.createdAt.isAfter(today.subtract(const Duration(days: 7)));
          case '30days': return i.createdAt.isAfter(today.subtract(const Duration(days: 30)));
          default: return true;
        }
      }).toList();
    }
    return list;
  }

  void _del(LocalQuestion q) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Soruyu sil', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      content: const Text('Bu soru ve çözümü silinecek.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
        FilledButton(onPressed: () { QuestionStore.instance.remove(q.id); Navigator.pop(ctx); ScaffoldMessenger.of(context).clearSnackBars(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, backgroundColor: const Color(0xFF1E293B), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), margin: const EdgeInsets.fromLTRB(16, 0, 16, 16), duration: const Duration(seconds: 2), content: const Row(children: [Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18), SizedBox(width: 10), Text('Soru silindi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14))]))); Future.delayed(const Duration(seconds: 2), () { if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar(); }); },
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)), child: const Text('Sil')),
      ]));
  }

  void _showFilter() {
    final subjects = QuestionStore.instance.questions.map((q) => q.subject).toSet().toList();
    showModalBottomSheet(context: context, showDragHandle: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => SafeArea(
        child: Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('Filtrele', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
              const Spacer(),
              if (_fSubject != null || _fDate != null || _fStatus != null)
                TextButton(onPressed: () { setState(() { _fSubject = null; _fDate = null; _fStatus = null; }); Navigator.pop(ctx); },
                  child: const Text('Temizle', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 20),
            _sec('DURUM', [
              _chip('Tümü', _fStatus == null, () { ss(() {}); setState(() => _fStatus = null); }),
              _chip('Çözüldü', _fStatus == 'solved', () { ss(() {}); setState(() => _fStatus = 'solved'); }),
              _chip('Çözülüyor', _fStatus == 'solving', () { ss(() {}); setState(() => _fStatus = 'solving'); }),
            ]),
            if (subjects.isNotEmpty) ...[const SizedBox(height: 18),
              _sec('DERS', [
                _chip('Tümü', _fSubject == null, () { ss(() {}); setState(() => _fSubject = null); }),
                ...subjects.map((s) => _chip(s, _fSubject == s, () { ss(() {}); setState(() => _fSubject = s); })),
              ])],
            const SizedBox(height: 18),
            _sec('TARİH', [
              _chip('Tümü', _fDate == null, () { ss(() {}); setState(() => _fDate = null); }),
              _chip('Bugün', _fDate == 'today', () { ss(() {}); setState(() => _fDate = 'today'); }),
              _chip('Dün', _fDate == 'yesterday', () { ss(() {}); setState(() => _fDate = 'yesterday'); }),
              _chip('Son 7 gün', _fDate == '7days', () { ss(() {}); setState(() => _fDate = '7days'); }),
              _chip('Son 30 gün', _fDate == '30days', () { ss(() {}); setState(() => _fDate = '30days'); }),
            ]),
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

  Widget _chip(String l, bool on, VoidCallback t) => GestureDetector(onTap: t,
    child: AnimatedContainer(duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(color: on ? const Color(0xFF6366F1) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12), border: Border.all(color: on ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0))),
      child: Text(l, style: TextStyle(color: on ? Colors.white : const Color(0xFF475569), fontWeight: FontWeight.w600, fontSize: 13))));

  Color _sc(String s) {
    final l = s.toLowerCase();
    if (l.contains('mat')) return const Color(0xFF6366F1);
    if (l.contains('geo')) return const Color(0xFF8B5CF6);
    if (l.contains('fiz')) return const Color(0xFFEC4899);
    if (l.contains('kim')) return const Color(0xFF14B8A6);
    if (l.contains('bio')) return const Color(0xFF22C55E);
    if (l.contains('ede') || l.contains('turk')) return const Color(0xFFF59E0B);
    if (l.contains('tar')) return const Color(0xFFEF4444);
    return const Color(0xFF6366F1);
  }

  bool get _isWide => MediaQuery.of(context).size.width > 700;

  @override
  Widget build(BuildContext context) {
    final filt = _filtered();
    final vis = filt.take(_visCount).toList();
    final hasF = _fSubject != null || _fDate != null || _fStatus != null;
    final wide = _isWide;
    final screenW = MediaQuery.of(context).size.width;
    // Content padding scales with screen
    final hPad = wide ? (screenW * 0.06).clamp(24.0, 80.0) : 20.0;

    return Scaffold(backgroundColor: wide ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
      body: SafeArea(child: CustomScrollView(controller: _scrollCtrl, slivers: [
        // ── HEADER (web: navbar style)
        SliverToBoxAdapter(child: Container(
          padding: EdgeInsets.fromLTRB(hPad, wide ? 16 : 14, hPad, wide ? 16 : 0),
          decoration: wide ? BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: const Color(0xFFE2E8F0).withAlpha(80))),
            boxShadow: [BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 8, offset: const Offset(0, 2))],
          ) : null,
          child: Row(children: [
            KoalaLogo(size: wide ? 36 : 40),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Koala', style: TextStyle(fontSize: wide ? 20 : 22, fontWeight: FontWeight.w900, color: const Color(0xFF1E293B), letterSpacing: -0.5)),
              if (!wide) Text('Öğrenmenin en tatlı yolu', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
            ]),
            if (wide) ...[
              const SizedBox(width: 32),
              // Inline search for web
              Expanded(child: Container(
                height: 44,
                constraints: const BoxConstraints(maxWidth: 480),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE8ECF4))),
                child: Row(children: [
                  Icon(Icons.search_rounded, size: 18, color: Colors.grey.shade400),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: _searchCtrl, onChanged: (v) => setState(() => _search = v),
                    style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
                    decoration: InputDecoration(hintText: 'Sorularında ara...', hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                      border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero, isDense: true))),
                  if (_search.isNotEmpty)
                    GestureDetector(onTap: () { _searchCtrl.clear(); setState(() => _search = ''); },
                      child: Icon(Icons.close_rounded, size: 16, color: Colors.grey.shade400)),
                ]))),
              const SizedBox(width: 16),
            ] else
              const Spacer(),
            // Soru Sor button (web only, inline)
            if (wide) ...[
              GestureDetector(
                onTap: () async { await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuestionShareScreen())); _loadCredits(); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withAlpha(30), blurRadius: 8, offset: const Offset(0, 3))]),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text('Soru Sor', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
            ],
            // Credits
            Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [const Color(0xFF6366F1).withAlpha(15), const Color(0xFF8B5CF6).withAlpha(10)]),
                borderRadius: BorderRadius.circular(99), border: Border.all(color: const Color(0xFF6366F1).withAlpha(20))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFF6366F1)),
                const SizedBox(width: 4),
                Text('$_credits', style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.w800, fontSize: 14)),
              ])),
            const SizedBox(width: 10),
            // Profile
            GestureDetector(
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
                _loadCredits();
              },
              child: Container(
                width: 38, height: 38,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)])),
                child: const Icon(Icons.person_rounded, color: Colors.white, size: 18),
              ),
            ),
          ]))),

        // ── SEARCH (mobile only)
        if (!wide)
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(children: [
              Expanded(child: Container(height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE8ECF4)),
                  boxShadow: [BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 8, offset: const Offset(0, 2))]),
                child: Row(children: [
                  Icon(Icons.search_rounded, size: 20, color: Colors.grey.shade400),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: _searchCtrl, onChanged: (v) => setState(() => _search = v),
                    style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
                    decoration: InputDecoration(hintText: 'Sorularında ara...', hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                      border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero, isDense: true))),
                  if (_search.isNotEmpty)
                    GestureDetector(onTap: () { _searchCtrl.clear(); setState(() => _search = ''); },
                      child: Icon(Icons.close_rounded, size: 18, color: Colors.grey.shade400)),
                ]))),
              const SizedBox(width: 10),
              GestureDetector(onTap: _showFilter,
                child: Container(width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: hasF ? const Color(0xFF6366F1) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: hasF ? const Color(0xFF6366F1) : const Color(0xFFE8ECF4)),
                    boxShadow: [BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 8, offset: const Offset(0, 2))]),
                  child: Icon(Icons.tune_rounded, size: 20, color: hasF ? Colors.white : Colors.grey.shade500))),
            ]))),

        // LOADING SKELETON
        if (_isLoading)
          SliverToBoxAdapter(child: Padding(
            padding: EdgeInsets.fromLTRB(wide ? hPad : 20, 8, wide ? hPad : 20, 0),
            child: Column(children: List.generate(3, (i) =>
              _ShimmerCard(delay: i * 150)))))
        else
        // ── WELCOME (no questions)
        if (vis.isEmpty && !hasF && _search.isEmpty)
          SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(hPad, wide ? 60 : 30, hPad, 0),
            child: wide
              // Web: horizontal layout
              ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const KoalaHero(size: 160),
                  const SizedBox(width: 40),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Merhaba!', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
                    const SizedBox(height: 10),
                    Text('Fotoğraf çek, Koala sana öğretsin.\nHer soruyu adım adım anlatırım.',
                      style: TextStyle(fontSize: 16, color: Colors.grey.shade500, height: 1.6)),
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: () async { await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuestionShareScreen())); _loadCredits(); },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withAlpha(40), blurRadius: 16, offset: const Offset(0, 6))]),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.camera_alt_rounded, color: Colors.white, size: 20),
                          SizedBox(width: 10),
                          Text('İlk Sorunu Sor', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                        ]),
                      ),
                    ),
                  ]),
                ])
              // Mobile: vertical layout (same as before)
              : Column(children: [
                  const KoalaHero(size: 140),
                  const SizedBox(height: 20),
                  const Text('Merhaba!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
                  const SizedBox(height: 8),
                  Text('Fotoğraf çek, Koala sana öğretsin.\nHer soruyu adım adım anlatırım.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Colors.grey.shade500, height: 1.5)),
                ])))
        else ...[
          // ── SECTION HEADER + FILTER (web: inline filter chips)
          SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(hPad, wide ? 24 : 22, hPad, wide ? 16 : 10),
            child: Row(children: [
              Text('Soruların', style: TextStyle(fontSize: wide ? 20 : 16, fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
              const SizedBox(width: 10),
              if (filt.isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFF6366F1).withAlpha(10), borderRadius: BorderRadius.circular(99)),
                child: Text('${filt.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF6366F1)))),
              const Spacer(),
              // Filter button (web only)
              if (wide) GestureDetector(onTap: _showFilter,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: hasF ? const Color(0xFF6366F1) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: hasF ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.tune_rounded, size: 16, color: hasF ? Colors.white : Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Text('Filtre', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: hasF ? Colors.white : Colors.grey.shade500)),
                  ]),
                )),
            ]))),

          // ── EMPTY FILTER
          if (vis.isEmpty)
            SliverToBoxAdapter(child: Container(padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              child: Column(children: [
                Icon(Icons.filter_list_off_rounded, color: Colors.grey.shade300, size: 40),
                const SizedBox(height: 12),
                const Text('Sonuç bulunamadı', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                const SizedBox(height: 6),
                Text('Farklı filtre dene', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              ])))
          else if (wide)
            SliverList(delegate: SliverChildBuilderDelegate((_, i) {
              final q = vis[i];
              return Padding(padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 12),
                child: _Tile(q: q, c: _sc(q.subject), wide: true,
                  tap: () async { await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(questionId: q.id))); _loadCredits(); },
                  del: () => _del(q)));
            }, childCount: vis.length))
          else
            // ── MOBILE: list (same as before)
            SliverList(delegate: SliverChildBuilderDelegate((_, i) {
              final q = vis[i];
              return Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: _Tile(q: q, c: _sc(q.subject), wide: false,
                  tap: () async { await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(questionId: q.id))); _loadCredits(); },
                  del: () => _del(q)));
            }, childCount: vis.length)),
        ],

        if (vis.length < filt.length)
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(20),
            child: Center(child: SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey.shade300))))),

        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ])),
      // FAB only on mobile
      floatingActionButton: wide ? null : FloatingActionButton.extended(
        onPressed: () async { await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuestionShareScreen())); _loadCredits(); },
        backgroundColor: const Color(0xFF6366F1), elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 20),
        label: const Text('Soru Sor', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))));
  }
}

// ═══════════════════════════════════════════
// QUESTION TILE (supports both mobile list + web grid)
// ═══════════════════════════════════════════

class _Tile extends StatelessWidget {
  const _Tile({required this.q, required this.c, required this.tap, required this.del, this.wide = false});
  final LocalQuestion q; final Color c; final VoidCallback tap; final VoidCallback del; final bool wide;

  @override
  Widget build(BuildContext context) {
    final solving = q.status == QStatus.solving;

    return Dismissible(key: ValueKey(q.id), direction: wide ? DismissDirection.none : DismissDirection.endToStart,
      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(color: const Color(0xFFEF4444).withAlpha(12), borderRadius: BorderRadius.circular(20)),
        child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 22)),
      confirmDismiss: (_) async { del(); return false; },
      child: Material(color: Colors.transparent,
        child: InkWell(onTap: tap, borderRadius: BorderRadius.circular(20),
          hoverColor: const Color(0xFF6366F1).withAlpha(6),
          child: Container(padding: EdgeInsets.all(wide ? 18 : 16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFEEF2F7)),
              boxShadow: [BoxShadow(color: c.withAlpha(6), blurRadius: 12, offset: const Offset(0, 3))]),
            child: Row(children: [
              Container(width: wide ? 52 : 56, height: wide ? 52 : 56,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.withAlpha(12), c.withAlpha(6)])),
                child: ClipRRect(borderRadius: BorderRadius.circular(16),
                  child: Image.memory(q.imageBytes, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(Icons.image_rounded, color: c.withAlpha(60), size: 24)))),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Row(children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: c.withAlpha(12), borderRadius: BorderRadius.circular(8)),
                    child: Text(q.subject, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700))),
                  const SizedBox(width: 6),
                  if (solving) _B(l: 'Çözülüyor', c: Colors.amber.shade700, spin: true)
                  else const _B(l: 'Çözüldü', c: Color(0xFF22C55E), ic: Icons.check_circle_rounded),
                  const Spacer(),
                  Text(_ago(q.createdAt), style: TextStyle(color: Colors.grey.shade400, fontSize: 10)),
                ]),
                const SizedBox(height: 6),
                Text(_prev(q), maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: solving ? Colors.grey.shade400 : const Color(0xFF475569), height: 1.4,
                    fontStyle: solving ? FontStyle.italic : FontStyle.normal)),
              ])),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: c.withAlpha(50), size: 22),
            ])))));
  }

  String _prev(LocalQuestion q) {
    if (q.status == QStatus.solving) return 'Koala çözüm üretiyor...';
    if (q.answer == null) return '';
    final s = StructuredAnswer.tryParse(q.answer!);
    if (s != null) return s.summary.isNotEmpty ? s.summary : s.finalAnswer;
    final r = q.answer!; return r.length > 80 ? '${r.substring(0, 80)}...' : r;
  }

  String _ago(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'şimdi';
    if (d.inMinutes < 60) return '${d.inMinutes} dk';
    if (d.inHours < 24) return '${d.inHours} sa';
    return '${d.inDays}g';
  }
}

class _B extends StatelessWidget {
  const _B({required this.l, required this.c, this.ic, this.spin = false});
  final String l; final Color c; final IconData? ic; final bool spin;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    if (spin) SizedBox(width: 9, height: 9, child: CircularProgressIndicator(strokeWidth: 1.5, color: c))
    else if (ic != null) Icon(ic, size: 11, color: c),
    const SizedBox(width: 3),
    Text(l, style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w600))]);
}














class _ShimmerCard extends StatefulWidget {
  const _ShimmerCard({this.delay = 0});
  final int delay;
  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
    _anim = Tween<double>(begin: -1.0, end: 2.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    if (widget.delay > 0) {
      _ctrl.stop();
      Future.delayed(Duration(milliseconds: widget.delay), () { if (mounted) _ctrl.repeat(); });
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFEEF2F7)),
        ),
        child: Row(children: [
          Container(width: 56, height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment(_anim.value - 1, 0),
                end: Alignment(_anim.value, 0),
                colors: const [Color(0xFFF1F5F9), Color(0xFFE2E8F0), Color(0xFFF1F5F9)]))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 90, height: 14,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(7),
                gradient: LinearGradient(
                  begin: Alignment(_anim.value - 1, 0),
                  end: Alignment(_anim.value, 0),
                  colors: const [Color(0xFFF1F5F9), Color(0xFFE2E8F0), Color(0xFFF1F5F9)]))),
            const SizedBox(height: 10),
            Container(width: double.infinity, height: 11,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(6),
                gradient: LinearGradient(
                  begin: Alignment(_anim.value - 1, 0),
                  end: Alignment(_anim.value, 0),
                  colors: const [Color(0xFFF8FAFC), Color(0xFFEEF2F7), Color(0xFFF8FAFC)]))),
            const SizedBox(height: 7),
            Container(width: 180, height: 11,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(6),
                gradient: LinearGradient(
                  begin: Alignment(_anim.value - 1, 0),
                  end: Alignment(_anim.value, 0),
                  colors: const [Color(0xFFF8FAFC), Color(0xFFEEF2F7), Color(0xFFF8FAFC)]))),
          ])),
        ]),
      ),
    );
  }
}



