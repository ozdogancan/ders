import 'package:flutter/material.dart';

/// Uygulama boot / async init sırasında gösterilen splash ekranı.
///
/// Tasarım: yumuşak, ferah iç-mimari estetiği. Kod-çizimli krem gradient
/// taban ilk frame'i anında kaplar; üstüne ~8KB'lık soft iç-mekan görseli
/// yumuşakça fade-in olur. Ortada gölgeli koala ikonu, altında ince
/// indeterminate gradient progress bar. Hiç metin yok.
///
/// Android native splash (values*/styles.xml) aynı krem tonunu (#F7F4EF)
/// kullanır; bu ekran devralınca geçiş kesintisiz. Web tarafında ayrı bir
/// preloader yok — motor inerken body krem (#F7F4EF) görünür, sonra bu ekran.
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
    // Soft iç-mekan arka planı — ~8KB webp, kod-çizimli gradient zaten ilk
    // frame'i kapladığı için yüklenme gecikmesi UI'da görünmez.
    precacheImage(
      const AssetImage('assets/images/splash_bg.webp'),
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
    // Logo: ekran genişliğinin ~%42'si, 168-188 arası clamp'lenir.
    final logoSize = (size.width * 0.42).clamp(168.0, 188.0);

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
          fit: StackFit.expand,
          children: [
            // Soft iç-mekan arka planı — gradient tabanın üstüne yumuşakça
            // fade-in olur. Görsel hazır değilken gradient görünür (beyaz
            // flaş yok); ~8KB olduğu için yüklenme gecikme yaşatmaz.
            Positioned.fill(
              child: Image.asset(
                'assets/images/splash_bg.webp',
                fit: BoxFit.cover,
                frameBuilder: (context, child, frame, wasSync) {
                  return AnimatedOpacity(
                    opacity: (wasSync || frame != null) ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    child: child,
                  );
                },
              ),
            ),
            // Logonun arkasında yumuşak beyaz hale — koala + gölge net
            // okunsun, arka plan gözü yormasın.
            Center(
              child: Container(
                width: size.width * 0.95,
                height: size.width * 0.95,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.88),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                    stops: const [0.34, 1.0],
                  ),
                ),
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
                      // İki katmanlı gölge — derinlik + zemine oturma hissi.
                      boxShadow: [
                        // Geniş, yumuşak ambient gölge (havada süzülme).
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 64,
                          offset: const Offset(0, 30),
                          spreadRadius: -10,
                        ),
                        // Dar, koyu temas gölgesi (ikonu zemine bağlar).
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                          spreadRadius: -6,
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
