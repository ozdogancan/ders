import 'package:flutter/material.dart';

/// Uygulama boot / async init sırasında gösterilen splash ekranı.
///
/// Tasarım: yumuşak, ferah iç-mimari estetiği. Arka plan tamamen kod ile
/// çizilir (hiç asset yüklenmez — splash anında çıkar). Ortada büyük koala
/// ikonu, altında ince indeterminate gradient progress bar. Hiç metin yok.
///
/// Android native splash (values*/styles.xml) ve web preloader (index.html)
/// aynı krem tonunu (#F7F4EF) kullanır; bu ekran devralınca geçiş kesintisiz.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Progress bar paleti.
  static const _barTrack = Color(0xFFE0DCEC);
  static const _barFrom = Color(0xFF6C63FF);
  static const _barTo = Color(0xFF9B5CFF);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // İkonu önceden cache'le — devam eden ekranlarda anında hazır olsun.
    precacheImage(
      const AssetImage('assets/images/koala_splash_icon.png'),
      context,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // Logo: ekran genişliğinin ~%40'ı, 160-180 arası clamp'lenir.
    final logoSize = (size.width * 0.40).clamp(160.0, 180.0);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          // Yumuşak dikey gradient — krem → bej → soft-blue.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF7F4EF),
              Color(0xFFEFEAE3),
              Color(0xFFE8E9EE),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Derinlik için iki büyük, çok düşük opaklıkta blur daire.
            Positioned(
              top: -size.width * 0.35,
              right: -size.width * 0.30,
              child: _SoftBlob(
                diameter: size.width * 0.85,
                color: const Color(0xFFFFFFFF).withValues(alpha: 0.45),
              ),
            ),
            Positioned(
              bottom: -size.width * 0.40,
              left: -size.width * 0.30,
              child: _SoftBlob(
                diameter: size.width * 0.90,
                color: const Color(0xFF9FB4D6).withValues(alpha: 0.20),
              ),
            ),
            // Logo + progress bar.
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Kare canvas üstündeki beyaz köşe üçgenlerini kırpmak için
                  // yuvarlatılmış clip — radius = boyut * 0.225.
                  Container(
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(logoSize * 0.225),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(logoSize * 0.225),
                      child: Image.asset(
                        'assets/images/koala_splash_icon.png',
                        width: logoSize,
                        height: logoSize,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // İnce indeterminate gradient progress bar.
                  SizedBox(
                    width: 180,
                    height: 6,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: _ProgressBarPainter(
                            progress: _controller.value,
                            track: _barTrack,
                            from: _barFrom,
                            to: _barTo,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Büyük, çok yumuşak (blur'lu) renk lekesi — derinlik hissi için.
class _SoftBlob extends StatelessWidget {
  const _SoftBlob({required this.diameter, required this.color});

  final double diameter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0.0)],
        ),
      ),
    );
  }
}

/// İnce indeterminate progress bar painter'ı.
///
/// Açık renkli bir track üzerinde, mor gradient'li bir segment soldan sağa
/// sürekli süzülür. [progress] 0..1 arası döngüsel ilerler.
class _ProgressBarPainter extends CustomPainter {
  _ProgressBarPainter({
    required this.progress,
    required this.track,
    required this.from,
    required this.to,
  });

  final double progress;
  final Color track;
  final Color from;
  final Color to;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height);

    // Track.
    final trackRect = RRect.fromRectAndRadius(
      Offset.zero & size,
      radius,
    );
    canvas.drawRRect(trackRect, Paint()..color = track);

    // Hareketli segment — bar genişliğinin %45'i kadar.
    final segWidth = size.width * 0.45;
    // -segWidth .. size.width arası süzülür (içeri/dışarı kayar).
    final travel = size.width + segWidth;
    final segLeft = progress * travel - segWidth;

    final segRect = Rect.fromLTWH(
      segLeft,
      0,
      segWidth,
      size.height,
    );

    final paint = Paint()
      ..shader = LinearGradient(
        colors: [from, to],
      ).createShader(segRect);

    // Segmenti track'in içinde tut (clip).
    canvas.save();
    canvas.clipRRect(trackRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(segRect, radius),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ProgressBarPainter old) =>
      old.progress != progress;
}
