// Shared mini profile bottom-sheet — başkasının profilini ON-DEMAND göstermek
// için tek nokta. user_quick_popup + user_profile_sheet'in yerini alır.
//
// İçerik:
//   - Compact hero card (avatar 72, isim, role chip, "Üye"/"Pro" pill).
//   - Action row: Takip Et / Takipte toggle pill, Mesaj pill, ⋯ menu
//     (sessize al / engelle / şikayet — stub'lar dahil).
//   - Stats row (Tasarımlar / Takipçi / Takip).
//   - 2 tab: Paylaşımlar (AI üretimleri + paylaşımlar karışık) / AI (yalnız
//     AI). Public veri üzerinden — kullanıcı kendi data'sını burada görmez
//     (bu kendi profilin için ProfileTabScreen var).
//   - Tile tap → UserDesignSwipeScreen.
//   - Pro/designer + self değilse "Yorum bırak" CTA — modal review form.
//
// Kullanım:
//   MiniProfileSheet.open(context, user: koalaUser);

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../core/theme/koala_tokens.dart';
import '../../services/designer_reviews_service.dart';
import '../../services/follow_service.dart';
import '../../services/shared_design_service.dart';
import '../../services/user_profile_service.dart';
import 'profile_photo_view.dart';
import 'user_design_swipe.dart';

class MiniProfileSheet extends ConsumerStatefulWidget {
  final KoalaUserProfile user;
  const MiniProfileSheet({super.key, required this.user});

  static Future<void> open(BuildContext context,
      {required KoalaUserProfile user}) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: KoalaColors.bg,
      isScrollControlled: true,
      enableDrag: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => MiniProfileSheet(user: user),
    );
  }

  @override
  ConsumerState<MiniProfileSheet> createState() => _MiniProfileSheetState();
}

class _MiniProfileSheetState extends ConsumerState<MiniProfileSheet>
    with SingleTickerProviderStateMixin {
  bool? _isFollowing;
  bool? _isDesigner;
  bool _busyFollow = false;

  int _followers = 0;
  int _following = 0;

  List<Map<String, dynamic>> _aiDesigns = const [];
  List<Map<String, dynamic>> _sharedDesigns = const [];
  bool _loading = true;

  DesignerReviewsResult _reviews = DesignerReviewsResult.empty;
  bool _reviewsLoading = false;

  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _isDesigner = widget.user.isPro ? true : null;
    _loadAll();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final uid = widget.user.uid;
    if (uid.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final stF = FollowService.stateFor(uid);
    final cntF = FollowService.counts(uid);
    final designerF = widget.user.isPro
        ? Future<bool>.value(true)
        : UserProfileService.isDesigner(uid);
    final sharedF = SharedDesignService.publicByUid(uid, limit: 40);
    final aiF = _loadPublicAi(uid);

    final results = await Future.wait<dynamic>([
      stF,
      cntF,
      designerF,
      sharedF,
      aiF,
    ]);

    if (!mounted) return;
    final st = results[0] as FollowState;
    final cnt = results[1] as ({int followers, int following});
    final designer = results[2] as bool;
    final shared = results[3] as List;
    final ai = results[4] as List<Map<String, dynamic>>;

    setState(() {
      _isFollowing = st.following;
      _followers = cnt.followers;
      _following = cnt.following;
      _isDesigner = designer;
      _sharedDesigns = shared
          .cast<SharedDesign>()
          .map((s) => {
                ...s.toMapForProfileTab(),
                'is_ai': false,
              })
          .toList();
      _aiDesigns = ai;
      _loading = false;
    });

    // Yorumları yalnız designer/pro için yükle.
    if (designer || widget.user.isPro) {
      _loadReviews();
    }
  }

  /// Public AI üretimleri — koala_saved_items üzerinden, user_id eşitliği.
  /// Defansif: tablonun visibility kolonu yoksa boş döner.
  Future<List<Map<String, dynamic>>> _loadPublicAi(String uid) async {
    try {
      // Mevcut SavedItemsService.getByType yalnız current user'a bakar.
      // Burada başkasının public AI'larını çekmek için doğrudan tabloyu
      // sorguluyoruz — visibility/public kolonu varsa eq, yoksa hep boş.
      final data = await Supabase.instance.client
          .from('koala_saved_items')
          .select(
              'item_id, image_url, title, subtitle, extra_data, created_at, item_type')
          .eq('user_id', uid)
          .eq('item_type', 'project')
          .order('created_at', ascending: false)
          .limit(40);
      final rows = List<Map<String, dynamic>>.from(data);
      return rows
          .map((r) => {
                'id': (r['item_id'] ?? '').toString(),
                'item_id': (r['item_id'] ?? '').toString(),
                'image_url': (r['image_url'] ?? '').toString(),
                'title': (r['title'] ?? '').toString(),
                'subtitle': (r['subtitle'] ?? '').toString(),
                'extra_data': r['extra_data'],
                'is_ai': true,
              })
          .where((r) => (r['image_url'] as String).isNotEmpty)
          .toList();
    } catch (e) {
      // Defansif: tablo yoksa veya RLS engellerse sessiz boş döner.
      return const [];
    }
  }

  Future<void> _loadReviews() async {
    if (_reviewsLoading) return;
    setState(() => _reviewsLoading = true);
    final r = await DesignerReviewsService.getForDesigner(widget.user.uid);
    if (!mounted) return;
    setState(() {
      _reviews = r;
      _reviewsLoading = false;
    });
  }

  Future<void> _toggleFollow() async {
    if (_busyFollow) return;
    setState(() => _busyFollow = true);
    final prev = _isFollowing ?? false;
    setState(() {
      _isFollowing = !prev;
      _followers += prev ? -1 : 1;
    });
    try {
      final st = await FollowService.toggle(widget.user.uid);
      if (!mounted) return;
      setState(() => _isFollowing = st.following);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isFollowing = prev;
        _followers += prev ? 1 : -1;
      });
    } finally {
      if (mounted) setState(() => _busyFollow = false);
    }
  }

  void _openChat() {
    final uid = widget.user.uid;
    if (uid.isEmpty) return;
    Navigator.of(context).pop();
    // Mesaj — designer ise dm/new, değilse de aynı route (defansif).
    context.push('/chat/dm/new', extra: {
      'designerId': uid,
      if ((widget.user.displayName ?? '').isNotEmpty)
        'designerName': widget.user.displayName,
      if ((widget.user.avatarUrl ?? '').isNotEmpty)
        'designerAvatarUrl': widget.user.avatarUrl,
    });
  }

  void _openMoreMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KoalaColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: KoalaColors.border,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const SizedBox(height: 6),
            ListTile(
              leading: const Icon(LucideIcons.bellOff,
                  color: KoalaColors.textSec),
              title: const Text('Bildirimleri sessize al',
                  style: KoalaText.bodyMedium),
              onTap: () async {
                Navigator.pop(ctx);
                await FollowService.muteToggle(widget.user.uid);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Bildirim tercihin güncellendi.')),
                );
              },
            ),
            ListTile(
              leading:
                  const Icon(LucideIcons.userX, color: KoalaColors.error),
              title: const Text('Engelle',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: KoalaColors.error)),
              onTap: () {
                Navigator.pop(ctx);
                _toast('Engelleme yakında');
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.flag,
                  color: KoalaColors.textSec),
              title: const Text('Şikayet et', style: KoalaText.bodyMedium),
              onTap: () {
                Navigator.pop(ctx);
                _toast('Şikayetin alındı, ekibimiz inceleyecek.');
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  List<Map<String, dynamic>> get _allDesigns => [
        ..._aiDesigns,
        ..._sharedDesigns,
      ];

  void _openSwipe(List<Map<String, dynamic>> list, int index) {
    if (list.isEmpty) return;
    UserDesignSwipeScreen.open(
      context,
      items: list,
      ownerUid: widget.user.uid,
      initialIndex: index,
    );
  }

  Future<void> _openReviewForm() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null || me.isEmpty) return;
    if (me == widget.user.uid) return; // self-review yasak — UI gate.
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: KoalaColors.bg,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ReviewFormSheet(designerId: widget.user.uid),
    );
    if (submitted == true) _loadReviews();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final me = FirebaseAuth.instance.currentUser?.uid;
    final isSelf = me != null && me == user.uid;
    final isDesignerOrPro = (_isDesigner == true) || user.isPro;
    final canReview = !isSelf && isDesignerOrPro;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.45,
      maxChildSize: 0.96,
      builder: (_, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: KoalaColors.border,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _hero(),
                    const SizedBox(height: 12),
                    _actionRow(),
                    const SizedBox(height: 16),
                    _statsRow(),
                    if (canReview) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 20),
                        child: OutlinedButton.icon(
                          onPressed: _openReviewForm,
                          icon: const Icon(LucideIcons.star, size: 16),
                          label: const Text('Yorum bırak'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: KoalaColors.accentDeep,
                            side: const BorderSide(
                                color: KoalaColors.accentDeep, width: 1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(100),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                          ),
                        ),
                      ),
                    ],
                    if (isDesignerOrPro && _reviews.count > 0) ...[
                      const SizedBox(height: 14),
                      _reviewsBlock(),
                    ],
                    const SizedBox(height: 18),
                    _tabBar(),
                    _tabBody(),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _hero() {
    final user = widget.user;
    final name = (user.displayName?.trim().isNotEmpty == true)
        ? user.displayName!.trim()
        : 'Koala kullanıcısı';
    final hasAvatar = (user.avatarUrl ?? '').isNotEmpty;
    final about = (user.about ?? '').trim();
    final tag = 'minisheet-${user.uid}';
    final isDesignerOrPro = (_isDesigner == true) || user.isPro;
    final roleLabel = isDesignerOrPro
        ? (about.isNotEmpty ? 'Profesyonel Tasarımcı' : 'Koala Pro')
        : 'Ev Sahibi';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: KoalaColors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: hasAvatar
                  ? () {
                      HapticFeedback.selectionClick();
                      ProfilePhotoView.open(context,
                          url: user.avatarUrl!, heroTag: tag);
                    }
                  : null,
              child: Hero(
                tag: tag,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KoalaColors.accentSoft,
                    border: Border.all(
                      color: isDesignerOrPro
                          ? KoalaColors.accentDeep
                          : KoalaColors.borderSolid,
                      width: isDesignerOrPro ? 1.4 : 0.6,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: hasAvatar
                      ? CachedNetworkImage(
                          imageUrl: user.avatarUrl!, fit: BoxFit.cover)
                      : const Icon(LucideIcons.user,
                          size: 32, color: KoalaColors.accentDeep),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: KoalaText.h2.copyWith(
                            fontSize: 18,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      if (user.verified) ...[
                        const SizedBox(width: 6),
                        const Icon(LucideIcons.badgeCheck,
                            size: 16, color: KoalaColors.accentDeep),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDesignerOrPro
                          ? KoalaColors.accentSoft
                          : KoalaColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      roleLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isDesignerOrPro
                            ? KoalaColors.accentDeep
                            : KoalaColors.textSec,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                  if (about.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      about,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: KoalaColors.textSec,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionRow() {
    final followKnown = _isFollowing != null;
    final following = _isFollowing == true;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 42,
              child: ElevatedButton(
                onPressed:
                    !followKnown || _busyFollow ? null : _toggleFollow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: (followKnown && following)
                      ? KoalaColors.surface
                      : KoalaColors.accentDeep,
                  foregroundColor: (followKnown && following)
                      ? KoalaColors.text
                      : Colors.white,
                  side: (followKnown && following)
                      ? const BorderSide(
                          color: KoalaColors.borderSolid, width: 1)
                      : BorderSide.none,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  !followKnown
                      ? 'Yükleniyor…'
                      : (following ? 'Takipte' : 'Takip Et'),
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 42,
              child: OutlinedButton.icon(
                onPressed: _openChat,
                icon: const Icon(LucideIcons.messageCircle, size: 16),
                label: const Text('Mesaj',
                    style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: KoalaColors.text,
                  side: const BorderSide(
                      color: KoalaColors.borderSolid, width: 1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 42,
            height: 42,
            child: OutlinedButton(
              onPressed: _openMoreMenu,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: KoalaColors.textSec,
                side: const BorderSide(
                    color: KoalaColors.borderSolid, width: 1),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Icon(LucideIcons.moreHorizontal, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsRow() {
    final designs = _allDesigns.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(child: _stat(designs, 'Tasarım')),
          Expanded(child: _stat(_followers, 'Takipçi')),
          Expanded(child: _stat(_following, 'Takip')),
        ],
      ),
    );
  }

  Widget _stat(int n, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          n.toString(),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: KoalaColors.text,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: KoalaColors.textSec,
          ),
        ),
      ],
    );
  }

  Widget _reviewsBlock() {
    final avg = _reviews.avg.toStringAsFixed(1);
    final shown = _reviews.reviews.take(3).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.star,
                  size: 16, color: Color(0xFFEFA01F)),
              const SizedBox(width: 6),
              Text(
                'Yorumlar ($avg/5 · ${_reviews.count})',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: KoalaColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...shown.map((r) => _reviewCard(r)),
        ],
      ),
    );
  }

  Widget _reviewCard(DesignerReview r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KoalaColors.borderSolid, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(
              5,
              (i) => Icon(
                i < r.rating ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 14,
                color: const Color(0xFFEFA01F),
              ),
            ),
          ),
          if ((r.comment ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              r.comment!,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: KoalaColors.text,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tabBar() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: KoalaColors.borderSolid, width: 0.6),
          bottom: BorderSide(color: KoalaColors.borderSolid, width: 0.6),
        ),
      ),
      child: TabBar(
        controller: _tabCtrl,
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorWeight: 1.6,
        indicatorColor: KoalaColors.text,
        dividerHeight: 0,
        labelColor: KoalaColors.text,
        unselectedLabelColor: KoalaColors.textTer,
        tabs: const [
          Tab(
            height: 42,
            iconMargin: EdgeInsets.zero,
            icon: Icon(LucideIcons.layoutGrid, size: 18),
          ),
          Tab(
            height: 42,
            iconMargin: EdgeInsets.zero,
            icon: Icon(LucideIcons.sparkles, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _tabBody() {
    if (_loading) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: CircularProgressIndicator(
              color: KoalaColors.accentDeep, strokeWidth: 2),
        ),
      );
    }
    final isAll = _tabCtrl.index == 0;
    final items = isAll ? _allDesigns : _aiDesigns;
    if (items.isEmpty) {
      return _emptyTab(isAll);
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        childAspectRatio: 1,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final it = items[i];
        final url = (it['image_url'] ?? it['thumb_url'] ?? '').toString();
        final isAi = it['is_ai'] == true;
        return GestureDetector(
          onTap: () => _openSwipe(items, i),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                color: KoalaColors.surfaceAlt,
                child: url.isEmpty
                    ? Container(color: KoalaColors.surfaceAlt)
                    : CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => Container(
                          color: KoalaColors.surfaceAlt,
                          child: const Icon(LucideIcons.imageOff,
                              color: KoalaColors.textTer, size: 22),
                        ),
                      ),
              ),
              if (isAi)
                const Positioned(
                  top: 4,
                  right: 4,
                  child: _MiniAiPill(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _emptyTab(bool isAll) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
      child: Column(
        children: [
          Icon(
            isAll ? LucideIcons.layoutGrid : LucideIcons.sparkles,
            size: 28,
            color: KoalaColors.textTer,
          ),
          const SizedBox(height: 8),
          Text(
            isAll ? 'Henüz paylaşım yok' : 'Henüz AI tasarımı yok',
            style: KoalaText.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _MiniAiPill extends StatelessWidget {
  const _MiniAiPill();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(99),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.sparkles, size: 7, color: KoalaColors.accentDeep),
          SizedBox(width: 2),
          Text(
            'AI',
            style: TextStyle(
              fontSize: 7.5,
              fontWeight: FontWeight.w800,
              color: KoalaColors.accentDeep,
              letterSpacing: 0.3,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Yorum formu sheet ──────────────────────────────────────────────
class _ReviewFormSheet extends StatefulWidget {
  final String designerId;
  const _ReviewFormSheet({required this.designerId});
  @override
  State<_ReviewFormSheet> createState() => _ReviewFormSheetState();
}

class _ReviewFormSheetState extends State<_ReviewFormSheet> {
  int _rating = 0;
  final _ctrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_rating < 1) {
      setState(() => _error = 'Lütfen bir yıldız seç.');
      return;
    }
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me != null && me == widget.designerId) {
      setState(() => _error = 'Kendine yorum bırakamazsın.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final ok = await DesignerReviewsService.submit(
      designerId: widget.designerId,
      rating: _rating,
      comment: _ctrl.text,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _submitting = false;
        _error = 'Yorum gönderilemedi. Tekrar dene.';
      });
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KoalaColors.border,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Yorum bırak', style: KoalaText.h2),
              const SizedBox(height: 4),
              const Text(
                'Bu tasarımcı/profesyonel hakkındaki deneyimini paylaş.',
                style: KoalaText.bodySmall,
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final filled = i < _rating;
                  return IconButton(
                    iconSize: 34,
                    icon: Icon(
                      filled
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: const Color(0xFFEFA01F),
                    ),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      setState(() => _rating = i + 1);
                    },
                  );
                }),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ctrl,
                maxLines: 4,
                maxLength: 500,
                style: KoalaText.body,
                decoration: InputDecoration(
                  hintText: 'Birkaç cümle yaz (opsiyonel)',
                  hintStyle: KoalaText.hint,
                  filled: true,
                  fillColor: KoalaColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: KoalaColors.borderSolid, width: 0.8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: KoalaColors.borderSolid, width: 0.8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: KoalaColors.accentDeep, width: 1.2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(
                        color: KoalaColors.error, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KoalaColors.accentDeep,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(
                    _submitting ? 'Gönderiliyor…' : 'Gönder',
                    style: KoalaText.button,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
