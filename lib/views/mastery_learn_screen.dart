import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../services/chatgpt_service.dart';
import '../services/credit_service.dart';
import '../stores/mastery_store.dart';
import '../stores/question_store.dart';

class MasteryLearnScreen extends StatefulWidget {
  const MasteryLearnScreen({super.key, required this.topicId});
  final String topicId;
  @override
  State<MasteryLearnScreen> createState() => _MasteryLearnScreenState();
}

class _MasteryLearnScreenState extends State<MasteryLearnScreen>
    with TickerProviderStateMixin {
  final ChatGptService _chat = ChatGptService();
  final CreditService _credit = CreditService();
  final ScrollController _scroll = ScrollController();

  MasteryTopic? get _topic => MasteryStore.instance.getById(widget.topicId);
  bool _loading = false;
  bool _waitingAnswer = false;
  int _credits = 0;

  // Placement test state
  bool _placementActive = false;
  int _placementStep = 0; // 0,1,2
  int _placementCorrect = 0;
  bool _placementDone = false;
  MasteryLevel? _detectedLevel;
  bool _showLevelAnimation = false;

  // Question state
  String _explanation = '';
  String _question = '';
  List<String> _options = [];
  String _correctAnswer = '';
  int? _selectedOption;
  bool? _lastCorrect;

  // Level-up animation
  AnimationController? _levelAnimCtrl;
  Animation<double>? _levelAnimScale;
  Animation<double>? _levelAnimOpacity;

  // Step colors (same as chat_screen)
  static const _stepColors = [
    Color(0xFF6366F1), Color(0xFF0EA5E9), Color(0xFF8B5CF6),
    Color(0xFF14B8A6), Color(0xFFF59E0B), Color(0xFFEC4899),
  ];

  @override
  void initState() {
    super.initState();
    _loadCredits();
    _initLevelAnim();
    _checkPlacement();
  }

  void _initLevelAnim() {
    _levelAnimCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800));
    _levelAnimScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _levelAnimCtrl!, curve: Curves.elasticOut));
    _levelAnimOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _levelAnimCtrl!, curve: const Interval(0, 0.4)));
  }

  @override
  void dispose() {
    _scroll.dispose();
    _levelAnimCtrl?.dispose();
    super.dispose();
  }

  Future<void> _loadCredits() async {
    final c = await _credit.getCredits();
    if (mounted) setState(() => _credits = c);
  }

  void _checkPlacement() {
    final t = _topic;
    if (t == null) return;

    // Only do placement if topic is brand new (no questions answered yet)
    if (t.totalQuestions == 0) {
      setState(() => _placementActive = true);
      _startPlacementQuestion();
    } else {
      _startPhase();
    }
  }

  // ═══════════════════════════════════════════
  // PLACEMENT TEST (3 questions: easy, medium, hard)
  // ═══════════════════════════════════════════

  Future<void> _startPlacementQuestion() async {
    final t = _topic;
    if (t == null) return;
    setState(() => _loading = true);

    final difficulty = _placementStep == 0
        ? 'kolay (temel kavram)'
        : _placementStep == 1
            ? 'orta (uygulama)'
            : 'zor (analiz)';

    final prompt =
        '${t.title} konusundan $difficulty seviyede 1 coktan secmeli soru sor. '
        'Formul gerekiyorsa LaTeX formatinda yaz (dolar isareti KULLANMA). '
        'SADECE su formatta yaz:\n'
        'SORU: [soru]\n'
        'A) [secenek]\nB) [secenek]\nC) [secenek]\nD) [secenek]\n'
        'DOGRU: [A/B/C/D]';

    try {
      final result = await _chat.askText(prompt);
      _parsePlacementContent(result);
    } catch (e) {
      setState(() {
        _question = 'Bir hata oluştu. Tekrar dene.';
        _loading = false;
      });
    }
    setState(() => _loading = false);
  }

  void _parsePlacementContent(String raw) {
    final lines = raw.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    _question = '';
    _options = [];
    _correctAnswer = '';
    _selectedOption = null;
    _lastCorrect = null;
    _waitingAnswer = true;
    _explanation = '';

    for (final line in lines) {
      if (line.startsWith('SORU:')) {
        _question = line.substring(5).trim();
      } else if (RegExp(r'^[A-D]\)').hasMatch(line)) {
        _options.add(line.substring(2).trim());
      } else if (line.startsWith('DOGRU:')) {
        _correctAnswer = line.substring(6).trim().toUpperCase();
      }
    }
  }

  void _selectPlacementOption(int idx) async {
    if (_selectedOption != null) return;
    setState(() => _selectedOption = idx);

    final selected = String.fromCharCode(65 + idx);
    final correct = selected == _correctAnswer;
    if (correct) _placementCorrect++;

    await _credit.spendOneCredit();
    await _loadCredits();

    setState(() {
      _lastCorrect = correct;
      _waitingAnswer = false;
    });

    _scrollToBottom();
  }

  void _nextPlacement() {
    _placementStep++;
    if (_placementStep >= 3) {
      // Determine level
      if (_placementCorrect >= 3) {
        _detectedLevel = MasteryLevel.usta;
      } else if (_placementCorrect >= 2) {
        _detectedLevel = MasteryLevel.kalfa;
      } else {
        _detectedLevel = MasteryLevel.cirak;
      }

      // Skip phases based on level
      final t = _topic;
      if (t != null) {
        if (_detectedLevel == MasteryLevel.kalfa) {
          // Skip first 2 phases
          MasteryStore.instance.skipToPhase(t.id, 2);
        } else if (_detectedLevel == MasteryLevel.usta) {
          // Skip first 3 phases
          MasteryStore.instance.skipToPhase(t.id, 3);
        }
      }

      setState(() {
        _placementDone = true;
        _showLevelAnimation = true;
      });
      _levelAnimCtrl?.forward();
    } else {
      _startPlacementQuestion();
    }
  }

  void _finishPlacement() {
    setState(() {
      _placementActive = false;
      _showLevelAnimation = false;
    });
    _startPhase();
  }

  // ═══════════════════════════════════════════
  // NORMAL PHASE FLOW
  // ═══════════════════════════════════════════

  Future<void> _startPhase() async {
    final t = _topic;
    if (t == null) return;
    final phase = t.activePhase;
    if (phase == null) return;

    setState(() => _loading = true);

    try {
      final prompt = _buildPrompt(t, phase);
      final result = await _chat.askText(prompt);
      _parseContent(result);
    } catch (e) {
      setState(() => _question = 'Bir hata oluştu. Tekrar dene.');
    }
    setState(() => _loading = false);
  }

  String _buildPrompt(MasteryTopic t, MasteryPhase phase) {
    final wrongRow = t.wrongInRow;
    final adaptiveHint = wrongRow >= 2
        ? 'Ogrenci zorlanıyor. Cok basit dille, ornekle anlat. '
        : wrongRow >= 1
            ? 'Farkli acidan anlat. '
            : '';

    // Optimized: shorter prompts, formula included, no unnecessary verbosity
    final phaseHints = {
      'discover': 'Temel kavram sorusu. 2 cumle aciklama yeter.',
      'remember': 'Hatırlama sorusu. 1 cumle ipucu ver.',
      'apply': 'Uygulama/hesaplama sorusu. Formulu soruya dahil et.',
      'analyze': 'Analiz sorusu. Neden-sonuc veya tuzak soru.',
      'master': 'Zor ve yaratici soru. Farkli senaryo.',
    };

    final hint = phaseHints[phase.id] ?? '';

    return '${t.title} konusundan Turkce 1 coktan secmeli soru sor. '
        '$hint $adaptiveHint'
        'Formul varsa LaTeX formatinda yaz (dolar isareti KULLANMA). '
        'SADECE su formatta cevap ver, baska hicbir sey yazma:\n'
        'ACIKLAMA: [1-2 cumle]\n'
        'SORU: [soru metni]\n'
        'A) [secenek]\nB) [secenek]\nC) [secenek]\nD) [secenek]\n'
        'DOGRU: [A/B/C/D]';
  }

  void _parseContent(String raw) {
    final lines = raw.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    _explanation = '';
    _question = '';
    _options = [];
    _correctAnswer = '';
    _selectedOption = null;
    _lastCorrect = null;
    _waitingAnswer = true;

    for (final line in lines) {
      if (line.startsWith('ACIKLAMA:')) {
        _explanation = line.substring(9).trim();
      } else if (line.startsWith('SORU:')) {
        _question = line.substring(5).trim();
      } else if (RegExp(r'^[A-D]\)').hasMatch(line)) {
        _options.add(line.substring(2).trim());
      } else if (line.startsWith('DOGRU:')) {
        _correctAnswer = line.substring(6).trim().toUpperCase();
      }
    }
  }

  void _selectOption(int idx) async {
    if (_selectedOption != null) return;
    final t = _topic;
    if (t == null) return;

    final prevLevel = t.level;
    setState(() => _selectedOption = idx);

    final selected = String.fromCharCode(65 + idx);
    final correct = selected == _correctAnswer;

    if (correct) {
      MasteryStore.instance.answerCorrect(t.id);
    } else {
      MasteryStore.instance.answerWrong(t.id);
    }

    await _credit.spendOneCredit();
    await _loadCredits();

    // Check level-up
    final newLevel = _topic?.level;
    if (newLevel != null && newLevel != prevLevel) {
      _detectedLevel = newLevel;
      setState(() => _showLevelAnimation = true);
      _levelAnimCtrl?.reset();
      _levelAnimCtrl?.forward();
    }

    setState(() {
      _lastCorrect = correct;
      _waitingAnswer = false;
    });

    _scrollToBottom();
  }

  void _next() {
    final t = _topic;
    if (t == null) return;

    if (_showLevelAnimation) {
      setState(() => _showLevelAnimation = false);
    }

    if (t.status == TopicStatus.completed) {
      Navigator.of(context).pop();
      return;
    }

    _startPhase();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  // ═══════════════════════════════════════════
  // LATEX HELPERS (from chat_screen)
  // ═══════════════════════════════════════════

  String _cleanLatex(String s) {
    return s.replaceAll(RegExp(r'^\$+|\$+$'), '').replaceAll('\$', '').trim();
  }

  bool _hasLatex(String s) {
    return RegExp(r'\\(frac|sqrt|sum|int|times|div|alpha|beta|pi|theta|infty|lim|log|sin|cos|tan|pm|cdot|leq|geq|neq|approx|rightarrow|leftarrow|Rightarrow|Leftarrow|begin|end|text)')
        .hasMatch(s) ||
        RegExp(r'\^{?\d').hasMatch(s) ||
        RegExp(r'_{?\d').hasMatch(s);
  }

  Widget _renderTextWithLatex(String text, {TextStyle? style, Color? latexColor}) {
    final effectiveStyle = style ?? const TextStyle(fontSize: 15, color: Color(0xFF334155), height: 1.6);
    final effectiveLatexColor = latexColor ?? const Color(0xFF6366F1);

    if (!_hasLatex(text)) {
      return Text(text, style: effectiveStyle);
    }

    // Split by LaTeX segments
    final parts = <InlineSpan>[];
    final regex = RegExp(r'(\\[a-zA-Z]+(?:\{[^}]*\})*(?:\^{?[^}\s]+}?)?(?:_{?[^}\s]+}?)?|[_^]{[^}]+}|\{[^}]*\})');
    int lastEnd = 0;

    // Simple approach: if it looks mostly like LaTeX, render whole thing as LaTeX
    if (_hasLatex(text) && text.length < 200) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Math.tex(
          _cleanLatex(text),
          textStyle: TextStyle(fontSize: 18, color: effectiveLatexColor),
          onErrorFallback: (_) => Text(text, style: effectiveStyle),
        ),
      );
    }

    return Text(text, style: effectiveStyle);
  }

  // ═══════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final t = _topic;
    if (t == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Konu bulunamadı')));
    }

    if (_placementActive) return _buildPlacementScreen(t);
    return _buildMainScreen(t);
  }

  // ═══════════════════════════════════════════
  // PLACEMENT TEST SCREEN
  // ═══════════════════════════════════════════

  Widget _buildPlacementScreen(MasteryTopic t) {
    final levelLabels = ['Kolay', 'Orta', 'Zor'];
    final levelIcons = [Icons.sentiment_satisfied_rounded, Icons.psychology_rounded, Icons.local_fire_department_rounded];

    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFD),
      body: SafeArea(
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: const Color(0xFFF1F5F9)),
                  child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF475569))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Seviye Tespiti',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                    Text(t.title,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withAlpha(15),
                  borderRadius: BorderRadius.circular(99)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.bolt_rounded, size: 14, color: Color(0xFF6366F1)),
                  const SizedBox(width: 3),
                  Text('$_credits',
                    style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.w800, fontSize: 13)),
                ])),
            ]),
          ),

          // Step indicator
          if (!_placementDone)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: List.generate(3, (i) {
                  final isActive = i == _placementStep;
                  final isDone = i < _placementStep;
                  final c = isDone
                      ? const Color(0xFF22C55E)
                      : isActive
                          ? const Color(0xFF6366F1)
                          : const Color(0xFFCBD5E1);
                  return Expanded(
                    child: Container(
                      margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                      child: Column(children: [
                        Container(
                          height: 4,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(99),
                            color: c),
                        ),
                        const SizedBox(height: 6),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(
                            isDone ? Icons.check_circle_rounded : levelIcons[i],
                            size: 14, color: c),
                          const SizedBox(width: 4),
                          Text(levelLabels[i],
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
                        ]),
                      ]),
                    ),
                  );
                }),
              ),
            ),

          const SizedBox(height: 12),

          // Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
                : _showLevelAnimation
                    ? _buildLevelReveal()
                    : ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        children: [
                          // Question card with LaTeX
                          if (_question.isNotEmpty)
                            _buildQuestionCard(_question),

                          // Options
                          ..._buildOptions(),

                          // Feedback
                          if (_lastCorrect != null)
                            _buildFeedback(),

                          // Next button
                          if (_selectedOption != null && !_showLevelAnimation)
                            _buildNextButton(
                              onPressed: _nextPlacement,
                              label: _placementStep >= 2 ? 'Sonucu Gör' : 'Sonraki Soru',
                            ),
                        ],
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _buildLevelReveal() {
    final level = _detectedLevel ?? MasteryLevel.cirak;
    final color = _levelColor(level);
    final label = _levelLabel(level);
    final message = level == MasteryLevel.usta
        ? 'Harika! Zaten çok iyisin. Seni en zor sorulara alalım!'
        : level == MasteryLevel.kalfa
            ? 'Güzel! Temellerin sağlam. Uygulama aşamasından başlayalım!'
            : 'Merak etme, temelden başlayarak seni Usta yapacağız!';

    final targetLabel = level == MasteryLevel.usta
        ? 'Ustalaşmaya çok yakınsın!'
        : level == MasteryLevel.kalfa
            ? 'Seni Usta\'ya çıkaralım!'
            : 'Hedef: Usta seviyesi!';

    return AnimatedBuilder(
      animation: _levelAnimCtrl!,
      builder: (_, __) => Opacity(
        opacity: _levelAnimOpacity?.value ?? 1,
        child: Transform.scale(
          scale: _levelAnimScale?.value ?? 1,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Level icon
                Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [color, color.withAlpha(180)]),
                    boxShadow: [BoxShadow(color: color.withAlpha(60), blurRadius: 32, spreadRadius: 4)],
                  ),
                  child: Icon(
                    level == MasteryLevel.usta
                        ? Icons.workspace_premium_rounded
                        : level == MasteryLevel.kalfa
                            ? Icons.star_rounded
                            : Icons.school_rounded,
                    size: 48, color: Colors.white),
                ),
                const SizedBox(height: 24),

                // Result text
                Text('$_placementCorrect/3 Doğru',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
                const SizedBox(height: 8),
                Text('Şu an $label seviyesindesin',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: color.withAlpha(15),
                    borderRadius: BorderRadius.circular(99)),
                  child: Text(targetLabel,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
                ),
                const SizedBox(height: 16),
                Text(message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.grey.shade600, height: 1.5)),
                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity, height: 56,
                  child: FilledButton(
                    onPressed: _finishPlacement,
                    style: FilledButton.styleFrom(
                      backgroundColor: color,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                    child: const Text('Başlayalım!',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // MAIN LEARNING SCREEN
  // ═══════════════════════════════════════════

  Widget _buildMainScreen(MasteryTopic t) {
    final phase = t.activePhase;
    final lc = _levelColor(t.level);
    final tutorName = tutorNameForSubject(t.subject);
    final tutorAsset = tutorAssetForSubject(t.subject);

    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFD),
      body: SafeArea(
        child: Stack(
          children: [
            Column(children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: const Color(0xFFF1F5F9)),
                      child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF475569))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(t.title,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                  ),
                  if (t.streak > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFFF6B6B), Color(0xFFEE5A24)]),
                        borderRadius: BorderRadius.circular(99)),
                      child: Text('${t.streak} seri',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withAlpha(15),
                      borderRadius: BorderRadius.circular(99)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.bolt_rounded, size: 14, color: Color(0xFF6366F1)),
                      const SizedBox(width: 3),
                      Text('$_credits',
                        style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.w800, fontSize: 13)),
                    ])),
                ]),
              ),

              // Progress
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: t.overallProgress,
                          backgroundColor: const Color(0xFFEEF2F7),
                          valueColor: AlwaysStoppedAnimation(lc),
                          minHeight: 6)),
                    ),
                    const SizedBox(width: 10),
                    Text('${t.progressPercent}%',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: lc)),
                  ]),
                  const SizedBox(height: 4),
                  if (phase != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('${phase.title} — ${phase.questionsDone}/${phase.questionsTotal}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                    ),
                ]),
              ),

              // Tutor + Phase badge
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(children: [
                  // Tutor avatar
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF6366F1).withAlpha(30))),
                    child: ClipOval(
                      child: Image.asset(tutorAsset,
                        fit: BoxFit.cover, alignment: Alignment.topCenter,
                        errorBuilder: (_, __, ___) => Container(
                          color: const Color(0xFF6366F1).withAlpha(15),
                          child: const Icon(Icons.auto_awesome, size: 14, color: Color(0xFF6366F1))))),
                  ),
                  const SizedBox(width: 8),
                  Text(tutorName,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                  const Spacer(),
                  if (phase != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withAlpha(10),
                        borderRadius: BorderRadius.circular(10)),
                      child: Text(phase.title.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w800,
                          color: Color(0xFF6366F1), letterSpacing: 0.5)),
                    ),
                ]),
              ),

              const SizedBox(height: 12),

              // Content
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
                    : ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        children: [
                          // Explanation card with LaTeX
                          if (_explanation.isNotEmpty)
                            _buildExplanationCard(_explanation),

                          // Question card with LaTeX
                          if (_question.isNotEmpty)
                            _buildQuestionCard(_question),

                          // Options
                          ..._buildOptions(),

                          // Feedback
                          if (_lastCorrect != null)
                            _buildFeedback(),

                          // Next button
                          if (_selectedOption != null && !_showLevelAnimation)
                            _buildNextButton(onPressed: _next),
                        ],
                      ),
              ),
            ]),

            // Level-up overlay
            if (_showLevelAnimation && !_placementActive)
              _buildLevelUpOverlay(),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // SHARED UI COMPONENTS (with LaTeX support)
  // ═══════════════════════════════════════════

  Widget _buildExplanationCard(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEEF2F7)),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 8)]),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0EA5E9).withAlpha(15)),
            child: const Icon(Icons.lightbulb_outline_rounded, size: 16, color: Color(0xFF0EA5E9)),
          ),
          const SizedBox(width: 12),
          Expanded(child: _renderTextWithLatex(text,
            style: const TextStyle(fontSize: 15, color: Color(0xFF334155), height: 1.6))),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(String text) {
    final c = _stepColors[0];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c.withAlpha(8), const Color(0xFF8B5CF6).withAlpha(4)]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withAlpha(15))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_hasLatex(text)) ...[
            Text(
              _extractTextPart(text),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A), height: 1.5)),
            if (_extractLatexPart(text).isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: c.withAlpha(8),
                  borderRadius: BorderRadius.circular(12)),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Math.tex(
                    _cleanLatex(_extractLatexPart(text)),
                    textStyle: TextStyle(fontSize: 20, color: c),
                    onErrorFallback: (_) => Text(
                      _extractLatexPart(text),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c, fontFamily: 'monospace'))),
                ),
              ),
            ],
          ] else
            Text(text,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A), height: 1.5)),
        ],
      ),
    );
  }

  String _extractTextPart(String s) {
    // Try to separate natural text from LaTeX
    final cleaned = s.replaceAll(RegExp(r'\\[a-zA-Z]+\{[^}]*\}'), '').replaceAll(RegExp(r'[_^]\{[^}]*\}'), '').trim();
    if (cleaned.length > s.length * 0.3) return s; // Mostly text, return as-is
    return s;
  }

  String _extractLatexPart(String s) {
    final match = RegExp(r'(\\[a-zA-Z].*$|[_^]\{.*$)').firstMatch(s);
    return match?.group(0) ?? '';
  }

  List<Widget> _buildOptions() {
    return _options.asMap().entries.map((e) {
      final i = e.key;
      final opt = e.value;
      final letter = String.fromCharCode(65 + i);
      final selected = _selectedOption == i;
      final isCorrectAnswer = letter == _correctAnswer;

      Color bgColor = Colors.white;
      Color borderColor = const Color(0xFFEEF2F7);
      Color textColor = const Color(0xFF475569);
      Color letterBg = const Color(0xFFF1F5F9);
      Color letterColor = const Color(0xFF64748B);

      if (_selectedOption != null) {
        if (isCorrectAnswer) {
          bgColor = const Color(0xFF22C55E).withAlpha(10);
          borderColor = const Color(0xFF22C55E).withAlpha(40);
          textColor = const Color(0xFF166534);
          letterBg = const Color(0xFF22C55E);
          letterColor = Colors.white;
        } else if (selected && !isCorrectAnswer) {
          bgColor = const Color(0xFFEF4444).withAlpha(10);
          borderColor = const Color(0xFFEF4444).withAlpha(40);
          textColor = const Color(0xFF991B1B);
          letterBg = const Color(0xFFEF4444);
          letterColor = Colors.white;
        }
      }

      return GestureDetector(
        onTap: () {
          if (_placementActive) {
            _selectPlacementOption(i);
          } else {
            _selectOption(i);
          }
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
            boxShadow: selected != null && isCorrectAnswer
                ? [BoxShadow(color: const Color(0xFF22C55E).withAlpha(12), blurRadius: 8)]
                : null),
          child: Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: letterBg),
              child: Center(
                child: Text(letter,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: letterColor))),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _hasLatex(opt)
                  ? _renderTextWithLatex(opt,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor),
                      latexColor: textColor)
                  : Text(opt, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
            ),
            if (_selectedOption != null && isCorrectAnswer)
              const Icon(Icons.check_circle_rounded, size: 20, color: Color(0xFF22C55E)),
            if (selected && !isCorrectAnswer && _selectedOption != null)
              const Icon(Icons.cancel_rounded, size: 20, color: Color(0xFFEF4444)),
          ])),
      );
    }).toList();
  }

  Widget _buildFeedback() {
    final isCorrect = _lastCorrect ?? false;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: isCorrect
            ? [const Color(0xFF22C55E).withAlpha(8), const Color(0xFF16A34A).withAlpha(4)]
            : [const Color(0xFFEF4444).withAlpha(8), const Color(0xFFDC2626).withAlpha(4)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isCorrect
            ? const Color(0xFF22C55E).withAlpha(20) : const Color(0xFFEF4444).withAlpha(20))),
      child: Row(children: [
        Icon(
          isCorrect ? Icons.check_circle_rounded : Icons.info_rounded,
          color: isCorrect ? const Color(0xFF22C55E) : const Color(0xFFEF4444), size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            isCorrect ? 'Doğru! Harika gidiyorsun.' : 'Yanlış. Doğru cevap: $_correctAnswer',
            style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700,
              color: isCorrect ? const Color(0xFF166534) : const Color(0xFF991B1B))),
        ),
      ]),
    );
  }

  Widget _buildNextButton({required VoidCallback onPressed, String label = 'Devam Et'}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        width: double.infinity, height: 54,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
          child: Text(label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }

  Widget _buildLevelUpOverlay() {
    final level = _detectedLevel ?? MasteryLevel.cirak;
    final color = _levelColor(level);
    final label = _levelLabel(level);

    return AnimatedBuilder(
      animation: _levelAnimCtrl!,
      builder: (_, __) => Container(
        color: Colors.black.withAlpha((((_levelAnimOpacity?.value ?? 0) * 0.5) * 255).toInt()),
        child: Center(
          child: Opacity(
            opacity: _levelAnimOpacity?.value ?? 1,
            child: Transform.scale(
              scale: _levelAnimScale?.value ?? 1,
              child: Container(
                margin: const EdgeInsets.all(32),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [BoxShadow(color: color.withAlpha(40), blurRadius: 32, spreadRadius: 4)]),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [color, color.withAlpha(180)]),
                      boxShadow: [BoxShadow(color: color.withAlpha(50), blurRadius: 24)]),
                    child: const Icon(Icons.arrow_upward_rounded, size: 40, color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  Text('Seviye Atladın!',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
                  const SizedBox(height: 8),
                  Text('Artık $label seviyesindesin',
                    style: const TextStyle(fontSize: 16, color: Color(0xFF475569))),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity, height: 48,
                    child: FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        backgroundColor: color,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      child: const Text('Devam Et',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════

  Color _levelColor(MasteryLevel l) {
    switch (l) {
      case MasteryLevel.cirak: return const Color(0xFFF59E0B);
      case MasteryLevel.kalfa: return const Color(0xFF6366F1);
      case MasteryLevel.usta: return const Color(0xFF22C55E);
    }
  }

  String _levelLabel(MasteryLevel l) {
    switch (l) {
      case MasteryLevel.cirak: return 'Çırak';
      case MasteryLevel.kalfa: return 'Kalfa';
      case MasteryLevel.usta: return 'Usta';
    }
  }
}
