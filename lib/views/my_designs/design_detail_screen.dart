import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/koala_tokens.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Tasarım detay — tam ekran sinematik görüntüleyici.
///
/// Tasarım kararları:
/// - Arka plan SİYAH. Foto hero transition'dan geliyor, chrome minimal.
/// - Scroll yok, tek view. Üstte küçük kapat butonu, altta blur'lu info bar.
/// - İnfo bar: başlık + tarz chip'i + "Pro ile tasarla" CTA. Başka bir şey yok.
/// - DoubleTap ile paylaş/indir sprint sonrası (şimdi sessiz).
class DesignDetailScreen extends StatelessWidget {
  final Map<String, dynamic> item;
  const DesignDetailScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final imageUrl = (item['image_url'] as String?) ?? '';
    final title = (item['title'] as String?) ?? 'Mekan';
    final subtitle = (item['subtitle'] as String?) ?? '';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Hero foto
            Hero(
              tag: 'design-${item['id']}',
              child: Center(
                child: imageUrl.isEmpty
                    ? _broken()
                    : CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                        fadeInDuration: const Duration(milliseconds: 240),
                        errorWidget: (_, _, _) => _broken(),
                      ),
              ),
            ),
            // Üst gradient (kapat butonu okunabilirliği)
            const Positioned(
              top: 0, left: 0, right: 0, height: 140,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x99000000), Colors.transparent],
                  ),
                ),
              ),
            ),
            // Alt gradient (info bar)
            const Positioned(
              bottom: 0, left: 0, right: 0, height: 260,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xEE000000)],
                  ),
                ),
              ),
            ),
            // Kapat
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: KoalaSpacing.md,
              child: _CircleBtn(
                icon: LucideIcons.x,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            // İnfo bar
            Positioned(
              left: 0, right: 0,
              bottom: MediaQuery.of(context).padding.bottom + KoalaSpacing.lg,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: KoalaSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.4,
                        height: 1.1,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius:
                                BorderRadius.circular(KoalaRadius.pill),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.18),
                                width: 0.5),
                          ),
                          child: Text(
                            subtitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: KoalaSpacing.lg),
                    // Pro CTA — tek iş odağı
                    FilledButton.icon(
                      onPressed: () {
                        // TODO: pro match akışına push — şimdilik snackbar
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Pro eşleştirme yakında — tarzına uygun iç mimarları hazırlıyoruz.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: KoalaColors.text,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(KoalaRadius.pill),
                        ),
                      ),
                      icon: const Icon(LucideIcons.sparkles, size: 18),
                      label: const Text(
                        'Bu tarzda bir pro ile tasarla',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ).animate().fadeIn(duration: 360.ms, delay: 180.ms).slideY(
                      begin: 0.12,
                      end: 0,
                      duration: 360.ms,
                      delay: 180.ms,
                      curve: Curves.easeOutCubic,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _broken() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.imageOff,
              color: Colors.white54, size: 40),
          const SizedBox(height: 10),
          Text(
            'Görsel süresi doldu',
            style: KoalaText.bodySec.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.18), width: 0.5),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
