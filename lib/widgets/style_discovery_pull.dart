// ═══════════════════════════════════════════════════════════
// STYLE DISCOVERY PULL — input bar'ın üstünde ince handle strip.
// Kullanıcı parmağını yukarı çektikçe sheet parmağını canlı
// takip eder. Eşik geçilince StyleDiscoveryLiveScreen açılır.
//
// Kullanım:
//   StyleDiscoveryPull(
//     child: _TypewriterInput(...),  // mevcut input bar
//   )
// Widget, child'ı olduğu gibi render eder + üstüne handle strip
// ekler + drag sırasında sheet'i bütün ekranı kaplayacak şekilde
// canlı büyütür.
// ═══════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/koala_tokens.dart';
import '../views/style_discovery_live_screen.dart';

class StyleDiscoveryPull extends StatefulWidget {
  const StyleDiscoveryPull({
    super.key,
    required this.child,
    this.totalCountBuilder,
  });

  /// Sarmalanan input bar (bottom sabit)
  final Widget child;

  /// Opsiyonel — sheet başlığında "2.847 tasarım" göstermek için
  /// count fetch fonksiyonu. null ise sadece "sana özel öneriler".
  final Future<int> Function()? totalCountBuilder;

  @override
  State<StyleDiscoveryPull> createState() => _StyleDiscoveryPullState();
}

class _StyleDiscoveryPullState extends State<StyleDiscoveryPull>
    with TickerProviderStateMixin {
  // Drag durumu: 0 = idle, > 0 = ne kadar yukarı çekildi (px)
  double _dragY = 0;
  bool _dragging = false;
  bool _opening = false;

  // Spring-back controller (bırakınca aşağı yumuşakça iner)
  late final AnimationController _releaseCtrl;
  double _releaseStart = 0;

  // Idle handle nefes animasyonu
  late final AnimationController _idleCtrl;

  int? _totalCount;

  // Threshold — ekranın %35'i çekilince "aç" olarak kabul et
  double _threshold(BuildContext ctx) =>
      MediaQuery.of(ctx).size.height * 0.35;

  @override
  void initState() {
    super.initState();
    _releaseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..addListener(() {
        if (!_dragging) {
          setState(() {
            _dragY = _releaseStart * (1 - _releaseCtrl.value);
          });
        }
      });
    _idleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
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

  void _onDragStart(DragStartDetails d) {
    if (_opening) return;
    setState(() {
      _dragging = true;
      _releaseCtrl.stop();
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_opening) return;
    // delta.dy < 0 = yukarı
    setState(() {
      _dragY = math.max(0, _dragY - d.delta.dy);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    if (_opening) return;
    final vy = d.velocity.pixelsPerSecond.dy; // < 0 = yukarı flick
    final th = _threshold(context);
    final shouldOpen = _dragY > th || vy < -900;
    if (shouldOpen) {
      _open();
    } else {
      _springBack();
    }
  }

  void _springBack() {
    setState(() {
      _dragging = false;
      _releaseStart = _dragY;
    });
    _releaseCtrl.forward(from: 0);
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _dragging = false;
    });
    HapticFeedback.mediumImpact();
    // Sheet'i önce full height'a çıkar (kısa anim), sonra route push
    await _animateToFull();
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => const StyleDiscoveryLiveScreen(),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: anim,
              curve: Curves.easeOut,
            ),
            child: child,
          );
        },
      ),
    );
    if (!mounted) return;
    // Route kapanınca handle'ı sıfırla
    setState(() {
      _opening = false;
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
      setState(() {
        _dragY = start + (targetH - start) * t;
      });
    });
    await ctrl.forward();
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final th = _threshold(context);
    final progress = (_dragY / th).clamp(0.0, 1.0);
    final willOpen = _dragY > th;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ── BOTTOM STACK: handle strip + child (input) ──
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HandleStrip(
              idleCtrl: _idleCtrl,
              active: _dragging || _dragY > 4,
              progress: progress,
              onDragStart: _onDragStart,
              onDragUpdate: _onDragUpdate,
              onDragEnd: _onDragEnd,
            ),
            widget.child,
          ],
        ),

        // ── SHEET — live tracks drag, covers screen from bottom ──
        if (_dragY > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _dragY.clamp(0.0, screenH),
            child: IgnorePointer(
              child: _RisingSheet(
                height: _dragY,
                willOpen: willOpen,
                totalCount: _totalCount,
                progress: progress,
              ),
            ),
          ),
      ],
    );
  }
}

// ─── HANDLE STRIP — input'un hemen üstünde ince çubuk ───
class _HandleStrip extends StatelessWidget {
  const _HandleStrip({
    required this.idleCtrl,
    required this.active,
    required this.progress,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final AnimationController idleCtrl;
  final bool active;
  final double progress;
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
        height: 34,
        color: Colors.transparent,
        alignment: Alignment.center,
        child: AnimatedBuilder(
          animation: idleCtrl,
          builder: (_, __) {
            // Idle: çok hafif yukarı-aşağı float (2px)
            final floaty = active ? 0.0 : math.sin(idleCtrl.value * math.pi) * 2;
            // Active: handle bar genişler + morlaşır
            final activeT = progress;
            final barW = 32 + activeT * 28;
            final barOpacity = 0.35 + activeT * 0.55;
            return Transform.translate(
              offset: Offset(0, -floaty),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: barW,
                    height: 4,
                    decoration: BoxDecoration(
                      color: KoalaColors.accentDeep
                          .withValues(alpha: barOpacity),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── RISING SHEET — drag ile büyüyen keşfet önizlemesi ───
class _RisingSheet extends StatelessWidget {
  const _RisingSheet({
    required this.height,
    required this.willOpen,
    required this.totalCount,
    required this.progress,
  });

  final double height;
  final bool willOpen;
  final int? totalCount;
  final double progress; // 0..1 eşiğe kadar

  @override
  Widget build(BuildContext context) {
    // İçerik opacity — 40px'ten sonra yavaşça belirir
    final contentOpacity =
        ((height - 40) / 120).clamp(0.0, 1.0);
    final radius = (1 - progress) * 28; // yukarı çıktıkça köşeler düzleşir
    final scale = 0.96 + progress * 0.04;

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
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.topCenter,
          child: _SheetPreview(
            willOpen: willOpen,
            totalCount: totalCount,
          ),
        ),
      ),
    );
  }
}

class _SheetPreview extends StatelessWidget {
  const _SheetPreview({
    required this.willOpen,
    required this.totalCount,
  });
  final bool willOpen;
  final int? totalCount;

  @override
  Widget build(BuildContext context) {
    final sub = totalCount != null
        ? '${_fmt(totalCount!)} tasarım · sana özel öneriler'
        : 'Sana özel öneriler';

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Küçük grab çizgisi (üstte)
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
          // Hero önizleme kartı
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
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
                  // Alt gradient
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
          const SizedBox(height: 16),
          // Hint — bırak, açılıyor / devam et
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              willOpen ? 'Bırak — başla ✨' : 'Yukarı çekmeye devam et',
              key: ValueKey(willOpen),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: willOpen
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
