import 'dart:ui' as ui show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/koala_tokens.dart';

/// Alt nav — 4 hedef + ortada "Paylaş" FAB.
///
/// Sekmeler L→R: Ana Sayfa | Mesajlar | [Paylaş] | AI | Projeler.
/// Paylaş bir tab değil, bir aksiyondur — foto yükleyip MekanWizard'a girer.
///
/// Görsel: floating glass-pill (önceki nav'la aynı silüet), seçili durumda
/// göze batmayan ince renk + minik scale + bold-leşen etiket. Geçişler
/// AnimatedScale / AnimatedDefaultTextStyle ile yumuşak.
class KoalaBottomNav extends StatelessWidget {
  final KoalaTab current;
  final void Function(KoalaTab) onSelect;
  final VoidCallback onPaylasTap;
  final int unreadMessages;
  // Optional anchor keys — coachmark overlay attaches its spotlights to these
  // render boxes. Null in normal usage; supplied by MainShell.
  final GlobalKey? homeKey;
  final GlobalKey? chatKey;
  final GlobalKey? paylasKey;
  final GlobalKey? aiKey;
  final GlobalKey? profileKey;

  const KoalaBottomNav({
    super.key,
    required this.current,
    required this.onSelect,
    required this.onPaylasTap,
    this.unreadMessages = 0,
    this.homeKey,
    this.chatKey,
    this.paylasKey,
    this.aiKey,
    this.profileKey,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return SafeArea(
      top: false,
      minimum: EdgeInsets.only(bottom: bottom > 0 ? 8 : 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.68),
                borderRadius: BorderRadius.circular(34),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.7),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: KoalaColors.accent.withValues(alpha: 0.05),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _NavItem(
                    anchorKey: homeKey,
                    icon: LucideIcons.home,
                    label: 'Ana Sayfa',
                    selected: current == KoalaTab.home,
                    onTap: () => onSelect(KoalaTab.home),
                  ),
                  _NavItem(
                    anchorKey: chatKey,
                    icon: LucideIcons.messageCircle,
                    label: 'Mesajlar',
                    selected: current == KoalaTab.chat,
                    badge: unreadMessages,
                    onTap: () => onSelect(KoalaTab.chat),
                  ),
                  _PaylasFab(anchorKey: paylasKey, onTap: onPaylasTap),
                  _NavItem(
                    anchorKey: aiKey,
                    icon: LucideIcons.sparkles,
                    label: 'AI',
                    selected: current == KoalaTab.ai,
                    onTap: () => onSelect(KoalaTab.ai),
                  ),
                  _ProfileNavItem(
                    anchorKey: profileKey,
                    selected: current == KoalaTab.projeler,
                    onTap: () => onSelect(KoalaTab.projeler),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum KoalaTab { home, chat, ai, projeler }

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;
  final GlobalKey? anchorKey;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
    this.anchorKey,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? KoalaColors.accentDeep : KoalaColors.textSec;
    return Expanded(
      key: anchorKey,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedScale(
                    scale: selected ? 1.08 : 1.0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutBack,
                    child: Icon(icon, size: 22, color: color),
                  ),
                  const SizedBox(height: 3),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 220),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                      letterSpacing: -0.1,
                    ),
                    child: Text(label),
                  ),
                ],
              ),
              // Unread dot — sayı YOK, sadece temiz kırmızı nokta.
              // Kullanıcı isteği: "nokta şeklinde bildirim".
              if (badge > 0)
                Positioned(
                  top: 6,
                  right: 18,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: KoalaColors.error,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.6),
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

/// Profil nav slotu — kullanıcının avatarı varsa CircleAvatar olarak gösterir;
/// yoksa user ikonuna düşer. Aktif sekmede ince mor halka + minik scale.
class _ProfileNavItem extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final GlobalKey? anchorKey;
  const _ProfileNavItem({
    required this.selected,
    required this.onTap,
    this.anchorKey,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? KoalaColors.accentDeep : KoalaColors.textSec;
    return Expanded(
      key: anchorKey,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: selected ? 1.06 : 1.0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                child: StreamBuilder<User?>(
                  stream: FirebaseAuth.instance.userChanges(),
                  builder: (context, snap) {
                    final user =
                        snap.data ?? FirebaseAuth.instance.currentUser;
                    final url = user?.photoURL ?? '';
                    if (url.isEmpty) {
                      return Icon(LucideIcons.user, size: 22, color: color);
                    }
                    // Polished round avatar: solid 30px, brand ring on active,
                    // subtle border off-state, soft glow on selection.
                    return Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? KoalaColors.accentDeep
                              : KoalaColors.border,
                          width: selected ? 2 : 1,
                        ),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: KoalaColors.accentDeep
                                      .withValues(alpha: 0.22),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        fadeInDuration: const Duration(milliseconds: 120),
                        placeholder: (_, _) =>
                            Container(color: KoalaColors.accentSoft),
                        errorWidget: (_, _, _) => Icon(
                          LucideIcons.user,
                          size: 18,
                          color: color,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                  letterSpacing: -0.1,
                ),
                child: const Text('Profil'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaylasFab extends StatelessWidget {
  final VoidCallback onTap;
  final GlobalKey? anchorKey;
  const _PaylasFab({required this.onTap, this.anchorKey});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              key: anchorKey,
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [KoalaColors.accentDeep, KoalaColors.accent],
                ),
                boxShadow: [
                  BoxShadow(
                    color: KoalaColors.accent.withValues(alpha: 0.38),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Icon(LucideIcons.plus, size: 24, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
