import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/koala_tokens.dart';
import '../../../services/mekan_analyze_service.dart';
import '../../style_discovery_screen.dart';
import '../mekan_constants.dart';
import '../widgets/mekan_ui.dart';

/// Stil seçim ekranı — sakin, tek odaklı.
/// Yapı: [foto + tespit] → [renk şeridi] → [stil grid] → [başlat]
/// "Senin tarzın" iddialı kartını kaldırdık. Profilde kayıtlı stil varsa
/// sadece ilgili karta küçük bir yıldız ve altta tek satır hatırlatma
/// düşüyor — kullanıcıya dayatmıyoruz.
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
        // NOT: Otomatik seçim yapmıyoruz. Kullanıcı kendisi işaretlemeli.
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadedProfile = true);
    }
  }

  ThemeOption? _matchTheme(String? key) {
    if (key == null) return null;
    final k = key.toLowerCase().trim();
    for (final t in kThemes) {
      if (t.value.toLowerCase() == k) return t;
      if (t.tr.toLowerCase() == k) return t;
    }
    const aliases = {
      'minimal': 'Minimalist',
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
    await _loadProfile();
  }

  @override
  Widget build(BuildContext context) {
    final analysis = widget.analysis;
    final matched = _matchTheme(_primaryStyle);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        KoalaSpacing.xl, KoalaSpacing.md, KoalaSpacing.xl, KoalaSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1) Kullanıcı fotosu — ana odak
          _heroPhoto(),
          const SizedBox(height: KoalaSpacing.lg),

          // 2) Tespit — tek satır
          Text(analysis.roomLabelTr, style: KoalaText.h1),
          const SizedBox(height: 4),
          if (analysis.mood.isNotEmpty)
            Text(
              _firstSentence(analysis.mood),
              style: KoalaText.bodySec,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: KoalaSpacing.lg),

          // 3) Renk şeridi — sade daireler
          if (analysis.colors.isNotEmpty) _colorStrip(analysis.colors),
          if (analysis.colors.isNotEmpty)
            const SizedBox(height: KoalaSpacing.xxl),

          // 4) Stil seçimi — oda adına göre kişiselleştirilmiş başlık
          Text(_styleHeading(analysis.roomLabelTr), style: KoalaText.h3),
          const SizedBox(height: 4),
          Text(
            'Seçtiğin tarza göre yeniden tasarlayacağım.',
            style: KoalaText.bodySec.copyWith(fontSize: 13),
          ),
          const SizedBox(height: KoalaSpacing.md),
          _themeGrid(matched),

          // 5) Hafif hatırlatma — DAYATMA YOK
          const SizedBox(height: KoalaSpacing.md),
          if (_loadedProfile) _hint(matched),

          const SizedBox(height: KoalaSpacing.xxl),

          // 6) Başlat
          MekanPrimaryButton(
            label: _theme == null ? 'Bir tarz seç' : 'Tasarımı başlat',
            onTap: _theme == null ? null : () => widget.onSubmit(_theme!),
            trailing: _theme == null ? null : Icons.auto_awesome_rounded,
          ),
        ],
      ),
    );
  }

  Widget _heroPhoto() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(KoalaRadius.lg),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Image.memory(widget.bytes, fit: BoxFit.cover),
      ),
    );
  }

  String _styleHeading(String roomLabel) {
    final r = roomLabel.toLowerCase();
    if (r == 'mekan' || r.isEmpty) return 'Hangi tarzda yeniden tasarlansın?';
    return '$roomLabel hangi tarzda olsun?';
  }

  String _firstSentence(String s) {
    final t = s.trim();
    final i = t.indexOf('.');
    final cut = (i > 0 && i < 120) ? t.substring(0, i + 1) : t;
    if (cut.length <= 120) return cut;
    return '${cut.substring(0, 117)}…';
  }

  Widget _colorStrip(List<MekanColor> colors) {
    // Yalın daireler — isim yok. Tooltip'te hex kalıyor (hover/long-press).
    return Row(
      children: [
        for (var i = 0; i < colors.length && i < 6; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Tooltip(
            message: colors[i].hex,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: colors[i].color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: KoalaColors.border,
                  width: 0.5,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _hint(ThemeOption? matched) {
    if (matched != null) {
      // Kullanıcının daha önce bulduğu tarz var — küçük satır, dayatma yok.
      return Row(
        children: [
          const Icon(Icons.history_rounded,
              size: 14, color: KoalaColors.textSec),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Son keşfinde ${matched.tr} çıkmıştı · kartta ★',
              style: KoalaText.bodySec.copyWith(fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: _openDiscovery,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: KoalaColors.accentDeep,
            ),
            child: const Text(
              'Yenile',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    }
    // Stil hiç yoksa — keşif davetini küçük tut.
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _openDiscovery,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: KoalaColors.accentDeep,
        ),
        icon: const Icon(Icons.auto_awesome_outlined, size: 14),
        label: const Text(
          'Tarzını keşfedelim mi?',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _themeGrid(ThemeOption? matched) {
    final roomKey = widget.analysis.roomKey;
    return LayoutBuilder(builder: (ctx, c) {
      final cardW = (c.maxWidth - KoalaSpacing.md) / 2;
      return Wrap(
        spacing: KoalaSpacing.md,
        runSpacing: KoalaSpacing.md,
        children: [
          for (final t in kThemes)
            _themeTile(
              t,
              cardW,
              roomKey: roomKey,
              highlighted: matched?.value == t.value,
            ),
        ],
      );
    });
  }

  Widget _themeTile(
    ThemeOption t,
    double width, {
    required String roomKey,
    required bool highlighted,
  }) {
    final active = _theme?.value == t.value;
    return GestureDetector(
      onTap: () => setState(() => _theme = t),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: width,
        decoration: BoxDecoration(
          color: KoalaColors.surface,
          borderRadius: BorderRadius.circular(KoalaRadius.lg),
          border: Border.all(
            color: active ? KoalaColors.accentDeep : KoalaColors.border,
            width: active ? 2 : 0.5,
          ),
          boxShadow: active ? KoalaShadows.accentGlow : null,
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Kart görseli: gerçek Unsplash fotoğrafı + gradient fallback.
            ClipRRect(
              borderRadius: BorderRadius.circular(KoalaRadius.md),
              child: AspectRatio(
                aspectRatio: 5 / 4,
                child: _StyleImage(
                  url: t.imageFor(roomKey),
                  fallback: t.swatch,
                  active: active,
                  highlighted: highlighted,
                ),
              ),
            ),
            const SizedBox(height: KoalaSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.tr,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: KoalaColors.text,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (highlighted)
                  const Icon(Icons.star_rounded,
                      color: KoalaColors.accent, size: 14),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Network görseli + fallback gradient. Yükleme sırasında fade-in yapar;
/// hata olursa gradient'a düşer. Aktif/işaretli kart için overlay ekler.
class _StyleImage extends StatelessWidget {
  final String url;
  final List<int> fallback;
  final bool active;
  final bool highlighted;
  const _StyleImage({
    required this.url,
    required this.fallback,
    required this.active,
    required this.highlighted,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: fallback.map((c) => Color(c)).toList(),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // Fallback — her zaman altta, görsel yüklenemese de bir şey gözüksün.
        Container(decoration: BoxDecoration(gradient: gradient)),
        Image.network(
          url,
          fit: BoxFit.cover,
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return AnimatedOpacity(
              opacity: 0,
              duration: const Duration(milliseconds: 1),
              child: child,
            );
          },
          frameBuilder: (ctx, child, frame, wasSync) {
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOut,
              child: child,
            );
          },
          errorBuilder: (ctx, err, stack) => const SizedBox.shrink(),
        ),
        // Hafif alt gradient — metin üstüne oturmasa da kart doygunlaşsın.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.06),
                ],
              ),
            ),
          ),
        ),
        if (active)
          Positioned(
            top: 6,
            right: 6,
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
        if (!active && highlighted)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(KoalaRadius.pill),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_rounded,
                      color: KoalaColors.accent, size: 12),
                  SizedBox(width: 2),
                  Text(
                    'Son keşfin',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: KoalaColors.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
