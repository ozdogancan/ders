import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/theme/koala_tokens.dart';
import '../../services/mekan_analyze_service.dart';
import '../../services/replicate_service.dart';
import 'mekan_constants.dart';
import 'stages/generating_stage.dart';
import 'stages/result_stage.dart';
import 'stages/style_stage.dart';
import 'widgets/mekan_ui.dart';

/// Mekan akışı state machine — foto HomeScreen'den geliyor.
/// Açılışta /api/analyze-room ile oda tespiti → style → generating → result.
class MekanFlowScreen extends StatefulWidget {
  final Uint8List initialBytes;
  const MekanFlowScreen({super.key, required this.initialBytes});

  @override
  State<MekanFlowScreen> createState() => _MekanFlowScreenState();
}

enum _Phase { analyzing, notMekan, style, generating, result, error }

class _MekanFlowScreenState extends State<MekanFlowScreen> {
  _Phase _phase = _Phase.analyzing;
  late Uint8List _bytes;
  AnalyzeResult? _analysis;
  ThemeOption? _theme;
  String? _afterSrc;
  bool _mock = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _bytes = widget.initialBytes;
    _analyze();
  }

  Future<void> _analyze() async {
    setState(() {
      _phase = _Phase.analyzing;
      _errorMsg = null;
    });
    try {
      final r = await MekanAnalyzeService.analyze(_bytes);
      if (!mounted) return;
      if (r.isNotMekan) {
        setState(() {
          _analysis = r;
          _phase = _Phase.notMekan;
        });
        return;
      }
      setState(() {
        _analysis = r;
        _phase = _Phase.style;
      });
    } on MekanAnalyzeException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = '${e.code} · ${e.detail}';
        _phase = _Phase.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = e.toString();
        _phase = _Phase.error;
      });
    }
  }

  Future<void> _generate(ThemeOption theme) async {
    final a = _analysis;
    if (a == null) return;
    setState(() {
      _phase = _Phase.generating;
      _theme = theme;
      _errorMsg = null;
    });
    try {
      // Oda tipi analyze'dan gelir; boşsa "living room" varsayılanı.
      final room = a.roomType.isNotEmpty ? a.roomType : 'living room';
      final r = await ReplicateService.restyle(
        imageBytes: _bytes,
        room: room.replaceAll('_', ' '),
        theme: theme.value,
      );
      if (!mounted) return;
      setState(() {
        _afterSrc = r.output;
        _mock = r.mock;
        _phase = _Phase.result;
      });
    } on ReplicateException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = '${e.code} · ${e.detail}';
        _phase = _Phase.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = e.toString();
        _phase = _Phase.error;
      });
    }
  }

  void _onPro() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Tarzını Keşfet / Mesajlar ile aynı AppBar — app genelinde tutarlı.
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      appBar: AppBar(
        backgroundColor: KoalaColors.bg,
        surfaceTintColor: KoalaColors.bg,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Mekan', style: KoalaText.h2),
      ),
      body: SafeArea(
        top: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _buildPhase(),
        ),
      ),
    );
  }

  Widget _buildPhase() {
    switch (_phase) {
      case _Phase.analyzing:
        return _analyzingView();
      case _Phase.notMekan:
        return _notMekanView();
      case _Phase.style:
        return StyleStage(
          key: const ValueKey('style'),
          bytes: _bytes,
          analysis: _analysis!,
          onSubmit: _generate,
        );
      case _Phase.generating:
        return GeneratingStage(
          key: const ValueKey('generating'),
          bytes: _bytes,
          room: _analysis?.roomLabelTr ?? 'Mekan',
          theme: _theme?.tr ?? '',
        );
      case _Phase.result:
        return ResultStage(
          key: const ValueKey('result'),
          beforeBytes: _bytes,
          afterSrc: _afterSrc!,
          room: _analysis?.roomLabelTr ?? 'Mekan',
          theme: _theme?.tr ?? '',
          mock: _mock,
          onRetry: () => _generate(_theme!),
          onNewStyle: () => setState(() => _phase = _Phase.style),
          onRestart: () => Navigator.of(context).pop(),
          onPro: _onPro,
        );
      case _Phase.error:
        return _errorView();
    }
  }

  Widget _analyzingView() {
    return _AnalyzingView(
      key: const ValueKey('analyzing'),
      bytes: _bytes,
    );
  }

  Widget _notMekanView() {
    final cap = _analysis?.caption.trim() ?? '';
    // Gemini "Bu bir selfie gibi görünüyor" gibi nazik bir cümle döndürüyor.
    // Varsa onu kullan, yoksa genel mesaj.
    final msg = cap.isNotEmpty
        ? cap
        : 'İç mekan görmüyorum bu karede. Salonun, yatak odan, mutfağın — '
            'bir oda fotoğrafı yükler misin?';
    return Padding(
      key: const ValueKey('notMekan'),
      padding: const EdgeInsets.fromLTRB(
          KoalaSpacing.xl, KoalaSpacing.md, KoalaSpacing.xl, KoalaSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Küçük foto önizleme — kullanıcı ne yüklediğini görsün.
          Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(KoalaRadius.lg),
                image: DecorationImage(
                  image: MemoryImage(_bytes),
                  fit: BoxFit.cover,
                ),
                border: Border.all(color: KoalaColors.border, width: 0.5),
              ),
            ),
          ),
          const SizedBox(height: KoalaSpacing.xl),
          const Text('Bunu tasarlayamam 🐨',
              style: KoalaText.h1, textAlign: TextAlign.center),
          const SizedBox(height: KoalaSpacing.sm),
          Text(
            msg,
            style: KoalaText.bodySec,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: KoalaSpacing.xxl),
          MekanPrimaryButton(
            label: 'Başka fotoğraf seç',
            onTap: () => Navigator.of(context).pop(),
            trailing: Icons.photo_library_outlined,
          ),
        ],
      ),
    );
  }

  ({String title, String body}) _humanError() {
    final m = _errorMsg ?? '';
    final lower = m.toLowerCase();
    if (lower.contains('insufficient credit') ||
        lower.contains('402') ||
        lower.contains('billing')) {
      return (
        title: 'Şu an tasarım yapamıyoruz',
        body: 'Görsel üretimi için kapasite geçici olarak doldu. '
            'Birazdan tekrar dener misin?',
      );
    }
    if (lower.contains('429') || lower.contains('rate limit')) {
      return (
        title: 'Biraz yoğunuz',
        body: 'Çok sayıda istek geldi. 30 saniye sonra tekrar dener misin?',
      );
    }
    if (lower.contains('load failed') ||
        lower.contains('clientexception') ||
        lower.contains('network') ||
        lower.contains('socketexception')) {
      return (
        title: 'İnternete ulaşamadım',
        body: 'Bağlantını kontrol edip tekrar dener misin?',
      );
    }
    return (
      title: 'Bir şey ters gitti',
      body: m.isEmpty ? 'Bilinmeyen hata' : m,
    );
  }

  Widget _errorView() {
    final e = _humanError();
    return Padding(
      key: const ValueKey('error'),
      padding: const EdgeInsets.fromLTRB(
          KoalaSpacing.xl, KoalaSpacing.md, KoalaSpacing.xl, KoalaSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: KoalaColors.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.error_outline,
                  color: KoalaColors.error, size: 32),
            ),
          ),
          const SizedBox(height: KoalaSpacing.xl),
          Text(e.title,
              style: KoalaText.h1, textAlign: TextAlign.center),
          const SizedBox(height: KoalaSpacing.sm),
          Text(
            e.body,
            style: KoalaText.bodySec,
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: KoalaSpacing.xxl),
          MekanPrimaryButton(
            label: 'Tekrar dene',
            onTap: () {
              if (_analysis == null) {
                _analyze();
              } else if (_theme != null) {
                _generate(_theme!);
              } else {
                _analyze();
              }
            },
            trailing: Icons.refresh_rounded,
          ),
          const SizedBox(height: KoalaSpacing.md),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Geri dön',
                style: KoalaText.label.copyWith(
                  color: KoalaColors.textSec,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Analiz yüklenirken gösterilen ekran — fotonun üstünde soldan sağa
/// süzülen mor tarama çizgisi + dönen durum metni. "AI gerçekten bakıyor"
/// hissi verir; 3-5 saniyelik bir beklemeyi sıkmadan geçirir.
class _AnalyzingView extends StatefulWidget {
  final Uint8List bytes;
  const _AnalyzingView({super.key, required this.bytes});

  @override
  State<_AnalyzingView> createState() => _AnalyzingViewState();
}

class _AnalyzingViewState extends State<_AnalyzingView>
    with TickerProviderStateMixin {
  static const _statuses = [
    'Odayı okuyorum',
    'Renkleri eşliyorum',
    'Mobilyaları tanıyorum',
    'Havayı yakalıyorum',
  ];

  late final AnimationController _scan;
  late final AnimationController _pulse;
  Timer? _timer;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    _scan = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!mounted) return;
      setState(() => _i = (_i + 1) % _statuses.length);
    });
  }

  @override
  void dispose() {
    _scan.dispose();
    _pulse.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
          ScaleTransition(
            scale: Tween(begin: 0.985, end: 1.015).animate(
              CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(KoalaRadius.xl),
              child: SizedBox(
                width: 200,
                height: 200,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Fotoğraf
                    Image.memory(widget.bytes, fit: BoxFit.cover),
                    // Mor overlay gradient — tarayıcı hissi
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            KoalaColors.accentDeep.withValues(alpha: 0.14),
                            Colors.transparent,
                            KoalaColors.accentDeep.withValues(alpha: 0.10),
                          ],
                        ),
                      ),
                    ),
                    // Tarama çizgisi
                    AnimatedBuilder(
                      animation: _scan,
                      builder: (_, _) {
                        final t = _scan.value;
                        return CustomPaint(
                          painter: _ScanLinePainter(progress: t),
                        );
                      },
                    ),
                    // Köşe çerçeveleri — kamera vizör hissi
                    const _CornerFrame(),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: KoalaSpacing.xxl),
          const Text('Fotoğrafın inceleniyor',
              style: KoalaText.h2, textAlign: TextAlign.center),
          const SizedBox(height: KoalaSpacing.sm),
          SizedBox(
            height: 20,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 380),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.3),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: Text(
                '${_statuses[_i]}…',
                key: ValueKey(_i),
                style: KoalaText.bodySec,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: KoalaSpacing.xl),
          SizedBox(
            width: 140,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(KoalaRadius.pill),
              child: const LinearProgressIndicator(
                minHeight: 3,
                backgroundColor: KoalaColors.surfaceAlt,
                valueColor:
                    AlwaysStoppedAnimation<Color>(KoalaColors.accentDeep),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }
}

/// Fotonun üstünde yukarı-aşağı süzülen 2px'lik mor çizgi + altı aydınlatan
/// yumuşak glow. Sadelik için tek sıfır-1 ilerleme değeriyle çalışır.
class _ScanLinePainter extends CustomPainter {
  final double progress;
  _ScanLinePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;
    // Glow
    final glow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          KoalaColors.accentDeep.withValues(alpha: 0.28),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, y - 18, size.width, 36));
    canvas.drawRect(Rect.fromLTWH(0, y - 18, size.width, 36), glow);
    // Çizgi
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
  }

  @override
  bool shouldRepaint(covariant _ScanLinePainter old) =>
      old.progress != progress;
}

/// Kamera vizör köşeleri — fotonun 4 köşesine minik L'ler.
class _CornerFrame extends StatelessWidget {
  const _CornerFrame();

  @override
  Widget build(BuildContext context) {
    const c = KoalaColors.accentDeep;
    Widget corner(
            {bool top = false, bool left = false, bool right = false, bool bottom = false}) =>
        Positioned(
          top: top ? 10 : null,
          left: left ? 10 : null,
          right: right ? 10 : null,
          bottom: bottom ? 10 : null,
          child: CustomPaint(
            size: const Size(18, 18),
            painter: _CornerPainter(
                top: top, left: left, right: right, bottom: bottom, color: c),
          ),
        );
    return Stack(
      children: [
        corner(top: true, left: true),
        corner(top: true, right: true),
        corner(bottom: true, left: true),
        corner(bottom: true, right: true),
      ],
    );
  }
}

class _CornerPainter extends CustomPainter {
  final bool top, left, right, bottom;
  final Color color;
  _CornerPainter({
    required this.top,
    required this.left,
    required this.right,
    required this.bottom,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final w = size.width, h = size.height;
    if (top && left) {
      canvas.drawLine(const Offset(0, 0), Offset(w * 0.7, 0), p);
      canvas.drawLine(const Offset(0, 0), Offset(0, h * 0.7), p);
    } else if (top && right) {
      canvas.drawLine(Offset(w, 0), Offset(w * 0.3, 0), p);
      canvas.drawLine(Offset(w, 0), Offset(w, h * 0.7), p);
    } else if (bottom && left) {
      canvas.drawLine(Offset(0, h), Offset(w * 0.7, h), p);
      canvas.drawLine(Offset(0, h), Offset(0, h * 0.3), p);
    } else if (bottom && right) {
      canvas.drawLine(Offset(w, h), Offset(w * 0.3, h), p);
      canvas.drawLine(Offset(w, h), Offset(w, h * 0.3), p);
    }
  }

  @override
  bool shouldRepaint(covariant _CornerPainter old) =>
      old.color != color;
}
