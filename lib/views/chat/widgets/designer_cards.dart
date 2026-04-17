import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/koala_tokens.dart';
import '../../../helpers/auth_guard.dart';
import '../../../services/evlumba_live_service.dart';
import '../../../services/saved_items_service.dart';
import '../../../services/profile_feedback_service.dart';
import '../../../widgets/like_button.dart';
import '../../../widgets/save_button.dart';
import '../../../widgets/share_sheet.dart';
import '../../../widgets/chat/designer_chat_popup.dart';
import '../../../widgets/projects_gallery_popup.dart';
import 'chat_constants.dart';

class DesignerCards extends StatelessWidget {
  const DesignerCards(this.d, {super.key});
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    // Gemini bazen designers dizisi yerine flat data g\u00F6nderir \u2014 her iki format\u0131 da handle et
    List<Map<String, dynamic>> designers;
    final rawDesigners = d['designers'];
    if (rawDesigners is List && rawDesigners.isNotEmpty) {
      designers = rawDesigners.cast<Map<String, dynamic>>();
    } else if (d['name'] != null) {
      // Flat format \u2014 kart kendisi tek bir tasar\u0131mc\u0131
      designers = [d];
    } else {
      designers = [];
    }
    // Aynı ID veya isimli tasarımcıları filtrele (AI bazen duplike döner)
    final seenIds = <String>{};
    designers = designers.where((ds) {
      final id = (ds['id'] ?? ds['name'] ?? '').toString().trim();
      if (id.isEmpty) return true;
      return seenIds.add(id); // add returns false if already exists
    }).toList();
    if (designers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Tasar\u0131mc\u0131 bilgisi y\u00FCklenemedi.', style: TextStyle(color: Colors.grey)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            'Sana Uygun Tasar\u0131mc\u0131lar',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ),
        ...designers.map((ds) {
          final name = ds['name'] as String? ?? '';
          final initials = name
              .split(' ')
              .map((w) => w.isNotEmpty ? w[0] : '')
              .take(2)
              .join()
              .toUpperCase();
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R),
              color: Colors.white,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [accent, KoalaColors.accentMuted],
                        ),
                      ),
                      child: Center(
                        child: Text(
                          initials,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                          Text(
                            '${ds['title'] ?? '\u0130\u00E7 Mimar'} \u00B7 ${ds['specialty'] ?? ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (ds['rating'] != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: const Color(0xFFFFF7ED),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: KoalaColors.star,
                            ),
                            Text(
                              ' ${ds['rating']}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: KoalaColors.star,
                              ),
                            ),
                          ],
                        ),
                      ),
                    LikeButton(
                      itemType: SavedItemType.designer,
                      itemId: ds['id']?.toString() ?? name,
                      title: name,
                      imageUrl: ds['avatar_url'] as String?,
                      subtitle: ds['title'] as String? ?? '\u0130\u00E7 Mimar',
                      size: 20,
                    ),
                    SaveButton(
                      itemType: SavedItemType.designer,
                      itemId: ds['id']?.toString() ?? name,
                      title: name,
                      subtitle: ds['title'] as String? ?? '\u0130\u00E7 Mimar',
                      size: 20,
                      onToggled: (isSaved) {
                        if (isSaved) {
                          ProfileFeedbackService.recordSaveSignal(
                            itemTitle: name,
                            style: ds['specialty'] as String?,
                          );
                        }
                      },
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        ShareSheet.show(
                          context,
                          itemType: SavedItemType.designer,
                          itemId: ds['id']?.toString() ?? name,
                          title: name,
                          imageUrl: ds['avatar_url'] as String?,
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.share_rounded,
                          size: 20,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                  ],
                ),
                if (ds['bio'] != null && (ds['bio'] as String).isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: const Color(0xFFF3F0FF),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.auto_awesome_rounded, size: 14, color: accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            ds['bio'] as String,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                              height: 1.4,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Response time indicator
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 8, height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: KoalaColors.greenAlt,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        ds['city'] != null ? 'Genellikle 24 saat i\u00E7inde yan\u0131tlar \u00B7 ${ds['city']}' : 'Genellikle 24 saat i\u00E7inde yan\u0131tlar',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                // Portfolio görselleri — max 3 thumb; daha fazla varsa son
                // thumb'a "+N" overlay eklenir, tıklanınca tüm galerisi açılır.
                if ((ds['portfolio_projects'] as List?)?.isNotEmpty == true ||
                    (ds['portfolio_images'] as List?)?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _PortfolioStrip(
                      designerId: ds['id']?.toString() ?? '',
                      designerName: name,
                      designerAvatarUrl: ds['avatar_url']?.toString(),
                      totalProjects: (ds['total_projects'] as int?) ??
                          ((ds['portfolio_projects'] as List?)?.length ??
                              (ds['portfolio_images'] as List?)?.length ??
                              0),
                      projects: (ds['portfolio_projects'] as List?)
                              ?.whereType<Map>()
                              .map((m) => Map<String, dynamic>.from(m))
                              .toList() ??
                          const [],
                      images: List<String>.from(
                        (ds['portfolio_images'] as List? ?? const [])
                            .whereType<String>(),
                      ),
                    ),
                  ),
                if (ds['min_budget'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'Min: ${ds['min_budget']}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                // Primary CTA — Tasarımcıya Yaz (popup — AI chat kaybolmaz)
                GestureDetector(
                  onTap: () async {
                    final designerId = ds['id']?.toString() ?? '';
                    if (designerId.isEmpty) return;
                    HapticFeedback.lightImpact();

                    // Auth kontrolü — anonim kullanıcıyı giriş ekranına yönlendir
                    if (!await ensureAuthenticated(context)) return;
                    if (!context.mounted) return;

                    final specialty = ds['specialty']?.toString() ?? '';

                    DesignerChatPopup.show(
                      context,
                      designerId: designerId,
                      designerName: name,
                      designerAvatarUrl: ds['avatar_url']?.toString(),
                      contextType: 'ai_chat',
                      contextId: designerId,
                      initialMessage: specialty.isNotEmpty
                          ? 'Merhaba, $specialty alanındaki çalışmalarınızı inceledim. Projem için görüşmek isterim.'
                          : 'Merhaba, çalışmalarınızı çok beğendim. Projem için görüşmek isterim.',
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: KoalaColors.greenAlt,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_rounded, size: 15, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'Tasar\u0131mc\u0131ya Yaz',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

/// Portfolio thumb şeridi — max 3 görseli gösterir. 3'ten fazla proje varsa
/// son thumb'ın üzerine "+N" overlay koyar; tap tüm galeriyi `ProjectsGalleryPopup`
/// ile açar. Her thumb altında proje kategorisi (`project_type` → Türkçe) yazar.
class _PortfolioStrip extends StatelessWidget {
  const _PortfolioStrip({
    required this.designerId,
    required this.designerName,
    required this.images,
    required this.projects,
    required this.totalProjects,
    this.designerAvatarUrl,
  });

  final String designerId;
  final String designerName;
  final String? designerAvatarUrl;
  final List<String> images;
  final List<Map<String, dynamic>> projects;
  final int totalProjects;

  static const int _visible = 3;

  String _prettyCategory(String raw) {
    const trMap = {
      'living_room': 'Oturma Odası',
      'bedroom': 'Yatak Odası',
      'kitchen': 'Mutfak',
      'bathroom': 'Banyo',
      'kids_room': 'Çocuk Odası',
      'office': 'Çalışma Odası',
      'dining_room': 'Yemek Odası',
      'hallway': 'Antre',
      'balcony': 'Balkon',
      'outdoor': 'Dış Mekan',
    };
    final key = raw.toLowerCase().trim();
    if (trMap.containsKey(key)) return trMap[key]!;
    final cleaned = raw.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    if (cleaned.isEmpty) return 'Proje';
    return cleaned
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  Future<List<Map<String, dynamic>>> _resolveProjects() async {
    if (projects.isNotEmpty) return projects;
    // Fallback: portfolio_images varsa image'lardan project stub'ı üret
    if (designerId.isNotEmpty && EvlumbaLiveService.isReady) {
      try {
        final fetched = await EvlumbaLiveService.getDesignerProjects(
          designerId,
          limit: 12,
        );
        if (fetched.isNotEmpty) return fetched;
      } catch (_) {}
    }
    return images
        .map((url) => <String, dynamic>{
              'id': '',
              'title': '',
              'project_type': '',
              'cover_image_url': url,
              'image_url': url,
              'designer_id': designerId,
            })
        .toList();
  }

  Future<void> _openGallery(BuildContext context, int tapIndex) async {
    HapticFeedback.selectionClick();
    final resolved = await _resolveProjects();
    if (!context.mounted || resolved.isEmpty) return;
    final idx = tapIndex.clamp(0, resolved.length - 1);
    await ProjectsGalleryPopup.show(
      context,
      projects: resolved,
      initialIndex: idx,
      designer: {
        'id': designerId,
        'full_name': designerName,
        'avatar_url': designerAvatarUrl ?? '',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = totalProjects > 0 ? totalProjects : images.length;
    final thumbsCount = images.length;
    final show = thumbsCount <= _visible ? thumbsCount : _visible;
    final extra = total - show;

    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: show,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final isLastWithExtra = i == show - 1 && extra > 0;
          final pt = i < projects.length
              ? (projects[i]['project_type'] ?? '').toString()
              : '';
          final categoryLabel = pt.isEmpty ? 'Proje' : _prettyCategory(pt);
          final thumb = ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              images[i],
              width: 96,
              height: 72,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 96,
                height: 72,
                color: KoalaColors.surfaceMuted,
                child: const Icon(LucideIcons.imageOff,
                    size: 20, color: KoalaColors.textTer),
              ),
            ),
          );

          return GestureDetector(
            onTap: () => _openGallery(context, i),
            child: SizedBox(
              width: 96,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      thumb,
                      if (isLastWithExtra)
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.55),
                              alignment: Alignment.center,
                              child: Text(
                                '+$extra',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    categoryLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: KoalaColors.textSec,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
