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

/// Evlumba marketplace tasarımcıları + 'evlumba-design' sentetik stüdyo
/// verified kabul edilir. EV SAHİPLERİ (normal Koala kullanıcısı) verified
/// DEĞİL — onların id'si Firebase uid (UUID değil), tasarımcılarınki ise
/// Evlumba designer_projects.designer_id = UUID. Bu yüzden UUID formatı
/// kontrol edilir: UUID → tasarımcı (verified), Firebase uid → ev sahibi (hayır).
final RegExp _kUuidRe = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool isVerifiedDesignerId(String designerId) {
  if (designerId.isEmpty) return false;
  if (designerId == 'evlumba-design') return true;
  return _kUuidRe.hasMatch(designerId);
}
