import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../editorial_theme.dart';
import '../mekan_constants.dart';
import '../widgets/editorial_primitives.dart';

class StyleStage extends StatefulWidget {
  final Uint8List bytes;
  final void Function(RoomOption, ThemeOption) onSubmit;
  final VoidCallback onBack;
  const StyleStage({
    super.key,
    required this.bytes,
    required this.onSubmit,
    required this.onBack,
  });

  @override
  State<StyleStage> createState() => _StyleStageState();
}

class _StyleStageState extends State<StyleStage> {
  RoomOption _room = kRooms.first;
  ThemeOption? _theme;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Ordinal(n: '02', label: 'Tarz'),
                GestureDetector(
                  onTap: widget.onBack,
                  child: Caps('← Geri',
                      size: 10, color: MekanPalette.fog, tracking: 2),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Foto + başlık yan yana (asimetrik)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: MemoryImage(widget.bytes),
                      fit: BoxFit.cover,
                    ),
                    border: Border.all(color: MekanPalette.line),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Display('Hangi tarzda?', size: 32, italic: true),
                      const SizedBox(height: 6),
                      Caps('Bir tarz seç · tek tıkla tasarla',
                          size: 10, color: MekanPalette.moss),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),
            const Hairline(),
            const SizedBox(height: 14),
            Caps('Oda', size: 10, color: MekanPalette.moss),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kRooms.map((r) {
                final active = r.value == _room.value;
                return GestureDetector(
                  onTap: () => setState(() => _room = r),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: active ? MekanPalette.ink : Colors.transparent,
                      border: Border.all(
                        color: active ? MekanPalette.ink : MekanPalette.line,
                      ),
                    ),
                    child: Text(
                      r.tr.toUpperCase(),
                      style: MekanType.caps(
                        size: 10,
                        color: active ? MekanPalette.paper : MekanPalette.ink,
                        tracking: 1.8,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),
            const Hairline(),
            const SizedBox(height: 14),
            Caps(
              _theme == null
                  ? 'Tarz · seçilmedi'
                  : 'Tarz · N°${(kThemes.indexOf(_theme!) + 1).toString().padLeft(2, '0')}',
              size: 10,
              color: MekanPalette.moss,
            ),
            const SizedBox(height: 12),

            // 2 sütun tarz grid'i
            LayoutBuilder(builder: (ctx, c) {
              final cardW = (c.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < kThemes.length; i++)
                    _themeTile(kThemes[i], i, cardW),
                ],
              );
            }),

            const SizedBox(height: 28),
            const Hairline(),
            const SizedBox(height: 18),
            PrimaryPill(
              label: _theme == null
                  ? 'Bir tarz seç'
                  : '${_theme!.tr} tasarımı başlat',
              onTap: _theme == null
                  ? null
                  : () => widget.onSubmit(_room, _theme!),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _themeTile(ThemeOption t, int i, double width) {
    final active = _theme?.value == t.value;
    return GestureDetector(
      onTap: () => setState(() => _theme = t),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: active ? MekanPalette.ink : MekanPalette.line,
                ),
              ),
              child: AspectRatio(
                aspectRatio: 5 / 4,
                child: Stack(children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: t.swatch.map((c) => Color(c)).toList(),
                          stops: _stops(t.swatch.length),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 10,
                    child: Text(
                      'N°${(i + 1).toString().padLeft(2, '0')}',
                      style: MekanType.mono(size: 9, tracking: 1.6)
                          .copyWith(color: MekanPalette.ink.withValues(alpha: 0.55)),
                    ),
                  ),
                  if (active)
                    const Positioned(
                      top: 8,
                      right: 10,
                      child: _Dot(),
                    ),
                ]),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.tr,
                      style: MekanType.display(
                          size: 18, italic: true, color: MekanPalette.ink)),
                  const SizedBox(height: 4),
                  Caps(t.tag, size: 9, color: MekanPalette.fog),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<double> _stops(int n) {
    if (n <= 1) return const [0.0];
    return [for (int i = 0; i < n; i++) i / (n - 1)];
  }
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: MekanPalette.burnt,
          shape: BoxShape.circle,
        ),
      );
}
