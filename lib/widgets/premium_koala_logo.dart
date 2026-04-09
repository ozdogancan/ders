import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme/koala_tokens.dart';

class PremiumKoalaLogo extends StatelessWidget {
  const PremiumKoalaLogo({super.key, this.size = 140});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, KoalaColors.surfaceCool],
          stops: [0.2, 1.0],
        ),
        boxShadow: [
          // Soft outer drop shadow mimicking iOS app icon depth
          BoxShadow(
            color: KoalaColors.accentDeep.withValues(alpha:0.08),
            blurRadius: size * 0.35,
            offset: Offset(0, size * 0.1),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha:0.04),
            blurRadius: size * 0.1,
            offset: Offset(0, size * 0.03),
          ),
          // Inner glowing highlight at the top edge
          BoxShadow(
            color: Colors.white.withValues(alpha:0.9),
            blurRadius: 2,
            offset: const Offset(0, -2),
            spreadRadius: -1,
          ),
        ],
      ),
      child: Center(
        child: SizedBox(
          width: size * 0.70,
          height: size * 0.70,
          child: CustomPaint(
            painter: _KoalaNeumorphicPainter(),
          ),
        ),
      ),
    );
  }
}

class _KoalaNeumorphicPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    
    // Scale canvas to a 100x100 virtual grid centered at (0,0)
    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.scale(w / 100, h / 100);

    // Dark titanium metallic gradient for the strokes and fills
    final shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF8B8898), Color(0xFF454054)],
      stops: [0.0, 1.0],
    ).createShader(Rect.fromCenter(center: Offset.zero, width: 100, height: 100));

    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = shader;

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = shader;

    // --- Create perfectly overlapping paths to map the outer contour ---
    // The ears are slightly high and wide
    final earL = Path()..addOval(Rect.fromCenter(center: const Offset(-34, -18), width: 34, height: 34));
    final earR = Path()..addOval(Rect.fromCenter(center: const Offset(34, -18), width: 34, height: 34));
    // The face is a wide ellipse that drops down slightly
    final face = Path()..addOval(Rect.fromCenter(center: const Offset(0, 7), width: 80, height: 62));

    // Combine them into a single continuous outline (like the image)
    final combinedEars = Path.combine(PathOperation.union, earL, earR);
    final contour = Path.combine(PathOperation.union, face, combinedEars);

    // Draw a very subtle white highlight slightly below the outline to simulate embossing
    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha:0.9);
      
    canvas.save();
    canvas.translate(0, 1.5);
    canvas.drawPath(contour, highlightPaint);
    canvas.restore();

    // Now draw the actual metallic contour
    canvas.drawPath(contour, outlinePaint);

    // --- Inner Ear Fluffs ---
    // Left ear fluff (arc)
    final fluffL = Path()..addArc(Rect.fromCenter(center: const Offset(-34, -18), width: 18, height: 18), math.pi * 0.7, math.pi * 1.0);
    final fluffR = Path()..addArc(Rect.fromCenter(center: const Offset(34, -18), width: 18, height: 18), math.pi * 1.3, math.pi * 1.0);
    
    // Draw highlight for fluffs
    canvas.save();
    canvas.translate(0, 1.5);
    canvas.drawPath(fluffL, highlightPaint);
    canvas.drawPath(fluffR, highlightPaint);
    canvas.restore();
    
    // Draw the actual metallic fluffs
    canvas.drawPath(fluffL, outlinePaint);
    canvas.drawPath(fluffR, outlinePaint);

    // --- Eyes ---
    canvas.drawCircle(const Offset(-16, 2), 4.5, fillPaint);
    canvas.drawCircle(const Offset(16, 2), 4.5, fillPaint);

    // --- Big Nose ---
    final noseRect = Rect.fromCenter(center: const Offset(0, 18), width: 20, height: 30);
    final noseRRect = RRect.fromRectAndRadius(noseRect, const Radius.circular(10));
    
    // Nose highlight
    canvas.save();
    canvas.translate(0, 1.5);
    canvas.drawRRect(noseRRect, Paint()..color = Colors.white.withValues(alpha:0.9));
    canvas.restore();
    
    // Metallic Nose
    canvas.drawRRect(noseRRect, fillPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
