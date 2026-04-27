import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/koala_tokens.dart';
import '../../services/analytics_service.dart';
import '../../services/swipe_deck_service.dart';

/// "Zevkimi keşfet" — analyze-room confidence düşükse veya kullanıcı
/// açıkça istediğinde açılan kısa swipe akışı. 6-8 kart, drag-to-swipe,
/// soft "anlaşılan zevkin..." reveal'ı, tek CTA ile restyle'a hand-off.
///
/// Tasarım disiplini `mekan/style_discovery_screen.dart` ile paralel —
/// yeni token, yeni font, yeni paket yok. Hand-rolled stack + GestureDetector
/// + AnimatedContainer. `flutter_card_swiper` pubspec'te yoktu.
///
/// Dönüş: kullanıcı reveal'da "Tasarlayalım"a basarsa parent route
/// `Navigator.pop` ile [SwipeResult] alır. "Atla" veya geri → null.
class SwipeScreen extends StatefulWidget {
  /// Backend'in tahmin ettiği oda tipi (Türkçe; "Yatak Odası" vs). Deck
  /// filtresi için service'e iletilir; null ise random.
  final String? roomTypeHint;

  /// Restyle prefetch entegrasyonu — 5. like'ta tetiklemek için. Caller
  /// taraf hem image hem theme bilmeli. Null ise prefetch atlanır
  /// (örn. inferred theme henüz yokken bu ekran açıldıysa).
  final RestylePrefetchTrigger? prefetchTrigger;

  /// Service injection — test/preview için.
  final SwipeDeckService? service;

  const SwipeScreen({
    super.key,
    this.roomTypeHint,
    this.prefetchTrigger,
    this.service,
  });

  @override
  State<SwipeScreen> createState() => _SwipeScreenState();
}

/// Caller'ın kendi prefetch context'iyle çağrı yapabilmesi için kapı.
typedef RestylePrefetchTrigger = void Function();

enum _Phase { loading, swiping, revealing }

class _SwipeScreenState extends State<SwipeScreen> {
  static const int _deckSize = 8;
  static const int _minSwipesToFinish = 6;
  static const double _swipeThreshold = 100;
  static const int _prefetchAfterLikes = 5;

  late final SwipeDeckService _service;
  _Phase _phase = _Phase.loading;
  List<SwipeCard> _deck = const [];
  int _index = 0;
  final List<SwipeCard> _liked = [];
  // Hangi index'lerde sağa/sola gitti — progress dot'ları için.
  final List<bool> _swipeOutcomes = [];

  // Drag state
  double _dragX = 0;
  bool _animatingExit = false;
  bool _hapticFired = false;
  bool _hintDismissed = false;
  bool _prefetchFired = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? SwipeDeckService();
    unawaited(
      Analytics.swipeDeckOpened(
        roomType: widget.roomTypeHint,
        deckSize: _deckSize,
      ),
    );
    _loadDeck();
  }

  Future<void> _loadDeck() async {
    final cards = await _service.fetchDeck(
      roomType: widget.roomTypeHint,
      limit: _deckSize,
    );
    if (!mounted) return;
    final trimmed = cards.take(_deckSize).toList();
    setState(() {
      _deck = trimmed;
      _phase = trimmed.isEmpty ? _Phase.revealing : _Phase.swiping;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _precacheNext();
    });
  }

  void _precacheNext() {
    for (int o = 1; o <= 2; o++) {
      final i = _index + o;
      if (i < _deck.length) {
        final url = _deck[i].coverUrl;
        if (url.isNotEmpty) {
          unawaited(
            precacheImage(NetworkImage(url), context).catchError((_) {}),
          );
        }
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_animatingExit) return;
    setState(() => _dragX += d.delta.dx);
    final past = _dragX.abs() > _swipeThreshold;
    if (past && !_hapticFired) {
      _hapticFired = true;
      unawaited(HapticFeedback.selectionClick());
    } else if (!past && _hapticFired) {
      _hapticFired = false;
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (_animatingExit) return;
    if (_dragX > _swipeThreshold) {
      _commit(liked: true);
    } else if (_dragX < -_swipeThreshold) {
      _commit(liked: false);
    } else {
      setState(() => _dragX = 0);
    }
  }

  void _commit({required bool liked}) {
    if (_index >= _deck.length) return;
    final card = _deck[_index];
    if (liked) _liked.add(card);
    _swipeOutcomes.add(liked);
    _hintDismissed = true;
    unawaited(
      Analytics.swipeCard(
        projectId: card.id,
        liked: liked,
        index: _index,
      ),
    );

    // 5. like'ta restyle prefetch'i tetikle.
    if (liked &&
        !_prefetchFired &&
        _liked.length >= _prefetchAfterLikes &&
        widget.prefetchTrigger != null) {
      _prefetchFired = true;
      try {
        widget.prefetchTrigger!.call();
      } catch (_) {/* sessiz başarısızlık */}
    }

    setState(() {
      _animatingExit = true;
      _dragX = liked ? 600 : -600;
    });

    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() {
        _index += 1;
        _dragX = 0;
        _animatingExit = false;
        _hapticFired = false;
      });
      _precacheNext();
      // Bitti veya minimum + tüm sağa kalanlar tükendi → reveal.
      if (_index >= _deck.length || _index >= _minSwipesToFinish) {
        // _minSwipesToFinish'i geçince otomatik bitirme yapma — kullanıcı
        // 8'e kadar swipe edebilsin ama 6'dan sonra deck biterse veya kart
        // kalmazsa bitir. Bu satırı sadece deck bitti diye değil, kart
        // bitti diye tetikliyoruz; davranış: 6+ swipe sonrası deck biterse
        // reveal aç. (Min davranışı için ek "Bitir" butonu yok — UX hard
        // constraint'leri bu deck'i otomatik bitirmemizi söylüyor.)
        if (_index >= _deck.length || _index >= _minSwipesToFinish) {
          _openReveal();
        }
      }
    });
  }

  void _openReveal() {
    if (_phase == _Phase.revealing) return;
    final tagFreq = <String, int>{};
    for (final c in _liked) {
      for (final t in c.tags) {
        final k = t.trim().toLowerCase();
        if (k.isEmpty) continue;
        tagFreq[k] = (tagFreq[k] ?? 0) + 1;
      }
    }
    final top = tagFreq.keys.toList()
      ..sort((a, b) => (tagFreq[b] ?? 0).compareTo(tagFreq[a] ?? 0));
    final topTags = top.take(3).toList();
    unawaited(
      Analytics.swipeRevealed(
        liked: _liked.length,
        total: _index,
        topTags: topTags,
      ),
    );
    setState(() => _phase = _Phase.revealing);
  }

  void _onTapRestyle() {
    unawaited(Analytics.swipeCtaTapped(action: 'restyle'));
    final tagFreq = <String, int>{};
    for (final c in _liked) {
      for (final t in c.tags) {
        final k = t.trim().toLowerCase();
        if (k.isEmpty) continue;
        tagFreq[k] = (tagFreq[k] ?? 0) + 1;
      }
    }
    final colorFreq = <int, int>{};
    final colorOrder = <Color>[];
    for (final c in _liked) {
      for (final col in c.colors) {
        // ignore: deprecated_member_use
        final v = col.value;
        if (!colorFreq.containsKey(v)) colorOrder.add(col);
        colorFreq[v] = (colorFreq[v] ?? 0) + 1;
      }
    }
    final lovedTags = (tagFreq.keys.toList()
          ..sort((a, b) => (tagFreq[b] ?? 0).compareTo(tagFreq[a] ?? 0)))
        .take(5)
        .toList();
    final lovedColors = (colorOrder.toList()
          // ignore: deprecated_member_use
          ..sort((a, b) =>
              (colorFreq[b.value] ?? 0).compareTo(colorFreq[a.value] ?? 0)))
        .take(5)
        .toList();
    Navigator.of(context).pop(
      SwipeResult(
        lovedTags: lovedTags,
        lovedColors: lovedColors,
        lovedProjectIds: _liked.map((c) => c.id).toList(),
      ),
    );
  }

  void _onTapSkip() {
    unawaited(Analytics.swipeCtaTapped(action: 'skip'));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      appBar: AppBar(
        backgroundColor: KoalaColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft, color: KoalaColors.text),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(0.5),
          child: Divider(
            height: 0.5,
            thickness: 0.5,
            color: KoalaColors.divider,
          ),
        ),
      ),
      body: SafeArea(child: _buildPhase()),
    );
  }

  Widget _buildPhase() {
    switch (_phase) {
      case _Phase.loading:
        return const _DeckSkeleton();
      case _Phase.swiping:
        return _buildSwiping();
      case _Phase.revealing:
        return _buildRevealing();
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // SWIPING
  // ──────────────────────────────────────────────────────────────────────

  Widget _buildSwiping() {
    final atEnd = _index >= _deck.length;
    if (atEnd) {
      // Deck tükendi ama reveal henüz açılmadıysa — geçici loader.
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(KoalaColors.accentDeep),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: KoalaSpacing.sm),
          const Text(
            'Birkaç kart, hızlı bir keşif',
            style: KoalaText.bodySec,
          ),
          const SizedBox(height: KoalaSpacing.xs),
          Text(
            'Hangisi sana daha çok benziyor?',
            style: KoalaText.serif(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          const SizedBox(height: KoalaSpacing.lg),
          Expanded(child: _buildDeck()),
          const SizedBox(height: KoalaSpacing.lg),
          _ProgressDots(
            total: _deckSize,
            done: _swipeOutcomes.length,
          ),
          const SizedBox(height: KoalaSpacing.md),
        ],
      ),
    );
  }

  Widget _buildDeck() {
    final active = _deck[_index];
    final hasNext = _index + 1 < _deck.length;
    final next = hasNext ? _deck[_index + 1] : null;
    final hasNext2 = _index + 2 < _deck.length;
    final next2 = hasNext2 ? _deck[_index + 2] : null;

    final rotation = (_dragX / 600).clamp(-0.14, 0.14);
    final dragOpacity =
        _animatingExit ? 0.0 : (1.0 - (_dragX.abs() / 800).clamp(0.0, 0.6));
    final showHint = _index == 0 && !_hintDismissed && _dragX.abs() < 8;
    final likeStrength = (_dragX / _swipeThreshold).clamp(-1.0, 1.0);

    return LayoutBuilder(
      builder: (ctx, constraints) {
        return Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            if (next2 != null)
              Positioned(
                top: -16,
                left: 0,
                right: 0,
                child: Transform.scale(
                  scale: 0.92,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.5,
                      child: _SwipeCardView(
                        card: next2,
                      ),
                    ),
                  ),
                ),
              ),
            if (next != null)
              Positioned(
                top: -8,
                left: 0,
                right: 0,
                child: Transform.scale(
                  scale: 0.96,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.85,
                      child: _SwipeCardView(card: next),
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: GestureDetector(
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                child: AnimatedContainer(
                  duration: Duration(milliseconds: _animatingExit ? 220 : 240),
                  curve: Curves.easeOutCubic,
                  transform: Matrix4.identity()
                    ..translate(_dragX, _dragX.abs() * 0.05)
                    ..rotateZ(rotation),
                  transformAlignment: Alignment.bottomCenter,
                  child: Opacity(
                    opacity: dragOpacity.clamp(0.0, 1.0),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: _SwipeCardView(
                        card: active,
                        likeStrength: likeStrength,
                        showHint: showHint,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // REVEALING
  // ──────────────────────────────────────────────────────────────────────

  Widget _buildRevealing() {
    // En çok beğenilenden seç — top-3 mood-board görseli.
    // Liked kart sırası "swipe ettiği sırayla". 3 yetmezse boş kalsın.
    final boards = _liked.take(3).toList();
    final summary = _summary(_liked);
    final hasContent = _liked.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KoalaSpacing.xl,
        KoalaSpacing.md,
        KoalaSpacing.xl,
        KoalaSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: KoalaSpacing.lg),
          Text(
            'Anlaşılan zevkin…',
            style: KoalaText.serif(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          )
              .animate()
              .fadeIn(duration: 280.ms)
              .slideY(
                begin: 0.06,
                end: 0,
                duration: 320.ms,
                delay: 140.ms,
                curve: Curves.easeOutCubic,
              ),
          const SizedBox(height: KoalaSpacing.sm),
          Text(
            summary,
            style: KoalaText.bodySec,
          )
              .animate(delay: 220.ms)
              .fadeIn(duration: 280.ms)
              .slideY(
                begin: 0.06,
                end: 0,
                duration: 320.ms,
                curve: Curves.easeOutCubic,
              ),
          const SizedBox(height: KoalaSpacing.xxl),
          if (boards.isNotEmpty)
            SizedBox(
              height: 140,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  for (int i = 0; i < boards.length; i++) ...[
                    _MoodBoardImage(card: boards[i])
                        .animate(delay: (300 + i * 60).ms)
                        .fadeIn(duration: 260.ms)
                        .slideY(
                          begin: 0.08,
                          end: 0,
                          duration: 300.ms,
                          curve: Curves.easeOutCubic,
                        ),
                    if (i < boards.length - 1)
                      const SizedBox(width: KoalaSpacing.md),
                  ],
                ],
              ),
            ),
          const Spacer(),
          if (hasContent)
            _PrimaryCta(
              label: 'Şimdi mekanını bu tarzda tasarlayalım',
              onTap: _onTapRestyle,
            ).animate(delay: 520.ms).fadeIn(duration: 260.ms)
          else
            _PrimaryCta(
              label: 'Şimdi tasarlayalım',
              onTap: _onTapRestyle,
            ).animate(delay: 520.ms).fadeIn(duration: 260.ms),
          const SizedBox(height: KoalaSpacing.sm),
          Center(
            child: TextButton(
              onPressed: _onTapSkip,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(
                  horizontal: KoalaSpacing.md,
                ),
              ),
              child: const Text(
                'Atla, ben kendim seçeyim',
                style: KoalaText.bodySec,
              ),
            ),
          ).animate(delay: 600.ms).fadeIn(duration: 220.ms),
        ],
      ),
    );
  }

  /// Liked kartların tag frekansından tek satır Türkçe özet üret.
  /// Top-3 tag'i şablona iliştir; like yoksa nazik fallback.
  String _summary(List<SwipeCard> liked) {
    if (liked.isEmpty) {
      return 'Henüz net bir sinyal yok — birkaç kart daha beğensen tarzını okurum.';
    }
    final freq = <String, int>{};
    final order = <String>[];
    for (final c in liked) {
      for (final t in c.tags) {
        final k = t.trim().toLowerCase();
        if (k.isEmpty) continue;
        if (!freq.containsKey(k)) order.add(k);
        freq[k] = (freq[k] ?? 0) + 1;
      }
    }
    if (freq.isEmpty) {
      return 'Sade ve sıcak bir his — bunu temel alıp tasarlayalım.';
    }
    final sorted = order.toList()
      ..sort((a, b) => (freq[b] ?? 0).compareTo(freq[a] ?? 0));
    final top = sorted.take(3).toList();
    if (top.length == 1) return '${_cap(top.first)} bir his.';
    if (top.length == 2) {
      return '${_cap(top[0])} tonlar, ${top[1]} dokunuş.';
    }
    return '${_cap(top[0])} tonlar, ${top[1]} dokunuş, ${top[2]} bir atmosfer.';
  }

  String _cap(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _SwipeCardView extends StatelessWidget {
  final SwipeCard card;

  /// Aktif kartın drag yönü gücü — -1 (sol/geçtim) … +1 (sağ/sevdim).
  /// Peek kartlarda 0.
  final double likeStrength;

  /// İlk kartta bir kerelik tooltip ipucu.
  final bool showHint;

  const _SwipeCardView({
    required this.card,
    this.likeStrength = 0,
    this.showHint = false,
  });

  @override
  Widget build(BuildContext context) {
    final shownTags = card.tags.take(3).toList();
    final shownColors = card.colors.take(5).toList();

    return Container(
      decoration: BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(KoalaRadius.lg),
        border: Border.all(color: KoalaColors.divider, width: 1),
        boxShadow: KoalaShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                card.coverUrl.isNotEmpty
                    ? Image.network(
                        card.coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: KoalaColors.surfaceAlt,
                          alignment: Alignment.center,
                          child: const Icon(
                            LucideIcons.image,
                            color: KoalaColors.textTer,
                            size: 24,
                          ),
                        ),
                      )
                    : Container(color: KoalaColors.surfaceAlt),
                if (likeStrength.abs() > 0.05)
                  IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      decoration: BoxDecoration(
                        color: (likeStrength > 0
                                ? KoalaColors.like
                                : KoalaColors.dislike)
                            .withValues(alpha: likeStrength.abs() * 0.18),
                      ),
                    ),
                  ),
                if (showHint)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: KoalaSpacing.md),
                      child: _HintPill(),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KoalaSpacing.md,
              KoalaSpacing.sm,
              KoalaSpacing.md,
              KoalaSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (shownTags.isNotEmpty)
                  Wrap(
                    spacing: KoalaSpacing.xs,
                    runSpacing: KoalaSpacing.xs,
                    children: [
                      for (final t in shownTags) _TagChip(label: t),
                    ],
                  ),
                if (shownColors.isNotEmpty) ...[
                  const SizedBox(height: KoalaSpacing.sm),
                  Row(
                    children: [
                      for (final c in shownColors) ...[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: KoalaColors.border,
                              width: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  const _TagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KoalaSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: KoalaColors.surfaceAlt,
        borderRadius: BorderRadius.circular(KoalaRadius.pill),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: KoalaColors.textMed,
        ),
      ),
    );
  }
}

class _HintPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KoalaSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(KoalaRadius.pill),
      ),
      child: const Text(
        'kaydır → seviyorsan sağa, geçiyorsan sola',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).fadeIn(
          duration: 600.ms,
          begin: 0.6,
        );
  }
}

class _ProgressDots extends StatelessWidget {
  final int total;
  final int done;
  const _ProgressDots({required this.total, required this.done});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < total; i++) ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: i < done
                  ? KoalaColors.accentDeep
                  : KoalaColors.surfaceAlt,
              shape: BoxShape.circle,
            ),
          ),
          if (i < total - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _MoodBoardImage extends StatelessWidget {
  final SwipeCard card;
  const _MoodBoardImage({required this.card});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      height: 140,
      decoration: BoxDecoration(
        color: KoalaColors.surfaceAlt,
        borderRadius: BorderRadius.circular(KoalaRadius.md),
        border: Border.all(color: KoalaColors.divider, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: card.coverUrl.isNotEmpty
          ? Image.network(
              card.coverUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                LucideIcons.image,
                color: KoalaColors.textTer,
                size: 20,
              ),
            )
          : const Icon(
              LucideIcons.image,
              color: KoalaColors.textTer,
              size: 20,
            ),
    );
  }
}

class _PrimaryCta extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryCta({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KoalaColors.accentDeep,
      borderRadius: BorderRadius.circular(KoalaRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(KoalaRadius.pill),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(
            horizontal: KoalaSpacing.lg,
            vertical: KoalaSpacing.md,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: KoalaSpacing.sm),
              const Icon(
                LucideIcons.arrowRight,
                size: 18,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeckSkeleton extends StatelessWidget {
  const _DeckSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: KoalaSpacing.sm),
          Container(width: 220, height: 14, color: KoalaColors.surfaceAlt),
          const SizedBox(height: KoalaSpacing.sm),
          Container(
            width: double.infinity,
            height: 22,
            color: KoalaColors.surfaceAlt,
          ),
          const SizedBox(height: KoalaSpacing.lg),
          Expanded(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                  color: KoalaColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(KoalaRadius.lg),
                ),
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .fadeIn(duration: 600.ms, begin: 0.55),
            ),
          ),
          const SizedBox(height: KoalaSpacing.lg),
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: KoalaColors.surfaceAlt,
              borderRadius: BorderRadius.circular(KoalaRadius.pill),
            ),
          ),
          const SizedBox(height: KoalaSpacing.md),
        ],
      ),
    );
  }
}
