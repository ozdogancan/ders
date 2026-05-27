// Non-designer kullanıcılar için hafif profil bottom-sheet.
// - Avatar, isim, "Üye" rozeti, bio
// - Takip / Takipte pill (toggle)
// - X tasarım · Y takipçi satırı (async optimistik)
// - Public paylaşımlardan küçük grid (max 6)

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../core/theme/koala_tokens.dart';
import '../../services/follow_service.dart';
import '../../services/user_profile_service.dart';
import 'profile_photo_view.dart';

class UserProfileSheet extends ConsumerStatefulWidget {
  final KoalaUserProfile user;
  const UserProfileSheet({super.key, required this.user});

  static Future<void> open(BuildContext context,
      {required KoalaUserProfile user}) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: KoalaColors.bg,
      isScrollControlled: true,
      enableDrag: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => UserProfileSheet(user: user),
    );
  }

  @override
  ConsumerState<UserProfileSheet> createState() => _UserProfileSheetState();
}

class _UserProfileSheetState extends ConsumerState<UserProfileSheet> {
  bool? _isFollowing;
  bool _busy = false;
  int _followers = 0;
  int _designs = 0;
  List<Map<String, dynamic>> _shared = const [];

  @override
  void initState() {
    super.initState();
    _loadAsync();
  }

  Future<void> _loadAsync() async {
    // Optimistik: hızlı sayaçlar + takip durumu paralel.
    final stF = FollowService.stateFor(widget.user.uid);
    final cntF = FollowService.counts(widget.user.uid);
    final sharedF = _loadShared();

    final results = await Future.wait([stF, cntF, sharedF]);
    if (!mounted) return;
    final st = results[0] as FollowState;
    final cnt = results[1] as ({int followers, int following});
    final shared = results[2] as List<Map<String, dynamic>>;
    setState(() {
      _isFollowing = st.following;
      _followers = cnt.followers;
      _designs = shared.length;
      _shared = shared;
    });
  }

  Future<List<Map<String, dynamic>>> _loadShared() async {
    try {
      final data = await Supabase.instance.client
          .from('koala_user_shared_designs')
          .select('id, image_url, thumb_url, title')
          .eq('user_id', widget.user.uid)
          .eq('status', 'published')
          .order('published_at', ascending: false)
          .limit(6);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _toggleFollow() async {
    if (_busy) return;
    setState(() => _busy = true);
    final prev = _isFollowing ?? false;
    // optimistik
    setState(() {
      _isFollowing = !prev;
      _followers += prev ? -1 : 1;
    });
    try {
      final st = await FollowService.toggle(widget.user.uid);
      if (!mounted) return;
      setState(() => _isFollowing = st.following);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFollowing = prev;
        _followers += prev ? 1 : -1;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Takip işlemi başarısız oldu')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final name = (user.displayName?.trim().isNotEmpty == true)
        ? user.displayName!.trim()
        : 'Koala kullanıcısı';
    final hasAvatar = (user.avatarUrl ?? '').isNotEmpty;
    final about = (user.about ?? '').trim();
    final tag = 'usrsheet-${user.uid}';
    final followKnown = _isFollowing != null;
    final following = _isFollowing == true;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KoalaColors.border,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
                const SizedBox(height: 18),
                GestureDetector(
                  onTap: hasAvatar
                      ? () {
                          HapticFeedback.selectionClick();
                          ProfilePhotoView.open(context,
                              url: user.avatarUrl!, heroTag: tag);
                        }
                      : null,
                  child: Hero(
                    tag: tag,
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: KoalaColors.accentSoft,
                        border: Border.all(
                            color: KoalaColors.borderSolid, width: 0.6),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: hasAvatar
                          ? CachedNetworkImage(
                              imageUrl: user.avatarUrl!, fit: BoxFit.cover)
                          : const Icon(LucideIcons.user,
                              size: 36, color: KoalaColors.accentDeep),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: KoalaText.h3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: KoalaColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: KoalaColors.borderSolid, width: 0.6),
                      ),
                      child: const Text(
                        'Üye',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: KoalaColors.textSec,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // counts line
                Text(
                  '$_designs tasarım · $_followers takipçi',
                  style: const TextStyle(
                    fontSize: 12,
                    color: KoalaColors.textSec,
                  ),
                ),
                if (about.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    about,
                    style: KoalaText.bodySmall,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _busy ? null : _toggleFollow,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: (followKnown && following)
                          ? KoalaColors.surface
                          : KoalaColors.accentDeep,
                      foregroundColor: (followKnown && following)
                          ? KoalaColors.text
                          : Colors.white,
                      side: BorderSide(
                        color: (followKnown && following)
                            ? KoalaColors.borderSolid
                            : KoalaColors.accentDeep,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      !followKnown
                          ? 'Yükleniyor…'
                          : (following ? 'Takipte' : 'Takip et'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (_shared.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Paylaşımları',
                      style: KoalaText.label,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _shared.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                      childAspectRatio: 1,
                    ),
                    itemBuilder: (_, i) {
                      final it = _shared[i];
                      final url = (it['thumb_url'] ?? it['image_url'] ?? '')
                          .toString();
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: url.isEmpty
                            ? Container(color: KoalaColors.accentSoft)
                            : CachedNetworkImage(
                                imageUrl: url,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  color: KoalaColors.accentSoft,
                                  child: const Icon(LucideIcons.image,
                                      color: KoalaColors.accentDeep, size: 20),
                                ),
                              ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
