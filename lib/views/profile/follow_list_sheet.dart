// Instagram-pattern followers/following bottom sheet.
// - Tap row → MiniProfileSheet for a peek.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/koala_tokens.dart';
import '../../services/follow_service.dart';
import '../../services/user_profile_service.dart';
import 'mini_profile_sheet.dart';

enum FollowListMode { followers, following }

class FollowListSheet extends ConsumerStatefulWidget {
  final String ownerUid;
  final FollowListMode mode;
  const FollowListSheet({
    super.key,
    required this.ownerUid,
    required this.mode,
  });

  static Future<void> open(
    BuildContext context, {
    required String ownerUid,
    required FollowListMode mode,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: KoalaColors.bg,
      isScrollControlled: true,
      enableDrag: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => FollowListSheet(ownerUid: ownerUid, mode: mode),
    );
  }

  @override
  ConsumerState<FollowListSheet> createState() => _FollowListSheetState();
}

class _FollowListSheetState extends ConsumerState<FollowListSheet> {
  bool _loading = true;
  List<KoalaUserProfile> _users = const [];
  // local toggle cache for following state per uid
  final Map<String, bool> _followingCache = {};

  // Client-side search filter.
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim().toLowerCase();
      if (q == _query) return;
      setState(() => _query = q);
    });
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<KoalaUserProfile> get _filtered {
    if (_query.isEmpty) return _users;
    return _users.where((u) {
      final n = (u.displayName ?? '').toLowerCase();
      return n.contains(_query);
    }).toList();
  }

  Future<void> _load() async {
    try {
      final ids = widget.mode == FollowListMode.followers
          ? await FollowService.followerIds(widget.ownerUid)
          : await FollowService.followingIds(widget.ownerUid);
      final users = await UserProfileService.getMany(ids);
      // Preserve original ids order
      final byUid = {for (final u in users) u.uid: u};
      final ordered = <KoalaUserProfile>[];
      for (final id in ids) {
        final u = byUid[id];
        if (u != null) {
          ordered.add(u);
        } else {
          ordered.add(KoalaUserProfile(uid: id));
        }
      }
      if (!mounted) return;
      setState(() {
        _users = ordered;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Liste yüklenemedi')),
      );
    }
  }

  Future<void> _toggleFollow(String designerId) async {
    final st = await FollowService.toggle(designerId);
    if (!mounted) return;
    setState(() => _followingCache[designerId] = st.following);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.mode == FollowListMode.followers
        ? 'Takipçiler'
        : 'Takip Edilenler';
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: KoalaColors.border,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const SizedBox(height: 12),
            Text(title, style: KoalaText.h3),
            const SizedBox(height: 8),
            const Divider(height: 1, color: KoalaColors.borderSolid),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: TextField(
                controller: _searchCtrl,
                style: KoalaText.body,
                decoration: InputDecoration(
                  hintText: 'Ara...',
                  hintStyle: KoalaText.hint,
                  prefixIcon: const Icon(LucideIcons.search,
                      size: 16, color: KoalaColors.textTer),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                  isDense: true,
                  filled: true,
                  fillColor: KoalaColors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: KoalaColors.borderSolid, width: 0.6),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: KoalaColors.borderSolid, width: 0.6),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: KoalaColors.accentDeep, width: 1.2),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: KoalaColors.accentDeep,
                        strokeWidth: 2,
                      ),
                    )
                  : _filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              _query.isNotEmpty
                                  ? 'Eşleşen kullanıcı yok.'
                                  : (widget.mode == FollowListMode.followers
                                      ? 'Henüz takipçi yok.'
                                      : 'Henüz kimseyi takip etmiyor.'),
                              style: KoalaText.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final u = _filtered[i];
                            final isSelf = u.uid == myUid;
                            final isFollowing =
                                _followingCache[u.uid] ?? false;
                            return _FollowRow(
                              user: u,
                              isSelf: isSelf,
                              followingKnown:
                                  _followingCache.containsKey(u.uid),
                              isFollowing: isFollowing,
                              onToggle: () => _toggleFollow(u.uid),
                              onTap: () => MiniProfileSheet.open(
                                context,
                                user: u,
                              ),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }
}

class _FollowRow extends StatelessWidget {
  final KoalaUserProfile user;
  final bool isSelf;
  final bool followingKnown;
  final bool isFollowing;
  final VoidCallback onToggle;
  final VoidCallback onTap;
  const _FollowRow({
    required this.user,
    required this.isSelf,
    required this.followingKnown,
    required this.isFollowing,
    required this.onToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = (user.displayName?.trim().isNotEmpty == true)
        ? user.displayName!.trim()
        : 'Koala kullanıcısı';
    final hasAvatar = (user.avatarUrl ?? '').isNotEmpty;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KoalaColors.accentSoft,
                border: Border.all(color: KoalaColors.borderSolid, width: 0.6),
              ),
              clipBehavior: Clip.antiAlias,
              child: hasAvatar
                  ? CachedNetworkImage(
                      imageUrl: user.avatarUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const Icon(
                        LucideIcons.user,
                        color: KoalaColors.accentDeep,
                        size: 22,
                      ),
                    )
                  : const Icon(LucideIcons.user,
                      color: KoalaColors.accentDeep, size: 22),
            ),
            const SizedBox(width: 12),
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
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: KoalaColors.text,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (user.isPro) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: KoalaColors.accentSoft,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Pro',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: KoalaColors.accentDeep,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if ((user.about ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        user.about!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: KoalaColors.textSec,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            if (!isSelf)
              SizedBox(
                height: 32,
                child: OutlinedButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    onToggle();
                  },
                  style: OutlinedButton.styleFrom(
                    backgroundColor: (followingKnown && isFollowing)
                        ? KoalaColors.surface
                        : KoalaColors.accentDeep,
                    foregroundColor: (followingKnown && isFollowing)
                        ? KoalaColors.text
                        : Colors.white,
                    side: BorderSide(
                      color: (followingKnown && isFollowing)
                          ? KoalaColors.borderSolid
                          : KoalaColors.accentDeep,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    minimumSize: const Size(0, 32),
                  ),
                  child: Text(
                    (followingKnown && isFollowing) ? 'Takipte' : 'Takip et',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
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

