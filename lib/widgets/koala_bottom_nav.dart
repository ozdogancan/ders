import 'dart:ui' as ui show ImageFilter;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/koala_tokens.dart';

/// Glassmorphism alt navigasyon — snaphome benzeri, floating, rounded pill.
/// 4 sekme: Ana Sayfa | Mesajlar | Swipe | Projeler. Seçili sekme accentSoft
/// dolgulu ve büyütülmüş.
class KoalaBottomNav extends StatelessWidget {
  final KoalaTab current;
  final void Function(KoalaTab) onSelect;
  final int unreadMessages;

  const KoalaBottomNav({
    super.key,
    required this.current,
    required this.onSelect,
    this.unreadMessages = 0,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return SafeArea(
      top: false,
      minimum: EdgeInsets.only(bottom: bottom > 0 ? 6 : 14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(38),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(38),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.72),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: KoalaColors.accent.withValues(alpha: 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NavItem(
                    icon: LucideIcons.home,
                    label: 'Ana Sayfa',
                    selected: current == KoalaTab.home,
                    onTap: () => onSelect(KoalaTab.home),
                  ),
                  _NavItem(
                    icon: LucideIcons.messageCircle,
                    label: 'Mesajlar',
                    selected: current == KoalaTab.chat,
                    badge: unreadMessages,
                    onTap: () => onSelect(KoalaTab.chat),
                  ),
                  _NavItem(
                    icon: LucideIcons.sparkles,
                    label: 'Swipe',
                    selected: current == KoalaTab.swipe,
                    onTap: () => onSelect(KoalaTab.swipe),
                  ),
                  _NavItem(
                    icon: LucideIcons.folder,
                    label: 'Projeler',
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

enum KoalaTab { home, chat, swipe, projeler }

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        // İstenmeyen "ışık sönmesi" → splash/highlight kapalı.
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        child: Container(
          // Animation YOK — sekme değişiminde fade-out şovu görünmesin.
          padding: EdgeInsets.symmetric(
            horizontal: selected ? 18 : 14,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      KoalaColors.accentDeep,
                      KoalaColors.accent,
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(30),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: KoalaColors.accent.withValues(alpha: 0.36),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    size: 21,
                    color: selected ? Colors.white : KoalaColors.textSec,
                  ),
                  if (badge > 0)
                    Positioned(
                      top: -5,
                      right: -7,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: KoalaColors.error,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                              color: Colors.white, width: 1.4),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          badge > 9 ? '9+' : '$badge',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
