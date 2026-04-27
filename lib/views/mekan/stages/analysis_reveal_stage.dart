import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/koala_tokens.dart';
import '../../../services/mekan_analyze_service.dart';
import '../widgets/mekan_ui.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// "Koala senin mekanını okudu" — fullscreen editorial reveal.
///
/// Neden ayrı bir stage:
/// Eski akışta `style_stage` aynı anda (a) analizin sonucunu gösteriyor ve
/// (b) kullanıcıdan tarz seçmesini istiyordu. Kullanıcı hem "ne gördü" hem
/// "hangisini seç" yüküyle karşılaşıyordu → "wow" anı ezildi, kaos arttı.
///
/// Bu ekran tek iş yapar: **analizin sonucunu göstermek**. Aşamalı
/// (staggered) reveal ile kullanıcıya "AI gerçekten baktı ve anladı"
/// hissi verir, sonra tek CTA ile akışı ileri atar. Karar mantığı —
/// "taste var mı, swipe'a mı yönlendirelim, direkt mi üretelim" — bu
/// ekranın sorumluluğu DEĞİL; sadece onSubmit callback'i flow'a "kullanıcı
/// devam dedi" sinyali gönderir, router ne yapacağına kendisi karar verir.
///
/// Secondary CTA "Kendim seçeyim" — power user kaçış yolu, direkt manuel
/// stil pickerına gider. Çoğu kullanıcı primary'yi bastığında Koala onlara
/// en uygun rotayı (moodboard / swipe) seçer.
class AnalysisRevealStage extends StatelessWidget {
  final Uint8List bytes;
  final AnalyzeResult analysis;

  /// Kullanıcı "Zevkime göre yeniden tasarla" bastı → router taste decision'a.
  final VoidCallback onAutoDesign;

  /// Kullanıcı "Kendim seçeyim" bastı → manuel stil picker.
  final VoidCallback onManualPick;

  const AnalysisRevealStage({
    super.key,
    required this.bytes,
    required this.analysis,
    required this.onAutoDesign,
    required this.onManualPick,
  });

  @override
  Widget build(BuildContext context) {
    final colors = analysis.colors.take(5).toList();
    final mood = _prettyMood(analysis.mood);
    final styleLabel = _prettyStyle(analysis.style);
    final roomLabel = analysis.roomLabelTr;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Ekran yüksekliği tight'sa padding'i düşür — small phone'larda
        // CTA'lar kesilmesin diye safety.
        final compact = constraints.maxHeight < 680;
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            KoalaSpacing.xl,
            compact ? KoalaSpacing.md : KoalaSpacing.lg,
            KoalaSpacing.xl,
            KoalaSpacing.xxl,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight -
                  (compact ? KoalaSpacing.md : KoalaSpacing.lg) -
                  KoalaSpacing.xxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── (1) Eyebrow — tek satır, küçük, accentDeep
                _eyebrow(),
                const SizedBox(height: KoalaSpacing.md),

                // ── (2) Hero foto + overlay badge (style rozeti)
                _heroPhoto(styleLabel),
                const SizedBox(height: KoalaSpacing.xl),

                // ── (3) Ana başlık — room label TR
                _title(roomLabel),
                if (mood.isNotEmpty) ...[
                  const SizedBox(height: KoalaSpacing.sm),
                  _moodLine(mood),
                ],
                const SizedBox(height: KoalaSpacing.xl),

                // ── (4) Palette — tek tek düşen daireler
                if (colors.isNotEmpty) _paletteRow(colors),
                if (colors.isNotEmpty) const SizedBox(height: KoalaSpacing.xxl),

                const Spacer(),

                // ── (5) Primary CTA — zevkime göre yeniden tasarla
                _primaryCta(),
                const SizedBox(height: KoalaSpacing.md),

                // ── (6) Secondary — kendim seçeyim (power user)
                _secondaryCta(),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────
  // Parts
  // ─────────────────────────────────────────────────────────

  Widget _eyebrow() {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: KoalaColors.accentDeep,
            shape: BoxShape.circle,
          ),
        )
            .animate(onPlay: (c) => c.repeat())
            .fadeIn(duration: 600.ms)
            .then()
            .fadeOut(delay: 600.ms, duration: 600.ms),
        const SizedBox(width: 8),
        Text(
          'KOALA OKUDU',
          style: KoalaText.caption.copyWith(
            color: KoalaColors.accentDeep,
            letterSpacing: 1.6,
          ),
        ),
      ],
    ).animate().fadeIn(duration: 320.ms, delay: 80.ms);
  }

  Widget _heroPhoto(String? styleLabel) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(KoalaRadius.xl),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(bytes, fit: BoxFit.cover),
            // Alt gradient — metin üstüne oturmasa da derinlik
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.35),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
            // Style rozeti — sol alt, foto üstünde
            if (styleLabel != null && styleLabel.isNotEmpty)
              Positioned(
                left: KoalaSpacing.md,
                bottom: KoalaSpacing.md,
                child: _glassChip(
                  icon: LucideIcons.sparkles,
                  label: styleLabel,
                ),
              ).animate().fadeIn(delay: 900.ms, duration: 420.ms).slideY(
                    begin: 0.4,
                    end: 0,
                    delay: 900.ms,
                    duration: 420.ms,
                    curve: Curves.easeOutCubic,
                  ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 480.ms, delay: 120.ms)
        .scale(
          begin: const Offset(0.96, 0.96),
          end: const Offset(1, 1),
          duration: 520.ms,
          delay: 120.ms,
          curve: Curves.easeOutCubic,
        );
  }

  Widget _glassChip({required IconData icon, required String label}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(KoalaRadius.pill),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(KoalaRadius.pill),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.32),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _title(String roomLabel) {
    return Text(
      roomLabel,
      style: KoalaText.h1.copyWith(
        fontSize: 32,
        letterSpacing: -0.8,
        height: 1.1,
      ),
    )
        .animate()
        .fadeIn(duration: 380.ms, delay: 420.ms)
        .slideY(
          begin: 0.3,
          end: 0,
          duration: 420.ms,
          delay: 420.ms,
          curve: Curves.easeOutCubic,
        );
  }

  Widget _moodLine(String mood) {
    return Text(
      mood,
      style: KoalaText.bodySec.copyWith(
        fontSize: 15,
        height: 1.45,
        fontStyle: FontStyle.italic,
      ),
      maxLines: 3,
    )
        .animate()
        .fadeIn(duration: 420.ms, delay: 620.ms)
        .slideY(
          begin: 0.3,
          end: 0,
          duration: 420.ms,
          delay: 620.ms,
          curve: Curves.easeOutCubic,
        );
  }

  Widget _paletteRow(List<MekanColor> colors) {
    return Row(
      children: [
        for (var i = 0; i < colors.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Tooltip(
            message: '${colors[i].name} · ${colors[i].hex}',
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: colors[i].color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: KoalaColors.border,
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors[i].color.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            ),
          )
              .animate()
              .fadeIn(
                delay: (900 + i * 110).ms,
                duration: 320.ms,
              )
              .scale(
                begin: const Offset(0.4, 0.4),
                end: const Offset(1, 1),
                delay: (900 + i * 110).ms,
                duration: 380.ms,
                curve: Curves.easeOutBack,
              ),
        ],
      ],
    );
  }

  Widget _primaryCta() {
    return MekanPrimaryButton(
      label: 'Zevkime göre yeniden tasarla',
      onTap: onAutoDesign,
      trailing: LucideIcons.sparkles,
    )
        .animate()
        .fadeIn(delay: 1550.ms, duration: 380.ms)
        .slideY(
          begin: 0.25,
          end: 0,
          delay: 1550.ms,
          duration: 420.ms,
          curve: Curves.easeOutCubic,
        );
  }

  Widget _secondaryCta() {
    return Center(
      child: TextButton(
        onPressed: onManualPick,
        style: TextButton.styleFrom(
          foregroundColor: KoalaColors.textSec,
          padding: const EdgeInsets.symmetric(
            horizontal: KoalaSpacing.md,
            vertical: KoalaSpacing.sm,
          ),
        ),
        child: const Text(
          'Ben kendim tarz seçeyim',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: KoalaColors.textSec,
            decoration: TextDecoration.underline,
            decorationColor: KoalaColors.textTer,
          ),
        ),
      ),
    ).animate().fadeIn(delay: 1750.ms, duration: 380.ms);
  }

  // ─────────────────────────────────────────────────────────
  // String helpers
  // ─────────────────────────────────────────────────────────

  String _prettyStyle(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    const tr = {
      'minimalist': 'Minimalist',
      'scandinavian': 'Skandinav',
      'japandi': 'Japandi',
      'modern': 'Modern',
      'contemporary': 'Çağdaş',
      'bohemian': 'Bohem',
      'industrial': 'Endüstriyel',
      'rustic': 'Rustik',
      'traditional': 'Geleneksel',
      'mid-century': 'Mid-Century',
      'mid century': 'Mid-Century',
    };
    final k = s.toLowerCase();
    return tr[k] ?? (s[0].toUpperCase() + s.substring(1));
  }

  /// Mood alanı bazen tek kelime ("calm, warm"), bazen cümle olabilir.
  /// Tek kelime gelirse virgülleri " · " ile değiştir, ilk harfi büyüt.
  /// Cümleyse ilk cümleyi al.
  String _prettyMood(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    // Virgülle ayrılmış kısa mood etiketleri
    if (t.length < 40 && t.contains(',')) {
      final parts = t
          .split(',')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .take(4)
          .map((p) => p[0].toUpperCase() + p.substring(1))
          .toList();
      return parts.join(' · ');
    }
    // Cümle — ilk cümleyi al
    final i = t.indexOf('.');
    final cut = (i > 0 && i < 140) ? t.substring(0, i + 1) : t;
    if (cut.length <= 140) return cut;
    return '${cut.substring(0, 137)}…';
  }
}
