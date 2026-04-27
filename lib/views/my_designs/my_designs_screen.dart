import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/koala_tokens.dart';
import '../../services/saved_items_service.dart';
import 'design_detail_screen.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// "Tasarımların" — kullanıcının kaydedilen restyle render'larını gösterir.
///
/// Design intent:
/// - Grid DEĞİL. 2'li grid Pinterest hissi verir, kişisel hissettirmez. Bu
///   ekran "senin evinin hikâyesi" gibi tek sütun cinematic feed.
/// - Her kart full-bleed 16:10 hero + alt overlay. Palette/room/zaman overlay
///   fotonun üstünde, kart altında metadata yok — ekranın her elemanı foto
///   odaklı.
/// - Empty state karakterli. "Henüz tasarım yok" jeneriği yerine bir resim +
///   CTA + sahte skeleton kart (preview nasıl görüneceğini gösterir).
/// - Pull-to-refresh, skeleton shimmer, micro-scale press — bütün detay.
///
/// Not: saved_items.image_url Vercel Blob ephemeral (24-72h). Liste açıldıkça
/// bazı kartlar 404 olabilir — CachedNetworkImage errorWidget ile `_brokenCard`
/// fallback gösteriyor. Supabase Storage migration Sprint B.
class MyDesignsScreen extends StatefulWidget {
  const MyDesignsScreen({super.key});

  @override
  State<MyDesignsScreen> createState() => _MyDesignsScreenState();
}

class _MyDesignsScreenState extends State<MyDesignsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() {
    return SavedItemsService.getByType(SavedItemType.design, limit: 100);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: KoalaColors.accentDeep,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return _skeleton();
              }
              if (snap.hasError) {
                return _errorView(snap.error.toString());
              }
              final items = snap.data ?? const [];
              if (items.isEmpty) {
                return _emptyView();
              }
              return _listView(items);
            },
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // List
  // ─────────────────────────────────────────────────────────

  Widget _listView(List<Map<String, dynamic>> items) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        _sliverHeader(count: items.length),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            KoalaSpacing.xl,
            KoalaSpacing.lg,
            KoalaSpacing.xl,
            KoalaSpacing.xxxl,
          ),
          sliver: SliverList.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: KoalaSpacing.lg),
            itemBuilder: (context, i) {
              final item = items[i];
              return _DesignCard(item: item, index: i);
            },
          ),
        ),
      ],
    );
  }

  SliverToBoxAdapter _sliverHeader({required int count}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          KoalaSpacing.xl,
          KoalaSpacing.lg,
          KoalaSpacing.xl,
          KoalaSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Geri butonu — sola yapışık
            _backButton(),
            const SizedBox(height: KoalaSpacing.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    'Tasarımların',
                    style: KoalaText.h1.copyWith(
                      fontSize: 34,
                      letterSpacing: -0.8,
                      height: 1.05,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: KoalaColors.accentSoft,
                    borderRadius: BorderRadius.circular(KoalaRadius.pill),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: KoalaColors.accentDeep,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'AI ile tasarladığın mekanlar',
              style: KoalaText.bodySec,
            ),
          ],
        )
            .animate()
            .fadeIn(duration: 420.ms)
            .slideY(begin: 0.1, end: 0, duration: 420.ms),
      ),
    );
  }

  Widget _backButton() {
    return GestureDetector(
      onTap: () {
        if (GoRouter.of(context).canPop()) {
          GoRouter.of(context).pop();
        } else {
          context.go('/');
        }
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: KoalaColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: KoalaColors.border, width: 0.5),
        ),
        alignment: Alignment.center,
        child: const Icon(LucideIcons.arrowLeft, size: 20),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // Skeleton / Empty / Error
  // ─────────────────────────────────────────────────────────

  Widget _skeleton() {
    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        _sliverHeader(count: 0),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            KoalaSpacing.xl,
            KoalaSpacing.lg,
            KoalaSpacing.xl,
            KoalaSpacing.xxxl,
          ),
          sliver: SliverList.separated(
            itemCount: 3,
            separatorBuilder: (_, _) =>
                const SizedBox(height: KoalaSpacing.lg),
            itemBuilder: (_, i) => _SkeletonCard(delayMs: 100 * i),
          ),
        ),
      ],
    );
  }

  Widget _emptyView() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _sliverHeader(count: 0).child ?? const SizedBox.shrink(),
        const SizedBox(height: KoalaSpacing.xxxl),
        Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  KoalaColors.accentSoft,
                  KoalaColors.accentSoft.withValues(alpha: 0),
                ],
              ),
            ),
            alignment: Alignment.center,
            child: const Icon(
              LucideIcons.sparkles,
              size: 52,
              color: KoalaColors.accentDeep,
            ),
          ),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scale(
              begin: const Offset(1, 1),
              end: const Offset(1.05, 1.05),
              duration: 1800.ms,
              curve: Curves.easeInOut,
            ),
        const SizedBox(height: KoalaSpacing.xl),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.xxl),
          child: Column(
            children: [
              Text(
                'Henüz mekan tasarlamadın',
                style: KoalaText.h2,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: KoalaSpacing.sm),
              Text(
                'Salonunun, yatak odanın ya da mutfağının '
                'bir fotoğrafını çek — Koala bambaşka hâlini göstersin.',
                style: KoalaText.bodySec.copyWith(height: 1.55),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: KoalaSpacing.xl),
              SizedBox(
                width: 220,
                child: FilledButton.icon(
                  onPressed: () {
                    if (GoRouter.of(context).canPop()) {
                      GoRouter.of(context).pop();
                    } else {
                      context.go('/');
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: KoalaColors.accentDeep,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(KoalaRadius.pill),
                    ),
                  ),
                  icon: const Icon(LucideIcons.camera, size: 18),
                  label: const Text(
                    'İlk mekanını çek',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(duration: 420.ms, delay: 100.ms);
  }

  Widget _errorView(String msg) {
    return ListView(
      children: [
        const SizedBox(height: KoalaSpacing.xxxl),
        const Center(
          child: Icon(LucideIcons.cloudOff, size: 48, color: KoalaColors.textTer),
        ),
        const SizedBox(height: KoalaSpacing.md),
        Center(
          child: Text('Yüklenemedi', style: KoalaText.h3),
        ),
        const SizedBox(height: KoalaSpacing.sm),
        Center(
          child: TextButton(
            onPressed: _refresh,
            child: const Text('Tekrar dene'),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// Design Card (full-bleed cinematic)
// ─────────────────────────────────────────────────────────

class _DesignCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final int index;
  const _DesignCard({required this.item, required this.index});

  @override
  State<_DesignCard> createState() => _DesignCardState();
}

class _DesignCardState extends State<_DesignCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final imageUrl = (widget.item['image_url'] as String?) ?? '';
    final title = (widget.item['title'] as String?) ?? 'Mekan';
    final subtitle = (widget.item['subtitle'] as String?) ?? '';
    final createdAt = widget.item['created_at']?.toString();

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () => _open(context),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: Hero(
          tag: 'design-${widget.item['id']}',
          child: Material(
            type: MaterialType.transparency,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(KoalaRadius.xl),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Background fill — yüklenirken ve hata durumunda gradient
                    DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            KoalaColors.accentSoft,
                            KoalaColors.surfaceAlt,
                          ],
                        ),
                      ),
                    ),
                    if (imageUrl.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        fadeInDuration: const Duration(milliseconds: 320),
                        errorWidget: (_, _, _) => _brokenOverlay(),
                      ),
                    // Alt gradient — metin okunabilirliği
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            Color(0xCC000000),
                          ],
                          stops: [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                    // Alt overlay — meta
                    Positioned(
                      left: KoalaSpacing.lg,
                      right: KoalaSpacing.lg,
                      bottom: KoalaSpacing.lg,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: -0.3,
                                    height: 1.1,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (subtitle.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    subtitle,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.white.withValues(alpha: 0.82),
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (createdAt != null)
                            Text(
                              _relativeTime(createdAt),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.65),
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(
          delay: (80 + widget.index * 70).ms,
          duration: 420.ms,
        )
        .slideY(
          begin: 0.15,
          end: 0,
          delay: (80 + widget.index * 70).ms,
          duration: 420.ms,
          curve: Curves.easeOutCubic,
        );
  }

  Widget _brokenOverlay() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: KoalaColors.surfaceAlt,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.imageOff,
              color: KoalaColors.textTer,
              size: 28,
            ),
            const SizedBox(height: 6),
            Text(
              'Görsel süresi doldu',
              style: KoalaText.bodySmall.copyWith(
                color: KoalaColors.textSec,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, _, _) => DesignDetailScreen(item: widget.item),
        transitionsBuilder: (_, anim, _, child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final int delayMs;
  const _SkeletonCard({required this.delayMs});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(KoalaRadius.xl),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Container(
          color: KoalaColors.surfaceAlt,
        )
            .animate(onPlay: (c) => c.repeat())
            .shimmer(
              delay: delayMs.ms,
              duration: 1400.ms,
              color: KoalaColors.surface.withValues(alpha: 0.6),
            ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────

String _relativeTime(String iso) {
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'ŞİMDİ';
  if (diff.inMinutes < 60) return '${diff.inMinutes} DK';
  if (diff.inHours < 24) return '${diff.inHours} SA';
  if (diff.inDays < 7) return '${diff.inDays} GÜN';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} HF';
  return '${(diff.inDays / 30).floor()} AY';
}

// NOT: SliverToBoxAdapter.child zaten public field — extension gereksizdi
// (eskisi self-referential recursion'a giriyordu). Doğrudan `.child` kullan.
