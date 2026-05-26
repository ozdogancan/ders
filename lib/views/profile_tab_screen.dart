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
import '../services/evlumba_live_service.dart';
import '../services/follow_service.dart';
import '../services/saved_items_service.dart';
import '../services/user_profile_service.dart';
import '../widgets/ask_and_apply_sheet.dart';
import '../widgets/verified_badge.dart';
import 'mekan/wizard/mekan_wizard_screen.dart';
import 'profile/follow_list_sheet.dart';
import 'profile/profile_design_swipe.dart';
import 'profile/profile_design_tile.dart';
import 'profile/profile_photo_view.dart';

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
      final ai = await SavedItemsService.getByType(
        SavedItemType.project,
        limit: 40,
      );
      if (!mounted) return;
      setState(() {
        _aiDesigns = ai;
        _sharedDesigns = const [];
        _designsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _designsLoading = false);
    }
  }

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
    await Future.wait([_loadDesigns(), _loadCounts()]);
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

    return Scaffold(
      backgroundColor: KoalaColors.bg,
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        color: KoalaColors.accent,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(
              child: _Hero(
                uid: user?.uid ?? '',
                name: name,
                role: roleLabel,
                photo: photo,
                verified: verified,
                isPro: isPro,
                uploading: _uploadingAvatar,
                onAvatarTap: () => _openAvatarActions(photo),
                onAvatarLongPress: () => context.push('/profile'),
              ),
            ),
            SliverToBoxAdapter(
              child: _StatsRow(
                designs: _designsLoading
                    ? 0
                    : (_aiDesigns.length + _sharedDesigns.length),
                followers: _followers,
                following: _following,
                onFollowers: () => _openFollowList(FollowListMode.followers),
                onFollowing: () => _openFollowList(FollowListMode.following),
              ),
            ),
            if (canSwitch) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              SliverToBoxAdapter(
                child: _RoleSwitch(
                  selected: effectiveRole,
                  onSelect: (r) {
                    setState(() => _viewRole = r);
                    _saveRole(r);
                    HapticFeedback.selectionClick();
                  },
                ),
              ),
            ],
            if (about.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              SliverToBoxAdapter(child: _AboutSection(about: about)),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 18)),
            SliverToBoxAdapter(child: _editButton()),
            if (!isPro &&
                application?.isPending != true &&
                application?.isApproved != true) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 14)),
              SliverToBoxAdapter(child: _proCta()),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 22)),
            SliverToBoxAdapter(child: _tabBar()),
            SliverToBoxAdapter(child: _designsTabBody()),
            // Bottom safe area for nav bar/FAB — generous whitespace.
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.viewPaddingOf(context).bottom + 96,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Edit button ───
  Widget _editButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        child: Material(
          color: KoalaColors.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: _openEditor,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: KoalaColors.borderSolid, width: 0.8),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Profili düzenle',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: KoalaColors.text,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── "Profesyonel ol" gradient CTA (only when not pro & no pending app) ───
  Widget _proCta() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            HapticFeedback.selectionClick();
            final submitted = await showProApplicationSheet(context);
            if (submitted == true) ref.invalidate(userProfileProvider);
          },
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [KoalaColors.accentDeep, KoalaColors.accent],
              ),
              boxShadow: [
                BoxShadow(
                  color: KoalaColors.accentDeep.withValues(alpha: 0.22),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                    child: const Icon(LucideIcons.badgeCheck,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Profesyonel ol',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Tasarımlarını paylaş, müşterilerle eşleş.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(LucideIcons.chevronRight,
                      color: Colors.white, size: 20),
                ],
              ),
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
        tabs: const [
          Tab(
            height: 42,
            icon: Icon(LucideIcons.layoutGrid, size: 18),
            iconMargin: EdgeInsets.zero,
          ),
          Tab(
            height: 42,
            icon: Icon(LucideIcons.upload, size: 18),
            iconMargin: EdgeInsets.zero,
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
    final isAi = _designsTab.index == 0;
    final items = isAi ? _aiDesigns : _sharedDesigns;
    if (items.isEmpty) {
      return isAi ? _emptyDesigns() : _emptyShared();
    }
    return _designsGrid(items, isAi: isAi);
  }

  Widget _designsGrid(List<Map<String, dynamic>> items, {required bool isAi}) {
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
        return ProfileDesignTile(
          item: item,
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
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 360),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) =>
            ProfileDesignSwipeScreen(items: items, initialIndex: index),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
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

  Widget _emptyShared() {
    return _emptyState(
      icon: LucideIcons.upload,
      title: 'Henüz paylaşımın yok',
      subtitle:
          'Kendi mekanının fotoğrafını yükle, Koala farklı tarzlarda tasarlasın.',
      cta: 'İlk tasarımını paylaş',
      ctaIcon: LucideIcons.plus,
      onTap: _openShareUpload,
    );
  }

  Widget _emptyDesigns() {
    return _emptyState(
      icon: LucideIcons.sparkles,
      title: 'Henüz tasarım yok',
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

// ─── Hero widget — avatar + name + role + bio + photo-view affordance ───
class _Hero extends StatelessWidget {
  final String uid;
  final String name;
  final String role;
  final String? photo;
  final bool verified;
  final bool isPro;
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
    required this.uploading,
    required this.onAvatarTap,
    required this.onAvatarLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final hasUrl = (photo ?? '').isNotEmpty;
    final tag = profilePhotoHeroTag(uid.isEmpty ? 'me' : uid);
    final showBrandRing = verified || isPro;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPad + 18, 20, 14),
      child: Column(
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
              alignment: Alignment.center,
              children: [
                // Subtle radial halo — premium, IG/LinkedIn-grade polish.
                IgnorePointer(
                  child: Container(
                    width: 148,
                    height: 148,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        radius: 0.5,
                        colors: [
                          KoalaColors.accentDeep.withValues(alpha: 0.06),
                          KoalaColors.accentDeep.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                Hero(
                  tag: tag,
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasUrl ? Colors.white : KoalaColors.accentSoft,
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
                            size: 40, color: KoalaColors.accentDeep),
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
                        border: Border.all(color: KoalaColors.bg, width: 2),
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
          const SizedBox(height: 12),
          Text(
            name,
            style: KoalaText.h1.copyWith(
              fontSize: 22,
              letterSpacing: -0.4,
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            role,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: KoalaColors.textSec,
              letterSpacing: -0.1,
            ),
          ),
        ],
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

// ─── About section — bio + "Daha fazla" expand (LinkedIn-style) ───
class _AboutSection extends StatefulWidget {
  final String about;
  const _AboutSection({required this.about});

  @override
  State<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<_AboutSection> {
  bool _expanded = false;
  static const _kCollapsedMax = 3;
  static const _kLongLength = 140;

  @override
  Widget build(BuildContext context) {
    final long = widget.about.length > _kLongLength;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: KoalaColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: KoalaColors.borderSolid, width: 0.6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hakkımda',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: KoalaColors.textSec,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: Text(
                widget.about,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: KoalaColors.text,
                  letterSpacing: -0.1,
                ),
                maxLines: _expanded ? null : _kCollapsedMax,
                overflow: _expanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
              ),
            ),
            if (long) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    _expanded ? 'Daha az' : 'Daha fazla',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: KoalaColors.accentDeep,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ),
            ],
          ],
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

/// Profesyonel başvuru sheet'ini açar. Settings ekranı bunu kullanır.
Future<bool?> showProApplicationSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: KoalaColors.bg,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    useSafeArea: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.88,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const ProApplicationSheet(),
  );
}

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

// ─── Pro başvuru taxonomy: Evlumba `profiles` (role='designer') ────────
// Evlumba DB'de ayrı bir `professions` / `specialties` tablosu yok — taksonomi
// `profiles` tablosundaki distinct değerlerden türetiliyor (free-text alanlar).
//   - profession  → tek-seçim dropdown
//   - specialty   → çoklu-seçim chip (Evlumba'da virgülle ayrılmış string,
//                   tokenize ediliyor).
class ProTaxonomy {
  final List<String> professions;
  final List<String> specialties;
  const ProTaxonomy({required this.professions, required this.specialties});
}

int _trCompare(String a, String b) =>
    a.toLowerCase().compareTo(b.toLowerCase());

/// Evlumba `profiles`'ten profession + specialty taksonomisini tek defa
/// çekip Riverpod'da cache'ler (FutureProvider keepAlive default).
final proTaxonomyProvider = FutureProvider<ProTaxonomy>((ref) async {
  try {
    final ready = await EvlumbaLiveService.waitForReady();
    if (!ready) {
      return const ProTaxonomy(professions: [], specialties: []);
    }
    final rows = await EvlumbaLiveService.client
        .from('profiles')
        .select('profession, specialty')
        .eq('role', 'designer')
        .limit(500);
    final profSet = <String>{};
    final specSet = <String>{};
    for (final r in List<Map<String, dynamic>>.from(rows)) {
      final p = (r['profession'] ?? '').toString().trim();
      if (p.isNotEmpty) profSet.add(p);
      final s = (r['specialty'] ?? '').toString().trim();
      if (s.isEmpty) continue;
      // Evlumba'da specialty bazen "İç Mimari, Mobilya, Aydınlatma" gibi
      // virgülle ayrılmış geliyor — token'lara böl.
      for (final raw in s.split(RegExp(r'[,/;|]'))) {
        final t = raw.trim();
        if (t.isNotEmpty && t.length <= 40) specSet.add(t);
      }
    }
    final profs = profSet.toList()..sort(_trCompare);
    final specs = specSet.toList()..sort(_trCompare);
    return ProTaxonomy(professions: profs, specialties: specs);
  } catch (e) {
    debugPrint('proTaxonomyProvider error: $e');
    return const ProTaxonomy(professions: [], specialties: []);
  }
});

// ─── Profesyonel başvuru sheet (settings'ten ve profilden çağrılır) ───
class ProApplicationSheet extends ConsumerStatefulWidget {
  const ProApplicationSheet({super.key});
  @override
  ConsumerState<ProApplicationSheet> createState() =>
      _ProApplicationSheetState();
}

class _ProApplicationSheetState extends ConsumerState<ProApplicationSheet> {
  static const int _maxSpecialties = 5;

  // Gemini-generated hero (moved from settings card).
  static const String _heroUrl =
      'https://xgefjepaqnghaotqybpi.supabase.co/storage/v1/object/public/koala-seed/pro-cta/hero-v1.webp';

  final _fullName = TextEditingController();
  final _city = TextEditingController();
  final _ig = TextEditingController();
  final _portfolio = TextEditingController();
  final _reason = TextEditingController();

  String? _profession;
  final Set<String> _specialties = <String>{};

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final u = FirebaseAuth.instance.currentUser;
    if ((u?.displayName ?? '').isNotEmpty) _fullName.text = u!.displayName!;
  }

  @override
  void dispose() {
    _fullName.dispose();
    _city.dispose();
    _ig.dispose();
    _portfolio.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final name = _fullName.text.trim();
    final prof = (_profession ?? '').trim();
    if (name.isEmpty || prof.isEmpty) {
      setState(() => _error = 'Ad ve meslek alanı zorunlu.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    // Specialty array → tek satır CSV: mevcut applyForPro imzası tek
    // `profession` string alıyor; backend route güncellenene kadar
    // specialty'leri profession kuyruğuna ekleyerek payload'da koruyoruz.
    // (Backend tweak gerekli — bkz. rapor: `specialties: string[]` alanı.)
    final specialtiesStr = _specialties.toList().join(', ');
    final professionPayload =
        specialtiesStr.isEmpty ? prof : '$prof — $specialtiesStr';

    final ok = await UserProfileService.applyForPro(
      fullName: name,
      profession: professionPayload,
      city: _city.text.trim(),
      igUrl: _ig.text.trim(),
      portfolioUrl: _portfolio.text.trim(),
      reason: _reason.text.trim(),
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _submitting = false;
        _error = 'Gönderilemedi, biraz sonra tekrar dene.';
      });
      return;
    }
    Navigator.pop(context, true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Başvurun alındı — değerlendirme sonrası sana bildirim göndereceğiz.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _toggleSpecialty(String s) {
    setState(() {
      if (_specialties.contains(s)) {
        _specialties.remove(s);
      } else {
        if (_specialties.length >= _maxSpecialties) return;
        _specialties.add(s);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context);
    final taxonomyAsync = ref.watch(proTaxonomyProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ─── Hero strip (140h) ───────────────────────────────────
          _ProSheetHero(imageUrl: _heroUrl),
          // ─── Scrollable form body ────────────────────────────────
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionLabel('Hakkında'),
                  const SizedBox(height: 10),
                  _field(_fullName, label: 'Ad Soyad', hint: 'Tam adın'),
                  const SizedBox(height: 12),
                  _field(_city, label: 'Şehir', hint: 'İstanbul, İzmir…'),
                  const SizedBox(height: 22),
                  _divider(),
                  const SizedBox(height: 18),

                  _sectionLabel('Mesleğin'),
                  const SizedBox(height: 10),
                  _professionPicker(taxonomyAsync),
                  const SizedBox(height: 22),
                  _divider(),
                  const SizedBox(height: 18),

                  _sectionLabel(
                    'Uzmanlıkların',
                    trailing: '${_specialties.length} / $_maxSpecialties',
                  ),
                  const SizedBox(height: 10),
                  _specialtyPicker(taxonomyAsync),
                  const SizedBox(height: 22),
                  _divider(),
                  const SizedBox(height: 18),

                  _sectionLabel('Sosyal & İletişim'),
                  const SizedBox(height: 10),
                  _field(_ig,
                      label: 'Instagram', hint: '@kullaniciadi veya link'),
                  const SizedBox(height: 22),
                  _divider(),
                  const SizedBox(height: 18),

                  _sectionLabel('Portfolyo (opsiyonel)'),
                  const SizedBox(height: 10),
                  _field(_portfolio,
                      label: 'Portföy / Web', hint: 'https://… (varsa)'),
                  const SizedBox(height: 12),
                  _field(_reason,
                      label: 'Birkaç cümle (opsiyonel)',
                      hint:
                          'Tarzın, deneyimin, neden Koala\'da olmak istiyorsun?',
                      maxLines: 3),

                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!,
                        style: const TextStyle(
                            color: KoalaColors.error, fontSize: 13)),
                  ],
                  const SizedBox(height: 20),

                  // ─── Bottom CTA (56h, gradient) ──────────────────
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          KoalaColors.accentDeep,
                          KoalaColors.accent,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              KoalaColors.accentDeep.withValues(alpha: 0.32),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: Text(
                          _submitting
                              ? 'Gönderiliyor…'
                              : 'Başvuruyu gönder',
                          style: KoalaText.button,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── UI pieces ─────────────────────────────────────────────────────

  Widget _sectionLabel(String s, {String? trailing}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            s.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7280),
              letterSpacing: 1.1,
            ),
          ),
        ),
        if (trailing != null)
          Text(trailing,
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9CA3AF),
              )),
      ],
    );
  }

  Widget _divider() => Container(
        height: 1,
        color: const Color(0xFFF1F3F5),
      );

  Widget _professionPicker(AsyncValue<ProTaxonomy> taxonomyAsync) {
    return taxonomyAsync.when(
      loading: () => _pickerLoading(),
      error: (_, _) => _professionDropdown(const <String>[]),
      data: (tx) => _professionDropdown(tx.professions),
    );
  }

  Widget _professionDropdown(List<String> options) {
    final items = <String>{
      ...options,
      if (_profession != null) _profession!,
    }.toList();
    return Container(
      decoration: BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KoalaColors.borderSolid, width: 0.8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _profession,
          isExpanded: true,
          hint: Text(
            options.isEmpty
                ? 'Meslekler yükleniyor…'
                : 'Meslek seç (ör. İç Mimar)',
            style: KoalaText.hint,
          ),
          icon: const Icon(LucideIcons.chevronDown,
              size: 18, color: KoalaColors.textSec),
          style: KoalaText.body,
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(12),
          items: items
              .map((p) => DropdownMenuItem<String>(
                    value: p,
                    child: Text(p, style: KoalaText.body),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _profession = v),
        ),
      ),
    );
  }

  Widget _specialtyPicker(AsyncValue<ProTaxonomy> taxonomyAsync) {
    return taxonomyAsync.when(
      loading: () => _pickerLoading(),
      error: (_, _) => _specialtyChips(const <String>[]),
      data: (tx) => _specialtyChips(tx.specialties),
    );
  }

  Widget _specialtyChips(List<String> options) {
    if (options.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KoalaColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: KoalaColors.borderSolid, width: 0.8),
        ),
        child: const Text(
          'Uzmanlık listesi şu an yüklenemedi. Başvuruyu mesleğinle gönderebilirsin.',
          style: KoalaText.bodySec,
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((s) {
        final selected = _specialties.contains(s);
        final disabled =
            !selected && _specialties.length >= _maxSpecialties;
        return GestureDetector(
          onTap: disabled ? null : () => _toggleSpecialty(s),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? KoalaColors.accentDeep
                  : (disabled
                      ? const Color(0xFFF3F4F6)
                      : KoalaColors.surface),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? KoalaColors.accentDeep
                    : KoalaColors.borderSolid,
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  const Icon(LucideIcons.check,
                      size: 13, color: Colors.white),
                  const SizedBox(width: 5),
                ],
                Text(
                  s,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12.5,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected
                        ? Colors.white
                        : (disabled
                            ? const Color(0xFF9CA3AF)
                            : KoalaColors.text),
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _pickerLoading() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KoalaColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: KoalaColors.borderSolid, width: 0.8),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: KoalaColors.accentDeep,
              ),
            ),
            SizedBox(width: 12),
            Text('Yükleniyor…', style: KoalaText.bodySec),
          ],
        ),
      );

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

/// Pro sheet'in üst hero şeridi — Gemini-generated görsel + soft scrim +
/// "Profesyonel ol" başlığı + drag handle.
class _ProSheetHero extends StatelessWidget {
  final String imageUrl;
  const _ProSheetHero({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SizedBox(
        height: 140,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 250),
              placeholder: (_, _) => const _ProSheetHeroFallback(),
              errorWidget: (_, _, _) => const _ProSheetHeroFallback(),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x33000000),
                    Color(0x00000000),
                    Color(0xAA000000),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
            Positioned(
              top: 10,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
            ),
            const Positioned(
              left: 20,
              right: 20,
              bottom: 14,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PROFESYONEL OL',
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xE6FFFFFF),
                      letterSpacing: 1.5,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Tasarımlarını dünyayla buluştur',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.3,
                      shadows: [
                        Shadow(
                          color: Color(0x66000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProSheetHeroFallback extends StatelessWidget {
  const _ProSheetHeroFallback();
  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6C63FF), Color(0xFF9B5CFF)],
        ),
      ),
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
