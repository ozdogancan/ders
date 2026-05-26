// Profil sekmesi — Instagram-clean. Avatar + isim/rol + 3 numara + 2 tab grid.
// Pro CTA settings ekranında, burada YOK. Profil düzenleme tek nötr buton.
// Avatar kısa-tap → fotoğraf sheet, uzun-bas → /profile (ayarlar).

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, FileOptions;

import '../core/theme/koala_tokens.dart';
import '../services/saved_items_service.dart';
import '../services/user_profile_service.dart';
import '../widgets/verified_badge.dart';
import 'mekan/wizard/mekan_wizard_screen.dart';
import 'my_designs/design_detail_screen.dart';

class ProfileTabScreen extends ConsumerStatefulWidget {
  const ProfileTabScreen({super.key});

  @override
  ConsumerState<ProfileTabScreen> createState() => _ProfileTabScreenState();
}

class _ProfileTabScreenState extends ConsumerState<ProfileTabScreen>
    with SingleTickerProviderStateMixin {
  // AI Tasarımları — Koala AI ile üretilen (saved_items type='project').
  List<Map<String, dynamic>> _aiDesigns = const [];
  // Paylaştıklarım — kullanıcının yüklediği. Şimdilik ayrı tablo yok.
  List<Map<String, dynamic>> _sharedDesigns = const [];
  bool _designsLoading = true;
  bool _uploadingAvatar = false;
  late final TabController _designsTab;

  @override
  void initState() {
    super.initState();
    _designsTab = TabController(length: 2, vsync: this);
    _designsTab.addListener(() {
      if (mounted) setState(() {});
    });
    _loadDesigns();
  }

  @override
  void dispose() {
    _designsTab.dispose();
    super.dispose();
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

  Future<void> _refreshAll() async {
    ref.invalidate(userProfileProvider);
    await _loadDesigns();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final bundle = ref.watch(userProfileProvider).asData?.value;
    final profile = bundle?.profile;
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
    final role = profile?.isPro == true
        ? (about.isNotEmpty ? 'Profesyonel Tasarımcı' : 'Koala Pro')
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
              child: _hero(name, role, about, photo, verified),
            ),
            SliverToBoxAdapter(child: _statsRow()),
            const SliverToBoxAdapter(child: SizedBox(height: 18)),
            SliverToBoxAdapter(child: _editButton()),
            const SliverToBoxAdapter(child: SizedBox(height: 22)),
            SliverToBoxAdapter(child: _tabBar()),
            SliverToBoxAdapter(child: _designsTabBody()),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
            SliverToBoxAdapter(child: _settingsRow()),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  // ─── Hero — flat, minimal: avatar + isim + rol + bio ───
  Widget _hero(String name, String role, String about, String? photo,
      bool verified) {
    final topPad = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPad + 18, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar — kısa-tap fotoğraf, uzun-bas ayarlar.
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _openAvatarActions(photo);
            },
            onLongPress: () {
              HapticFeedback.mediumImpact();
              context.push('/profile');
            },
            child: _avatar(photo, verified),
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
          if (about.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              about,
              style: KoalaText.bodySmall,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _avatar(String? url, bool verified) {
    final hasUrl = (url ?? '').isNotEmpty;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hasUrl ? Colors.white : KoalaColors.accentSoft,
            border: Border.all(color: KoalaColors.borderSolid, width: 0.6),
          ),
          clipBehavior: Clip.antiAlias,
          child: hasUrl
              ? CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover)
              : const Icon(LucideIcons.user,
                  size: 38, color: KoalaColors.accentDeep),
        ),
        if (_uploadingAvatar)
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
        // Kamera ikonu YALNIZCA henüz fotoğraf yokken görünür — kullanıcıya
        // "buraya dokunup foto ekle" sinyali. Foto eklendikten sonra
        // affordance kalkar (Instagram pattern).
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
    );
  }

  // ─── Stats — placeholder dash YOK; sadece veri olan stat'leri göster.
  // Instagram pattern: "—" yerine hiç gösterme. "Kayıt" backend yokken
  // gizleniyor, eklenince geri açılır.
  Widget _statsRow() {
    final designCount =
        _designsLoading ? null : (_aiDesigns.length + _sharedDesigns.length);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(child: _statTile(designCount?.toString() ?? '0', 'Tasarım')),
        ],
      ),
    );
  }

  Widget _statTile(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
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
  }

  // ─── Tek nötr "Profili düzenle" butonu — Instagram pattern ───
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

  // ─── 2 tab — underline, sade ───
  Widget _tabBar() {
    return Container(
      decoration: const Border(
        top: BorderSide(color: KoalaColors.borderSolid, width: 0.6),
        bottom: BorderSide(color: KoalaColors.borderSolid, width: 0.6),
      ).toBoxDecoration(),
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

  // 3 kolon kare grid — Instagram. 2px gutter, chrome yok.
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
        return _DesignGridTile(
          item: item,
          type: isAi ? SavedItemType.project : SavedItemType.design,
          onEdit: () => _openEditDesignSheet(item, isAi: isAi),
          onDelete: () => _confirmDeleteDesign(item, isAi: isAi),
        );
      },
    );
  }

  Widget _emptyShared() {
    return _emptyState(
      icon: LucideIcons.upload,
      title: 'Henüz paylaşımın yok',
      subtitle: 'Kendi mekanının fotoğrafını yükle, Koala farklı tarzlarda tasarlasın.',
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
          // Instagram pattern: empty-state CTA outlined, marketing-y filled
          // pill DEĞİL. Tıkalanabilir ama dikkat çekmeyen.
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
              leading: const Icon(LucideIcons.camera,
                  color: KoalaColors.accentDeep),
              title:
                  const Text('Fotoğraf çek', style: KoalaText.bodyMedium),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(LucideIcons.image,
                  color: KoalaColors.accentDeep),
              title:
                  const Text('Galeriden seç', style: KoalaText.bodyMedium),
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

  // ─── Sessiz "Ayarlar" satırı, low-key ───
  Widget _settingsRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            context.push('/profile');
          },
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(LucideIcons.settings,
                    size: 15, color: KoalaColors.textSec),
                SizedBox(width: 8),
                Text(
                  'Ayarlar',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: KoalaColors.textSec,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Profil fotoğrafı: tap → kaynak sheet → upload/remove ───
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
            if (!kIsWeb)
              ListTile(
                leading: const Icon(LucideIcons.camera,
                    color: KoalaColors.accentDeep),
                title: const Text('Fotoğraf çek',
                    style: KoalaText.bodyMedium),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
            ListTile(
              leading: const Icon(LucideIcons.image,
                  color: KoalaColors.accentDeep),
              title: const Text('Galeriden seç',
                  style: KoalaText.bodyMedium),
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

Widget _dragHandle() => Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: KoalaColors.border,
        borderRadius: BorderRadius.circular(100),
      ),
    );

// Border'ı BoxDecoration'a çevirmek için küçük yardımcı.
extension on Border {
  BoxDecoration toBoxDecoration() => BoxDecoration(border: this);
}

/// Profesyonel başvuru sheet'ini açar. Settings ekranı bunu kullanır.
/// Submit edilirse `true` döner; çağıran `userProfileProvider`'ı
/// invalidate etmeli.
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
    final ok = await UserProfileService.upsert(
      displayName: _nameCtrl.text.trim(),
      about: _aboutCtrl.text.trim(),
      contact: {
        if (_igCtrl.text.trim().isNotEmpty) 'instagram': _igCtrl.text.trim(),
        if (_webCtrl.text.trim().isNotEmpty) 'website': _webCtrl.text.trim(),
      },
    );
    if (!mounted) return;
    if (!ok) {
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

// ─── Profesyonel başvuru sheet (settings'ten çağrılır) ───
class ProApplicationSheet extends StatefulWidget {
  const ProApplicationSheet({super.key});
  @override
  State<ProApplicationSheet> createState() => _ProApplicationSheetState();
}

class _ProApplicationSheetState extends State<ProApplicationSheet> {
  final _fullName = TextEditingController();
  final _profession = TextEditingController();
  final _city = TextEditingController();
  final _ig = TextEditingController();
  final _portfolio = TextEditingController();
  final _reason = TextEditingController();
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
    _profession.dispose();
    _city.dispose();
    _ig.dispose();
    _portfolio.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final name = _fullName.text.trim();
    final prof = _profession.text.trim();
    if (name.isEmpty || prof.isEmpty) {
      setState(() => _error = 'Ad ve meslek alanı zorunlu.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final ok = await UserProfileService.applyForPro(
      fullName: name,
      profession: prof,
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
              const SizedBox(height: 24),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
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
                          color: KoalaColors.accentDeep
                              .withValues(alpha: 0.28),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(LucideIcons.badgeCheck,
                        size: 24, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Profesyonel başvurusu', style: KoalaText.h2),
                        SizedBox(height: 2),
                        Text(
                          'Onaylanınca yeşil tik + paylaşım yetkisi.',
                          style: KoalaText.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Birkaç bilgi yeter — Evlumba ekibi kısa sürede dönüş yapar.',
                style: KoalaText.bodySec,
              ),
              const SizedBox(height: 24),
              _field(_fullName, label: 'Ad Soyad', hint: 'Tam adın'),
              const SizedBox(height: 14),
              _field(_profession,
                  label: 'Meslek / Uzmanlık',
                  hint: 'ör. İç Mimar, Mobilya Tasarımcısı'),
              const SizedBox(height: 14),
              _field(_city, label: 'Şehir', hint: 'İstanbul, İzmir…'),
              const SizedBox(height: 14),
              _field(_ig, label: 'Instagram', hint: '@kullaniciadi veya link'),
              const SizedBox(height: 14),
              _field(_portfolio,
                  label: 'Portföy / Web', hint: 'https://… (varsa)'),
              const SizedBox(height: 14),
              _field(_reason,
                  label: 'Birkaç cümle (opsiyonel)',
                  hint: 'Tarzın, deneyimin, neden Koala\'da olmak istiyorsun?',
                  maxLines: 3),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(
                        color: KoalaColors.error, fontSize: 13)),
              ],
              const SizedBox(height: 24),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [KoalaColors.accentDeep, KoalaColors.accent],
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
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: Text(
                      _submitting ? 'Gönderiliyor…' : 'Başvuruyu gönder',
                      style: KoalaText.button,
                    ),
                  ),
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

// ─────────────────────────────────────────────────────────
// Tasarım grid tile — Instagram. Tap → DesignDetailScreen. Long-press → menü.
// Chrome yok: başlık, "…" buton, gradient — hepsi kalktı.
// ─────────────────────────────────────────────────────────
class _DesignGridTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final SavedItemType type;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _DesignGridTile({
    required this.item,
    required this.type,
    required this.onEdit,
    required this.onDelete,
  });

  void _openMenu(BuildContext context) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KoalaColors.bg,
      isDismissible: true,
      enableDrag: true,
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
              leading: const Icon(LucideIcons.pencil,
                  color: KoalaColors.accentDeep),
              title: const Text('Düzenle', style: KoalaText.bodyMedium),
              onTap: () {
                Navigator.pop(ctx);
                onEdit();
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.trash2,
                  color: KoalaColors.error),
              title: const Text(
                'Sil',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: KoalaColors.error,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx);
                onDelete();
              },
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
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = (item['image_url'] as String?) ?? '';
    final title = (item['title'] as String?) ?? 'Mekan';
    final id = item['id']?.toString() ?? title;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).push(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 360),
            reverseTransitionDuration: const Duration(milliseconds: 280),
            pageBuilder: (_, _, _) => DesignDetailScreen(item: item),
            transitionsBuilder: (_, anim, _, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
      },
      onLongPress: () => _openMenu(context),
      child: Hero(
        tag: 'design-$id',
        child: Container(
          color: KoalaColors.surfaceAlt,
          child: imageUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, _) =>
                      Container(color: KoalaColors.surfaceAlt),
                  errorWidget: (_, _, _) => Container(
                    color: KoalaColors.surfaceAlt,
                    child: Center(
                      child: Semantics(
                        label: title,
                        child: const Icon(LucideIcons.imageOff,
                            color: KoalaColors.textTer, size: 22),
                      ),
                    ),
                  ),
                )
              : Container(color: KoalaColors.surfaceAlt),
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
