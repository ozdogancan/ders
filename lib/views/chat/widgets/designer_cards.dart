import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/koala_tokens.dart';
import '../../../helpers/auth_guard.dart';
import '../../../services/saved_items_service.dart';
import '../../../services/profile_feedback_service.dart';
import '../../../widgets/like_button.dart';
import '../../../widgets/save_button.dart';
import '../../../widgets/share_sheet.dart';
import '../../../widgets/chat/designer_chat_popup.dart';
import '../../designer_profile_screen.dart';
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
                // thumb'a "+N" overlay eklenir, dokunulduğunda profil açılır.
                if (ds['portfolio_images'] != null && (ds['portfolio_images'] as List).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _PortfolioStrip(
                      designerId: ds['id']?.toString() ?? '',
                      designerName: name,
                      images: List<String>.from(
                        (ds['portfolio_images'] as List).whereType<String>(),
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
                const SizedBox(height: 8),
                // Secondary \u2014 Profili G\u00F6r (full-width outline)
                GestureDetector(
                  onTap: () {
                    final designerId = ds['id']?.toString() ?? '';
                    final profileUrl = designerId.isNotEmpty
                        ? 'https://www.evlumba.com/tasarimci/$designerId'
                        : 'https://www.evlumba.com/tasarimcilar';
                    launchUrl(
                      Uri.parse(profileUrl),
                      mode: LaunchMode.inAppBrowserView,
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: accent.withValues(alpha: 0.25)),
                    ),
                    child: const Center(
                      child: Text(
                        'Profili G\u00F6r',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
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

/// Portfolio thumb şeridi — max 3 görseli gösterir. 3'ten fazla varsa son
/// thumb'ın üzerine "+N Tümünü gör" overlay koyar ve dokunuşu designer
/// profile ekranına yönlendirir (orada bütün portfolio kategorili görünür).
class _PortfolioStrip extends StatelessWidget {
  const _PortfolioStrip({
    required this.designerId,
    required this.designerName,
    required this.images,
  });

  final String designerId;
  final String designerName;
  final List<String> images;

  static const int _visible = 3;

  void _openProfile(BuildContext context) {
    if (designerId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DesignerProfileScreen(
          designerId: designerId,
          designerName: designerName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = images.length;
    final show = total <= _visible ? total : _visible;
    final extra = total - show;

    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: show,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final isLastWithExtra = i == show - 1 && extra > 0;
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
                child: Icon(Icons.image_rounded, color: KoalaColors.textTer),
              ),
            ),
          );

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _openProfile(context);
            },
            child: Stack(
              children: [
                thumb,
                if (isLastWithExtra)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.55),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '+$extra',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Text(
                              'Tümünü gör',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
