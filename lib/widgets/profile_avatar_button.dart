import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/koala_tokens.dart';

/// Sağ üst köşedeki profil ikonu — anasayfa/mesajlar/swipe/projelerim'de
/// tutarlı yer alır. Tıklayınca /profile route'una gider.
class ProfileAvatarButton extends StatelessWidget {
  final double size;
  const ProfileAvatarButton({super.key, this.size = 38});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Material(
      color: KoalaColors.accentSoft,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => context.push('/profile'),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: KoalaColors.accentSoft,
            border: Border.all(
              color: KoalaColors.accentDeep.withValues(alpha: 0.18),
              width: 0.8,
            ),
            image: user?.photoURL != null
                ? DecorationImage(
                    image: CachedNetworkImageProvider(user!.photoURL!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: user?.photoURL == null
              ? Icon(
                  LucideIcons.user,
                  size: size * 0.45,
                  color: KoalaColors.accentDeep,
                )
              : null,
        ),
      ),
    );
  }
}
