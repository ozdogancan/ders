import 'package:flutter/material.dart';
import '../../../core/theme/koala_tokens.dart';
import 'chat_constants.dart';

class QuestionChips extends StatefulWidget {
  const QuestionChips(this.d, {super.key, required this.onTap});
  final Map<String, dynamic> d;
  final void Function(String) onTap;

  @override
  State<QuestionChips> createState() => QuestionChipsState();
}

class QuestionChipsState extends State<QuestionChips> {
  String? _selectedChip;

  @override
  Widget build(BuildContext context) {
    final question = widget.d['question'] as String? ?? widget.d['title'] as String? ?? '';
    final raw = widget.d['chips'] ?? widget.d['options'] ?? [];
    if (raw is! List || (raw).isEmpty) return const SizedBox.shrink();

    final chips = <Map<String, String>>[];
    for (final item in raw) {
      if (item is String) {
        chips.add({'label': item, 'value': item});
      } else if (item is Map) {
        final label = (item['label'] ?? item['text'] ?? item.values.first ?? '')
            .toString();
        final value = (item['value'] ?? item['label'] ?? label).toString();
        chips.add({'label': label, 'value': value});
      }
    }

    final bool answered = _selectedChip != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        border: Border.all(color: KoalaColors.accentLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (question.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                question,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips
                .map(
                  (chip) {
                    final isSelected = _selectedChip == chip['label'];
                    return GestureDetector(
                      onTap: answered ? null : () {
                        setState(() => _selectedChip = chip['label']);
                        widget.onTap(chip['label']!);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          color: isSelected
                              ? accent
                              : answered
                                  ? KoalaColors.surfaceMuted
                                  : accentLight,
                          border: Border.all(
                            color: isSelected
                                ? accent
                                : answered
                                    ? Colors.grey.shade200
                                    : accent.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Text(
                          chip['label']!,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : answered
                                    ? Colors.grey.shade400
                                    : accent,
                          ),
                        ),
                      ),
                    );
                  },
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
