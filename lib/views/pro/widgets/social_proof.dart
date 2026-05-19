import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/koala_tokens.dart';

class SocialProofRow extends StatefulWidget {
  const SocialProofRow({super.key});

  @override
  State<SocialProofRow> createState() => _SocialProofRowState();
}

class _SocialProofRowState extends State<SocialProofRow> {
  static const _testimonials = <String>[
    '"Bir kahve molasında salonumun tasarımını gördüm. Çok keyifli." — Elif',
    '"3 farklı tarzı denedim, en sevdiğimi seçtim. Süper kolay." — Burak',
    '"Tasarımcıya gitmeden net fikrim oldu, para kazandım." — Ayşe',
    '"Mutfak yenileme öncesi çok yardımcı oldu, her şey gözümde canlandı." — Mehmet',
  ];

  int _i = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      setState(() => _i = (_i + 1) % _testimonials.length);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 0; i < 5; i++)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 1.5),
                child: Icon(LucideIcons.star,
                    size: 14, color: KoalaColors.star),
              ),
            const SizedBox(width: 8),
            const Text(
              '5.0',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: KoalaColors.text,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              '·  12K+ kullanıcı',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: KoalaColors.textSec,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: Padding(
            key: ValueKey(_i),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _testimonials[_i],
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
                color: KoalaColors.textMed,
                height: 1.45,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
