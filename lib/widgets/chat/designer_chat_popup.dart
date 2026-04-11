import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../core/theme/koala_tokens.dart';
import '../../services/messaging_service.dart';

/// Tasarımcıya mesaj atma popup'ı.
/// Mevcut ekranın üzerinde açılır, AI chat kaybolmaz.
/// "xyz'ye bağlanılıyor" animasyonu → sohbet ekranı.
class DesignerChatPopup {
  DesignerChatPopup._();

  /// Popup'ı aç — herhangi bir ekrandan çağrılabilir.
  static Future<void> show(
    BuildContext context, {
    required String designerId,
    required String designerName,
    String? designerAvatarUrl,
    String? contextType,
    String? contextId,
    String? contextTitle,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black26,
      builder: (_) => _DesignerChatSheet(
        designerId: designerId,
        designerName: designerName,
        designerAvatarUrl: designerAvatarUrl,
        contextType: contextType,
        contextId: contextId,
        contextTitle: contextTitle,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// CHAT SHEET (DraggableScrollableSheet)
// ═══════════════════════════════════════════════════════

class _DesignerChatSheet extends StatefulWidget {
  const _DesignerChatSheet({
    required this.designerId,
    required this.designerName,
    this.designerAvatarUrl,
    this.contextType,
    this.contextId,
    this.contextTitle,
  });

  final String designerId;
  final String designerName;
  final String? designerAvatarUrl;
  final String? contextType;
  final String? contextId;
  final String? contextTitle;

  @override
  State<_DesignerChatSheet> createState() => _DesignerChatSheetState();
}

enum _SheetState { connecting, ready, error }

class _DesignerChatSheetState extends State<_DesignerChatSheet>
    with SingleTickerProviderStateMixin {
  _SheetState _state = _SheetState.connecting;
  String? _conversationId;
  String? _errorMsg;

  // Chat state
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _sending = false;
  bool _loadingMore = false;
  bool _uploadingImage = false;
  String? _uid;

  // Animation
  late AnimationController _pulseController;

  // DraggableScrollableSheet controller
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _connect();
  }

  @override
  void dispose() {
    if (_conversationId != null) {
      MessagingService.unsubscribeFromMessages(_conversationId!);
    }
    _textController.dispose();
    _scrollController.dispose();
    _pulseController.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  /// Bağlantı kur — conversation oluştur veya getir
  Future<void> _connect() async {
    try {
      final conv = await MessagingService.getOrCreateConversation(
        designerId: widget.designerId,
        contextType: widget.contextType,
        contextId: widget.contextId,
        contextTitle: widget.contextTitle,
      );

      if (conv == null) {
        if (mounted) {
          setState(() {
            _state = _SheetState.error;
            _errorMsg = 'Bağlantı kurulamadı. Lütfen tekrar deneyin.';
          });
        }
        return;
      }

      _conversationId = conv['id'] as String;

      // Mesajları yükle
      final messages = await MessagingService.getMessages(
        conversationId: _conversationId!,
      );

      // Realtime abone ol
      _subscribeRealtime();

      // Okundu işaretle
      MessagingService.markAsRead(_conversationId!);

      // Koala sender metadata ile ilk mesajı gönder (eğer yeni conversation ise)
      if (messages.isEmpty && widget.contextType != null) {
        final user = FirebaseAuth.instance.currentUser;
        final displayName = user?.displayName ?? 'Kullanıcı';
        final email = user?.email ?? '';

        await MessagingService.sendMessage(
          conversationId: _conversationId!,
          content:
              '${widget.contextTitle ?? 'Merhaba'} hakkında bilgi almak istiyorum.',
          metadata: {
            'sender_display': 'Koala - $displayName',
            'sender_email': email,
            'source': 'koala_app',
            if (widget.contextType != null) 'context_type': widget.contextType,
            if (widget.contextId != null) 'context_id': widget.contextId,
          },
        );

        // Mesajları tekrar yükle
        final updatedMessages = await MessagingService.getMessages(
          conversationId: _conversationId!,
        );
        if (mounted) {
          setState(() {
            _messages = updatedMessages;
            _state = _SheetState.ready;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _messages = messages;
            _state = _SheetState.ready;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _SheetState.error;
          _errorMsg = 'Bir hata oluştu: $e';
        });
      }
    }
  }

  void _subscribeRealtime() {
    if (_conversationId == null) return;
    MessagingService.subscribeToMessages(
      conversationId: _conversationId!,
      onMessage: (msg) {
        if (mounted) {
          setState(() => _messages.insert(0, msg));
          if (msg['sender_id'] != _uid) {
            MessagingService.markAsRead(_conversationId!);
          }
        }
      },
    );
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingMore || _messages.isEmpty || _conversationId == null) return;
    setState(() => _loadingMore = true);
    final oldest = _messages.last;
    final older = await MessagingService.getMessages(
      conversationId: _conversationId!,
      beforeId: oldest['id'] as String,
    );
    if (mounted) {
      setState(() {
        _messages.addAll(older);
        _loadingMore = false;
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending || _conversationId == null) return;

    _textController.clear();
    setState(() => _sending = true);

    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? 'Kullanıcı';
    final email = user?.email ?? '';

    await MessagingService.sendMessage(
      conversationId: _conversationId!,
      content: text,
      metadata: {
        'sender_display': 'Koala - $displayName',
        'sender_email': email,
        'source': 'koala_app',
      },
    );

    if (mounted) setState(() => _sending = false);
  }

  Future<void> _pickAndSendImage() async {
    if (_conversationId == null) return;
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
      final fileName =
          '${_uid ?? 'anon'}/${DateTime.now().millisecondsSinceEpoch}.$ext';

      await Supabase.instance.client.storage
          .from('message-images')
          .uploadBinary(fileName, bytes);

      final imageUrl = Supabase.instance.client.storage
          .from('message-images')
          .getPublicUrl(fileName);

      final user = FirebaseAuth.instance.currentUser;
      await MessagingService.sendMessage(
        conversationId: _conversationId!,
        content: '\u{1F4F7} Fotoğraf',
        type: MessageType.image,
        attachmentUrl: imageUrl,
        metadata: {
          'sender_display': 'Koala - ${user?.displayName ?? 'Kullanıcı'}',
          'sender_email': user?.email ?? '',
          'source': 'koala_app',
        },
      );
    } catch (_) {
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
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: KoalaColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 20,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // ── Handle + Header ──
              _buildHeader(),

              // ── Content ──
              Expanded(
                child: _state == _SheetState.connecting
                    ? _buildConnecting()
                    : _state == _SheetState.error
                        ? _buildError()
                        : _buildChat(),
              ),

              // ── Input bar (sadece ready durumunda) ──
              if (_state == _SheetState.ready)
                Padding(
                  padding: EdgeInsets.only(bottom: bottomPad),
                  child: _buildInputBar(),
                ),
            ],
          ),
        );
      },
    );
  }

  // ─── HEADER ──────────────────────────────────────────
  Widget _buildHeader() {
    final initials = widget.designerName
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();

    return Column(
      children: [
        // Drag handle
        Container(
          margin: const EdgeInsets.only(top: 10, bottom: 6),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: KoalaColors.borderSolid,
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        // Designer info + close
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KoalaSpacing.lg,
            vertical: KoalaSpacing.sm,
          ),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [KoalaColors.accent, KoalaColors.accentMuted],
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
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(initials,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ),
              ),
              const SizedBox(width: KoalaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.designerName, style: KoalaText.h4),
                    Text(
                      _state == _SheetState.connecting
                          ? 'Bağlanılıyor...'
                          : 'evlumba.com',
                      style: KoalaText.bodySmall.copyWith(
                        color: _state == _SheetState.connecting
                            ? KoalaColors.accent
                            : KoalaColors.textTer,
                      ),
                    ),
                  ],
                ),
              ),
              // Expand button
              IconButton(
                onPressed: () {
                  final current = _sheetController.size;
                  _sheetController.animateTo(
                    current < 0.8 ? 0.95 : 0.55,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
                icon: Icon(
                  _sheetController.isAttached && _sheetController.size > 0.8
                      ? Icons.expand_more_rounded
                      : Icons.expand_less_rounded,
                  color: KoalaColors.textSec,
                ),
                tooltip: 'Büyüt / Küçült',
              ),
              // Close
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded,
                    color: KoalaColors.textSec, size: 22),
                tooltip: 'Kapat',
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: KoalaColors.borderSolid),
      ],
    );
  }

  // ─── CONNECTING STATE ────────────────────────────────
  Widget _buildConnecting() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated avatar
          FadeTransition(
            opacity: Tween(begin: 0.4, end: 1.0).animate(_pulseController),
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [KoalaColors.accent, KoalaColors.accentMuted],
                ),
                boxShadow: KoalaShadows.accentGlow,
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded,
                  color: Colors.white, size: 32),
            ),
          ),
          const SizedBox(height: KoalaSpacing.xxl),
          Text(
            "${widget.designerName}'e bağlanılıyor...",
            style: KoalaText.h3,
          ),
          const SizedBox(height: KoalaSpacing.sm),
          Text(
            'Sohbet hazırlanıyor',
            style: KoalaText.bodySec,
          ),
          const SizedBox(height: KoalaSpacing.xxl),
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: KoalaColors.accent,
            ),
          ),
        ],
      ),
    );
  }

  // ─── ERROR STATE ─────────────────────────────────────
  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KoalaSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: KoalaColors.error, size: 48),
            const SizedBox(height: KoalaSpacing.lg),
            Text(_errorMsg ?? 'Bir hata oluştu',
                style: KoalaText.body, textAlign: TextAlign.center),
            const SizedBox(height: KoalaSpacing.xxl),
            TextButton.icon(
              onPressed: () {
                setState(() => _state = _SheetState.connecting);
                _connect();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tekrar Dene'),
              style: TextButton.styleFrom(
                foregroundColor: KoalaColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── CHAT MESSAGES ───────────────────────────────────
  Widget _buildChat() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded,
                color: KoalaColors.textTer, size: 40),
            const SizedBox(height: KoalaSpacing.md),
            Text(
              'Mesajınızı yazın ve gönderin!',
              style: KoalaText.bodySec,
            ),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notif) {
        if (notif is ScrollEndNotification &&
            _scrollController.position.pixels >=
                _scrollController.position.maxScrollExtent - 100) {
          _loadOlderMessages();
        }
        return false;
      },
      child: ListView.builder(
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
                    strokeWidth: 2, color: KoalaColors.accent),
              ),
            );
          }
          return _PopupMessageBubble(
            message: _messages[index],
            isMe: _messages[index]['sender_id'] == _uid,
          );
        },
      ),
    );
  }

  // ─── INPUT BAR ───────────────────────────────────────
  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: KoalaSpacing.lg,
        right: KoalaSpacing.sm,
        top: KoalaSpacing.sm,
        bottom: KoalaSpacing.sm + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: KoalaColors.surface,
        border: Border(
          top: BorderSide(color: KoalaColors.borderSolid, width: 0.5),
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
                          strokeWidth: 2, color: KoalaColors.accent),
                    )
                  : const Icon(Icons.camera_alt_rounded,
                      color: KoalaColors.textSec, size: 24),
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
                hintText: '${widget.designerName} ile mesajlaş...',
                hintStyle: KoalaText.bodySec,
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
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// MESSAGE BUBBLE (popup versiyonu)
// ═══════════════════════════════════════════════════════
class _PopupMessageBubble extends StatelessWidget {
  const _PopupMessageBubble({required this.message, required this.isMe});
  final Map<String, dynamic> message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final content = message['content'] as String? ?? '';
    final type = message['message_type'] as String? ?? 'text';
    final createdAt =
        DateTime.tryParse(message['created_at']?.toString() ?? '');
    final timeStr = createdAt != null
        ? '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}'
        : '';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: KoalaSpacing.sm),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
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
            bottomLeft:
                Radius.circular(isMe ? KoalaRadius.lg : KoalaRadius.xs),
            bottomRight:
                Radius.circular(isMe ? KoalaRadius.xs : KoalaRadius.lg),
          ),
          border:
              isMe ? null : Border.all(color: KoalaColors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Image
            if (type == 'image' && message['attachment_url'] != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(KoalaRadius.sm),
                child: Image.network(
                  message['attachment_url'] as String,
                  width: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_rounded,
                      color: KoalaColors.textTer),
                ),
              ),
            // Text
            if (content.isNotEmpty)
              Text(
                content,
                style: TextStyle(
                  fontSize: 14,
                  color: isMe ? Colors.white : KoalaColors.text,
                  height: 1.4,
                ),
              ),
            // Time
            const SizedBox(height: 3),
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
