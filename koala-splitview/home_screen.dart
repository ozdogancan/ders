import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  // ── SPLIT VIEW STATE ──
  String? _selectedQuestionId;

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
    _showOverlayToast(
      icon: Icons.check_rounded,
      iconColor: const Color(0xFF22C55E),
      message: '${q.subject} sorun çözüldü!',
      actionLabel: 'Gör',
      onAction: () => _openQuestion(q.id),
    );
  }

  void _showOverlayToast({required IconData icon, required Color iconColor, required String message, String? actionLabel, VoidCallback? onAction}) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(builder: (ctx) => _ToastOverlay(
      icon: icon, iconColor: iconColor, message: message,
      actionLabel: actionLabel, onAction: onAction,
      onDismiss: () { entry.remove(); },
    ));
    overlay.insert(entry);
  }

  List<LocalQuestion> _filtered() {
    var list = QuestionStore.instance.questions.toList();
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((i) => i.subject.toLowerCase().contains(q) || (i.answer ?? '').toLowerCase().contains(q)).toList();
    }
    if (_fSubject != null) list = list.where((i) => i.subject == _fSubject).toList();
    if (_fStatus == 'solving') list = list.where((i) => i.status == QStatus.solving).toList();
    else if (_fStatus == 'waiting') list = list.where((i) => i.status == QStatus.waitingAnswer).toList();
    else if (_fStatus == 'solved') list = list.where((i) => i.status == QStatus.solved).toList();
    else if (_fStatus == 'unread') list = list.where((i) => i.status == QStatus.solved && i.chatMessages.where((m) => m.role == 'user').isEmpty).toList();
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

  /// Opens a question — in split view (wide) selects it in panel, in mobile pushes route
  void _openQuestion(String questionId) {
    if (_isSplitView) {
      setState(() => _selectedQuestionId = questionId);
    } else {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(questionId: questionId)));
      _loadCredits();
    }
  }

  void _del(LocalQuestion q) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Soruyu sil', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      content: const Text('Bu soru ve çözümü silinecek.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
        FilledButton(onPressed: () {
          // If deleting the selected question, clear selection
          if (_selectedQuestionId == q.id) {
            setState(() => _selectedQuestionId = null);
          }
          QuestionStore.instance.remove(q.id);
          Navigator.pop(ctx);
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            behavior: SnackBarBehavior.floating, backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16), duration: const Duration(seconds: 2),
            content: const Row(children: [
              Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
              SizedBox(width: 10),
              Text('Soru silindi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
            ])));
        }, style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)), child: const Text('Sil')),
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
              _chip('Cevap bekleniyor', _fStatus == 'waiting', () { ss(() {}); setState(() => _fStatus = 'waiting'); }),
              _chip('Okunmamış', _fStatus == 'unread', () { ss(() {}); setState(() => _fStatus = 'unread'); }),
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

  /// Split view: 900px+ shows side-by-side panels
  bool get _isSplitView => MediaQuery.of(context).size.width >= 900;

  @override
  Widget build(BuildContext context) {
    if (_isSplitView) {
      return _buildSplitView();
    }
    return _buildNormalView();
  }

  // ╔══════════════════════════════════════════════════╗
  // ║  SPLIT VIEW (900px+): Left list + Right chat    ║
  // ╚══════════════════════════════════════════════════╝

  Widget _buildSplitView() {
    final screenW = MediaQuery.of(context).size.width;
    // Left panel width: 340–420px depending on screen
    final leftWidth = (screenW * 0.33).clamp(320.0, 420.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(children: [
          // ── TOP NAV BAR (full width) ──
          _buildSplitNavBar(),
          // ── BODY: side by side ──
          Expanded(
            child: Row(children: [
              // ── LEFT PANEL: question list ──
              SizedBox(
                width: leftWidth,
                child: _buildLeftPanel(),
              ),
              // ── DIVIDER ──
              Container(width: 1, color: const Color(0xFFE2E8F0).withAlpha(120)),
              // ── RIGHT PANEL: chat or empty state ──
              Expanded(child: _buildRightPanel()),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildSplitNavBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: const Color(0xFFE2E8F0).withAlpha(80))),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        KoalaLogo(size: 34),
        const SizedBox(width: 10),
        const Text('Koala', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1E293B), letterSpacing: -0.5)),
        const SizedBox(width: 32),
        // Search
        Expanded(child: Container(
          height: 42,
          constraints: const BoxConstraints(maxWidth: 400),
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
        // Soru Sor button
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
          child: Builder(builder: (_) {
            final photoUrl = FirebaseAuth.instance.currentUser?.photoURL;
            return Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: photoUrl == null ? const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]) : null,
                border: photoUrl != null ? Border.all(color: const Color(0xFF6366F1).withAlpha(40), width: 2) : null,
              ),
              child: photoUrl != null
                ? ClipOval(child: Image.network(photoUrl, width: 38, height: 38, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, color: Colors.white, size: 18)))
                : const Icon(Icons.person_rounded, color: Colors.white, size: 18),
            );
          }),
        ),
      ]),
    );
  }

  Widget _buildLeftPanel() {
    final filt = _filtered();
    final vis = filt.take(_visCount).toList();
    final hasF = _fSubject != null || _fDate != null || _fStatus != null;

    return Container(
      color: Colors.white,
      child: Column(children: [
        // ── Panel header with filter ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Row(children: [
            Text('Soruların', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
            const SizedBox(width: 8),
            if (filt.isNotEmpty) Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFF6366F1).withAlpha(10), borderRadius: BorderRadius.circular(99)),
              child: Text('${filt.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF6366F1)))),
            const Spacer(),
            GestureDetector(onTap: _showFilter,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: hasF ? const Color(0xFF6366F1) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: hasF ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.tune_rounded, size: 14, color: hasF ? Colors.white : Colors.grey.shade500),
                  const SizedBox(width: 5),
                  Text('Filtre', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: hasF ? Colors.white : Colors.grey.shade500)),
                ]),
              )),
          ]),
        ),
        // ── Question list ──
        Expanded(
          child: _isLoading
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(children: List.generate(3, (i) => _ShimmerCard(delay: i * 150))))
            : vis.isEmpty && !hasF && _search.isEmpty
              ? _buildLeftEmptyState()
              : vis.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.filter_list_off_rounded, color: Colors.grey.shade300, size: 36),
                    const SizedBox(height: 10),
                    const Text('Sonuç bulunamadı', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                    const SizedBox(height: 4),
                    Text('Farklı filtre dene', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ]))
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                    itemCount: vis.length + (vis.length < filt.length ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= vis.length) {
                        return Padding(padding: const EdgeInsets.all(16),
                          child: Center(child: SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey.shade300))));
                      }
                      final q = vis[i];
                      final isSelected = _selectedQuestionId == q.id;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _SplitTile(
                          q: q,
                          c: _sc(q.subject),
                          isSelected: isSelected,
                          tap: () => _openQuestion(q.id),
                          del: () => _del(q),
                        ),
                      );
                    },
                  ),
        ),
      ]),
    );
  }

  Widget _buildLeftEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const KoalaHero(size: 100),
          const SizedBox(height: 16),
          const Text('Merhaba!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
          const SizedBox(height: 8),
          Text('Fotoğraf çek, Koala sana öğretsin.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500, height: 1.5)),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () async { await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuestionShareScreen())); _loadCredits(); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withAlpha(30), blurRadius: 12, offset: const Offset(0, 4))]),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('İlk Sorunu Sor', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildRightPanel() {
    if (_selectedQuestionId == null) {
      return _buildRightEmptyState();
    }
    // Embedded chat — uses key to force rebuild on question change
    return ChatScreen(
      key: ValueKey('split_chat_$_selectedQuestionId'),
      questionId: _selectedQuestionId!,
      embedded: true,
      onCreditsChanged: () => _loadCredits(),
    );
  }

  Widget _buildRightEmptyState() {
    return Container(
      color: const Color(0xFFFAFBFD),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF6366F1).withAlpha(10),
            ),
            child: const Icon(Icons.chat_bubble_outline_rounded, size: 36, color: Color(0xFF6366F1)),
          ),
          const SizedBox(height: 20),
          const Text('Bir soru seç', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
          const SizedBox(height: 8),
          Text('Soldaki listeden bir soruya tıkla\nçözümü burada görüntüle',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500, height: 1.6)),
        ]),
      ),
    );
  }

  // ╔══════════════════════════════════════════════════╗
  // ║  NORMAL VIEW (<900px) — original code           ║
  // ╚══════════════════════════════════════════════════╝

  Widget _buildNormalView() {
    final filt = _filtered();
    final vis = filt.take(_visCount).toList();
    final hasF = _fSubject != null || _fDate != null || _fStatus != null;
    final wide = _isWide;
    final screenW = MediaQuery.of(context).size.width;
    final hPad = wide ? (screenW * 0.06).clamp(24.0, 80.0) : 20.0;

    return Scaffold(backgroundColor: Colors.white,
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
              Expanded(child: Container(
                height: 44,
                constraints: const BoxConstraints(maxWidth: 480),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
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
            GestureDetector(
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
                _loadCredits();
              },
              child: Builder(builder: (_) {
                final photoUrl = FirebaseAuth.instance.currentUser?.photoURL;
                return Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: photoUrl == null ? const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]) : null,
                    border: photoUrl != null ? Border.all(color: const Color(0xFF6366F1).withAlpha(40), width: 2) : null,
                  ),
                  child: photoUrl != null
                    ? ClipOval(child: Image.network(photoUrl, width: 38, height: 38, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, color: Colors.white, size: 18)))
                    : const Icon(Icons.person_rounded, color: Colors.white, size: 18),
                );
              }),
            ),
          ]))),

        // ── SEARCH (mobile only)
        if (!wide)
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(children: [
              Expanded(child: Container(height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0))),
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
                child: Container(width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: hasF ? const Color(0xFF6366F1) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: hasF ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0))),
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
              : Column(children: [
                  const KoalaHero(size: 140),
                  const SizedBox(height: 20),
                  const Text('Merhaba!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
                  const SizedBox(height: 8),
                  Text('Fotoğraf çek, Koala sana öğretsin.\nHer soruyu adım adım anlatırım.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Colors.grey.shade500, height: 1.5)),
                ])))
        else ...[
          // ── SECTION HEADER
          SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(hPad, wide ? 24 : 22, hPad, wide ? 16 : 10),
            child: Row(children: [
              Text('Soruların', style: TextStyle(fontSize: wide ? 20 : 16, fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
              const SizedBox(width: 10),
              if (filt.isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFF6366F1).withAlpha(10), borderRadius: BorderRadius.circular(99)),
                child: Text('${filt.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF6366F1)))),
              const Spacer(),
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
      floatingActionButton: wide ? null : FloatingActionButton.extended(
        onPressed: () async { await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuestionShareScreen())); _loadCredits(); },
        backgroundColor: const Color(0xFF6366F1), elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 20),
        label: const Text('Soru Sor', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))));
  }
}

// ╔══════════════════════════════════════════════════╗
// ║  SPLIT VIEW COMPACT TILE (for left panel)       ║
// ╚══════════════════════════════════════════════════╝

class _SplitTile extends StatelessWidget {
  const _SplitTile({required this.q, required this.c, required this.isSelected, required this.tap, required this.del});
  final LocalQuestion q; final Color c; final bool isSelected; final VoidCallback tap; final VoidCallback del;

  @override
  Widget build(BuildContext context) {
    final solving = q.status == QStatus.solving;
    final isUnread = q.status == QStatus.solved && q.chatMessages.where((m) => m.role == 'user').isEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: tap,
        onLongPress: del,
        borderRadius: BorderRadius.circular(14),
        hoverColor: const Color(0xFF6366F1).withAlpha(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF6366F1).withAlpha(8) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                ? const Color(0xFF6366F1).withAlpha(60)
                : isUnread
                  ? const Color(0xFF6366F1).withAlpha(30)
                  : const Color(0xFFEEF2F7),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            // Thumbnail
            Container(width: 48, height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [c.withAlpha(12), c.withAlpha(6)])),
              child: ClipRRect(borderRadius: BorderRadius.circular(12),
                child: Image.memory(q.imageBytes, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(Icons.image_rounded, color: c.withAlpha(60), size: 20)))),
            const SizedBox(width: 10),
            // Info
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: c.withAlpha(12), borderRadius: BorderRadius.circular(6)),
                  child: Text(q.subject, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700))),
                const SizedBox(width: 5),
                if (solving) _B(l: 'Çözülüyor', c: Colors.amber.shade700, spin: true)
                else if (q.status == QStatus.waitingAnswer) const _B(l: 'Bekliyor', c: Color(0xFF6366F1), ic: Icons.help_outline_rounded)
                else const _B(l: 'Çözüldü', c: Color(0xFF22C55E), ic: Icons.check_circle_rounded),
                const Spacer(),
                Text(_ago(q.createdAt), style: TextStyle(color: Colors.grey.shade400, fontSize: 9)),
              ]),
              const SizedBox(height: 4),
              Text(_prev(q), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: solving ? Colors.grey.shade400 : const Color(0xFF475569),
                  fontStyle: solving ? FontStyle.italic : FontStyle.normal)),
            ])),
            // Selection indicator
            if (isSelected)
              Container(
                margin: const EdgeInsets.only(left: 6),
                width: 4, height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  String _prev(LocalQuestion q) {
    if (q.status == QStatus.error) return 'Bir hata oluştu, kredin iade edildi.';
    if (q.status == QStatus.waitingAnswer) return 'Koala sana bir soru sordu...';
    if (q.status == QStatus.solving) return 'Koala çözüm üretiyor...';
    if (q.answer == null) return '';
    final s = StructuredAnswer.tryParse(q.answer!);
    if (s != null) return s.summary.isNotEmpty ? s.summary : s.finalAnswer;
    final r = q.answer!; return r.length > 60 ? '${r.substring(0, 60)}...' : r;
  }

  String _ago(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'şimdi';
    if (d.inMinutes < 60) return '${d.inMinutes} dk';
    if (d.inHours < 24) return '${d.inHours} sa';
    return '${d.inDays}g';
  }
}

// ╔══════════════════════════════════════════════════╗
// ║  ORIGINAL TILE (for mobile + 700-900px range)   ║
// ╚══════════════════════════════════════════════════╝

class _Tile extends StatelessWidget {
  const _Tile({required this.q, required this.c, required this.tap, required this.del, this.wide = false});
  final LocalQuestion q; final Color c; final VoidCallback tap; final VoidCallback del; final bool wide;

  @override
  Widget build(BuildContext context) {
    final solving = q.status == QStatus.solving;
    final isUnread = q.status == QStatus.solved && q.chatMessages.where((m) => m.role == 'user').isEmpty;

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
              border: Border.all(color: isUnread ? const Color(0xFF6366F1).withAlpha(60) : const Color(0xFFEEF2F7)),
              boxShadow: [BoxShadow(color: c.withAlpha(6), blurRadius: 12, offset: const Offset(0, 3))]),
            child: Row(children: [
              Container(width: wide ? 64 : 80, height: wide ? 64 : 80,
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
                  else if (q.status == QStatus.waitingAnswer) const _B(l: 'Cevap bekleniyor', c: Color(0xFF6366F1), ic: Icons.help_outline_rounded)
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
    if (q.status == QStatus.error) return 'Bir hata oluştu, kredin iade edildi.';
    if (q.status == QStatus.waitingAnswer) return 'Koala sana bir soru sordu, cevabını bekliyor...';
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

class _ToastOverlay extends StatefulWidget {
  const _ToastOverlay({required this.icon, required this.iconColor, required this.message, this.actionLabel, this.onAction, required this.onDismiss});
  final IconData icon;
  final Color iconColor;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;
  @override
  State<_ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<_ToastOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
    Future.delayed(const Duration(seconds: 2), _dismiss);
  }

  void _dismiss() {
    if (!mounted) return;
    _ctrl.reverse().then((_) { if (mounted) widget.onDismiss(); });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 16,
      left: 16, right: 16,
      child: SlideTransition(position: _slideAnim,
        child: FadeTransition(opacity: _fadeAnim,
          child: Material(color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(30), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Row(children: [
                Container(width: 26, height: 26,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: widget.iconColor.withAlpha(30)),
                  child: Icon(widget.icon, color: widget.iconColor, size: 14)),
                const SizedBox(width: 10),
                Expanded(child: Text(widget.message,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14, decoration: TextDecoration.none))),
                if (widget.actionLabel != null)
                  GestureDetector(
                    onTap: () { _dismiss(); widget.onAction?.call(); },
                    child: Text(widget.actionLabel!, style: const TextStyle(color: Color(0xFF818CF8), fontWeight: FontWeight.w700, fontSize: 14, decoration: TextDecoration.none))),
              ]),
            )))));
  }
}
