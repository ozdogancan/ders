import 'package:flutter/material.dart';
import '../../../core/theme/koala_tokens.dart';
import 'chat_constants.dart';

class QuickTips extends StatelessWidget {
  const QuickTips(this.d, {super.key});
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final tips = (d['tips'] as List?) ?? [];
    // Parse tips -- could be strings, maps with text/emoji/title, etc.
    final parsed = <String>[];
    for (final t in tips) {
      if (t is String && t.trim().isNotEmpty) {
        parsed.add(t);
      } else if (t is Map) {
        final text = t['text'] ?? t['description'] ?? t['title'] ?? '';
        final emoji = t['emoji'] ?? '';
        final combined = '$emoji $text'.trim();
        if (combined.isNotEmpty) parsed.add(combined);
      }
    }
    if (parsed.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(R),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '\u{1F4A1} \u0130pu\u00E7lar\u0131',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          const SizedBox(height: 10),
          ...parsed.map(
            (tip) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 7),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha:0.5),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tip,
                      style: const TextStyle(
                        fontSize: 13,
                        color: KoalaColors.ink,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
