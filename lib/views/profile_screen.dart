import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState, User;

import '../core/theme/koala_tokens.dart';
import '../widgets/media_upload_helper.dart';
import '../services/analytics_service.dart';
import '../services/collections_service.dart';
import '../services/saved_items_service.dart';
import 'admin/admin_shell.dart';
import 'auth_common.dart';
import 'auth_entry_screen.dart';
import 'collections_screen.dart';
import 'notifications_screen.dart';
import 'saved/saved_screen_v2.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Profil ekranı — refine tasarım. #FAFAFB üniform background,
/// avatar ring'inde ve butonlarda mor accent. Header card, stats row (3 tile),
/// sectioned settings (Hesap / Uygulama / Hakkında).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Background — direktif: tek tip #FAFAFB.
  static const Color _bg = Color(0xFFFAFAFB);

  final _user = FirebaseAuth.instance.currentUser;
  String? _photoUrl;
  String _displayName = '';
  String _email = '';
  int _adminTapCount = 0;
  Map<String, int> _savedCounts = {'design': 0, 'designer': 0, 'product': 0};
  int _collectionCount = 0;

  @override
  void initState() {
    super.initState();
    Analytics.screenViewed('profile');
    _displayName = _user?.displayName ?? '';
    _email = _user?.email ?? '';
    _photoUrl = _user?.photoURL;
    _loadStats();
  }

  Future<void> _loadStats() async {
    final results = await Future.wait([
      SavedItemsService.getCounts(),
      CollectionsService.getAll(),
    ]);
    if (mounted) {
      setState(() {
        _savedCounts = results[0] as Map<String, int>;
        _collectionCount = (results[1] as List).length;
      });
    }
  }

  Future<void> _pickProfilePhoto() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 512,
          maxHeight: 512,
          imageQuality: 80);
      if (image == null) return;
      final bytes = await image.readAsBytes();
      // MIME magic-byte'tan — uzantı ve contentType senkron olmazsa avatar
      // broken image görünüyor (özellikle HEIC/WEBP galeri seçimlerinde).
      final mime = MediaUploadHelper.detectMime(bytes);
      final ext = MediaUploadHelper.extensionFor(mime);
      final fileName =
          'profile_${_user!.uid}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final supabase = Supabase.instance.client;
      await supabase.storage.from('avatars').uploadBinary(fileName, bytes,
          fileOptions: FileOptions(contentType: mime, upsert: true));
      final publicUrl =
          supabase.storage.from('avatars').getPublicUrl(fileName);
      await _user.updatePhotoURL(publicUrl);
      if (mounted) {
        setState(() => _photoUrl = publicUrl);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: KoalaColors.greenBright,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            content: const Text('Profil fotoğrafı güncellendi',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600))));
      }
    } catch (e) {
      debugPrint('Photo error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: KoalaColors.errorBright,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            content: const Text('Fotoğraf yüklenemedi, tekrar dene',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600))));
      }
    }
  }

  void _editName() {
    final ctrl = TextEditingController(text: _displayName);
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: const Text('İsmini Değiştir',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                content: TextField(
                    controller: ctrl,
                    autofocus: true,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                        hintText: 'Adın',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: KoalaColors.accent, width: 2)))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Vazgeç')),
                  FilledButton(
                      onPressed: () async {
                        final name = ctrl.text.trim();
                        if (name.isEmpty || name.length > 50) return;
                        Navigator.pop(ctx);
                        try {
                          await _user?.updateDisplayName(name);
                          if (mounted) setState(() => _displayName = name);
                        } catch (e) {
                          debugPrint('Name update error: $e');
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('İsim güncellenemedi'),
                                    behavior: SnackBarBehavior.floating));
                          }
                        }
                      },
                      style: FilledButton.styleFrom(
                          backgroundColor: KoalaColors.accent),
                      child: const Text('Kaydet')),
                ]));
  }

  bool get _isAnonymous => _user?.isAnonymous ?? true;

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: const Text('Çıkış Yap',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 17)),
                content: const Text(
                    'Hesabından çıkış yapmak istediğine emin misin?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Vazgeç')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(
                          backgroundColor: KoalaColors.errorBright),
                      child: const Text('Çıkış Yap')),
                ]));
    if (confirm != true) return;

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    if (!mounted) return;

    // GoRouter bypass — doğrudan Navigator ile tüm stack'ı temizleyip auth ekranını göster
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (_) => const AuthEntryScreen(mode: AuthFlowMode.login)),
      (route) => false,
    );
  }

  void _goToLogin() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
          builder: (_) => const AuthEntryScreen(mode: AuthFlowMode.login)),
    );
  }

  void _comingSoon(String label) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Text('$label · Yakında'),
      ));
  }

  void _goBackHome() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.go('/');
  }

  // Mesaj sayısı placeholder — şu an SavedItemsService'te tutulmuyor.
  int get _designsCount =>
      (_savedCounts['design'] ?? 0) + (_savedCounts['project'] ?? 0);
  int get _savedTotal => _savedCounts.values.fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    final totalDesigns = _designsCount;
    final totalSaved = _savedTotal;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Top app bar ─────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 16, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _goBackHome,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.white,
                          border: Border.all(
                              color: KoalaColors.border, width: 0.6),
                        ),
                        child: const Icon(
                          LucideIcons.arrowLeft,
                          size: 18,
                          color: KoalaColors.textMed,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () {
                        _adminTapCount++;
                        if (_adminTapCount >= 5) {
                          _adminTapCount = 0;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AdminShell(),
                            ),
                          );
                        }
                      },
                      child: const Text(
                        'Profil',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: KoalaColors.text,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Header card (avatar 80 + name + email) ─────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: KoalaColors.border.withValues(alpha: 0.6),
                        width: 0.6),
                  ),
                  child: Column(
                    children: [
                      // Avatar 80px — ring sadece accentDeep ile (mor sınır).
                      GestureDetector(
                        onTap: _pickProfilePhoto,
                        child: Stack(
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              padding: const EdgeInsets.all(2.5),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    KoalaColors.accentDeep,
                                    KoalaColors.accent,
                                  ],
                                ),
                              ),
                              child: Container(
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                ),
                                padding: const EdgeInsets.all(2),
                                child: ClipOval(
                                  child: _photoUrl != null
                                      ? Image.network(
                                          _photoUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => Container(
                                            color: KoalaColors.surfaceAlt,
                                            child: const Icon(LucideIcons.user,
                                                color: KoalaColors.textTer,
                                                size: 36),
                                          ),
                                        )
                                      : Container(
                                          color: KoalaColors.surfaceAlt,
                                          child: const Icon(LucideIcons.user,
                                              color: KoalaColors.textTer,
                                              size: 36),
                                        ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: KoalaColors.accentDeep,
                                  border: Border.all(
                                      color: Colors.white, width: 2.5),
                                ),
                                child: const Icon(
                                  LucideIcons.camera,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      // İsim — 22px Manrope w700
                      Text(
                        _isAnonymous
                            ? 'Misafir Kullanıcı'
                            : (_displayName.isNotEmpty
                                ? _displayName
                                : 'Koala Kullanıcı'),
                        style: const TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: KoalaColors.text,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // E-posta — 14px secondary
                      Text(
                        _isAnonymous
                            ? 'Giriş yap ve tüm özellikleri kullan'
                            : _email,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _isAnonymous
                              ? KoalaColors.accentDeep
                              : KoalaColors.textSec,
                        ),
                      ),
                      if (_isAnonymous) ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 42,
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _goToLogin,
                            style: FilledButton.styleFrom(
                              backgroundColor: KoalaColors.accentDeep,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(LucideIcons.logIn, size: 16),
                            label: const Text(
                              'Giriş Yap',
                              style: TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: _editName,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: KoalaColors.text,
                            side: const BorderSide(
                                color: KoalaColors.border, width: 0.8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                          ),
                          icon: const Icon(LucideIcons.pencil, size: 14),
                          label: const Text(
                            'İsmi Düzenle',
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // ── Stats row — Tasarımlarım / Kaydedilenler / Mesajlar ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _StatTile(
                        icon: LucideIcons.image,
                        label: 'Tasarımlarım',
                        value: '$totalDesigns',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatTile(
                        icon: LucideIcons.bookmark,
                        label: 'Kaydedilenler',
                        value: '$totalSaved',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatTile(
                        icon: LucideIcons.messageCircle,
                        label: 'Mesajlar',
                        value: '$_collectionCount',
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Section: Hesap ─────────────────────────────
            SliverToBoxAdapter(
              child: _SectionHeader('Hesap'),
            ),
            SliverToBoxAdapter(
              child: _SectionCard(
                children: [
                  _SettingRow(
                    icon: LucideIcons.bookmark,
                    label: 'Kaydedilenlerim',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SavedScreenV2()),
                    ),
                  ),
                  const _Divider(),
                  _SettingRow(
                    icon: LucideIcons.folderHeart,
                    label: 'Koleksiyonlarım',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const CollectionsScreen()),
                    ),
                  ),
                  if (!_isAnonymous) ...[
                    const _Divider(),
                    _SettingRow(
                      icon: LucideIcons.mail,
                      label: 'E-posta',
                      trailing: _email,
                    ),
                    const _Divider(),
                    _SettingRow(
                      icon: LucideIcons.logOut,
                      label: 'Çıkış Yap',
                      iconColor: KoalaColors.errorBright,
                      onTap: _logout,
                    ),
                  ],
                ],
              ),
            ),

            // ── Section: Uygulama ─────────────────────────
            SliverToBoxAdapter(
              child: _SectionHeader('Uygulama'),
            ),
            SliverToBoxAdapter(
              child: _SectionCard(
                children: [
                  _SettingRow(
                    icon: LucideIcons.bell,
                    label: 'Bildirimler',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NotificationsScreen(),
                      ),
                    ),
                  ),
                  const _Divider(),
                  _SettingRow(
                    icon: LucideIcons.languages,
                    label: 'Dil',
                    trailing: 'Türkçe',
                    onTap: () => _comingSoon('Dil seçimi'),
                  ),
                ],
              ),
            ),

            // ── Section: Hakkında ─────────────────────────
            SliverToBoxAdapter(
              child: _SectionHeader('Hakkında'),
            ),
            SliverToBoxAdapter(
              child: _SectionCard(
                children: [
                  _SettingRow(
                    icon: LucideIcons.info,
                    label: 'Versiyon',
                    trailing: 'v1.0.0',
                  ),
                  const _Divider(),
                  _SettingRow(
                    icon: LucideIcons.shield,
                    label: 'Gizlilik',
                    onTap: () => _comingSoon('Gizlilik politikası'),
                  ),
                  const _Divider(),
                  _SettingRow(
                    icon: LucideIcons.fileText,
                    label: 'KVKK',
                    onTap: () => _comingSoon('KVKK aydınlatma'),
                  ),
                ],
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 36),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stats tile — küçük 3'lü grid kartı (ikon + sayı + label).
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: KoalaColors.border.withValues(alpha: 0.6), width: 0.6),
      ),
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: KoalaColors.accentSoft,
            ),
            child: Icon(icon, size: 16, color: KoalaColors.accentDeep),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: KoalaColors.text,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: KoalaColors.textSec,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: KoalaColors.textTer,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: KoalaColors.border.withValues(alpha: 0.6), width: 0.6),
        ),
        child: Column(children: children),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
    this.iconColor,
  });
  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final clr = iconColor ?? KoalaColors.text;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 18, color: clr),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: clr,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              if (trailing != null && trailing!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    trailing!,
                    style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: KoalaColors.textSec,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (onTap != null)
                const Icon(LucideIcons.chevronRight,
                    size: 18, color: KoalaColors.textTer),
            ],
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        height: 0.5,
        color: KoalaColors.border.withValues(alpha: 0.5),
      ),
    );
  }
}
