import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/theme/koala_tokens.dart';
import '../core/utils/format_utils.dart';
import '../services/chat_persistence.dart';
import '../services/messaging_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/shimmer_loading.dart';
import 'chat_detail_screen.dart';

/// Mesajlar ekranı — AI chat geçmişi + tasarımcı konuşmaları
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});
  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<Map<String, dynamic>> _conversations = [];
  List<ChatSummary> _aiChats = [];
  bool _loading = true;
  bool _hasError = false;
  bool _showAllAi = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _hasError = false; });
    try {
      final convFuture = MessagingService.getConversations();
      final aiFuture = ChatPersistence.loadConversations();
      final results = await Future.wait([convFuture, aiFuture]);
      if (mounted) {
        setState(() {
          _conversations = results[0] as List<Map<String, dynamic>>;
          _aiChats = results[1] as List<ChatSummary>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _hasError = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      appBar: AppBar(
        backgroundColor: KoalaColors.bg,
        surfaceTintColor: KoalaColors.bg,
        elevation: 0,
        leading: IconButton(
          onPressed: _goBackHome,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Mesajlar', style: KoalaText.h2),
      ),
      body: _loading
          ? const ShimmerList(itemCount: 6, cardHeight: 72)
          : _hasError
              ? ErrorState(onRetry: _load)
              : (_conversations.isEmpty && _aiChats.isEmpty)
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: KoalaColors.accent,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.lg),
                    children: [
                      // ─── AI Asistan (pinli) ───
                      _buildAiSection(),

                      // ─── Tasarımcı konuşmaları ───
                      if (_conversations.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.only(
                            top: KoalaSpacing.lg,
                            bottom: KoalaSpacing.sm,
                          ),
                          child: Text('Tasarımcılar', style: KoalaText.caption),
                        ),
                        ..._conversations.map(_buildConversationTile),
                      ],

                      const SizedBox(height: KoalaSpacing.xxxl),
                    ],
                  ),
                ),
    );
  }

  void _goBackHome() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.go('/');
  }

  Widget _buildEmpty() {
    return const EmptyState(
      icon: Icons.chat_rounded,
      title: 'Henüz bir tasarımcıyla mesajlaşmadın',
      description: 'Tasarımcı profillerinden "Mesaj Gönder" ile sohbet başlat',
    );
  }

  // ─── AI Asistan section ───
  Widget _buildAiSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: KoalaSpacing.sm, bottom: KoalaSpacing.sm),
          child: Text('AI Asistan', style: KoalaText.caption),
        ),
        // Yeni AI sohbet başlat
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ChatDetailScreen()),
          ),
          child: Container(
            padding: const EdgeInsets.all(KoalaSpacing.lg),
            decoration: BoxDecoration(
              gradient: KoalaColors.accentGradient,
              borderRadius: BorderRadius.circular(KoalaRadius.lg),
            ),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
                SizedBox(width: KoalaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Koala AI',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Stil analizi, ürün önerisi, renk paleti...',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.white70),
              ],
            ),
          ),
        ),

        // Eski AI sohbetler
        if (_aiChats.isNotEmpty)
          ..._aiChats.take(_showAllAi ? _aiChats.length : 3).map((chat) => GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatDetailScreen(chatId: chat.id),
                  ),
                ),
                child: Container(
                  margin: const EdgeInsets.only(top: KoalaSpacing.sm),
                  padding: const EdgeInsets.all(KoalaSpacing.md),
                  decoration: KoalaDeco.card,
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: KoalaColors.accentSoft,
                          borderRadius: BorderRadius.circular(KoalaRadius.sm),
                        ),
                        child: const Icon(Icons.chat_rounded,
                            size: 16, color: KoalaColors.accent),
                      ),
                      const SizedBox(width: KoalaSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              chat.title,
                              style: KoalaText.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (chat.lastMessage != null)
                              Text(
                                chat.lastMessage!,
                                style: KoalaText.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      Text(
                        timeAgo(chat.updatedAt),
                        style: KoalaText.labelSmall,
                      ),
                    ],
                  ),
                ),
              )),

        // "Tümünü Gör" butonu
        if (!_showAllAi && _aiChats.length > 3)
          Padding(
            padding: const EdgeInsets.only(top: KoalaSpacing.sm),
            child: GestureDetector(
              onTap: () => setState(() => _showAllAi = true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: KoalaSpacing.md),
                alignment: Alignment.center,
                decoration: KoalaDeco.card,
                child: Text(
                  '${_aiChats.length - 3} sohbet daha göster',
                  style: KoalaText.label.copyWith(color: KoalaColors.accent),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── Tasarımcı konuşma tile ───
  Widget _buildConversationTile(Map<String, dynamic> conv) {
    final lastMessage = conv['last_message'] as String? ?? '';
    final title = conv['title'] as String? ?? 'Tasarımcı';
    final lastAt = DateTime.tryParse(conv['last_message_at']?.toString() ?? '');

    // Unread count (current user perspective)
    final uid = MessagingService.currentUserId;
    final isUser = conv['user_id'] == uid;
    final unread = isUser
        ? (conv['unread_count_user'] as int?) ?? 0
        : (conv['unread_count_designer'] as int?) ?? 0;

    final initials = title
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();

    return GestureDetector(
      onTap: () async {
        await context.push('/chat/dm/${conv['id']}', extra: {
          'designerName': title,
        });
        _load(); // Refresh unread counts
      },
      child: Container(
        margin: const EdgeInsets.only(top: KoalaSpacing.sm),
        padding: const EdgeInsets.all(KoalaSpacing.lg),
        decoration: KoalaDeco.card,
        child: Row(
          children: [
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [KoalaColors.accent, Color(0xFFA78BFA)],
                ),
              ),
              child: Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: KoalaSpacing.md),

            // Name + last message
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: KoalaText.h4),
                  if (lastMessage.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      lastMessage,
                      style: unread > 0
                          ? KoalaText.bodyMedium
                          : KoalaText.bodySec,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // Time + badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (lastAt != null)
                  Text(timeAgo(lastAt), style: KoalaText.labelSmall),
                if (unread > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: KoalaColors.error,
                      borderRadius: BorderRadius.circular(KoalaRadius.pill),
                    ),
                    child: Text(
                      unread > 9 ? '9+' : '$unread',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

}
