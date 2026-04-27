import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/koala_tokens.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PUBLIC DTOs
// ═══════════════════════════════════════════════════════════════════════════

/// Hafif designer-project temsili — swipe ekranı için gereken tek-kart bilgisi.
/// Pro match'taki ağır _Project'in aksine: sadece görsel + başlık + tag.
/// Decluttered card UX'i — designer / fiyat / similarity gösterilmiyor.
class DesignerProjectLite {
  final String id;
  final String title;
  final String projectType; // ör. "yatak odası", "salon"
  final String coverUrl;
  final List<String> tags;

  const DesignerProjectLite({
    required this.id,
    required this.title,
    required this.projectType,
    required this.coverUrl,
    required this.tags,
  });
}

/// Swipe sonucu çıkarılan stil özeti — restyle prompt'unu zenginleştirmek
/// ve background prefetch'i tetiklemek için kullanılır.
class StyleDiscoveryPreview {
  final List<String> lovedTags;
  final List<String>? lovedColors;
  final String? mood;

  const StyleDiscoveryPreview({
    required this.lovedTags,
    this.lovedColors,
    this.mood,
  });
}

/// Sheet'in dönüş değeri.
/// - `confirmed: true`  → kullanıcı reveal ekranında "Evet, tasarla"ya bastı
/// - `confirmed: false` → şu an üretilmiyor; null dönerse "atla" anlamı
class StyleSwipeResult {
  final bool confirmed;
  final StyleDiscoveryPreview preview;
  final List<String> lovedProjectIds;

  const StyleSwipeResult({
    required this.confirmed,
    required this.preview,
    required this.lovedProjectIds,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// SHEET
// ═══════════════════════════════════════════════════════════════════════════

/// "Tarzını Keşfedelim" — kullanıcı restyle istediğinde stil güveni düşükse
/// (analyze confidence < 0.65) açılan modal. 6 designer projesi tek-tek
/// kart olarak gelir, swipe ile sevdim/atla. 5. swipe'ta `onPrefetchReady`
/// tetiklenir → restyle arka planda hazırlanır. Reveal ekranında kullanıcı
/// "Evet, tasarla" derken üretim genelde %60-80 tamam.
///
/// Tasarım niyeti: SnapHome benzeri sade swipe; Koala sıcak-krem; başlıkta
/// Fraunces serif, body bodySec; flutter_animate giriş; emoji yok; Lucide.
class StyleSwipeSheet extends StatefulWidget {
  final String roomTypeGuess;
  final List<DesignerProjectLite> candidateProjects;
  final void Function(StyleDiscoveryPreview)? onPrefetchReady;

  const StyleSwipeSheet({
    super.key,
    required this.roomTypeGuess,
    required this.candidateProjects,
    this.onPrefetchReady,
  });

  /// Sheet'i göster. Kart listesi boşsa çağıran taraf yine de güvenli — sheet
  /// kullanıcıya "atla" sunar ve null döner. Kullanıcı "Evet, tasarla" derse
  /// `StyleSwipeResult(confirmed: true, ...)` döner.
  static Future<StyleSwipeResult?> show(
    BuildContext context, {
    required String roomTypeGuess,
    required List<DesignerProjectLite> candidateProjects,
    void Function(StyleDiscoveryPreview)? onPrefetchReady,
  }) {
    return showModalBottomSheet<StyleSwipeResult?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => StyleSwipeSheet(
        roomTypeGuess: roomTypeGuess,
        candidateProjects: candidateProjects,
        onPrefetchReady: onPrefetchReady,
      ),
    );
  }

  @override
  State<StyleSwipeSheet> createState() => _StyleSwipeSheetState();
}

enum _Stage { intro, swipe, reveal }

class _StyleSwipeSheetState extends State<StyleSwipeSheet> {
  _Stage _stage = _Stage.intro;

  /// Kart sırası — sabit 6 ile sınırlanır (varsa). Eksikse mevcut kadar.
  late final List<DesignerProjectLite> _deck;
  int _index = 0;
  final List<DesignerProjectLite> _loved = [];
  bool _prefetchFired = false;

  @override
  void initState() {
    super.initState();
    _deck = widget.candidateProjects.take(6).toList();
  }

  void _start() {
    // Boş deck → swipe'a girmenin anlamı yok. Doğrudan reveal'a düş;
    // reveal lovedTags boşken kullanıcıya "henüz net değil, manuel
    // seçelim" hissi vermeden "atla" akışıyla aynı sonucu verir.
    if (_deck.isEmpty) {
      Navigator.of(context).pop(); // null = atla
      return;
    }
    setState(() => _stage = _Stage.swipe);
  }

  void _skip() {
    Navigator.of(context).pop();
  }

  void _onSwipe({required bool liked}) {
    if (_index >= _deck.length) return;
    final card = _deck[_index];
    if (liked) _loved.add(card);

    final nextIndex = _index + 1;

    // 5. swipe (index 4 sonrası, yani 5 oy verildi) → prefetch tetikle.
    // Reveal'a varmadan üretim arka planda başlar.
    if (!_prefetchFired && nextIndex >= 5) {
      _prefetchFired = true;
      final preview = _buildPreview();
      widget.onPrefetchReady?.call(preview);
    }

    if (nextIndex >= _deck.length) {
      setState(() {
        _index = nextIndex;
        _stage = _Stage.reveal;
      });
    } else {
      setState(() => _index = nextIndex);
    }
  }

  /// Loved kartlardan top-N tag'i toparla (sıra korunarak, dedup'lu).
  StyleDiscoveryPreview _buildPreview() {
    final seen = <String>{};
    final tags = <String>[];
    for (final p in _loved) {
      for (final t in p.tags) {
        final norm = t.trim();
        if (norm.isEmpty) continue;
        if (seen.add(norm.toLowerCase())) {
          tags.add(norm);
        }
      }
    }
    return StyleDiscoveryPreview(lovedTags: tags);
  }

  void _confirm() {
    final preview = _buildPreview();
    Navigator.of(context).pop(
      StyleSwipeResult(
        confirmed: true,
        preview: preview,
        lovedProjectIds: _loved.map((e) => e.id).toList(),
      ),
    );
  }

  void _restartSwipe() {
    setState(() {
      _loved.clear();
      _index = 0;
      _prefetchFired = false;
      _stage = _Stage.swipe;
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.92;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: KoalaColors.bg,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KoalaRadius.xl),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle — pro_match_sheet ile birebir aynı.
            Padding(
              padding: const EdgeInsets.only(top: KoalaSpacing.md),
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KoalaColors.borderMed,
                    borderRadius: BorderRadius.circular(KoalaRadius.pill),
                  ),
                ),
              ),
            ),
            const SizedBox(height: KoalaSpacing.lg),
            Flexible(child: _buildStage()),
          ],
        ),
      ),
    );
  }

  Widget _buildStage() {
    switch (_stage) {
      case _Stage.intro:
        return _IntroView(
          key: const ValueKey('intro'),
          onStart: _start,
          onSkip: _skip,
        );
      case _Stage.swipe:
        return _SwipeView(
          key: ValueKey('swipe-$_index'),
          card: _deck[_index],
          index: _index,
          total: _deck.length,
          onLike: () => _onSwipe(liked: true),
          onSkip: () => _onSwipe(liked: false),
        );
      case _Stage.reveal:
        return _RevealView(
          key: const ValueKey('reveal'),
          loved: _loved,
          roomTypeGuess: widget.roomTypeGuess,
          onConfirm: _confirm,
          onRestart: _restartSwipe,
        );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGE 1 — INTRO
// ═══════════════════════════════════════════════════════════════════════════

class _IntroView extends StatelessWidget {
  final VoidCallback onStart;
  final VoidCallback onSkip;

  const _IntroView({super.key, required this.onStart, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KoalaSpacing.xl,
        KoalaSpacing.lg,
        KoalaSpacing.xl,
        KoalaSpacing.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Soft icon — Koala sıcak-krem accent.
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: KoalaColors.accentSoft,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(LucideIcons.sparkles,
                  color: KoalaColors.accentDeep, size: 26),
            ),
          ).animate(delay: 80.ms).fadeIn(duration: 250.ms).slideY(
                begin: 0.06,
                end: 0,
                duration: 250.ms,
                curve: Curves.easeOutCubic,
              ),
          const SizedBox(height: KoalaSpacing.xl),
          Text(
            'Sana 6 kart gösterelim, zevkini hızlıca anlayalım.',
            style: KoalaText.serif(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ).animate(delay: 80.ms).fadeIn(duration: 250.ms).slideY(
                begin: 0.06,
                end: 0,
                duration: 250.ms,
                curve: Curves.easeOutCubic,
              ),
          const SizedBox(height: KoalaSpacing.md),
          const Text(
            'Beğen ya da geç — birkaç saniye sürer.',
            style: KoalaText.bodySec,
            textAlign: TextAlign.center,
          ).animate(delay: 120.ms).fadeIn(duration: 250.ms),
          const SizedBox(height: KoalaSpacing.xxl),
          FilledButton(
            onPressed: onStart,
            style: FilledButton.styleFrom(
              backgroundColor: KoalaColors.accentDeep,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(KoalaRadius.md),
              ),
              textStyle: KoalaText.button,
            ),
            child: const Text('Başla'),
          ).animate(delay: 220.ms).fadeIn(duration: 220.ms),
          const SizedBox(height: KoalaSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Atla, doğrudan tasarla',
                style: KoalaText.label.copyWith(color: KoalaColors.textSec),
              ),
            ),
          ).animate(delay: 280.ms).fadeIn(duration: 220.ms),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGE 2 — SWIPE
// ═══════════════════════════════════════════════════════════════════════════

class _SwipeView extends StatefulWidget {
  final DesignerProjectLite card;
  final int index;
  final int total;
  final VoidCallback onLike;
  final VoidCallback onSkip;

  const _SwipeView({
    super.key,
    required this.card,
    required this.index,
    required this.total,
    required this.onLike,
    required this.onSkip,
  });

  @override
  State<_SwipeView> createState() => _SwipeViewState();
}

class _SwipeViewState extends State<_SwipeView> {
  // Drag state — kullanıcının kartı yatay sürüklemesi sırasındaki offset.
  // Dikkat: tek kart gösteriyoruz, dolayısıyla bu state widget bazında
  // sıfırlanıyor (key her index değişiminde değişiyor → otomatik reset).
  double _dragX = 0;

  // Flutter'ın drag eşiği — bu eşik aşılırsa swipe sayılır.
  static const _swipeThreshold = 100.0;

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() => _dragX += d.delta.dx);
  }

  void _onPanEnd(DragEndDetails d) {
    if (_dragX > _swipeThreshold) {
      widget.onLike();
    } else if (_dragX < -_swipeThreshold) {
      widget.onSkip();
    } else {
      setState(() => _dragX = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final progress = '${widget.index + 1}/${widget.total}';

    // Kart rotasyonu — sürükleme miktarına göre hafif eğilir.
    final rotation = (_dragX / 400).clamp(-0.12, 0.12);
    final likeOpacity = (_dragX / 120).clamp(0.0, 1.0);
    final skipOpacity = (-_dragX / 120).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KoalaSpacing.xl,
        0,
        KoalaSpacing.xl,
        KoalaSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Progress dots — sade, hangi kartta olduğumuzu gösterir.
          _ProgressDots(current: widget.index, total: widget.total),
          const SizedBox(height: KoalaSpacing.sm),
          Center(
            child: Text(
              progress,
              style: KoalaText.bodySmall,
            ),
          ),
          const SizedBox(height: KoalaSpacing.lg),
          // Kart — sürüklenebilir, hafif rotate, like/skip overlay'leri.
          Flexible(
            child: GestureDetector(
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: Transform.translate(
                offset: Offset(_dragX, 0),
                child: Transform.rotate(
                  angle: rotation,
                  child: Stack(
                    children: [
                      _ProjectCard(card: card)
                          .animate(delay: 220.ms)
                          .fadeIn(duration: 280.ms)
                          .slideY(
                            begin: 0.06,
                            end: 0,
                            duration: 320.ms,
                            curve: Curves.easeOutCubic,
                          ),
                      // Like overlay
                      if (likeOpacity > 0)
                        Positioned(
                          top: KoalaSpacing.lg,
                          left: KoalaSpacing.lg,
                          child: Opacity(
                            opacity: likeOpacity,
                            child: _OverlayBadge(
                              icon: LucideIcons.heart,
                              label: 'Sevdim',
                              color: KoalaColors.like,
                            ),
                          ),
                        ),
                      // Skip overlay
                      if (skipOpacity > 0)
                        Positioned(
                          top: KoalaSpacing.lg,
                          right: KoalaSpacing.lg,
                          child: Opacity(
                            opacity: skipOpacity,
                            child: _OverlayBadge(
                              icon: LucideIcons.x,
                              label: 'Atla',
                              color: KoalaColors.dislike,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: KoalaSpacing.xl),
          // Aksiyon butonları — mobilde başparmak için iri.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _CircleButton(
                icon: LucideIcons.x,
                color: KoalaColors.dislike,
                onTap: widget.onSkip,
              )
                  .animate(delay: 280.ms)
                  .fadeIn(duration: 240.ms)
                  .slideY(begin: 0.1, end: 0, duration: 280.ms),
              _CircleButton(
                icon: LucideIcons.heart,
                color: KoalaColors.like,
                onTap: widget.onLike,
              )
                  .animate(delay: 320.ms)
                  .fadeIn(duration: 240.ms)
                  .slideY(begin: 0.1, end: 0, duration: 280.ms),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  final int current;
  final int total;
  const _ProgressDots({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < total; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              width: i == current ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i <= current
                    ? KoalaColors.accentDeep
                    : KoalaColors.borderMed,
                borderRadius: BorderRadius.circular(KoalaRadius.pill),
              ),
            ),
          ),
      ],
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final DesignerProjectLite card;
  const _ProjectCard({required this.card});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(KoalaRadius.lg),
        border: Border.all(color: KoalaColors.border, width: 0.5),
        boxShadow: KoalaShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: card.coverUrl.isNotEmpty
                ? Image.network(
                    card.coverUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: KoalaColors.surfaceAlt,
                      alignment: Alignment.center,
                      child: const Icon(LucideIcons.image,
                          color: KoalaColors.textTer, size: 28),
                    ),
                  )
                : Container(color: KoalaColors.surfaceAlt),
          ),
          Padding(
            padding: const EdgeInsets.all(KoalaSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  card.title.isEmpty ? 'İsimsiz proje' : card.title,
                  style: KoalaText.serif(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (card.projectType.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    card.projectType,
                    style: KoalaText.bodySec.copyWith(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (card.tags.isNotEmpty) ...[
                  const SizedBox(height: KoalaSpacing.md),
                  Wrap(
                    spacing: KoalaSpacing.xs + 2,
                    runSpacing: KoalaSpacing.xs,
                    children: card.tags
                        .take(3)
                        .map((t) => _TagChip(label: t))
                        .toList(),
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
        horizontal: KoalaSpacing.sm + 2,
        vertical: KoalaSpacing.xs,
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

class _OverlayBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _OverlayBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KoalaSpacing.md,
        vertical: KoalaSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(KoalaRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CircleButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KoalaColors.surface,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: color, size: 26),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGE 3 — REVEAL
// ═══════════════════════════════════════════════════════════════════════════

class _RevealView extends StatelessWidget {
  final List<DesignerProjectLite> loved;
  final String roomTypeGuess;
  final VoidCallback onConfirm;
  final VoidCallback onRestart;

  const _RevealView({
    super.key,
    required this.loved,
    required this.roomTypeGuess,
    required this.onConfirm,
    required this.onRestart,
  });

  /// Loved kartlardan top 3 dedup'lu tag — Türkçe başlığı kurmak için.
  List<String> _topTags() {
    final seen = <String>{};
    final out = <String>[];
    for (final p in loved) {
      for (final t in p.tags) {
        final norm = t.trim();
        if (norm.isEmpty) continue;
        if (seen.add(norm.toLowerCase())) {
          out.add(norm);
          if (out.length >= 3) return out;
        }
      }
    }
    return out;
  }

  /// Oda anahtarı → Türkçe genitif ("yatak odanı", "salonunu", "mutfağını").
  /// CTA'da: "Bu zevkte {yatak odanı} tasarlayalım mı?"
  String _roomGenitive(String key) {
    final k = key.toLowerCase();
    if (k.contains('bed')) return 'yatak odanı';
    if (k.contains('living') || k.contains('salon')) return 'salonunu';
    if (k.contains('kitchen') || k.contains('mutfak')) return 'mutfağını';
    if (k.contains('bath') || k.contains('banyo')) return 'banyonu';
    if (k.contains('dining') || k.contains('yemek')) return 'yemek odanı';
    if (k.contains('office') || k.contains('study')) return 'çalışma odanı';
    if (k.contains('entry') || k.contains('hall') || k.contains('antre')) {
      return 'antreni';
    }
    return 'mekanını';
  }

  @override
  Widget build(BuildContext context) {
    final tags = _topTags();
    final hasTags = tags.isNotEmpty;
    final taglineMain = hasTags ? tags.join(' · ') : 'Henüz net değil';
    final mood = _roomGenitive(roomTypeGuess);
    final boards = loved.take(3).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KoalaSpacing.xl,
        KoalaSpacing.lg,
        KoalaSpacing.xl,
        KoalaSpacing.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Zevkin',
            style: KoalaText.caption,
            textAlign: TextAlign.center,
          ).animate(delay: 80.ms).fadeIn(duration: 240.ms),
          const SizedBox(height: KoalaSpacing.lg),
          // Mood-board — sevilen 3 kart, hafif overlap, soft shadow.
          if (boards.isNotEmpty)
            SizedBox(
              height: 140,
              child: _MoodBoard(boards: boards)
                  .animate(delay: 80.ms)
                  .fadeIn(duration: 280.ms)
                  .slideY(
                    begin: 0.06,
                    end: 0,
                    duration: 320.ms,
                    curve: Curves.easeOutCubic,
                  ),
            )
          else
            // Hiç sevdiği yoksa nötr placeholder — kullanıcıyı suçlamadan.
            Container(
              height: 140,
              decoration: BoxDecoration(
                color: KoalaColors.surfaceAlt,
                borderRadius: BorderRadius.circular(KoalaRadius.lg),
              ),
              alignment: Alignment.center,
              child: const Icon(LucideIcons.heartOff,
                  color: KoalaColors.textTer, size: 28),
            ),
          const SizedBox(height: KoalaSpacing.xl),
          Text(
            taglineMain,
            style: KoalaText.serif(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ).animate(delay: 120.ms).fadeIn(duration: 280.ms).slideY(
                begin: 0.06,
                end: 0,
                duration: 320.ms,
                curve: Curves.easeOutCubic,
              ),
          const SizedBox(height: KoalaSpacing.sm),
          Text(
            'Bu zevkte $mood tasarlayalım mı?',
            style: KoalaText.bodySec,
            textAlign: TextAlign.center,
          ).animate(delay: 160.ms).fadeIn(duration: 280.ms),
          const SizedBox(height: KoalaSpacing.xxl),
          FilledButton(
            onPressed: onConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: KoalaColors.accentDeep,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(KoalaRadius.md),
              ),
              textStyle: KoalaText.button,
            ),
            child: const Text('Evet, tasarla'),
          ).animate(delay: 220.ms).fadeIn(duration: 240.ms),
          const SizedBox(height: KoalaSpacing.sm),
          TextButton(
            onPressed: onRestart,
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
            child: Text(
              'Yeniden swipe',
              style: KoalaText.label.copyWith(color: KoalaColors.textSec),
            ),
          ).animate(delay: 280.ms).fadeIn(duration: 240.ms),
        ],
      ),
    );
  }
}

class _MoodBoard extends StatelessWidget {
  final List<DesignerProjectLite> boards;
  const _MoodBoard({required this.boards});

  static const double _tileW = 110;
  static const double _tileH = 130;
  static const double _overlap = 18; // px overlap arası

  @override
  Widget build(BuildContext context) {
    // 3 kart, hafif rotate + Stack ile overlap → derinlik hissi.
    // Ortadaki kart en üstte ve düz; yan kartlar geriye doğru hafif eğimli.
    final n = boards.length.clamp(0, 3);
    if (n == 0) return const SizedBox.shrink();

    final stride = _tileW - _overlap;
    final totalWidth = _tileW + (n - 1) * stride;
    final rotations = n == 1 ? [0.0] : (n == 2 ? [-0.04, 0.04] : [-0.06, 0.0, 0.06]);
    // zIndex: ortadaki en üstte → render sırasını ayarlıyoruz.
    final order = n == 3 ? [0, 2, 1] : List<int>.generate(n, (i) => i);

    return Center(
      child: SizedBox(
        width: totalWidth,
        height: _tileH + 8,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final i in order)
              Positioned(
                left: i * stride,
                top: i == 1 ? 0 : 4,
                child: Transform.rotate(
                  angle: rotations[i],
                  child: _MoodTile(card: boards[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MoodTile extends StatelessWidget {
  final DesignerProjectLite card;
  const _MoodTile({required this.card});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _MoodBoard._tileW,
      height: _MoodBoard._tileH,
      decoration: BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(KoalaRadius.md),
        border: Border.all(color: KoalaColors.border, width: 0.5),
        boxShadow: KoalaShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: card.coverUrl.isNotEmpty
          ? Image.network(
              card.coverUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  Container(color: KoalaColors.surfaceAlt),
            )
          : Container(color: KoalaColors.surfaceAlt),
    );
  }
}
