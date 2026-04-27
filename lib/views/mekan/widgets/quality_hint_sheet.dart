import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/koala_tokens.dart';
import '../../../services/mekan_analyze_service.dart';

/// Soft-band guidance — fotonun bir oda olduğu kabul edildi ama kalite
/// `restyle` için zayıf. Kullanıcıyı zorlamadan, tatlı dille tekrar
/// çekmeye davet et. "Yine de devam et" hep açık — agency kullanıcıda.
///
/// Tasarım niyeti: editorial, sakin, suçlayıcı değil. Fraunces serif başlık,
/// 220-360ms easeOutCubic anims. Issue ikonları Lucide. Bg KoalaColors.surface.
class QualityHintSheet extends StatelessWidget {
  final Uint8List bytes;
  final List<QualityIssue> issues;
  final double qualityScore;
  final VoidCallback onRetake;
  final VoidCallback onContinue;

  const QualityHintSheet({
    super.key,
    required this.bytes,
    required this.issues,
    required this.qualityScore,
    required this.onRetake,
    required this.onContinue,
  });

  /// Sheet'i göster — boolean döner: true ise devam, false ise yeniden çek.
  static Future<bool?> show(
    BuildContext context, {
    required Uint8List bytes,
    required List<QualityIssue> issues,
    required double qualityScore,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => QualityHintSheet(
        bytes: bytes,
        issues: issues,
        qualityScore: qualityScore,
        onRetake: () => Navigator.of(ctx).pop(false),
        onContinue: () => Navigator.of(ctx).pop(true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = issues.isNotEmpty ? issues.first : QualityIssue.unknown;
    final hint = _hintFor(primary);

    return Container(
      decoration: const BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KoalaRadius.xl),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        KoalaSpacing.xl,
        KoalaSpacing.md,
        KoalaSpacing.xl,
        KoalaSpacing.xxl,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: KoalaSpacing.lg),
                decoration: BoxDecoration(
                  color: KoalaColors.borderMed,
                  borderRadius: BorderRadius.circular(KoalaRadius.pill),
                ),
              ),
            ),

            // Foto önizleme (küçük, davetkar)
            Center(
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(KoalaRadius.lg),
                  image: DecorationImage(
                    image: MemoryImage(bytes),
                    fit: BoxFit.cover,
                  ),
                  border: Border.all(color: KoalaColors.border, width: 0.5),
                ),
              ),
            ).animate().fadeIn(duration: 280.ms, curve: Curves.easeOutCubic).scale(
                  begin: const Offset(0.92, 0.92),
                  end: const Offset(1, 1),
                  duration: 320.ms,
                  curve: Curves.easeOutCubic,
                ),

            const SizedBox(height: KoalaSpacing.xl),

            // Başlık (Fraunces editorial)
            Text(
              hint.title,
              style: KoalaText.serif(fontSize: 22, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ).animate(delay: 120.ms).fadeIn(duration: 320.ms).slideY(
                  begin: 0.06,
                  end: 0,
                  duration: 360.ms,
                  curve: Curves.easeOutCubic,
                ),

            const SizedBox(height: KoalaSpacing.sm),

            Text(
              hint.body,
              style: KoalaText.bodySec,
              textAlign: TextAlign.center,
            ).animate(delay: 180.ms).fadeIn(duration: 320.ms),

            // Detay chip'ler — birden fazla issue varsa hepsini göster
            if (issues.length > 1) ...[
              const SizedBox(height: KoalaSpacing.lg),
              Wrap(
                spacing: KoalaSpacing.sm,
                runSpacing: KoalaSpacing.sm,
                alignment: WrapAlignment.center,
                children: issues
                    .map((i) => _IssueChip(issue: i))
                    .toList(),
              ).animate(delay: 240.ms).fadeIn(duration: 280.ms),
            ],

            const SizedBox(height: KoalaSpacing.xxl),

            // Primary: Yeniden çek (accentDeep)
            FilledButton.icon(
              onPressed: onRetake,
              style: FilledButton.styleFrom(
                backgroundColor: KoalaColors.accentDeep,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(KoalaRadius.md + 2),
                ),
                textStyle: KoalaText.button,
              ),
              icon: const Icon(LucideIcons.camera, size: 18),
              label: const Text('Yeniden çek'),
            ).animate(delay: 300.ms).fadeIn(duration: 280.ms).slideY(
                  begin: 0.1,
                  end: 0,
                  duration: 320.ms,
                  curve: Curves.easeOutCubic,
                ),

            const SizedBox(height: KoalaSpacing.sm),

            // Secondary: Yine de devam et (text button — görünür ama vurgusuz)
            TextButton(
              onPressed: onContinue,
              child: Text(
                'Yine de devam et',
                style: KoalaText.label.copyWith(color: KoalaColors.textSec),
              ),
            ).animate(delay: 360.ms).fadeIn(duration: 240.ms),
          ],
        ),
      ),
    );
  }

  /// Issue → Türkçe başlık + body + (ileride) hint görsel.
  /// Tek issue mantıklı çoğu zaman; "primary" issue'a göre konuşuyoruz.
  _Hint _hintFor(QualityIssue issue) {
    switch (issue) {
      case QualityIssue.blurry:
        return const _Hint(
          title: 'Foto biraz bulanık',
          body: 'Daha net bir kare çekersen, AI mobilyaları ve oranları '
              'çok daha iyi anlar. İki saniye sabit tut yeter.',
        );
      case QualityIssue.tooDark:
        return const _Hint(
          title: 'Burada ışık az',
          body: 'Perdeyi açıp ya da lambayı yakıp tekrar dener misin? '
              'Aydınlık karelerde renk analizi gerçeğine yakın çıkıyor.',
        );
      case QualityIssue.tooFar:
        return const _Hint(
          title: 'Biraz yakın çek',
          body: 'Oda çok uzaktan göründüğü için detaylar küçük kalıyor. '
              'Bir-iki adım yaklaşırsan AI mobilyaları daha iyi tanır.',
        );
      case QualityIssue.partialView:
        return const _Hint(
          title: 'Geniş açı dener misin?',
          body: 'Sadece bir köşesi görünüyor. Odanın 2-3 duvarını birden '
              'gösteren bir açı, restyle\'ın işine çok yarar.',
        );
      case QualityIssue.clutteredWithPeople:
        return const _Hint(
          title: 'Kadrajda insanlar var',
          body: 'Fotoğrafa odaklanabilelim diye odanın boş halini çekersen '
              'çok yardımı dokunur. Kediyi çıkarmana gerek yok 😊',
        );
      case QualityIssue.lowResolution:
        return const _Hint(
          title: 'Çözünürlük düşük',
          body: 'Foto çok küçük geldi. Galerinden büyük orijinaliyle '
              'yükleyebilir misin?',
        );
      case QualityIssue.unknown:
        return const _Hint(
          title: 'Daha iyi sonuç için',
          body: 'Daha net bir açı çekersen restyle çok daha güzel '
              'çıkacak. Yine de devam edebilirsin.',
        );
    }
  }
}

class _Hint {
  final String title;
  final String body;
  const _Hint({required this.title, required this.body});
}

class _IssueChip extends StatelessWidget {
  final QualityIssue issue;
  const _IssueChip({required this.issue});

  @override
  Widget build(BuildContext context) {
    final (icon, label) = _meta(issue);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KoalaSpacing.md,
        vertical: KoalaSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: KoalaColors.surfaceAlt,
        borderRadius: BorderRadius.circular(KoalaRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: KoalaColors.textMed),
          const SizedBox(width: 6),
          Text(label, style: KoalaText.labelSmall),
        ],
      ),
    );
  }

  static (IconData, String) _meta(QualityIssue i) {
    switch (i) {
      case QualityIssue.blurry: return (LucideIcons.eyeOff, 'bulanık');
      case QualityIssue.tooDark: return (LucideIcons.moon, 'karanlık');
      case QualityIssue.tooFar: return (LucideIcons.zoomOut, 'uzak');
      case QualityIssue.partialView: return (LucideIcons.crop, 'parçalı');
      case QualityIssue.clutteredWithPeople: return (LucideIcons.users, 'kalabalık');
      case QualityIssue.lowResolution: return (LucideIcons.image, 'düşük çözünürlük');
      case QualityIssue.unknown: return (LucideIcons.info, 'iyileştirilebilir');
    }
  }
}
