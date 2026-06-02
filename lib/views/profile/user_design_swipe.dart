// Fullscreen design swipe — bir kullanıcının tüm tasarımları arasında yatay
// PageView. Her sayfada görsel + 3 floating CTA: Paylaş / Sor / Uygula.
//
// Kaynak: AI üretimleri (saved_items type=project) + kullanıcı paylaşımları
// (koala_user_shared_designs). Caller liste + initialIndex passlar.
//
// CTA davranışı:
//   - Paylaş → InstagramShareSheet (WhatsApp / Instagram-yakında / Linki kopyala
//     / Sistem paylaş).
//   - Sor → showAskAndApplySheet. ownerUid == currentUid ise `isOwnDesign:true`
//     ile çağrılır → "Tasarımcısına sor" gizlenir, yalnız Koala AI + Evlumba.
//   - Uygula → showAskAndApplySheet (aynı sheet, "Mekânıma uygula" satırı).
//
// NOT: Bu ekran swipe içinde aktif bir alt-shell olmadığı için modal değil;
// MaterialPageRoute ile push edilir. Arka plan siyah, üst safe area'da kapatma.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/koala_tokens.dart';
import '../../services/shared_design_service.dart';
import '../../widgets/ask_and_apply_sheet.dart';
import '../../widgets/koala_ai_badge.dart';
import 'instagram_share_sheet.dart';

class UserDesignSwipeScreen extends StatefulWidget {
  /// Map normalize: her item şu key'leri içerebilir:
  ///   - id / item_id
  ///   - image_url
  ///   - title
  ///   - subtitle
  ///   - is_ai (bool) — UI rozet için
  ///   - extra_data (Map) — designer_id, designer_name, category vb.
  final List<Map<String, dynamic>> items;
  final int initialIndex;

  /// Bu listenin sahibi olan kullanıcının UID'i. CurrentUser ile eşleşirse
  /// "Sor" sheet'inde tasarımcı seçeneği gizlenir.
  final String ownerUid;

  const UserDesignSwipeScreen({
    super.key,
    required this.items,
    required this.ownerUid,
    this.initialIndex = 0,
  });

  static Future<void> open(
    BuildContext context, {
    required List<Map<String, dynamic>> items,
    required String ownerUid,
    int initialIndex = 0,
  }) {
    if (items.isEmpty) return Future.value();
    return Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, _, _) => UserDesignSwipeScreen(
          items: items,
          ownerUid: ownerUid,
          initialIndex: initialIndex,
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  State<UserDesignSwipeScreen> createState() => _UserDesignSwipeScreenState();
}

class _UserDesignSwipeScreenState extends State<UserDesignSwipeScreen> {
  late final PageController _ctrl;
  late int _index;

  // 2026-06-02: Oturum başına tek görüntülenme — aynı tasarımı ileri-geri
  // kaydırınca tekrar sayma.
  final Set<String> _viewedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _ctrl = PageController(initialPage: _index);
    _countView(_index);
  }

  void _countView(int i) {
    if (i < 0 || i >= widget.items.length) return;
    final item = widget.items[i];
    // Yalnız paylaşım tasarımları (AI değil) — Evlumba projesi id'si zaten
    // RPC'de 0 satır eşler ama gereksiz çağrı yapma.
    if (item['is_ai'] == true) return;
    final id = (item['id'] ?? item['item_id'] ?? '').toString();
    if (id.isEmpty || _viewedIds.contains(id)) return;
    _viewedIds.add(id);
    SharedDesignService.incrementView(id);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _isOwner {
    final me = FirebaseAuth.instance.currentUser?.uid;
    return me != null && me.isNotEmpty && me == widget.ownerUid;
  }

  Map<String, dynamic> get _current => widget.items[_index];

  String get _designId =>
      (_current['id'] ?? _current['item_id'] ?? '').toString();
  String get _imageUrl => (_current['image_url'] ?? '').toString();
  // 2026-06-02: Başlıktan "Yeni " önekini at (kullanıcı isteği — "Yeni Yemek
  // Odası" yerine sadece "Yemek Odası").
  String get _title {
    var t = (_current['title'] ?? 'Tasarım').toString().trim();
    t = t.replaceFirst(RegExp(r'^\s*[Yy]eni\s+'), '');
    return t.isEmpty ? 'Tasarım' : t;
  }

  String get _subtitle => (_current['subtitle'] ?? '').toString();

  bool get _aiGenerated => _current['is_ai'] == true;

  /// Sol-altta gösterilecek "Kategori · Tarz" satırı — hem AI hem paylaşım
  /// tasarımları için tutarlı. Oda tipini ve tarzı item alanlarından türetir.
  String get _metaLine {
    String pretty(String raw) {
      final r = raw.trim().toLowerCase().replaceAll('_', ' ').replaceAll('i̇', 'i');
      if (r.isEmpty) return '';
      const map = {
        'living room': 'Oturma Odası', 'salon': 'Oturma Odası', 'oturma odasi': 'Oturma Odası',
        'bedroom': 'Yatak Odası', 'yatak odasi': 'Yatak Odası',
        'kitchen': 'Mutfak', 'mutfak': 'Mutfak',
        'bathroom': 'Banyo', 'banyo': 'Banyo',
        'kids room': 'Çocuk Odası', 'cocuk odasi': 'Çocuk Odası',
        'office': 'Çalışma Odası', 'ofis': 'Çalışma Odası', 'calisma odasi': 'Çalışma Odası',
        'dining room': 'Yemek Odası', 'yemek odasi': 'Yemek Odası',
        'hallway': 'Antre', 'antre': 'Antre', 'hall': 'Hol', 'hol': 'Hol',
        'balcony': 'Balkon', 'balkon': 'Balkon',
        'modern': 'Modern', 'minimal': 'Minimal', 'skandinav': 'Skandinav',
        'klasik': 'Klasik', 'bohem': 'Bohem', 'endustriyel': 'Endüstriyel',
        'luks': 'Lüks', 'japandi': 'Japandi',
      };
      final hit = map[r];
      if (hit != null) return hit;
      return r.split(' ').where((w) => w.isNotEmpty)
          .map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
    }

    final p = _current;
    final cat = pretty([
      (p['project_type'] ?? '').toString(),
      (p['category'] ?? '').toString(),
      (p['room_type'] ?? p['roomType'] ?? '').toString(),
    ].firstWhere((s) => s.trim().isNotEmpty, orElse: () => ''));
    String style = pretty((p['style'] ?? '').toString());
    if (style.isEmpty) {
      final tags = p['tags'];
      if (tags is List && tags.isNotEmpty) style = pretty(tags.first.toString());
    }
    return [cat, style].where((s) => s.isNotEmpty).join(' · ');
  }

  ({String? designerId, String? designerName, String? designerAvatar, String? category})
      get _designerInfo {
    final extra = _current['extra_data'];
    if (extra is! Map) {
      return (
        designerId: null,
        designerName: null,
        designerAvatar: null,
        category: null
      );
    }
    String? norm(String key) {
      final v = (extra[key] ?? '').toString().trim();
      return v.isEmpty ? null : v;
    }

    return (
      designerId: norm('designer_id'),
      designerName: norm('designer_name'),
      designerAvatar: norm('designer_avatar_url'),
      category: norm('category') ?? norm('style_tr'),
    );
  }

  Future<void> _onShare() async {
    HapticFeedback.selectionClick();
    await InstagramShareSheet.show(
      context,
      title: _title,
      imageUrl: _imageUrl,
      linkUrl: _imageUrl,
    );
  }

  Future<void> _onAsk() async {
    HapticFeedback.selectionClick();
    final info = _designerInfo;
    await showAskAndApplySheet(
      context,
      designId: _designId,
      title: _title,
      imageUrl: _imageUrl,
      subtitle: _subtitle.isNotEmpty ? _subtitle : null,
      designerId: info.designerId,
      designerName: info.designerName,
      designerAvatarUrl: info.designerAvatar,
      category: info.category,
      isOwnDesign: _isOwner,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const Scaffold(backgroundColor: Colors.black);
    }
    final topPad = MediaQuery.of(context).padding.top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _ctrl,
              itemCount: widget.items.length,
              physics:
                  const PageScrollPhysics(parent: BouncingScrollPhysics()),
              onPageChanged: (i) {
                HapticFeedback.selectionClick();
                setState(() => _index = i);
                _countView(i);
              },
              itemBuilder: (_, i) => _DesignPage(item: widget.items[i]),
            ),
            // Top gradient + close + index pill.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: topPad + 120,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x99000000), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: topPad + 6,
              left: 8,
              child: _circleBtn(
                icon: LucideIcons.x,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
            Positioned(
              top: topPad + 14,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '${_index + 1} / ${widget.items.length}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ),
            // Bottom gradient + CTAs.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  height: 220,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC000000)],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Başlık + (varsa) Koala AI rozeti.
                      if (_title.isNotEmpty)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                _title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                  shadows: [
                                    Shadow(
                                      color: Color(0x99000000),
                                      blurRadius: 6,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_aiGenerated) ...[
                              const SizedBox(width: 8),
                              const KoalaAiBadge(size: 28),
                            ],
                          ],
                        ),
                      // 2026-06-02: Kategori · Tarz — hem AI hem paylaşım için
                      // (eskiden non-AI'da görünmüyordu). subtitle yoksa meta.
                      if (_metaLine.isNotEmpty || _subtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _metaLine.isNotEmpty ? _metaLine : _subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xCCFFFFFF),
                            letterSpacing: -0.1,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          // 2026-05-28: "Uygula" geçici olarak kaldırıldı.
                          Expanded(
                            child: _bottomCta(
                              icon: LucideIcons.messageCircle,
                              label: 'Sor',
                              primary: true,
                              onTap: _onAsk,
                            ),
                          ),
                          const SizedBox(width: 10),
                          _circleBtn(
                            icon: LucideIcons.share2,
                            onTap: _onShare,
                            size: 50,
                            iconSize: 20,
                            bg: Colors.white,
                            iconColor: KoalaColors.text,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomCta({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return Material(
      color: primary
          ? KoalaColors.accentDeep
          : Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: primary
                ? null
                : Border.all(
                    color: Colors.white.withValues(alpha: 0.18), width: 0.8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _circleBtn({
    required IconData icon,
    required VoidCallback onTap,
    double size = 40,
    double iconSize = 18,
    Color bg = const Color(0x66000000),
    Color iconColor = Colors.white,
  }) {
    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: iconColor, size: iconSize),
        ),
      ),
    );
  }
}

class _DesignPage extends StatelessWidget {
  final Map<String, dynamic> item;
  const _DesignPage({required this.item});

  @override
  Widget build(BuildContext context) {
    final imageUrl = (item['image_url'] ?? '').toString();
    final id = (item['id'] ?? item['item_id'] ?? '').toString();
    final tag = 'design-${id.isEmpty ? imageUrl : id}';
    return Center(
      child: Hero(
        tag: tag,
        child: imageUrl.isEmpty
            ? _broken()
            : CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                fadeInDuration: const Duration(milliseconds: 220),
                placeholder: (_, _) => const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                ),
                errorWidget: (_, _, _) => _broken(),
              ),
      ),
    );
  }

  Widget _broken() => const Center(
        child: Icon(LucideIcons.imageOff, color: Colors.white38, size: 36),
      );
}
