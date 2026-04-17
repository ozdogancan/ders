// ═══════════════════════════════════════════════════════════
// STYLE DISCOVERY PULL — input bar'ın üstünde "Tarzını Keşfet"
// chip'i. Kullanıcı sayfanın HERHANGİ BİR YERİNDEN yukarı
// kaydırınca sheet parmağı takip eder. Eşiğe ulaşıp bırakınca
// StyleDiscoveryLiveScreen açılır. Drag başlayınca arka planda
// ilk batch görselleri prefetch edilir.
//
// External drag: Home Screen body içindeki pointer eventlerini
// [beginExternalDrag] / [updateExternalDrag] / [endExternalDrag]
// üzerinden iletir — böylece chip dışındaki her yer drag source.
// ═══════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/koala_tokens.dart';
import '../services/evlumba_live_service.dart';
import '../views/style_discovery_live_screen.dart';

class StyleDiscoveryPull extends StatefulWidget {
  const StyleDiscoveryPull({
    super.key,
    required this.child,
    this.totalCountBuilder,
  });

  final Widget child;
  final Future<int> Function()? totalCountBuilder;

  @override
  State<StyleDiscoveryPull> createState() => StyleDiscoveryPullState();
}

class StyleDiscoveryPullState extends State<StyleDiscoveryPull>
    with TickerProviderStateMixin {
  // ─── Drag state ───
  double _dragY = 0;
  bool _dragging = false;
  bool _opening = false;

  // ─── Spring-back controller (bırakınca aşağı iner) ───
  late final AnimationController _releaseCtrl;
  double _releaseStart = 0;

  // ─── Idle chip nefes animasyonu (up-arrow bob) ───
  late final AnimationController _idleCtrl;

  // ─── Background prefetch ───
  bool _prefetching = false;
  bool _prefetchKicked = false;
  int _prefetchedCount = 0;

  int? _totalCount;

  // Threshold — ekranın %30'u
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

    _maybeLoadCount();
  }

  Future<void> _maybeLoadCount() async {
    if (widget.totalCountBuilder == null) return;
    try {
      final c = await widget.totalCountBuilder!();
      if (mounted) setState(() => _totalCount = c);
    } catch (_) {}
  }

  @override
  void dispose() {
    _releaseCtrl.dispose();
    _idleCtrl.dispose();
    super.dispose();
  }

  bool _isAtThreshold() {
    if (!mounted) return false;
    return _dragY >= _threshold(context);
  }

  // ─── External API — home body pointer events buraya yönlenir ───
  void beginExternalDrag() => _onDragStart();
  void updateExternalDrag(double deltaDy) => _onDragDelta(deltaDy);
  void endExternalDrag(double velocityY) => _onDragEnd(velocityY);
  bool get isDragging => _dragging;

  void _onDragStart([DragStartDetails? _]) {
    if (_opening) return;
    setState(() {
      _dragging = true;
      _releaseCtrl.stop();
    });
    // Prefetch drag başlar başlamaz (arka planda)
    _kickPrefetch();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _onDragDelta(d.delta.dy);
  }

  void _onDragDelta(double dy) {
    if (_opening) return;
    final next = math.max(0, _dragY - dy);
    setState(() => _dragY = next.toDouble());
    if (_isAtThreshold()) {
      // Tek haptic feedback eşiğe ilk ulaşınca
      // (burada her frame atmaması için flag gerekmez; selectionClick hafif)
    }
  }

  void _onDragEndDetails(DragEndDetails d) {
    _onDragEnd(d.velocity.pixelsPerSecond.dy);
  }

  void _onDragEnd(double velocityY) {
    if (_opening) return;
    // Flick yukarı → aç
    if (velocityY < -900) {
      _open();
      return;
    }
    // Eşiği geçtiyse aç
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
        setState(() => _prefetchedCount = covers.length);
      }
    } catch (_) {
    } finally {
      _prefetching = false;
    }
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    HapticFeedback.mediumImpact();
    await _animateToFull();
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) => const StyleDiscoveryLiveScreen(),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
    if (!mounted) return;
    // Reset so prefetch can re-run next session (covers may be stale)
    _prefetchKicked = false;
    _prefetchedCount = 0;
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

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final th = _threshold(context);
    final progress = (_dragY / th).clamp(0.0, 1.0);
    final atThreshold = _dragY >= th;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HandleStrip(
              idleCtrl: _idleCtrl,
              active: _dragging || _dragY > 4,
              onDragStart: (_) => _onDragStart(),
              onDragUpdate: _onDragUpdate,
              onDragEnd: _onDragEndDetails,
            ),
            widget.child,
          ],
        ),

        // ── SHEET — parmak yukarı çekildikçe büyür ──
        if (_dragY > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _dragY.clamp(0.0, screenH),
            child: IgnorePointer(
              child: _RisingSheet(
                height: _dragY,
                atThreshold: atThreshold,
                totalCount: _totalCount,
                progress: progress,
                prefetchedCount: _prefetchedCount,
              ),
            ),
          ),
      ],
    );
  }
}

// ─── HANDLE STRIP — sade "Tarzını Keşfet" chip'i (çizgi yok) ───
class _HandleStrip extends StatelessWidget {
  const _HandleStrip({
    required this.idleCtrl,
    required this.active,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final AnimationController idleCtrl;
  final bool active;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: onDragStart,
      onVerticalDragUpdate: onDragUpdate,
      onVerticalDragEnd: onDragEnd,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: idleCtrl,
          builder: (_, _) {
            final floaty =
                active ? 0.0 : math.sin(idleCtrl.value * math.pi) * 2;
            return Transform.translate(
              offset: Offset(0, -floaty),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: active
                      ? KoalaColors.accentDeep.withValues(alpha: 0.14)
                      : KoalaColors.accentSoft,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: KoalaColors.accentDeep.withValues(alpha: 0.18),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.chevronUp,
                      size: 14,
                      color: KoalaColors.accentDeep,
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'Tarzını Keşfet',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: KoalaColors.accentDeep,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.auto_awesome,
                      size: 11,
                      color: KoalaColors.accentDeep,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── RISING SHEET — drag ile büyür ───
class _RisingSheet extends StatelessWidget {
  const _RisingSheet({
    required this.height,
    required this.atThreshold,
    required this.totalCount,
    required this.progress,
    required this.prefetchedCount,
  });

  final double height;
  final bool atThreshold;
  final int? totalCount;
  final double progress;
  final int prefetchedCount;

  @override
  Widget build(BuildContext context) {
    final contentOpacity = ((height - 40) / 120).clamp(0.0, 1.0);
    final radius = (1 - progress) * 28;

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
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: contentOpacity,
        child: _SheetBody(
          atThreshold: atThreshold,
          totalCount: totalCount,
          prefetchedCount: prefetchedCount,
        ),
      ),
    );
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.atThreshold,
    required this.totalCount,
    required this.prefetchedCount,
  });

  final bool atThreshold;
  final int? totalCount;
  final int prefetchedCount;

  @override
  Widget build(BuildContext context) {
    final sub = totalCount != null
        ? '${_fmt(totalCount!)} tasarım · sana özel öneriler'
        : 'Sana özel öneriler hazırlıyoruz';

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grab çizgisi (üst ortası)
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
                child: const Icon(Icons.auto_awesome,
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
          Padding(
            padding: const EdgeInsets.only(left: 46),
            child: Text(
              sub,
              style: const TextStyle(
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
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 18,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Text(
                            'JAPANDİ · SALON',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Sakin, açık ahşap,\nnefes alan bir yaşam alanı',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.25,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Alt hint
          Center(
            child: Text(
              atThreshold
                  ? (prefetchedCount > 0
                      ? 'Bırak → $prefetchedCount tasarım hazır'
                      : 'Bırak → açılsın')
                  : 'Yukarı çekmeye devam et',
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

  static String _fmt(int n) {
    if (n < 1000) return '$n';
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
