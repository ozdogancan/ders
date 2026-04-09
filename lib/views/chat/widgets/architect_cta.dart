import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/koala_tokens.dart';
import '../../designers_screen.dart';

class ArchitectCTA extends StatelessWidget {
  const ArchitectCTA(this.d, {super.key});
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [KoalaColors.accentDeep, KoalaColors.accentMuted, KoalaColors.accentMuted],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white.withValues(alpha:0.2),
                ),
                child: const Icon(
                  Icons.videocam_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '\u0130\u00E7 Mimarla Konu\u015F',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'evlumba uzmanlar\u0131ndan biri sana yard\u0131mc\u0131 olsun',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              SizedBox(
                width: 72,
                height: 28,
                child: Stack(
                  children: [
                    _dot(0, KoalaColors.pink),
                    _dot(18, KoalaColors.blue),
                    _dot(36, KoalaColors.greenAlt),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Uzman i\u00E7 mimarlar seni bekliyor',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha:0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DesignersScreen()),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
              ),
              child: const Center(
                child: Text(
                  'Uzman Bul ve \u00DCcretsiz G\u00F6r\u00FC\u015F',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: KoalaColors.accentDeep,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(double left, Color color) => Positioned(
    left: left,
    child: Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white.withValues(alpha:0.3), width: 2),
      ),
      child: const Icon(Icons.person_rounded, size: 14, color: Colors.white),
    ),
  );
}
