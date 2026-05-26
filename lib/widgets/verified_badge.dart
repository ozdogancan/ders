import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/koala_tokens.dart';

/// Onaylı profesyonel rozeti — Twitter/Instagram benzeri yeşil tik.
/// Boyut [size] avatar yanında / kart üstünde kullanıma göre ayarlanır.
class VerifiedBadge extends StatelessWidget {
  final double size;
  final Color background;
  const VerifiedBadge({
    super.key,
    this.size = 14,
    this.background = KoalaColors.green,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background,
        border: Border.all(
          color: Colors.white,
          width: size > 18 ? 2.0 : 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: background.withValues(alpha: 0.30),
            blurRadius: size * 0.4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Icon(
        LucideIcons.check,
        size: size * 0.62,
        color: Colors.white,
      ),
    );
  }
}

/// Evlumba marketplace'ten gelen tüm tasarımcılar + 'evlumba-design' sentetik
/// stüdyo — verified kabul edilir.
bool isVerifiedDesignerId(String designerId) {
  if (designerId.isEmpty) return false;
  // evlumba-design synthetic studio
  if (designerId == 'evlumba-design') return true;
  // Diğer designer_id'ler UUID şeklinde (Evlumba designer_projects.designer_id).
  // Hepsi marketplace üyesi — onaylı kabul edilir.
  return true;
}
