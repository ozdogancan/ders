import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/theme/koala_tokens.dart';

/// CachedNetworkImage wrapper — lazy loading, fade-in, memory cache boyutu
class OptimizedImage extends StatelessWidget {
  const OptimizedImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.borderRadius = KoalaRadius.md,
    this.fit = BoxFit.cover,
  });

  final String url;
  final double? width;
  final double? height;
  final double borderRadius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CachedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: fit,
        memCacheWidth: width != null ? (width! * MediaQuery.of(context).devicePixelRatio).toInt() : 600,
        memCacheHeight: height != null ? (height! * MediaQuery.of(context).devicePixelRatio).toInt() : null,
        fadeInDuration: const Duration(milliseconds: 300),
        placeholder: (_, __) => Container(
          width: width,
          height: height,
          color: KoalaColors.surfaceAlt,
        ),
        errorWidget: (_, __, ___) => Container(
          width: width,
          height: height,
          color: KoalaColors.surfaceAlt,
          child: const Icon(Icons.broken_image_rounded, color: KoalaColors.textTer, size: 24),
        ),
      ),
    );
  }
}
