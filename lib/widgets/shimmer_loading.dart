import 'package:flutter/material.dart';
import '../core/theme/koala_tokens.dart';

/// Shimmer efektli skeleton loading widget'ları.
/// Veri yüklenirken CircularProgressIndicator yerine kullanılır.

class ShimmerCard extends StatefulWidget {
  const ShimmerCard({
    super.key,
    this.width = double.infinity,
    this.height = 80,
    this.borderRadius = KoalaRadius.lg,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  State<ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<ShimmerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _anim = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          gradient: LinearGradient(
            begin: Alignment(_anim.value - 1, 0),
            end: Alignment(_anim.value, 0),
            colors: const [
              KoalaColors.surfaceAlt,
              KoalaColors.surfaceCool,
              KoalaColors.surfaceAlt,
            ],
          ),
        ),
      ),
    );
  }
}

/// Dikey shimmer liste
class ShimmerList extends StatelessWidget {
  const ShimmerList({
    super.key,
    this.itemCount = 4,
    this.cardHeight = 80,
    this.spacing = KoalaSpacing.md,
    this.padding = const EdgeInsets.all(KoalaSpacing.lg),
  });

  final int itemCount;
  final double cardHeight;
  final double spacing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        children: List.generate(
          itemCount,
          (i) => Padding(
            padding: EdgeInsets.only(bottom: i < itemCount - 1 ? spacing : 0),
            child: ShimmerCard(height: cardHeight),
          ),
        ),
      ),
    );
  }
}

/// Grid shimmer
class ShimmerGrid extends StatelessWidget {
  const ShimmerGrid({
    super.key,
    this.itemCount = 4,
    this.cardHeight = 160,
    this.crossAxisCount = 2,
    this.spacing = KoalaSpacing.md,
    this.padding = const EdgeInsets.all(KoalaSpacing.lg),
  });

  final int itemCount;
  final double cardHeight;
  final int crossAxisCount;
  final double spacing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          childAspectRatio: 0.75,
        ),
        itemCount: itemCount,
        itemBuilder: (_, __) => ShimmerCard(height: cardHeight),
      ),
    );
  }
}
