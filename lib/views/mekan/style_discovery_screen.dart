import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/koala_tokens.dart';
import '../../services/analytics_service.dart';
import '../../services/style_discovery_service.dart';
import 'widgets/style_card.dart';
import 'widgets/style_reveal_sheet.dart';

/// "Tarz keşfi" — analyze-room confidence düşükse açılan 30sn swipe akışı.
/// 8 kart üzerinde sevdim/atla → top tag/color aggregate → reveal sheet.
///
/// Tasarım disiplini pro_match_sheet ile paralel: Fraunces serif başlık +
/// KoalaText.bodySec subtitle, 240ms fade + slideY giriş, accentDeep CTA,
/// hairline border'lar, soft shadow. Yeni paket eklenmedi — gesture native
/// GestureDetector + AnimatedContainer.
///
/// Dönüş: kullanıcı reveal'da CTA'ya basarsa parent route `Navigator.pop`
/// ile `StyleHints` alır. İptal/back → `null`.
class StyleDiscoveryScreen extends StatefulWidget {
  /// Backend'in tahmin ettiği oda tipi — deck'i bu odaya göre filtrelemek
  /// için service'e geçilir. Boşsa "any".
  final String roomTypeGuess;

  /// Service injection — test/preview yolunda mock geçilebilir.
  final StyleDiscoveryService? service;

  const StyleDiscoveryScreen({
    super.key,
    required this.roomTypeGuess,
    this.service,
  });

  @override
  State<StyleDiscoveryScreen> createState() => _StyleDiscoveryScreenState();
}

class _StyleDiscoveryScreenState extends State<StyleDiscoveryScreen>
    with SingleTickerProviderStateMixin {
  static const int _deckSize = 8;
  static const int _minSwipesToFinish = 5;
  static const double _swipeThreshold = 100;

  late final StyleDiscoveryService _service;
  Future<List<DiscoveryCard>>? _deckFuture;
  List<DiscoveryCard> _deck = const [];
  int _index = 0;
  final List<DiscoveryCard> _liked = [];
  // Drag state
  double _dragX = 0;
  bool _animatingExit = false;
  bool _revealShown = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? StyleDiscoveryService();
    unawaited(
      Analytics.styleDiscoveryStarted(roomTypeGuess: widget.roomTypeGuess),
    );
    _deckFuture = _loadDeck();
  }

  Future<List<DiscoveryCard>> _loadDeck() async {
    final cards = await _service.fetchDeck(roomTypeGuess: widget.roomTypeGuess);
    final trimmed = cards.take(_deckSize).toList();
    if (mounted) {
      setState(() => _deck = trimmed);
      // İlk frame sonrası bir sonraki kartı pre-cache et — image swap'da
      // beyaz flash olmasın.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _precacheNext();
      });
    }
    return trimmed;
  }

  void _precacheNext() {
    final nextIdx = _index + 1;
    if (nextIdx < _deck.length) {
      final url = _deck[nextIdx].imageUrl;
      if (url.isNotEmpty) {
        unawaited(precacheImage(NetworkImage(url), context).catchError((_) {}));
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_animatingExit) return;
    setState(() => _dragX += d.delta.dx);
  }

  void _onPanEnd(DragEndDetails d) {
    if (_animatingExit) return;
    if (_dragX > _swipeThreshold) {
      _commit(liked: true);
    } else if (_dragX < -_swipeThreshold) {
      _commit(liked: false);
    } else {
      // Spring back — AnimatedContainer'ın 240ms transition'ı
      // _dragX=0 set'iyle tetiklenir.
      setState(() => _dragX = 0);
    }
  }

  void _commit({required bool liked}) {
    if (_index >= _deck.length) return;
    final card = _deck[_index];
    if (liked) _liked.add(card);
    unawaited(
      Analytics.styleDiscoverySwipe(
        index: _index,
        liked: liked,
        cardId: card.id,
      ),
    );

    setState(() {
      _animatingExit = true;
      // Off-screen target — fade-out + translate.
      _dragX = liked ? 600 : -600;
    });

    // Kısa exit animasyonu sonrası bir sonraki karta geç. 200ms hızlı +
    // tatmin edici.
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() {
        _index += 1;
        _dragX = 0;
        _animatingExit = false;
      });
      _precacheNext();
      if (_index >= _deck.length) {
        _openReveal();
      }
    });
  }

  void _onTapButton({required bool liked}) {
    if (_animatingExit) return;
    _commit(liked: liked);
  }

  void _onTapFinishEarly() {
    if (_index < _minSwipesToFinish) return;
    _openReveal();
  }

  Future<void> _openReveal() async {
    if (_revealShown) return;
    _revealShown = true;
    final hints = _service.buildHintsFromLikes(_liked);
    unawaited(
      Analytics.styleDiscoveryFinished(
        swipeCount: _index,
        topTags: hints.topTags,
      ),
    );
    unawaited(Analytics.styleDiscoveryRevealOpened());

    if (!mounted) return;
    final accepted = await StyleRevealSheet.show(
      context,
      hints: hints,
      likedCards: _liked,
    );
    if (!mounted) return;
    if (accepted != null) {
      // Parent flow hints'leri alıp restyle prompt'una zerk eder.
      Navigator.of(context).pop(accepted);
    } else {
      // "Tarzı yenile" — sheet kapandı, swipe'a dön. Kullanıcının önceki
      // beğenilerini tutuyoruz; istersen reset için _liked.clear() yap.
      _revealShown = false;
    }
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
      body: SafeArea(
        child: FutureBuilder<List<DiscoveryCard>>(
          future: _deckFuture,
          builder: (ctx, snap) {
            // Loading > 300ms → skeleton; aksi halde direkt UI gözüksün.
            if (snap.connectionState != ConnectionState.done) {
              return const _DeckSkeleton();
            }
            if (snap.hasError || _deck.isEmpty) {
              return const _DeckEmpty();
            }
            return _buildBody();
          },
        ),
      ),
    );
  }

  Widget _buildBody() {
    final atEnd = _index >= _deck.length;
    final progress = (_index / _deckSize).clamp(0.0, 1.0);
    final canFinish = _index >= _minSwipesToFinish && !atEnd;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: KoalaSpacing.sm),
          // ── Subtitle (small, secondary)
          Text(
            '30 saniyede zevkini öğreneyim',
            style: KoalaText.bodySec,
          )
              .animate(delay: 80.ms)
              .fadeIn(duration: 280.ms)
              .slideY(
                begin: 0.06,
                end: 0,
                duration: 320.ms,
                curve: Curves.easeOutCubic,
              ),
          const SizedBox(height: KoalaSpacing.xs),
          // ── Big serif title
          Text(
            'Hangisi sana daha çok benziyor?',
            style: KoalaText.serif(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          )
              .animate(delay: 80.ms)
              .fadeIn(duration: 280.ms)
              .slideY(
                begin: 0.06,
                end: 0,
                duration: 320.ms,
                curve: Curves.easeOutCubic,
              ),
          const SizedBox(height: KoalaSpacing.lg),
          // ── Progress bar (height 3, KoalaRadius.full)
          _ProgressBar(progress: progress)
              .animate(delay: 120.ms)
              .fadeIn(duration: 280.ms),
          const SizedBox(height: KoalaSpacing.xl),
          // ── Card deck (Stack: peek + active)
          Expanded(child: _buildDeck(atEnd)),
          const SizedBox(height: KoalaSpacing.lg),
          // ── Action buttons
          if (!atEnd)
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: LucideIcons.x,
                    label: 'Bana göre değil',
                    background: KoalaColors.surfaceAlt,
                    foreground: KoalaColors.textSec,
                    onTap: () => _onTapButton(liked: false),
                  ),
                ),
                const SizedBox(width: KoalaSpacing.md),
                Expanded(
                  child: _ActionButton(
                    icon: LucideIcons.heart,
                    label: 'Bu hoşuma gitti',
                    background: KoalaColors.accent,
                    foreground: Colors.white,
                    onTap: () => _onTapButton(liked: true),
                  ),
                ),
              ],
            ).animate(delay: 220.ms).fadeIn(duration: 240.ms).slideY(
                  begin: 0.08,
                  end: 0,
                  duration: 280.ms,
                  curve: Curves.easeOutCubic,
                ),
          // "Bitir" — yalnızca min 5 swipe'tan sonra.
          if (canFinish) ...[
            const SizedBox(height: KoalaSpacing.sm),
            Center(
              child: TextButton(
                onPressed: _onTapFinishEarly,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: KoalaSpacing.md,
                  ),
                ),
                child: Text(
                  'Bitir',
                  style: KoalaText.bodySec,
                ),
              ),
            ),
          ],
          const SizedBox(height: KoalaSpacing.md),
        ],
      ),
    );
  }

  Widget _buildDeck(bool atEnd) {
    if (atEnd) {
      // Reveal açılırken ekranda boşluk olmasın — sade nötr placeholder.
      return Center(
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor:
                  AlwaysStoppedAnimation<Color>(KoalaColors.accentDeep),
            ),
          ),
        ),
      );
    }

    final active = _deck[_index];
    final hasNext = _index + 1 < _deck.length;
    final next = hasNext ? _deck[_index + 1] : null;
    final hasNext2 = _index + 2 < _deck.length;
    final next2 = hasNext2 ? _deck[_index + 2] : null;

    final rotation = (_dragX / 600).clamp(-0.14, 0.14); // ~ ±8°
    final dragOpacity =
        _animatingExit ? 0.0 : (1.0 - (_dragX.abs() / 800).clamp(0.0, 0.6));

    return LayoutBuilder(
      builder: (ctx, constraints) {
        return Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            // Peek 2 — en arkadaki, daha küçük ve daha yukarıda.
            if (next2 != null)
              Positioned(
                top: -16,
                left: 0,
                right: 0,
                child: Transform.scale(
                  scale: 0.92,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.55,
                      child: StyleCard(
                        key: ValueKey('peek2_${next2.id}'),
                        card: next2,
                        delayMs: 0,
                      ),
                    ),
                  ),
                ),
              ),
            // Peek 1 — biraz arkada, 0.96 scale, -8 y.
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
                      child: StyleCard(
                        key: ValueKey('peek1_${next.id}'),
                        card: next,
                        delayMs: 0,
                      ),
                    ),
                  ),
                ),
              ),
            // Active — sürüklenebilir, hafif rotate, drag-out fade.
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
                      child: StyleCard(
                        key: ValueKey('active_${active.id}_$_index'),
                        card: active,
                        delayMs: 60,
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
}

// ═══════════════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _ProgressBar extends StatelessWidget {
  final double progress;
  const _ProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(KoalaRadius.pill),
      child: Container(
        height: 3,
        color: KoalaColors.surfaceAlt,
        child: Align(
          alignment: Alignment.centerLeft,
          child: AnimatedFractionallySizedBox(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            widthFactor: progress.clamp(0.0, 1.0),
            heightFactor: 1,
            child: Container(
              decoration: BoxDecoration(
                color: KoalaColors.accentDeep,
                borderRadius: BorderRadius.circular(KoalaRadius.pill),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(KoalaRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(KoalaRadius.pill),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(
            horizontal: KoalaSpacing.md,
            vertical: KoalaSpacing.md,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: KoalaSpacing.sm),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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
          Container(
            width: 220,
            height: 14,
            color: KoalaColors.surfaceAlt,
          ),
          const SizedBox(height: KoalaSpacing.sm),
          Container(
            width: double.infinity,
            height: 22,
            color: KoalaColors.surfaceAlt,
          ),
          const SizedBox(height: KoalaSpacing.lg),
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: KoalaColors.surfaceAlt,
              borderRadius: BorderRadius.circular(KoalaRadius.pill),
            ),
          ),
          const SizedBox(height: KoalaSpacing.xl),
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
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: KoalaColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(KoalaRadius.pill),
                  ),
                ),
              ),
              const SizedBox(width: KoalaSpacing.md),
              Expanded(
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: KoalaColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(KoalaRadius.pill),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: KoalaSpacing.md),
        ],
      ),
    );
  }
}

class _DeckEmpty extends StatelessWidget {
  const _DeckEmpty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(KoalaSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: KoalaColors.accentSoft,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                LucideIcons.sparkles,
                color: KoalaColors.accentDeep,
                size: 26,
              ),
            ),
            const SizedBox(height: KoalaSpacing.lg),
            Text(
              'Şu an gösterecek kart yok',
              style: KoalaText.serif(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KoalaSpacing.sm),
            const Text(
              'Birazdan tekrar dener misin?',
              style: KoalaText.bodySec,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
