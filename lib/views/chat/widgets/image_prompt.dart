import 'package:flutter/material.dart';
import '../../../core/theme/koala_tokens.dart';
import 'chat_constants.dart';
import 'package:lucide_icons/lucide_icons.dart';

class ImagePrompt extends StatelessWidget {
  const ImagePrompt(this.d, {super.key, required this.onGenerate});
  final Map<String, dynamic> d;
  final void Function(String) onGenerate;
  @override
  Widget build(BuildContext context) {
    final title = d['title'] as String? ?? 'Tasar\u0131m G\u00F6rseli';
    final prompt = d['prompt'] as String? ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(R),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [KoalaColors.accentSoft, const Color(0xFFE8F4FD)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.sparkles, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () => onGenerate(prompt),
              icon: const Icon(LucideIcons.brush, size: 18),
              label: const Text(
                'G\u00F6rseli Olu\u015Ftur',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
