import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/koala_tokens.dart';
import '../../../services/saved_items_service.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Home'daki "Devam et" kartı — kullanıcının son kaydedilen restyle render'ı.
///
/// Retention loop'un görünür köşetaşı: uygulamayı tekrar açtığında gözüne ilk
/// çarpan şey kendi son tasarımı. Jenerik "hoş geldin" yerine "son bıraktığın
/// yerden devam et" hissi. Latest design yoksa widget kendini tamamen saklar
/// (SizedBox.shrink) — placeholder kirliliği yaratma.
///
/// Data: SavedItemsService.getByType(design, limit:1). Cache'siz — home her
/// build'de fetch edebilir, önemli değil (tek satır, Supabase <100ms).
class ContinueDesignCard extends StatefulWidget {
  const ContinueDesignCard({super.key});

  @override
  State<ContinueDesignCard> createState() => _ContinueDesignCardState();
}

class _ContinueDesignCardState extends State<ContinueDesignCard> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _future = SavedItemsService.getByType(SavedItemType.design, limit: 1);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final data = snap.data;
        if (data == null || data.isEmpty) return const SizedBox.shrink();
        final item = data.first;
        return _buildCard(context, item);
      },
    );
  }

  Widget _buildCard(BuildContext context, Map<String, dynamic> item) {
    final imageUrl = (item['image_url'] as String?) ?? '';
    final title = (item['title'] as String?) ?? 'Mekanın';
    final subtitle = (item['subtitle'] as String?) ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.xl),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () => context.push('/my-designs'),
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(KoalaRadius.xl),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Background fallback
                  const DecoratedBox(
                    decoration: BoxDecoration(
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
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                    ),
                  // Dark bottom gradient
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Color(0x33000000),
                          Color(0xEE000000),
                        ],
                        stops: [0.0, 0.55, 1.0],
                      ),
                    ),
                  ),
                  // Content
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
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  )
                                      .animate(
                                          onPlay: (c) => c.repeat(reverse: true))
                                      .fadeIn(duration: 900.ms),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'DEVAM ET',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.6,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 24,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.4,
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
                        const SizedBox(width: KoalaSpacing.md),
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            LucideIcons.arrowRight,
                            size: 20,
                            color: KoalaColors.text,
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
    )
        .animate()
        .fadeIn(duration: 420.ms)
        .slideY(begin: 0.08, end: 0, duration: 420.ms, curve: Curves.easeOutCubic);
  }
}
