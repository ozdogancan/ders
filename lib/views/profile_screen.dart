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
import 'style_profile_screen.dart';
import 'package:lucide_icons/lucide_icons.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
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
      final image = await picker.pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 80);
      if (image == null) return;
      final bytes = await image.readAsBytes();
      // MIME magic-byte'tan — uzantı ve contentType senkron olmazsa avatar
      // broken image görünüyor (özellikle HEIC/WEBP galeri seçimlerinde).
      final mime = MediaUploadHelper.detectMime(bytes);
      final ext = MediaUploadHelper.extensionFor(mime);
      final fileName = 'profile_${_user!.uid}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final supabase = Supabase.instance.client;
      await supabase.storage.from('avatars').uploadBinary(fileName, bytes,
        fileOptions: FileOptions(contentType: mime, upsert: true));
      final publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName);
      await _user.updatePhotoURL(publicUrl);
      if (mounted) {
        setState(() => _photoUrl = publicUrl);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating, backgroundColor: KoalaColors.greenBright,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          content: const Text('Profil fotoğrafı güncellendi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))));
      }
    } catch (e) {
      debugPrint('Photo error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating, backgroundColor: KoalaColors.errorBright,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          content: const Text('Fotoğraf yüklenemedi, tekrar dene', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))));
      }
    }
  }

  void _editName() {
    final ctrl = TextEditingController(text: _displayName);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('İsmini Değiştir', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      content: TextField(controller: ctrl, autofocus: true,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        decoration: InputDecoration(hintText: 'Adın',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: KoalaColors.accent, width: 2)))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
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
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('İsim güncellenemedi'),
                  behavior: SnackBarBehavior.floating));
              }
            }
          },
          style: FilledButton.styleFrom(backgroundColor: KoalaColors.accent),
          child: const Text('Kaydet')),
      ]));
  }

  bool get _isAnonymous => _user?.isAnonymous ?? true;

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Çıkış Yap', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      content: const Text('Hesabından çıkış yapmak istediğine emin misin?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: KoalaColors.errorBright),
          child: const Text('Çıkış Yap')),
      ]));
    if (confirm != true) return;

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    if (!mounted) return;

    // GoRouter bypass — doğrudan Navigator ile tüm stack'ı temizleyip auth ekranını göster
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthEntryScreen(mode: AuthFlowMode.login)),
      (route) => false,
    );
  }

  void _goToLogin() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const AuthEntryScreen(mode: AuthFlowMode.login)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaColors.surfaceMuted,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _goBackHome,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: KoalaColors.surfaceCool,
                        ),
                        child: const Icon(
                          LucideIcons.arrowLeft,
                          size: 18,
                          color: KoalaColors.textMed,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
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
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: KoalaColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _pickProfilePhoto,
                      child: Stack(
                        children: [
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [KoalaColors.accent, KoalaColors.accent],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: KoalaColors.accent.withValues(alpha: 0.15),
                                  blurRadius: 24,
                                ),
                              ],
                            ),
                            child: _photoUrl != null
                                ? ClipOval(
                                    child: Image.network(
                                      _photoUrl!,
                                      fit: BoxFit.cover,
                                      width: 96,
                                      height: 96,
                                      errorBuilder: (_, _, _) => const Icon(
                                        LucideIcons.user,
                                        color: Colors.white,
                                        size: 44,
                                      ),
                                    ),
                                  )
                                : const Icon(
                                    LucideIcons.user,
                                    color: Colors.white,
                                    size: 44,
                                  ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                border: Border.all(
                                  color: KoalaColors.surfaceMuted,
                                  width: 3,
                                ),
                              ),
                              child: const Icon(
                                LucideIcons.camera,
                                size: 14,
                                color: KoalaColors.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isAnonymous
                          ? 'Misafir Kullanıcı'
                          : (_displayName.isNotEmpty
                                ? _displayName
                                : 'Koala Kullanıcı'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: KoalaColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isAnonymous
                          ? 'Giriş yap ve tüm özellikleri kullan'
                          : _email,
                      style: TextStyle(
                        fontSize: 14,
                        color: _isAnonymous
                            ? KoalaColors.accent
                            : Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _StatBadge(
                          '${_savedCounts.values.fold(0, (a, b) => a + b)}',
                          'Kayıt',
                        ),
                        Container(
                          width: 1,
                          height: 28,
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          color: KoalaColors.borderSolid,
                        ),
                        _StatBadge('$_collectionCount', 'Koleksiyon'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.white,
                  ),
                  child: Column(
                    children: [
                      _ActionTile(
                        icon: LucideIcons.bookmark,
                        label: 'Kaydedilenlerim',
                        color: KoalaColors.accent,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SavedScreenV2()),
                        ),
                      ),
                      const Divider(height: 1),
                      _ActionTile(
                        icon: LucideIcons.folderHeart,
                        label: 'Koleksiyonlarım',
                        color: KoalaColors.pink,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CollectionsScreen(),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      _ActionTile(
                        icon: LucideIcons.bell,
                        label: 'Bildirimler',
                        color: KoalaColors.warning,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const NotificationsScreen(),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      _ActionTile(
                        icon: LucideIcons.palette,
                        label: 'Stil Profilim',
                        color: KoalaColors.accent,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const StyleProfileScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (!_isAnonymous)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AYARLAR',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade400,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SettingTile(
                        icon: LucideIcons.user,
                        label: 'İsim',
                        value: _displayName.isNotEmpty
                            ? _displayName
                            : 'Belirtilmemiş',
                        onTap: _editName,
                      ),
                      _SettingTile(
                        icon: LucideIcons.mail,
                        label: 'E-posta',
                        value: _email,
                        editable: false,
                      ),
                    ],
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HESAP',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey.shade400,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_isAnonymous)
                      _SettingTile(
                        icon: LucideIcons.logIn,
                        label: 'Giriş Yap',
                        value: 'Google veya telefon ile',
                        color: KoalaColors.accent,
                        onTap: _goToLogin,
                      )
                    else
                      _SettingTile(
                        icon: LucideIcons.logOut,
                        label: 'Çıkış Yap',
                        value: '',
                        color: KoalaColors.warning,
                        onTap: _logout,
                      ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 36, 20, 40),
                child: Center(
                  child: Text(
                    'Koala v1.0.0',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade400,
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

  void _goBackHome() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.go('/');
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap,
    child: Padding(padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(children: [
        Container(width: 36, height: 36,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: color.withValues(alpha:0.08)),
          child: Icon(icon, size: 18, color: color)),
        const SizedBox(width: 14),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: KoalaColors.text))),
        Icon(LucideIcons.chevronRight, size: 20, color: Colors.grey.shade300),
      ])));
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({required this.icon, required this.label, required this.value, this.onTap, this.editable = true, this.color});
  final IconData icon; final String label, value; final VoidCallback? onTap; final bool editable; final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = color ?? KoalaColors.accent;
    return GestureDetector(onTap: editable ? onTap : null,
      child: Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Container(width: 36, height: 36,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: c.withValues(alpha:0.08)),
            child: Icon(icon, size: 18, color: c)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
            if (value.isNotEmpty) Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: KoalaColors.text)),
          ])),
          if (editable && onTap != null) Icon(LucideIcons.chevronRight, size: 20, color: Colors.grey.shade300),
        ])));
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge(this.count, this.label);
  final String count, label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(count, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: KoalaColors.text)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      ],
    );
  }
}
