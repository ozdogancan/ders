// ═══════════════════════════════════════════════════════════
// STYLE DISCOVERY PULL — input bar'ın üstünde "Tarzını Keşfet"
// chip'i. Kullanıcı sayfanın HERHANGİ BİR YERİNDEN yukarı
// kaydırınca sheet parmağı takip eder. Eşiğe ulaşıp bırakınca
// StyleDiscoveryLiveScreen açılır (login) veya
// StyleDiscoveryGuestLanding açılır (misafir).
//
// Chip'e tıklayınca da aynı akış tetiklenir.
//
// External drag: Home Screen body içindeki pointer eventlerini
// [beginExternalDrag] / [updateExternalDrag] / [endExternalDrag]
// üzerinden iletir.
// ═══════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/koala_tokens.dart';
import '../services/evlumba_live_service.dart';
import '../views/style_discovery_live_screen.dart';

class StyleDiscoveryPull extends StatefulWidget {
  const StyleDiscoveryPull({
    super.key,
    required this.child,
    this.totalCountBuilder,
    this.showHandleStrip = true,
  });

  final Widget child;
  final Future<int> Function()? totalCountBuilder;

  /// Görünür "Tarzını Keşfet" chip'ini gösterip göstermeyeceği.
  /// false ise gesture sistemi (whole-page swipe-up) çalışmaya devam eder
  /// ama visible chip kaybolur. 2026-04-27 ana sayfa redesign'da kapatıldı.
  final bool showHandleStrip;

  @override
  State<StyleDiscoveryPull> createState() => StyleDiscoveryPullState();
}

class StyleDiscoveryPullState extends State<StyleDiscoveryPull>
    with TickerProviderStateMixin {
  // ─── Drag state ───
  double _dragY = 0;
  bool _dragging = false;
  bool _opening = false;

  // ─── Spring-back controller ───
  late final AnimationController _releaseCtrl;
  double _releaseStart = 0;

  // ─── Idle chip nefes animasyonu ───
  late final AnimationController _idleCtrl;

  // ─── Threshold-cross bump animation ───
  late final AnimationController _bumpCtrl;
  bool _bumpedThisDrag = false;

  // ─── Onboarding hint animation ───
  late final AnimationController _hintCtrl;
  double _hintY = 0;
  bool _playingHint = false;

  // ─── Background prefetch ───
  bool _prefetching = false;
  bool _prefetchKicked = false;

  double _threshold(BuildContext ctx) =>
      MediaQuery.of(ctx).size.height * 0.30;

  @override
  void initState() {
    super.initState();
    _releaseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..addListener(() {
        if (!_dragging) {
          setState(() {
            _dragY = _releaseStart *
                (1 - Curves.easeOutCubic.transform(_releaseCtrl.value));
          });
        }
      });

    _idleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _bumpCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _hintCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..addListener(() {
        setState(() {
          // 0 → peak (60px) → back to 0
          final t = _hintCtrl.value;
          final eased = t < 0.5
              ? Curves.easeOutCubic.transform(t * 2)
              : 1 - Curves.easeInCubic.transform((t - 0.5) * 2);
          _hintY = 60 * eased;
        });
      });
  }

  @override
  void dispose() {
    _releaseCtrl.dispose();
    _idleCtrl.dispose();
    _bumpCtrl.dispose();
    _hintCtrl.dispose();
    super.dispose();
  }

  bool _isAtThreshold() {
    if (!mounted) return false;
    return _dragY >= _threshold(context);
  }

  // ─── External API ───
  void beginExternalDrag() => _onDragStart();
  void updateExternalDrag(double deltaDy) => _onDragDelta(deltaDy);
  void endExternalDrag(double velocityY) => _onDragEnd(velocityY);
  bool get isDragging => _dragging;

  /// Onboarding ipucu — chip'i 60px yukarı oynat, yumuşakça geri indir,
  /// 2 kez tekrarla. SharedPreferences check home_screen'de yapılıyor.
  Future<void> playOnboardingHint() async {
    if (_playingHint || _dragging || _opening) return;
    _playingHint = true;
    for (int i = 0; i < 2; i++) {
      HapticFeedback.lightImpact();
      await _hintCtrl.forward(from: 0);
      _hintCtrl.reset();
      _hintY = 0;
      if (mounted) setState(() {});
      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
    }
    _playingHint = false;
  }

  void _onDragStart([DragStartDetails? _]) {
    if (_opening) return;
    setState(() {
      _dragging = true;
      _bumpedThisDrag = false;
      _releaseCtrl.stop();
    });
    _kickPrefetch();
  }

  void _onDragUpdate(DragUpdateDetails d) => _onDragDelta(d.delta.dy);

  void _onDragDelta(double dy) {
    if (_opening) return;
    final next = math.max(0, _dragY - dy);
    setState(() => _dragY = next.toDouble());
    // Eşik geçilince tek seferlik haptic + bump animasyonu
    if (!_bumpedThisDrag && _isAtThreshold()) {
      _bumpedThisDrag = true;
      HapticFeedback.mediumImpact();
      _bumpCtrl.forward(from: 0);
    } else if (_bumpedThisDrag && !_isAtThreshold()) {
      _bumpedThisDrag = false;
    }
  }

  void _onDragEndDetails(DragEndDetails d) {
    _onDragEnd(d.velocity.pixelsPerSecond.dy);
  }

  void _onDragEnd(double velocityY) {
    if (_opening) return;
    if (velocityY < -900) {
      _open();
      return;
    }
    if (_isAtThreshold()) {
      _open();
      return;
    }
    _springBack();
  }

  void _springBack() {
    setState(() {
      _dragging = false;
      _releaseStart = _dragY;
    });
    _releaseCtrl.forward(from: 0);
  }

  Future<void> _kickPrefetch() async {
    if (_prefetchKicked || _prefetching) return;
    _prefetchKicked = true;
    _prefetching = true;
    try {
      if (!EvlumbaLiveService.isReady) return;
      final batch = await EvlumbaLiveService.getProjects(limit: 10);
      final covers = <String>[];
      for (final p in batch) {
        final imgs = p['designer_project_images'] as List?;
        if (imgs == null || imgs.isEmpty) continue;
        final sorted = List<Map<String, dynamic>>.from(
          imgs.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
        )..sort((a, b) =>
            ((a['sort_order'] as num?)?.toInt() ?? 9999)
                .compareTo((b['sort_order'] as num?)?.toInt() ?? 9999));
        final url = (sorted.first['image_url'] ?? '').toString();
        if (url.isNotEmpty && !url.startsWith('data:')) covers.add(url);
      }
      if (mounted) {
        for (final url in covers.take(4)) {
          precacheImage(CachedNetworkImageProvider(url), context);
        }
      }
    } catch (_) {
    } finally {
      _prefetching = false;
    }
  }

  bool _isGuest() {
    final u = FirebaseAuth.instance.currentUser;
    return u == null || u.isAnonymous;
  }

  /// Dışarıdan tetikleme — ChatDetail'deki swipe ikonundan veya benzer
  /// yerlerden `_pullKey.currentState?.openProgrammatically()` ile çağırılır.
  Future<void> openProgrammatically() => _open();

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    HapticFeedback.mediumImpact();
    await _animateToFull();
    if (!mounted) return;

    final guest = _isGuest();
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) => guest
            ? const StyleDiscoveryGuestLanding()
            : const StyleDiscoveryLiveScreen(),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
    if (!mounted) return;
    _prefetchKicked = false;
    setState(() {
      _opening = false;
      _dragging = false;
      _dragY = 0;
    });
  }

  Future<void> _animateToFull() async {
    final targetH = MediaQuery.of(context).size.height;
    final start = _dragY;
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    ctrl.addListener(() {
      if (!mounted) return;
      final t = Curves.easeOutCubic.transform(ctrl.value);
      setState(() => _dragY = start + (targetH - start) * t);
    });
    await ctrl.forward();
    ctrl.dispose();
  }

  /// Chip'e tap — login kontrol + aç
  void _onChipTap() {
    if (_opening || _dragging) return;
    HapticFeedback.selectionClick();
    _open();
  }

  @override
  Widget build(BuildContext context) {
    final th = _threshold(context);
    final progress = (_dragY / th).clamp(0.0, 1.0);

    // Handle CARD'ın kendisi yukarı doğru büyür — kullanıcı drag yaparken
    // kartın yüksekliği _dragY kadar artar. Yeni sheet ÇIKMAZ; mevcut
    // alan genişler. _RisingSheet kullanımı tamamen kaldırıldı.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showHandleStrip)
          Transform.translate(
            offset: Offset(0, -_hintY),
            child: _HandleStrip(
              idleCtrl: _idleCtrl,
              bumpCtrl: _bumpCtrl,
              active: _dragging || _dragY > 4,
              progress: progress,
              showHandIcon: _playingHint,
              dragY: _dragY,
              onTap: _onChipTap,
              onDragStart: (_) => _onDragStart(),
              onDragUpdate: _onDragUpdate,
              onDragEnd: _onDragEndDetails,
            ),
          ),
        widget.child,
      ],
    );
  }
}

// ─── HANDLE STRIP — yukarı doğru kendisi büyüyen kart ───
class _HandleStrip extends StatelessWidget {
  const _HandleStrip({
    required this.idleCtrl,
    required this.bumpCtrl,
    required this.active,
    required this.progress,
    required this.showHandIcon,
    required this.dragY,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final AnimationController idleCtrl;
  final AnimationController bumpCtrl;
  final bool active;
  final double progress;
  final bool showHandIcon;
  // dragY = kullanıcının yukarı çekmiş olduğu mesafe. Card'ın yüksekliğini
  // bu kadar büyütür → kart "yukarı doğru genişler" hissi.
  final double dragY;
  final VoidCallback onTap;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onVerticalDragStart: onDragStart,
      onVerticalDragUpdate: onDragUpdate,
      onVerticalDragEnd: onDragEnd,
      child: AnimatedBuilder(
        animation: bumpCtrl,
        builder: (_, _) {
          // 2026-04-27: Idle floaty oscillation kaldırıldı (user "yukarı
          // aşağı oynamasın" dedi). Sadece threshold-cross bump kaldı.
          final bv = bumpCtrl.value;
          final bump = bv == 0 ? 0.0 : math.sin(bv * math.pi) * 4;
          final scale = 1.0 + progress * 0.02;

          return Transform.translate(
            offset: Offset(0, -bump),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                // KART KENDİSİ YUKARI BÜYÜR — dragY arttıkça height artar.
                // Min 94 (collapsed), max screenH * 0.55 (kullanıcı drag eder
                // ama kartı tüm ekranı kaplamamasını sağlamak için cap).
                height: (94.0 + dragY).clamp(
                  94.0,
                  MediaQuery.of(context).size.height * 0.6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: KoalaColors.accentDeep.withValues(alpha: 0.10),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: KoalaColors.accentDeep.withValues(alpha: 0.10),
                      blurRadius: 22,
                      offset: const Offset(0, -4),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      // Drag indicator (handle bar) — tap+drag affordance
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: active
                              ? KoalaColors.accentDeep
                                  .withValues(alpha: 0.45)
                              : Colors.black.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Content row — sparkle tile + title + subtitle
                      Row(
                        children: [
                          // Sparkles icon tile (accent gradient square)
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(13),
                              gradient: KoalaColors.accentGradientV,
                              boxShadow: [
                                BoxShadow(
                                  color: KoalaColors.accentDeep
                                      .withValues(alpha: 0.32),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              LucideIcons.sparkles,
                              size: 20,
                              color: Colors.white,
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
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: KoalaColors.text,
                                    letterSpacing: -0.3,
                                    height: 1.15,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Tasarımlar seni bekliyor',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    color: KoalaColors.textSec,
                                    letterSpacing: -0.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Pulsing chevron — "yukarı çek" sinyali
                          Transform.scale(
                            scale: 1.0 + progress * 0.25,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: KoalaColors.accent
                                    .withValues(alpha: 0.10),
                              ),
                              child: Icon(
                                showHandIcon
                                    ? LucideIcons.hand
                                    : LucideIcons.chevronUp,
                                size: 16,
                                color: KoalaColors.accentDeep,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // ── Drag ile büyüyen alan: discovery preview ──
                      // dragY > 0 oldukça progress ile fade-in. İçerik:
                      // sıcak hero gradient + "Tarzlarını keşfet" başlığı
                      // + 2x2 görsel grid teaser. Threshold'a yaklaşırken
                      // tam görünür → kullanıcı parmağı kaldırınca açılır.
                      if (dragY > 4)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Opacity(
                              opacity: progress.clamp(0.0, 1.0),
                              child: _DiscoveryPreviewInline(
                                progress: progress,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Card büyüdükçe açılan inline preview — discovery sheet'in mini'si.
/// Hero başlığı + 2x2 görsel grid (style mosaic). Kullanıcı görünce
/// "yukarı çekersem buradan devam ederim" hissi alır, sonra threshold'da
/// gerçek discovery screen'e geçer.
class _DiscoveryPreviewInline extends StatelessWidget {
  const _DiscoveryPreviewInline({required this.progress});
  final double progress;

  static const _styleRefs = [
    'https://images.unsplash.com/photo-1556909114-f6e7ad7d3136?w=300&q=80&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1567538096630-e0c55bd6374c?w=300&q=80&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1586023492125-27b2c045efd7?w=300&q=80&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1493663284031-b7e3aefcae8e?w=300&q=80&auto=format&fit=crop',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            KoalaColors.accent.withValues(alpha: 0.06),
            Colors.transparent,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.sparkles,
                size: 12,
                color: KoalaColors.accentDeep,
              ),
              const SizedBox(width: 6),
              Text(
                'Hayalindeki tarzı keşfet',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: KoalaColors.text.withValues(alpha: 0.85),
                  letterSpacing: -0.2,
                ),
              ),
              const Spacer(),
              if (progress > 0.85)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: KoalaColors.accentDeep,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    'Bırak ↑',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              crossAxisCount: 4,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              children: _styleRefs
                  .map((url) => ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          placeholder: (_, _) =>
                              Container(color: const Color(0xFFEFEAE3)),
                          errorWidget: (_, _, _) =>
                              Container(color: const Color(0xFFEFEAE3)),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── RISING SHEET ───
class _RisingSheet extends StatelessWidget {
  const _RisingSheet({
    required this.height,
    required this.atThreshold,
    required this.progress,
  });

  final double height;
  final bool atThreshold;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final contentOpacity = ((height - 40) / 120).clamp(0.0, 1.0);
    final radius = (1 - progress) * 28 + 4;
    // Content slide-in: üstten aşağı açılır hissi
    final slideY = (1 - progress) * -20;
    // Glow: drag arttıkça accentDeep alpha büyür
    final glowAlpha = progress * 0.3;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F4ED),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(radius),
          topRight: Radius.circular(radius),
        ),
        boxShadow: [
          BoxShadow(
            color: KoalaColors.accentDeep.withValues(alpha: 0.12),
            blurRadius: 32,
            offset: const Offset(0, -8),
          ),
          // Gradient-glow efekti — accent ışığı yayılsın
          BoxShadow(
            color: KoalaColors.accentDeep.withValues(alpha: glowAlpha),
            blurRadius: 48,
            spreadRadius: 2,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: contentOpacity,
        child: Transform.translate(
          offset: Offset(0, slideY),
          child: _SheetBody(atThreshold: atThreshold),
        ),
      ),
    );
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.atThreshold});

  final bool atThreshold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: KoalaColors.ink.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [KoalaColors.accent, KoalaColors.accentDeep],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(LucideIcons.sparkles,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Tarzını Keşfedelim',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: KoalaColors.ink,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.only(left: 46),
            child: Text(
              'Tasarımlar seni bekliyor',
              style: TextStyle(
                fontSize: 12.5,
                color: KoalaColors.textSec,
              ),
            ),
          ),
          const SizedBox(height: 18),
          // Hero preview
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                image: const DecorationImage(
                  image: NetworkImage(
                    'https://images.unsplash.com/photo-1586023492125-27b2c045efd7?w=900&q=80',
                  ),
                  fit: BoxFit.cover,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.7),
                        ],
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 18,
                    right: 18,
                    bottom: 18,
                    child: Text(
                      'Beğendiklerini kaydet · tarzını bulalım',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.3,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              atThreshold ? 'Bırak → aç' : 'Yukarı çekmeye devam',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: atThreshold
                    ? KoalaColors.accentDeep
                    : KoalaColors.textSec,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// GUEST LANDING — misafir kullanıcı için signup CTA
// ═══════════════════════════════════════════════════════════
class StyleDiscoveryGuestLanding extends StatelessWidget {
  const StyleDiscoveryGuestLanding({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Back
              Align(
                alignment: Alignment.topLeft,
                child: GestureDetector(
                  onTap: () {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    } else {
                      context.go('/');
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(LucideIcons.x,
                        size: 22, color: KoalaColors.ink),
                  ),
                ),
              ),
              const Spacer(),
              // Amblem
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: KoalaColors.accentSoft,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: KoalaColors.accentDeep.withValues(alpha: 0.18),
                        blurRadius: 32,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: const Icon(LucideIcons.sparkles,
                      size: 56, color: KoalaColors.accentDeep),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Sana özel tasarım keşfi',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: KoalaColors.ink,
                  letterSpacing: -0.5,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 24),
              const _GuestFeature(
                icon: LucideIcons.layers,
                text: 'Tasarımları kaydırarak tarzını öğren',
              ),
              const SizedBox(height: 14),
              const _GuestFeature(
                icon: LucideIcons.heart,
                text: 'Beğendiklerini kaydet, koleksiyonun oluşsun',
              ),
              const SizedBox(height: 14),
              const _GuestFeature(
                icon: LucideIcons.wand,
                text: 'AI sana özel öneri hazırlasın',
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () => context.go('/auth'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: KoalaColors.accentDeep,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                child: const Text('Kayıt Ol'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => context.go('/auth'),
                child: const Text(
                  'Zaten hesabım var → Giriş',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: KoalaColors.textMed,
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

class _GuestFeature extends StatelessWidget {
  const _GuestFeature({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: KoalaColors.accentSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: KoalaColors.accentDeep),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: KoalaColors.ink,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
