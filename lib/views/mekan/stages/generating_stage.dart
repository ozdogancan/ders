import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/koala_tokens.dart';
import '../../../widgets/koala_bottom_nav.dart';
import '../../main_shell.dart';
import '../../../services/background_gen.dart';

/// Generating stage — sade, editorial, snaphome benzeri.
/// Yumuşak pulse + tek temiz statü metni. Süslü scan/sparkle yok.
class GeneratingStage extends StatefulWidget {
  final Uint8List bytes;
  final String room;
  final String theme;
  final String? themeValue; // backend cache key (English slug)
  const GeneratingStage({
    super.key,
    required this.bytes,
    required this.room,
    required this.theme,
    this.themeValue,
  });

  @override
  State<GeneratingStage> createState() => _GeneratingStageState();
}

class _GeneratingStageState extends State<GeneratingStage>
    with SingleTickerProviderStateMixin {
  static const _statuses = [
    'Odanı okuyorum',
    'Stili dokuyorum',
    'Renkleri dengeliyorum',
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
      duration: const Duration(milliseconds: 2400),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Foto + nazik pulse glow
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, _) {
                final t = _pulse.value;
                return Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(KoalaRadius.xl),
                    boxShadow: [
                      BoxShadow(
                        color: KoalaColors.accent
                            .withValues(alpha: 0.18 + 0.10 * t),
                        blurRadius: 30 + 14 * t,
                        spreadRadius: 0,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(KoalaRadius.xl),
                    child: Image.memory(widget.bytes, fit: BoxFit.cover),
                  ),
                );
              },
            ),
            const SizedBox(height: 36),
            // Sade başlık
            const Text(
              'Tasarımın hazırlanıyor',
              style: KoalaText.h2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 18,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                transitionBuilder: (c, a) =>
                    FadeTransition(opacity: a, child: c),
                child: Text(
                  _statuses[_i],
                  key: ValueKey(_i),
                  style: KoalaText.bodySec.copyWith(
                    color: KoalaColors.textSec,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // İnce çizgi-progress (snaphome estetiği)
            SizedBox(
              width: 96,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(KoalaRadius.pill),
                child: const LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: KoalaColors.surfaceAlt,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(KoalaColors.accentDeep),
                ),
              ),
            ),
            // Süreci Küçült kaldırıldı (2026-04-28).
          ],
        ),
      ),
    );
  }
}
