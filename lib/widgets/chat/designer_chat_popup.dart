import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/koala_tokens.dart';
import '../../services/evlumba_live_service.dart';
import '../../services/koala_ai_service.dart';
import '../../services/messaging_service.dart';
import '../../services/saved_items_service.dart';
import '../../views/chat_detail_screen.dart';
import '../save_button.dart';

/// Tasarımcıya mesaj atma popup'ı.
/// Mevcut ekranın üzerinde açılır, AI chat kaybolmaz.
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
    String? initialMessage,
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
        initialMessage: initialMessage,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// CHAT SHEET
// ═══════════════════════════════════════════════════════

class _DesignerChatSheet extends StatefulWidget {
  const _DesignerChatSheet({
    required this.designerId,
    required this.designerName,
    this.designerAvatarUrl,
    this.contextType,
    this.contextId,
    this.contextTitle,
    this.initialMessage,
  });

  final String designerId;
  final String designerName;
  final String? designerAvatarUrl;
  final String? contextType;
  final String? contextId;
  final String? contextTitle;
  final String? initialMessage;

  @override
  State<_DesignerChatSheet> createState() => _DesignerChatSheetState();
}

enum _SheetState { connecting, ready, error }

class _DesignerChatSheetState extends State<_DesignerChatSheet>
    with SingleTickerProviderStateMixin {
  _SheetState _state = _SheetState.connecting;
  String? _conversationId;
  String? _errorMsg;

  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _sending = false;
  bool _loadingMore = false;
  bool _uploadingImage = false;
  String? _uid;

  // Designer detay bilgileri
  Map<String, dynamic>? _designerDetail;
  List<Map<String, dynamic>> _designerProjects = [];

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _connect();
    _loadDesignerDetail();
  }

  @override
  void dispose() {
    if (_conversationId != null) {
      MessagingService.unsubscribeFromMessages(_conversationId!);
    }
    _textController.dispose();
    _scrollController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadDesignerDetail() async {
    try {
      if (!EvlumbaLiveService.isReady) {
        await EvlumbaLiveService.waitForReady(timeout: const Duration(seconds: 5));
      }
      if (!EvlumbaLiveService.isReady) return;
      final detail = await EvlumbaLiveService.getDesignerById(widget.designerId);
      final projects = await EvlumbaLiveService.getDesignerProjects(widget.designerId, limit: 6);
      if (mounted) setState(() { _designerDetail = detail; _designerProjects = projects; });
    } catch (_) {}
  }

  Future<void> _connect() async {
    try {
      final conv = await MessagingService.getOrCreateConversation(
        designerId: widget.designerId,
        contextType: widget.contextType,
        contextId: widget.contextId,
        contextTitle: widget.contextTitle,
      );
      if (conv == null) {
        if (mounted) setState(() { _state = _SheetState.error; _errorMsg = 'Bağlantı kurulamadı.'; });
        return;
      }
      _conversationId = conv['id'] as String;
      final messages = await MessagingService.getMessages(conversationId: _conversationId!);
      _subscribeRealtime();
      MessagingService.markAsRead(_conversationId!);

      // Mesajları göster
      if (mounted) setState(() { _messages = messages; _state = _SheetState.ready; });

      // Context veya initialMessage varsa input'a yaz — kullanıcı karar versin
      if (messages.isEmpty && widget.contextTitle != null && widget.contextTitle!.isNotEmpty) {
        _textController.text = '${widget.contextTitle} hakk\u0131nda bilgi almak istiyorum.';
      } else if (widget.initialMessage != null && widget.initialMessage!.trim().isNotEmpty) {
        _textController.text = widget.initialMessage!.trim();
      }
    } catch (e) {
      if (mounted) setState(() { _state = _SheetState.error; _errorMsg = 'Bir hata oluştu: $e'; });
    }
  }

  void _subscribeRealtime() {
    if (_conversationId == null) return;
    MessagingService.subscribeToMessages(
      conversationId: _conversationId!,
      onMessage: (msg) {
        if (mounted) {
          setState(() => _messages.insert(0, msg));
          if (msg['sender_id'] != _uid) MessagingService.markAsRead(_conversationId!);
        }
      },
    );
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingMore || _messages.isEmpty || _conversationId == null) return;
    setState(() => _loadingMore = true);
    final older = await MessagingService.getMessages(
      conversationId: _conversationId!, beforeId: _messages.last['id'] as String,
    );
    if (mounted) setState(() { _messages.addAll(older); _loadingMore = false; });
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending || _conversationId == null) return;
    _textController.clear();
    setState(() => _sending = true);
    final user = FirebaseAuth.instance.currentUser;
    await MessagingService.sendMessage(
      conversationId: _conversationId!, content: text,
      metadata: { 'sender_display': 'Koala - ${user?.displayName ?? 'Kullanıcı'}', 'sender_email': user?.email ?? '', 'source': 'koala_app' },
    );
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _pickAndSendImage() async {
    if (_conversationId == null) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 80);
    if (picked == null) return;
    setState(() => _uploadingImage = true);
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.path.split('.').last.toLowerCase();
      const allowed = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'};
      if (!allowed.contains(ext)) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Desteklenmeyen dosya türü')));
        setState(() => _uploadingImage = false);
        return;
      }
      final fileName = '${_uid ?? 'anon'}/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await Supabase.instance.client.storage.from('message-images').uploadBinary(fileName, bytes);
      final imageUrl = Supabase.instance.client.storage.from('message-images').getPublicUrl(fileName);
      final user = FirebaseAuth.instance.currentUser;
      await MessagingService.sendMessage(
        conversationId: _conversationId!, content: '\u{1F4F7} Fotoğraf', type: MessageType.image, attachmentUrl: imageUrl,
        metadata: { 'sender_display': 'Koala - ${user?.displayName ?? 'Kullanıcı'}', 'sender_email': user?.email ?? '', 'source': 'koala_app' },
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Görsel yüklenemedi')));
    }
    if (mounted) setState(() => _uploadingImage = false);
  }

  void _openDesignerProfile() {
    launchUrl(Uri.parse('https://www.evlumba.com/tasarimci/${widget.designerId}'), mode: LaunchMode.inAppBrowserView);
  }

  /// Portfolio görseline tıklanınca proje detay overlay aç
  void _openProjectViewer(Map<String, dynamic> project, int startIndex) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => _ProjectViewerSheet(
        project: project,
        allProjects: _designerProjects,
        startIndex: startIndex,
        designerName: widget.designerName,
        designerId: widget.designerId,
        onAskAI: (question, {String? hiddenContext}) {
          // AI chat'e yönlendir
          Navigator.of(context).pop(); // viewer kapat
          Navigator.of(context).pop(); // designer popup kapat
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ChatDetailScreen(
              initialText: question,
              hiddenContext: hiddenContext,
            )),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardVisible = media.viewInsets.bottom > 0;

    // Tam ekran full-screen page olarak göster
    return Container(
      height: media.size.height * 0.92,
      decoration: const BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -4))],
      ),
      child: Column(
        children: [
          // ── Handle ──
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40, height: 4,
              decoration: BoxDecoration(color: KoalaColors.borderSolid, borderRadius: BorderRadius.circular(2)),
            ),
          ),

          // ── Header ──
          _buildHeader(),

          // ── Content ──
          Expanded(
            child: _state == _SheetState.connecting
                ? _buildConnecting()
                : _state == _SheetState.error
                    ? _buildError()
                    : _buildChat(),
          ),

          // ── Input ──
          if (_state == _SheetState.ready) _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final initials = widget.designerName.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();
    final specialty = (_designerDetail?['specialty'] ?? '').toString().trim();
    final city = (_designerDetail?['city'] ?? '').toString().trim();

    return Column(
      children: [
        // Top row
        Padding(
          padding: const EdgeInsets.only(left: 8, right: 8),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded, color: KoalaColors.text, size: 22),
              ),
              const Spacer(),
              SaveButton(itemType: SavedItemType.designer, itemId: widget.designerId, title: widget.designerName, subtitle: specialty.isNotEmpty ? specialty : 'İç Mimar', size: 20),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: KoalaColors.textSec, size: 22),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),

        // Designer info
        GestureDetector(
          onTap: _openDesignerProfile,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [KoalaColors.accent, KoalaColors.accentMuted])),
                  child: widget.designerAvatarUrl != null
                      ? ClipOval(child: Image.network(widget.designerAvatarUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Center(child: Text(initials, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)))))
                      : Center(child: Text(initials, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.designerName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: KoalaColors.text)),
                      if (specialty.isNotEmpty)
                        Padding(padding: const EdgeInsets.only(top: 1), child: Text(specialty, style: const TextStyle(fontSize: 13, color: KoalaColors.textSec))),
                      const SizedBox(height: 3),
                      Row(children: [
                        Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF4CAF50))),
                        const SizedBox(width: 5),
                        Expanded(child: Text(
                          city.isNotEmpty ? 'Genellikle 24 saat i\u00e7inde yan\u0131tlar \u00b7 $city' : 'Genellikle 24 saat i\u00e7inde yan\u0131tlar',
                          style: const TextStyle(fontSize: 11, color: KoalaColors.textTer), overflow: TextOverflow.ellipsis,
                        )),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Portfolio — tıklanabilir
        if (_designerProjects.isNotEmpty)
          SizedBox(
            height: 62,
            child: ListView.separated(
              padding: const EdgeInsets.only(left: 20, right: 20, bottom: 8),
              scrollDirection: Axis.horizontal,
              itemCount: _designerProjects.length.clamp(0, 6),
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final img = (_designerProjects[i]['cover_image_url'] ?? _designerProjects[i]['cover_url'] ?? _designerProjects[i]['image_url'] ?? '').toString().trim();
                if (img.isEmpty) return const SizedBox.shrink();
                return GestureDetector(
                  onTap: () => _openProjectViewer(_designerProjects[i], i),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(img, width: 78, height: 54, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(width: 78, height: 54, color: KoalaColors.surfaceAlt)),
                  ),
                );
              },
            ),
          ),

        const Divider(height: 1, color: KoalaColors.borderSolid),
      ],
    );
  }

  Widget _buildConnecting() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween(begin: 0.4, end: 1.0).animate(_pulseController),
            child: Container(
              width: 72, height: 72,
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [KoalaColors.accent, KoalaColors.accentMuted]), boxShadow: KoalaShadows.accentGlow),
              child: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 32),
            ),
          ),
          const SizedBox(height: KoalaSpacing.xxl),
          Text("${widget.designerName}'e ba\u011flan\u0131l\u0131yor...", style: KoalaText.h3),
          const SizedBox(height: KoalaSpacing.sm),
          Text('Sohbet haz\u0131rlan\u0131yor', style: KoalaText.bodySec),
          const SizedBox(height: KoalaSpacing.xxl),
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: KoalaColors.accent)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KoalaSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: KoalaColors.error, size: 48),
            const SizedBox(height: KoalaSpacing.lg),
            Text(_errorMsg ?? 'Bir hata olu\u015ftu', style: KoalaText.body, textAlign: TextAlign.center),
            const SizedBox(height: KoalaSpacing.xxl),
            TextButton.icon(
              onPressed: () { setState(() => _state = _SheetState.connecting); _connect(); },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tekrar Dene'),
              style: TextButton.styleFrom(foregroundColor: KoalaColors.accent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChat() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, color: KoalaColors.textTer, size: 40),
            const SizedBox(height: KoalaSpacing.md),
            Text('Mesaj\u0131n\u0131z\u0131 yaz\u0131n ve g\u00f6nderin!', style: KoalaText.bodySec),
          ],
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notif) {
        if (notif is ScrollEndNotification && _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 100) _loadOlderMessages();
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.lg, vertical: KoalaSpacing.md),
        itemCount: _messages.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (_loadingMore && index == _messages.length) {
            return const Center(child: Padding(padding: EdgeInsets.all(KoalaSpacing.md), child: CircularProgressIndicator(strokeWidth: 2, color: KoalaColors.accent)));
          }
          return _PopupMessageBubble(message: _messages[index], isMe: _messages[index]['sender_id'] == _uid);
        },
      ),
    );
  }

  Widget _buildInputBar() {
    final media = MediaQuery.of(context);
    final keyboardUp = media.viewInsets.bottom > 0;
    return Container(
      padding: EdgeInsets.only(
        left: KoalaSpacing.lg, right: KoalaSpacing.sm, top: KoalaSpacing.sm,
        bottom: keyboardUp ? media.viewInsets.bottom + KoalaSpacing.sm : media.padding.bottom + KoalaSpacing.sm,
      ),
      decoration: const BoxDecoration(color: KoalaColors.surface, border: Border(top: BorderSide(color: KoalaColors.borderSolid, width: 0.5))),
      child: Row(
        children: [
          GestureDetector(
            onTap: _uploadingImage ? null : _pickAndSendImage,
            child: Padding(
              padding: const EdgeInsets.only(right: KoalaSpacing.sm),
              child: _uploadingImage
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: KoalaColors.accent))
                  : const Icon(Icons.camera_alt_rounded, color: KoalaColors.textSec, size: 24),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _textController, style: KoalaText.body, maxLines: 4, minLines: 1,
              textInputAction: TextInputAction.send, onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: '${widget.designerName} ile mesajla\u015f...', hintStyle: KoalaText.bodySec,
                filled: true, fillColor: KoalaColors.bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(KoalaRadius.xl), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.lg, vertical: KoalaSpacing.md),
              ),
            ),
          ),
          const SizedBox(width: KoalaSpacing.sm),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: _sending ? KoalaColors.accentLight : KoalaColors.accent, shape: BoxShape.circle),
              child: _sending
                  ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// PROJECT VIEWER — portfolio görseli tıklanınca açılır
// ═══════════════════════════════════════════════════════
class _ProjectViewerSheet extends StatefulWidget {
  const _ProjectViewerSheet({
    required this.project,
    required this.allProjects,
    required this.startIndex,
    required this.designerName,
    required this.designerId,
    required this.onAskAI,
  });

  final Map<String, dynamic> project;
  final List<Map<String, dynamic>> allProjects;
  final int startIndex;
  final String designerName;
  final String designerId;
  final void Function(String question, {String? hiddenContext}) onAskAI;

  @override
  State<_ProjectViewerSheet> createState() => _ProjectViewerSheetState();
}

class _ProjectViewerSheetState extends State<_ProjectViewerSheet> {
  late PageController _pageCtrl;
  late int _currentIndex;

  // Inline info state
  String? _styleAnswer;
  bool _styleLoading = false;
  bool _styleTapped = false;
  Map<String, dynamic>? _designerInfo;
  bool _designerTapped = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.startIndex;
    _pageCtrl = PageController(initialPage: widget.startIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _current => widget.allProjects[_currentIndex];

  String _coverUrl(Map<String, dynamic> project) {
    for (final key in ['cover_image_url', 'cover_url', 'image_url']) {
      final v = (project[key] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  /// "Bu tarz nedir?" — inline AI cevap
  Future<void> _askStyleInline() async {
    if (_styleTapped) return;
    setState(() { _styleTapped = true; _styleLoading = true; });
    try {
      final title = (_current['title'] ?? 'Proje').toString();
      final description = (_current['description'] ?? '').toString();
      final ai = KoalaAIService();
      final prompt = 'Kullanıcı "$title" adlı bir iç mimari tasarıma bakıyor. '
          '${description.isNotEmpty ? "Proje açıklaması: $description. " : ""}'
          'Tasarımcı: ${widget.designerName}. '
          'Bu tasarımın stilini kısaca analiz et. Sadece düz metin olarak 2-3 cümle yaz. '
          'Hangi tasarım akımına ait olabileceğini, muhtemel renk paletini ve malzeme seçimlerini belirt. '
          'JSON formatı kullanma, sadece düz Türkçe metin yaz.';
      final answer = await ai.askPlainText(prompt);
      if (mounted) setState(() { _styleAnswer = answer; _styleLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _styleAnswer = 'Stil analizi şu an yapılamadı.'; _styleLoading = false; });
    }
  }

  /// "Hakkında" — DB'den designer bilgisi
  Future<void> _showDesignerInfo() async {
    if (_designerTapped) return;
    setState(() => _designerTapped = true);
    try {
      if (!EvlumbaLiveService.isReady) {
        await EvlumbaLiveService.waitForReady(timeout: const Duration(seconds: 3));
      }
      final detail = await EvlumbaLiveService.getDesignerById(widget.designerId);
      final reviews = await EvlumbaLiveService.getDesignerReviews(widget.designerId);
      if (mounted) setState(() {
        _designerInfo = {
          ...?detail,
          '_review_count': reviews.length,
        };
      });
    } catch (_) {
      if (mounted) setState(() { _designerInfo = {'_error': true}; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = (_current['title'] ?? 'Proje').toString();
    final currentImageUrl = _coverUrl(_current);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40, height: 4,
              decoration: BoxDecoration(color: KoalaColors.borderSolid, borderRadius: BorderRadius.circular(2)),
            ),
          ),

          // Top bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: KoalaColors.textSec, size: 22),
                ),
                Expanded(
                  child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: KoalaColors.text), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
                ),
                // Page indicator
                Text('${_currentIndex + 1}/${widget.allProjects.length}', style: const TextStyle(fontSize: 13, color: KoalaColors.textTer)),
                const SizedBox(width: 12),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Image pager
          Expanded(
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: widget.allProjects.length,
              onPageChanged: (i) => setState(() {
                _currentIndex = i;
                // Sayfa değişince inline cevapları resetle
                _styleAnswer = null;
                _styleLoading = false;
                _styleTapped = false;
                _designerInfo = null;
                _designerTapped = false;
              }),
              itemBuilder: (_, i) {
                final url = _coverUrl(widget.allProjects[i]);
                if (url.isEmpty) return Container(color: KoalaColors.surfaceAlt, alignment: Alignment.center, child: const Icon(Icons.image_rounded, size: 48, color: KoalaColors.textTer));
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: KoalaColors.surfaceAlt)),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // AI smart chips + inline answers
          Expanded(
            flex: 0,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Koala AI\'a Sor', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: KoalaColors.textTer, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SmartChip(
                        icon: Icons.search_rounded,
                        label: 'Bu tasarımdaki ürünleri bul',
                        onTap: () {
                          final context = currentImageUrl.isNotEmpty
                              ? 'Tasarım: "$title", Tasarımcı: ${widget.designerName}, Görsel URL: $currentImageUrl. Bu görseldeki mobilya ve dekorasyon ürünlerini analiz et ve search_products ile Türkiye marketlerinden benzerlerini bul.'
                              : null;
                          widget.onAskAI('$title tasarımındaki ürünleri bul', hiddenContext: context);
                        },
                      ),
                      _SmartChip(
                        icon: Icons.palette_rounded,
                        label: 'Benzer tasarımlar göster',
                        onTap: () {
                          final context = currentImageUrl.isNotEmpty
                              ? 'Tasarım: "$title", Tasarımcı: ${widget.designerName}, Görsel URL: $currentImageUrl. Bu tasarıma benzer projeleri search_projects ile bul.'
                              : null;
                          widget.onAskAI('$title tasarımına benzer projeler göster', hiddenContext: context);
                        },
                      ),
                      _SmartChip(
                        icon: Icons.style_rounded,
                        label: 'Bu tarz nedir?',
                        disabled: _styleTapped,
                        loading: _styleLoading,
                        onTap: _askStyleInline,
                      ),
                      _SmartChip(
                        icon: Icons.person_search_rounded,
                        label: '${widget.designerName} hakkında',
                        disabled: _designerTapped,
                        onTap: _showDesignerInfo,
                      ),
                    ],
                  ),

                  // Inline: Stil analizi cevabı
                  if (_styleLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: KoalaColors.accent)),
                          SizedBox(width: 8),
                          Text('Stil analiz ediliyor...', style: TextStyle(fontSize: 12, color: KoalaColors.textSec)),
                        ],
                      ),
                    ),
                  if (_styleAnswer != null)
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: KoalaColors.accentSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: KoalaColors.accent.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.style_rounded, size: 16, color: KoalaColors.accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _styleAnswer!,
                              style: const TextStyle(fontSize: 13, color: KoalaColors.text, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Inline: Tasarımcı bilgisi
                  if (_designerTapped && _designerInfo == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: KoalaColors.accent)),
                          SizedBox(width: 8),
                          Text('Bilgiler yükleniyor...', style: TextStyle(fontSize: 12, color: KoalaColors.textSec)),
                        ],
                      ),
                    ),
                  if (_designerInfo != null)
                    _buildDesignerInfoCard(),
                ],
              ),
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }

  Widget _buildDesignerInfoCard() {
    if (_designerInfo?['_error'] == true) {
      return Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: KoalaColors.surfaceAlt, borderRadius: BorderRadius.circular(12)),
        child: const Text('Tasarımcı bilgisi yüklenemedi.', style: TextStyle(fontSize: 13, color: KoalaColors.textSec)),
      );
    }

    final d = _designerInfo!;
    final name = (d['full_name'] ?? widget.designerName).toString();
    final specialty = (d['specialty'] ?? '').toString();
    final city = (d['city'] ?? '').toString();
    final reviewCount = (d['_review_count'] ?? 0) as int;
    final avatarUrl = (d['avatar_url'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KoalaColors.accentSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KoalaColors.accent.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          // Mini avatar
          Container(
            width: 40, height: 40,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [KoalaColors.accent, KoalaColors.accentMuted])),
            child: avatarUrl.isNotEmpty
                ? ClipOval(child: Image.network(avatarUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Center(child: Text(name.isNotEmpty ? name[0] : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)))))
                : Center(child: Text(name.isNotEmpty ? name[0] : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: KoalaColors.text)),
                if (specialty.isNotEmpty || city.isNotEmpty)
                  Text(
                    [if (specialty.isNotEmpty) specialty, if (city.isNotEmpty) city].join(' · '),
                    style: const TextStyle(fontSize: 12, color: KoalaColors.textSec),
                  ),
                if (reviewCount > 0)
                  Text('$reviewCount değerlendirme', style: const TextStyle(fontSize: 11, color: KoalaColors.textTer)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmartChip extends StatelessWidget {
  const _SmartChip({required this.icon, required this.label, required this.onTap, this.disabled = false, this.loading = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool disabled;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final color = disabled ? KoalaColors.textTer : KoalaColors.accent;
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: disabled ? KoalaColors.surfaceAlt : KoalaColors.accentSoft,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: disabled ? KoalaColors.border : KoalaColors.accent.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: KoalaColors.accent))
            else
              Icon(disabled ? Icons.check_circle_rounded : icon, size: 15, color: color),
            const SizedBox(width: 6),
            Flexible(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color))),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// MESSAGE BUBBLE
// ═══════════════════════════════════════════════════════
class _PopupMessageBubble extends StatelessWidget {
  const _PopupMessageBubble({required this.message, required this.isMe});
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
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.lg, vertical: KoalaSpacing.md),
        decoration: BoxDecoration(
          color: isMe ? KoalaColors.accent : KoalaColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(KoalaRadius.lg), topRight: const Radius.circular(KoalaRadius.lg),
            bottomLeft: Radius.circular(isMe ? KoalaRadius.lg : KoalaRadius.xs),
            bottomRight: Radius.circular(isMe ? KoalaRadius.xs : KoalaRadius.lg),
          ),
          border: isMe ? null : Border.all(color: KoalaColors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (type == 'image' && message['attachment_url'] != null)
              ClipRRect(borderRadius: BorderRadius.circular(KoalaRadius.sm), child: Image.network(message['attachment_url'] as String, width: 180, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: KoalaColors.textTer))),
            if (content.isNotEmpty) Text(content, style: TextStyle(fontSize: 14, color: isMe ? Colors.white : KoalaColors.text, height: 1.4)),
            const SizedBox(height: 3),
            Text(timeStr, style: TextStyle(fontSize: 10, color: isMe ? Colors.white60 : KoalaColors.textTer)),
          ],
        ),
      ),
    );
  }
}
