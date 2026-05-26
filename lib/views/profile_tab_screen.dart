// Profil sekmesi — alt nav'ın son slotu. Header + stats + takip ettiklerim
// + tasarımlarım kısayolu. Instagram benzeri yoğun ama Koala tasarım diline
// sadık.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/koala_tokens.dart';
import '../providers/pro_status_provider.dart';
import '../services/evlumba_live_service.dart';
import '../services/follow_service.dart';
import '../services/user_profile_service.dart';
import '../widgets/verified_badge.dart';
import 'projeler_screen.dart';

class ProfileTabScreen extends ConsumerStatefulWidget {
  const ProfileTabScreen({super.key});

  @override
  ConsumerState<ProfileTabScreen> createState() => _ProfileTabScreenState();
}

class _ProfileTabScreenState extends ConsumerState<ProfileTabScreen> {
  List<Map<String, dynamic>> _follows = const [];
  bool _loading = true;

  static const String _evlumbaAvatar =
      'https://xgefjepaqnghaotqybpi.supabase.co/storage/v1/object/public/koala-seed/avatars/evlumba-design.webp';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final follows = await FollowService.myFollows();
    if (!mounted) return;
    setState(() {
      _follows = follows;
      _loading = false;
    });
    ref.invalidate(userProfileProvider);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isPro = ref.watch(proStatusProvider).value?.isPro ?? false;
    final bundle = ref.watch(userProfileProvider).asData?.value;
    final profile = bundle?.profile;
    final application = bundle?.application ?? ProApplicationStatus.none;
    final stored = profile?.displayName?.trim();
    final displayName = (stored?.isNotEmpty == true
            ? stored
            : (user?.displayName ?? '').trim()) ??
        '';
    final email = user?.email ?? '';
    final name = displayName.isNotEmpty
        ? displayName
        : (email.isNotEmpty ? email.split('@').first : 'Profil');
    final photo = user?.photoURL;
    final verified = profile?.verified == true;

    return Scaffold(
      backgroundColor: KoalaColors.bg,
      appBar: AppBar(
        backgroundColor: KoalaColors.bg,
        surfaceTintColor: KoalaColors.bg,
        elevation: 0,
        title: const Text('Profil', style: KoalaText.h2),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.settings),
            color: KoalaColors.text,
            tooltip: 'Ayarlar',
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: KoalaColors.accent,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            _header(name, email, photo, isPro, verified),
            const SizedBox(height: 20),
            _stats(),
            const SizedBox(height: 22),
            _aboutSection(profile),
            const SizedBox(height: 18),
            _proSection(application, profile?.isPro == true),
            const SizedBox(height: 22),
            _followsSection(),
            const SizedBox(height: 18),
            _projectsTeaser(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _header(
      String name, String email, String? photo, bool isPro, bool verified) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _avatar(photo, isPro, verified),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: KoalaText.h2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isPro) ...[
                      const SizedBox(width: 8),
                      _proPill(),
                    ],
                  ],
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    email,
                    style: KoalaText.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(String? url, bool isPro, bool verified) {
    final hasUrl = (url ?? '').isNotEmpty;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: isPro
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
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: EdgeInsets.all(isPro ? 3 : 0),
          child: ClipOval(
            child: Container(
              color: hasUrl ? Colors.white : KoalaColors.accentSoft,
              alignment: Alignment.center,
              child: hasUrl
                  ? CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover)
                  : const Icon(LucideIcons.user,
                      size: 36, color: KoalaColors.accentDeep),
            ),
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

  Widget _proPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD66B), Color(0xFFEFA01F)],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'PRO',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: 0.4,
          height: 1.1,
        ),
      ),
    );
  }

  Widget _stats() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _statCard(
            icon: LucideIcons.folder,
            label: 'Tasarım',
            value: '—',
            onTap: _openProjects,
          ),
          const SizedBox(width: 10),
          _statCard(
            icon: LucideIcons.users,
            label: 'Takip',
            value: '${_follows.length}',
            onTap: null,
          ),
          const SizedBox(width: 10),
          _statCard(
            icon: LucideIcons.heart,
            label: 'Beğeni',
            value: '—',
            onTap: null,
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: Material(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: KoalaColors.borderSolid, width: 0.8),
            ),
            child: Column(
              children: [
                Icon(icon, size: 18, color: KoalaColors.accentDeep),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: KoalaColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(label, style: KoalaText.labelSmall),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _followsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text('TAKİP ETTİĞİN TASARIMCILAR',
              style: KoalaText.caption),
        ),
        const SizedBox(height: 10),
        if (_loading)
          const SizedBox(
              height: 80, child: Center(child: CircularProgressIndicator()))
        else if (_follows.isEmpty)
          _emptyFollows()
        else
          SizedBox(
            height: 104,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemBuilder: (_, i) => _FollowAvatar(
                designerId: _follows[i]['designer_id'] as String,
                evlumbaAvatar: _evlumbaAvatar,
              ),
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemCount: _follows.length,
            ),
          ),
      ],
    );
  }

  Widget _emptyFollows() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: KoalaColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: KoalaColors.borderSolid, width: 0.8),
        ),
        child: const Row(
          children: [
            Icon(LucideIcons.users, color: KoalaColors.accentDeep),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Henüz tasarımcı takip etmiyorsun. Bir tasarımcının profilini açıp "Takip et" diyebilirsin — yeni tasarım paylaştığında bildirim gelir.',
                style: KoalaText.bodySec,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _projectsTeaser() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: _openProjects,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: KoalaColors.borderSolid, width: 0.8),
            ),
            child: const Row(
              children: [
                Icon(LucideIcons.folder, color: KoalaColors.accentDeep),
                SizedBox(width: 12),
                Expanded(
                    child:
                        Text('Tüm tasarımlarımı gör', style: KoalaText.label)),
                Icon(LucideIcons.chevronRight,
                    size: 18, color: KoalaColors.textTer),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openProjects() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProjelerScreen()),
    );
  }

  // ─── Hakkında bölümü ───
  Widget _aboutSection(KoalaUserProfile? profile) {
    final about = (profile?.about ?? '').trim();
    final contact = profile?.contact ?? const <String, dynamic>{};
    final ig = (contact['instagram'] ?? '').toString().trim();
    final web = (contact['website'] ?? '').toString().trim();
    final hasContact = ig.isNotEmpty || web.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: KoalaColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: KoalaColors.borderSolid, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('HAKKINDA', style: KoalaText.caption),
                ),
                InkWell(
                  onTap: _openEditor,
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Text(
                      'Düzenle',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: KoalaColors.accentDeep,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (about.isEmpty)
              const Text(
                'Henüz bir tanıtım yazmadın. Kendinden, tarzından ve evinden kısaca bahset.',
                style: KoalaText.bodySec,
              )
            else
              Text(about, style: KoalaText.body),
            if (hasContact) ...[
              const SizedBox(height: 10),
              const Divider(height: 1, color: KoalaColors.borderLight),
              const SizedBox(height: 10),
              if (ig.isNotEmpty)
                _contactRow(LucideIcons.instagram, ig),
              if (web.isNotEmpty) ...[
                if (ig.isNotEmpty) const SizedBox(height: 6),
                _contactRow(LucideIcons.globe, web),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _contactRow(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: KoalaColors.accentDeep),
        const SizedBox(width: 8),
        Expanded(
          child: Text(value,
              style: KoalaText.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  // ─── Profesyonel ol kartı ───
  Widget _proSection(ProApplicationStatus app, bool isPro) {
    if (isPro || app.isApproved) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: KoalaColors.greenLight,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: KoalaColors.green.withValues(alpha: 0.3),
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              const VerifiedBadge(size: 22),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Profesyonel hesabın aktif',
                        style: KoalaText.h4),
                    SizedBox(height: 2),
                    Text(
                      'Tasarımlarını paylaşıp Koala\'da öne çıkabilirsin.',
                      style: KoalaText.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (app.isPending) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: KoalaColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: KoalaColors.accentDeep.withValues(alpha: 0.3),
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: KoalaColors.accentSoft,
                ),
                child: const Icon(LucideIcons.clock,
                    size: 18, color: KoalaColors.accentDeep),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Başvurun değerlendiriliyor',
                        style: KoalaText.h4),
                    SizedBox(height: 2),
                    Text(
                      'Evlumba ekibi en kısa sürede dönüş yapacak. Sonucu bildirim olarak alacaksın.',
                      style: KoalaText.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    final rejected = app.isRejected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: _openApplicationSheet,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: KoalaColors.accentDeep.withValues(alpha: 0.18),
                width: 0.9,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  KoalaColors.accentSoft.withValues(alpha: 0.45),
                  Colors.transparent,
                ],
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        KoalaColors.accentDeep,
                        KoalaColors.accent,
                      ],
                    ),
                  ),
                  child: const Icon(LucideIcons.badgeCheck,
                      size: 20, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Profesyonel olarak Koala\'ya katıl',
                        style: KoalaText.h4,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        rejected
                            ? 'Başvurun şu an için onaylanmadı. Bilgilerini güncelleyip tekrar dene.'
                            : 'Tasarımlarını yayınla, takipçi topla, yeşil tik kazan.',
                        style: KoalaText.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(LucideIcons.chevronRight,
                    size: 18, color: KoalaColors.textTer),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openEditor() async {
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

  Future<void> _openApplicationSheet() async {
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: KoalaColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _ProApplicationSheet(),
    );
    if (submitted == true) ref.invalidate(userProfileProvider);
  }
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
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KoalaColors.border,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
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
              borderSide: const BorderSide(
                  color: KoalaColors.accentDeep, width: 1.2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}

// ─── Profesyonel başvuru sheet ───
class _ProApplicationSheet extends StatefulWidget {
  const _ProApplicationSheet();
  @override
  State<_ProApplicationSheet> createState() => _ProApplicationSheetState();
}

class _ProApplicationSheetState extends State<_ProApplicationSheet> {
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
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KoalaColors.border,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Profesyonel başvurusu', style: KoalaText.h2),
              const SizedBox(height: 6),
              const Text(
                'Birkaç bilgi yeter. Evlumba ekibi inceleyip kısa sürede dönüş yapar; onaylandığında yeşil tik ve tasarım paylaşma yetkisi gelir.',
                style: KoalaText.bodySec,
              ),
              const SizedBox(height: 18),
              _field(_fullName, label: 'Ad Soyad', hint: 'Tam adın'),
              const SizedBox(height: 12),
              _field(_profession,
                  label: 'Meslek / Uzmanlık',
                  hint: 'ör. İç Mimar, Mobilya Tasarımcısı'),
              const SizedBox(height: 12),
              _field(_city, label: 'Şehir', hint: 'İstanbul, İzmir…'),
              const SizedBox(height: 12),
              _field(_ig, label: 'Instagram', hint: '@kullaniciadi veya link'),
              const SizedBox(height: 12),
              _field(_portfolio,
                  label: 'Portföy / Web', hint: 'https://… (varsa)'),
              const SizedBox(height: 12),
              _field(_reason,
                  label: 'Birkaç cümle (opsiyonel)',
                  hint: 'Tarzın, deneyimin, neden Koala\'da olmak istiyorsun?',
                  maxLines: 3),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(
                        color: KoalaColors.error, fontSize: 13)),
              ],
              const SizedBox(height: 18),
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
                  child: Text(_submitting ? 'Gönderiliyor…' : 'Başvuruyu gönder',
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
              borderSide: const BorderSide(
                  color: KoalaColors.accentDeep, width: 1.2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}

class _FollowAvatar extends StatefulWidget {
  final String designerId;
  final String evlumbaAvatar;
  const _FollowAvatar({required this.designerId, required this.evlumbaAvatar});

  @override
  State<_FollowAvatar> createState() => _FollowAvatarState();
}

class _FollowAvatarState extends State<_FollowAvatar> {
  String? _name;
  String? _avatar;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.designerId == 'evlumba-design') {
      if (mounted) {
        setState(() {
          _name = 'Evlumba Design';
          _avatar = widget.evlumbaAvatar;
          _loading = false;
        });
      }
      return;
    }
    try {
      final d = await EvlumbaLiveService.getDesigner(widget.designerId);
      if (!mounted) return;
      setState(() {
        _name = (d?['full_name'] ?? d?['business_name'] ?? 'Tasarımcı')
            .toString();
        _avatar = (d?['avatar_url'] ?? '').toString();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = (_avatar ?? '').isNotEmpty;
    final verified = isVerifiedDesignerId(widget.designerId);
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: KoalaColors.accentSoft,
                ),
                clipBehavior: Clip.antiAlias,
                child: hasUrl
                    ? CachedNetworkImage(
                        imageUrl: _avatar!,
                        fit: BoxFit.cover,
                        placeholder: (_, _) =>
                            Container(color: KoalaColors.accentSoft),
                        errorWidget: (_, _, _) => const Icon(LucideIcons.user,
                            color: KoalaColors.accentDeep),
                      )
                    : Center(
                        child: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(LucideIcons.user,
                                color: KoalaColors.accentDeep),
                      ),
              ),
              if (verified)
                const Positioned(
                  right: -2,
                  bottom: -2,
                  child: VerifiedBadge(size: 18),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _name ?? '…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: KoalaColors.text,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}
