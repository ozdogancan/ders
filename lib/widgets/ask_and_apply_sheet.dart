// Paylaşılan "Sor ve Uygula" bottom sheet.
//
// Style discovery'deki 3-seçenek "Sor" popup'ının yeniden kullanılabilir hâli +
// 4. seçenek: Mekânıma Uygula → foto picker → MekanWizardScreen(targetDesignUrl).
//
// Profile tab'daki Tasarımlarım carousel'inde her kartın altındaki "Sor ve
// Uygula" CTA bu sheet'i açar.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/koala_tokens.dart';
import '../services/evlumba_live_service.dart';
import '../views/mekan/wizard/mekan_wizard_screen.dart';
import 'free_consult_sheet.dart';

const String _evlumbaDesignAvatarUrl =
    'https://xgefjepaqnghaotqybpi.supabase.co/storage/v1/object/public/koala-seed/avatars/evlumba-design.webp';

/// [designId]/[title]/[imageUrl] — tasarımın chat'e iliştirilecek meta'sı.
/// [designerId] varsa ve `evlumba-design` değilse "Tasarımcısına sor" seçeneği
/// gözükür. [designerName]/[designerAvatarUrl] varsa kullanılır, yoksa lazy
/// fetch ile çekilir.
Future<void> showAskAndApplySheet(
  BuildContext context, {
  required String designId,
  required String title,
  required String imageUrl,
  String? subtitle,
  String? designerId,
  String? designerName,
  String? designerAvatarUrl,
  String? category,
  bool isOwnDesign = false,
}) async {
  HapticFeedback.selectionClick();
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: KoalaColors.bg,
    barrierColor: Colors.black54,
    isScrollControlled: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _AskAndApplySheet(
      designId: designId,
      title: title,
      imageUrl: imageUrl,
      subtitle: subtitle,
      designerId: designerId,
      designerName: designerName,
      designerAvatarUrl: designerAvatarUrl,
      category: category,
      isOwnDesign: isOwnDesign,
    ),
  );
}

class _AskAndApplySheet extends ConsumerStatefulWidget {
  final String designId;
  final String title;
  final String imageUrl;
  final String? subtitle;
  final String? designerId;
  final String? designerName;
  final String? designerAvatarUrl;
  final String? category;
  final bool isOwnDesign;

  const _AskAndApplySheet({
    required this.designId,
    required this.title,
    required this.imageUrl,
    this.subtitle,
    this.designerId,
    this.designerName,
    this.designerAvatarUrl,
    this.category,
    this.isOwnDesign = false,
  });

  @override
  ConsumerState<_AskAndApplySheet> createState() => _AskAndApplySheetState();
}

class _AskAndApplySheetState extends ConsumerState<_AskAndApplySheet> {
  String? _designerName;
  String? _designerAvatar;

  @override
  void initState() {
    super.initState();
    _designerName = widget.designerName;
    _designerAvatar = widget.designerAvatarUrl;
    final id = widget.designerId ?? '';
    if (id.isNotEmpty &&
        id != 'evlumba-design' &&
        (_designerName == null || _designerName!.isEmpty)) {
      _lazyFetchDesigner(id);
    }
  }

  Future<void> _lazyFetchDesigner(String id) async {
    try {
      final d = await EvlumbaLiveService.getDesigner(id);
      if (!mounted || d == null) return;
      setState(() {
        _designerName =
            (d['full_name'] ?? d['business_name'] ?? '').toString().trim();
        _designerAvatar = (d['avatar_url'] ?? '').toString().trim();
      });
    } catch (_) {/* sessiz */}
  }

  Map<String, dynamic> _pendingDesign(String forDesignerId) => {
        'id': widget.designId,
        'title': widget.title,
        if ((widget.subtitle ?? '').isNotEmpty) 'tagline': widget.subtitle,
        if ((widget.category ?? '').isNotEmpty) 'category': widget.category,
        'imageUrl': widget.imageUrl,
        'designerId': forDesignerId,
      };

  Future<void> _onApply() async {
    Navigator.of(context).pop();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final picker = ImagePicker();
      final f = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 60,
      );
      if (f == null) return;
      final bytes = await f.readAsBytes();
      navigator.push(
        MaterialPageRoute(
          builder: (_) => MekanWizardScreen(
            photoBytes: bytes,
            targetDesignUrl:
                widget.imageUrl.isNotEmpty ? widget.imageUrl : null,
            targetDesignerId: widget.designerId,
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Fotoğraf seçilemedi.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final designerId = (widget.designerId ?? '').trim();
    // Kullanıcının kendi tasarımı için "Tasarımcısına sor" gizlenir —
    // yalnız Koala AI + Evlumba Design seçenekleri kalır.
    final showDesignerOption = !widget.isOwnDesign &&
        designerId.isNotEmpty &&
        designerId != 'evlumba-design';
    final ctx = context;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: KoalaColors.border,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 2),
              child: Text('Sor', style: KoalaText.h2),
            ),
            const SizedBox(height: 4),
            Text(
              'Bu tasarımı kime soralım?',
              style: KoalaText.bodySmall,
            ),
            const SizedBox(height: 12),
            _askOption(
              leading: const _AskLeading(
                icon: Icons.auto_awesome_rounded,
                gradient: true,
              ),
              title: "Koala AI'ya sor",
              subtitle: 'Yapay zekâ asistanından anında fikir al',
              onTap: () {
                Navigator.of(ctx).pop();
                ctx.push('/chat/ai', extra: {
                  'initialText': 'Bu tasarımı beğendim: "${widget.title}". '
                      'Bunun gibi bir tarzı evime nasıl uygulayabilirim?',
                });
              },
            ),
            _askOption(
              leading: const _AskLeading(
                imageUrl: _evlumbaDesignAvatarUrl,
                icon: Icons.home_work_rounded,
              ),
              title: "Evlumba Design'a sor",
              subtitle: 'Evlumba stüdyosundan profesyonel destek al',
              onTap: () {
                Navigator.of(ctx).pop();
                // Tek-konuşma + free-consult gate. Yeni thread yaratmaz —
                // her zaman aynı Evlumba conv'a gider.
                enterEvlumbaConversation(
                  ctx,
                  ref,
                  projectTitle: widget.title,
                  pendingDesign: _pendingDesign('evlumba-design'),
                );
              },
            ),
            if (showDesignerOption)
              _askOption(
                leading: _AskLeading(
                  imageUrl: (_designerAvatar ?? '').isNotEmpty
                      ? _designerAvatar
                      : null,
                  icon: Icons.person_rounded,
                ),
                title: 'Tasarımcısına sor',
                subtitle: (_designerName ?? '').isNotEmpty
                    ? '${_designerName!} ile doğrudan konuş'
                    : 'Bu tasarımı yapan tasarımcıyla konuş',
                onTap: () {
                  Navigator.of(ctx).pop();
                  ctx.push('/chat/dm/new', extra: {
                    'designerId': designerId,
                    if ((_designerName ?? '').isNotEmpty)
                      'designerName': _designerName,
                    if ((_designerAvatar ?? '').isNotEmpty)
                      'designerAvatarUrl': _designerAvatar,
                    'projectTitle': widget.title,
                    'pendingDesign': _pendingDesign(designerId),
                  });
                },
              ),
            // 2026-05-28: "Mekânıma uygula" seçeneği geçici olarak kaldırıldı
            // (kullanıcı kararı). İleride geri açılacaksa highlight'lı şekilde
            // tekrar render edilebilir.
          ],
        ),
      ),
    );
  }

  Widget _askOption({
    required Widget leading,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool highlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: highlight
            ? KoalaColors.accentDeep.withValues(alpha: 0.06)
            : KoalaColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: highlight
                  ? Border.all(
                      color: KoalaColors.accentDeep.withValues(alpha: 0.35),
                      width: 1)
                  : null,
            ),
            child: Row(
              children: [
                SizedBox(width: 48, height: 48, child: leading),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: KoalaText.h4),
                      const SizedBox(height: 2),
                      Text(subtitle, style: KoalaText.bodySmall),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: highlight
                        ? KoalaColors.accentDeep
                        : KoalaColors.textMuted,
                    size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AskLeading extends StatelessWidget {
  final String? imageUrl;
  final IconData? icon;
  final bool gradient;
  final bool tintGold;
  const _AskLeading({
    this.imageUrl,
    this.icon,
    this.gradient = false,
    this.tintGold = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: gradient && !hasImage
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [KoalaColors.accentDeep, KoalaColors.accent],
              )
            : (tintGold && !hasImage
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFD66B), Color(0xFFEFA01F)],
                  )
                : null),
        color: hasImage
            ? null
            : ((gradient || tintGold) ? null : KoalaColors.accentSoft),
        boxShadow: [
          BoxShadow(
            color: (tintGold
                    ? const Color(0xFFEFA01F)
                    : KoalaColors.accent)
                .withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: hasImage ? Clip.antiAlias : Clip.none,
      child: hasImage
          ? CachedNetworkImage(
              imageUrl: imageUrl!,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(color: KoalaColors.accentSoft),
              errorWidget: (_, _, _) => Container(
                color: KoalaColors.accentSoft,
                child: Icon(
                  icon ?? Icons.person_rounded,
                  color: KoalaColors.accentDeep,
                  size: 22,
                ),
              ),
            )
          : Center(
              child: Icon(
                icon ?? Icons.help_outline_rounded,
                size: 22,
                color: (gradient || tintGold)
                    ? Colors.white
                    : KoalaColors.accentDeep,
              ),
            ),
    );
  }
}
