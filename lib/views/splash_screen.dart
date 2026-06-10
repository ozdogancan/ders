import 'package:flutter/material.dart';

/// Uygulama boot / async init sırasında gösterilen splash ekranı.
///
/// Tasarım: yumuşak, ferah iç-mimari estetiği. Kod-çizimli krem gradient
/// taban ilk frame'i kaplar; üstüne soft iç-mekan görseli + gölgeli koala
/// logosu gelir, altında ince indeterminate gradient progress bar. Metin yok.
///
/// Android native splash (values*/styles.xml) ve web preloader (index.html
/// #koala-preloader) BU ekranla birebir aynı tasarımı kullanır — aynı logo,
/// arka plan, boyut, gölge. Böylece preloader → bu ekran geçişi görünmezdir;
/// kullanıcı tek, kesintisiz bir splash görür.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Progress bar paleti.
  static const _barTrack = Color(0xFFE3DEEF);
  static const _barFrom = Color(0xFF7C6EF2); // KoalaDS.accent
  static const _barTo = Color(0xFF6C5CE7);   // KoalaDS.accentDeep

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
      const AssetImage('assets/images/koala_splash_logo.webp'),
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
    // Logo: ekran genişliğinin ~%56'sı, 216-252 arası clamp'lenir — splash'ın
    // ana öğesi, belirgin ve büyük dursun.
    final logoSize = (size.width * 0.56).clamp(216.0, 252.0);

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
            // Soft iç-mekan arka planı — HTML preloader ile AYNI dosya;
            // tarayıcı cache'inden anında gelir. Fade yok: preloader'dan
            // devralırken birebir aynı görüntü, geç gelme/oynama olmaz.
            Positioned.fill(
              child: Image.asset(
                'assets/images/splash_bg.webp',
                fit: BoxFit.cover,
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
                      // Net, derli toplu gölge — ikonu zemine oturtur ama
                      // etrafa yayılıp dağınık/puslu görünmez.
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 34,
                          offset: const Offset(0, 18),
                          spreadRadius: -14,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 9,
                          offset: const Offset(0, 4),
                          spreadRadius: -3,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(logoSize * 0.225),
                      child: Image.asset(
                        'assets/images/koala_splash_logo.webp',
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
