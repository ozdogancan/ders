import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../services/replicate_service.dart';
import 'editorial_theme.dart';
import 'mekan_constants.dart';
import 'stages/style_stage.dart';
import 'stages/generating_stage.dart';
import 'stages/result_stage.dart';
import 'widgets/editorial_primitives.dart';

/// Mekan akışı state machine — foto HomeScreen'den geliyor.
/// style → generating → result → [retry / new style / restart / pro].
class MekanFlowScreen extends StatefulWidget {
  final Uint8List initialBytes;
  const MekanFlowScreen({super.key, required this.initialBytes});

  @override
  State<MekanFlowScreen> createState() => _MekanFlowScreenState();
}

enum _Phase { style, generating, result, error }

class _MekanFlowScreenState extends State<MekanFlowScreen> {
  _Phase _phase = _Phase.style;
  late Uint8List _bytes;
  RoomOption? _room;
  ThemeOption? _theme;
  String? _afterSrc;
  bool _mock = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _bytes = widget.initialBytes;
  }

  Future<void> _generate(RoomOption room, ThemeOption theme) async {
    setState(() {
      _phase = _Phase.generating;
      _room = room;
      _theme = theme;
      _errorMsg = null;
    });
    try {
      final r = await ReplicateService.restyle(
        imageBytes: _bytes,
        room: room.value,
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
    // Pro handoff — şimdilik tasarımcılar ekranına gönderiyoruz.
    // v2: oda tipi + tarz etiketiyle filtrelenmiş liste.
    Navigator.of(context).pop();
    // Home ekranı "Uzman Bul"u kendi navigasyonuyla açıyor; MVP için
    // sadece geri dön, akış sonlandı.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MekanPalette.paper,
      body: SafeArea(
        child: Column(
          children: [
            _masthead(context),
            const Hairline(padding: EdgeInsets.symmetric(horizontal: 24)),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 380),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _buildPhase(),
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _buildPhase() {
    switch (_phase) {
      case _Phase.style:
        return StyleStage(
          key: const ValueKey('style'),
          bytes: _bytes,
          onSubmit: _generate,
          onBack: () => Navigator.of(context).pop(),
        );
      case _Phase.generating:
        return GeneratingStage(
          key: const ValueKey('generating'),
          bytes: _bytes,
          room: _room!.tr,
          theme: _theme!.tr,
        );
      case _Phase.result:
        return ResultStage(
          key: const ValueKey('result'),
          beforeBytes: _bytes,
          afterSrc: _afterSrc!,
          room: _room!.tr,
          theme: _theme!.tr,
          mock: _mock,
          onRetry: () => _generate(_room!, _theme!),
          onNewStyle: () => setState(() => _phase = _Phase.style),
          onRestart: () => Navigator.of(context).pop(),
          onPro: _onPro,
        );
      case _Phase.error:
        return _errorView();
    }
  }

  Widget _errorView() {
    return Padding(
      key: const ValueKey('error'),
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Display('Bir şey\nters gitti.', size: 40, italic: true),
          const SizedBox(height: 12),
          Text(
            _errorMsg ?? '',
            style: MekanType.mono(
                size: 10, tracking: 1.6, color: MekanPalette.fog),
          ),
          const SizedBox(height: 24),
          EButton(
            label: 'Tekrar dene',
            primary: true,
            onTap: () => _generate(_room!, _theme!),
          ),
        ],
      ),
    );
  }

  Widget _masthead(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: Caps('← Koala',
                size: 10, color: MekanPalette.ink, tracking: 2.4),
          ),
          RichText(
            text: TextSpan(children: [
              TextSpan(
                text: 'mekan',
                style: MekanType.display(size: 22, italic: true)
                    .copyWith(letterSpacing: -0.5, height: 1),
              ),
              TextSpan(
                text: '.',
                style: MekanType.display(size: 22, italic: true, color: MekanPalette.burnt)
                    .copyWith(letterSpacing: -0.5, height: 1),
              ),
            ]),
          ),
          Caps('N°001', size: 10, color: MekanPalette.fog, tracking: 2.4),
        ],
      ),
    );
  }

  Widget _footer() {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: MekanPalette.line)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Caps('Koala · by evlumba',
              size: 9, color: MekanPalette.fog, tracking: 2),
          Text('Mekanın sana ait.',
              style: MekanType.body(
                  size: 12, italic: true, color: MekanPalette.fog)),
        ],
      ),
    );
  }
}
