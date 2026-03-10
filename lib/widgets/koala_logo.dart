import 'package:flutter/material.dart';

class KoalaLogo extends StatelessWidget {
  const KoalaLogo({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _KoalaPainter()),
    );
  }
}

class KoalaHero extends StatelessWidget {
  const KoalaHero({super.key, this.size = 120});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            const Color(0xFF6366F1).withAlpha(12),
            const Color(0xFF6366F1).withAlpha(4),
            Colors.transparent,
          ],
          stops: const [0.0, 0.7, 1.0],
        ),
      ),
      child: Center(
        child: SizedBox(
          width: size * 0.75,
          height: size * 0.75,
          child: CustomPaint(painter: _KoalaPainter()),
        ),
      ),
    );
  }
}

class _KoalaPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // Colors
    const bodyColor = Color(0xFF7C8DB5);
    const bodyLight = Color(0xFFA8B8D8);
    const earInner = Color(0xFFCBA6D4);
    const white = Color(0xFFF0F4F8);
    const nose = Color(0xFF6366F1);
    const eye = Color(0xFF1E293B);

    final bodyPaint = Paint()..style = PaintingStyle.fill;

    // ── EARS (behind head)
    // Left ear
    bodyPaint.color = bodyColor;
    canvas.drawCircle(Offset(cx - w * 0.28, h * 0.22), w * 0.18, bodyPaint);
    bodyPaint.color = earInner;
    canvas.drawCircle(Offset(cx - w * 0.28, h * 0.22), w * 0.12, bodyPaint);

    // Right ear
    bodyPaint.color = bodyColor;
    canvas.drawCircle(Offset(cx + w * 0.28, h * 0.22), w * 0.18, bodyPaint);
    bodyPaint.color = earInner;
    canvas.drawCircle(Offset(cx + w * 0.28, h * 0.22), w * 0.12, bodyPaint);

    // ── HEAD
    bodyPaint.color = bodyColor;
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, h * 0.38), width: w * 0.7, height: h * 0.5), bodyPaint);

    // ── FACE (lighter area)
    bodyPaint.color = white;
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, h * 0.42), width: w * 0.48, height: h * 0.34), bodyPaint);

    // ── EYES
    bodyPaint.color = eye;
    canvas.drawCircle(Offset(cx - w * 0.11, h * 0.36), w * 0.045, bodyPaint);
    canvas.drawCircle(Offset(cx + w * 0.11, h * 0.36), w * 0.045, bodyPaint);

    // Eye shine
    bodyPaint.color = Colors.white;
    canvas.drawCircle(Offset(cx - w * 0.10, h * 0.35), w * 0.018, bodyPaint);
    canvas.drawCircle(Offset(cx + w * 0.12, h * 0.35), w * 0.018, bodyPaint);

    // ── NOSE
    bodyPaint.color = nose;
    final noseRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, h * 0.44), width: w * 0.13, height: h * 0.07),
      Radius.circular(w * 0.04),
    );
    canvas.drawRRect(noseRect, bodyPaint);

    // ── MOUTH (subtle smile)
    final mouthPaint = Paint()
      ..color = const Color(0xFF475569)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.012
      ..strokeCap = StrokeCap.round;

    final mouthPath = Path();
    mouthPath.moveTo(cx - w * 0.06, h * 0.48);
    mouthPath.quadraticBezierTo(cx, h * 0.52, cx + w * 0.06, h * 0.48);
    canvas.drawPath(mouthPath, mouthPaint);

    // ── BLUSH
    bodyPaint.color = const Color(0xFFFFB8C6).withAlpha(80);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - w * 0.18, h * 0.43), width: w * 0.08, height: h * 0.04), bodyPaint);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + w * 0.18, h * 0.43), width: w * 0.08, height: h * 0.04), bodyPaint);

    // ── BODY
    bodyPaint.color = bodyColor;
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, h * 0.72), width: w * 0.55, height: h * 0.4), bodyPaint);

    // Belly
    bodyPaint.color = bodyLight;
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, h * 0.74), width: w * 0.38, height: h * 0.28), bodyPaint);

    // ── GRADUATION CAP
    final capPaint = Paint()..color = nose..style = PaintingStyle.fill;

    // Cap base (diamond shape)
    final capPath = Path();
    capPath.moveTo(cx, h * 0.1);
    capPath.lineTo(cx - w * 0.28, h * 0.2);
    capPath.lineTo(cx, h * 0.27);
    capPath.lineTo(cx + w * 0.28, h * 0.2);
    capPath.close();
    canvas.drawPath(capPath, capPaint);

    // Cap top
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, h * 0.1), width: w * 0.12, height: h * 0.05),
        Radius.circular(w * 0.02)),
      capPaint);

    // Tassel
    final tasselPaint = Paint()
      ..color = const Color(0xFFFBBF24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.015
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx + w * 0.22, h * 0.2), Offset(cx + w * 0.22, h * 0.28), tasselPaint);
    canvas.drawCircle(Offset(cx + w * 0.22, h * 0.29), w * 0.02, Paint()..color = const Color(0xFFFBBF24));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
