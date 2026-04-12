import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/koala_tokens.dart';
import '../helpers/auth_guard.dart';
import '../services/evlumba_live_service.dart';
import '../services/messaging_service.dart';
import '../services/saved_items_service.dart';
import '../widgets/chat/designer_chat_popup.dart';
import '../widgets/koala_widgets.dart';
import '../widgets/save_button.dart';
import 'chat_detail_screen.dart';

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
  bool showCategoryChips;
  final int replyKey;

  _ExpertTurn({
    required this.userMessage,
    required this.intent,
    required this.experts,
    required this.prompts,
    required this.assistantText,
    required this.isLoading,
    required this.isComplete,
    this.showCategoryChips = false,
    required this.replyKey,
  });
}

class DesignersScreen extends StatefulWidget {
  const DesignersScreen({super.key});

  @override
  State<DesignersScreen> createState() => _DesignersScreenState();
}

class _DesignersScreenState extends State<DesignersScreen> {
  // Chips are built dynamically from DB in _loadExperts
  List<_ExpertChip> _chips = <_ExpertChip>[];

  final TextEditingController _input = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ExpertPreview> _allExperts = <_ExpertPreview>[];
  final List<_ExpertTurn> _turns = <_ExpertTurn>[];

  // User's style preferences from style discovery
  String? _userStyle;
  String? _userRoom;
  String? _userBudget;
  List<String> _userColors = [];

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

    // Auth kontrolü — anonim kullanıcıyı giriş ekranına yönlendir
    if (!await ensureAuthenticated(context)) return;
    if (!mounted) return;

    // Popup ile sohbet aç (mevcut ekran kaybolmaz)
    DesignerChatPopup.show(
      context,
      designerId: designerId,
      designerName: name,
      designerAvatarUrl: expert.designer['avatar_url']?.toString(),
      contextType: 'designer',
      contextId: designerId,
      contextTitle: name,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadUserPreferences();
    _loadExperts();
  }

  Future<void> _loadUserPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _userStyle = prefs.getString('onb_style');
    _userRoom = prefs.getString('onb_room');
    _userBudget = prefs.getString('onb_budget');
    _userColors = prefs.getStringList('onb_colors') ?? [];
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
      // Yeterli havuz — tüm uzmanları görmek için
      final publishedProjects = await EvlumbaLiveService.getProjects(limit: 40);
      final projectsByDesigner = <String, List<Map<String, dynamic>>>{};
      for (final project in publishedProjects) {
        final designerId = (project['designer_id'] ?? '').toString().trim();
        if (designerId.isEmpty) continue;
        projectsByDesigner.putIfAbsent(designerId, () => <Map<String, dynamic>>[]).add(project);
      }

      // Tüm tasarımcıları yükle (12 ile sınırlama)
      final previews = await Future.wait(
        projectsByDesigner.entries.map((entry) async {
          final designerId = entry.key;
          final designer = await EvlumbaLiveService.getDesigner(designerId);
          if (designer == null) return null;
          final projects = List<Map<String, dynamic>>.from(entry.value);

          final rating = (designer['rating'] as num?)?.toDouble() ?? 0;
          final specialty = (designer['specialty'] ?? designer['about'] ?? '')
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

      final experts = previews.whereType<_ExpertPreview>().toList();

      // DB'deki gerçek specialty'lere göre chip oluştur
      final specialtyCounts = <String, int>{};
      for (final expert in experts) {
        final raw = (expert.designer['specialty'] ?? '').toString().trim();
        if (raw.isNotEmpty) {
          specialtyCounts[raw] = (specialtyCounts[raw] ?? 0) + 1;
        }
      }

      // DB'deki gerçek oda tiplerini say
      final roomCounts = <String, int>{};
      for (final project in publishedProjects) {
        final pt = (project['project_type'] ?? '').toString().trim();
        if (pt.isNotEmpty) {
          roomCounts[pt] = (roomCounts[pt] ?? 0) + 1;
        }
      }

      // Sadece gerçekten var olan specialty'leri chip yap (en az 3 uzman)
      final dynamicChips = <_ExpertChip>[];
      final sortedSpecialties = specialtyCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final entry in sortedSpecialties) {
        if (entry.value >= 3) {
          dynamicChips.add(_ExpertChip(entry.key, 'specialty:${entry.key}'));
        }
      }

      // Oda tipi chipsleri ekle (en az 5 proje olan)
      final roomLabels = <String, String>{
        'Yatak Odası': 'Yatak Odası',
        'Banyo': 'Banyo',
        'Oturma Odası': 'Salon',
        'Mutfak': 'Mutfak',
        'Antre': 'Antre',
      };
      final sortedRooms = roomCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final entry in sortedRooms) {
        if (entry.value >= 5) {
          final label = roomLabels[entry.key] ?? entry.key;
          dynamicChips.add(_ExpertChip(label, 'room:${entry.key}'));
        }
      }

      setState(() {
        _allExperts
          ..clear()
          ..addAll(experts);
        _chips = dynamicChips;
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

    // activeIntent'i modifier'sız sakla
    final baseIntent = intent.split('|').first;
    setState(() {
      _activeIntent = baseIntent;
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
    final rng = Random();

    // Modifier parse: "specialty:İç Mimar|exclude_prev" gibi
    final parts = intent.split('|');
    final baseIntent = parts.first;
    final excludePrev = parts.contains('exclude_prev');
    final topPortfolio = parts.contains('top_portfolio');

    // Intent türünü belirle: specialty: veya room: prefix'i
    final isSpecialtyFilter = baseIntent.startsWith('specialty:');
    final isRoomFilter = baseIntent.startsWith('room:');
    final filterValue = baseIntent.contains(':') ? baseIntent.split(':').last : baseIntent;

    // Oda adını style discovery key'ine çevir
    final roomMap = <String, String>{
      'Yatak Odası': 'yatak_odasi',
      'Banyo': 'banyo',
      'Oturma Odası': 'salon',
      'Mutfak': 'mutfak',
      'Antre': 'antre',
      'Salon': 'salon',
    };

    // 1) Filtreleme: chip'e göre aday havuzunu daralt
    List<_ExpertPreview> candidates;
    if (isSpecialtyFilter) {
      candidates = _allExperts.where((e) {
        final spec = (e.designer['specialty'] ?? '').toString().trim();
        return spec == filterValue;
      }).toList();
    } else if (isRoomFilter) {
      candidates = _allExperts.where((e) {
        return e.projects.any((p) =>
            (p['project_type'] ?? '').toString().trim() == filterValue);
      }).toList();
    } else {
      // Serbest metin araması
      final normalized = _normalize(intent);
      candidates = _allExperts.where((e) {
        final searchText = _normalize(
          '${e.designer['specialty'] ?? ''} ${e.designer['about'] ?? ''} '
          '${e.designer['city'] ?? ''} ${e.designer['full_name'] ?? ''}',
        );
        return searchText.contains(normalized);
      }).toList();
      if (candidates.isEmpty) candidates = List.from(_allExperts);
    }

    if (candidates.isEmpty) candidates = List.from(_allExperts);

    // "Başka uzmanlar göster" → önceki turn'daki uzmanları hariç tut
    if (excludePrev && _turns.length >= 2) {
      final prevTurn = _turns[_turns.length - 2];
      final prevIds = prevTurn.experts
          .map((e) => (e.designer['id'] ?? '').toString())
          .toSet();
      final filtered = candidates
          .where((e) => !prevIds.contains((e.designer['id'] ?? '').toString()))
          .toList();
      if (filtered.length >= 2) candidates = filtered;
    }

    // 2) Skorlama: kullanıcının zevkine göre sırala
    final scored = candidates.map((expert) {
      var score = 0.0;

      // Proje sayısı bonusu (daha fazla proje = daha güvenilir)
      score += expert.projects.length * 0.5;

      // Rating bonusu
      score += expert.rating * 2;

      // Kullanıcının tercih ettiği oda tipiyle eşleşme
      if (_userRoom != null && _userRoom!.isNotEmpty) {
        final userRoomKey = _userRoom!;
        final matchingRoomProjects = expert.projects.where((p) {
          final pt = (p['project_type'] ?? '').toString().trim();
          final ptKey = roomMap[pt] ?? pt.toLowerCase();
          return ptKey == userRoomKey || pt == userRoomKey;
        }).length;
        score += matchingRoomProjects * 3;
      }

      // Oda filtresi seçilmişse, o odada proje sayısına göre ekstra bonus
      if (isRoomFilter) {
        final roomProjects = expert.projects.where((p) =>
            (p['project_type'] ?? '').toString().trim() == filterValue).length;
        score += roomProjects * 2;
      }

      // "Portfolyosu en güçlü" → proje sayısı ağırlığını artır, rastgeleliği azalt
      if (topPortfolio) {
        score += expert.projects.length * 5;
        score += rng.nextDouble() * 0.5;
      } else {
        // Normal mod: küçük rastgelelik
        score += rng.nextDouble() * 2;
      }

      return MapEntry(expert, score);
    }).toList();

    // Skora göre azalan sırala
    scored.sort((a, b) => b.value.compareTo(a.value));

    return scored.take(4).map((e) => e.key).toList();
  }

  String _assistantReply(String intent, List<_ExpertPreview> experts) {
    if (experts.isEmpty) {
      return 'Sana uygun uzmanları henüz netleştiremedim. Biraz daha stil, bütçe ya da oda tipi söylersen daha iyi süzerim.';
    }

    final parts = intent.split('|');
    final baseIntent = parts.first;
    final excludePrev = parts.contains('exclude_prev');
    final topPortfolio = parts.contains('top_portfolio');

    final first = (experts.first.designer['full_name'] ?? 'ilk uzman').toString();
    final second = experts.length > 1
        ? (experts[1].designer['full_name'] ?? '').toString()
        : '';

    final isRoom = baseIntent.startsWith('room:');
    final isSpecialty = baseIntent.startsWith('specialty:');
    final filterValue = baseIntent.contains(':') ? baseIntent.split(':').last : baseIntent;

    // Kullanıcının stil profili varsa kişiselleştirilmiş mesaj
    final styleNote = _userStyle != null && _userStyle!.isNotEmpty
        ? ' Senin stil profiline göre en uyumlu olanları öne aldım.'
        : '';

    // Modifier'a göre özel cevaplar
    if (excludePrev) {
      return 'Farklı isimler getirdim: $first${second.isNotEmpty ? ' ve $second' : ''} bu sefer dikkatini çekebilir.$styleNote';
    }
    if (topPortfolio) {
      final topCount = experts.first.projects.length;
      return '$first $topCount projeyle en güçlü portfolyoya sahip.${second.isNotEmpty ? ' $second da yakın takipte.' : ''}$styleNote';
    }

    if (isRoom) {
      return second.isNotEmpty
          ? '$filterValue projeleriyle öne çıkan iki isim: $first ve $second.$styleNote'
          : '$filterValue tarafında ilk bakmanı istediğim uzman $first.$styleNote';
    }
    if (isSpecialty) {
      return second.isNotEmpty
          ? '$filterValue alanında güçlü iki isim: $first ve $second. Proje yoğunluğu ve portfolyo kalitesine göre seçtim.$styleNote'
          : '$filterValue alanında ilk bakmanı istediğim uzman $first.$styleNote';
    }
    return second.isNotEmpty
        ? 'Senin ihtiyacına göre önce $first ve $second dikkat çekiyor. Portfolyo dili ve proje yoğunluğu daha güçlü olanları öne aldım.$styleNote'
        : 'Senin ihtiyacına göre ilk bakmanı istediğim uzman $first.$styleNote';
  }

  List<String> _smartPrompts(String intent, List<_ExpertPreview> experts) {
    final parts = intent.split('|');
    final baseIntent = parts.first;
    final isRoom = baseIntent.startsWith('room:');
    final filterValue = baseIntent.contains(':') ? baseIntent.split(':').last : baseIntent;
    final hasProjects = experts.any((e) => e.projects.isNotEmpty);
    final alreadyExcluded = parts.contains('exclude_prev');
    final alreadyPortfolio = parts.contains('top_portfolio');

    final prompts = <String>[];

    // Her zaman "başka uzmanlar" sun (zaten farklıları hariç tutacak)
    if (!alreadyExcluded) {
      prompts.add('Başka uzmanlar göster');
    } else {
      prompts.add('Daha fazla uzman göster');
    }

    // Portfolyo önerisi — henüz seçilmediyse
    if (hasProjects && !alreadyPortfolio) {
      prompts.add('Portfolyosu en güçlü olanı çıkar');
    }

    // Oda bazlı öneriler: mevcut filtre oda değilse, ilgili odaları öner
    if (!isRoom && _chips.any((c) => c.keyword.startsWith('room:'))) {
      // Kullanıcının tercih ettiği oda varsa onu öner
      final roomLabels = {'salon': 'Salon', 'yatak_odasi': 'Yatak Odası', 'banyo': 'Banyo', 'mutfak': 'Mutfak'};
      if (_userRoom != null && roomLabels.containsKey(_userRoom)) {
        prompts.add('${roomLabels[_userRoom]} projeleri olan uzmanlar');
      }
    }

    // Oda filtresi seçiliyse specialty öner
    if (isRoom) {
      prompts.add('Bu alanda en deneyimli mimarlar');
    }

    // Her zaman kategori değiştirme seçeneği
    prompts.add('Başka kategori seçmek istiyorum');

    return prompts;
  }

  String? _resolveIntent(String text) {
    final normalized = _normalize(text);
    // Chip keyword'leri: specialty: veya room: prefix'li
    for (final chip in _chips) {
      final chipNorm = _normalize(chip.label);
      if (normalized.contains(chipNorm)) return chip.keyword;
    }
    // Genel arama terimleri
    if (normalized.contains('ic mim') || normalized.contains('mimar')) {
      return 'specialty:İç Mimar';
    }
    if (normalized.contains('banyo')) return 'room:Banyo';
    if (normalized.contains('mutfak')) return 'room:Mutfak';
    if (normalized.contains('salon') || normalized.contains('oturma')) {
      return 'room:Oturma Odası';
    }
    if (normalized.contains('yatak')) return 'room:Yatak Odası';
    return null;
  }

  void _submit() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    _startTurn(_resolveIntent(text) ?? _activeIntent ?? 'specialty:İç Mimar', text);
  }

  void _handlePrompt(String prompt) {
    if (prompt.contains('Başka kategori')) {
      HapticFeedback.lightImpact();
      final turn = _ExpertTurn(
        userMessage: prompt,
        intent: 'reset',
        experts: <_ExpertPreview>[],
        prompts: <String>[],
        assistantText: 'Tabii, hangi kategoriye bakmak istersin?',
        isLoading: false,
        isComplete: true,
        showCategoryChips: true,
        replyKey: _replyKey++,
      );
      setState(() {
        // _activeIntent'i null yapmıyoruz — üstteki chip'ler açılmasın
        _turns.add(turn);
      });
      _scrollToBottom();
      return;
    }

    // Özel komutları intent'e göm
    final intent = _activeIntent ?? 'specialty:İç Mimar';
    if (prompt.contains('Başka uzmanlar') || prompt.contains('Daha fazla uzman')) {
      _startTurn('$intent|exclude_prev', prompt);
    } else if (prompt.contains('Portfolyosu')) {
      _startTurn('$intent|top_portfolio', prompt);
    } else if (prompt.contains('projeleri olan uzmanlar')) {
      // "Salon projeleri olan uzmanlar" → oda filtresi
      final roomMap = {'Salon': 'Oturma Odası', 'Yatak Odası': 'Yatak Odası', 'Banyo': 'Banyo', 'Mutfak': 'Mutfak'};
      for (final entry in roomMap.entries) {
        if (prompt.contains(entry.key)) {
          _startTurn('room:${entry.value}', prompt);
          return;
        }
      }
      _startTurn(intent, prompt);
    } else if (prompt.contains('en deneyimli mimarlar')) {
      _startTurn('specialty:İç Mimar|top_portfolio', prompt);
    } else {
      _startTurn(intent, prompt);
    }
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
                      ? const LoadingState()
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
              // Kategori seçim chip'leri (inline, chat içinde)
              if (turn.showCategoryChips && isLast)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _chips.map((chip) {
                      return _ExpertQuickChip(
                        label: chip.label,
                        onTap: () => _startTurn(chip.keyword, chip.label),
                      );
                    }).toList(),
                  ),
                ),
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
              if (isLast && !turn.showCategoryChips)
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
                      color: KoalaColors.textSec.withValues(alpha: 0.72),
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
                              colors: [KoalaColors.accent, KoalaColors.accentDark],
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
          colors: [KoalaColors.accentDark, KoalaColors.accentDeep],
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
                          const Icon(Icons.star_rounded, size: 16, color: KoalaColors.star),
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

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'U';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: url.isEmpty ? const LinearGradient(colors: [_ExpertK.primary, Color(0xFF9B8AFF)]) : null,
        color: url.isNotEmpty ? null : null,
        image: url.isNotEmpty ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover) : null,
      ),
      alignment: Alignment.center,
      child: url.isEmpty
          ? Text(
              _initials,
              style: GoogleFonts.manrope(
                fontSize: size * 0.3,
                fontWeight: FontWeight.w800,
                color: Colors.white,
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
                                    const Icon(Icons.star_rounded, size: 16, color: KoalaColors.star),
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
                        color: KoalaColors.accentSoft,
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
                    color: KoalaColors.textSec.withValues(alpha: 0.72),
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
                    colors: [KoalaColors.accent, KoalaColors.accentDark],
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
