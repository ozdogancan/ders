import 'package:flutter/material.dart';

import '../../services/messaging_service.dart';
import '../../views/conversation_detail_screen.dart';

/// Tasarımcıya mesaj atma entry-point'i.
///
/// TARİHÇE: Eskiden `showModalBottomSheet` ile kendi popup chat UI'ı açardı
/// (`_DesignerChatSheet` ~1100 satır). Mesajlar ekranıyla UI paritesi
/// (kategori etiketi, input, foto picker, tasarım gönderimi vs.) iki yerde
/// ayrı ayrı sürdürülemiyordu. Artık tek kaynak `ConversationDetailScreen`:
///   - conv yoksa LAZY başlat (conversationId null → ilk mesajda yaratılır)
///     → "Mesaj At" popup'ı açıp göndermezse Mesajlar listesine DÜŞMEZ.
///   - UI birebir Mesajlar ekranıyla aynı (aynı widget).
///   - Evlumba bridge MessagingService.sendMessage içinden otomatik çalışır
///     (koala_direct_messages INSERT'inden sonra).
class DesignerChatPopup {
  DesignerChatPopup._();

  /// Tam ekran Mesaj ekranını aç. Yeni sohbetse LAZY mode (ilk mesajda insert).
  static Future<void> show(
    BuildContext context, {
    required String designerId,
    required String designerName,
    String? designerAvatarUrl,
    // contextType/contextId artık kullanılmıyor — parity için signature stabil.
    String? contextType,
    String? contextId,
    String? contextTitle,
    String? initialMessage,
  }) async {
    // Var olan sohbet var mı? Sadece SELECT — yoksa null, insert YAPMAZ.
    final existing = await MessagingService.findExistingConversation(
      designerId: designerId,
    );
    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationDetailScreen(
          conversationId: existing?['id']?.toString(),
          designerId: designerId,
          designerName: designerName,
          designerAvatarUrl: designerAvatarUrl,
          projectTitle: contextTitle,
          initialDraft: initialMessage,
        ),
      ),
    );
  }
}
