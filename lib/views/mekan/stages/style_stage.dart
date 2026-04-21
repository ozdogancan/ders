import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/koala_tokens.dart';
import '../../../services/mekan_analyze_service.dart';
import '../../style_discovery_screen.dart';
import '../mekan_constants.dart';
import '../widgets/mekan_ui.dart';

class StyleStage extends StatefulWidget {
  final Uint8List bytes;
  final AnalyzeResult analysis;
  final void Function(ThemeOption) onSubmit;
  const StyleStage({
    super.key,
    required this.bytes,
    required this.analysis,
    required this.onSubmit,
  });

  @override
  State<StyleStage> createState() => _StyleStageState();
}

class _StyleStageState extends State<StyleStage> {
  ThemeOption? _theme;
  String? _primaryStyle;
  bool _loadedProfile = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('koala_style_profile');
      String? primary;
      if (raw != null && raw.isNotEmpty) {
        final m = jsonDecode(raw);
        if (m is Map<String, dynamic>) {
          primary = (m['primary_style'] as String?)?.trim();
          if (primary != null && primary.isEmpty) primary = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _primaryStyle = primary;
        _loadedProfile = true;
        // Eğer kullanıcı tarzını biliyorsak varsayılan olarak uygula.
        if (primary != null) {
          final match = _matchTheme(primary);
          if (match != null) _theme = match;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadedProfile = true);
    }
  }

  ThemeOption? _matchTheme(String key) {
    final k = key.toLowerCase().trim();
    for (final t in kThemes) {
      if (t.value.toLowerCase() == k) return t;
      if (t.tr.toLowerCase() == k) return t;
    }
    // Yaygın eşleşmeler
    const aliases = {
      'minimal': 'Minimalist',
      'minimalist': 'Minimalist',
      'scandinavian': 'Scandinavian',
      'skandinav': 'Scandinavian',
      'iskandinav': 'Scandinavian',
      'japandi': 'Japandi',
      'modern': 'Modern',
      'contemporary': 'Modern',
      'bohemian': 'Bohemian',
      'boho': 'Bohemian',
      'bohem': 'Bohemian',
      'industrial': 'Industrial',
      'endustriyel': 'Industrial',
      'endüstriyel': 'Industrial',
    };
    final mapped = aliases[k];
    if (mapped == null) return null;
    for (final t in kThemes) {
      if (t.value == mapped) return t;
    }
    return null;
  }

  Future<void> _openDiscovery() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const StyleDiscoveryScreen(entryPoint: 'mekan_flow'),
      ),
    );
    // Geri dönüşte profili tazele.
    await _loadProfile();
  }

  @override
  Widget build(BuildContext context) {
    final analysis = widget.analysis;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        KoalaSpacing.xl, KoalaSpacing.md, KoalaSpacing.xl, KoalaSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1) Foto + tespit edilen oda
          _photoAndDetection(analysis),
          const SizedBox(height: KoalaSpacing.xxl),

          // 2) Renk paleti analizi
          if (analysis.colors.isNotEmpty) ...[
            const Text('Renk paleti', style: KoalaText.h3),
            const SizedBox(height: KoalaSpacing.sm),
            _palette(analysis.colors),
            const SizedBox(height: KoalaSpacing.xxl),
          ],

          // 3) Stil profili kartı
          if (_loadedProfile) ...[
            _styleProfileCard(),
            const SizedBox(height: KoalaSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _openDiscovery,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: KoalaColors.textSec,
                ),
                icon: const Icon(Icons.explore_outlined, size: 14),
                label: Text(
                  'Tarzını güncellemek ister misin?',
                  style: KoalaText.bodySec.copyWith(
                    decoration: TextDecoration.underline,
                    decorationColor: KoalaColors.textSec,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: KoalaSpacing.xxl),

          // 4) Tema seçici
          const Text('Bir tarz seç', style: KoalaText.h3),
          const SizedBox(height: KoalaSpacing.xs),
          Text(
            _theme == null
                ? 'Odayı hangi havada yeniden hayal edelim?'
                : 'Seçili · ${_theme!.tr}',
            style: KoalaText.bodySec,
          ),
          const SizedBox(height: KoalaSpacing.lg),
          _themeGrid(),

          const SizedBox(height: KoalaSpacing.xxl),

          // 5) Başlat
          MekanPrimaryButton(
            label: _theme == null
                ? 'Bir tarz seç'
                : 'Tasarımı başlat',
            onTap: _theme == null ? null : () => widget.onSubmit(_theme!),
            trailing: _theme == null ? null : Icons.auto_awesome_rounded,
          ),
        ],
      ),
    );
  }

  Widget _photoAndDetection(AnalyzeResult a) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KoalaRadius.md),
            image: DecorationImage(
              image: MemoryImage(widget.bytes),
              fit: BoxFit.cover,
            ),
            border: Border.all(color: KoalaColors.border, width: 0.5),
          ),
        ),
        const SizedBox(width: KoalaSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                '${a.roomLabelTr} tespit edildi',
                style: KoalaText.h2,
              ),
              const SizedBox(height: 6),
              if (a.caption.isNotEmpty)
                Text(
                  _shorten(a.caption),
                  style: KoalaText.bodySec,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: KoalaSpacing.sm),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  MekanChip(
                    label: a.roomLabelTr,
                    icon: Icons.check_circle_outline,
                  ),
                  if (a.mood.isNotEmpty)
                    MekanChip(
                      label: a.mood,
                      tint: KoalaColors.surfaceAlt,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _shorten(String s) {
    final t = s.trim();
    if (t.length <= 140) return t;
    return '${t.substring(0, 137)}…';
  }

  Widget _palette(List<MekanColor> colors) {
    return Container(
      padding: const EdgeInsets.all(KoalaSpacing.md),
      decoration: KoalaDeco.card,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final c in colors) _swatchChip(c),
        ],
      ),
    );
  }

  Widget _swatchChip(MekanColor c) {
    return Container(
      padding: const EdgeInsets.only(left: 6, right: 12, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: KoalaColors.surfaceMuted,
        borderRadius: BorderRadius.circular(KoalaRadius.pill),
        border: Border.all(color: KoalaColors.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: c.color,
              shape: BoxShape.circle,
              border: Border.all(
                  color: KoalaColors.border, width: 0.5),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            c.name,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: KoalaColors.text,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            c.hex,
            style: const TextStyle(
              fontSize: 11,
              color: KoalaColors.textSec,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _styleProfileCard() {
    final hasStyle = _primaryStyle != null;
    if (hasStyle) {
      final match = _matchTheme(_primaryStyle!);
      final label = match?.tr ?? _primaryStyle!;
      return Container(
        padding: const EdgeInsets.all(KoalaSpacing.lg),
        decoration: BoxDecoration(
          color: KoalaColors.accentSoft,
          borderRadius: BorderRadius.circular(KoalaRadius.lg),
          border: Border.all(
              color: KoalaColors.accent.withValues(alpha: 0.25), width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: KoalaColors.accentDeep,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.star_rounded,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: KoalaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Senin tarzın',
                          style: KoalaText.caption),
                      const SizedBox(height: 2),
                      Text(label, style: KoalaText.h3),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: KoalaSpacing.md),
            Text(
              'Bu tarzı uygulayalım mı? Aşağıdan istersen başka tarz seçebilirsin.',
              style: KoalaText.bodySec,
            ),
            const SizedBox(height: KoalaSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _openDiscovery,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: KoalaColors.accentDeep,
                ),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text(
                  'Tarzını tekrar keşfet',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Stil bilinmiyor — keşif CTA'sı
    return Container(
      padding: const EdgeInsets.all(KoalaSpacing.lg),
      decoration: BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(KoalaRadius.lg),
        border: Border.all(color: KoalaColors.hintBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tarzını henüz bilmiyoruz', style: KoalaText.h3),
          const SizedBox(height: 6),
          Text(
            'Birkaç görsele göz at, sana yakın hissedeni işaretle — tarzını tanıyalım.',
            style: KoalaText.bodySec,
          ),
          const SizedBox(height: KoalaSpacing.md),
          MekanSecondaryButton(
            label: 'Tarzını Keşfet',
            onTap: _openDiscovery,
            fullWidth: true,
            icon: Icons.auto_awesome_outlined,
          ),
        ],
      ),
    );
  }

  Widget _themeGrid() {
    return LayoutBuilder(builder: (ctx, c) {
      final cardW = (c.maxWidth - KoalaSpacing.md) / 2;
      return Wrap(
        spacing: KoalaSpacing.md,
        runSpacing: KoalaSpacing.md,
        children: [
          for (final t in kThemes) _themeTile(t, cardW),
        ],
      );
    });
  }

  Widget _themeTile(ThemeOption t, double width) {
    final active = _theme?.value == t.value;
    final highlighted = _primaryStyle != null &&
        _matchTheme(_primaryStyle!)?.value == t.value;
    return GestureDetector(
      onTap: () => setState(() => _theme = t),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: width,
        decoration: BoxDecoration(
          color: KoalaColors.surface,
          borderRadius: BorderRadius.circular(KoalaRadius.lg),
          border: Border.all(
            color: active
                ? KoalaColors.accentDeep
                : (highlighted
                    ? KoalaColors.accent.withValues(alpha: 0.35)
                    : KoalaColors.border),
            width: active ? 2 : (highlighted ? 1 : 0.5),
          ),
          boxShadow: active ? KoalaShadows.accentGlow : null,
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(KoalaRadius.md),
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
                  if (active)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          color: KoalaColors.accentDeep,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.check_rounded,
                            color: Colors.white, size: 14),
                      ),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: KoalaSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.tr,
                    style: KoalaText.h4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (highlighted && !active)
                  const Icon(Icons.star_rounded,
                      color: KoalaColors.accent, size: 14),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              t.tag,
              style: KoalaText.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
