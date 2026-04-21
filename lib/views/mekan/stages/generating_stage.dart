import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../editorial_theme.dart';
import '../widgets/editorial_primitives.dart';

class GeneratingStage extends StatefulWidget {
  final Uint8List bytes;
  final String room;
  final String theme;
  const GeneratingStage({
    super.key,
    required this.bytes,
    required this.room,
    required this.theme,
  });

  @override
  State<GeneratingStage> createState() => _GeneratingStageState();
}

class _GeneratingStageState extends State<GeneratingStage>
    with SingleTickerProviderStateMixin {
  static const _statuses = [
    'Odanı okuyorum',
    'Çizgileri izliyorum',
    'Stili dokuyorum',
    'Işığı ayarlıyorum',
    'Son dokunuşlar',
  ];

  late final AnimationController _ring;
  Timer? _statusTimer;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    _ring = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _statusTimer = Timer.periodic(const Duration(milliseconds: 2400), (_) {
      if (!mounted) return;
      setState(() => _i = (_i + 1) % _statuses.length);
    });
  }

  @override
  void dispose() {
    _ring.dispose();
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 28),
            const Ordinal(n: '03', label: 'Dönüşüm'),
            const SizedBox(height: 26),
            const Display('Hayal\nediyorum…', size: 44, italic: true),
            const SizedBox(height: 32),
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: MekanPalette.line),
                ),
                child: Stack(children: [
                  // Faded photo
                  Positioned.fill(
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.matrix([
                        0.6, 0.3, 0.1, 0, 0,
                        0.3, 0.6, 0.1, 0, 0,
                        0.3, 0.3, 0.4, 0, 0,
                        0, 0, 0, 0.35, 0,
                      ]),
                      child: Image.memory(widget.bytes, fit: BoxFit.cover),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            MekanPalette.paper.withValues(alpha: 0.4),
                            MekanPalette.paper.withValues(alpha: 0.75),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Rings
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _ring,
                      builder: (_, __) => CustomPaint(
                        painter: _RingsPainter(_ring.value),
                      ),
                    ),
                  ),
                  const Center(
                    child: Text(
                      '§',
                      style: TextStyle(
                        fontFamily: 'Fraunces',
                        fontSize: 52,
                        color: MekanPalette.moss,
                        fontWeight: FontWeight.w300,
                        height: 1,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 26),
            const Hairline(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: Caps(
                      '${_statuses[_i]}…',
                      key: ValueKey(_i),
                      size: 11,
                      color: MekanPalette.ink,
                    ),
                  ),
                  Caps('${widget.theme} · ${widget.room}',
                      size: 10, color: MekanPalette.fog),
                ],
              ),
            ),
            const Hairline(),
            const SizedBox(height: 20),
            Text(
              'Model odanın mimarisini koruyor, sadece yüzeylerin '
              'karakterini değiştiriyor. Genelde 10–20 saniye sürer.',
              style: MekanType.body(size: 14, italic: true, color: MekanPalette.fog),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  final double t; // 0..1
  _RingsPainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var k = 0; k < 3; k++) {
      final local = (t + k / 3) % 1.0;
      final r = 30 + local * 90;
      final a = (1 - local) * 0.6;
      final paint = Paint()
        ..color = MekanPalette.moss.withValues(alpha: a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingsPainter old) => old.t != t;
}
