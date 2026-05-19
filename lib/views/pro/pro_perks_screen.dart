// Pro Perks screen — positive reinforcement for Pro users. Reduces churn
// by showing all the value they're getting. Accessible from profile only
// while subscription is active.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/koala_tokens.dart';

class ProPerksScreen extends StatelessWidget {
  const ProPerksScreen({super.key});

  static const _perks = <_Perk>[
    _Perk(
      icon: LucideIcons.sparkles,
      title: 'Sınırsız AI tasarımı',
      body: 'Her ay onlarca farklı stilde mekan üret. Hiçbir kota yok.',
    ),
    _Perk(
      icon: LucideIcons.imagePlus,
      title: '4K yüksek çözünürlük',
      body: 'Ürettiğin tasarımları profesyonel baskı kalitesinde indir.',
    ),
    _Perk(
      icon: LucideIcons.bookmark,
      title: 'Sınırsız kayıt',
      body: 'Beğendiğin tüm tasarımları sınırsız sakla, koleksiyon yap.',
    ),
    _Perk(
      icon: LucideIcons.messageCircle,
      title: 'Sınırsız Koala AI',
      body: 'Asistan ile mekanın hakkında günlük limit olmadan konuş.',
    ),
    _Perk(
      icon: LucideIcons.zap,
      title: 'Önceliklendirilmiş üretim',
      body: 'Tasarımların kuyruğa girmeden öncelikli olarak işlenir.',
    ),
    _Perk(
      icon: LucideIcons.crown,
      title: 'Profesyonel desteğe öncelik',
      body: 'İç mimar talebin Pro üye olarak listenin başına alınır.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      appBar: AppBar(
        backgroundColor: KoalaColors.bg,
        surfaceTintColor: KoalaColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: KoalaColors.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Pro Avantajların',
          style: GoogleFonts.fraunces(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: KoalaColors.text,
            letterSpacing: -0.4,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [KoalaColors.accentDeep, KoalaColors.accentMuted],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: KoalaColors.accentDeep.withValues(alpha: 0.28),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(LucideIcons.crown,
                        size: 22, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Koala Pro üyesisin',
                          style: GoogleFonts.fraunces(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Tüm premium özelliklere erişimin var',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            ..._perks.map((p) => _PerkRow(perk: p)),
          ],
        ),
      ),
    );
  }
}

class _Perk {
  const _Perk({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;
}

class _PerkRow extends StatelessWidget {
  const _PerkRow({required this.perk});
  final _Perk perk;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KoalaColors.border, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: KoalaColors.accentSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(perk.icon,
                size: 18, color: KoalaColors.accentDeep),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        perk.title,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: KoalaColors.text,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const Icon(LucideIcons.checkCircle2,
                        size: 16, color: KoalaColors.greenAlt),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  perk.body,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: KoalaColors.textMed,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
