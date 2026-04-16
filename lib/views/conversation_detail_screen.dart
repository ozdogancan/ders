import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/koala_tokens.dart';
import '../services/evlumba_live_service.dart';
import '../services/global_message_listener.dart';
import '../services/koala_ai_service.dart';
import '../services/messaging_service.dart';
import '../services/saved_items_service.dart';
import '../widgets/koala_widgets.dart';
import '../widgets/save_button.dart';
import 'chat_detail_screen.dart';

/// Tasarımcı ile mesaj detay ekranı — gerçek zamanlı
class ConversationDetailScreen extends StatefulWidget {
  const ConversationDetailScreen({
    super.key,
    required this.conversationId,
    this.designerId,
    this.designerName = 'Tasarımcı',
    this.designerAvatarUrl,
    this.projectTitle,
    this.unreadOnEntry,
  });

  final String conversationId;
  final String? designerId;
  final String designerName;
  final String? designerAvatarUrl;
  final String? projectTitle;

  /// Chat list ekranı tapta markAsRead fire-and-forget tetikliyor, o yüzden
  /// detail açıldığında DB'den okuduğumuz unread_count zaten 0 olabiliyor.
  /// "Yeni mesajlar" divider'ını doğru hesaplamak için chat list bu sayıyı
  /// navigation extra ile aktarıyor. null ise detail screen DB'den fetch eder
  /// (toast tap / deep link yolunda markAsRead henüz çağrılmamıştır).
  final int? unreadOnEntry;

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

  /// Oldest unread message ID on entry. "Yeni mesajlar" divider bunun üstünde
  /// gözükür ve ilk frame'de ekran buraya pozisyonlanır. markAsRead UI'ı
  /// bozmasın diye bu değer session boyunca sabit kalır — divider kaybolmaz.
  ///
  /// NOT: production DB'de koala_direct_messages.read_at kolonu yok; unread
  /// sayısı koala_conversations.unread_count_user/designer'dan geliyor. Giriş
  /// anında bu sayıyı bir kere okuyup N en yeni designer mesajını "unread"
  /// olarak işaretliyoruz; divider N'inci (en eski unread) bubble'ın üstünde
  /// duruyor.
  String? _firstUnreadId;
  final _firstUnreadKey = GlobalKey();

  // Portfolio header collapse state — varsayılan KAPALI, yer kaplamasın.
  bool _portfolioExpanded = false;

  // Conversation-level realtime listener — backend pullInbound her 3s unread'i
  // yeniden hesapladığından, biz bu ekrana bakarken unread>0 bump olursa
  // HEMEN markAsRead çağır. Aksi halde badge sürekli geri "1" olur.
  void Function(Map<String, dynamic>)? _convListener;

  // Designer detay bilgileri
  Map<String, dynamic>? _designerDetail;
  List<Map<String, dynamic>> _designerProjects = [];
  Map<String, dynamic>? _contextProject; // projectTitle'a eşleşen proje (varsa)

  @override
  void initState() {
    super.initState();
    _uid = MessagingService.currentUserId;
    // _loadMessages() kendi sonunda markAsRead çağırıyor — önce unread sayısını
    // oku, divider'ı hesapla, sonra read flag'ini indir. Eski init'te _markRead
    // paralel çalışıp unread sayısını sıfırlayabiliyordu ve divider kayboluyordu.
    _loadMessages();
    _subscribeRealtime();
    _subscribeConversationUpdates();
    _scrollController.addListener(_onScroll);
    _loadDesignerDetail();
    // Global toast bu conv'un detay ekranındayken suppress edilsin —
    // kullanıcı mesajı zaten görüyor, tekrar toast göstermeye gerek yok.
    GlobalMessageListener.suppressConvId = widget.conversationId;
  }

  @override
  void dispose() {
    if (GlobalMessageListener.suppressConvId == widget.conversationId) {
      GlobalMessageListener.suppressConvId = null;
    }
    MessagingService.unsubscribeFromMessages(widget.conversationId);
    try {
      MessagingService.unsubscribeFromConversations(listener: _convListener);
    } catch (_) {}
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDesignerDetail() async {
    if (widget.designerId == null || widget.designerId!.isEmpty) return;
    try {
      if (!EvlumbaLiveService.isReady) {
        await EvlumbaLiveService.waitForReady(timeout: const Duration(seconds: 5));
      }
      if (!EvlumbaLiveService.isReady) return;

      final detail = await EvlumbaLiveService.getDesignerById(widget.designerId!);
      final projects = await EvlumbaLiveService.getDesignerProjects(
        widget.designerId!,
        limit: 30,
      );

      // projectTitle verildiyse eşleşen projeyi bul — mesaj alanında kart olarak göstereceğiz
      Map<String, dynamic>? matched;
      final ctxTitle = widget.projectTitle?.trim();
      if (ctxTitle != null && ctxTitle.isNotEmpty && projects.isNotEmpty) {
        for (final p in projects) {
          if ((p['title'] ?? '').toString().trim() == ctxTitle) {
            matched = p;
            break;
          }
        }
      }

      if (mounted) {
        setState(() {
          _designerDetail = detail;
          _designerProjects = projects;
          _contextProject = matched;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadMessages() async {
    // 1) markAsRead'den ÖNCE unread sayısını oku — read flag indirildiğinde
    //    sayı 0'a düşüyor; divider hesabı kayboluyor.
    // Chat list tap yolunda markAsRead navigation'dan önce fire ediliyor,
    // bu yüzden getConversation race ile 0 dönebiliyor. widget.unreadOnEntry
    // varsa (>=0) onu kullan — chat list'in tap anında yakaladığı gerçek
    // sayı. Yoksa (toast / deep link) DB'den oku.
    int unreadOnEntry = 0;
    if (_firstUnreadId == null) {
      final hint = widget.unreadOnEntry;
      if (hint != null && hint > 0) {
        unreadOnEntry = hint;
      } else {
        try {
          final conv =
              await MessagingService.getConversation(widget.conversationId);
          if (conv != null) {
            final isUser = conv['user_id'] == _uid;
            unreadOnEntry = isUser
                ? ((conv['unread_count_user'] as int?) ?? 0)
                : ((conv['unread_count_designer'] as int?) ?? 0);
          }
        } catch (_) {}
      }
    }

    final data = await MessagingService.getMessages(
      conversationId: widget.conversationId,
    );
    if (!mounted) return;

    // Entry'de, diğer tarafın attığı son N mesajı "unread" kabul et (N =
    // conversation seviyesi unread_count). data DESC sıralı (newest first):
    // sırayla karşıdan gelen mesajları say, N'inciyi (en eski unread) divider
    // konumu olarak işaretle.
    String? firstUnreadId;
    if (_firstUnreadId == null && unreadOnEntry > 0) {
      int seen = 0;
      for (final m in data) {
        final sender = m['sender_id']?.toString();
        if (sender != null && sender != _uid) {
          seen++;
          firstUnreadId = m['id']?.toString();
          if (seen >= unreadOnEntry) break;
        }
      }
    }

    setState(() {
      _messages = data;
      _loading = false;
      _firstUnreadId ??= firstUnreadId;
    });

    // Divider'a scroll — sadece bu oturumda ilk açılışta.
    if (_firstUnreadId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToFirstUnread();
      });
    }

    // Son adım: mesajlar ve divider konumlandıktan sonra read flag indir.
    // İlk frame render olsun diye kısa gecikme — divider post-frame scroll'u
    // atılmadan önce unread sayacı sıfırlanırsa UI'da flicker olabilir.
    Future<void>.delayed(const Duration(milliseconds: 60), () {
      if (!mounted) return;
      _markRead();
    });
  }

  void _scrollToFirstUnread() {
    final ctx = _firstUnreadKey.currentContext;
    if (ctx == null) return;
    try {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.3, // divider ekranın üst 1/3 kısmında
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } catch (_) {}
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
          if (msg['sender_id'] != _uid) {
            MessagingService.markAsRead(widget.conversationId);
          }
        }
      },
    );
  }

  /// Konuşma UPDATE event'lerini dinle — unread_count_user sıfırdan büyük
  /// bump olursa HEMEN tekrar markAsRead çağır. Backend inbound sync her 3s
  /// unread sayısını recompute ediyor; bu ekran açıkken yeni mesaj geldiğinde
  /// badge'in 1'e çıkıp kalmasını önlüyor.
  void _subscribeConversationUpdates() {
    _convListener = (record) {
      if (!mounted) return;
      final convId = record['id']?.toString();
      if (convId != widget.conversationId) return;
      final uid = MessagingService.currentUserId;
      final isUser = record['user_id'] == uid;
      final unreadNow = isUser
          ? ((record['unread_count_user'] as int?) ?? 0)
          : ((record['unread_count_designer'] as int?) ?? 0);
      if (unreadNow > 0) {
        MessagingService.markAsRead(widget.conversationId);
      }
    };
    MessagingService.subscribeToConversations(onUpdate: _convListener!);
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
      final ext = picked.path.split('.').last.toLowerCase();
      const allowedExt = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'};
      if (!allowedExt.contains(ext)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Desteklenmeyen dosya türü')),
          );
        }
        setState(() => _uploadingImage = false);
        return;
      }
      final fileName = '${_uid ?? 'anon'}/${DateTime.now().millisecondsSinceEpoch}.$ext';

      await Supabase.instance.client.storage
          .from('message-images')
          .uploadBinary(fileName, bytes);

      final imageUrl = Supabase.instance.client.storage
          .from('message-images')
          .getPublicUrl(fileName);

      await MessagingService.sendMessage(
        conversationId: widget.conversationId,
        content: '\u{1F4F7} Fotoğraf',
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

  void _openDesignerProfile() {
    if (widget.designerId == null) return;
    final url = 'https://www.evlumba.com/tasarimci/${widget.designerId}';
    launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
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
        designerId: widget.designerId ?? '',
        onAskAI: (question, {String? hiddenContext}) {
          Navigator.of(context).pop(); // viewer kapat
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
    final keyboardUp = media.viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: KoalaColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Zengin Header ──
            _buildHeader(),

            // Spesifik projeden geldiyse — mesaj alanının üstünde sabit bağlam kartı
            if (_contextProject != null) _buildContextProjectCard(),

            // Messages
            Expanded(
              child: _loading
                  ? const LoadingState()
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
                            final m = _messages[index];
                            final isMe = m['sender_id'] == _uid;
                            final msgId = m['id']?.toString();
                            // Divider: bu mesaj ilk unread ise üstüne (reverse
                            // list'te "üst" = daha sonra gelen index) yerleştir.
                            // reverse:true → görsel sıra: eski alta, yeni üste
                            // aslında tersi: reverse list 0=bottom visual, so
                            // yeni mesajlar GÖRSEL olarak alt. Divider ilk
                            // unread'ın üzerinde gözükmesi için bu message
                            // widget'ı altına divider eklemek lazım (reverse'te
                            // altına = visual üstüne).
                            final isFirstUnread =
                                _firstUnreadId != null && msgId == _firstUnreadId;
                            if (isFirstUnread) {
                              // reverse:true → Column çocukları normal yukarı-
                              // aşağı akar ama TÜM liste alttan üste akar.
                              // Divider'ı Column'un üstüne koyarsak bubble'ın
                              // GÖRSEL olarak ÜSTÜNDE gözükür — yani kullanıcı
                              // aşağı kaydırdıkça önce "Yeni mesajlar" çizgisi,
                              // sonra ilk unread bubble.
                              return Column(
                                key: _firstUnreadKey,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const _NewMessagesDivider(),
                                  _MessageBubble(message: m, isMe: isMe),
                                ],
                              );
                            }
                            return _MessageBubble(message: m, isMe: isMe);
                          },
                        ),
            ),

            // Input bar
            Container(
              padding: EdgeInsets.only(
                left: KoalaSpacing.lg,
                right: KoalaSpacing.sm,
                top: KoalaSpacing.sm,
                bottom: keyboardUp
                    ? media.viewInsets.bottom + KoalaSpacing.sm
                    : media.padding.bottom + KoalaSpacing.sm,
              ),
              decoration: const BoxDecoration(
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
                        hintText: '${widget.designerName} ile mesajlaş...',
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
      ),
    );
  }

  Widget _buildHeader() {
    final initials = widget.designerName
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();

    final specialty = (_designerDetail?['specialty'] ?? '').toString().trim();
    final city = (_designerDetail?['city'] ?? '').toString().trim();

    return Container(
      color: KoalaColors.surface,
      child: Column(
        children: [
          // Top row: back + actions
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 8, top: 4),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: KoalaColors.text, size: 22),
                ),
                const Spacer(),
                if (widget.designerId != null)
                  SaveButton(
                    itemType: SavedItemType.designer,
                    itemId: widget.designerId!,
                    title: widget.designerName,
                    subtitle: specialty.isNotEmpty ? specialty : 'İç Mimar',
                    size: 20,
                  ),
                IconButton(
                  onPressed: _openDesignerProfile,
                  icon: const Icon(Icons.open_in_new_rounded,
                      color: KoalaColors.textSec, size: 20),
                  tooltip: 'Profili Gör',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),

          // Designer info
          GestureDetector(
            onTap: _openDesignerProfile,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar
                  Container(
                    width: 52,
                    height: 52,
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
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white)),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(initials,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.designerName,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: KoalaColors.text,
                          ),
                        ),
                        if (specialty.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              specialty,
                              style: const TextStyle(
                                fontSize: 13,
                                color: KoalaColors.textSec,
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF4CAF50),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                city.isNotEmpty
                                    ? 'Genellikle 24 saat içinde yanıtlar \u00b7 $city'
                                    : 'Genellikle 24 saat içinde yanıtlar',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: KoalaColors.textTer,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Portfolio — varsayılan KAPALI (yer kaplamasın), tıklanınca açılır.
          if (_designerProjects.isNotEmpty) _buildPortfolioSection(),

          const Divider(height: 1, color: KoalaColors.borderSolid),
        ],
      ),
    );
  }

  /// Tüm Tasarımlar header + collapse/expand — varsayılan kapalı.
  /// Kapalıyken: tek satır başlık + ilk 4 mini thumbnail + genişlet ikonu.
  /// Açıkken: mevcut 124px ListView görünümü.
  Widget _buildPortfolioSection() {
    final count = _designerProjects.length;
    final previewCount = count < 4 ? count : 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _portfolioExpanded = !_portfolioExpanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 14, 8),
            child: Row(
              children: [
                const Icon(Icons.collections_rounded,
                    size: 14, color: KoalaColors.textTer),
                const SizedBox(width: 6),
                Text(
                  'Tüm Tasarımlar ($count)',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: KoalaColors.textTer,
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                // Kapalıyken ilk 4 proje mini-avatar şerit olarak görünür
                if (!_portfolioExpanded)
                  SizedBox(
                    height: 26,
                    child: Stack(
                      children: List.generate(previewCount, (i) {
                        final p = _designerProjects[i];
                        final img = (p['cover_image_url'] ??
                                p['cover_url'] ??
                                p['image_url'] ??
                                '')
                            .toString()
                            .trim();
                        return Positioned(
                          left: i * 18.0,
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: KoalaColors.surface, width: 1.5),
                              color: KoalaColors.surfaceAlt,
                            ),
                            child: ClipOval(
                              child: img.isNotEmpty
                                  ? Image.network(img,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const SizedBox())
                                  : const Icon(Icons.image_outlined,
                                      size: 12, color: KoalaColors.textTer),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                if (!_portfolioExpanded)
                  SizedBox(width: (previewCount * 18.0) + 6),
                Icon(
                  _portfolioExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: KoalaColors.textSec,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _portfolioExpanded
              ? SizedBox(
                  height: 124,
                  child: ListView.separated(
                    padding: const EdgeInsets.only(
                        left: 20, right: 20, bottom: 12),
                    scrollDirection: Axis.horizontal,
                    itemCount: _designerProjects.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) {
                      final project = _designerProjects[i];
                      final img = (project['cover_image_url'] ??
                              project['cover_url'] ??
                              project['image_url'] ??
                              '')
                          .toString()
                          .trim();
                      final title = (project['title'] ?? '').toString().trim();
                      final isContext = widget.projectTitle != null &&
                          widget.projectTitle!.trim() == title;

                      return GestureDetector(
                        onTap: () => _openProjectViewer(project, i),
                        child: SizedBox(
                          width: 130,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: img.isNotEmpty
                                        ? Image.network(
                                            img,
                                            width: 130,
                                            height: 86,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Container(
                                              width: 130,
                                              height: 86,
                                              color: KoalaColors.surfaceAlt,
                                              child: const Icon(
                                                  Icons.image_not_supported_outlined,
                                                  size: 20,
                                                  color: KoalaColors.textTer),
                                            ),
                                          )
                                        : Container(
                                            width: 130,
                                            height: 86,
                                            color: KoalaColors.surfaceAlt,
                                            child: const Icon(Icons.image_outlined,
                                                size: 20,
                                                color: KoalaColors.textTer),
                                          ),
                                  ),
                                  if (isContext)
                                    Positioned(
                                      top: 6,
                                      left: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: KoalaColors.accent,
                                          borderRadius: BorderRadius.circular(
                                              KoalaRadius.pill),
                                        ),
                                        child: const Text(
                                          'Bu Proje',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (title.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    title,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: KoalaColors.text,
                                      height: 1.25,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// Spesifik projeden gelindiğinde mesaj alanının üstünde pinli gösterilen kart
  Widget _buildContextProjectCard() {
    final project = _contextProject!;
    final img = (project['cover_image_url'] ??
            project['cover_url'] ??
            project['image_url'] ??
            '')
        .toString()
        .trim();
    final title = (project['title'] ?? '').toString().trim();
    final room = (project['room_type'] ?? project['category'] ?? '').toString().trim();

    // Index bul — tıklanınca açmak için
    final idx = _designerProjects.indexOf(project);

    return GestureDetector(
      onTap: idx >= 0 ? () => _openProjectViewer(project, idx) : null,
      child: Container(
        margin: const EdgeInsets.fromLTRB(KoalaSpacing.lg, KoalaSpacing.md, KoalaSpacing.lg, 0),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: KoalaColors.accentSoft,
          borderRadius: BorderRadius.circular(KoalaRadius.md),
          border: Border.all(color: KoalaColors.accent.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: img.isNotEmpty
                  ? Image.network(
                      img,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 52,
                        height: 52,
                        color: KoalaColors.surfaceAlt,
                        child: const Icon(Icons.image_outlined, size: 18, color: KoalaColors.textTer),
                      ),
                    )
                  : Container(
                      width: 52,
                      height: 52,
                      color: KoalaColors.surfaceAlt,
                      child: const Icon(Icons.image_outlined, size: 18, color: KoalaColors.textTer),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.push_pin_rounded, size: 11, color: KoalaColors.accent),
                      SizedBox(width: 4),
                      Text(
                        'Mesajlaştığınız proje',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: KoalaColors.accent,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title.isNotEmpty ? title : 'Proje',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: KoalaColors.text,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (room.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        room,
                        style: const TextStyle(
                          fontSize: 11,
                          color: KoalaColors.textSec,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: KoalaColors.accent),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// PROJECT VIEWER — portfolio görseli tıklanınca
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
  void dispose() { _pageCtrl.dispose(); super.dispose(); }

  Map<String, dynamic> get _current => widget.allProjects[_currentIndex];

  String _coverUrl(Map<String, dynamic> p) {
    for (final k in ['cover_image_url', 'cover_url', 'image_url']) {
      final v = (p[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

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
        _designerInfo = { ...?detail, '_review_count': reviews.length };
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
      decoration: const BoxDecoration(color: KoalaColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        children: [
          Center(child: Container(margin: const EdgeInsets.only(top: 10, bottom: 6), width: 40, height: 4, decoration: BoxDecoration(color: KoalaColors.borderSolid, borderRadius: BorderRadius.circular(2)))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded, color: KoalaColors.textSec, size: 22)),
                Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: KoalaColors.text), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis)),
                Text('${_currentIndex + 1}/${widget.allProjects.length}', style: const TextStyle(fontSize: 13, color: KoalaColors.textTer)),
                const SizedBox(width: 12),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: PageView.builder(
              controller: _pageCtrl, itemCount: widget.allProjects.length,
              onPageChanged: (i) => setState(() {
                _currentIndex = i;
                _styleAnswer = null; _styleLoading = false; _styleTapped = false;
                _designerInfo = null; _designerTapped = false;
              }),
              itemBuilder: (_, i) {
                final url = _coverUrl(widget.allProjects[i]);
                if (url.isEmpty) return Container(color: KoalaColors.surfaceAlt, alignment: Alignment.center, child: const Icon(Icons.image_rounded, size: 48, color: KoalaColors.textTer));
                return Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: KoalaColors.surfaceAlt))));
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
                  const Text("Koala AI'a Sor", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: KoalaColors.textTer, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _SmartChip(
                      icon: Icons.search_rounded,
                      label: 'Bu tasarımdaki ürünleri bul',
                      onTap: () {
                        final ctx = currentImageUrl.isNotEmpty
                            ? 'Tasarım: "$title", Tasarımcı: ${widget.designerName}, Görsel URL: $currentImageUrl. Bu görseldeki mobilya ve dekorasyon ürünlerini analiz et ve search_products ile Türkiye marketlerinden benzerlerini bul.'
                            : null;
                        widget.onAskAI('$title tasarımındaki ürünleri bul', hiddenContext: ctx);
                      },
                    ),
                    _SmartChip(
                      icon: Icons.palette_rounded,
                      label: 'Benzer tasarımlar göster',
                      onTap: () {
                        final ctx = currentImageUrl.isNotEmpty
                            ? 'Tasarım: "$title", Tasarımcı: ${widget.designerName}, Görsel URL: $currentImageUrl. Bu tasarıma benzer projeleri search_projects ile bul.'
                            : null;
                        widget.onAskAI('$title tasarımına benzer projeler göster', hiddenContext: ctx);
                      },
                    ),
                    _SmartChip(icon: Icons.style_rounded, label: 'Bu tarz nedir?', disabled: _styleTapped, loading: _styleLoading, onTap: _askStyleInline),
                    _SmartChip(icon: Icons.person_search_rounded, label: '${widget.designerName} hakkında', disabled: _designerTapped, onTap: _showDesignerInfo),
                  ]),

                  // Inline: Stil analizi
                  if (_styleLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Row(children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: KoalaColors.accent)),
                        SizedBox(width: 8),
                        Text('Stil analiz ediliyor...', style: TextStyle(fontSize: 12, color: KoalaColors.textSec)),
                      ]),
                    ),
                  if (_styleAnswer != null)
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: KoalaColors.accentSoft, borderRadius: BorderRadius.circular(12), border: Border.all(color: KoalaColors.accent.withValues(alpha: 0.15))),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.style_rounded, size: 16, color: KoalaColors.accent),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_styleAnswer!, style: const TextStyle(fontSize: 13, color: KoalaColors.text, height: 1.4))),
                      ]),
                    ),

                  // Inline: Tasarımcı bilgisi
                  if (_designerTapped && _designerInfo == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Row(children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: KoalaColors.accent)),
                        SizedBox(width: 8),
                        Text('Bilgiler yükleniyor...', style: TextStyle(fontSize: 12, color: KoalaColors.textSec)),
                      ]),
                    ),
                  if (_designerInfo != null) _buildDesignerInfoCard(),
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
        margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(12),
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
      margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: KoalaColors.accentSoft, borderRadius: BorderRadius.circular(12), border: Border.all(color: KoalaColors.accent.withValues(alpha: 0.15))),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [KoalaColors.accent, KoalaColors.accentMuted])),
          child: avatarUrl.isNotEmpty
              ? ClipOval(child: Image.network(avatarUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Center(child: Text(name.isNotEmpty ? name[0] : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)))))
              : Center(child: Text(name.isNotEmpty ? name[0] : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: KoalaColors.text)),
          if (specialty.isNotEmpty || city.isNotEmpty)
            Text([if (specialty.isNotEmpty) specialty, if (city.isNotEmpty) city].join(' · '), style: const TextStyle(fontSize: 12, color: KoalaColors.textSec)),
          if (reviewCount > 0)
            Text('$reviewCount değerlendirme', style: const TextStyle(fontSize: 11, color: KoalaColors.textTer)),
        ])),
      ]),
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
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (loading)
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: KoalaColors.accent))
          else
            Icon(disabled ? Icons.check_circle_rounded : icon, size: 15, color: color),
          const SizedBox(width: 6),
          Flexible(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color))),
        ]),
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

// ═══════════════════════════════════════════════════════
// UNREAD DIVIDER (WhatsApp tarzı "Yeni mesajlar" çizgisi)
// ═══════════════════════════════════════════════════════
class _NewMessagesDivider extends StatelessWidget {
  const _NewMessagesDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: KoalaSpacing.sm,
        horizontal: KoalaSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              color: KoalaColors.accent.withValues(alpha: 0.35),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.sm),
            child: Text(
              'Yeni mesajlar',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: KoalaColors.accent.withValues(alpha: 0.9),
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              color: KoalaColors.accent.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }
}
