import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/koala_tokens.dart';
import '../services/evlumba_live_service.dart';
import '../services/messaging_service.dart';
import '../services/saved_items_service.dart';
import '../widgets/save_button.dart';
import 'chat_detail_screen.dart';
import 'conversation_detail_screen.dart';

// Alias — KoalaTokens source of truth
class _ExpertK {
  static const surface = KoalaColors.bg;
  static const surfaceLow = KoalaColors.surfaceAlt;
  static const surfaceCard = KoalaColors.surface;
  static const outline = KoalaColors.border;
  static const text = KoalaColors.text;
  static const muted = KoalaColors.textSec;
  static const primary = KoalaColors.accent;
}

class _ExpertChip {
  final String label;
  final String keyword;

  const _ExpertChip(this.label, this.keyword);
}

class _ExpertPreview {
  final Map<String, dynamic> designer;
  final List<Map<String, dynamic>> projects;
  final double rating;
  final String summary;

  const _ExpertPreview({
    required this.designer,
    required this.projects,
    required this.rating,
    required this.summary,
  });
}

class _ExpertTurn {
  final String userMessage;
  final String intent;
  List<_ExpertPreview> experts;
  List<String> prompts;
  String assistantText;
  bool isLoading;
  bool isComplete;
  final int replyKey;

  _ExpertTurn({
    required this.userMessage,
    required this.intent,
    required this.experts,
    required this.prompts,
    required this.assistantText,
    required this.isLoading,
    required this.isComplete,
    required this.replyKey,
  });
}

class DesignersScreen extends StatefulWidget {
  const DesignersScreen({super.key});

  @override
  State<DesignersScreen> createState() => _DesignersScreenState();
}

class _DesignersScreenState extends State<DesignersScreen> {
  static const _chips = <_ExpertChip>[
    _ExpertChip('İç Mimarlar', 'ic mimar'),
    _ExpertChip('Dekorasyon Uzmanları', 'dekorasyon'),
    _ExpertChip('Renk Danışmanları', 'renk'),
    _ExpertChip('Mobilya Tasarımcıları', 'mobilya'),
  ];

  final TextEditingController _input = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ExpertPreview> _allExperts = <_ExpertPreview>[];
  final List<_ExpertTurn> _turns = <_ExpertTurn>[];

  bool _loading = true;
  String? _error;
  String? _activeIntent;
  int _replyKey = 0;

  String _designerInquiryText(_ExpertPreview expert, {String? customMessage}) {
    final name = (expert.designer['full_name'] ?? 'uzman').toString().trim();
    final projectTitles = expert.projects
        .take(2)
        .map((project) => (project['title'] ?? '').toString().trim())
        .where((title) => title.isNotEmpty)
        .toList();
    final projectContext = projectTitles.isEmpty
        ? ''
        : ' Portfolyosunda özellikle ${projectTitles.join(' ve ')} projeleri dikkatimi çekti.';
    final note = customMessage?.trim() ?? '';
    final base =
        '$name ile çalışmak istiyorum.$projectContext Bu uzmanla iletişim kurmam ve süreci başlatmam için beni yönlendir.';
    if (note.isEmpty) return base;
    return '$base Kullanıcının notu: $note';
  }

  Future<void> _openExpertChat(_ExpertPreview expert, {String? customMessage}) async {
    final designerId = expert.designer['id']?.toString() ?? '';
    final name = (expert.designer['full_name'] ?? 'Tasarımcı').toString();
    final uid = MessagingService.currentUserId;

    // Giriş yapmamışsa auth ekranına yönlendir
    if (uid == null && mounted) {
      Navigator.of(context).pop(); // bottom sheet'i kapat
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF6C5CE7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
          content: const Row(
            children: [
              Icon(Icons.login_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('Tasarımcıya mesaj atmak için giriş yapın.', style: TextStyle(color: Colors.white, fontSize: 13))),
            ],
          ),
        ),
      );
      return;
    }

    // Gerçek mesajlaşma konuşması başlat
    final conv = await MessagingService.getOrCreateConversation(
      designerId: designerId,
      contextType: 'designer',
      contextId: designerId,
      contextTitle: name,
    );

    if (conv != null && mounted) {
      // Bottom sheet açıksa kapat
      Navigator.of(context).pop();
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ConversationDetailScreen(
            conversationId: conv['id'] as String,
            designerName: name,
            designerAvatarUrl: expert.designer['avatar_url']?.toString(),
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFEF4444),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
          content: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('Bağlantı kurulamadı. Lütfen tekrar deneyin.', style: TextStyle(color: Colors.white, fontSize: 13))),
            ],
          ),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadExperts();
  }

  @override
  void dispose() {
    _input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadExperts() async {
    if (!EvlumbaLiveService.isReady) {
      setState(() {
        _loading = false;
        _error = 'Bağlantı hazır değil.';
      });
      return;
    }

    try {
      final publishedProjects = await EvlumbaLiveService.getProjects(limit: 80);
      final projectsByDesigner = <String, List<Map<String, dynamic>>>{};
      for (final project in publishedProjects) {
        final designerId = (project['designer_id'] ?? '').toString().trim();
        if (designerId.isEmpty) continue;
        projectsByDesigner.putIfAbsent(designerId, () => <Map<String, dynamic>>[]).add(project);
      }

      final previews = await Future.wait(
        projectsByDesigner.entries.take(12).map((entry) async {
          final designerId = entry.key;
          final designer = await EvlumbaLiveService.getDesigner(designerId);
          if (designer == null) return null;
          final projects = List<Map<String, dynamic>>.from(entry.value);

          final rating = (designer['rating'] as num?)?.toDouble() ?? 0;
          final specialty = (designer['specialty'] ?? designer['bio'] ?? '')
              .toString()
              .trim();

          return _ExpertPreview(
            designer: designer,
            projects: projects.take(6).toList(),
            rating: rating,
            summary: specialty.isEmpty
                ? 'Yaşam alanları için dengeli ve uygulanabilir çözümler üretiyor.'
                : specialty,
          );
        }),
      );

      if (!mounted) return;
      setState(() {
        _allExperts
          ..clear()
          ..addAll(previews.whereType<_ExpertPreview>());
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  static String _normalize(String raw) {
    const source = 'çğıöşüÇĞİÖŞÜ';
    const target = 'cgiosuCGIOSU';
    var result = raw.trim();
    for (var i = 0; i < source.length; i++) {
      result = result.replaceAll(source[i], target[i]);
    }
    return result.toLowerCase();
  }

  static String _projectCover(Map<String, dynamic> project) {
    for (final key in ['cover_image_url', 'cover_url', 'image_url']) {
      final value = (project[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }

    final images = (project['designer_project_images'] as List?)
        ?.whereType<Map>()
        .toList();
    if (images == null || images.isEmpty) return '';

    images.sort(
      (a, b) => ((a['sort_order'] as num?)?.toInt() ?? 9999)
          .compareTo((b['sort_order'] as num?)?.toInt() ?? 9999),
    );
    return (images.first['image_url'] ?? '').toString().trim();
  }

  void _startTurn(String intent, String message) {
    HapticFeedback.lightImpact();
    final turn = _ExpertTurn(
      userMessage: message,
      intent: intent,
      experts: <_ExpertPreview>[],
      prompts: <String>[],
      assistantText: 'Senin için en doğru uzmanları süzüyorum.',
      isLoading: true,
      isComplete: false,
      replyKey: _replyKey++,
    );

    setState(() {
      _activeIntent = intent;
      _turns.add(turn);
    });

    _scrollToBottom();
    _resolveTurn(turn);
  }

  Future<void> _resolveTurn(_ExpertTurn turn) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    final matches = _matchExperts(turn.intent);
    setState(() {
      turn.experts
        ..clear()
        ..addAll(matches);
      turn.assistantText = _assistantReply(turn.intent, matches);
      turn.prompts = _smartPrompts(turn.intent, matches);
      turn.isLoading = false;
    });
  }

  List<_ExpertPreview> _matchExperts(String intent) {
    final normalized = _normalize(intent);
    final filtered = _allExperts.where((expert) {
      final specialty = _normalize(
        (expert.designer['specialty'] ?? expert.summary).toString(),
      );
      final bio = _normalize((expert.designer['bio'] ?? '').toString());
      final city = _normalize((expert.designer['city'] ?? '').toString());
      return specialty.contains(normalized) ||
          bio.contains(normalized) ||
          city.contains(normalized);
    }).toList()
      ..sort((a, b) => b.projects.length.compareTo(a.projects.length));

    if (filtered.isEmpty) {
      final fallback = List<_ExpertPreview>.from(_allExperts)
        ..sort((a, b) => b.projects.length.compareTo(a.projects.length));
      return fallback.take(4).toList();
    }

    return filtered.take(4).toList();
  }

  String _assistantReply(String intent, List<_ExpertPreview> experts) {
    if (experts.isEmpty) {
      return 'Sana uygun uzmanları henüz netleştiremedim. Biraz daha stil, bütçe ya da oda tipi söylersen daha iyi süzerim.';
    }

    final first = (experts.first.designer['full_name'] ?? 'ilk uzman').toString();
    final second = experts.length > 1
        ? (experts[1].designer['full_name'] ?? '').toString()
        : '';

    if (_normalize(intent).contains('renk')) {
      return second.isNotEmpty
          ? 'Renk ve atmosfer tarafında gözü güçlü iki isim öne çıktı: $first ve $second. Portfolyosu daha okunur olanları seçtim.'
          : 'Renk tarafında ilk bakmanı istediğim uzman $first.';
    }
    if (_normalize(intent).contains('mobilya')) {
      return second.isNotEmpty
          ? 'Mobilya ve yerleşim kararlarında güçlü duran isimleri seçtim: $first ve $second. Ürün dili daha karakterli olanları öne aldım.'
          : 'Mobilya tarafında ilk bakmanı istediğim uzman $first.';
    }
    return second.isNotEmpty
        ? 'Senin ihtiyacına göre önce $first ve $second dikkat çekiyor. Portfolyo dili ve proje yoğunluğu daha güçlü olanları öne aldım.'
        : 'Senin ihtiyacına göre ilk bakmanı istediğim uzman $first.';
  }

  List<String> _smartPrompts(String intent, List<_ExpertPreview> experts) {
    final hasProjects = experts.any((expert) => expert.projects.isNotEmpty);
    if (_normalize(intent).contains('renk')) {
      return [
        'Daha premium uzman göster',
        'Bütçeme yakın olanı bul',
        if (hasProjects) 'Portfolyosu en güçlü olanı çıkar',
        'Başka uzman tipi seçmek istiyorum',
      ];
    }
    return [
      'Bana en uygun olan hangisi?',
      'Daha sıcak tarz çalışan uzman göster',
      if (hasProjects) 'Portfolyosu güçlü olanı öne çıkar',
      'Başka uzman tipi seçmek istiyorum',
    ];
  }

  String? _resolveIntent(String text) {
    final normalized = _normalize(text);
    if (normalized.contains('renk')) return 'renk';
    if (normalized.contains('mobilya')) return 'mobilya';
    if (normalized.contains('dekor')) return 'dekorasyon';
    if (normalized.contains('ic mim') || normalized.contains('uzman')) return 'ic mimar';
    return null;
  }

  void _submit() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    _startTurn(_resolveIntent(text) ?? _activeIntent ?? 'ic mimar', text);
  }

  void _handlePrompt(String prompt) {
    if (prompt.contains('Başka uzman tipi')) {
      setState(() => _activeIntent = null);
      _scrollToBottom();
      return;
    }
    _startTurn(_activeIntent ?? 'ic mimar', prompt);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 240,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _openProject(_ExpertPreview expert, Map<String, dynamic> project) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.24),
      builder: (_) => _ExpertDetailSheet(
        expert: expert,
        highlightedProjectId: (project['id'] ?? '').toString(),
        onSendMessage: (message) => _openExpertChat(expert, customMessage: message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ExpertK.surface,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                _topBar(context),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: _ExpertK.primary,
                            strokeWidth: 2,
                          ),
                        )
                      : _error != null
                          ? _ErrorState(message: _error!)
                          : _content(),
                ),
              ],
            ),
            _bottomComposer(),
          ],
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Container(
      color: _ExpertK.surface,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(
                  LucideIcons.arrowLeft,
                  size: 24,
                  color: _ExpertK.primary,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Uzman Bul',
                style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _ExpertK.text,
                ),
              ),
            ],
          ),
          const Text(
            'koala',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _ExpertK.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 124),
      children: [
        const _ExpertAssistantBubble(
          text: 'Yaşam alanına en uygun uzmanı birlikte bulalım. Önce nasıl bir desteğe ihtiyacın olduğunu seç.',
          lowSurface: true,
        ),
        const SizedBox(height: 22),
        if (_activeIntent == null)
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _chips.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final chip = _chips[index];
                return _ExpertQuickChip(
                  label: chip.label,
                  onTap: () => _startTurn(chip.keyword, chip.label),
                );
              },
            ),
          ),
        if (_turns.isNotEmpty) const SizedBox(height: 24),
        ..._turns.asMap().entries.expand((entry) {
          final turn = entry.value;
          final isLast = entry.key == _turns.length - 1;
          return <Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: _ExpertUserBubble(text: turn.userMessage),
            ),
            const SizedBox(height: 24),
            if (turn.isLoading)
              const _ExpertTypingBubble()
            else if (!turn.isComplete)
              _ExpertTypewriterBubble(
                key: ValueKey(turn.replyKey),
                text: turn.assistantText,
                onComplete: () {
                  if (!mounted || turn.isComplete) return;
                  setState(() => turn.isComplete = true);
                },
              )
            else
              _ExpertAssistantBubble(text: turn.assistantText),
            if (turn.isComplete) ...[
              const SizedBox(height: 22),
              ...turn.experts.asMap().entries.map(
                    (expertEntry) => Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: _ExpertCard(
                        expert: expertEntry.value,
                        onTap: () => _openExpertChat(expertEntry.value),
                        onProjectTap: (project) => _openProject(expertEntry.value, project),
                      ),
                    ),
                  ),
              if (isLast)
                _ExpertPromptWrap(
                  prompts: turn.prompts,
                  onTap: _handlePrompt,
                ),
            ],
            const SizedBox(height: 24),
          ];
        }),
      ],
    );
  }

  Widget _bottomComposer() {
    final bottom = MediaQuery.of(context).padding.bottom;
    final hasText = _input.text.trim().isNotEmpty;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 6, 16, bottom + 22),
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06), width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.04),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.search, size: 18, color: _ExpertK.muted),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _input,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: _activeIntent == null ? 'uzman keşfet...' : "Koala'ya sor...",
                    hintStyle: GoogleFonts.manrope(
                      fontSize: 14,
                      color: const Color(0xFF787585).withValues(alpha: 0.72),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                ),
              ),
              GestureDetector(
                onTap: _submit,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasText ? null : Colors.black.withValues(alpha: 0.04),
                      gradient: hasText
                          ? const LinearGradient(
                              colors: [Color(0xFF7C6EF2), Color(0xFF5A4DBF)],
                            )
                          : null,
                    ),
                    child: Icon(
                      LucideIcons.arrowUp,
                      size: 18,
                      color: hasText ? Colors.white : _ExpertK.muted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpertAssistantBubble extends StatelessWidget {
  final String text;
  final bool lowSurface;

  const _ExpertAssistantBubble({
    required this.text,
    this.lowSurface = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _ExpertK.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.center,
          child: const Text('🐨', style: TextStyle(fontSize: 20)),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 312),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            decoration: BoxDecoration(
              color: lowSurface ? _ExpertK.surfaceLow : _ExpertK.surfaceCard,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(24),
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
              border: Border.all(color: _ExpertK.outline.withValues(alpha: lowSurface ? 0.10 : 0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Koala AI',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _ExpertK.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  text,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    height: 1.6,
                    color: _ExpertK.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ExpertTypewriterBubble extends StatefulWidget {
  final String text;
  final VoidCallback onComplete;

  const _ExpertTypewriterBubble({
    super.key,
    required this.text,
    required this.onComplete,
  });

  @override
  State<_ExpertTypewriterBubble> createState() => _ExpertTypewriterBubbleState();
}

class _ExpertTypewriterBubbleState extends State<_ExpertTypewriterBubble> {
  String _visible = '';
  int _index = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    while (mounted && _index < widget.text.length) {
      await Future<void>.delayed(const Duration(milliseconds: 12));
      if (!mounted) return;
      final next = (_index + 2).clamp(0, widget.text.length);
      setState(() {
        _index = next;
        _visible = widget.text.substring(0, _index);
      });
    }
    if (!_done && mounted) {
      _done = true;
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ExpertAssistantBubble(text: _visible);
  }
}

class _ExpertTypingBubble extends StatelessWidget {
  const _ExpertTypingBubble();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _ExpertK.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.center,
          child: const Text('🐨', style: TextStyle(fontSize: 20)),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            color: _ExpertK.surfaceCard,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(24),
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            border: Border.all(color: _ExpertK.outline.withValues(alpha: 0.15)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              3,
              (index) => Padding(
                padding: EdgeInsets.only(right: index == 2 ? 0 : 6),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _ExpertK.primary.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExpertQuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ExpertQuickChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _ExpertK.primary.withValues(alpha: 0.82)),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _ExpertK.primary,
          ),
        ),
      ),
    );
  }
}

class _ExpertUserBubble extends StatelessWidget {
  final String text;

  const _ExpertUserBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5646CA), Color(0xFF6F61E5)],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(6),
        ),
      ),
      child: Text(
        text,
        style: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _ExpertCard extends StatelessWidget {
  final _ExpertPreview expert;
  final VoidCallback onTap;
  final ValueChanged<Map<String, dynamic>> onProjectTap;

  const _ExpertCard({
    required this.expert,
    required this.onTap,
    required this.onProjectTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = (expert.designer['full_name'] ?? 'İsimsiz uzman').toString();
    final avatar = (expert.designer['avatar_url'] ?? '').toString().trim();
    final projects = expert.projects.take(5).toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _ExpertK.surfaceCard,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(url: avatar, name: name, size: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _ExpertK.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (expert.rating > 0) ...[
                          const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 4),
                          Text(
                            expert.rating.toStringAsFixed(1),
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: _ExpertK.text,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Text(
                          '${expert.projects.length} Proje',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _ExpertK.muted.withValues(alpha: 0.72),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SaveButton(
                itemType: SavedItemType.designer,
                itemId: expert.designer['id']?.toString() ?? name,
                title: name,
                subtitle: expert.designer['specialty']?.toString(),
                imageUrl: avatar.isNotEmpty ? avatar : null,
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            expert.summary,
            style: GoogleFonts.manrope(
              fontSize: 14,
              height: 1.55,
              color: _ExpertK.muted,
            ),
          ),
          if (projects.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: projects.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final project = projects[index];
                  final imageUrl = _DesignersScreenState._projectCover(project);
                  final title = (project['title'] ?? 'Proje').toString();

                  return GestureDetector(
                    onTap: () => onProjectTap(project),
                    child: SizedBox(
                      width: 132,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: SizedBox(
                              width: 132,
                              height: 78,
                              child: imageUrl.isEmpty
                                  ? Container(color: _ExpertK.surfaceLow)
                                  : Image.network(
                                      imageUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) =>
                                          Container(color: _ExpertK.surfaceLow),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: _ExpertK.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                color: _ExpertK.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(
                'Mesaj At',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String url;
  final String name;
  final double size;

  const _Avatar({
    required this.url,
    required this.name,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _ExpertK.primary.withValues(alpha: 0.14),
        image: url.isNotEmpty ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover) : null,
      ),
      alignment: Alignment.center,
      child: url.isEmpty
          ? Text(
              name.isEmpty ? 'U' : name.substring(0, 1).toUpperCase(),
              style: GoogleFonts.manrope(
                fontSize: size * 0.34,
                fontWeight: FontWeight.w800,
                color: _ExpertK.primary,
              ),
            )
          : null,
    );
  }
}

class _ExpertPromptWrap extends StatelessWidget {
  final List<String> prompts;
  final ValueChanged<String> onTap;

  const _ExpertPromptWrap({
    required this.prompts,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: prompts.map((prompt) {
        return GestureDetector(
          onTap: () => onTap(prompt),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _ExpertK.outline.withValues(alpha: 0.30)),
            ),
            child: Text(
              prompt,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _ExpertK.text,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;

  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _ExpertK.muted,
          ),
        ),
      ),
    );
  }
}

class _ExpertDetailSheet extends StatefulWidget {
  final _ExpertPreview expert;
  final String? highlightedProjectId;
  final ValueChanged<String> onSendMessage;

  const _ExpertDetailSheet({
    required this.expert,
    required this.onSendMessage,
    this.highlightedProjectId,
  });

  @override
  State<_ExpertDetailSheet> createState() => _ExpertDetailSheetState();
}

class _ExpertDetailSheetState extends State<_ExpertDetailSheet> {
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _submitMessage() {
    final message = _messageController.text.trim();
    _messageController.clear();
    widget.onSendMessage(message);
  }

  @override
  Widget build(BuildContext context) {
    final expert = widget.expert;
    final projects = List<Map<String, dynamic>>.from(expert.projects);
    if (widget.highlightedProjectId != null) {
      projects.sort((a, b) {
        final aMatch = (a['id'] ?? '').toString() == widget.highlightedProjectId;
        final bMatch = (b['id'] ?? '').toString() == widget.highlightedProjectId;
        if (aMatch == bMatch) return 0;
        return aMatch ? -1 : 1;
      });
    }

    final name = (expert.designer['full_name'] ?? 'İsimsiz uzman').toString();
    final avatar = (expert.designer['avatar_url'] ?? '').toString().trim();
    final city = (expert.designer['city'] ?? '').toString().trim();

    return DraggableScrollableSheet(
      expand: false,
      minChildSize: 0.56,
      initialChildSize: 0.84,
      maxChildSize: 0.94,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: _ExpertK.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 56,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
                  children: [
                    Row(
                      children: [
                        _Avatar(url: avatar, name: name, size: 68),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: GoogleFonts.manrope(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: _ExpertK.text,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (expert.rating > 0) ...[
                                    const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF59E0B)),
                                    const SizedBox(width: 4),
                                    Text(
                                      expert.rating.toStringAsFixed(1),
                                      style: GoogleFonts.manrope(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: _ExpertK.text,
                                      ),
                                    ),
                                  ],
                                  if (city.isNotEmpty) ...[
                                    const SizedBox(width: 10),
                                    Text(
                                      city,
                                      style: GoogleFonts.manrope(
                                        fontSize: 12,
                                        color: _ExpertK.muted,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F0FF),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        expert.summary,
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          height: 1.55,
                          color: _ExpertK.muted,
                        ),
                      ),
                    ),
                    if (projects.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      Text(
                        'Diğer Tasarımları',
                        style: GoogleFonts.manrope(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: _ExpertK.text,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ...projects.map((project) {
                        final imageUrl = _DesignersScreenState._projectCover(project);
                        final title = (project['title'] ?? 'Proje').toString();

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                                  child: SizedBox(
                                    height: 168,
                                    width: double.infinity,
                                    child: imageUrl.isEmpty
                                        ? Container(color: _ExpertK.surfaceLow)
                                        : Image.network(
                                            imageUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) =>
                                                Container(color: _ExpertK.surfaceLow),
                                          ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    title,
                                    style: GoogleFonts.manrope(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: _ExpertK.text,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
              _DetailComposer(
                controller: _messageController,
                designerName: name,
                onSend: _submitMessage,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DetailComposer extends StatelessWidget {
  final TextEditingController controller;
  final String designerName;
  final VoidCallback onSend;

  const _DetailComposer({
    required this.controller,
    required this.designerName,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 18),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06), width: 0.5),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: '$designerName için mesaj yaz...',
                  hintStyle: GoogleFonts.manrope(
                    fontSize: 14,
                    color: const Color(0xFF787585).withValues(alpha: 0.72),
                  ),
                  border: InputBorder.none,
                ),
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _ExpertK.text,
                ),
              ),
            ),
            GestureDetector(
              onTap: onSend,
              child: Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.only(right: 8),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF7C6EF2), Color(0xFF5A4DBF)],
                  ),
                ),
                child: const Icon(LucideIcons.arrowUp, size: 18, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
