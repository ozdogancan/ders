import 'package:flutter/material.dart';

/// KoalaPressable — ana CTA'lara "basma hissi" veren ortak wrapper (v2 G2).
///
/// Basılınca 0.97 scale-down (100ms, easeOut) — Airbnb/Linear inceliği,
/// bounce yok. İki kullanım modu:
///
///  • `onTap` verilirse tıklamayı kendisi yönetir (GestureDetector).
///  • `onTap` null ise SADECE basışı dinler (Listener) — tıklamayı child
///    içindeki buton/InkWell yönetir; gesture arena'ya karışmadığı için
///    mevcut davranış (ripple, Semantics, disabled durumu) aynen korunur.
class KoalaPressable extends StatefulWidget {
  const KoalaPressable({
    super.key,
    required this.child,
    this.onTap,
    this.enabled = true,
    this.pressedScale = 0.97,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  final double pressedScale;

  @override
  State<KoalaPressable> createState() => _KoalaPressableState();
}

class _KoalaPressableState extends State<KoalaPressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scale = Tween<double>(begin: 1.0, end: widget.pressedScale).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _down() {
    if (widget.enabled) _ctrl.forward();
  }

  void _up() => _ctrl.reverse();

  @override
  Widget build(BuildContext context) {
    final Widget scaled = ScaleTransition(scale: _scale, child: widget.child);

    if (widget.onTap == null) {
      // Pasif mod — tıklama child'da (InkWell/FilledButton vb.), biz sadece
      // basışı izleyip scale uygularız.
      return Listener(
        onPointerDown: (PointerDownEvent _) => _down(),
        onPointerUp: (PointerUpEvent _) => _up(),
        onPointerCancel: (PointerCancelEvent _) => _up(),
        child: scaled,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _down(),
      onTapUp: (_) => _up(),
      onTapCancel: _up,
      onTap: widget.enabled ? widget.onTap : null,
      child: scaled,
    );
  }
}
