// Designer portfolio swipe — tasarımcı profilinde bir tasarıma tıklayınca
// açılır, yatay PageView ile diğer tasarımlarına kayarak geçilebilir.
// Her tasarım sayfasında sağ alt köşede persistent "Sor" floating button —
// tek tıkta showAskAndApplySheet açar, ekstra network roundtrip yok.
//
// Web'de mouse-drag swipe aktif (custom ScrollBehavior). Mobil'de native.
//
// Kullanıcı geri bildirimi: "swipe da bi resme basıyorum profil açılıyor
// orada tasarımlar var birine tıklıyorum diğerine bu açtığımı kapamadan
// geçemiyorum" — bu ekran tam olarak bu sorunu çözer.

import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/koala_tokens.dart';
import '../../widgets/ask_and_apply_sheet.dart';

/// Tasarımcı portfolyosu içinde swipe edilebilir tam-ekran tasarım gezgini.
///
/// [projects] — tasarımcının tüm yayınlanmış tasarımları (`DesignerProfileSheet`
/// tarafından zaten çekilmiş, ekstra fetch yok).
/// [initialIndex] — kullanıcının tıkladığı kartın sıradaki yeri.
/// [designerId]/[designerName]/[designerAvatarUrl] — Sor sheet'ine doğrudan
/// iletilir; lazy fetch yapılmaması için pre-resolved.
class DesignerDesignSwipeScreen extends StatefulWidget {
  final List<Map<String, dynamic>> projects;
  final int initialIndex;
  final String designerId;
  final String? designerName;
  final String? designerAvatarUrl;

  const DesignerDesignSwipeScreen({
    super.key,
    required this.projects,
    required this.designerId,
    this.initialIndex = 0,
    this.designerName,
    this.designerAvatarUrl,
  });

  @override
  State<DesignerDesignSwipeScreen> createState() =>
      _DesignerDesignSwipeScreenState();
}

class _DesignerDesignSwipeScreenState extends State<DesignerDesignSwipeScreen> {
  late final PageController _ctrl;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.projects.length - 1);
    _ctrl = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _coverOf(Map<String, dynamic> p) {
    for (final k in ['cover_image_url', 'cover_url', 'image_url']) {
      final v = (p[k] ?? '').toString().trim();
      if (v.isNotEmpty && !v.startsWith('data:')) return v;
    }
    final imgs = p['designer_project_images'] as List?;
    if (imgs != null && imgs.isNotEmpty) {
      final sorted = List<Map<String, dynamic>>.from(
        imgs.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
      )..sort((a, b) => ((a['sort_order'] as num?)?.toInt() ?? 9999)
          .compareTo((b['sort_order'] as num?)?.toInt() ?? 9999));
      return (sorted.first['image_url'] ?? '').toString();
    }
    return '';
  }

  String _prettyCategory(String raw) {
    final r = raw.trim().toLowerCase();
    const map = {
      'living_room': 'Oturma Odası',
      'bedroom': 'Yatak Odası',
      'kitchen': 'Mutfak',
      'bathroom': 'Banyo',
      'kids_room': 'Çocuk Odası',
      'office': 'Çalışma Odası',
      'dining_room': 'Yemek Odası',
      'hallway': 'Antre',
    };
    return map[r] ?? raw;
  }

  Future<void> _onAsk(Map<String, dynamic> p) async {
    HapticFeedback.selectionClick();
    final id = p['id']?.toString() ?? '';
    final title = (p['title'] ?? '').toString().trim();
    final cat = _prettyCategory((p['project_type'] ?? '').toString());
    final displayTitle =
        title.isNotEmpty ? title : (cat.isNotEmpty ? '$cat projesi' : 'Tasarım');
    await showAskAndApplySheet(
      context,
      designId: id,
      title: displayTitle,
      imageUrl: _coverOf(p),
      subtitle: cat.isNotEmpty ? cat : null,
      designerId: widget.designerId,
      designerName: widget.designerName,
      designerAvatarUrl: widget.designerAvatarUrl,
      category: cat.isNotEmpty ? cat : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.projects.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.shrink(),
      );
    }
    final current = widget.projects[_index];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Web'de mouse-drag swipe için custom ScrollBehavior.
            ScrollConfiguration(
              behavior: const _DragScrollBehavior(),
              child: PageView.builder(
                controller: _ctrl,
                itemCount: widget.projects.length,
                physics: const PageScrollPhysics(parent: BouncingScrollPhysics()),
                onPageChanged: (i) {
                  HapticFeedback.selectionClick();
                  setState(() => _index = i);
                },
                itemBuilder: (_, i) => _DesignPage(
                  project: widget.projects[i],
                  coverUrl: _coverOf(widget.projects[i]),
                ),
              ),
            ),
            // Üst gradient — kapat butonu okunaklı olsun.
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 140,
              child: IgnorePointer(
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
            ),
            // Alt gradient — başlık / Sor pill kontrastı.
            const Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 240,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC000000)],
                    ),
                  ),
                ),
              ),
            ),
            // Kapat butonu
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              child: _GlassIconButton(
                icon: LucideIcons.x,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
            // Sayfa göstergesi (1 / N)
            Positioned(
              top: MediaQuery.of(context).padding.top + 14,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '${_index + 1} / ${widget.projects.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
            // Başlık + Sor FAB. Sor butonu sağ alt — persistent.
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 18,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((current['project_type'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Text(
                                _prettyCategory(
                                    (current['project_type'] ?? '').toString()),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        if ((current['title'] ?? '').toString().trim().isNotEmpty)
                          Text(
                            (current['title'] ?? '').toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _SorPill(onTap: () => _onAsk(current)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesignPage extends StatelessWidget {
  final Map<String, dynamic> project;
  final String coverUrl;
  const _DesignPage({required this.project, required this.coverUrl});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: coverUrl.isEmpty
          ? const Icon(LucideIcons.imageOff,
              color: Colors.white24, size: 56)
          : CachedNetworkImage(
              imageUrl: coverUrl,
              fit: BoxFit.contain,
              fadeInDuration: const Duration(milliseconds: 220),
              placeholder: (_, _) => const SizedBox.shrink(),
              errorWidget: (_, _, _) => const Icon(
                LucideIcons.imageOff,
                color: Colors.white24,
                size: 56,
              ),
            ),
    );
  }
}

/// Persistent "Sor" pill — altın aksan + cam efektli.
class _SorPill extends StatelessWidget {
  final VoidCallback onTap;
  const _SorPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(100),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: KoalaColors.accentDeep,
            borderRadius: BorderRadius.circular(100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.messageCircle, size: 16, color: Colors.white),
              SizedBox(width: 6),
              Text(
                'Sor',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.black.withValues(alpha: 0.32),
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon, color: Colors.white, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

/// Web/desktop'ta mouse-drag ile swipe için kustom ScrollBehavior.
/// PageView default'unda touch/stylus dışındaki cihazlar drag etmiyor.
class _DragScrollBehavior extends MaterialScrollBehavior {
  const _DragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.unknown,
      };
}
