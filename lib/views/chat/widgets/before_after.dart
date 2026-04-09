import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/koala_tokens.dart';
import '../../../services/messaging_service.dart';
import '../../conversation_detail_screen.dart';
import 'chat_constants.dart';

class BeforeAfter extends StatelessWidget {
  const BeforeAfter(this.d, {super.key});
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final changes = (d['changes'] as List?)?.cast<String>() ?? [];
    final imageUrl = d['image_url'] as String? ?? '';
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(R),
        gradient: const LinearGradient(
          colors: [KoalaColors.accentSoft, KoalaColors.greenLight],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Proje g\u00F6rseli
          if (imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(R)),
              child: Image.network(
                imageUrl,
                width: double.infinity,
                height: 160,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          Text(
            d['title'] ?? '',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          const SizedBox(height: 10),
          ...changes.map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: KoalaColors.greenDark,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      c,
                      style: const TextStyle(
                        fontSize: 13,
                        color: KoalaColors.ink,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (d['estimated_budget'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Tahmini: ${d['estimated_budget']}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ),
          // Tasar\u0131mc\u0131yla ileti\u015Fim \u2014 designer_id varsa g\u00F6ster
          if (d['designer_id'] != null && (d['designer_id'] as String).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: GestureDetector(
                onTap: () async {
                  final designerId = d['designer_id'] as String;
                  final title = d['title'] as String? ?? 'Tasar\u0131m';
                  HapticFeedback.lightImpact();
                  final conv = await MessagingService.getOrCreateConversation(
                    designerId: designerId,
                    contextType: 'project',
                    contextId: designerId,
                    contextTitle: title,
                  );
                  if (conv != null && context.mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ConversationDetailScreen(
                          conversationId: conv['id'] as String,
                          designerName: d['designer_name'] as String? ?? 'Tasar\u0131mc\u0131',
                        ),
                      ),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: KoalaColors.greenAlt,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          duration: const Duration(seconds: 4),
                          content: const Row(
                            children: [
                              Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Expanded(child: Text('Mesaj\u0131n\u0131z iletildi! Genellikle 24 saat i\u00E7inde d\u00F6n\u00FC\u015F yap\u0131l\u0131r.', style: TextStyle(color: Colors.white, fontSize: 13))),
                            ],
                          ),
                        ),
                      );
                    }
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: KoalaColors.greenAlt,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_rounded, size: 14, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'Bu Tasar\u0131mc\u0131yla \u00C7al\u0131\u015F',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
              ],
            ),
          ), // close inner Padding
        ],
      ),
    );
  }
}
