import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../core/theme/koala_tokens.dart';
import '../services/messaging_service.dart';

/// Tasarımcı ile mesaj detay ekranı — gerçek zamanlı
class ConversationDetailScreen extends StatefulWidget {
  const ConversationDetailScreen({
    super.key,
    required this.conversationId,
    this.designerName = 'Tasarımcı',
    this.designerAvatarUrl,
  });

  final String conversationId;
  final String designerName;
  final String? designerAvatarUrl;

  @override
  State<ConversationDetailScreen> createState() =>
      _ConversationDetailScreenState();
}

class _ConversationDetailScreenState extends State<ConversationDetailScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _loadingMore = false;
  bool _uploadingImage = false;
  String? _uid;

  @override
  void initState() {
    super.initState();
    _uid = MessagingService.currentUserId;
    _loadMessages();
    _subscribeRealtime();
    _markRead();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    MessagingService.unsubscribeFromMessages(widget.conversationId);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final data = await MessagingService.getMessages(
      conversationId: widget.conversationId,
    );
    if (mounted) setState(() { _messages = data; _loading = false; });
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingMore || _messages.isEmpty) return;
    setState(() => _loadingMore = true);
    final oldest = _messages.last;
    final older = await MessagingService.getMessages(
      conversationId: widget.conversationId,
      beforeId: oldest['id'] as String,
    );
    if (mounted) {
      setState(() {
        _messages.addAll(older);
        _loadingMore = false;
      });
    }
  }

  void _subscribeRealtime() {
    MessagingService.subscribeToMessages(
      conversationId: widget.conversationId,
      onMessage: (msg) {
        if (mounted) {
          setState(() => _messages.insert(0, msg));
          // Gelen mesaj karşı taraftansa okundu işaretle
          if (msg['sender_id'] != _uid) {
            MessagingService.markAsRead(widget.conversationId);
          }
        }
      },
    );
  }

  Future<void> _markRead() async {
    await MessagingService.markAsRead(widget.conversationId);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100) {
      _loadOlderMessages();
    }
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending) return;

    _textController.clear();
    setState(() => _sending = true);

    await MessagingService.sendMessage(
      conversationId: widget.conversationId,
      content: text,
    );

    if (mounted) setState(() => _sending = false);
  }

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 80,
    );
    if (picked == null) return;

    setState(() => _uploadingImage = true);

    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.path.split('.').last;
      final fileName = '${_uid ?? 'anon'}/${DateTime.now().millisecondsSinceEpoch}.$ext';

      await Supabase.instance.client.storage
          .from('message-images')
          .uploadBinary(fileName, bytes);

      final imageUrl = Supabase.instance.client.storage
          .from('message-images')
          .getPublicUrl(fileName);

      await MessagingService.sendMessage(
        conversationId: widget.conversationId,
        content: '📷 Fotoğraf',
        type: MessageType.image,
        attachmentUrl: imageUrl,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Görsel yüklenemedi')),
        );
      }
    }

    if (mounted) setState(() => _uploadingImage = false);
  }

  @override
  Widget build(BuildContext context) {
    final initials = widget.designerName
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();

    return Scaffold(
      backgroundColor: KoalaColors.bg,
      appBar: AppBar(
        backgroundColor: KoalaColors.surface,
        surfaceTintColor: KoalaColors.surface,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            // Avatar
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [KoalaColors.accent, Color(0xFFA78BFA)],
                ),
              ),
              child: widget.designerAvatarUrl != null
                  ? ClipOval(
                      child: Image.network(
                        widget.designerAvatarUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: Text(initials,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(initials,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ),
            ),
            const SizedBox(width: KoalaSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.designerName, style: KoalaText.h4),
                Text('evlumba.com', style: KoalaText.bodySmall.copyWith(color: KoalaColors.textTer)),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Messages
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: KoalaColors.accent,
                    ),
                  )
                : _messages.isEmpty
                    ? const Center(
                        child: Text(
                          'Henüz mesaj yok. İlk mesajı sen gönder!',
                          style: KoalaText.bodySec,
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: KoalaSpacing.lg,
                          vertical: KoalaSpacing.md,
                        ),
                        itemCount: _messages.length + (_loadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (_loadingMore && index == _messages.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(KoalaSpacing.md),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: KoalaColors.accent,
                                ),
                              ),
                            );
                          }
                          return _MessageBubble(
                            message: _messages[index],
                            isMe: _messages[index]['sender_id'] == _uid,
                          );
                        },
                      ),
          ),

          // Input bar
          Container(
            padding: EdgeInsets.only(
              left: KoalaSpacing.lg,
              right: KoalaSpacing.sm,
              top: KoalaSpacing.sm,
              bottom: KoalaSpacing.sm + MediaQuery.of(context).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: KoalaColors.surface,
              border: Border(
                top: BorderSide(color: KoalaColors.border, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                // Image picker
                GestureDetector(
                  onTap: _uploadingImage ? null : _pickAndSendImage,
                  child: Padding(
                    padding: const EdgeInsets.only(right: KoalaSpacing.sm),
                    child: _uploadingImage
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: KoalaColors.accent,
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt_rounded,
                            color: KoalaColors.textSec,
                            size: 24,
                          ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    style: KoalaText.body,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: 'Mesaj yaz...',
                      hintStyle: KoalaText.hint,
                      filled: true,
                      fillColor: KoalaColors.bg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(KoalaRadius.xl),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: KoalaSpacing.lg,
                        vertical: KoalaSpacing.md,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: KoalaSpacing.sm),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _sending ? KoalaColors.accentLight : KoalaColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: _sending
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
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

// ═══════════════════════════════════════════════════════
// MESSAGE BUBBLE
// ═══════════════════════════════════════════════════════
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMe});
  final Map<String, dynamic> message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final content = message['content'] as String? ?? '';
    final type = message['message_type'] as String? ?? 'text';
    final createdAt = DateTime.tryParse(message['created_at']?.toString() ?? '');
    final timeStr = createdAt != null
        ? '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}'
        : '';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: KoalaSpacing.sm),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: KoalaSpacing.lg,
          vertical: KoalaSpacing.md,
        ),
        decoration: BoxDecoration(
          color: isMe ? KoalaColors.accent : KoalaColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(KoalaRadius.lg),
            topRight: const Radius.circular(KoalaRadius.lg),
            bottomLeft: Radius.circular(isMe ? KoalaRadius.lg : KoalaRadius.xs),
            bottomRight: Radius.circular(isMe ? KoalaRadius.xs : KoalaRadius.lg),
          ),
          border: isMe ? null : Border.all(color: KoalaColors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Image message
            if (type == 'image' && message['attachment_url'] != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(KoalaRadius.sm),
                child: Image.network(
                  message['attachment_url'] as String,
                  width: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_rounded,
                    color: KoalaColors.textTer,
                  ),
                ),
              ),

            // Text content
            if (content.isNotEmpty)
              Text(
                content,
                style: TextStyle(
                  fontSize: 14,
                  color: isMe ? Colors.white : KoalaColors.text,
                  height: 1.4,
                ),
              ),

            // Timestamp
            const SizedBox(height: 4),
            Text(
              timeStr,
              style: TextStyle(
                fontSize: 10,
                color: isMe ? Colors.white60 : KoalaColors.textTer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
