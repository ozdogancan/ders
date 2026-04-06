import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../core/config/env.dart';

class StyleDiscoveryScreen extends StatefulWidget {
  const StyleDiscoveryScreen({super.key, this.entryPoint = 'first_run'});

  final String entryPoint;

  @override
  State<StyleDiscoveryScreen> createState() => _StyleDiscoveryScreenState();
}

class _StyleDiscoveryScreenState extends State<StyleDiscoveryScreen>
    with TickerProviderStateMixin {
  static const int _minShownBeforeFinish = 6;
  static const int _targetLikes = 3;
  static const int _maxCardsToShow = 10;
  static const int _explorationPhase = 5; // ilk 5 kart keşif

  final List<_DiscoveryCard> _pool = _buildFullPool();
  late final List<_DiscoveryCard> _deck;
  bool _deckAdapted = false;
  final Set<String> _likedIds = <String>{};
  final Map<String, double> _styleScores = <String, double>{};
  final Map<String, double> _roomScores = <String, double>{};
  final Map<String, double> _colorScores = <String, double>{};
  final Map<String, double> _budgetScores = <String, double>{};
  final List<_SwipeRecord> _swipeHistory = <_SwipeRecord>[];

  int _index = 0;
  double _dragDx = 0;
  double _dragDy = 0;
  bool _leaving = false;
  bool _didPrefetch = false;
  bool _showTutorial = true;

  late final AnimationController _swipeExitController;
  late final AnimationController _entryController;
  late final AnimationController _pulseController;
  _DiscoveryCard? _animatingCard;
  bool _animatingLike = false;
  double _animatingVelocity = 0;
  double _exitStartDx = 0;
  double _exitTargetDx = 0;

  int get _shownCount => math.min(_index + 1, _deck.length);
  int get _likesCount => _likedIds.length;

  _DiscoveryCard? get _currentCard =>
      _index < _deck.length ? _deck[_index] : null;
  bool get _isSwipeAnimating => _swipeExitController.isAnimating;

  bool get _hasEnoughSignal {
    if (_shownCount < _minShownBeforeFinish || _likesCount < _targetLikes) {
      return false;
    }
    return _topStyleShare() >= 0.5;
  }

  bool get _shouldShowFinishCta {
    if (_likesCount == 0) return false;
    if (_hasEnoughSignal) return true;
    if (_shownCount >= _maxCardsToShow) return true;
    return false;
  }

  /// İlk 5 kart: her ana stilden birer tane (maksimum çeşitlilik).
  List<_DiscoveryCard> _buildInitialDeck() {
    final seen = <String>{};
    final initial = <_DiscoveryCard>[];
    for (final card in _pool) {
      if (seen.contains(card.style)) continue;
      seen.add(card.style);
      initial.add(card);
      if (initial.length >= _explorationPhase) break;
    }
    return initial;
  }

  /// 5. karttan sonra çağrılır. Beğenilen stillere yakın kartları havuzdan seçer.
  void _adaptDeck() {
    if (_deckAdapted) return;
    _deckAdapted = true;

    final shownIds = _deck.map((c) => c.id).toSet();
    final remaining = _pool.where((c) => !shownIds.contains(c.id)).toList();

    if (remaining.isEmpty) return;

    // Her karta beğenilere göre skor ver
    final scored = remaining.map((card) {
      double score = 0;
      score += (_styleScores[card.style] ?? 0) * 2.0;   // stil en önemli
      score += (_roomScores[card.room] ?? 0) * 1.0;     // oda tercihi
      score += (_budgetScores[card.budget] ?? 0) * 0.5;  // bütçe
      for (final color in card.colors) {
        score += (_colorScores[color] ?? 0) * 0.3;       // renkler
      }
      return MapEntry(card, score);
    }).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // En yüksek skorlu 5 kartı (veya kalan kadar) ekle
    final adaptiveCards = scored
        .take(_maxCardsToShow - _deck.length)
        .map((e) => e.key)
        .toList();

    _deck.addAll(adaptiveCards);
  }

  @override
  void initState() {
    super.initState();
    _deck = _buildInitialDeck();
    _swipeExitController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 300),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _completeAnimatedSwipe();
          }
        });
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didPrefetch) return;
    _didPrefetch = true;
    for (int i = 0; i < _deck.length && i < 4; i++) {
      if (_deck[i].imageUrl.isNotEmpty) {
        precacheImage(CachedNetworkImageProvider(_deck[i].imageUrl), context);
      }
    }
  }

  void _prefetchAhead() {
    for (int i = _index + 1; i <= _index + 2 && i < _deck.length; i++) {
      if (_deck[i].imageUrl.isNotEmpty) {
        precacheImage(CachedNetworkImageProvider(_deck[i].imageUrl), context);
      }
    }
  }

  @override
  void dispose() {
    _swipeExitController.dispose();
    _entryController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _handleSkip() async {
    if (_leaving) return;
    _leaving = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('style_discovery_prompted', true);
    await prefs.setBool('style_discovery_completed', false);
    if (!mounted) return;
    Navigator.of(context).pop('skipped');
  }

  Future<void> _handleSwipe(bool liked, {double velocity = 0}) async {
    final card = _currentCard;
    if (_leaving || card == null || _isSwipeAnimating) return;
    HapticFeedback.mediumImpact();
    final width = MediaQuery.of(context).size.width;
    _animatingCard = card;
    _animatingLike = liked;
    _animatingVelocity = velocity.abs();
    _exitStartDx = _dragDx.abs() < 24 ? (liked ? 24 : -24) : _dragDx;
    _exitTargetDx = width * (liked ? 1.4 : -1.4);
    setState(() {});
    await _swipeExitController.forward(from: 0);
  }

  /// Maps velocity (px/s) to a confidence multiplier.
  /// Button tap (0 velocity) = 1.0, slow drag = 0.7, fast flick = 1.3
  double _velocityMultiplier(double absVelocity) {
    if (absVelocity < 200) return 1.0;   // button tap or very slow
    if (absVelocity < 500) return 0.7;   // slow / hesitant drag
    if (absVelocity < 1000) return 1.0;  // normal swipe
    return 1.3;                          // fast decisive flick
  }

  Future<void> _completeAnimatedSwipe() async {
    final card = _animatingCard;
    if (card == null) return;
    final multiplier = _velocityMultiplier(_animatingVelocity);
    final weight = ((_animatingLike ? 1.0 : -0.3) * multiplier);
    _swipeHistory.add(_SwipeRecord(card: card, liked: _animatingLike, weight: weight));
    _applySignal(card, liked: _animatingLike, weight: weight);
    if (!mounted) return;

    // Keşif fazı bitti mi? → deck'i adapte et
    if (_index + 1 >= _explorationPhase && !_deckAdapted) {
      _adaptDeck();
    }

    setState(() {
      _dragDx = 0;
      _dragDy = 0;
      _index++;
      _animatingCard = null;
      _exitStartDx = 0;
      _exitTargetDx = 0;
      _swipeExitController.reset();
    });
    _prefetchAhead();
    if (_index >= _deck.length && mounted) {
      await _finish();
    }
  }

  void _applySignal(_DiscoveryCard card, {required bool liked, required double weight}) {
    if (liked) _likedIds.add(card.id);
    _styleScores.update(card.style, (v) => v + weight, ifAbsent: () => weight);
    _roomScores.update(card.room, (v) => v + weight, ifAbsent: () => weight);
    _budgetScores.update(
      card.budget,
      (v) => v + weight,
      ifAbsent: () => weight,
    );
    for (final color in card.colors) {
      _colorScores.update(color, (v) => v + weight, ifAbsent: () => weight);
    }
  }

  void _reverseSignal(_DiscoveryCard card, {required bool liked, required double weight}) {
    if (liked) _likedIds.remove(card.id);
    _styleScores.update(card.style, (v) => v - weight, ifAbsent: () => 0);
    _roomScores.update(card.room, (v) => v - weight, ifAbsent: () => 0);
    _budgetScores.update(card.budget, (v) => v - weight, ifAbsent: () => 0);
    for (final color in card.colors) {
      _colorScores.update(color, (v) => v - weight, ifAbsent: () => 0);
    }
  }

  void _undo() {
    if (_swipeHistory.isEmpty || _isSwipeAnimating || _leaving) return;
    HapticFeedback.lightImpact();
    final last = _swipeHistory.removeLast();
    _reverseSignal(last.card, liked: last.liked, weight: last.weight);
    setState(() {
      _index--;
      _dragDx = 0;
      _dragDy = 0;
    });
  }

  double _topStyleShare() {
    if (_likesCount == 0) return 0;
    final positives = _styleScores.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (positives.isEmpty) return 0;
    return positives.first.value / _likesCount;
  }

  List<String> _sortedPositiveKeys(Map<String, double> scores) {
    final entries = scores.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((e) => e.key).toList();
  }

  List<String> _sortedNegativeKeys(Map<String, double> scores) {
    final entries = scores.entries.where((e) => e.value < 0).toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return entries.map((e) => e.key).toList();
  }

  Map<String, dynamic> _buildProfile() {
    final styles = _sortedPositiveKeys(_styleScores);
    final rooms = _sortedPositiveKeys(_roomScores);
    final budgets = _sortedPositiveKeys(_budgetScores);
    final colors = _sortedPositiveKeys(_colorScores).take(3).toList();

    final dislikedStyles = _sortedNegativeKeys(_styleScores);
    final dislikedColors = _sortedNegativeKeys(_colorScores);

    final likedDetails = _deck
        .where((c) => _likedIds.contains(c.id))
        .map((c) => <String, dynamic>{
              'title': c.title,
              'style': c.styleLabel,
              'room': c.roomLabel,
              'colors': c.colors,
              'budget': c.budgetLabel,
              'subtitle': c.subtitle,
            })
        .toList();

    return <String, dynamic>{
      'primary_style': styles.isNotEmpty ? styles.first : null,
      'secondary_style': styles.length > 1 ? styles[1] : null,
      'preferred_room': rooms.isNotEmpty ? rooms.first : null,
      'budget_band': budgets.isNotEmpty ? budgets.first : null,
      'preferred_colors': colors,
      'disliked_styles': dislikedStyles,
      'disliked_colors': dislikedColors,
      'liked_card_ids': _likedIds.toList(),
      'liked_details': likedDetails,
      'likes_count': _likesCount,
      'shown_count': _shownCount,
      'entry_point': widget.entryPoint,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _finish() async {
    if (_leaving) return;
    _leaving = true;
    final profile = _buildProfile();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('style_discovery_prompted', true);
    await prefs.setBool('style_discovery_completed', true);
    await prefs.setString('koala_style_profile', jsonEncode(profile));

    final primaryStyle = profile['primary_style'] as String?;
    final preferredRoom = profile['preferred_room'] as String?;
    final budgetBand = profile['budget_band'] as String?;
    final colors = (profile['preferred_colors'] as List<dynamic>? ?? [])
        .cast<String>();

    if (primaryStyle != null && primaryStyle.isNotEmpty) {
      await prefs.setString('onb_style', primaryStyle);
    }
    if (preferredRoom != null && preferredRoom.isNotEmpty) {
      await prefs.setString('onb_room', preferredRoom);
    }
    if (budgetBand != null && budgetBand.isNotEmpty) {
      await prefs.setString('onb_budget', budgetBand);
    }
    if (colors.isNotEmpty) {
      await prefs.setStringList('onb_colors', colors);
    }
    final dislikedStyles = (profile['disliked_styles'] as List<dynamic>? ?? [])
        .cast<String>();
    if (dislikedStyles.isNotEmpty) {
      await prefs.setStringList('onb_disliked_styles', dislikedStyles);
    }
    final dislikedColors = (profile['disliked_colors'] as List<dynamic>? ?? [])
        .cast<String>();
    if (dislikedColors.isNotEmpty) {
      await prefs.setStringList('onb_disliked_colors', dislikedColors);
    }

    await _syncProfile(profile);

    if (!mounted) return;
    Navigator.of(context).pop('completed');
  }

  Future<void> _syncProfile(Map<String, dynamic> profile) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !Env.hasSupabaseConfig) return;
    try {
      await Supabase.instance.client
          .from('users')
          .update({
            'style_preference': profile['primary_style'],
            'color_preferences': profile['preferred_colors'],
            'preferred_room': profile['preferred_room'],
            'budget_range': profile['budget_band'],
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', uid);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final card = _animatingCard ?? _currentCard;
    final mq = MediaQuery.of(context);
    final width = mq.size.width;
    final bottomPad = mq.padding.bottom;

    final animatedDx = _isSwipeAnimating
        ? lerpDouble(
                _exitStartDx,
                _exitTargetDx,
                Curves.easeOutCubic.transform(_swipeExitController.value),
              ) ??
              _dragDx
        : _dragDx;
    final swipeRatio = (animatedDx / (width * 0.35)).clamp(-1.0, 1.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F5F0),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ── Header ──
              FadeTransition(
                opacity: CurvedAnimation(
                  parent: _entryController,
                  curve: const Interval(0, 0.5, curve: Curves.easeOut),
                ),
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -0.3),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: _entryController,
                    curve: const Interval(0, 0.5, curve: Curves.easeOut),
                  )),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF7C6EF2), Color(0xFF6C5CE7)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.auto_awesome_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tarzını Keşfedelim',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1A1D2A),
                                  letterSpacing: -0.3,
                                ),
                              ),
                              SizedBox(height: 1),
                              Text(
                                'Beğendiğin mekanları sağa kaydır',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF8E8A96),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _handleSkip,
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF8E8A96),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          child: const Text(
                            'Atla',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Progress ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 4,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: Stack(
                            children: [
                              Container(
                                color: const Color(0xFFE8E3DC),
                              ),
                              FractionallySizedBox(
                                widthFactor:
                                    (_shownCount / _maxCardsToShow).clamp(0, 1),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(99),
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF7C6EF2),
                                        Color(0xFF6C5CE7),
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
                    const SizedBox(width: 12),
                    Text(
                      '$_shownCount/$_maxCardsToShow',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFAEA8B8),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Card Stack ──
              Expanded(
                child: FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _entryController,
                    curve: const Interval(0.2, 0.8, curve: Curves.easeOut),
                  ),
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.15),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: _entryController,
                      curve: const Interval(0.2, 0.8, curve: Curves.easeOut),
                    )),
                    child: card == null
                        ? _DoneState(
                            onFinish: _finish,
                            title: _likesCount == 0
                                ? 'Sohbette netleştiririz'
                                : 'Harika, tarzını anladık!',
                            body: _likesCount == 0
                                ? 'Kartları atladın ama sorun yok.\nSohbette birlikte keşfederiz.'
                                : 'Koala artık sana en uygun\nönerileri hazırlayacak.',
                            likesCount: _likesCount,
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    // Next card (only one behind)
                                    if (_index + 1 < _deck.length)
                                      Positioned.fill(
                                        top: 8,
                                        left: 8,
                                        right: 8,
                                        child: _DiscoveryCardView(
                                          card: _deck[_index + 1],
                                          offset: Offset.zero,
                                          rotation: 0,
                                          scale: 0.96,
                                          likeOpacity: 0,
                                          nopeOpacity: 0,
                                          dimmed: true,
                                        ),
                                      ),
                                    // Current card
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onPanUpdate: (details) {
                                        if (_isSwipeAnimating) return;
                                        setState(() {
                                          _showTutorial = false;
                                          _dragDx += details.delta.dx;
                                          _dragDy += details.delta.dy * 0.3;
                                        });
                                      },
                                      onPanEnd: (details) {
                                        if (_isSwipeAnimating) return;
                                        final velocity =
                                            details.velocity.pixelsPerSecond.dx;
                                        if (_dragDx > 90 || velocity > 700) {
                                          _handleSwipe(true, velocity: velocity);
                                          return;
                                        }
                                        if (_dragDx < -90 || velocity < -700) {
                                          _handleSwipe(false, velocity: velocity);
                                          return;
                                        }
                                        setState(() {
                                          _dragDx = 0;
                                          _dragDy = 0;
                                        });
                                      },
                                      child: _DiscoveryCardView(
                                        card: card,
                                        offset: Offset(
                                          animatedDx,
                                          _isSwipeAnimating
                                              ? _dragDy *
                                                  (1 -
                                                      _swipeExitController
                                                          .value)
                                              : _dragDy,
                                        ),
                                        rotation: animatedDx / 600,
                                        scale: 1,
                                        likeOpacity: swipeRatio > 0
                                            ? swipeRatio.abs()
                                            : 0,
                                        nopeOpacity: swipeRatio < 0
                                            ? swipeRatio.abs()
                                            : 0,
                                        dimmed: false,
                                      ),
                                    ),
                                    // Tutorial overlay
                                    if (_showTutorial && _index == 0)
                                      Positioned.fill(
                                        child: GestureDetector(
                                          onTap: () => setState(() => _showTutorial = false),
                                          child: AnimatedOpacity(
                                            opacity: _showTutorial ? 1.0 : 0.0,
                                            duration: const Duration(milliseconds: 300),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(24),
                                                color: Colors.black.withValues(alpha: 0.55),
                                              ),
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                    children: [
                                                      _TutorialHint(
                                                        icon: Icons.arrow_back_rounded,
                                                        label: 'PAS',
                                                        color: const Color(0xFFE26257),
                                                      ),
                                                      _TutorialHint(
                                                        icon: Icons.arrow_forward_rounded,
                                                        label: 'SEVERiM',
                                                        color: const Color(0xFF39B97A),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 24),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 20,
                                                      vertical: 10,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white.withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                    child: const Text(
                                                      'Koala tarzini anlasin\nSana ozel oneriler hazirlasin',
                                                      textAlign: TextAlign.center,
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w500,
                                                        height: 1.5,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 16),
                                                  Text(
                                                    'Kaydirmaya basla',
                                                    style: TextStyle(
                                                      color: Colors.white.withValues(alpha: 0.6),
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                  ),
                ),
              ),

              // ── Bottom Controls ──
              FadeTransition(
                opacity: CurvedAnimation(
                  parent: _entryController,
                  curve: const Interval(0.5, 1, curve: Curves.easeOut),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    bottomPad + 16,
                  ),
                  child: _shouldShowFinishCta
                      ? _FinishCta(onFinish: _finish)
                      : _SwipeControls(
                          onLike: _isSwipeAnimating
                              ? null
                              : () => _handleSwipe(true),
                          onPass: _isSwipeAnimating
                              ? null
                              : () => _handleSwipe(false),
                          onUndo: _swipeHistory.isNotEmpty && !_isSwipeAnimating
                              ? _undo
                              : null,
                          swipeRatio: swipeRatio,
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

// ─── Card View ────────────────────────────────────────────────

class _DiscoveryCardView extends StatelessWidget {
  const _DiscoveryCardView({
    required this.card,
    required this.offset,
    required this.rotation,
    required this.scale,
    required this.likeOpacity,
    required this.nopeOpacity,
    this.dimmed = false,
  });

  final _DiscoveryCard card;
  final Offset offset;
  final double rotation;
  final double scale;
  final double likeOpacity;
  final double nopeOpacity;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: offset,
      child: Transform.rotate(
        angle: rotation,
        child: Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: dimmed ? 0.6 : 1.0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  if (!dimmed)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 40,
                      offset: const Offset(0, 20),
                      spreadRadius: -4,
                    ),
                  if (!dimmed)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Full-bleed image
                    _CardImage(
                      imageUrl: card.imageUrl,
                      palette: card.palette,
                    ),

                    // Gradient overlay - bottom only for readability
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.0, 0.35, 0.65, 1.0],
                            colors: [
                              Colors.black.withValues(alpha: 0.15),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.15),
                              Colors.black.withValues(alpha: 0.72),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Top pills - room & budget
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: Row(
                        children: [
                          _GlassPill(
                            icon: card.icon,
                            text: card.roomLabel,
                          ),
                          const SizedBox(width: 8),
                          _GlassPill(text: card.budgetLabel),
                          const Spacer(),
                          _GlassPill(text: card.styleLabel, accent: true),
                        ],
                      ),
                    ),

                    // Bottom content
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              card.title,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              card.subtitle,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.4,
                                color: Colors.white.withValues(alpha: 0.85),
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            const SizedBox(height: 14),
                            // Color dots
                            Row(
                              children: [
                                for (int i = 0;
                                    i < card.colorHexes.length && i < 4;
                                    i++) ...[
                                  if (i > 0) const SizedBox(width: 6),
                                  _ColorDot(
                                    color: card.colorHexes[i],
                                    label: card.colors[i],
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Like badge
                    if (likeOpacity > 0)
                      Positioned.fill(
                        child: _SwipeOverlay(
                          isLike: true,
                          opacity: likeOpacity.clamp(0.0, 1.0),
                        ),
                      ),

                    // Nope badge
                    if (nopeOpacity > 0)
                      Positioned.fill(
                        child: _SwipeOverlay(
                          isLike: false,
                          opacity: nopeOpacity.clamp(0.0, 1.0),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Swipe Overlay ────────────────────────────────────────────

class _SwipeOverlay extends StatelessWidget {
  const _SwipeOverlay({required this.isLike, required this.opacity});

  final bool isLike;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final color = isLike ? const Color(0xFF39B97A) : const Color(0xFFE26257);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: color.withValues(alpha: 0.6 * opacity),
          width: 3,
        ),
        color: color.withValues(alpha: 0.08 * opacity),
      ),
      child: Align(
        alignment: isLike ? Alignment.topRight : Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Transform.rotate(
            angle: isLike ? 0.18 : -0.18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color, width: 3),
                color: color.withValues(alpha: 0.15),
              ),
              child: Text(
                isLike ? 'SEVERIM' : 'PAS',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Glass Pill ───────────────────────────────────────────────

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.text, this.icon, this.accent = false});

  final String text;
  final IconData? icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent
            ? const Color(0xFF6C5CE7).withValues(alpha: 0.85)
            : Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: accent ? 0.2 : 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Color Dot ────────────────────────────────────────────────

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Swipe Controls ───────────────────────────────────────────

class _SwipeControls extends StatelessWidget {
  const _SwipeControls({
    required this.onLike,
    required this.onPass,
    required this.onUndo,
    required this.swipeRatio,
  });

  final VoidCallback? onLike;
  final VoidCallback? onPass;
  final VoidCallback? onUndo;
  final double swipeRatio;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Pass button
        _CircleActionButton(
          icon: Icons.close_rounded,
          color: const Color(0xFFE26257),
          size: 56,
          iconSize: 28,
          onTap: onPass,
          highlighted: swipeRatio < -0.3,
        ),
        const SizedBox(width: 24),
        // Like button
        _CircleActionButton(
          icon: Icons.favorite_rounded,
          color: const Color(0xFF39B97A),
          size: 72,
          iconSize: 32,
          onTap: onLike,
          highlighted: swipeRatio > 0.3,
          primary: true,
        ),
        const SizedBox(width: 24),
        // Undo button
        AnimatedOpacity(
          opacity: onUndo != null ? 1.0 : 0.3,
          duration: const Duration(milliseconds: 200),
          child: _CircleActionButton(
            icon: Icons.undo_rounded,
            color: const Color(0xFFAEA8B8),
            size: 56,
            iconSize: 24,
            onTap: onUndo,
            highlighted: false,
          ),
        ),
      ],
    );
  }
}

class _CircleActionButton extends StatelessWidget {
  const _CircleActionButton({
    required this.icon,
    required this.color,
    required this.size,
    required this.iconSize,
    required this.onTap,
    this.highlighted = false,
    this.primary = false,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;
  final VoidCallback? onTap;
  final bool highlighted;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final scale = highlighted ? 1.12 : 1.0;
    return AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primary
                ? color
                : Colors.white,
            border: primary
                ? null
                : Border.all(
                    color: color.withValues(alpha: highlighted ? 0.5 : 0.2),
                    width: 2,
                  ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: primary ? 0.3 : 0.08),
                blurRadius: primary ? 20 : 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(
            icon,
            color: primary ? Colors.white : color,
            size: iconSize,
          ),
        ),
      ),
    );
  }
}

// ─── Finish CTA ───────────────────────────────────────────────

class _FinishCta extends StatelessWidget {
  const _FinishCta({required this.onFinish});

  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onFinish,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7C6EF2), Color(0xFF6C5CE7)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6C5CE7).withValues(alpha: 0.3),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Text(
              'Tarzım Hazır, Sohbete Gecelim',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Done State ───────────────────────────────────────────────

class _DoneState extends StatelessWidget {
  const _DoneState({
    required this.onFinish,
    required this.title,
    required this.body,
    required this.likesCount,
  });

  final VoidCallback onFinish;
  final String title;
  final String body;
  final int likesCount;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6C5CE7).withValues(alpha: 0.08),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF7C6EF2).withValues(alpha: 0.15),
                      const Color(0xFF6C5CE7).withValues(alpha: 0.08),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 36,
                  color: Color(0xFF6C5CE7),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1D2A),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.55,
                  color: Color(0xFF8E8A96),
                ),
              ),
              if (likesCount > 0) ...[
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF39B97A).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.favorite_rounded,
                        size: 16,
                        color: Color(0xFF39B97A),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$likesCount mekan begenildi',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF39B97A),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: onFinish,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7C6EF2), Color(0xFF6C5CE7)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF6C5CE7).withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Text(
                      'Sohbete Gec',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
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

// ─── Tutorial Hint ───────────────────────────────────────────

class _TutorialHint extends StatelessWidget {
  const _TutorialHint({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.2),
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// ─── Swipe Record ────────────────────────────────────────────

class _SwipeRecord {
  const _SwipeRecord({required this.card, required this.liked, required this.weight});
  final _DiscoveryCard card;
  final bool liked;
  final double weight;
}

// ─── Card Data ────────────────────────────────────────────────

class _DiscoveryCard {
  const _DiscoveryCard({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.style,
    required this.styleLabel,
    required this.room,
    required this.roomLabel,
    required this.budget,
    required this.budgetLabel,
    required this.colors,
    required this.colorHexes,
    required this.palette,
    required this.icon,
  });

  final String id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String style;
  final String styleLabel;
  final String room;
  final String roomLabel;
  final String budget;
  final String budgetLabel;
  final List<String> colors;
  final List<Color> colorHexes;
  final List<Color> palette;
  final IconData icon;
}

List<_DiscoveryCard> _buildFullPool() {
  return const [
    _DiscoveryCard(
      id: 'japandi_salon',
      title: 'Japandi Salon',
      subtitle: 'Sakin, açık ahşaplı ve nefes alan bir yaşam alanı.',
      imageUrl:
          'https://images.unsplash.com/photo-1586023492125-27b2c045efd7?auto=format&fit=crop&w=900&q=85',
      style: 'japandi',
      styleLabel: 'Japandi',
      room: 'salon',
      roomLabel: 'Salon',
      budget: 'mid',
      budgetLabel: '30-70K',
      colors: ['Kırık beyaz', 'Açık ahşap', 'Taş beji'],
      colorHexes: [Color(0xFFF5F0E8), Color(0xFFCDB68E), Color(0xFFD4C5A9)],
      palette: [Color(0xFFDDD2C1), Color(0xFFAA9275)],
      icon: Icons.weekend_rounded,
    ),
    _DiscoveryCard(
      id: 'minimal_bedroom',
      title: 'Minimal Yatak Odası',
      subtitle: 'Az eşya, yumuşak ışık ve temiz çizgiler.',
      imageUrl:
          'https://images.unsplash.com/photo-1615874959474-d609969a20ed?auto=format&fit=crop&w=900&q=85',
      style: 'minimalist',
      styleLabel: 'Minimalist',
      room: 'yatak_odasi',
      roomLabel: 'Yatak Odası',
      budget: 'mid',
      budgetLabel: '30-70K',
      colors: ['Beyaz', 'Kum beji', 'Yumuşak gri'],
      colorHexes: [Color(0xFFFAFAFA), Color(0xFFD9CBB8), Color(0xFFBDB8B0)],
      palette: [Color(0xFFE8E3D8), Color(0xFF96908B)],
      icon: Icons.bed_rounded,
    ),
    _DiscoveryCard(
      id: 'boho_bedroom',
      title: 'Boho Köşe',
      subtitle: 'Katmanlı tekstiller ve sıcak, rahat bir his.',
      imageUrl:
          'https://images.unsplash.com/photo-1522771739844-6a9f6d5f14af?auto=format&fit=crop&w=900&q=85',
      style: 'bohemian',
      styleLabel: 'Bohem',
      room: 'yatak_odasi',
      roomLabel: 'Yatak Odası',
      budget: 'low',
      budgetLabel: '10-30K',
      colors: ['Terracotta', 'Keten', 'Adaçayı'],
      colorHexes: [Color(0xFFC97A58), Color(0xFFD4C5A9), Color(0xFF8FA585)],
      palette: [Color(0xFFC97A58), Color(0xFF6C8C74)],
      icon: Icons.self_improvement_rounded,
    ),
    _DiscoveryCard(
      id: 'modern_kitchen',
      title: 'Modern Mutfak',
      subtitle: 'Net hatlar, mat yüzeyler ve güçlü kontrast.',
      imageUrl:
          'https://images.unsplash.com/photo-1600585152220-90363fe7e115?auto=format&fit=crop&w=900&q=85',
      style: 'modern',
      styleLabel: 'Modern',
      room: 'mutfak',
      roomLabel: 'Mutfak',
      budget: 'high',
      budgetLabel: '70-150K',
      colors: ['Antrasit', 'Sıcak gri', 'Beyaz'],
      colorHexes: [Color(0xFF454B52), Color(0xFF9A9590), Color(0xFFF5F5F5)],
      palette: [Color(0xFF62676C), Color(0xFFC5C2BE)],
      icon: Icons.kitchen_rounded,
    ),
    _DiscoveryCard(
      id: 'scandi_living',
      title: 'İskandinav Aydınlık',
      subtitle: 'Ferahlık, doğal ışık ve sıcak sadelik.',
      imageUrl:
          'https://images.unsplash.com/photo-1583847268964-b28dc8f51f92?auto=format&fit=crop&w=900&q=85',
      style: 'scandinavian',
      styleLabel: 'Skandinav',
      room: 'salon',
      roomLabel: 'Salon',
      budget: 'mid',
      budgetLabel: '30-70K',
      colors: ['Açık gri', 'Krem', 'Toz mavi'],
      colorHexes: [Color(0xFFD9DDE2), Color(0xFFF2EBE0), Color(0xFF9BB8D6)],
      palette: [Color(0xFFD9DDE2), Color(0xFF7F9BB6)],
      icon: Icons.wb_sunny_rounded,
    ),
    _DiscoveryCard(
      id: 'industrial_office',
      title: 'Endüstriyel Ofis',
      subtitle: 'Ham dokular, metal detaylar ve güçlü karakter.',
      imageUrl:
          'https://images.unsplash.com/photo-1497366216548-37526070297c?auto=format&fit=crop&w=900&q=85',
      style: 'industrial',
      styleLabel: 'Endüstriyel',
      room: 'ofis',
      roomLabel: 'Ofis',
      budget: 'mid',
      budgetLabel: '30-70K',
      colors: ['Kömür', 'Pas kahve', 'Beton'],
      colorHexes: [Color(0xFF3C3E42), Color(0xFF9D6646), Color(0xFFACA8A3)],
      palette: [Color(0xFF52555A), Color(0xFF9D6646)],
      icon: Icons.desktop_windows_rounded,
    ),
    _DiscoveryCard(
      id: 'classic_dining',
      title: 'Klasik Dokunuş',
      subtitle: 'Dengeli, zamansız ve biraz daha rafine.',
      imageUrl:
          'https://images.unsplash.com/photo-1600210492493-0946911123ea?auto=format&fit=crop&w=900&q=85',
      style: 'classic',
      styleLabel: 'Klasik',
      room: 'salon',
      roomLabel: 'Salon',
      budget: 'premium',
      budgetLabel: '150K+',
      colors: ['Fildişi', 'Ceviz', 'Altın beji'],
      colorHexes: [Color(0xFFF0E8D8), Color(0xFF6B4F38), Color(0xFFD4B896)],
      palette: [Color(0xFFE7DCC6), Color(0xFF8B684D)],
      icon: Icons.chair_alt_rounded,
    ),
    _DiscoveryCard(
      id: 'luxury_bathroom',
      title: 'Lüks Banyo',
      subtitle: 'Taş etkisi, yumuşak aydınlatma ve otel hissi.',
      imageUrl:
          'https://images.unsplash.com/photo-1584622650111-993a426fbf0a?auto=format&fit=crop&w=900&q=85',
      style: 'luxury',
      styleLabel: 'Lüks',
      room: 'banyo',
      roomLabel: 'Banyo',
      budget: 'premium',
      budgetLabel: '150K+',
      colors: ['Mermer', 'Kum taşı', 'Koyu bronz'],
      colorHexes: [Color(0xFFE8E2DA), Color(0xFFC5B9A8), Color(0xFF6B5D52)],
      palette: [Color(0xFFD8D1CB), Color(0xFF74655C)],
      icon: Icons.bathtub_rounded,
    ),
    _DiscoveryCard(
      id: 'japandi_bathroom',
      title: 'Spa Hissi',
      subtitle: 'Doğallığı yüksek, sakin ve yavaş bir banyo dili.',
      imageUrl:
          'https://images.unsplash.com/photo-1507652313519-d4e9174996dd?auto=format&fit=crop&w=900&q=85',
      style: 'japandi',
      styleLabel: 'Japandi',
      room: 'banyo',
      roomLabel: 'Banyo',
      budget: 'high',
      budgetLabel: '70-150K',
      colors: ['Taş beji', 'Keten', 'Bambu'],
      colorHexes: [Color(0xFFD2C5B3), Color(0xFFD4C5A9), Color(0xFFB5A882)],
      palette: [Color(0xFFD2C5B3), Color(0xFF9A856B)],
      icon: Icons.spa_rounded,
    ),
    _DiscoveryCard(
      id: 'modern_bedroom',
      title: 'Koyu Modern Yatak',
      subtitle: 'Dramatik tonlar ve otel benzeri sadelik.',
      imageUrl:
          'https://images.unsplash.com/photo-1618773928121-c32242e63f39?auto=format&fit=crop&w=900&q=85',
      style: 'modern',
      styleLabel: 'Modern',
      room: 'yatak_odasi',
      roomLabel: 'Yatak Odası',
      budget: 'high',
      budgetLabel: '70-150K',
      colors: ['Koyu taş', 'Buz grisi', 'Siyah'],
      colorHexes: [Color(0xFF5A5E64), Color(0xFFC5CCD6), Color(0xFF2A2D32)],
      palette: [Color(0xFF5A5E64), Color(0xFF9FA7B3)],
      icon: Icons.nightlight_round,
    ),
  ];
}

// ─── Card Image ───────────────────────────────────────────────

class _CardImage extends StatelessWidget {
  const _CardImage({required this.imageUrl, this.palette = const []});

  final String imageUrl;
  final List<Color> palette;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _ImagePlaceholder(palette: palette),
        if (imageUrl.isNotEmpty)
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 300),
              placeholder: (_, __) => const Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color(0xFF6C5CE7),
                  ),
                ),
              ),
              errorWidget: (_, __, ___) => const Center(
                child: Icon(
                  Icons.image_not_supported_outlined,
                  size: 40,
                  color: Color(0xFFCBC5D4),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ImagePlaceholder extends StatefulWidget {
  const _ImagePlaceholder({this.palette = const []});
  final List<Color> palette;

  @override
  State<_ImagePlaceholder> createState() => _ImagePlaceholderState();
}

class _ImagePlaceholderState extends State<_ImagePlaceholder>
    with TickerProviderStateMixin {
  late final AnimationController _shimmer;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shimmer.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasColors = widget.palette.length >= 2;
    final baseColor =
        hasColors ? widget.palette[0] : const Color(0xFFE0D4C1);
    final accentColor =
        hasColors ? widget.palette[1] : const Color(0xFFC5B8A5);

    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, child) {
        final sweep = _shimmer.value * 2 - 0.5;
        return Stack(
          fit: StackFit.expand,
          children: [
            // Base gradient
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    baseColor.withValues(alpha: 0.5),
                    accentColor.withValues(alpha: 0.35),
                    baseColor.withValues(alpha: 0.45),
                  ],
                ),
              ),
            ),
            // Shimmer sweep
            Positioned.fill(
              child: ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment(sweep - 0.3, -1),
                  end: Alignment(sweep + 0.3, 1),
                  colors: [
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: 0.08),
                    Colors.white.withValues(alpha: 0),
                  ],
                ).createShader(bounds),
                blendMode: BlendMode.srcATop,
                child: Container(color: Colors.white),
              ),
            ),
            // Center icon
            Center(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, child) {
                  final scale = 0.9 + 0.1 * _pulse.value;
                  final opacity = 0.15 + 0.1 * _pulse.value;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: opacity),
                      ),
                      child: Icon(
                        Icons.image_rounded,
                        size: 24,
                        color: Colors.white.withValues(alpha: opacity + 0.1),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
