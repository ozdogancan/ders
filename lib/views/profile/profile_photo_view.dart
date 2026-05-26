// Fullscreen Hero zoom view for the profile avatar.
// Pinch-to-zoom + tap-to-dismiss. Black backdrop.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

class ProfilePhotoView extends StatelessWidget {
  final String url;
  final String heroTag;
  const ProfilePhotoView({super.key, required this.url, required this.heroTag});

  static Future<void> open(BuildContext context,
      {required String url, required String heroTag}) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) =>
            ProfilePhotoView(url: url, heroTag: heroTag),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Stack(
            children: [
              Center(
                child: Hero(
                  tag: heroTag,
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: url.isEmpty
                        ? const Icon(LucideIcons.user,
                            size: 120, color: Colors.white24)
                        : CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.contain,
                            errorWidget: (_, _, _) => const Icon(
                              LucideIcons.imageOff,
                              color: Colors.white38,
                              size: 64,
                            ),
                          ),
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 12,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(LucideIcons.x, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Helper to share avatar heroTag between profile screen and viewer.
String profilePhotoHeroTag(String uid) => 'profile-photo-$uid';
