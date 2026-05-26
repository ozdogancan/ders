import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/koala_tokens.dart';

/// AI Araçları sekmesi için sectioned tool launcher.
///
/// Tasarım dili:
///   - Tüm başlıklar SOL hizalı (Notion / Linear / Things 3 estetiği)
///   - Kart yerine satır-tabanlı dense layout — leading icon square + başlık +
///     1-line subtitle + trailing chevron. Beyaz surface, hairline border.
///   - Bölümler arası geniş ritim (24-28px); satırlar arası 0 gap (continuous
///     card içinde divider).
///   - Marka rengi (KoalaColors.accent/accentDeep) sadece icon kareleri için
///     soft tint olarak kullanılır. Renk dolgusu yok — premium calmness.
class AiToolsSection extends StatelessWidget {
  const AiToolsSection({
    super.key,
    required this.onRestyle,
    required this.onStyleDiscovery,
    required this.onMoodBoard,
    required this.onBudget,
    required this.onColorAdvice,
    required this.onDesignerMatch,
    required this.onBeforeAfter,
    required this.onFreeChat,
  });

  final VoidCallback onRestyle;
  final VoidCallback onStyleDiscovery;
  final VoidCallback onMoodBoard;
  final VoidCallback onBudget;
  final VoidCallback onColorAdvice;
  final VoidCallback onDesignerMatch;
  final VoidCallback onBeforeAfter;
  final VoidCallback onFreeChat;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Section: Tasarım ───
          const _SectionHeader(
            eyebrow: 'Tasarım',
            title: 'Mekânını şekillendir',
            subtitle: 'Foto yükle, sonucu saniyeler içinde gör.',
          ),
          const SizedBox(height: 14),
          _ToolGroup(
            tools: [
              _ToolItem(
                icon: LucideIcons.wand2,
                title: 'Yeniden Tasarla',
                subtitle: 'Mevcut odanı seçtiğin stille restyle et',
                badge: _ToolBadge.pro,
                onTap: onRestyle,
              ),
              _ToolItem(
                icon: LucideIcons.layoutGrid,
                title: 'Mood Board',
                subtitle: 'Renk + doku + ürün kompozisyonu hazırla',
                badge: _ToolBadge.yeni,
                onTap: onMoodBoard,
              ),
              _ToolItem(
                icon: LucideIcons.arrowLeftRight,
                title: 'Önce / Sonra',
                subtitle: 'Eski ve yeni halini yan yana karşılaştır',
                onTap: onBeforeAfter,
              ),
            ],
          ),

          const SizedBox(height: 28),

          // ─── Section: Keşfet ───
          const _SectionHeader(
            eyebrow: 'Keşfet',
            title: 'İlhamı bul',
            subtitle: 'Stil ve renk dünyanı tanı, kararlarını netleştir.',
          ),
          const SizedBox(height: 14),
          _ToolGroup(
            tools: [
              _ToolItem(
                icon: LucideIcons.sparkles,
                title: 'Tarzını Keşfet',
                subtitle: 'Beğeni temelli kısa keşif — sana özel stil profili',
                onTap: onStyleDiscovery,
              ),
              _ToolItem(
                icon: LucideIcons.palette,
                title: 'Renk Önerisi',
                subtitle: 'Mekânının ışığına göre palet ve kombinler',
                onTap: onColorAdvice,
              ),
            ],
          ),

          const SizedBox(height: 28),

          // ─── Section: Planla ───
          const _SectionHeader(
            eyebrow: 'Planla',
            title: 'Bütçeni ve ekibini kur',
            subtitle: 'Sayılara dökülmüş net bir yol haritası.',
          ),
          const SizedBox(height: 14),
          _ToolGroup(
            tools: [
              _ToolItem(
                icon: LucideIcons.wallet,
                title: 'Bütçe Planı',
                subtitle: 'Oda + stil + bütçeye göre kalem kalem öneri',
                onTap: onBudget,
              ),
              _ToolItem(
                icon: LucideIcons.userCheck,
                title: 'İç Mimar Eşleştir',
                subtitle: 'Tarzına uygun profesyonelle tek tıkla buluş',
                badge: _ToolBadge.pro,
                onTap: onDesignerMatch,
              ),
            ],
          ),

          const SizedBox(height: 28),

          // ─── Section: Sohbet ───
          const _SectionHeader(
            eyebrow: 'Sohbet',
            title: 'Aklındakini sor',
            subtitle: 'Koala asistan her şeyini hatırlar, takip eder.',
          ),
          const SizedBox(height: 14),
          _ToolGroup(
            tools: [
              _ToolItem(
                icon: LucideIcons.messageSquare,
                title: 'Koala\'ya Sor',
                subtitle: 'Serbest sohbet — fikirlerini birlikte geliştirelim',
                onTap: onFreeChat,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────
// Section header — eyebrow + title + sub (TÜMÜ SOL HİZALI).
// ───────────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });
  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          eyebrow.toUpperCase(),
          textAlign: TextAlign.left,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: KoalaColors.accentDeep,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          textAlign: TextAlign.left,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: KoalaColors.text,
            letterSpacing: -0.4,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.left,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w400,
            color: KoalaColors.textSec,
            letterSpacing: -0.1,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────────────
// Tool group — sürekli beyaz surface, satırlar arası hairline divider.
// ───────────────────────────────────────────────────────────────────────
class _ToolGroup extends StatelessWidget {
  const _ToolGroup({required this.tools});
  final List<_ToolItem> tools;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: KoalaColors.border, width: 0.6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < tools.length; i++) ...[
            tools[i],
            if (i < tools.length - 1)
              const Padding(
                padding: EdgeInsets.only(left: 72),
                child: Divider(
                  height: 1,
                  thickness: 0.5,
                  color: KoalaColors.border,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

enum _ToolBadge { none, pro, yeni }

// ───────────────────────────────────────────────────────────────────────
// Tool row — icon square + title + subtitle + (badge) + chevron.
// Press feedback: subtle background tint, haptic light impact.
// ───────────────────────────────────────────────────────────────────────
class _ToolItem extends StatefulWidget {
  const _ToolItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge = _ToolBadge.none,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final _ToolBadge badge;

  @override
  State<_ToolItem> createState() => _ToolItemState();
}

class _ToolItemState extends State<_ToolItem> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) {
        _setPressed(false);
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _pressed ? KoalaColors.accentSoft.withValues(alpha: 0.6) : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Leading icon — brand soft square
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: KoalaColors.accentSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: KoalaColors.accent.withValues(alpha: 0.10),
                  width: 0.6,
                ),
              ),
              child: Icon(
                widget.icon,
                size: 20,
                color: KoalaColors.accentDeep,
              ),
            ),
            const SizedBox(width: 14),
            // Title + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.title,
                          textAlign: TextAlign.left,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: KoalaColors.text,
                            letterSpacing: -0.2,
                            height: 1.2,
                          ),
                        ),
                      ),
                      if (widget.badge != _ToolBadge.none) ...[
                        const SizedBox(width: 8),
                        _Pill(kind: widget.badge),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.subtitle,
                    textAlign: TextAlign.left,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                      color: KoalaColors.textSec,
                      letterSpacing: -0.05,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: KoalaColors.textTer,
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.kind});
  final _ToolBadge kind;

  @override
  Widget build(BuildContext context) {
    final isPro = kind == _ToolBadge.pro;
    final bg = isPro ? KoalaColors.accentDeep : KoalaColors.greenLight;
    final fg = isPro ? Colors.white : KoalaColors.greenDark;
    final label = isPro ? 'PRO' : 'YENİ';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: fg,
          letterSpacing: 0.6,
          height: 1.1,
        ),
      ),
    );
  }
}
