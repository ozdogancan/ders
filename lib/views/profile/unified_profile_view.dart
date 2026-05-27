// ═══════════════════════════════════════════════════════════════════════
// UnifiedProfileView — SS5 visual pattern (avatar + name + role + stats +
// Takip et + Hakkında + Tasarımları grid) shared across:
//   • Swipe card tap → designer profile (was DesignerProfileSheet)
//   • Mini profile sheet "Profili gör"
//   • Own profile tab (ownerEditable: true)
//
// When `viewedDesignId` is non-null, the matching tile in the Tasarımları
// grid gets a subtle dark overlay (alpha 0.30) + "Bunu görüntülediniz" pill
// at the top-left of that tile.
//
// When `ownerEditable` is true and the viewer is the same user, the follow
// row is replaced by an "Profili düzenle" + "Paylaş" row, and an "AI
// Stüdyom →" pill appears above the design grid when AI designs exist.
// ═══════════════════════════════════════════════════════════════════════

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../core/theme/koala_tokens.dart';
import '../../services/designer_reviews_service.dart';
import '../../services/evlumba_live_service.dart';
import '../../services/follow_service.dart';
import '../../services/saved_items_service.dart';
import '../../services/shared_design_service.dart';
import '../../services/user_profile_service.dart';
import '../../widgets/verified_badge.dart';
import '../projeler_screen.dart';
import 'profile_design_tile.dart';

class UnifiedProfileView extends StatefulWidget {
  final String profileId;
  final String? viewedDesignId;
  final bool ownerEditable;

  /// Optional override of the displayed profile (e.g. for designer cards from
  /// swipe deck where the row has already been hydrated). Falls back to a
  /// network fetch when null.
  final Map<String, dynamic>? seedProfile;

  /// Optional pre-loaded project pool — used by evlumba-design swipe deck.
  final List<Map<String, dynamic>>? seedPool;

  /// Called when the user long-presses the avatar (own profile → settings).
  final VoidCallback? onAvatarLongPress;

  /// Called when the owner taps "Profili düzenle".
  final VoidCallback? onEditProfile;

  /// Called when the owner taps the "AI Stüdyom →" pill.
  final VoidCallback? onOpenAiStudio;

  /// Called when a design tile is tapped — receives the tapped design map
  /// and the full list. If null, no-op.
  final void Function(List<Map<String, dynamic>> items, int index)? onTapDesign;

  const UnifiedProfileView({
    super.key,
    required this.profileId,
    this.viewedDesignId,
    this.ownerEditable = false,
    this.seedProfile,
    this.seedPool,
    this.onAvatarLongPress,
    this.onEditProfile,
    this.onOpenAiStudio,
    this.onTapDesign,
  });

  @override
  State<UnifiedProfileView> createState() => _UnifiedProfileViewState();
}

class _UnifiedProfileViewState extends State<UnifiedProfileView> {
  KoalaUserProfile? _profile;
  Map<String, dynamic>? _designerRow; // From profiles table (designers)
  List<Map<String, dynamic>> _designs = const [];
  bool _loading = true;

  FollowState _follow = FollowState.empty;
  bool _followBusy = false;
  ({int followers, int following}) _counts = (followers: 0, following: 0);

  DesignerReviewsResult _reviews = DesignerReviewsResult.empty;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  bool get _isSelf => _currentUid != null && _currentUid == widget.profileId;

  Future<void> _loadAll() async {
    final results = await Future.wait([
      _loadProfile(),
      _loadDesigns(),
      FollowService.counts(widget.profileId),
      FollowService.stateFor(widget.profileId),
      DesignerReviewsService.getForDesigner(widget.profileId),
    ], eagerError: false);
    if (!mounted) return;
    setState(() {
      _counts = results[2] as ({int followers, int following});
      _follow = results[3] as FollowState;
      _reviews = results[4] as DesignerReviewsResult;
      _loading = false;
    });
  }

  Future<void> _loadProfile() async {
    // Try koala_user_profiles first; designers also have a row in `profiles`.
    try {
      final ups = await UserProfileService.getMany([widget.profileId]);
      if (ups.isNotEmpty) {
        _profile = ups.first;
      } else {
        _profile = KoalaUserProfile(uid: widget.profileId);
      }
    } catch (_) {
      _profile = KoalaUserProfile(uid: widget.profileId);
    }
    // Designer row (profiles) — best-effort; richer fields than koala_user_profiles.
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select(
              'id, full_name, business_name, avatar_url, profession, specialty, city, bio, about')
          .eq('id', widget.profileId)
          .maybeSingle();
      if (row != null) _designerRow = Map<String, dynamic>.from(row);
    } catch (_) {/* swallow */}

    // Override with seed if provided.
    if (widget.seedProfile != null) {
      _designerRow ??= Map<String, dynamic>.from(widget.seedProfile!);
    }
  }

  Future<void> _loadDesigns() async {
    try {
      if (widget.ownerEditable && _isSelf) {
        // Owner: AI designs (saved_items.project) + shared designs.
        final results = await Future.wait([
          SavedItemsService.getByType(SavedItemType.project, limit: 40),
          SharedDesignService.myShared(limit: 40),
        ]);
        final ai = (results[0] as List<Map<String, dynamic>>)
            .map((m) => {...m, 'is_ai': true})
            .toList();
        final shared = (results[1] as List<SharedDesign>)
            .map((s) => {...s.toMapForProfileTab(), 'is_ai': false})
            .toList();
        _designs = [...shared, ...ai];
      } else {
        // Other user / designer: try EvlumbaLiveService projects.
        if (widget.profileId == 'evlumba-design' && widget.seedPool != null) {
          _designs = List<Map<String, dynamic>>.from(widget.seedPool!);
        } else {
          _designs = await EvlumbaLiveService.getProjects(
            designerId: widget.profileId,
            limit: 30,
          );
        }
      }
    } catch (e) {
      debugPrint('[unified_profile] designs load failed: $e');
      _designs = const [];
    }
  }

  Future<void> _onFollowTap() async {
    if (_followBusy) return;
    HapticFeedback.selectionClick();
    setState(() => _followBusy = true);
    final next = await FollowService.toggle(widget.profileId);
    if (!mounted) return;
    setState(() {
      _follow = next;
      _followBusy = false;
    });
  }

  Future<void> _onReviewSubmit(int rating, String comment) async {
    if (_isSelf) return;
    final ok = await DesignerReviewsService.submit(
      designerId: widget.profileId,
      rating: rating,
      comment: comment.isEmpty ? null : comment,
    );
    if (!mounted) return;
    if (ok) {
      // Optimistic insert.
      final uid = _currentUid ?? '';
      final stub = DesignerReview(
        id: 'local-${DateTime.now().millisecondsSinceEpoch}',
        designerId: widget.profileId,
        reviewerId: uid,
        rating: rating,
        comment: comment.isEmpty ? null : comment,
        createdAt: DateTime.now(),
      );
      final updated = [stub, ..._reviews.reviews];
      final sum = updated.fold<int>(0, (a, r) => a + r.rating);
      setState(() {
        _reviews = DesignerReviewsResult(
          reviews: updated,
          avg: sum / updated.length,
          count: updated.length,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Yorumun alındı, teşekkürler 🙌'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yorum gönderilemedi, tekrar dene.')),
      );
    }
  }

  // ─── Derived fields ───
  String get _name {
    final p = _profile;
    final d = _designerRow;
    final stored = (p?.displayName ?? '').trim();
    if (stored.isNotEmpty) return stored;
    final n =
        ((d?['full_name'] ?? d?['business_name'] ?? '') as String).trim();
    return n.isNotEmpty ? n : 'Profil';
  }

  String get _avatarUrl {
    final fromProfile = (_profile?.avatarUrl ?? '').trim();
    if (fromProfile.isNotEmpty) return fromProfile;
    return ((_designerRow?['avatar_url'] ?? '') as String).trim();
  }

  String get _about {
    final fromProfile = (_profile?.about ?? '').trim();
    if (fromProfile.isNotEmpty) return fromProfile;
    final d = _designerRow;
    return ((d?['bio'] ?? d?['about'] ?? '') as String).trim();
  }

  String get _role {
    final d = _designerRow;
    final prof =
        ((d?['profession'] ?? d?['specialty'] ?? '') as String).trim();
    if (prof.isNotEmpty) return prof;
    if (_profile?.isPro == true) return 'Profesyonel Tasarımcı';
    return 'Koala üyesi';
  }

  String get _city => ((_designerRow?['city'] ?? '') as String).trim();

  bool get _isDesignerOrPro =>
      _designerRow != null || (_profile?.isPro == true);

  bool get _hasAiDesigns =>
      _designs.any((d) => d['is_ai'] == true);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(
              color: KoalaColors.accentDeep, strokeWidth: 2),
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _hero(),
        _stats(),
        _actionsRow(),
        if (_about.isNotEmpty) _aboutSection(),
        if (_reviews.count > 0) _reviewsBlock(),
        if (!_isSelf && _isDesignerOrPro)
          _RateAndCommentBar(onSubmit: _onReviewSubmit),
        if (widget.ownerEditable && _isSelf && _hasAiDesigns) _aiStudioPill(),
        _projectsHeader(),
        _projectsGrid(),
        SizedBox(height: MediaQuery.viewPaddingOf(context).bottom + 32),
      ],
    );
  }

  // ─── Hero — SS5 ─────────────────────────────────────────────────────
  Widget _hero() {
    final isEvlumba = widget.profileId == 'evlumba-design';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            KoalaColors.accentSoft.withValues(alpha: 0.55),
            KoalaColors.bg,
          ],
        ),
      ),
      child: Column(
        children: [
          _avatar(isEvlumba),
          const SizedBox(height: 14),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _name,
                  style: KoalaText.h2,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isVerifiedDesignerId(widget.profileId) ||
                  _profile?.verified == true) ...[
                const SizedBox(width: 6),
                const VerifiedBadge(size: 18),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [_role, if (_city.isNotEmpty) _city]
                .where((s) => s.isNotEmpty)
                .join(' · '),
            style: KoalaText.bodySec,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _avatar(bool isEvlumba) {
    final url = _avatarUrl;
    final hasUrl = url.isNotEmpty;
    final inner = Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isEvlumba
            ? const SweepGradient(
                colors: [
                  KoalaColors.accentDeep,
                  KoalaColors.brandLight,
                  Color(0xFFFFC44C),
                  KoalaColors.accent,
                  KoalaColors.accentDeep,
                ],
              )
            : null,
        color: isEvlumba ? null : Colors.transparent,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: EdgeInsets.all(isEvlumba ? 3 : 0),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hasUrl ? Colors.white : KoalaColors.accentSoft,
        ),
        clipBehavior: Clip.antiAlias,
        child: hasUrl
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, _) =>
                    Container(color: KoalaColors.accentSoft),
                errorWidget: (_, _, _) => const Center(
                    child: Icon(LucideIcons.user,
                        size: 36, color: KoalaColors.accentDeep)),
              )
            : const Center(
                child: Icon(LucideIcons.user,
                    size: 36, color: KoalaColors.accentDeep),
              ),
      ),
    );
    if (widget.onAvatarLongPress == null) return inner;
    return GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
        widget.onAvatarLongPress!();
      },
      child: inner,
    );
  }

  // ─── Stats — 3 columns: Tasarım / Takipçi / Takip ───────────────────
  Widget _stats() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Row(
        children: [
          _stat(label: 'Tasarım', value: '${_designs.length}'),
          _statDiv(),
          _stat(label: 'Takipçi', value: '${_counts.followers}'),
          _statDiv(),
          _stat(label: 'Takip', value: '${_counts.following}'),
        ],
      ),
    );
  }

  Widget _stat({required String label, required String value}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: KoalaColors.text,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: KoalaText.labelSmall),
        ],
      ),
    );
  }

  Widget _statDiv() =>
      Container(width: 1, height: 26, color: KoalaColors.border);

  // ─── Actions row ────────────────────────────────────────────────────
  Widget _actionsRow() {
    if (widget.ownerEditable && _isSelf) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: ElevatedButton(
                  onPressed: widget.onEditProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KoalaColors.accentDeep,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Profili Düzenle',
                    style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    // Other-user view → follow CTA
    final following = _follow.following;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _followBusy ? null : _onFollowTap,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    following ? KoalaColors.surface : KoalaColors.accentDeep,
                foregroundColor:
                    following ? KoalaColors.text : Colors.white,
                disabledBackgroundColor: KoalaColors.surfaceAlt,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: following
                      ? const BorderSide(
                          color: KoalaColors.borderSolid, width: 1)
                      : BorderSide.none,
                ),
                elevation: 0,
              ),
              icon: Icon(
                following ? LucideIcons.check : LucideIcons.userPlus,
                size: 18,
              ),
              label: Text(
                following ? 'Takip ediliyor' : 'Takip et',
                style: KoalaText.button.copyWith(
                  color: following ? KoalaColors.text : Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── About ──────────────────────────────────────────────────────────
  Widget _aboutSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('HAKKINDA', style: KoalaText.caption),
          const SizedBox(height: 6),
          Text(_about, style: KoalaText.body),
        ],
      ),
    );
  }

  // ─── Reviews block (read-only list) ─────────────────────────────────
  Widget _reviewsBlock() {
    final avg = _reviews.avg.toStringAsFixed(1);
    final shown = _reviews.reviews.take(3).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
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
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...shown.map(_reviewCard),
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
                i < r.rating
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
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

  // ─── AI Stüdyom pill (owner only, when AI designs exist) ────────────
  Widget _aiStudioPill() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Material(
        color: KoalaColors.accentSoft,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onOpenAiStudio?.call();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: KoalaColors.accentDeep.withValues(alpha: 0.18),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.sparkles,
                    size: 16, color: KoalaColors.accentDeep),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'AI Stüdyom',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: KoalaColors.accentDeep,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                const Icon(LucideIcons.chevronRight,
                    size: 18, color: KoalaColors.accentDeep),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Projects header & grid ─────────────────────────────────────────
  Widget _projectsHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
      child: Row(
        children: [
          const Text('TASARIMLARI', style: KoalaText.caption),
          const Spacer(),
          if (_designs.isNotEmpty)
            Text('${_designs.length} adet', style: KoalaText.labelSmall),
        ],
      ),
    );
  }

  Widget _projectsGrid() {
    if (_designs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
        child: Center(
          child: Text(
            'Henüz yayınlanmış tasarım yok.',
            style: KoalaText.bodySec,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // If viewedDesignId is non-null, reorder so the viewed design is first.
    List<Map<String, dynamic>> ordered = _designs;
    int viewedIndex = -1;
    if (widget.viewedDesignId != null && widget.viewedDesignId!.isNotEmpty) {
      final idx = _designs.indexWhere((p) {
        final id = (p['id'] ?? p['item_id'] ?? '').toString();
        return id == widget.viewedDesignId;
      });
      if (idx > 0) {
        ordered = List<Map<String, dynamic>>.from(_designs);
        final viewed = ordered.removeAt(idx);
        ordered.insert(0, viewed);
        viewedIndex = 0;
      } else if (idx == 0) {
        viewedIndex = 0;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.78,
        ),
        itemCount: ordered.length,
        itemBuilder: (_, i) {
          final p = ordered[i];
          final cover = _coverOf(p);
          final title = (p['title'] ?? '').toString();
          final isViewed = i == viewedIndex;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onTapDesign?.call(ordered, i);
            },
            behavior: HitTestBehavior.opaque,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (cover.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: cover,
                      fit: BoxFit.cover,
                      memCacheWidth: 400,
                      placeholder: (_, _) =>
                          Container(color: KoalaColors.surfaceAlt),
                      errorWidget: (_, _, _) =>
                          Container(color: KoalaColors.surfaceAlt),
                    )
                  else
                    Container(color: KoalaColors.surfaceAlt),
                  // Standard bottom gradient for title legibility.
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.55),
                          ],
                          stops: const [0.55, 1.0],
                        ),
                      ),
                    ),
                  ),
                  // Subtle "Bunu görüntülediniz" overlay.
                  if (isViewed) ...[
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.30),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.eye,
                                size: 11, color: KoalaColors.accentDeep),
                            SizedBox(width: 4),
                            Text(
                              'Bunu görüntülediniz',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: KoalaColors.accentDeep,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (title.isNotEmpty)
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
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
}

// ═══════════════════════════════════════════════════════════════════════
// RateAndCommentBar — elegant inline review input.
// 5 interactive stars (40px tap targets, animated tap) + single-line
// TextField that expands on focus + small "Gönder" pill below.
// ═══════════════════════════════════════════════════════════════════════
class _RateAndCommentBar extends StatefulWidget {
  final Future<void> Function(int rating, String comment) onSubmit;
  const _RateAndCommentBar({required this.onSubmit});

  @override
  State<_RateAndCommentBar> createState() => _RateAndCommentBarState();
}

class _RateAndCommentBarState extends State<_RateAndCommentBar> {
  int _rating = 0;
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _focused = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() => _focused = _focus.hasFocus);
    });
    _ctrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting && _rating > 0 && _ctrl.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    HapticFeedback.lightImpact();
    await widget.onSubmit(_rating, _ctrl.text.trim());
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _rating = 0;
      _ctrl.clear();
      _focused = false;
    });
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: KoalaColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: KoalaColors.borderSolid, width: 0.6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bu profil için bir yorum bırak',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: KoalaColors.textSec,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: List.generate(5, (i) {
                final idx = i + 1;
                final filled = idx <= _rating;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _rating = idx);
                  },
                  child: AnimatedScale(
                    scale: filled ? 1.0 : 0.94,
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      child: Icon(
                        filled
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 28,
                        color: filled
                            ? const Color(0xFFEFA01F)
                            : KoalaColors.border,
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                maxLines: _focused ? 4 : 1,
                minLines: 1,
                style: const TextStyle(fontSize: 14, color: KoalaColors.text),
                decoration: InputDecoration(
                  hintText: 'Bir şeyler yaz...',
                  hintStyle: const TextStyle(
                    fontSize: 14,
                    color: KoalaColors.textTer,
                  ),
                  filled: true,
                  fillColor: KoalaColors.surfaceAlt,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Material(
                color: _canSubmit
                    ? KoalaColors.accentDeep
                    : KoalaColors.surfaceAlt,
                borderRadius: BorderRadius.circular(99),
                child: InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: _canSubmit ? _submit : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 9),
                    child: Text(
                      _submitting ? 'Gönderiliyor…' : 'Gönder',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _canSubmit
                            ? Colors.white
                            : KoalaColors.textTer,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Suppress unused import warning when ProfileDesignTile isn't needed yet —
// kept imported for future extension (consistent profile design tile look).
// ignore: unused_element
void _keep() => ProfileDesignTile;
