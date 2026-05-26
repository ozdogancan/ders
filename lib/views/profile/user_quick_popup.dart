// Tiny modal bottom-sheet popup showing a user peek.
// avatar (tap → enlarge), name + role chip, 1-line bio, "Profili gör" CTA.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/koala_tokens.dart';
import '../../services/user_profile_service.dart';
import '../designer_profile_screen.dart';
import 'profile_photo_view.dart';

class UserQuickPopup extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final name = (user.displayName?.trim().isNotEmpty == true)
        ? user.displayName!.trim()
        : 'Koala kullanıcısı';
    final hasAvatar = (user.avatarUrl ?? '').isNotEmpty;
    final about = (user.about ?? '').trim();
    final tag = 'quickpop-${user.uid}';

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
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DesignerProfileScreen(
                        designerId: user.uid,
                        designerName: user.displayName,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: KoalaColors.accentDeep,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text('Profili gör', style: KoalaText.button),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

