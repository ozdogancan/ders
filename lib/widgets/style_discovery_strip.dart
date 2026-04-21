// ═══════════════════════════════════════════════════════════
// STYLE DISCOVERY STRIP — input bar'ın üstünde yatay otomatik
// kayan 6 oda kartı. Her kart: temsili foto + sol-alt köşede
// glassmorphism label. Tap → SharedPreferences'a kategori filtresi
// yazılır + StyleDiscoveryPull.openProgrammatically() çağrılır —
// live screen initState'te prefs'ten kategoriyi okuyup deck'i
// filtreli yüklüyor.
//
// KATEGORİLER (Evlumba DB'deki gerçek `project_type` değerleri):
//   'Oturma Odası', 'Yatak Odası', 'Mutfak', 'Banyo', 'Antre'
//   + '' (Tümü) — 6. kart, filtersiz keşif
//
// PERFORMANS NOTLARI:
//   • Fotolar CDN'de (Unsplash), bundle'a binmiyor
//   • CachedNetworkImage disk cache + memCacheWidth/Height clamp
//     → RAM'de her kart max 400×540 raster (retina için yeterli)
//   • Auto-scroll Timer parmak dokununca pause, release'de resume
//   • URL bozulursa graceful gradient+icon fallback → sırıtmıyor
//   • BackdropFilter (glassmorphism) sadece görünen 2-3 kartta
//     mount oluyor — Flutter web CanvasKit için kabul edilebilir
//
// PULL GESTURE: Home'un page-level Listener'ı bu widget'ın
// üzerinden de geçer, yani yukarı swipe otomatik çalışır —
// strip ekstra pull handler'ı taşımıyor.
// ═══════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/koala_tokens.dart';

class _StripItem {
  /// DB'deki `project_type` değeri. '' → filtresiz (Tümü).
  final String categoryKey;
  final String imageUrl;
  final String label;
  final IconData fallbackIcon;
  final List<Color> fallbackGradient;
  const _StripItem({
    required this.categoryKey,
    required this.imageUrl,
    required this.label,
    required this.fallbackIcon,
    required this.fallbackGradient,
  });
}

/// 6 kart — 5 gerçek kategori + 1 "Tümü" (filtersiz keşif).
/// Sıra: en yaygın kullanım (oturma odası) → en niş (antre).
/// Dinamik sort-by-count'a geçmek istenirse:
/// `EvlumbaLiveService.client.from('designer_projects').select('project_type').count()`
/// benzeri bir agg ile başlangıçta bir kez sıralanabilir.
const _items = <_StripItem>[
  _StripItem(
    categoryKey: 'Oturma Odası',
    imageUrl:
        'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=400&h=540&q=75',
    label: 'Oturma Odası',
    fallbackIcon: LucideIcons.sofa,
    fallbackGradient: [Color(0xFFE5DEFF), Color(0xFFB5A7F0)],
  ),
  _StripItem(
    categoryKey: 'Yatak Odası',
    imageUrl:
        'https://images.unsplash.com/photo-1540518614846-7eded433c457?auto=format&fit=crop&w=400&h=540&q=75',
    label: 'Yatak Odası',
    fallbackIcon: LucideIcons.bed,
    fallbackGradient: [Color(0xFFFFE0E9), Color(0xFFE8B8C8)],
  ),
  _StripItem(
    categoryKey: 'Mutfak',
    imageUrl:
        'https://images.unsplash.com/photo-1556909114-f6e7ad7d3136?auto=format&fit=crop&w=400&h=540&q=75',
    label: 'Mutfak',
    fallbackIcon: LucideIcons.utensils,
    fallbackGradient: [Color(0xFFFFF0D6), Color(0xFFE8C988)],
  ),
  _StripItem(
    categoryKey: 'Banyo',
    imageUrl:
        'https://images.unsplash.com/photo-1552321554-5fefe8c9ef14?auto=format&fit=crop&w=400&h=540&q=75',
    label: 'Banyo',
    fallbackIcon: LucideIcons.bath,
    fallbackGradient: [Color(0xFFDDF3FF), Color(0xFFA8D5E8)],
  ),
  _StripItem(
    categoryKey: 'Antre',
    imageUrl:
        'https://images.unsplash.com/photo-1631679706909-1844bbd07221?auto=format&fit=crop&w=400&h=540&q=75',
    label: 'Antre',
    fallbackIcon: LucideIcons.doorOpen,
    fallbackGradient: [Color(0xFFE5EEDD), Color(0xFFA8C288)],
  ),
  _StripItem(
    categoryKey: '', // '' = Tümü (filtersiz)
    imageUrl:
        'https://images.unsplash.com/photo-1586023492125-27b2c045efd7?auto=format&fit=crop&w=400&h=540&q=75',
    label: 'Tümü',
    fallbackIcon: LucideIcons.sparkles,
    fallbackGradient: [Color(0xFFEDE9FE), Color(0xFF6366F1)],
  ),
];

class StyleDiscoveryStrip extends StatefulWidget {
  const StyleDiscoveryStrip({super.key, required this.onCardTap});

  /// Kart tıklandığında çağrılır — `categoryKey` DB'deki
  /// project_type değeri ('' = Tümü). Home_screen bu callback'te
  /// prefs'e yazıp `_pullKey.currentState?.openProgrammatically()`
  /// çağırıyor.
  final void Function(String categoryKey) onCardTap;

  @override
  State<StyleDiscoveryStrip> createState() => _StyleDiscoveryStripState();
}

class _StyleDiscoveryStripState extends State<StyleDiscoveryStrip> {
  static const double _cardWidth = 148;
  static const double _cardHeight = 188;
  static const double _cardSpacing = 10;
  static const double _stride = _cardWidth + _cardSpacing;
  static const Duration _tick = Duration(milliseconds: 2800);
  static const Duration _slide = Duration(milliseconds: 700);

  final _scrollCtrl = ScrollController();
  Timer? _autoTimer;
  bool _userInteracting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  void _start() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(_tick, (_) {
      if (!mounted || !_scrollCtrl.hasClients || _userInteracting) return;
      final cur = _scrollCtrl.offset;
      final max = _scrollCtrl.position.maxScrollExtent;
      final next = cur + _stride;
      if (next >= max - 0.5) {
        _scrollCtrl.animateTo(
          0,
          duration: _slide,
          curve: Curves.easeInOutCubic,
        );
      } else {
        _scrollCtrl.animateTo(
          next,
          duration: _slide,
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  void _pause() => _userInteracting = true;
  void _resume() => _userInteracting = false;

  @override
  void dispose() {
    _autoTimer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _pause(),
      onPointerUp: (_) => _resume(),
      onPointerCancel: (_) => _resume(),
      child: SizedBox(
        height: _cardHeight,
        child: ListView.separated(
          controller: _scrollCtrl,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          physics: const BouncingScrollPhysics(),
          itemCount: _items.length,
          separatorBuilder: (_, _) => const SizedBox(width: _cardSpacing),
          itemBuilder: (_, i) => _StripCard(
            item: _items[i],
            width: _cardWidth,
            height: _cardHeight,
            onTap: () => widget.onCardTap(_items[i].categoryKey),
          ),
        ),
      ),
    );
  }
}

class _StripCard extends StatelessWidget {
  const _StripCard({
    required this.item,
    required this.width,
    required this.height,
    required this.onTap,
  });

  final _StripItem item;
  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ─── Foto (CDN) + fallback gradient ───
              CachedNetworkImage(
                imageUrl: item.imageUrl,
                fit: BoxFit.cover,
                memCacheWidth: 400,
                memCacheHeight: 540,
                fadeInDuration: const Duration(milliseconds: 220),
                placeholder: (_, _) => _FallbackBg(item: item),
                errorWidget: (_, _, _) => _FallbackBg(item: item),
              ),
              // ─── Alt gradient scrim — label okunabilirliği için ───
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.05),
                          Colors.black.withValues(alpha: 0.38),
                        ],
                        stops: const [0.55, 0.75, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              // ─── Sol-alt glassmorphism label ───
              Positioned(
                left: 10,
                bottom: 10,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 0.6,
                        ),
                      ),
                      child: Text(
                        item.label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.15,
                          height: 1.1,
                        ),
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

/// URL yüklenmez / placeholder fazında gösterilen güzel fallback —
/// Item'a özel gradient + merkezde ikon. Boş kare yerine bu.
class _FallbackBg extends StatelessWidget {
  const _FallbackBg({required this.item});
  final _StripItem item;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: item.fallbackGradient,
        ),
      ),
      child: Center(
        child: Icon(
          item.fallbackIcon,
          size: 40,
          color: KoalaColors.ink.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

/// Prefs helper — strip tap handler'ı home_screen'de bunu çağırıyor.
/// StyleDiscoveryLiveScreen initState'inde aynı key okunuyor.
Future<void> writeStyleDiscoveryCategory(String categoryKey) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('style_discovery_category', categoryKey);
}
