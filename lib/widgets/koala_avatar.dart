import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Swappable Koala AI avatar. Loads from Supabase Storage with bundled fallback.
///
/// To swap the avatar:
///   1. Generate a square WebP via Gemini (recommend 512×512 transparent bg)
///   2. Upload to Supabase Storage → bucket `pro-assets` → file `koala-avatar.webp`
///   3. New avatar appears across the app on next image cache miss
///
/// Until uploaded, the bundled `assets/images/koalas.webp` is shown.
class KoalaAvatar extends StatelessWidget {
  final double size;
  final BoxFit fit;
  const KoalaAvatar({super.key, this.size = 56, this.fit = BoxFit.cover});

  static const _remoteUrl =
      'https://xgefjepaqnghaotqybpi.supabase.co/storage/v1/object/public/pro-assets/koala-avatar.webp';
  static const _fallbackAsset = 'assets/images/koalas.webp';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: _remoteUrl,
          fit: fit,
          width: size,
          height: size,
          // While loading or on error → bundled asset (instant, no flicker)
          placeholder: (_, __) =>
              Image.asset(_fallbackAsset, fit: fit, width: size, height: size),
          errorWidget: (_, __, ___) =>
              Image.asset(_fallbackAsset, fit: fit, width: size, height: size),
          memCacheWidth: (size * 3).round(),
        ),
      ),
    );
  }
}
