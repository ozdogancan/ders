import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../core/theme/koala_tokens.dart';

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

  late final AnimationController _pulse;
  Timer? _statusTimer;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _statusTimer = Timer.periodic(const Duration(milliseconds: 2400), (_) {
      if (!mounted) return;
      setState(() => _i = (_i + 1) % _statuses.length);
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        KoalaSpacing.xl, KoalaSpacing.xxl, KoalaSpacing.xl, KoalaSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: KoalaSpacing.lg),
          // Pulse foto önizleme
          ScaleTransition(
            scale: Tween(begin: 0.97, end: 1.03).animate(
              CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
            ),
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(KoalaRadius.xl),
                border: Border.all(color: KoalaColors.border, width: 0.5),
                boxShadow: KoalaShadows.card,
                image: DecorationImage(
                  image: MemoryImage(widget.bytes),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const SizedBox(height: KoalaSpacing.xxl),
          const Text('Tasarlanıyor…',
              style: KoalaText.h2, textAlign: TextAlign.center),
          const SizedBox(height: KoalaSpacing.sm),
          SizedBox(
            height: 20,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 380),
              child: Text(
                _statuses[_i],
                key: ValueKey(_i),
                style: KoalaText.bodySec,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: KoalaSpacing.xxl),
          // Linear progress — belirsiz
          SizedBox(
            width: 200,
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
          const SizedBox(height: KoalaSpacing.xxl),
          Text(
            '${widget.theme} · ${widget.room}',
            style: KoalaText.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: KoalaSpacing.xxl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.md),
            child: Text(
              'Model odanın mimarisini koruyor, sadece yüzeylerin karakterini '
              'değiştiriyor. Genelde 15–25 saniye sürer.',
              style: KoalaText.bodySec.copyWith(height: 1.55),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
