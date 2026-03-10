import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/config/env.dart';
import '../core/constants/lgs_math_learning_catalog.dart';
import '../core/constants/math_topic_catalog.dart';
import '../models/guided_lesson.dart';
import '../services/chatgpt_service.dart';
import '../services/credit_service.dart';
import '../services/did_service.dart';
import '../services/learning_resume_service.dart';
import '../services/supabase_storage_service.dart';
import '../widgets/did_video_view.dart';
import '../widgets/experience_ui.dart';
const String _kTutorAvatarUrl =
    'https://create-images-results.d-id.com/DefaultPresenters/Noelle_f/thumbnail.jpeg';
const String _kSelectedAvatarKey = 'lgs_math_selected_avatar_v3';
const String _kUnlockedAvatarsKey = 'lgs_math_unlocked_avatars_v3';
const int _kVideoCoachCreditCost = 12;

enum _CoachStage { discover, guided, practice, boss }

extension _CoachStageUi on _CoachStage {
  String get title => switch (this) {
    _CoachStage.discover => 'Fikri Yakala',
    _CoachStage.guided => 'Birlikte Çöz',
    _CoachStage.practice => 'Sıra Sende',
    _CoachStage.boss => 'Boss Soru',
  };

  String get subtitle => switch (this) {
    _CoachStage.discover => 'Konunun mantığını canlandır',
    _CoachStage.guided => 'Örnek üstünden akışı kur',
    _CoachStage.practice => 'Kontrollü deneme yap',
    _CoachStage.boss => 'Yeni nesil soru ile sabitle',
  };

  String get promptGoal => switch (this) {
    _CoachStage.discover => 'Kavramın sezgisini kur, sıkıcı olma.',
    _CoachStage.guided => 'Çözümü öğrenciyi de dahil ederek anlat.',
    _CoachStage.practice => 'Öğrenciye kısa bir deneme alanı aç.',
    _CoachStage.boss => 'Zorlayıcı ama öğretici bir son meydan okuma kur.',
  };

  IconData get icon => switch (this) {
    _CoachStage.discover => Icons.lightbulb_rounded,
    _CoachStage.guided => Icons.route_rounded,
    _CoachStage.practice => Icons.sports_score_rounded,
    _CoachStage.boss => Icons.emoji_events_rounded,
  };
}

class MathTutorScreen extends StatefulWidget {
  const MathTutorScreen({
    super.key,
    required this.examName,
    required this.subjectName,
    this.initialJourneyId,
    this.initialStageName,
  });

  final String examName;
  final String subjectName;
  final String? initialJourneyId;
  final String? initialStageName;

  @override
  State<MathTutorScreen> createState() => _MathTutorScreenState();
}

class _MathTutorScreenState extends State<MathTutorScreen> {
  final ChatGptService _chatGptService = ChatGptService();
  final DidService _didService = DidService();
  final SupabaseStorageService _storageService = SupabaseStorageService();
  final CreditService _creditService = CreditService();
  final LearningResumeService _resumeService = LearningResumeService();
  final TextEditingController _coachQuestionController =
      TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late final List<LgsMathJourney> _journeys;
  late LgsMathJourney _selectedJourney;

  final List<_CoachMessage> _messages = <_CoachMessage>[];
  final Map<String, GuidedLesson> _lessonCache = <String, GuidedLesson>{};
  final Map<String, Set<_CoachStage>> _completedStages =
      <String, Set<_CoachStage>>{};

  _CoachStage _activeStage = _CoachStage.discover;
  String? _selectedAvatarId;
  Set<String> _unlockedAvatarIds = <String>{'atlas'};
  int _credits = 0;
  bool _loadingCredits = true;
  bool _loadingLesson = false;
  bool _sendingQuestion = false;
  bool _videoCoachLoading = false;
  String? _lastApiError;
  String? _videoUrl;
  String? _tutorPublicUrl;

  static const List<_TutorAvatarOption> _avatarOptions = <_TutorAvatarOption>[
    _TutorAvatarOption(
      id: 'atlas',
      name: 'Atlas',
      role: 'Net anlatan ana koç',
      assetPath: 'assets/tutors/Matematik Man.png',
      unlockCost: 0,
      accent: AppColors.subjectMat,
    ),
    _TutorAvatarOption(
      id: 'mira',
      name: 'Mira',
      role: 'Geometri sezgisi güçlü koç',
      assetPath: 'assets/tutors/Fizik Woman.png',
      unlockCost: 18,
      accent: AppColors.subjectFizik,
    ),
    _TutorAvatarOption(
      id: 'nova',
      name: 'Nova',
      role: 'Hızlı tekrar ve boss soru koçu',
      assetPath: 'assets/tutors/Geometri Man.png',
      unlockCost: 30,
      accent: AppColors.teal,
    ),
  ];

  _TutorAvatarOption get _selectedAvatar {
    return _avatarOptions.firstWhere(
      (_TutorAvatarOption option) => option.id == _selectedAvatarId,
      orElse: () => _avatarOptions.first,
    );
  }

  String get _journeyKey => _selectedJourney.id;
  String get _lessonKey => '${_selectedJourney.id}_${_activeStage.name}';
  GuidedLesson? get _currentLesson => _lessonCache[_lessonKey];

  Set<_CoachStage> get _completedForSelectedJourney {
    return _completedStages[_journeyKey] ?? <_CoachStage>{};
  }

  double get _progressValue =>
      _completedForSelectedJourney.length / _CoachStage.values.length;

  int get _earnedXp =>
      (_selectedJourney.xpReward * _completedForSelectedJourney.length) ~/
      _CoachStage.values.length;

  @override
  void initState() {
    super.initState();
    _journeys = _buildJourneys();
    _selectedJourney = _resolveInitialJourney(widget.initialJourneyId);
    _activeStage = _stageFromName(widget.initialStageName);
    _loadStudioState();
    _loadResumeSelection();
    _loadCredits();
    _loadLesson();
    _persistLearningResume();
  }

  @override
  void dispose() {
    _coachQuestionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<LgsMathJourney> _buildJourneys() {
    if (widget.examName.trim() == 'LGS') {
      return LgsMathLearningCatalog.journeys;
    }

    final List<String> topics = MathTopicCatalog.topicsForExam(widget.examName);
    return List<LgsMathJourney>.generate(topics.length, (int index) {
      final String topic = topics[index];
      return LgsMathJourney(
        id: 'generic_$index',
        topicName: topic,
        heroName: topic,
        tagline: '$topic konusunu daha anlaşılır, kısa bloklarla çalış.',
        masteryGoal: '$topic sorularında işlem yerine mantığı oturt.',
        commonTrap:
            '$topic sorularında ilk bilgiyi yanlış okuyup akışı kaçırmak.',
        warmUpQuestion: '$topic için giriş seviyesinde bir örnekle başla.',
        bossQuestion: '$topic için zorlayıcı ama öğretici bir soru çöz.',
        skillChips: <String>['Temel mantık', 'Örnek soru', 'Mini tekrar'],
        quickPrompts: <String>[
          '$topic konusunu kısa anlat.',
          '$topic için bir örnek çöz.',
          '$topic için mini kontrol sorusu ver.',
        ],
        icon: Icons.auto_stories_rounded,
        accent: AppColors.subjectMat,
        xpReward: 80,
        difficulty: 2,
      );
    });
  }

  LgsMathJourney _resolveInitialJourney(String? journeyId) {
    if (journeyId == null || journeyId.isEmpty) {
      return _journeys.first;
    }
    for (final LgsMathJourney journey in _journeys) {
      if (journey.id == journeyId) {
        return journey;
      }
    }
    return _journeys.first;
  }

  _CoachStage _stageFromName(String? stageName) {
    if (stageName == null || stageName.isEmpty) {
      return _CoachStage.discover;
    }
    for (final _CoachStage stage in _CoachStage.values) {
      if (stage.name == stageName) {
        return stage;
      }
    }
    return _CoachStage.discover;
  }

  Future<void> _loadResumeSelection() async {
    if (widget.initialJourneyId != null) {
      return;
    }

    final LearningResumeSnapshot? snapshot = await _resumeService.load();
    if (snapshot == null ||
        snapshot.examName != widget.examName ||
        snapshot.subjectName != widget.subjectName ||
        !mounted) {
      return;
    }

    setState(() {
      _selectedJourney = _resolveInitialJourney(snapshot.journeyId);
      _activeStage = _stageFromName(snapshot.stageName);
    });
    if (_currentLesson == null) {
      await _loadLesson();
    }
  }

  Future<void> _persistLearningResume() {
    return _resumeService.save(
      LearningResumeSnapshot(
        examName: widget.examName,
        subjectName: widget.subjectName,
        journeyId: _selectedJourney.id,
        journeyName: _selectedJourney.heroName,
        stageName: _activeStage.name,
        progressPercent: (_progressValue * 100).round(),
        earnedXp: _earnedXp,
      ),
    );
  }

  Future<void> _loadStudioState() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? savedAvatar = prefs.getString(_kSelectedAvatarKey);
    final List<String> unlocked =
        prefs.getStringList(_kUnlockedAvatarsKey) ?? const <String>['atlas'];

    if (!mounted) {
      return;
    }
    setState(() {
      _selectedAvatarId = savedAvatar ?? 'atlas';
      _unlockedAvatarIds = unlocked.toSet()..add('atlas');
    });
    await _syncTutorAvatar();
  }

  Future<void> _saveAvatarState() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSelectedAvatarKey, _selectedAvatar.id);
    await prefs.setStringList(
      _kUnlockedAvatarsKey,
      _unlockedAvatarIds.toList(),
    );
  }

  Future<void> _loadCredits() async {
    final int credits = await _creditService.getCredits();
    if (!mounted) {
      return;
    }
    setState(() {
      _credits = credits;
      _loadingCredits = false;
    });
  }

  Future<void> _syncTutorAvatar() async {
    await _uploadTutorAvatar(_selectedAvatar.assetPath);
  }

  Future<void> _uploadTutorAvatar(String assetPath) async {
    try {
      final ByteData data = await rootBundle.load(assetPath);
      final Uint8List bytes = data.buffer.asUint8List();
      final String fileName = assetPath.split('/').last;
      final String url = await _storageService.uploadAvatarBytes(
        bytes: bytes,
        fileName: fileName,
      );
      if (mounted) {
        setState(() => _tutorPublicUrl = url);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _tutorPublicUrl = null);
      }
    }
  }

  Future<void> _loadLesson() async {
    if (_loadingLesson) {
      return;
    }

    setState(() {
      _loadingLesson = true;
      _lastApiError = null;
    });

    try {
      GuidedLesson lesson;
      if (Env.openAiApiKey.isEmpty && Env.geminiApiKey.isEmpty) {
        lesson = _buildOfflineLesson();
        _lastApiError =
            'API anahtarı yok. Şimdilik bu uygulamaya özel demo akışı gösteriliyor.';
      } else {
        final String raw = await _chatGptService.askConversation(
          systemPrompt: _lessonSystemPrompt,
          messages: <Map<String, String>>[
            <String, String>{'role': 'user', 'content': _buildLessonPrompt()},
          ],
        );
        lesson = GuidedLesson.fromJson(_extractJsonObject(raw));
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _lessonCache[_lessonKey] = lesson;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lessonCache[_lessonKey] = _buildOfflineLesson();
        _lastApiError = '$error';
      });
    } finally {
      if (mounted) {
        setState(() => _loadingLesson = false);
      }
    }
  }

  String get _lessonSystemPrompt => '''
Sen bu uygulamanın matematik koçusun.
Sıkıcı ders notu gibi konuşma. Öğrenciye küçük kazanımlar ver, sezgi kur, sonra örnek aç.
Her cevap Türkçe olsun.
8. sınıf öğrencisine göre yaz.
Sadece geçerli JSON döndür. Markdown, açıklama veya ekstra anahtar ekleme.
Şema:
{
  "title": "string",
  "opening": "string",
  "why_it_matters": "string",
  "coach_steps": ["string", "string", "string"],
  "challenge": "string",
  "checkpoint": "string",
  "watch_out": "string",
  "celebration": "string",
  "next_move": "string"
}
Kurallar:
- coach_steps her biri 1-2 cümle olsun.
- Öğrenciye hitap et.
- Yeni nesil soru mantığını ihmal etme.
- Ezber yerine mantık ve his oluştur.
''';

  String _buildLessonPrompt() {
    return '''
Sınav: ${widget.examName}
Branş: ${widget.subjectName}
Konu: ${_selectedJourney.topicName}
Konunun sahne adı: ${_selectedJourney.heroName}
Konu tonu: ${_selectedJourney.tagline}
Hedef kazanım: ${_selectedJourney.masteryGoal}
Yaygın tuzak: ${_selectedJourney.commonTrap}
Bu aşama: ${_activeStage.title}
Aşama amacı: ${_activeStage.promptGoal}
Başlangıç sorusu: ${_selectedJourney.warmUpQuestion}
Boss soru yönü: ${_selectedJourney.bossQuestion}
Hızlı odak etiketleri: ${_selectedJourney.skillChips.join(', ')}

Öğrenci bu ekranda gerçekten öğrendiğini hissetmeli. Bu yüzden:
1. opening kısmı merak uyandırsın.
2. why_it_matters kısmı neden öğrendiğini anlatsın.
3. challenge kısmı öğrenciyi denemeye itsin.
4. checkpoint kısmı tek kısa kontrol sorusu olsun.
5. celebration kısmı motive edici ama abartısız olsun.
''';
  }

  GuidedLesson _buildOfflineLesson() {
    final String stageHook = switch (_activeStage) {
      _CoachStage.discover =>
        'Bu turda önce konunun neden çalıştığını zihninde oturtacağız.',
      _CoachStage.guided =>
        'Şimdi çözüm akışını benimle birlikte kurup güven kazanacağız.',
      _CoachStage.practice =>
        'Bu kez top sende; ben yön vereceğim ama düşünmeyi sana bırakacağım.',
      _CoachStage.boss =>
        'Artık konu sıcak. Şimdi yeni nesil bir boss soruyla seviyeyi sabitleyelim.',
    };

    final List<String> steps = switch (_activeStage) {
      _CoachStage.discover => <String>[
        '${_selectedJourney.topicName} konusunu işlem kalıbı değil, ${_selectedJourney.masteryGoal.toLowerCase()} olarak düşün.',
        'İlk bakışta hangi bilgi anahtar, hangi bilgi dikkat dağıtıcı bunu ayır.',
        '${_selectedJourney.commonTrap} tuzağına düşmemek için çözümden önce kısa bir plan kur.',
      ],
      _CoachStage.guided => <String>[
        'Soruda senden ne istendiğini tek cümlede söyle.',
        'Verilen bilgilerden işe yarayanları sırala ve bir ara adım çıkar.',
        'Sonucu bulduktan sonra yeni nesil sorularda birim, yön ve yorum kontrolü yap.',
      ],
      _CoachStage.practice => <String>[
        'Ben sadece yönü söyleyeceğim: ilk adımda ilişkileri yaz.',
        'İkinci adımda işlemi değil mantığı kontrol et; neden o yöntemi seçtiğini söyle.',
        'Son adımda cevabını yorumlayıp yanlış yapmaya açık noktayı fark et.',
      ],
      _CoachStage.boss => <String>[
        'Boss soruda birden fazla fikir birleşir; bu yüzden önce soruyu parçala.',
        'Kolay parçayı çöz, sonra zor parçaya geri dön.',
        'Son kontrolde tuzak kelimeleri ve eksik yorum ihtimalini tara.',
      ],
    };

    return GuidedLesson(
      title: '${_activeStage.title} · ${_selectedJourney.heroName}',
      opening: stageHook,
      whyItMatters:
          'Bu konu LGS\'de sadece işlem için değil, düşünme ritmini kurmak için kritik. ${_selectedJourney.tagline}',
      coachSteps: steps,
      challenge: _activeStage == _CoachStage.boss
          ? _selectedJourney.bossQuestion
          : _selectedJourney.warmUpQuestion,
      checkpoint:
          '${_selectedJourney.topicName} çalışırken bugün aklında tutman gereken tek fikir ne?',
      watchOut: _selectedJourney.commonTrap,
      celebration:
          'Bir adımı temiz geçtiğinde konu gözünde küçülmeye başlar. Şu an tam o eşiği kuruyorsun.',
      nextMove: _activeStage == _CoachStage.boss
          ? 'İstersen şimdi koça kendi cümlenle takıldığın noktayı sor.'
          : 'Hazırsan bu adımı tamamlayıp bir sonraki göreve geç.',
    );
  }

  Map<String, dynamic> _extractJsonObject(String raw) {
    final String cleaned = raw.trim();
    final String withoutFence = cleaned
        .replaceAll(RegExp(r'^```json\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'^```\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*```$'), '')
        .trim();

    final Match? match = RegExp(r'\{[\s\S]*\}').firstMatch(withoutFence);
    final String candidate = match?.group(0) ?? withoutFence;
    final dynamic decoded = jsonDecode(candidate);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Model çıktısı JSON nesnesi değil.');
    }
    return decoded;
  }

  Future<void> _sendCoachQuestion({String? preset}) async {
    final String input = (preset ?? _coachQuestionController.text).trim();
    if (input.isEmpty || _sendingQuestion) {
      return;
    }

    setState(() {
      _sendingQuestion = true;
      _messages.add(_CoachMessage(role: 'user', text: input));
      if (preset != null) {
        _coachQuestionController.text = preset;
      }
    });

    String response;
    try {
      if (Env.openAiApiKey.isEmpty && Env.geminiApiKey.isEmpty) {
        response =
            'Kısa koç notu:\n- Bu soruyu ${_selectedJourney.topicName} mantığıyla parçalayalım.\n- Önce verilenleri netleştir.\n- Sonra hangi kuralın gerçekten işine yarayacağını seç.\n- İstersen şimdi tek bir adımını yaz, ben oradan devam edeyim.';
      } else {
        response = await _chatGptService.askConversation(
          systemPrompt:
              '''
Sen öğrenciyi sıkmadan konuya sokan bir matematik koçusun.
Türkçe yaz.
Kısa bloklar kullan.
Önce sezgi ver, sonra yön göster, en sonda mini kontrol sorusu sor.
Konu: ${_selectedJourney.topicName}
Aşama: ${_activeStage.title}
''',
          messages: _messages
              .map(
                (_CoachMessage message) => <String, String>{
                  'role': message.role,
                  'content': message.text,
                },
              )
              .toList(),
        );
      }
    } catch (error) {
      response =
          'Burada kısa bir koç molası verelim. Soruyu bir cümlede yeniden kur, sonra hangi bilginin asıl anahtar olduğunu beraber seçelim.';
      _lastApiError = '$error';
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _messages.add(_CoachMessage(role: 'assistant', text: response));
      _coachQuestionController.clear();
      _sendingQuestion = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _selectJourney(LgsMathJourney journey) {
    setState(() {
      _selectedJourney = journey;
      _activeStage = _CoachStage.discover;
    });
    _persistLearningResume();
    if (_currentLesson == null) {
      _loadLesson();
    }
  }

  void _selectStage(_CoachStage stage) {
    setState(() => _activeStage = stage);
    _persistLearningResume();
    if (_currentLesson == null) {
      _loadLesson();
    }
  }

  void _markStageCompleted() {
    final Set<_CoachStage> completed =
        _completedStages[_journeyKey] ?? <_CoachStage>{};
    if (completed.contains(_activeStage)) {
      return;
    }
    setState(() {
      completed.add(_activeStage);
      _completedStages[_journeyKey] = completed;
    });

    final int currentIndex = _CoachStage.values.indexOf(_activeStage);
    if (currentIndex < _CoachStage.values.length - 1) {
      setState(() => _activeStage = _CoachStage.values[currentIndex + 1]);
      if (_currentLesson == null) {
        _loadLesson();
      }
    }
    _persistLearningResume();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${_activeStage.title} tamamlandı. ${_selectedJourney.xpReward ~/ 4} XP kazandın.',
        ),
      ),
    );
  }

  Future<void> _showAvatarStudio() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: FrostedCard(
            radius: 32,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SectionHeading(
                      eyebrow: 'AVATAR STÜDYOSU',
                      title: 'Koçunu seç',
                      subtitle:
                          'Avatar hep ekranda durmak zorunda değil. Buradan seçilir, video koç çağrısında devreye girer.',
                    ),
                    const SizedBox(height: 16),
                    ..._avatarOptions.map((_TutorAvatarOption option) {
                      final bool unlocked = _unlockedAvatarIds.contains(
                        option.id,
                      );
                      final bool selected = option.id == _selectedAvatar.id;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: FrostedCard(
                          child: Row(
                            children: <Widget>[
                              _PortraitBadge(
                                assetPath: option.assetPath,
                                size: 68,
                                accent: option.accent,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        Expanded(
                                          child: Text(
                                            option.name,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleMedium,
                                          ),
                                        ),
                                        if (selected)
                                          const InfoPill(
                                            label: 'Seçili',
                                            backgroundColor:
                                                AppColors.brandLight,
                                            foregroundColor: AppColors.brand,
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      option.role,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      unlocked
                                          ? 'Kilidi açık'
                                          : '${option.unlockCost} kredi ile açılır',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(color: option.accent),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              FilledButton(
                                onPressed: () => _handleAvatarAction(option),
                                child: Text(
                                  unlocked
                                      ? (selected ? 'Seçili' : 'Seç')
                                      : 'Aç',
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleAvatarAction(_TutorAvatarOption option) async {
    if (_unlockedAvatarIds.contains(option.id)) {
      setState(() => _selectedAvatarId = option.id);
      await _saveAvatarState();
      await _syncTutorAvatar();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      return;
    }

    if (_credits < option.unlockCost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu avatarı açmak için daha fazla kredi gerekiyor.'),
        ),
      );
      return;
    }

    final int updated = await _creditService.spendCredits(option.unlockCost);
    setState(() {
      _credits = updated;
      _unlockedAvatarIds = <String>{..._unlockedAvatarIds, option.id};
      _selectedAvatarId = option.id;
    });
    await _saveAvatarState();
    await _syncTutorAvatar();

    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${option.name} koçu açıldı.')));
  }

  Future<void> _launchVideoCoach() async {
    if (_videoCoachLoading) {
      return;
    }
    if (_credits < _kVideoCoachCreditCost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Video koç açmak için en az 12 kredi gerekiyor.'),
        ),
      );
      return;
    }

    setState(() => _videoCoachLoading = true);
    try {
      final int updatedCredits = await _creditService.spendCredits(
        _kVideoCoachCreditCost,
      );
      final String avatarUrl = _tutorPublicUrl ?? _kTutorAvatarUrl;
      final GuidedLesson? lesson = _currentLesson;
      final String speechText = lesson == null
          ? '${_selectedJourney.topicName} için hazırım. Önce mantığı kuracağız, sonra seni kısa bir denemeye sokacağım.'
          : '${lesson.opening} Şimdi bir adım daha ilerleyelim. Kontrol sorum şu: ${lesson.checkpoint}';
      final String shortText = speechText.length > 220
          ? '${speechText.substring(0, 220)}...'
          : speechText;

      final String videoUrl = await _didService.createTalkingVideo(
        imageUrl: avatarUrl,
        text: shortText,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _credits = updatedCredits;
        _videoUrl = videoUrl;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Video koç başlatılamadı: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _videoCoachLoading = false);
      }
    }
  }

  void _closeVideoCoach() {
    setState(() => _videoUrl = null);
  }

  @override
  Widget build(BuildContext context) {
    final GuidedLesson? lesson = _currentLesson;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.examName} · Matematik Koçu'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: InfoPill(
                label: _loadingCredits ? '...' : '$_credits kredi',
                icon: Icons.bolt_rounded,
                backgroundColor: AppColors.brandLight,
                foregroundColor: AppColors.brand,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          AppBackdrop(
            primaryGlow: _selectedJourney.accent,
            secondaryGlow: AppColors.cyan,
            child: SafeArea(
              top: false,
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: <Widget>[
                  _CoachHero(
                    journey: _selectedJourney,
                    avatar: _selectedAvatar,
                    credits: _credits,
                    progressValue: _progressValue,
                    earnedXp: _earnedXp,
                    onAvatarTap: _showAvatarStudio,
                    onVideoCoachTap: _launchVideoCoach,
                    videoCoachLoading: _videoCoachLoading,
                  ),
                  if (_lastApiError != null) ...<Widget>[
                    const SizedBox(height: 14),
                    FrostedCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      color: AppColors.accentLight,
                      borderColor: AppColors.rose,
                      child: Text(
                        _lastApiError!,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: AppColors.ink),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SectionHeading(
                    eyebrow: 'KONU HARİTASI',
                    title: 'Konuyu ezbersiz değil, görev mantığıyla seç.',
                    subtitle:
                        'Kartlar artık düz konu listesi değil. Her biri ayrı beceri ve oyunlaştırılmış akış taşıyor.',
                  ),
                  const SizedBox(height: 14),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _journeys.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.95,
                        ),
                    itemBuilder: (_, int index) {
                      final LgsMathJourney journey = _journeys[index];
                      return _JourneyCard(
                        journey: journey,
                        selected: journey.id == _selectedJourney.id,
                        completedStages:
                            _completedStages[journey.id]?.length ?? 0,
                        onTap: () => _selectJourney(journey),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  SectionHeading(
                    eyebrow: 'BUGÜNKÜ ROTA',
                    title: '${_selectedJourney.heroName} için dört akıllı adım',
                    subtitle:
                        'Kunduz benzeri bir cevap hissi yerine, öğrenme ilerlemesini görünür kılan bir görev zinciri kurduk.',
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 126,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _CoachStage.values.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (_, int index) {
                        final _CoachStage stage = _CoachStage.values[index];
                        return _StageCard(
                          stage: stage,
                          accent: _selectedJourney.accent,
                          selected: stage == _activeStage,
                          completed: _completedForSelectedJourney.contains(
                            stage,
                          ),
                          onTap: () => _selectStage(stage),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  FrostedCard(
                    child: _loadingLesson
                        ? const SizedBox(
                            height: 220,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : lesson == null
                        ? _LessonEmptyState(onLoad: _loadLesson)
                        : _LessonPanel(
                            lesson: lesson,
                            journey: _selectedJourney,
                            stage: _activeStage,
                            accent: _selectedJourney.accent,
                            onReload: _loadLesson,
                            onComplete: _markStageCompleted,
                          ),
                  ),
                  const SizedBox(height: 24),
                  SectionHeading(
                    eyebrow: 'KOÇA SOR',
                    title: 'Takıldığın yeri kendi cümlenle aç.',
                    subtitle:
                        'Serbest soru alanı hâlâ var; ama artık ana deneyim değil, görev akışını tamamlayan destek katmanı.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _selectedJourney.quickPrompts.map((
                      String prompt,
                    ) {
                      return _QuickPromptChip(
                        label: prompt,
                        accent: _selectedJourney.accent,
                        onTap: () => _sendCoachQuestion(preset: prompt),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  FrostedCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        TextField(
                          controller: _coachQuestionController,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendCoachQuestion(),
                          decoration: InputDecoration(
                            labelText: 'Koça sor',
                            hintText:
                                '${_selectedJourney.topicName} konusunda takıldığın yeri yaz',
                            prefixIcon: const Icon(Icons.forum_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: _sendingQuestion
                                ? null
                                : () => _sendCoachQuestion(),
                            icon: _sendingQuestion
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded),
                            label: Text(
                              _sendingQuestion
                                  ? 'Gönderiliyor...'
                                  : 'Koçu Çağır',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_messages.isEmpty)
                    const _ChatEmptyState()
                  else
                    ..._messages.map((_CoachMessage message) {
                      final bool isUser = message.role == 'user';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Align(
                          alignment: isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 620),
                            child: FrostedCard(
                              padding: const EdgeInsets.all(16),
                              color: isUser
                                  ? AppColors.brandLight
                                  : AppColors.white.withValues(alpha: 0.9),
                              borderColor: isUser
                                  ? AppColors.brand.withValues(alpha: 0.16)
                                  : AppColors.white,
                              child: Text(
                                message.text,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: AppColors.textPrimary),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          if (_videoUrl != null || _videoCoachLoading)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.ink.withValues(alpha: 0.74),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: <Widget>[
                        Align(
                          alignment: Alignment.topRight,
                          child: IconButton(
                            onPressed: _closeVideoCoach,
                            icon: const Icon(Icons.close_rounded),
                            color: AppColors.white,
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: FrostedCard(
                              radius: 36,
                              color: AppColors.inkSoft.withValues(alpha: 0.84),
                              borderColor: AppColors.white.withValues(
                                alpha: 0.1,
                              ),
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      _PortraitBadge(
                                        assetPath: _selectedAvatar.assetPath,
                                        size: 64,
                                        accent: _selectedAvatar.accent,
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Text(
                                              '${_selectedAvatar.name} · Video Koç',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge
                                                  ?.copyWith(
                                                    color: AppColors.white,
                                                  ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _videoCoachLoading
                                                  ? 'Koç bağlanıyor...'
                                                  : 'Kısa bir odak konuşması ile seni derse geri sokuyor.',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                    color: AppColors.white
                                                        .withValues(alpha: 0.7),
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(28),
                                      child: _videoCoachLoading
                                          ? DecoratedBox(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: <Color>[
                                                    _selectedAvatar.accent
                                                        .withValues(alpha: 0.4),
                                                    AppColors.inkSoft,
                                                  ],
                                                ),
                                              ),
                                              child: const Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              ),
                                            )
                                          : DidVideoView(
                                              videoUrl: _videoUrl!,
                                              onEnded: _closeVideoCoach,
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CoachHero extends StatelessWidget {
  const _CoachHero({
    required this.journey,
    required this.avatar,
    required this.credits,
    required this.progressValue,
    required this.earnedXp,
    required this.onAvatarTap,
    required this.onVideoCoachTap,
    required this.videoCoachLoading,
  });

  final LgsMathJourney journey;
  final _TutorAvatarOption avatar;
  final int credits;
  final double progressValue;
  final int earnedXp;
  final VoidCallback onAvatarTap;
  final VoidCallback onVideoCoachTap;
  final bool videoCoachLoading;

  @override
  Widget build(BuildContext context) {
    return FrostedCard(
      padding: const EdgeInsets.all(0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(34),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              AppColors.ink,
              AppColors.inkSoft,
              journey.accent.withValues(alpha: 0.96),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const InfoPill(
                          label: 'LGS Matematik Koçu',
                          icon: Icons.psychology_alt_rounded,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          journey.heroName,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(color: AppColors.white),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          journey.topicName,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(color: AppColors.white),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          journey.tagline,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: AppColors.white.withValues(alpha: 0.74),
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    children: <Widget>[
                      _PortraitBadge(
                        assetPath: avatar.assetPath,
                        size: 86,
                        accent: avatar.accent,
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: onAvatarTap,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.white,
                          side: BorderSide(
                            color: AppColors.white.withValues(alpha: 0.14),
                          ),
                        ),
                        child: const Text('Avatar'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: journey.skillChips
                    .map((String chip) => InfoPill(label: chip))
                    .toList(),
              ),
              const SizedBox(height: 22),
              LinearProgressIndicator(
                value: progressValue,
                minHeight: 10,
                borderRadius: BorderRadius.circular(999),
                backgroundColor: AppColors.white.withValues(alpha: 0.16),
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.sun),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 20,
                runSpacing: 14,
                children: <Widget>[
                  HighlightMetric(
                    value: '${(progressValue * 100).round()}%',
                    label: 'rota ilerlemesi',
                    light: true,
                  ),
                  HighlightMetric(
                    value: '$earnedXp XP',
                    label: 'bugün kazanılan',
                    light: true,
                  ),
                  HighlightMetric(
                    value: '$credits',
                    label: 'mevcut kredi',
                    light: true,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: onVideoCoachTap,
                    icon: videoCoachLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.videocam_rounded),
                    label: const Text('Video Koç · 12 kredi'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onAvatarTap,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.white,
                      side: BorderSide(
                        color: AppColors.white.withValues(alpha: 0.14),
                      ),
                    ),
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('Avatar Stüdyosu'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({
    required this.journey,
    required this.selected,
    required this.completedStages,
    required this.onTap,
  });

  final LgsMathJourney journey;
  final bool selected;
  final int completedStages;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: selected
                  ? <Color>[
                      journey.accent,
                      journey.accent.withValues(alpha: 0.72),
                    ]
                  : <Color>[
                      AppColors.white,
                      journey.accent.withValues(alpha: 0.08),
                    ],
            ),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : journey.accent.withValues(alpha: 0.12),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: journey.accent.withValues(alpha: selected ? 0.22 : 0.08),
                blurRadius: 26,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.white.withValues(alpha: 0.16)
                            : journey.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        journey.icon,
                        color: selected ? AppColors.white : journey.accent,
                      ),
                    ),
                    const Spacer(),
                    InfoPill(
                      label: '$completedStages/4',
                      backgroundColor: selected
                          ? AppColors.white.withValues(alpha: 0.14)
                          : AppColors.brandLight,
                      foregroundColor: selected
                          ? AppColors.white
                          : AppColors.brand,
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  journey.heroName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: selected ? AppColors.white : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  journey.topicName,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: selected
                        ? AppColors.white.withValues(alpha: 0.92)
                        : journey.accent,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  journey.masteryGoal,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: selected
                        ? AppColors.white.withValues(alpha: 0.74)
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Text(
                      '${journey.xpReward} XP',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: selected
                            ? AppColors.white
                            : AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    ...List<Widget>.generate(journey.difficulty, (int index) {
                      return Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(
                          Icons.flash_on_rounded,
                          size: 16,
                          color: selected
                              ? AppColors.sun
                              : journey.accent.withValues(alpha: 0.8),
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StageCard extends StatelessWidget {
  const _StageCard({
    required this.stage,
    required this.accent,
    required this.selected,
    required this.completed,
    required this.onTap,
  });

  final _CoachStage stage;
  final Color accent;
  final bool selected;
  final bool completed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: FrostedCard(
        onTap: onTap,
        color: selected
            ? accent.withValues(alpha: 0.16)
            : AppColors.white.withValues(alpha: 0.86),
        borderColor: selected ? accent : AppColors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: selected
                        ? accent.withValues(alpha: 0.16)
                        : AppColors.brandLight,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    completed ? Icons.check_rounded : stage.icon,
                    color: accent,
                  ),
                ),
                const Spacer(),
                if (completed)
                  const InfoPill(
                    label: 'Tamam',
                    backgroundColor: AppColors.successLight,
                    foregroundColor: AppColors.success,
                  ),
              ],
            ),
            const Spacer(),
            Text(stage.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(stage.subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _LessonPanel extends StatelessWidget {
  const _LessonPanel({
    required this.lesson,
    required this.journey,
    required this.stage,
    required this.accent,
    required this.onReload,
    required this.onComplete,
  });

  final GuidedLesson lesson;
  final LgsMathJourney journey;
  final _CoachStage stage;
  final Color accent;
  final Future<void> Function() onReload;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  InfoPill(
                    label: stage.title,
                    icon: stage.icon,
                    backgroundColor: accent.withValues(alpha: 0.12),
                    foregroundColor: accent,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    lesson.title.isEmpty ? journey.heroName : lesson.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    lesson.opening,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filledTonal(
              onPressed: onReload,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _LessonInsightCard(
          title: 'Neden önemli?',
          description: lesson.whyItMatters,
          accent: accent,
          icon: Icons.visibility_rounded,
        ),
        const SizedBox(height: 12),
        ...List<Widget>.generate(lesson.coachSteps.length, (int index) {
          final String step = lesson.coachSteps[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FrostedCard(
              color: AppColors.white.withValues(alpha: 0.9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: Theme.of(
                          context,
                        ).textTheme.titleSmall?.copyWith(color: accent),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      step,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        _LessonInsightCard(
          title: 'Mini meydan okuma',
          description: lesson.challenge,
          accent: AppColors.accent,
          icon: Icons.sports_score_rounded,
        ),
        const SizedBox(height: 12),
        _LessonInsightCard(
          title: 'Dikkat et',
          description: lesson.watchOut,
          accent: AppColors.warning,
          icon: Icons.warning_amber_rounded,
        ),
        const SizedBox(height: 12),
        _LessonInsightCard(
          title: 'Kontrol sorusu',
          description: lesson.checkpoint,
          accent: AppColors.teal,
          icon: Icons.help_center_rounded,
        ),
        const SizedBox(height: 16),
        Text(
          lesson.celebration,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),
        Text(lesson.nextMove, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            FilledButton.icon(
              onPressed: onComplete,
              icon: const Icon(Icons.check_circle_rounded),
              label: const Text('Bu Adımı Tamamladım'),
            ),
            OutlinedButton.icon(
              onPressed: onReload,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('Bu Adımı Yeniden Kur'),
            ),
          ],
        ),
      ],
    );
  }
}

class _LessonInsightCard extends StatelessWidget {
  const _LessonInsightCard({
    required this.title,
    required this.description,
    required this.accent,
    required this.icon,
  });

  final String title;
  final String description;
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return FrostedCard(
      color: accent.withValues(alpha: 0.08),
      borderColor: accent.withValues(alpha: 0.12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickPromptChip extends StatelessWidget {
  const _QuickPromptChip({
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: accent.withValues(alpha: 0.14)),
          ),
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: accent),
          ),
        ),
      ),
    );
  }
}

class _ChatEmptyState extends StatelessWidget {
  const _ChatEmptyState();

  @override
  Widget build(BuildContext context) {
    return FrostedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Koç alanı boş', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Önce hızlı promptlardan birine dokun ya da kendi cümlenle nerede takıldığını yaz. Sistem seni doğrudan görev mantığı içinden yanıtlayacak.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _LessonEmptyState extends StatelessWidget {
  const _LessonEmptyState({required this.onLoad});

  final Future<void> Function() onLoad;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          'Bu adım henüz üretilmedi.',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Görev mantığını kurmak için bu aşamayı başlat. Sistem, konuya özel yapılandırılmış öğretim kartları üretecek.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: onLoad,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Aşamayı Başlat'),
        ),
      ],
    );
  }
}

class _PortraitBadge extends StatelessWidget {
  const _PortraitBadge({
    required this.assetPath,
    required this.size,
    required this.accent,
  });

  final String assetPath;
  final double size;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: <Color>[
            accent.withValues(alpha: 0.38),
            accent.withValues(alpha: 0.05),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: CircleAvatar(
        backgroundColor: AppColors.surface,
        child: ClipOval(
          child: Image.asset(
            assetPath,
            width: size,
            height: size,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (_, _, _) =>
                Icon(Icons.person_rounded, color: accent, size: size * 0.42),
          ),
        ),
      ),
    );
  }
}

class _TutorAvatarOption {
  const _TutorAvatarOption({
    required this.id,
    required this.name,
    required this.role,
    required this.assetPath,
    required this.unlockCost,
    required this.accent,
  });

  final String id;
  final String name;
  final String role;
  final String assetPath;
  final int unlockCost;
  final Color accent;
}

class _CoachMessage {
  const _CoachMessage({required this.role, required this.text});

  final String role;
  final String text;
}
