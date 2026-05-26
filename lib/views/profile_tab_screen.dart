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
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isPro = ref.watch(proStatusProvider).value?.isPro ?? false;
    final displayName = (user?.displayName ?? '').trim();
    final email = user?.email ?? '';
    final name = displayName.isNotEmpty
        ? displayName
        : (email.isNotEmpty ? email.split('@').first : 'Profil');
    final photo = user?.photoURL;

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
            _header(name, email, photo, isPro),
            const SizedBox(height: 20),
            _stats(),
            const SizedBox(height: 24),
            _followsSection(),
            const SizedBox(height: 20),
            _projectsTeaser(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _header(String name, String email, String? photo, bool isPro) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _avatar(photo, isPro),
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

  Widget _avatar(String? url, bool isPro) {
    final hasUrl = (url ?? '').isNotEmpty;
    return Container(
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
    return SizedBox(
      width: 72,
      child: Column(
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
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(LucideIcons.user,
                            color: KoalaColors.accentDeep),
                  ),
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
