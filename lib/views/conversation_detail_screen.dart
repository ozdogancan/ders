import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../core/theme/koala_tokens.dart';
import '../core/utils/format_utils.dart';
import '../services/evlumba_live_service.dart';
import '../services/global_message_listener.dart';
import '../services/koala_ai_service.dart';
import '../services/messaging_service.dart';
import '../widgets/koala_widgets.dart';
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
  final _picker = ImagePicker();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _loadingMore = false;
  String? _uid;

  /// Picker'dan seçilen ama henüz gönderilmemiş foto (bytes).
  /// Input'un üstünde preview kartı gösterilir; opsiyonel metinle send'e basınca
  /// optimize edilip Storage'a yüklenir ve mesaj olarak gönderilir.
  Uint8List? _pendingPhoto;

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

  /// İlk unread'e scroll — reverse:true list'te "üstte" göstermek için
  /// `alignment: 1.0` kullanıyoruz. Neden 1.0?
  ///   reverse:true → AxisDirection.up → leading = viewport BOTTOM,
  ///   trailing = viewport TOP. Dolayısıyla alignment 1.0 = trailing =
  ///   divider viewport'un TEPESİNE yerleşir. 0.3 kullanınca (eski kod)
  ///   divider %70 alttan çıkıp "üstte" görünmüyordu.
  ///
  /// Ayrıca ListView.builder lazy, hedef bubble henüz render edilmemişse
  /// `_firstUnreadKey.currentContext` null dönüyor; önce estimated offset'e
  /// jump edip widget'ı tree'ye sokuyoruz, sonra precise alignment için
  /// ensureVisible çağırıyoruz.
  Future<void> _scrollToFirstUnread() async {
    if (_firstUnreadId == null || !_scrollController.hasClients) return;
    if (!mounted) return;

    final idx = _messages.indexWhere(
      (m) => m['id']?.toString() == _firstUnreadId,
    );
    if (idx < 0) return;

    // Step 1: estimated pre-jump. Bubble ortalama ~80px; idx*80 → reverse
    // list'te hedefin viewport'a yakın olduğu scroll offset'i. Küçük bir
    // headroom ekleyip max'a clamp ediyoruz.
    try {
      final estimated = (idx * 80.0 - 120.0)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.jumpTo(estimated);
    } catch (_) {}

    // Step 2: layout pass için bir frame bekle, sonra precise ensureVisible.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final ctx = _firstUnreadKey.currentContext;
    if (ctx == null) return;
    try {
      await Scrollable.ensureVisible(
        ctx,
        alignment: 1.0, // reverse:true → 1.0 = viewport TOP
        duration: const Duration(milliseconds: 300),
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

  /// Send button: text + opsiyonel _pendingPhoto'yu birlikte gönderir.
  /// _pendingPhoto varsa: optimize → Storage upload → image type message
  /// (caption = text). Sadece text varsa: text type message.
  Future<void> _sendMessage() async {
    if (_sending) return;
    final text = _textController.text.trim();
    final photo = _pendingPhoto;
    if (text.isEmpty && photo == null) return;

    _textController.clear();
    setState(() {
      _sending = true;
      _pendingPhoto = null;
    });

    try {
      if (photo != null) {
        // Foto var → upload + image message (caption = text)
        final fileName =
            '${_uid ?? 'anon'}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        try {
          await Supabase.instance.client.storage
              .from('message-images')
              .uploadBinary(
                fileName,
                photo,
                fileOptions: const FileOptions(contentType: 'image/jpeg'),
              );
          final imageUrl = Supabase.instance.client.storage
              .from('message-images')
              .getPublicUrl(fileName);

          await MessagingService.sendMessage(
            conversationId: widget.conversationId,
            content: text, // caption (boş olabilir)
            type: MessageType.image,
            attachmentUrl: imageUrl,
          );
        } catch (e) {
          // Hata detayını göster — bucket/RLS/network sorununu bilmemiz lazım.
          debugPrint('[DM upload] error: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Görsel yüklenemedi: ${e.toString().split('\n').first}',
                ),
                duration: const Duration(seconds: 6),
              ),
            );
          }
        }
      } else {
        // Sadece text
        await MessagingService.sendMessage(
          conversationId: widget.conversationId,
          content: text,
        );
      }

      // Chat list'in sıralamayı güncellemesi için zorla tetikle
      // (Realtime UPDATE event'i bazen Firebase-auth'lu client'a düşmüyor)
      try {
        GlobalMessageListener.syncTick.value++;
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Picker bottom sheet: web'de doğrudan galeri, mobilde kamera/galeri seçimi.
  void _showPicker() {
    HapticFeedback.lightImpact();

    if (kIsWeb) {
      _doPick(ImageSource.gallery);
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: Colors.grey.shade300,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _pickBtn(Icons.camera_alt_rounded, 'Kamera', () {
                    Navigator.pop(context);
                    _doPick(ImageSource.camera);
                  }),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _pickBtn(Icons.photo_library_rounded, 'Galeri', () {
                    Navigator.pop(context);
                    _doPick(ImageSource.gallery);
                  }),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _doPick(ImageSource src) async {
    // image_picker built-in compression: long edge ~1280px, JPEG quality 70
    // Web'de zaten browser canvas ile yapılır; mobile'da plugin'in native
    // resize'ı çalışır. Ekstra image package decode/encode overhead yok.
    final f = await _picker.pickImage(
      source: src,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 70,
    );
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (!mounted) return;
    setState(() => _pendingPhoto = bytes);
  }

  Widget _pickBtn(IconData icon, String label, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: KoalaColors.accentLight,
          ),
          child: Column(
            children: [
              Icon(icon, size: 28, color: KoalaColors.accent),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: KoalaColors.text,
                ),
              ),
            ],
          ),
        ),
      );

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
    // Scaffold default `resizeToAvoidBottomInset: true` body'yi klavye yüksekliği
    // kadar yukarı kaydırıyor → input bar otomatik klavye üstünde olur.
    // Padding olarak SADECE safe-area'yı ekle, viewInsets.bottom'ı tekrar
    // eklersen "çift sayım" yapıp input klavyeden çok uzakta kalır.

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
                          // Lazy render hedef unread bubble'ı tree dışında
                          // bırakıyordu → _firstUnreadKey.currentContext null
                          // dönüp ensureVisible sessizce pas geçiyordu. 3000px
                          // cache ile ~30 mesaj tamamı önden build edilir.
                          cacheExtent: 3000,
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

            // Photo preview — picker'dan seçilen foto, send'e basana kadar burada
            if (_pendingPhoto != null) _buildPhotoPreview(),

            // Input bar — anasayfadaki TypewriterInput stiliyle aynı.
            // Scaffold body'yi klavye için zaten kaydırdı, biz yalnızca safe
            // area padding'ini ekliyoruz (chat_detail_screen ile aynı pattern).
            _buildInputBar(bottomPadding: media.padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoPreview() => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _pendingPhoto!,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => setState(() => _pendingPhoto = null),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Foto eklendi · isteğe bağlı bir not yazıp gönder',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: KoalaColors.textSec,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildInputBar({required double bottomPadding}) {
    final hasText = _textController.text.trim().isNotEmpty;
    final canSend = hasText || _pendingPhoto != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 2, 16, bottomPadding + 16),
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: Colors.white.withValues(alpha: 0.8),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: _sending ? null : _showPicker,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.04),
                  ),
                  child: const Icon(
                    LucideIcons.image,
                    size: 18,
                    color: KoalaColors.textSec,
                  ),
                ),
              ),
            ),
            Expanded(
              child: TextField(
                controller: _textController,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                onChanged: (_) => setState(() {}),
                maxLines: 4,
                minLines: 1,
                decoration: const InputDecoration(
                  hintText: 'Mesaj yaz...',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: KoalaColors.textTer,
                    fontWeight: FontWeight.w400,
                  ),
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                ),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: KoalaColors.text,
                ),
              ),
            ),
            GestureDetector(
              onTap: canSend && !_sending ? _sendMessage : null,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: canSend && !_sending
                        ? const LinearGradient(
                            colors: [
                              KoalaColors.accent,
                              KoalaColors.accentDark,
                            ],
                          )
                        : null,
                    color: canSend && !_sending
                        ? null
                        : Colors.black.withValues(alpha: 0.04),
                  ),
                  child: _sending
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          LucideIcons.arrowUp,
                          size: 18,
                          color: canSend
                              ? Colors.white
                              : KoalaColors.textSec,
                        ),
                ),
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
    final subParts = <String>[
      if (specialty.isNotEmpty) specialty,
      if (city.isNotEmpty) city,
    ];
    final subLine = subParts.join(' \u00b7 ');

    return Container(
      color: KoalaColors.surface,
      child: Column(
        children: [
          // Tek satır kompakt header — back + 36px avatar + name/sub + aktif pulse
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 16, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: KoalaColors.text, size: 22),
                ),
                // Avatar
                Container(
                  width: 36,
                  height: 36,
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
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(initials,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.designerName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: KoalaColors.text,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subLine.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFF4CAF50),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  subLine,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: KoalaColors.textTer,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
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
    // Supabase UTC döner; HH:MM lokale göre gösterilmeli.
    final timeStr = createdAt != null ? formatHM(createdAt) : '';

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
