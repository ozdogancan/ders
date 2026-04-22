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
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            MekanAppBar(
              title: 'Mekan',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _buildPhase(),
              ),
            ),
          ],
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
    return Padding(
      key: const ValueKey('analyzing'),
      padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KoalaRadius.xl),
              image: DecorationImage(
                image: MemoryImage(_bytes),
                fit: BoxFit.cover,
              ),
              border: Border.all(color: KoalaColors.border, width: 0.5),
              boxShadow: KoalaShadows.card,
            ),
          ),
          const SizedBox(height: KoalaSpacing.xxl),
          const Text('Fotoğrafın inceleniyor…', style: KoalaText.h2),
          const SizedBox(height: KoalaSpacing.sm),
          const Text(
            'Oda tipini ve renklerini tespit ediyorum.',
            style: KoalaText.bodySec,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: KoalaSpacing.xl),
          SizedBox(
            width: 160,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(KoalaRadius.pill),
              child: const LinearProgressIndicator(
                minHeight: 4,
                backgroundColor: KoalaColors.surfaceAlt,
                valueColor:
                    AlwaysStoppedAnimation<Color>(KoalaColors.accentDeep),
              ),
            ),
          ),
        ],
      ),
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
