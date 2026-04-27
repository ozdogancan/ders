import 'dart:typed_data';
import 'package:crypto/crypto.dart' show sha1;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/koala_tokens.dart';
import '../../../services/saved_items_service.dart';
import '../widgets/before_after.dart';
import '../widgets/mekan_ui.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Restyle sonucu — before/after + aksiyonlar.
///
/// "Climax" stage'i — kullanıcının "wow" hissedeceği yer. analysis_reveal ve
/// moodboard sahneleri staggered editorial vocabulary kurmuştu; result_stage
/// önce statikti ve momentumu kırıyordu (audit skoru 5.5/10). Bu yeniden
/// yazımda flutter_animate ile vocabulary'i tutturduk:
///   eyebrow      → 60ms delay,  fadeIn 320ms
///   title        → 120ms delay, fadeIn + slideY 360ms
///   chips        → 220ms delay, fadeIn + slideY 320ms (her chip 60ms ofset)
///   before/after → 320ms delay, fadeIn + scale 480ms (hero anı)
///   bookmark     → 700ms delay, fadeIn + slideY (opt-in toggle)
///   actions      → 850ms delay, fadeIn + slideY 320ms
///   pro CTA      → 1000ms delay, fadeIn + slideY + accent glow
///   footer link  → 1180ms delay, fadeIn 240ms
///
/// 2026-04-27: Auto-save kaldırıldı, opt-in bookmark toggle'a çevrildi.
/// Kullanıcı isterse bookmark'a tıklayıp kaydeder. Kaydedildikten sonra
/// "Tasarımlarına eklendi" chip'i görünür, tekrar tıklayınca silinir.
class ResultStage extends StatefulWidget {
  final Uint8List beforeBytes;
  final String afterSrc;
  final String room;
  final String theme;
  final bool mock;
  final VoidCallback onRetry;
  final VoidCallback onNewStyle;
  final VoidCallback onRestart;
  final VoidCallback onPro;

  const ResultStage({
    super.key,
    required this.beforeBytes,
    required this.afterSrc,
    required this.room,
    required this.theme,
    required this.mock,
    required this.onRetry,
    required this.onNewStyle,
    required this.onRestart,
    required this.onPro,
  });

  @override
  State<ResultStage> createState() => _ResultStageState();
}

class _ResultStageState extends State<ResultStage> {
  // sha1 idempotent id — aynı tasarım birden fazla kez kaydedilmez.
  late final String _itemId = sha1
      .convert(
        '${widget.theme}|${widget.afterSrc}|${widget.beforeBytes.length}'
            .codeUnits,
      )
      .toString()
      .substring(0, 24);

  bool _saved = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Kayıtlı mı diye kontrol et — sayfaya geri dönülürse doğru ikon görünsün.
    if (!widget.mock) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkSaved());
    }
  }

  Future<void> _checkSaved() async {
    final res = await SavedItemsService.isSaved(
      type: SavedItemType.design,
      itemId: _itemId,
    );
    if (!mounted) return;
    setState(() => _saved = res);
  }

  Future<void> _toggleSave() async {
    if (_saving || widget.mock) return;
    setState(() => _saving = true);
    try {
      final ok = await SavedItemsService.toggle(
        type: SavedItemType.design,
        itemId: _itemId,
        title: 'Yeni ${widget.room}',
        imageUrl: widget.afterSrc,
        subtitle: widget.theme,
        extraData: {
          'room': widget.room,
          'theme': widget.theme,
          'after_url': widget.afterSrc,
          'saved_at': DateTime.now().toIso8601String(),
        },
      );
      if (!mounted) return;
      if (ok) {
        setState(() => _saved = !_saved);
        // Hafif feedback — snackbar.
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.showSnackBar(
          SnackBar(
            content: Text(_saved
                ? 'Tasarımlarına eklendi'
                : 'Tasarımlarından kaldırıldı'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('Kaydedilemedi, tekrar dene'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        KoalaSpacing.xl,
        KoalaSpacing.md,
        KoalaSpacing.xl,
        KoalaSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── Eyebrow caption — "tasarımın hazır" ───
          _Eyebrow().animate(delay: 60.ms).fadeIn(
                duration: 320.ms,
                curve: Curves.easeOutCubic,
              ),

          const SizedBox(height: KoalaSpacing.sm),

          // ─── Title (Fraunces editorial) ───
          Text(
            'Yeni ${widget.room}',
            style: KoalaText.serif(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
            ),
          ).animate(delay: 120.ms).fadeIn(duration: 360.ms).slideY(
                begin: 0.06,
                end: 0,
                duration: 360.ms,
                curve: Curves.easeOutCubic,
              ),

          const SizedBox(height: KoalaSpacing.md),

          // ─── Chip row (room + theme) — staggered ───
          Wrap(
            spacing: KoalaSpacing.sm,
            runSpacing: KoalaSpacing.sm,
            children: [
              MekanChip(label: widget.room, icon: LucideIcons.home)
                  .animate(delay: 220.ms)
                  .fadeIn(duration: 320.ms)
                  .slideY(
                    begin: 0.2,
                    end: 0,
                    duration: 320.ms,
                    curve: Curves.easeOutCubic,
                  ),
              MekanChip(label: widget.theme, tint: KoalaColors.accentSoft)
                  .animate(delay: 280.ms)
                  .fadeIn(duration: 320.ms)
                  .slideY(
                    begin: 0.2,
                    end: 0,
                    duration: 320.ms,
                    curve: Curves.easeOutCubic,
                  ),
            ],
          ),

          const SizedBox(height: KoalaSpacing.lg),

          // ─── Before/After — climax moment ───
          BeforeAfter(
            beforeBytes: widget.beforeBytes,
            afterSrc: widget.afterSrc,
          )
              .animate(delay: 320.ms)
              .fadeIn(duration: 480.ms, curve: Curves.easeOutCubic)
              .scale(
                begin: const Offset(0.96, 0.96),
                end: const Offset(1, 1),
                duration: 480.ms,
                curve: Curves.easeOutCubic,
              ),

          // ─── Mock banner OR opt-in bookmark toggle ───
          if (widget.mock) ...[
            const SizedBox(height: KoalaSpacing.md),
            _MockBanner()
                .animate(delay: 600.ms)
                .fadeIn(duration: 320.ms),
          ] else ...[
            const SizedBox(height: KoalaSpacing.md),
            _BookmarkToggle(
              saved: _saved,
              loading: _saving,
              onTap: _toggleSave,
            )
                .animate(delay: 700.ms)
                .fadeIn(duration: 360.ms)
                .slideX(
                  begin: -0.04,
                  end: 0,
                  duration: 360.ms,
                  curve: Curves.easeOutCubic,
                ),
          ],

          const SizedBox(height: KoalaSpacing.xxl),

          // ─── Secondary actions row ───
          Row(
            children: [
              Expanded(
                child: MekanSecondaryButton(
                  label: 'Aynı tarzda tekrar',
                  onTap: widget.onRetry,
                  fullWidth: true,
                  icon: LucideIcons.refreshCw,
                ),
              ),
              const SizedBox(width: KoalaSpacing.md),
              Expanded(
                child: MekanSecondaryButton(
                  label: 'Başka tarz',
                  onTap: widget.onNewStyle,
                  fullWidth: true,
                  icon: LucideIcons.palette,
                ),
              ),
            ],
          ).animate(delay: 850.ms).fadeIn(duration: 320.ms).slideY(
                begin: 0.08,
                end: 0,
                duration: 320.ms,
                curve: Curves.easeOutCubic,
              ),

          const SizedBox(height: KoalaSpacing.lg),

          // ─── Primary CTA: Pro match — accent glow on entrance ───
          MekanPrimaryButton(
            label: 'Bu tasarımı gerçeğe dönüştür',
            onTap: widget.onPro,
            trailing: LucideIcons.arrowRight,
          )
              .animate(delay: 1000.ms)
              .fadeIn(duration: 360.ms)
              .slideY(
                begin: 0.1,
                end: 0,
                duration: 360.ms,
                curve: Curves.easeOutCubic,
              )
              // Soft glow pulse — kullanıcının dikkatini buraya çek
              .then(delay: 200.ms)
              .shimmer(
                duration: 1400.ms,
                color: KoalaColors.accent.withValues(alpha: 0.35),
              ),

          const SizedBox(height: KoalaSpacing.md),

          Text(
            'Bu odayı tasarlayabilecek iç mimarları sana getirelim — '
            'şehrinden ve senin tarzından çalışanları önce gösteririz.',
            style: KoalaText.bodySec,
            textAlign: TextAlign.center,
          ).animate(delay: 1080.ms).fadeIn(duration: 280.ms),

          const SizedBox(height: KoalaSpacing.xl),

          // ─── Footer: yeni foto ile başla ───
          Center(
            child: TextButton(
              onPressed: widget.onRestart,
              child: Text(
                'Yeni fotoğrafla başla',
                style: KoalaText.label.copyWith(
                  color: KoalaColors.accentDeep,
                  decoration: TextDecoration.underline,
                  decorationColor: KoalaColors.accentDeep,
                ),
              ),
            ),
          ).animate(delay: 1180.ms).fadeIn(duration: 240.ms),
        ],
      ),
    );
  }
}

/// "TASARIMIN HAZIR" eyebrow — caption-level uppercase + dot.
class _Eyebrow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pulsing dot — "live" sinyali
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: KoalaColors.accentDeep,
            shape: BoxShape.circle,
          ),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .fadeIn(duration: 1100.ms, curve: Curves.easeInOut)
            .scaleXY(begin: 0.7, end: 1.2, duration: 1100.ms),
        const SizedBox(width: 8),
        Text(
          'TASARIMIN HAZIR',
          style: KoalaText.caption.copyWith(
            color: KoalaColors.accentDeep,
            letterSpacing: 1.6,
          ),
        ),
      ],
    );
  }
}

/// Mock-mode warning banner — token-disciplined.
class _MockBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KoalaSpacing.md,
        vertical: KoalaSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: KoalaColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(KoalaRadius.md),
        border: Border.all(
          color: KoalaColors.warning.withValues(alpha: 0.45),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.info, size: 16, color: KoalaColors.warning),
          const SizedBox(width: KoalaSpacing.sm),
          Expanded(
            child: Text(
              'Demo · sunucuda anahtar ayarlandığında gerçek görseller gelir.',
              style: KoalaText.bodySmall.copyWith(
                color: KoalaColors.warning,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opt-in bookmark toggle — kullanıcı isterse kaydet.
/// Saved=true iken accentSoft fill + filled bookmark, saved=false iken outline.
/// Loading durumunda küçük spinner. Tek satır chip, tıklanabilir.
class _BookmarkToggle extends StatelessWidget {
  final bool saved;
  final bool loading;
  final VoidCallback onTap;

  const _BookmarkToggle({
    required this.saved,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = saved ? KoalaColors.accentSoft : Colors.transparent;
    final fg = saved ? KoalaColors.accentDeep : KoalaColors.textSec;
    final borderColor =
        saved ? Colors.transparent : KoalaColors.borderSolid;
    final label = saved ? 'Tasarımlarında' : 'Tasarımlarına ekle';

    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(KoalaRadius.pill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(
            horizontal: KoalaSpacing.md,
            vertical: KoalaSpacing.xs + 2,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(KoalaRadius.pill),
            border: Border.all(color: borderColor, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation(fg),
                  ),
                )
              else
                Icon(
                  saved ? LucideIcons.bookMarked : LucideIcons.bookmarkPlus,
                  size: 13,
                  color: fg,
                ),
              const SizedBox(width: 6),
              Text(
                label,
                style: KoalaText.labelSmall.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
