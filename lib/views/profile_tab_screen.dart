// Profil sekmesi — Medium/Instagram/LinkedIn benchmark.
// Hero: avatar + isim + (rating?) + bio + stats (Tasarım / Takipçi / Takip)
//       + (eğer hem pro hem ev sahibi) role-switch + (pro değilse) "Profesyonel ol" CTA.
// Bu sayfada AYAR satırı YOK. Ayarlar yalnız avatar long-press ile.
// Tap design → swipe-detail (PageView). Long-press tile → action sheet.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, FileOptions;

import '../core/theme/koala_tokens.dart';
import '../services/designer_reviews_service.dart';
import '../services/follow_service.dart';
import '../services/saved_items_service.dart';
import '../services/shared_design_service.dart';
import '../services/user_profile_service.dart';
import '../widgets/ask_and_apply_sheet.dart';
import '../widgets/verified_badge.dart';
import 'mekan/wizard/mekan_wizard_screen.dart';
import 'profile/follow_list_sheet.dart';
import 'profile/pro_application_sheet.dart';
import 'profile/profile_design_tile.dart';
import 'profile/profile_photo_view.dart';
import 'profile/unified_profile_view.dart';
import 'profile/user_design_swipe.dart';
import 'projeler_screen.dart';

// Re-export for back-compat: `profile_screen.dart` ve diğer callerlar
// `showProApplicationSheet`'i bu dosyadan import ediyor.
export 'profile/pro_application_sheet.dart' show showProApplicationSheet;

// Persisted role choice key.
const _kRoleSwitchPrefKey = 'profile_role_view'; // 'homeowner' | 'pro'

class ProfileTabScreen extends ConsumerStatefulWidget {
  const ProfileTabScreen({super.key});

  @override
  ConsumerState<ProfileTabScreen> createState() => _ProfileTabScreenState();
}

class _ProfileTabScreenState extends ConsumerState<ProfileTabScreen>
    with SingleTickerProviderStateMixin {
  // AI tasarımları (saved_items type='project') — kullanıcının kendi üretimi.
  List<Map<String, dynamic>> _aiDesigns = const [];
  // Paylaştıkları — kullanıcı yüklemeleri. Ayrı tablo yok, şimdilik boş.
  List<Map<String, dynamic>> _sharedDesigns = const [];
  bool _designsLoading = true;
  bool _uploadingAvatar = false;

  int _followers = 0;
  int _following = 0;

  /// 'homeowner' (varsayılan) ya da 'pro'. Kullanıcı hem pro hem ev sahibiyse
  /// switch ile değiştirebilir, son seçim persist.
  String _viewRole = 'homeowner';

  late final TabController _designsTab;

  // Reviews (yalnız pro/designer için doldurulur).
  DesignerReviewsResult _reviews = DesignerReviewsResult.empty;

  @override
  void initState() {
    super.initState();
    _designsTab = TabController(length: 2, vsync: this);
    _designsTab.addListener(() {
      if (mounted) setState(() {});
    });
    _restoreRole();
    _loadDesigns();
    _loadCounts();
    _loadReviews();
  }

  @override
  void dispose() {
    _designsTab.dispose();
    super.dispose();
  }

  Future<void> _restoreRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final r = prefs.getString(_kRoleSwitchPrefKey);
      if (r != null && mounted) {
        setState(() => _viewRole = r);
      }
    } catch (_) {/* swallow */}
  }

  Future<void> _saveRole(String role) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRoleSwitchPrefKey, role);
    } catch (_) {/* swallow */}
  }

  Future<void> _loadDesigns() async {
    try {
      final results = await Future.wait([
        SavedItemsService.getByType(SavedItemType.project, limit: 40),
        SharedDesignService.myShared(limit: 40),
      ]);
      if (!mounted) return;
      final ai = (results[0] as List<Map<String, dynamic>>)
          .map((m) => {...m, 'is_ai': true})
          .toList();
      final shared = (results[1] as List<SharedDesign>)
          .map((s) => {
                ...s.toMapForProfileTab(),
                'is_ai': false,
              })
          .toList();
      setState(() {
        _aiDesigns = ai;
        _sharedDesigns = shared;
        _designsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _designsLoading = false);
    }
  }

  Future<void> _loadReviews() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final r = await DesignerReviewsService.getForDesigner(uid);
    if (!mounted) return;
    setState(() => _reviews = r);
  }

  /// Birleşik tasarımlar (AI + paylaşımlar) — fullscreen swipe için.
  List<Map<String, dynamic>> get _allDesigns => [..._aiDesigns, ..._sharedDesigns];

  Future<void> _loadCounts() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final c = await FollowService.counts(uid);
    if (!mounted) return;
    setState(() {
      _followers = c.followers;
      _following = c.following;
    });
  }

  Future<void> _refreshAll() async {
    ref.invalidate(userProfileProvider);
    await Future.wait([_loadDesigns(), _loadCounts(), _loadReviews()]);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final bundle = ref.watch(userProfileProvider).asData?.value;
    final profile = bundle?.profile;
    final application = bundle?.application;
    final stored = profile?.displayName?.trim();
    final displayName = (stored?.isNotEmpty == true
            ? stored
            : (user?.displayName ?? '').trim()) ??
        '';
    final email = user?.email ?? '';
    final name = displayName.isNotEmpty
        ? displayName
        : (email.isNotEmpty ? email.split('@').first : 'Profil');
    final photo = (user?.photoURL?.isNotEmpty == true)
        ? user!.photoURL
        : profile?.avatarUrl;
    final verified = profile?.verified == true;
    final about = (profile?.about ?? '').trim();
    final isPro = profile?.isPro == true;
    final canSwitch = isPro; // pro user can toggle "Ev Sahibi / Profesyonel"
    final effectiveRole = canSwitch ? _viewRole : 'homeowner';
    final roleLabel = isPro
        ? (effectiveRole == 'pro'
            ? (about.isNotEmpty ? 'Profesyonel Tasarımcı' : 'Koala Pro')
            : 'Ev Sahibi')
        : 'Ev Sahibi';

    final memberSince = user?.metadata.creationTime;

    // 2026-05-27: Tüm profil görüntülemeleri (own + others) UnifiedProfileView
    // üzerinden — SS5 görsel pattern'i. Avatar long-press settings'e gitmek
    // için top-right icon button olarak korunuyor.
    final uid = user?.uid ?? '';
    if (uid.isEmpty) {
      return const Scaffold(
        backgroundColor: KoalaColors.bg,
        body: Center(
          child: CircularProgressIndicator(
              color: KoalaColors.accentDeep, strokeWidth: 2),
        ),
      );
    }
    // Reference legacy fields to keep the analyzer quiet — these state
    // helpers stay alive for potential future reuse (settings hook etc.).
    // ignore: unused_local_variable
    final _legacy = (name, photo, verified, about, isPro, application,
        memberSince, canSwitch, effectiveRole, roleLabel);
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        color: KoalaColors.accent,
        child: SafeArea(
          bottom: false,
          child: UnifiedProfileView(
            profileId: uid,
            ownerEditable: true,
            viewedDesignId: null,
            onAvatarLongPress: () => context.push('/profile'),
            onEditProfile: _openEditor,
            onOpenAiStudio: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ProjelerScreen(),
                ),
              );
            },
            onTapDesign: (items, index) {
              HapticFeedback.selectionClick();
              UserDesignSwipeScreen.open(
                context,
                items: items,
                ownerUid: uid,
                initialIndex: index,
              );
            },
          ),
        ),
      ),
    );
  }

  // ─── Edit + Share row (50/50) — primary purple edit, outlined share ───
  Widget _editAndShareRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: _openEditor,
                style: ElevatedButton.styleFrom(
                  backgroundColor: KoalaColors.accentDeep,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  'Profili Düzenle',
                  style:
                      TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: _shareOwnProfile,
                style: OutlinedButton.styleFrom(
                  foregroundColor: KoalaColors.text,
                  side: const BorderSide(
                      color: KoalaColors.borderSolid, width: 1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  'Paylaş',
                  style:
                      TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareOwnProfile() async {
    HapticFeedback.selectionClick();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final url = 'https://koalatutor.com/u/$uid';
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profil bağlantın kopyalandı'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ─── Reviews block ("Yorumlar (avg/5)" + up to 3 cards + "Tümünü gör") ───
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
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...shown.map(_reviewCard),
          if (_reviews.count > 3)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _openAllReviews,
                child: const Text('Tümünü gör'),
              ),
            ),
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

  void _openAllReviews() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KoalaColors.bg,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: _dragHandle()),
              const SizedBox(height: 14),
              const Text('Tüm Yorumlar', style: KoalaText.h2),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: _reviews.reviews.map(_reviewCard).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Compact "Profesyonel profilini aç" CTA (soft purple-tinted, 60h) ──
  Widget _proCtaCompact() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: KoalaColors.accentSoft,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            HapticFeedback.selectionClick();
            final submitted = await showProApplicationSheet(context);
            if (submitted == true) ref.invalidate(userProfileProvider);
          },
          child: Container(
            height: 60,
            padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: KoalaColors.accentDeep.withValues(alpha: 0.18),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KoalaColors.accentDeep.withValues(alpha: 0.14),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(LucideIcons.star,
                      color: KoalaColors.accentDeep, size: 16),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Profesyonel profilini aç',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: KoalaColors.accentDeep,
                          letterSpacing: -0.1,
                        ),
                      ),
                      SizedBox(height: 1),
                      Text(
                        'Tasarımlarını paylaş, müşterilerle eşleş',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: KoalaColors.textSec,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(LucideIcons.chevronRight,
                    color: KoalaColors.accentDeep, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── 2 tab — underline ───
  Widget _tabBar() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: KoalaColors.borderSolid, width: 0.6),
          bottom: BorderSide(color: KoalaColors.borderSolid, width: 0.6),
        ),
      ),
      child: TabBar(
        controller: _designsTab,
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorWeight: 1.6,
        indicatorColor: KoalaColors.text,
        dividerHeight: 0,
        labelColor: KoalaColors.text,
        unselectedLabelColor: KoalaColors.textTer,
        labelStyle: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.1,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
        tabs: [
          Tab(
            height: 42,
            iconMargin: EdgeInsets.zero,
            icon: Semantics(
              label: 'Paylaşımlar',
              button: true,
              child: const Icon(LucideIcons.layoutGrid, size: 18),
            ),
          ),
          Tab(
            height: 42,
            iconMargin: EdgeInsets.zero,
            icon: Semantics(
              label: 'AI Tasarımları',
              button: true,
              child: const Icon(LucideIcons.sparkles, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _designsTabBody() {
    if (_designsLoading) {
      return const SizedBox(
        height: 220,
        child: Center(
          child: CircularProgressIndicator(
              color: KoalaColors.accentDeep, strokeWidth: 2),
        ),
      );
    }
    final isAllTab = _designsTab.index == 0;
    final items = isAllTab ? _allDesigns : _aiDesigns;
    if (items.isEmpty) {
      return isAllTab ? _emptyAll() : _emptyAi();
    }
    return _designsGrid(items);
  }

  Widget _designsGrid(List<Map<String, dynamic>> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        childAspectRatio: 1.0,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        final isAi = item['is_ai'] == true;
        return ProfileDesignTile(
          item: item,
          isAi: isAi,
          onTap: () => _openSwipeDetail(items, i),
          onApply: () => _applyDesign(item),
          onAsk: () => _askAboutDesign(item),
          onEdit: () => _openEditDesignSheet(item, isAi: isAi),
          onDelete: () => _confirmDeleteDesign(item, isAi: isAi),
        );
      },
    );
  }

  void _openSwipeDetail(List<Map<String, dynamic>> items, int index) {
    HapticFeedback.selectionClick();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    UserDesignSwipeScreen.open(
      context,
      items: items,
      ownerUid: uid,
      initialIndex: index,
    );
  }

  Future<void> _applyDesign(Map<String, dynamic> item) async {
    HapticFeedback.selectionClick();
    // "Sor ve Uygula" sheet'i hem "tasarımcıya sor" hem "mekânıma uygula"
    // seçeneklerini sunar — Uygula CTA buraya bağlanır.
    await _openAskAndApply(item);
  }

  Future<void> _askAboutDesign(Map<String, dynamic> item) async {
    HapticFeedback.selectionClick();
    await _openAskAndApply(item);
  }

  Future<void> _openAskAndApply(Map<String, dynamic> item) async {
    final id = (item['item_id'] ?? item['id'] ?? '').toString();
    final title = (item['title'] ?? 'Tasarım').toString();
    final imageUrl = (item['image_url'] ?? '').toString();
    final subtitle = (item['subtitle'] ?? '').toString();
    final extra = item['extra_data'];
    String? designerId;
    String? designerName;
    String? designerAvatarUrl;
    String? category;
    if (extra is Map) {
      designerId = (extra['designer_id'] ?? '').toString();
      if (designerId.isEmpty) designerId = null;
      designerName = (extra['designer_name'] ?? '').toString();
      if (designerName.isEmpty) designerName = null;
      designerAvatarUrl = (extra['designer_avatar_url'] ?? '').toString();
      if (designerAvatarUrl.isEmpty) designerAvatarUrl = null;
      category = (extra['category'] ?? extra['style_tr'] ?? '').toString();
      if (category.isEmpty) category = null;
    }
    await showAskAndApplySheet(
      context,
      designId: id,
      title: title,
      imageUrl: imageUrl,
      subtitle: subtitle.isNotEmpty ? subtitle : null,
      designerId: designerId,
      designerName: designerName,
      designerAvatarUrl: designerAvatarUrl,
      category: category,
      isOwnDesign: true,
    );
  }

  Future<void> _openFollowList(FollowListMode mode) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    HapticFeedback.selectionClick();
    await FollowListSheet.open(context, ownerUid: uid, mode: mode);
    // refresh counts in case user toggled follows from within
    _loadCounts();
  }

  Widget _emptyAll() {
    return _emptyState(
      icon: LucideIcons.layoutGrid,
      title: 'Henüz paylaşımın yok',
      subtitle:
          'Bir mekânının fotoğrafını çek veya yükle — AI üretimlerin ve paylaşımların burada görünür.',
      cta: 'İlk tasarımını paylaş',
      ctaIcon: LucideIcons.plus,
      onTap: _openShareUpload,
    );
  }

  Widget _emptyAi() {
    return _emptyState(
      icon: LucideIcons.sparkles,
      title: 'Henüz AI tasarımı yok',
      subtitle: 'Bir mekânını çek, Koala farklı tarzları sana göstersin.',
      cta: 'İlk tasarımını oluştur',
      ctaIcon: LucideIcons.camera,
      onTap: () => context.go('/'),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required String cta,
    required IconData ctaIcon,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: KoalaColors.accentSoft,
            ),
            child: Icon(icon, color: KoalaColors.accentDeep, size: 24),
          ),
          const SizedBox(height: 12),
          Text(title, style: KoalaText.h4, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(subtitle,
              style: KoalaText.bodySmall, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: KoalaColors.text,
              side: const BorderSide(color: KoalaColors.border, width: 1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(100),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            icon: Icon(ctaIcon, size: 16, color: KoalaColors.textSec),
            label: Text(
              cta,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openShareUpload() async {
    HapticFeedback.selectionClick();
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
            const SizedBox(height: 8),
            _dragHandle(),
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
    if (source == null || !mounted) return;
    try {
      final picker = ImagePicker();
      final f = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        imageQuality: 60,
      );
      if (f == null || !mounted) return;
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MekanWizardScreen(photoBytes: bytes),
        ),
      );
    } catch (_) {/* swallow */}
  }

  Future<void> _openEditDesignSheet(
    Map<String, dynamic> item, {
    required bool isAi,
  }) async {
    final type = isAi ? SavedItemType.project : SavedItemType.design;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: KoalaColors.bg,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _DesignEditSheet(item: item, type: type),
    );
    if (changed == true && mounted) _loadDesigns();
  }

  Future<void> _confirmDeleteDesign(
    Map<String, dynamic> item, {
    required bool isAi,
  }) async {
    final type = isAi ? SavedItemType.project : SavedItemType.design;
    final itemId = (item['item_id'] ?? '').toString();
    if (itemId.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tasarımı sil'),
        content: const Text('Tasarımı silmek istediğine emin misin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: KoalaColors.error),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      if (isAi) {
        _aiDesigns = _aiDesigns
            .where((r) => (r['item_id'] ?? '').toString() != itemId)
            .toList();
      } else {
        _sharedDesigns = _sharedDesigns
            .where((r) => (r['item_id'] ?? '').toString() != itemId)
            .toList();
      }
    });
    final success = await SavedItemsService.removeItem(
      type: type,
      itemId: itemId,
    );
    if (!mounted) return;
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silinemedi, tekrar dene.')),
      );
      _loadDesigns();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tasarım silindi.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ─── Profil fotoğrafı: tap → kaynak sheet → upload/remove + view ───
  Future<void> _openAvatarActions(String? currentUrl) async {
    if (_uploadingAvatar) return;
    final hasPhoto = (currentUrl ?? '').isNotEmpty;
    final action = await showModalBottomSheet<String>(
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
            const SizedBox(height: 8),
            _dragHandle(),
            const SizedBox(height: 8),
            if (hasPhoto)
              ListTile(
                leading: const Icon(LucideIcons.expand,
                    color: KoalaColors.accentDeep),
                title: const Text('Fotoğrafı göster',
                    style: KoalaText.bodyMedium),
                onTap: () => Navigator.pop(ctx, 'view'),
              ),
            if (!kIsWeb)
              ListTile(
                leading: const Icon(LucideIcons.camera,
                    color: KoalaColors.accentDeep),
                title:
                    const Text('Fotoğraf çek', style: KoalaText.bodyMedium),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
            ListTile(
              leading: const Icon(LucideIcons.image,
                  color: KoalaColors.accentDeep),
              title:
                  const Text('Galeriden seç', style: KoalaText.bodyMedium),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(LucideIcons.trash2,
                    color: KoalaColors.error),
                title: const Text(
                  'Mevcut fotoğrafı kaldır',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: KoalaColors.error,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            ListTile(
              leading:
                  const Icon(LucideIcons.x, color: KoalaColors.textSec),
              title: const Text('İptal', style: KoalaText.bodyMedium),
              onTap: () => Navigator.pop(ctx),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'view':
        if (hasPhoto) {
          await ProfilePhotoView.open(
            context,
            url: currentUrl!,
            heroTag: profilePhotoHeroTag(
                FirebaseAuth.instance.currentUser?.uid ?? 'me'),
          );
        }
        break;
      case 'camera':
        await _pickAndUploadAvatar(ImageSource.camera);
        break;
      case 'gallery':
        await _pickAndUploadAvatar(ImageSource.gallery);
        break;
      case 'remove':
        await _confirmRemoveAvatar();
        break;
    }
  }

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 720,
        imageQuality: 80,
      );
      if (picked == null || !mounted) return;

      setState(() => _uploadingAvatar = true);

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('not_authenticated');

      final Uint8List bytes = await picked.readAsBytes();
      final objectPath = '$uid/avatar.webp';
      final storage = Supabase.instance.client.storage.from('avatars');
      await storage.uploadBinary(
        objectPath,
        bytes,
        fileOptions: const FileOptions(
          upsert: true,
          contentType: 'image/webp',
        ),
      );
      final basePublic = storage.getPublicUrl(objectPath);
      final v = DateTime.now().millisecondsSinceEpoch;
      final publicUrl = '$basePublic?v=$v';

      await Future.wait([
        FirebaseAuth.instance.currentUser!.updatePhotoURL(publicUrl),
        UserProfileService.setAvatarUrl(publicUrl).then((ok) {
          if (!ok) debugPrint('[avatar] supabase setAvatarUrl returned false');
        }),
      ]);

      if (!mounted) return;
      ref.invalidate(userProfileProvider);
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profil fotoğrafın güncellendi'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('[avatar] upload failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fotoğraf yüklenemedi'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _confirmRemoveAvatar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fotoğrafı kaldır'),
        content:
            const Text('Profil fotoğrafını kaldırmak istediğine emin misin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: KoalaColors.error),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _uploadingAvatar = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        try {
          await Supabase.instance.client.storage
              .from('avatars')
              .remove(['$uid/avatar.webp']);
        } catch (_) {/* swallow */}
      }
      await Future.wait([
        FirebaseAuth.instance.currentUser!.updatePhotoURL(null),
        UserProfileService.setAvatarUrl(null),
      ]);
      if (!mounted) return;
      ref.invalidate(userProfileProvider);
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profil fotoğrafı kaldırıldı.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('[avatar] remove failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fotoğraf kaldırılamadı')),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _openEditor() async {
    HapticFeedback.selectionClick();
    final bundle = ref.read(userProfileProvider).asData?.value;
    final profile = bundle?.profile;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: KoalaColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ProfileEditorSheet(initial: profile),
    );
    if (changed == true) ref.invalidate(userProfileProvider);
  }
}

// ─── Hero widget — SS3 layout: white card with avatar LEFT + name/role/
// member-date stacked RIGHT. About paragraph sits inside the same card.
class _Hero extends StatelessWidget {
  final String uid;
  final String name;
  final String role;
  final String? photo;
  final bool verified;
  final bool isPro;
  final DateTime? memberSince;
  final String about;
  final bool uploading;
  final VoidCallback onAvatarTap;
  final VoidCallback onAvatarLongPress;
  const _Hero({
    required this.uid,
    required this.name,
    required this.role,
    required this.photo,
    required this.verified,
    required this.isPro,
    required this.memberSince,
    required this.about,
    required this.uploading,
    required this.onAvatarTap,
    required this.onAvatarLongPress,
  });

  static const List<String> _trMonths = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
  ];

  String? _formatMember() {
    if (memberSince == null) return null;
    final m = _trMonths[(memberSince!.month - 1).clamp(0, 11)];
    return "$m ${memberSince!.year}'ten beri üye";
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final hasUrl = (photo ?? '').isNotEmpty;
    final tag = profilePhotoHeroTag(uid.isEmpty ? 'me' : uid);
    final showBrandRing = verified || isPro;
    final memberLine = _formatMember();

    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPad + 14, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onAvatarTap();
                  },
                  onLongPress: () {
                    HapticFeedback.mediumImpact();
                    onAvatarLongPress();
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Hero(
                        tag: tag,
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hasUrl
                                ? Colors.white
                                : KoalaColors.accentSoft,
                            border: Border.all(
                              color: showBrandRing
                                  ? KoalaColors.accentDeep
                                  : KoalaColors.borderSolid,
                              width: showBrandRing ? 1.5 : 0.6,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: hasUrl
                              ? CachedNetworkImage(
                                  imageUrl: photo!, fit: BoxFit.cover)
                              : const Icon(LucideIcons.user,
                                  size: 42, color: KoalaColors.accentDeep),
                        ),
                      ),
                      if (uploading)
                        Positioned.fill(
                          child: ClipOval(
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.35),
                              alignment: Alignment.center,
                              child: const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.4),
                              ),
                            ),
                          ),
                        )
                      else if (!verified && !hasUrl)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: KoalaColors.accentDeep,
                              border: Border.all(
                                  color: KoalaColors.surface, width: 2),
                            ),
                            child: const Icon(LucideIcons.camera,
                                size: 13, color: Colors.white),
                          ),
                        ),
                      if (verified)
                        const Positioned(
                          right: -2,
                          bottom: -2,
                          child: VerifiedBadge(size: 22),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: KoalaText.h2.copyWith(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                height: 1.1,
                              ),
                            ),
                          ),
                          if (verified) ...[
                            const SizedBox(width: 6),
                            const Icon(LucideIcons.badgeCheck,
                                size: 16, color: KoalaColors.accentDeep),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isPro
                              ? KoalaColors.accentSoft
                              : KoalaColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          role,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: isPro
                                ? KoalaColors.accentDeep
                                : KoalaColors.textSec,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                      if (memberLine != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(LucideIcons.calendar,
                                size: 12, color: KoalaColors.textTer),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                memberLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: KoalaColors.textTer,
                                  letterSpacing: -0.05,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (about.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                about,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: KoalaColors.text,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Stats row — 3 columns, taps open follow lists ───
class _StatsRow extends StatelessWidget {
  final int designs;
  final int followers;
  final int following;
  final VoidCallback onFollowers;
  final VoidCallback onFollowing;
  const _StatsRow({
    required this.designs,
    required this.followers,
    required this.following,
    required this.onFollowers,
    required this.onFollowing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(child: _stat(designs, 'Tasarım', null)),
          Expanded(child: _stat(followers, 'Takipçi', onFollowers)),
          Expanded(child: _stat(following, 'Takip', onFollowing)),
        ],
      ),
    );
  }

  Widget _stat(int n, String label, VoidCallback? onTap) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          n.toString(),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: KoalaColors.text,
            letterSpacing: -0.3,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: KoalaColors.textSec,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
    if (onTap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: content,
      );
    }
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: content,
      ),
    );
  }
}

// ─── Pro/Homeowner role switch — segmented pill ───
class _RoleSwitch extends StatelessWidget {
  final String selected; // 'homeowner' | 'pro'
  final ValueChanged<String> onSelect;
  const _RoleSwitch({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 38,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: KoalaColors.surfaceAlt,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          children: [
            _seg(
              label: 'Ev Sahibi',
              selected: selected == 'homeowner',
              onTap: () => onSelect('homeowner'),
            ),
            _seg(
              label: 'Profesyonel',
              selected: selected == 'pro',
              onTap: () => onSelect('pro'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seg(
      {required String label,
      required bool selected,
      required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : const [],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? KoalaColors.text : KoalaColors.textSec,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }
}

Widget _dragHandle() => Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: KoalaColors.border,
        borderRadius: BorderRadius.circular(100),
      ),
    );

// ─── Profil editor sheet ───
class _ProfileEditorSheet extends StatefulWidget {
  final KoalaUserProfile? initial;
  const _ProfileEditorSheet({this.initial});
  @override
  State<_ProfileEditorSheet> createState() => _ProfileEditorSheetState();
}

class _ProfileEditorSheetState extends State<_ProfileEditorSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _aboutCtrl;
  late final TextEditingController _igCtrl;
  late final TextEditingController _webCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    final c = p?.contact ?? const {};
    _nameCtrl = TextEditingController(text: p?.displayName ?? '');
    _aboutCtrl = TextEditingController(text: p?.about ?? '');
    _igCtrl = TextEditingController(text: (c['instagram'] ?? '').toString());
    _webCtrl = TextEditingController(text: (c['website'] ?? '').toString());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _aboutCtrl.dispose();
    _igCtrl.dispose();
    _webCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final name = _nameCtrl.text.trim();
    final about = _aboutCtrl.text.trim();
    final contact = {
      if (_igCtrl.text.trim().isNotEmpty) 'instagram': _igCtrl.text.trim(),
      if (_webCtrl.text.trim().isNotEmpty) 'website': _webCtrl.text.trim(),
    };
    debugPrint(
        '[profile_editor] save uid=${FirebaseAuth.instance.currentUser?.uid} '
        'name_len=${name.length} about_len=${about.length} '
        'contact_keys=${contact.keys.toList()}');
    final ok = await UserProfileService.upsert(
      displayName: name,
      about: about,
      contact: contact,
    );
    if (!mounted) return;
    if (!ok) {
      debugPrint('[profile_editor] upsert returned false');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaydedilemedi, tekrar dene.')),
      );
      setState(() => _saving = false);
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
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: _dragHandle()),
              const SizedBox(height: 14),
              const Text('Profilini düzenle', style: KoalaText.h2),
              const SizedBox(height: 18),
              _field(_nameCtrl, label: 'Görünen ad', hint: 'Adın ya da rumuzun'),
              const SizedBox(height: 12),
              _field(
                _aboutCtrl,
                label: 'Hakkında',
                hint: 'Tarzın, ilgi alanların, evin için bir iki cümle',
                maxLines: 4,
              ),
              const SizedBox(height: 12),
              _field(_igCtrl,
                  label: 'Instagram', hint: '@kullaniciadi veya link'),
              const SizedBox(height: 12),
              _field(_webCtrl, label: 'Web', hint: 'https://...'),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KoalaColors.accentDeep,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(_saving ? 'Kaydediliyor…' : 'Kaydet',
                      style: KoalaText.button),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c,
      {required String label, String? hint, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(label, style: KoalaText.caption),
        ),
        TextField(
          controller: c,
          maxLines: maxLines,
          style: KoalaText.body,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: KoalaText.hint,
            filled: true,
            fillColor: KoalaColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: KoalaColors.borderSolid, width: 0.8),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: KoalaColors.borderSolid, width: 0.8),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: KoalaColors.accentDeep, width: 1.2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}

// ─── Tasarım düzenle sheet ───
const List<({String key, String label})> _kRoomOptions = [
  (key: '', label: 'Belirtme'),
  (key: 'Oturma Odası', label: 'Oturma Odası'),
  (key: 'Yatak Odası', label: 'Yatak Odası'),
  (key: 'Mutfak', label: 'Mutfak'),
  (key: 'Banyo', label: 'Banyo'),
  (key: 'Antre', label: 'Antre'),
];

class _DesignEditSheet extends StatefulWidget {
  final Map<String, dynamic> item;
  final SavedItemType type;
  const _DesignEditSheet({required this.item, required this.type});

  @override
  State<_DesignEditSheet> createState() => _DesignEditSheetState();
}

class _DesignEditSheetState extends State<_DesignEditSheet> {
  late final TextEditingController _title;
  late final TextEditingController _desc;
  String _room = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(
        text: (widget.item['title'] ?? '').toString());
    _desc = TextEditingController(
        text: (widget.item['subtitle'] ?? '').toString());
    final extra = widget.item['extra_data'];
    if (extra is Map) {
      _room = (extra['style_tr'] ?? extra['style'] ?? '').toString();
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final itemId = (widget.item['item_id'] ?? '').toString();
    Map<String, dynamic> extra = {};
    final cur = widget.item['extra_data'];
    if (cur is Map) extra = Map<String, dynamic>.from(cur);
    if (_room.isNotEmpty) {
      extra['style_tr'] = _room;
    } else {
      extra.remove('style_tr');
    }
    final ok = await SavedItemsService.updateItem(
      type: widget.type,
      itemId: itemId,
      title: _title.text.trim(),
      subtitle: _desc.text.trim(),
      extraData: extra,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaydedilemedi, tekrar dene.')),
      );
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
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: _dragHandle()),
              const SizedBox(height: 20),
              const Text('Tasarımı düzenle', style: KoalaText.h2),
              const SizedBox(height: 18),
              _label('Başlık'),
              _textField(_title, hint: 'ör. Salonum'),
              const SizedBox(height: 14),
              _label('Açıklama'),
              _textField(_desc,
                  hint: 'Birkaç cümle (opsiyonel)', maxLines: 3),
              const SizedBox(height: 14),
              _label('Oda tipi'),
              DropdownButtonFormField<String>(
                initialValue: _room,
                decoration: InputDecoration(
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
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 4),
                ),
                items: _kRoomOptions
                    .map((o) => DropdownMenuItem(
                          value: o.key,
                          child: Text(o.label, style: KoalaText.body),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _room = v ?? ''),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KoalaColors.accentDeep,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(_saving ? 'Kaydediliyor…' : 'Kaydet',
                      style: KoalaText.button),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(s, style: KoalaText.caption),
      );

  Widget _textField(TextEditingController c,
      {String? hint, int maxLines = 1}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      style: KoalaText.body,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: KoalaText.hint,
        filled: true,
        fillColor: KoalaColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: KoalaColors.borderSolid, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: KoalaColors.borderSolid, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: KoalaColors.accentDeep, width: 1.2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}
