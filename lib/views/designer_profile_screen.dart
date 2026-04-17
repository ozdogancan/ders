import 'package:flutter/material.dart';

import '../core/theme/koala_tokens.dart';
import '../helpers/auth_guard.dart';
import '../services/evlumba_live_service.dart';
import '../services/saved_items_service.dart';
import '../widgets/chat/designer_chat_popup.dart';
import '../widgets/like_button.dart';
import '../widgets/save_button.dart';
import '../widgets/share_sheet.dart';

class DesignerProfileScreen extends StatefulWidget {
  final String designerId;
  final String? designerName;

  const DesignerProfileScreen({
    super.key,
    required this.designerId,
    this.designerName,
  });

  @override
  State<DesignerProfileScreen> createState() => _DesignerProfileScreenState();
}

class _DesignerProfileScreenState extends State<DesignerProfileScreen> {
  Map<String, dynamic>? _designer;
  List<Map<String, dynamic>> _projects = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDesigner();
  }

  Future<void> _loadDesigner() async {
    try {
      final designer = await EvlumbaLiveService.getDesigner(widget.designerId);
      List<Map<String, dynamic>> projects = [];
      if (designer != null) {
        projects =
            await EvlumbaLiveService.getDesignerProjects(widget.designerId);
      }
      if (mounted) {
        setState(() {
          _designer = designer;
          _projects = projects;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openChat() async {
    // Auth kontrolü
    if (!await ensureAuthenticated(context)) return;
    if (!mounted) return;

    final name = _designer?['full_name'] as String? ??
        widget.designerName ??
        'Tasarımcı';
    final avatar = _designer?['avatar_url'] as String?;

    DesignerChatPopup.show(
      context,
      designerId: widget.designerId,
      designerName: name,
      designerAvatarUrl: avatar,
      contextType: 'designer_profile',
      contextId: widget.designerId,
      contextTitle: '$name ile iletişim',
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _designer?['full_name'] as String? ??
        widget.designerName ??
        'Tasarımcı';
    final specialty = _designer?['specialty'] as String?;
    final city = _designer?['city'] as String?;
    final business = _designer?['business_name'] as String?;
    final avatar = _designer?['avatar_url'] as String?;

    final initials = name
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();

    return Scaffold(
      backgroundColor: KoalaColors.bg,
      appBar: AppBar(
        backgroundColor: KoalaColors.surface,
        surfaceTintColor: KoalaColors.surface,
        elevation: 0,
        title: Text(name, style: KoalaText.h3),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: KoalaColors.accent))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(KoalaSpacing.lg),
              child: Column(
                children: [
                  // ── Profile Card ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(KoalaSpacing.xxl),
                    decoration: KoalaDeco.cardElevated,
                    child: Column(
                      children: [
                        // Avatar
                        Container(
                          width: 80,
                          height: 80,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                KoalaColors.accent,
                                KoalaColors.accentMuted
                              ],
                            ),
                          ),
                          child: avatar != null
                              ? ClipOval(
                                  child: Image.network(avatar,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Center(
                                            child: Text(initials,
                                                style: const TextStyle(
                                                    fontSize: 28,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white)),
                                          )),
                                )
                              : Center(
                                  child: Text(initials,
                                      style: const TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white)),
                                ),
                        ),
                        const SizedBox(height: KoalaSpacing.lg),
                        Text(name, style: KoalaText.h2),
                        if (specialty != null) ...[
                          const SizedBox(height: KoalaSpacing.xs),
                          Text(specialty, style: KoalaText.bodySec),
                        ],
                        if (city != null || business != null) ...[
                          const SizedBox(height: KoalaSpacing.xs),
                          Text(
                            [if (business != null) business, if (city != null) city]
                                .join(' · '),
                            style: KoalaText.bodySmall,
                          ),
                        ],
                        const SizedBox(height: KoalaSpacing.xxl),

                        // ── MESAJ AT BUTTON ──
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: _openChat,
                            icon: const Icon(Icons.chat_bubble_outline_rounded,
                                size: 20),
                            label: const Text('Mesaj At',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: KoalaColors.accent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(KoalaRadius.md),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                        const SizedBox(height: KoalaSpacing.md),
                        // ── Like / Save / Share row ──
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _ActionIcon(
                              child: LikeButton(
                                itemType: SavedItemType.designer,
                                itemId: widget.designerId,
                                title: name,
                                imageUrl: _designer?['avatar_url'] as String?,
                                subtitle: specialty,
                                size: 22,
                              ),
                              label: 'Beğen',
                            ),
                            const SizedBox(width: KoalaSpacing.xl),
                            _ActionIcon(
                              child: SaveButton(
                                itemType: SavedItemType.designer,
                                itemId: widget.designerId,
                                title: name,
                                imageUrl: _designer?['avatar_url'] as String?,
                                subtitle: specialty,
                                size: 22,
                              ),
                              label: 'Kaydet',
                            ),
                            const SizedBox(width: KoalaSpacing.xl),
                            _ActionIcon(
                              onTap: () => ShareSheet.show(
                                context,
                                itemType: SavedItemType.designer,
                                itemId: widget.designerId,
                                title: name,
                                imageUrl: _designer?['avatar_url'] as String?,
                              ),
                              child: const Icon(Icons.ios_share_rounded,
                                  size: 22, color: KoalaColors.text),
                              label: 'Paylaş',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ── Projects ──
                  if (_projects.isNotEmpty) ...[
                    const SizedBox(height: KoalaSpacing.xxl),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Projeler', style: KoalaText.h3),
                    ),
                    const SizedBox(height: KoalaSpacing.md),
                    ..._projects.map((p) => _ProjectCard(project: p)),
                  ],
                ],
              ),
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// ACTION ICON (like/save/share with label)
// ═══════════════════════════════════════════════════════
class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.child,
    required this.label,
    this.onTap,
  });

  final Widget child;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 28, child: Center(child: child)),
        const SizedBox(height: 4),
        Text(label,
            style: KoalaText.caption
                .copyWith(color: KoalaColors.textMuted, fontSize: 11)),
      ],
    );
    if (onTap == null) return column;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KoalaRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: column,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// PROJECT CARD
// ═══════════════════════════════════════════════════════
class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project});
  final Map<String, dynamic> project;

  // "Bilgehan Ermiş Projesi" gibi tekrar eden title yerine kategori (Oturma
  // Odası vb) göster. project_type > room_type > category fallback.
  static const _trCategoryMap = {
    'living_room': 'Oturma Odası',
    'bedroom': 'Yatak Odası',
    'kitchen': 'Mutfak',
    'bathroom': 'Banyo',
    'dining_room': 'Yemek Odası',
    'office': 'Çalışma Odası',
    'kids_room': 'Çocuk Odası',
    'hallway': 'Koridor / Hol',
    'balcony': 'Balkon',
    'outdoor': 'Dış Mekan',
  };

  static String _prettyCategory(String raw) {
    final key = raw.toLowerCase().trim();
    if (_trCategoryMap.containsKey(key)) return _trCategoryMap[key]!;
    final cleaned = raw.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    if (cleaned.isEmpty) return raw;
    return cleaned
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  String _categoryOrTitle() {
    for (final k in ['project_type', 'room_type', 'category']) {
      final v = (project[k] ?? '').toString().trim();
      if (v.isNotEmpty) return _prettyCategory(v);
    }
    final t = (project['title'] ?? '').toString().trim();
    return t.isNotEmpty ? t : 'Proje';
  }

  @override
  Widget build(BuildContext context) {
    final title = _categoryOrTitle();
    final description = project['description'] as String? ?? '';
    final images = project['designer_project_images'] as List? ?? [];
    final firstImage =
        images.isNotEmpty ? images[0]['image_url'] as String? : null;

    return Container(
      margin: const EdgeInsets.only(bottom: KoalaSpacing.md),
      decoration: KoalaDeco.card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (firstImage != null)
            Image.network(
              firstImage,
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 180,
                color: KoalaColors.surfaceAlt,
                child: const Center(
                    child: Icon(Icons.image_rounded,
                        color: KoalaColors.textTer, size: 40)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(KoalaSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: KoalaText.h4),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: KoalaSpacing.xs),
                  Text(description,
                      style: KoalaText.bodySec,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
