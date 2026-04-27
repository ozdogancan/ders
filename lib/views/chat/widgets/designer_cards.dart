import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/koala_tokens.dart';
import '../../../helpers/auth_guard.dart';
import '../../../services/evlumba_live_service.dart';
import '../../../services/messaging_service.dart';
import '../../../services/saved_items_service.dart';
import '../../../widgets/save_button.dart';
import '../../../widgets/projects_gallery_popup.dart';

/// AI chat içinde gösterilen tasarımcı kartı.
/// Uzman Bul ekranındaki `_ExpertCard` ile görsel olarak birebir aynı —
/// 30 radius büyük kart, 64 px avatar (gerçek görsel), isim + rating + proje
/// sayısı, bio özeti, 5 proje thumb şeridi (132x78), tam genişlik mor
/// "Mesaj At" CTA. CTA tıklanınca `/chat/dm/:conversationId` stack'e push edilir.
class DesignerCards extends StatelessWidget {
  const DesignerCards(this.d, {super.key});
  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context) {
    // Gemini bazen designers dizisi yerine flat data gönderir — her iki format da
    List<Map<String, dynamic>> designers;
    final rawDesigners = d['designers'];
    if (rawDesigners is List && rawDesigners.isNotEmpty) {
      designers = rawDesigners.cast<Map<String, dynamic>>();
    } else if (d['name'] != null || d['full_name'] != null) {
      designers = [d];
    } else {
      designers = [];
    }

    // Aynı ID veya isimli tasarımcıları filtrele (AI bazen duplike döner)
    final seenIds = <String>{};
    designers = designers.where((ds) {
      final id = (ds['id'] ?? ds['name'] ?? ds['full_name'] ?? '')
          .toString()
          .trim();
      if (id.isEmpty) return true;
      return seenIds.add(id);
    }).toList();

    if (designers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Tasarımcı bilgisi yüklenemedi.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 4),
          child: Text(
            'Sana Uygun Tasarımcılar',
            style: GoogleFonts.manrope(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: KoalaColors.text,
            ),
          ),
        ),
        ...designers.map(
          (ds) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ChatExpertCard(designer: ds),
          ),
        ),
      ],
    );
  }
}

class _ChatExpertCard extends StatelessWidget {
  const _ChatExpertCard({required this.designer});
  final Map<String, dynamic> designer;

  String get _name =>
      (designer['full_name'] ?? designer['name'] ?? 'İsimsiz uzman')
          .toString()
          .trim();

  String get _avatar =>
      (designer['avatar_url'] ?? '').toString().trim();

  String get _id => (designer['id'] ?? '').toString();

  String get _matchReason =>
      (designer['match_reason'] ?? '').toString().trim();

  static const Map<String, String> _projectTypeLabels = {
    'living_room': 'Oturma',
    'bedroom': 'Yatak',
    'kitchen': 'Mutfak',
    'bathroom': 'Banyo',
    'kids_room': 'Çocuk',
    'office': 'Çalışma',
    'dining_room': 'Yemek',
    'hallway': 'Antre',
  };

  String _prettyType(String raw) {
    return _projectTypeLabels[raw.trim().toLowerCase()] ?? 'Proje';
  }

  String? get _bio {
    final raw = designer['bio']?.toString().trim();
    if (raw != null && raw.isNotEmpty) return raw;
    final specialty = designer['specialty']?.toString().trim();
    final city = designer['city']?.toString().trim();
    final parts = <String>[];
    if (specialty != null && specialty.isNotEmpty) parts.add(specialty);
    if (city != null && city.isNotEmpty) parts.add(city);
    return parts.isEmpty ? null : parts.join(' · ');
  }

  double get _rating {
    final r = designer['rating'];
    if (r is num) return r.toDouble();
    if (r is String) return double.tryParse(r) ?? 0;
    return 0;
  }

  int get _totalProjects {
    final t = designer['total_projects'];
    if (t is int) return t;
    if (t is num) return t.toInt();
    final pp = designer['portfolio_projects'] as List?;
    if (pp != null) return pp.length;
    final pi = designer['portfolio_images'] as List?;
    if (pi != null) return pi.length;
    return 0;
  }

  List<Map<String, dynamic>> get _projects {
    final raw = designer['portfolio_projects'] as List?;
    if (raw != null && raw.isNotEmpty) {
      return raw
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    final images = designer['portfolio_images'] as List?;
    if (images != null) {
      return images
          .whereType<String>()
          .map((url) => <String, dynamic>{
                'id': '',
                'title': '',
                'project_type': '',
                'cover_image_url': url,
                'image_url': url,
                'designer_id': _id,
              })
          .toList();
    }
    return const [];
  }

  void _openProfile(BuildContext context) {
    if (_id.isEmpty) return;
    HapticFeedback.lightImpact();
    context.push('/designer/$_id');
  }

  Future<void> _openChat(BuildContext context) async {
    if (_id.isEmpty) return;
    HapticFeedback.mediumImpact();

    if (!await ensureAuthenticated(context)) return;
    if (!context.mounted) return;

    final conv = await MessagingService.getOrCreateConversation(
      designerId: _id,
      contextType: 'ai_chat',
      contextId: _id,
      contextTitle: _name,
    );
    if (!context.mounted) return;
    final convId = conv?['id']?.toString();
    if (convId == null || convId.isEmpty) {
      HapticFeedback.heavyImpact();
      final err = MessagingService.lastConvError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            err == null || err.isEmpty
                ? 'Sohbet başlatılamadı. Lütfen birkaç saniye sonra tekrar deneyin.'
                : 'Sohbet başlatılamadı: $err',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }
    context.push('/chat/dm/$convId', extra: <String, dynamic>{
      'designerId': _id,
      if (_name.isNotEmpty) 'designerName': _name,
      if (_avatar.isNotEmpty) 'designerAvatarUrl': _avatar,
    });
  }

  Future<void> _openGallery(BuildContext context, int tapIndex) async {
    HapticFeedback.selectionClick();
    List<Map<String, dynamic>> resolved = _projects;
    if (resolved.isEmpty && _id.isNotEmpty && EvlumbaLiveService.isReady) {
      try {
        resolved = await EvlumbaLiveService.getDesignerProjects(_id, limit: 12);
      } catch (_) {}
    }
    if (!context.mounted || resolved.isEmpty) return;
    final idx = tapIndex.clamp(0, resolved.length - 1);
    await ProjectsGalleryPopup.show(
      context,
      projects: resolved,
      initialIndex: idx,
      designer: {
        'id': _id,
        'full_name': _name,
        'avatar_url': _avatar,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final projects = _projects.take(5).toList();
    final total = _totalProjects > 0 ? _totalProjects : projects.length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: avatar + isim + rating/proje sayısı + Save ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ExpertAvatar(url: _avatar, name: _name, size: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _name,
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: KoalaColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (_rating > 0) ...[
                          const Icon(LucideIcons.star,
                              size: 16, color: KoalaColors.star),
                          const SizedBox(width: 4),
                          Text(
                            _rating.toStringAsFixed(1),
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: KoalaColors.text,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        if (total > 0)
                          Text(
                            '$total Proje',
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color:
                                  KoalaColors.textSec.withValues(alpha: 0.72),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              SaveButton(
                itemType: SavedItemType.designer,
                itemId: _id.isNotEmpty ? _id : _name,
                title: _name,
                subtitle: designer['specialty']?.toString(),
                imageUrl: _avatar.isNotEmpty ? _avatar : null,
                size: 24,
                onToggled: (_) => HapticFeedback.selectionClick(),
              ),
            ],
          ),
          if (_bio != null) ...[
            const SizedBox(height: 14),
            Text(
              _bio!,
              style: GoogleFonts.manrope(
                fontSize: 14,
                height: 1.55,
                color: KoalaColors.textSec,
              ),
            ),
          ],
          if (projects.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: projects.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final p = projects[i];
                  final imageUrl =
                      (p['cover_image_url'] ?? p['image_url'] ?? '')
                          .toString();
                  final title = (p['title'] ?? '').toString().trim();
                  final projectType = (p['project_type'] ?? '').toString();
                  final label =
                      title.isEmpty ? _prettyType(projectType) : title;
                  return GestureDetector(
                    onTap: () => _openGallery(context, i),
                    child: SizedBox(
                      width: 132,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: SizedBox(
                              width: 132,
                              height: 78,
                              child: imageUrl.isEmpty
                                  ? Container(
                                      color: KoalaColors.surfaceAlt,
                                      child: const Icon(
                                        LucideIcons.imageOff,
                                        size: 20,
                                        color: KoalaColors.textTer,
                                      ),
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: imageUrl,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 264,
                                      placeholder: (_, __) => Container(
                                        color: KoalaColors.surfaceAlt,
                                      ),
                                      errorWidget: (_, __, ___) => Container(
                                        color: KoalaColors.surfaceAlt,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: KoalaColors.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (_matchReason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.sparkles,
                    size: 12,
                    color: KoalaColors.accentDeep.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _matchReason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: KoalaColors.textSec,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 40,
                child: GestureDetector(
                  onTap: () => _openProfile(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: KoalaColors.accentDeep.withValues(alpha: 0.4),
                        width: 1.2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Profil',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: KoalaColors.accentDeep,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 60,
                child: GestureDetector(
                  onTap: () => _openChat(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      color: KoalaColors.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Mesaj At',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExpertAvatar extends StatelessWidget {
  const _ExpertAvatar({
    required this.url,
    required this.name,
    this.size = 48,
  });

  final String url;
  final String name;
  final double size;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'U';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: url.isEmpty
            ? const LinearGradient(
                colors: [KoalaColors.accent, Color(0xFF9B8AFF)],
              )
            : null,
        image: url.isNotEmpty
            ? DecorationImage(
                image: CachedNetworkImageProvider(url),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: url.isEmpty
          ? Text(
              _initials,
              style: GoogleFonts.manrope(
                fontSize: size * 0.3,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            )
          : null,
    );
  }
}
