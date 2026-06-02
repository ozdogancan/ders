import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 2026-06-02: "Koala AI ile üretildi" rozeti. Küçük, sade, göze hoş; Gemini
/// ile üretilen Koala-AI amblemini gösterir. AI ile oluşturulan tasarımlarda
/// (profil grid, detay görüntüleyici, keşfet swipe) tutarlı kullanılır.
class KoalaAiBadge extends StatelessWidget {
  const KoalaAiBadge({super.key, this.size = 30});

  final double size;

  static const String _url =
      'https://xgefjepaqnghaotqybpi.supabase.co/storage/v1/object/public/koala-seed/icons/ai-badge-v2.webp';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(1.5),
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: _url,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 150),
          placeholder: (_, __) => const SizedBox.shrink(),
          errorWidget: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}
