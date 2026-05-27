import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/koala_tokens.dart';
import '../../widgets/ask_and_apply_sheet.dart';
import '../mekan/wizard/mekan_wizard_screen.dart';

/// Tasarım detay — tam ekran sinematik görüntüleyici.
///
/// Tasarım kararları:
/// - Arka plan SİYAH. Foto hero transition'dan geliyor.
/// - Alt info bar: başlık + (varsa) tarz chip + Uygula / Sor / Paylaş trio.
/// - 3 CTA hep aynı: "Bu tarzı mekânına uygula", "Sor", "WhatsApp'ta paylaş".
class DesignDetailScreen extends StatelessWidget {
  final Map<String, dynamic> item;
  const DesignDetailScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final imageUrl = (item['image_url'] as String?) ?? '';
    final title = (item['title'] as String?) ?? 'Mekan';
    final subtitle = (item['subtitle'] as String?) ?? '';
    // Hero tag MUST match ProfileDesignTile's tag: 'design-${item['id'] ?? title}'.
    final id = item['id']?.toString() ?? title;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Hero foto
            Hero(
              tag: 'design-$id',
              child: Center(
                child: imageUrl.isEmpty
                    ? _broken()
                    : CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                        fadeInDuration: const Duration(milliseconds: 240),
                        errorWidget: (_, _, _) => _broken(),
                      ),
              ),
            ),
            // Üst gradient
            const Positioned(
              top: 0, left: 0, right: 0, height: 140,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x99000000), Colors.transparent],
                  ),
                ),
              ),
            ),
            // Alt gradient
            const Positioned(
              bottom: 0, left: 0, right: 0, height: 320,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xEE000000)],
                  ),
                ),
              ),
            ),
            // Kapat
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: KoalaSpacing.md,
              child: _CircleBtn(
                icon: LucideIcons.x,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            // İnfo bar
            Positioned(
              left: 0, right: 0,
              bottom: MediaQuery.of(context).padding.bottom + KoalaSpacing.lg,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: KoalaSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.4,
                        height: 1.1,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius:
                                BorderRadius.circular(KoalaRadius.pill),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.18),
                                width: 0.5),
                          ),
                          child: Text(
                            subtitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: KoalaSpacing.lg),
                    // 2026-05-28: "Uygula" geçici olarak kaldırıldı.
                    // Action row: Sor (primary) + Paylaş.
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _PrimaryActionBtn(
                            icon: LucideIcons.messageCircle,
                            label: 'Sor',
                            onTap: () => _onAsk(context),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _IconActionBtn(
                          icon: LucideIcons.share2,
                          tooltip: 'Paylaş',
                          onTap: () => _onShare(),
                        ),
                      ],
                    ),
                  ],
                ).animate().fadeIn(duration: 320.ms, delay: 140.ms).slideY(
                      begin: 0.12,
                      end: 0,
                      duration: 320.ms,
                      delay: 140.ms,
                      curve: Curves.easeOutCubic,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Actions ─────────────────────────────────────────────────────────

  String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  Map<String, String?> _designerMeta() {
    final extra = item['extra_data'];
    if (extra is! Map) return const {};
    return {
      'designer_id': _str(extra['designer_id']),
      'designer_name': _str(extra['designer_name']),
      'designer_avatar_url': _str(extra['designer_avatar_url']),
      'category': _str(extra['category'] ?? extra['style_tr']),
    };
  }

  Future<void> _onApply(BuildContext context) async {
    HapticFeedback.selectionClick();
    final imageUrl = (item['image_url'] as String?) ?? '';
    final meta = _designerMeta();
    // "Uygula" → kullanıcının mekan fotoğrafını seç, sonra wizard'a hedef
    // tasarım URL'i ile gir. Wizard photoBytes ister.
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: KoalaColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: KoalaColors.border,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading:
                  const Icon(LucideIcons.camera, color: KoalaColors.accentDeep),
              title: const Text('Fotoğraf çek', style: KoalaText.bodyMedium),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading:
                  const Icon(LucideIcons.image, color: KoalaColors.accentDeep),
              title: const Text('Galeriden seç', style: KoalaText.bodyMedium),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        imageQuality: 60,
      );
      if (picked == null || !context.mounted) return;
      final bytes = await picked.readAsBytes();
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MekanWizardScreen(
            photoBytes: bytes,
            targetDesignUrl: imageUrl,
            targetDesignerId: meta['designer_id'],
          ),
        ),
      );
    } catch (_) {/* swallow */}
  }

  Future<void> _onAsk(BuildContext context) async {
    HapticFeedback.selectionClick();
    final meta = _designerMeta();
    final id = (item['item_id'] ?? item['id'] ?? '').toString();
    final title = (item['title'] ?? 'Tasarım').toString();
    final imageUrl = (item['image_url'] ?? '').toString();
    final subtitle = (item['subtitle'] ?? '').toString();
    // Fast — sheet is already a top-level scaffolded modal, opens in <300ms.
    await showAskAndApplySheet(
      context,
      designId: id,
      title: title,
      imageUrl: imageUrl,
      subtitle: subtitle.isNotEmpty ? subtitle : null,
      designerId: meta['designer_id'],
      designerName: meta['designer_name'],
      designerAvatarUrl: meta['designer_avatar_url'],
      category: meta['category'],
    );
  }

  Future<void> _onShare() async {
    HapticFeedback.selectionClick();
    final imageUrl = (item['image_url'] as String?) ?? '';
    final meta = _designerMeta();
    final dname = meta['designer_name'];
    final attribution = (dname != null && dname.isNotEmpty)
        ? '\nTasarım: $dname'
        : '';
    final body = imageUrl.isEmpty
        ? 'Koala\'da bu tasarıma bayıldım!$attribution\nhttps://koalatutor.com'
        : 'Koala\'da bu tasarıma bayıldım, sana da göstermek istedim:\n'
            '$imageUrl$attribution\n\nhttps://koalatutor.com';
    final uri = Uri.parse(
      'https://api.whatsapp.com/send?text=${Uri.encodeComponent(body)}',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {/* swallow */}
  }

  Widget _broken() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.imageOff,
              color: Colors.white54, size: 40),
          const SizedBox(height: 10),
          Text(
            'Görsel süresi doldu',
            style: KoalaText.bodySec.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.18), width: 0.5),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _PrimaryActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PrimaryActionBtn(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: KoalaColors.text,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KoalaRadius.pill),
        ),
      ),
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _IconActionBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _IconActionBtn(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.14),
        shape: const CircleBorder(
          side: BorderSide(color: Color(0x33FFFFFF), width: 0.5),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}
