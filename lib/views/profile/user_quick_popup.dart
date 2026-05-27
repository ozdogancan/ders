// Tiny modal bottom-sheet popup showing a user peek.
// avatar (tap → enlarge), name + role chip, 1-line bio.
// - Takip / Takipte pill toggles follow.
// - "Profili gör" CTA:
//     designer (profiles tablosunda satırı var) → DesignerProfileScreen
//     normal kullanıcı → UserProfileSheet (hafif user profili)

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/koala_tokens.dart';
import '../../services/follow_service.dart';
import '../../services/user_profile_service.dart';
import '../designer_profile_screen.dart';
import 'profile_photo_view.dart';
import 'user_profile_sheet.dart';

class UserQuickPopup extends StatefulWidget {
  final KoalaUserProfile user;
  const UserQuickPopup({super.key, required this.user});

  static Future<void> open(BuildContext context,
      {required KoalaUserProfile user}) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: KoalaColors.bg,
      isScrollControlled: false,
      enableDrag: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => UserQuickPopup(user: user),
    );
  }

  @override
  State<UserQuickPopup> createState() => _UserQuickPopupState();
}

class _UserQuickPopupState extends State<UserQuickPopup> {
  bool? _isDesigner;
  bool? _isFollowing;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _isDesigner = widget.user.isPro ? true : null;
    _loadAsync();
  }

  Future<void> _loadAsync() async {
    // designer probe + takip durumu paralel
    final designerF = widget.user.isPro
        ? Future.value(true)
        : UserProfileService.isDesigner(widget.user.uid);
    final followF = FollowService.stateFor(widget.user.uid);
    final results = await Future.wait([designerF, followF]);
    if (!mounted) return;
    setState(() {
      _isDesigner = results[0] as bool;
      _isFollowing = (results[1] as FollowState).following;
    });
  }

  Future<void> _toggleFollow() async {
    if (_busy) return;
    setState(() => _busy = true);
    final prev = _isFollowing ?? false;
    setState(() => _isFollowing = !prev);
    try {
      final st = await FollowService.toggle(widget.user.uid);
      if (!mounted) return;
      setState(() => _isFollowing = st.following);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isFollowing = prev);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openFullProfile() {
    Navigator.of(context).pop();
    // Designer durumu henüz yüklenmediyse defansif: user sheet aç.
    if (_isDesigner == true) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DesignerProfileScreen(
            designerId: widget.user.uid,
            designerName: widget.user.displayName,
          ),
        ),
      );
    } else {
      UserProfileSheet.open(context, user: widget.user);
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
    final tag = 'quickpop-${user.uid}';
    final followKnown = _isFollowing != null;
    final following = _isFollowing == true;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
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
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KoalaColors.accentSoft,
                    border:
                        Border.all(color: KoalaColors.borderSolid, width: 0.6),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: hasAvatar
                      ? CachedNetworkImage(
                          imageUrl: user.avatarUrl!, fit: BoxFit.cover)
                      : const Icon(LucideIcons.user,
                          size: 32, color: KoalaColors.accentDeep),
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
                if (user.isPro || _isDesigner == true) ...[
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
                      ),
                    ),
                  ),
                ] else if (_isDesigner == false) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: KoalaColors.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: KoalaColors.borderSolid, width: 0.6),
                    ),
                    child: const Text(
                      'Üye',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: KoalaColors.textSec,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (about.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                about,
                style: KoalaText.bodySmall,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 14),
            // Takip pill
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: !followKnown || _busy ? null : _toggleFollow,
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
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  !followKnown
                      ? 'Yükleniyor…'
                      : (following ? 'Takipte' : 'Takip et'),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _openFullProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: KoalaColors.surface,
                  foregroundColor: KoalaColors.text,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(
                        color: KoalaColors.borderSolid, width: 0.6),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Profili gör',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: KoalaColors.text,
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
