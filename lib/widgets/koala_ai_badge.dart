import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/koala_tokens.dart';

/// 2026-06-02: "Koala AI ile üretildi" rozeti — İKON DEĞİL, şık bir metin
/// wordmark'ı (kullanıcı isteği: "simge olmasın, güzel bir şekilde 'Koala AI'
/// yazsın, trademark gibi"). Küçük sparkle + "Koala AI" metni, mor gradient
/// pill. AI ile üretilen tasarımlarda (profil grid, detay, keşfet swipe) tutarlı.
class KoalaAiBadge extends StatelessWidget {
  const KoalaAiBadge({super.key, this.size = 30, this.compact = false});

  /// Geriye dönük uyum için tutuluyor; metin pill'inde yükseklik ölçeği olarak
  /// kullanılır (büyük değer → biraz daha büyük pill).
  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scale = (size / 30).clamp(0.85, 1.25);
    final fontSize = 11.5 * scale;
    final iconSize = 12.0 * scale;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 9 * scale,
        vertical: 5 * scale,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C6CF0), Color(0xFF5B4BD6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(100),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.sparkles, size: iconSize, color: Colors.white),
          SizedBox(width: 5 * scale),
          Text(
            'Koala AI',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.1,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
