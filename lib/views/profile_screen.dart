import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState, User;

import '../services/credit_service.dart';
import 'credit_store_screen.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _user = FirebaseAuth.instance.currentUser;
  final _creditService = CreditService();
  int _credits = 0;
  bool _loading = true;
  String? _photoUrl;
  String _displayName = '';
  String _email = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // Load credits
    final credits = await _creditService.getCredits();

    // Load user info
    final name = _user?.displayName ?? '';
    final email = _user?.email ?? '';
    final photo = _user?.photoURL ?? '';

    if (mounted) {
      setState(() {
        _credits = credits;
        _displayName = name;
        _email = email;
        _photoUrl = photo.isNotEmpty ? photo : null;
        _loading = false;
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
        imageQuality: 80,
      );
      if (image == null) return;

      // Upload to Supabase Storage
      final bytes = await image.readAsBytes();
      final fileName = 'profile_${_user!.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      try {
        final supabase = Supabase.instance.client;
        await supabase.storage.from('avatars').uploadBinary(
          fileName,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );

        final publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName);

        // Update Firebase profile
        await _user!.updatePhotoURL(publicUrl);

        // Update Supabase
        await supabase.from('users').update({
          'photo_url': publicUrl,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', _user!.uid);

        setState(() => _photoUrl = publicUrl);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF22C55E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            content: const Text('Profil fotoğrafı güncellendi',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ));
        }
      } catch (e) {
        // If storage bucket doesn't exist, just update locally
        debugPrint('Photo upload error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFF59E0B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            content: const Text('Fotoğraf şimdilik yüklenemedi',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ));
        }
      }
    } catch (e) {
      debugPrint('Image picker error: $e');
    }
  }

  void _editName() {
    final ctrl = TextEditingController(text: _displayName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('İsmini Değiştir',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'Adın',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);

              await _user?.updateDisplayName(name);

              try {
                final supabase = Supabase.instance.client;
                await supabase.from('users').update({
                  'display_name': name,
                  'updated_at': DateTime.now().toIso8601String(),
                }).eq('id', _user!.uid);
              } catch (_) {}

              setState(() => _displayName = name);
            },
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1)),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Çıkış Yap',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        content:
            const Text('Hesabından çıkış yapmak istediğine emin misin?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Hesabı Sil',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: Color(0xFFEF4444))),
        content: const Text(
            'Bu işlem geri alınamaz. Tüm verilerin silinecek.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Hesabı Sil'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      if (_user != null) {
        final supabase = Supabase.instance.client;
        await supabase.from('users').delete().eq('id', _user!.uid);
      }
      await _user?.delete();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
              'Hesap silme başarısız. Tekrar giriş yapıp dene.'),
          backgroundColor: const Color(0xFFEF4444),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFD),
      body: SafeArea(
        child: _loading
            ? const Center(
                child:
                    CircularProgressIndicator(color: Color(0xFF6366F1)))
            : CustomScrollView(slivers: [
                // Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: const Color(0xFFF1F5F9)),
                          child: const Icon(Icons.arrow_back_rounded,
                              size: 18, color: Color(0xFF475569)),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Text('Profil',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A))),
                    ]),
                  ),
                ),

                // Avatar + Name
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                    child: Column(children: [
                      // Avatar with edit button
                      GestureDetector(
                        onTap: _pickProfilePhoto,
                        child: Stack(children: [
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(colors: [
                                Color(0xFF6366F1),
                                Color(0xFF8B5CF6)
                              ]),
                              boxShadow: [
                                BoxShadow(
                                    color: const Color(0xFF6366F1)
                                        .withAlpha(40),
                                    blurRadius: 24)
                              ],
                            ),
                            child: _photoUrl != null
                                ? ClipOval(
                                    child: Image.network(_photoUrl!,
                                        fit: BoxFit.cover,
                                        width: 96,
                                        height: 96,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(
                                                Icons.person_rounded,
                                                color: Colors.white,
                                                size: 44)))
                                : const Icon(Icons.person_rounded,
                                    color: Colors.white, size: 44),
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
                                    color: const Color(0xFFFAFBFD),
                                    width: 3),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withAlpha(15),
                                      blurRadius: 8)
                                ],
                              ),
                              child: const Icon(
                                  Icons.camera_alt_rounded,
                                  size: 14,
                                  color: Color(0xFF6366F1)),
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      Text(
                          _displayName.isNotEmpty
                              ? _displayName
                              : 'Koala Kullanıcı',
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A))),
                      const SizedBox(height: 4),
                      Text(_email,
                          style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade500)),
                    ]),
                  ),
                ),

                // Credits card
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [
                          Color(0xFF6366F1),
                          Color(0xFF8B5CF6)
                        ]),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                              color:
                                  const Color(0xFF6366F1).withAlpha(35),
                              blurRadius: 24,
                              offset: const Offset(0, 8))
                        ],
                      ),
                      child: Row(children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: Colors.white.withAlpha(25)),
                          child: const Icon(Icons.bolt_rounded,
                              color: Colors.white, size: 26),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text('$_credits Kredi',
                                    style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white)),
                                Text(
                                    'Soru çözmek için kredi kullan',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white
                                            .withAlpha(180))),
                              ]),
                        ),
                        GestureDetector(
                          onTap: () async {
                            await Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const CreditStoreScreen()));
                            _loadData();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 11),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius:
                                    BorderRadius.circular(14)),
                            child: const Text('Kredi Al',
                                style: TextStyle(
                                    color: Color(0xFF6366F1),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13)),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),

                // Settings
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('AYARLAR',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.grey.shade400,
                                  letterSpacing: 1)),
                          const SizedBox(height: 12),
                          _Tile(
                            icon: Icons.person_rounded,
                            label: 'İsim',
                            value: _displayName.isNotEmpty
                                ? _displayName
                                : 'Belirtilmemiş',
                            onTap: _editName,
                          ),
                          _Tile(
                            icon: Icons.email_rounded,
                            label: 'E-posta',
                            value: _email,
                            editable: false,
                          ),
                        ]),
                  ),
                ),

                // Account
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('HESAP',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.grey.shade400,
                                  letterSpacing: 1)),
                          const SizedBox(height: 12),
                          _Tile(
                            icon: Icons.logout_rounded,
                            label: 'Çıkış Yap',
                            value: '',
                            color: const Color(0xFFF59E0B),
                            onTap: _logout,
                          ),
                          _Tile(
                            icon: Icons.delete_forever_rounded,
                            label: 'Hesabı Sil',
                            value: '',
                            color: const Color(0xFFEF4444),
                            onTap: _deleteAccount,
                          ),
                        ]),
                  ),
                ),

                // Version
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 36, 20, 40),
                    child: Center(
                        child: Text('Koala v1.0.0',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade400))),
                  ),
                ),
              ]),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.editable = true,
    this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool editable;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF6366F1);
    return GestureDetector(
      onTap: editable ? onTap : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEEF2F7)),
        ),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: c.withAlpha(12)),
            child: Icon(icon, size: 18, color: c),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w600)),
                  if (value.isNotEmpty)
                    Text(value,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A))),
                ]),
          ),
          if (editable && onTap != null)
            Icon(Icons.chevron_right_rounded,
                size: 20, color: Colors.grey.shade300),
        ]),
      ),
    );
  }
}
