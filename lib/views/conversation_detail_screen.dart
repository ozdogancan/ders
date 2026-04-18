import 'dart:async';

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
import '../services/messaging_service.dart';
import '../services/saved_items_service.dart';
import '../services/share_service.dart';
import '../widgets/koala_widgets.dart';

/// Tasarımcı ile mesaj detay ekranı — gerçek zamanlı
class ConversationDetailScreen extends StatefulWidget {
  const ConversationDetailScreen({
    super.key,
    this.conversationId,
    this.designerId,
    this.designerName = 'Tasarımcı',
    this.designerAvatarUrl,
    this.projectTitle,
    this.unreadOnEntry,
    this.initialDraft,
    this.pendingDesign,
  }) : assert(conversationId != null || designerId != null,
            'conversationId veya designerId verilmeli (lazy chat için)');

  /// Var olan sohbet ID'si — null ise ilk mesajda lazy yaratılır (designerId
  /// gerekir). Bu "Mesaj At" popup yerine tam ekran detay açıldığında kullanılır.
  final String? conversationId;
  final String? designerId;
  final String designerName;
  final String? designerAvatarUrl;
  final String? projectTitle;

  /// Lazy chat girişinde input'a ön-doldurulacak taslak metin (örn:
  /// "Merhaba, [proje adı] hakkında bilgi almak istiyorum").
  final String? initialDraft;

  /// ShareSheet'ten design paylaşımı için ön-dolmuş tasarım. Map keys:
  /// `id`, `title`, `imageUrl`, `designerId`. Input üstünde preview çıkar;
  /// send'e basınca image mesajı olarak gönderilir + `ShareService.logShareInChat`
  /// çağrılır (koala_shares + analytics).
  final Map<String, dynamic>? pendingDesign;

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
  // Proje viewer'dan "tasarım hakkında sor" ile gelen hazır görsel URL.
  // _pendingPhoto'dan farkı: bytes yok, upload yapılmaz — direkt attachment_url
  // olarak gönderilir (görsel zaten Evlumba CDN'inde).
  String? _pendingDesignUrl;
  // ShareSheet "design" flow'dan gelen tasarım meta bilgisi — send sonrası
  // koala_shares tablosuna "chat" kanalı olarak log'lanır.
  String? _pendingDesignId;
  String? _pendingDesignTitle;
  // Swipe kartından gelen isteğe bağlı bilgi: proje açıklaması ilk cümle +
  // oda kategorisi. Chat input üstündeki preview'da info olarak gösterilir.
  String? _pendingDesignTagline;
  String? _pendingDesignCategory;

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

  /// Aktif conversation ID. widget.conversationId null geldiğinde (lazy mode)
  /// ilk mesajda _ensureConversation() ile doldurulur. Null iken mesaj
  /// listesi/realtime/markRead çağrıları atlanır — henüz sohbet yok.
  String? _activeConvId;

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
    _activeConvId = widget.conversationId;
    _scrollController.addListener(_onScroll);
    _loadDesignerDetail();

    if (_activeConvId != null) {
      // _loadMessages() kendi sonunda markAsRead çağırıyor — önce unread sayısını
      // oku, divider'ı hesapla, sonra read flag'ini indir.
      _loadMessages();
      _subscribeRealtime();
      _subscribeConversationUpdates();
      // Global toast bu conv'un detay ekranındayken suppress edilsin.
      GlobalMessageListener.suppressConvId = _activeConvId;
    } else {
      // Lazy mode: conv henüz yok. Boş state göster, draft prefill et.
      _loading = false;
      final draft = widget.initialDraft;
      if (draft != null && draft.isNotEmpty) {
        _textController.text = draft;
      }
    }

    // ShareSheet → pendingDesign: input üstünde preview, send'e basınca image
    // mesajı olarak gönder + koala_shares log.
    final pd = widget.pendingDesign;
    if (pd != null) {
      final url = (pd['imageUrl'] ?? '').toString();
      final id = (pd['id'] ?? '').toString();
      if (url.isNotEmpty && id.isNotEmpty) {
        _pendingDesignUrl = url;
        _pendingDesignId = id;
        _pendingDesignTitle = (pd['title'] ?? '').toString();
        final tagline = (pd['tagline'] ?? '').toString().trim();
        _pendingDesignTagline = tagline.isEmpty ? null : tagline;
        final cat = (pd['category'] ?? '').toString().trim();
        _pendingDesignCategory = cat.isEmpty ? null : cat;
      }
    }
  }

  @override
  void dispose() {
    if (_activeConvId != null &&
        GlobalMessageListener.suppressConvId == _activeConvId) {
      GlobalMessageListener.suppressConvId = null;
    }
    if (_activeConvId != null) {
      MessagingService.unsubscribeFromMessages(_activeConvId!);
    }
    // ÖNEMLİ: _convListener null iken unsubscribe çağrılırsa tüm global listener'ları
    // siler (HomeScreen vs. patlar). Sadece abone olmuşsak kaldır.
    if (_convListener != null) {
      try {
        MessagingService.unsubscribeFromConversations(listener: _convListener);
      } catch (_) {}
    }
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// İlk mesaj gönderiminde lazy çağrılır: var olan conv'u bulur ya da
  /// yaratır, realtime subscribe/markRead'i bağlar. Başarılıysa conv map'i
  /// döner; null ise UI hata göstermeli.
  Future<Map<String, dynamic>?> _ensureConversation() async {
    if (_activeConvId != null) {
      // Zaten bağlı — getConversation ile taze kayıt dön (sendMessage'ın
      // sonraki adımında lazım olmuyor aslında; compat için map lazım değil).
      return {'id': _activeConvId};
    }
    final did = widget.designerId;
    if (did == null || did.isEmpty) return null;
    final conv = await MessagingService.getOrCreateConversation(
      designerId: did,
      contextTitle: widget.projectTitle,
    );
    if (conv == null) return null;
    final id = conv['id']?.toString();
    if (id == null || id.isEmpty) return null;
    if (!mounted) return conv;
    setState(() {
      _activeConvId = id;
    });
    // İlk attach: realtime + toast suppress bağla. Mesaj listesi zaten
    // boş — _sendMessage fonksiyonu ilk mesajı insert edecek ve realtime
    // listener onu listeye ekleyecek.
    _subscribeRealtime();
    _subscribeConversationUpdates();
    GlobalMessageListener.suppressConvId = id;
    return conv;
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
              await MessagingService.getConversation(_activeConvId!);
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
      conversationId: _activeConvId!,
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
    if (ctx == null || !ctx.mounted) return;
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
    final oldest = _messages.last;
    final pivotId = oldest['id']?.toString();
    // id yoksa pagination anchor'ı belirsiz; tüm mesajları tekrar çekmeyelim.
    if (pivotId == null || pivotId.isEmpty) return;
    setState(() => _loadingMore = true);
    final older = await MessagingService.getMessages(
      conversationId: _activeConvId!,
      beforeId: pivotId,
    );
    if (mounted) {
      setState(() {
        _messages.addAll(older);
        _loadingMore = false;
      });
    }
  }

  void _subscribeRealtime() {
    final cid = _activeConvId;
    if (cid == null) return;
    MessagingService.subscribeToMessages(
      conversationId: cid,
      onMessage: (msg) {
        if (mounted) {
          setState(() => _messages.insert(0, msg));
          if (msg['sender_id'] != _uid) {
            MessagingService.markAsRead(cid);
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
      if (convId != _activeConvId) return;
      final uid = MessagingService.currentUserId;
      final isUser = record['user_id'] == uid;
      final unreadNow = isUser
          ? ((record['unread_count_user'] as int?) ?? 0)
          : ((record['unread_count_designer'] as int?) ?? 0);
      if (unreadNow > 0 && _activeConvId != null) {
        MessagingService.markAsRead(_activeConvId!);
      }
    };
    MessagingService.subscribeToConversations(onUpdate: _convListener!);
  }

  Future<void> _markRead() async {
    final cid = _activeConvId;
    if (cid == null) return;
    await MessagingService.markAsRead(cid);
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
    final designUrl = _pendingDesignUrl;
    if (text.isEmpty && photo == null && designUrl == null) return;

    // ÖNEMLİ: text/foto'yu HENÜZ silme. Başarısızsa restore et ki kullanıcı
    // kayıp hissi yaşamasın. Sadece _sending true → input lock.
    setState(() => _sending = true);

    // Lazy mode: conv henüz yoksa ilk gönderimde yarat. Başarısızsa erken çık.
    if (_activeConvId == null) {
      final conv = await _ensureConversation();
      if (conv == null || _activeConvId == null) {
        if (!mounted) return;
        setState(() => _sending = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: const Text('Sohbet başlatılamadı — tekrar deneyin'),
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 6),
            ),
          );
        return;
      }
    }
    final cid = _activeConvId!;

    String? errorMsg;
    Map<String, dynamic>? sentMsg;
    try {
      if (designUrl != null && photo == null) {
        // Proje viewer'dan gelen hazır görsel: upload yok, direkt attach.
        sentMsg = await MessagingService.sendMessage(
          conversationId: cid,
          content: text, // caption (boş olabilir)
          type: MessageType.image,
          attachmentUrl: designUrl,
        );
        if (sentMsg == null) {
          errorMsg = 'Mesaj kaydedilemedi: '
              '${MessagingService.lastSendError ?? "bilinmeyen hata"}';
        }
      } else if (photo != null) {
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

          sentMsg = await MessagingService.sendMessage(
            conversationId: cid,
            content: text, // caption (boş olabilir)
            type: MessageType.image,
            attachmentUrl: imageUrl,
          );
          if (sentMsg == null) {
            errorMsg = 'Mesaj kaydedilemedi: '
                '${MessagingService.lastSendError ?? "bilinmeyen hata"}';
          }
        } catch (e) {
          debugPrint('[DM upload] error: $e');
          errorMsg = 'Görsel yüklenemedi: ${e.toString().split('\n').first}';
        }
      } else {
        // Sadece text
        sentMsg = await MessagingService.sendMessage(
          conversationId: cid,
          content: text,
        );
        if (sentMsg == null) {
          errorMsg = 'Mesaj gönderilemedi: '
              '${MessagingService.lastSendError ?? "bilinmeyen hata"}';
        }
      }

      // Chat list sıralamasını tetikle (Realtime bazen Firebase auth'lu
      // client'a düşmüyor).
      try {
        GlobalMessageListener.syncTick.value++;
      } catch (_) {}
    } finally {
      // NOT: `return` yerine `if (mounted) { ... }` — finally içindeki return
      // try bloğunda yakalanmamış exception'ı sessizce yutar (control_flow_in_finally).
      if (mounted) {
        if (sentMsg != null) {
        // BAŞARI: input'u temizle.
        _textController.clear();

        // Design paylaşımı ise koala_shares + analytics log (fire-and-forget).
        final designId = _pendingDesignId;
        if (designId != null && designId.isNotEmpty) {
          unawaited(ShareService.logShareInChat(
            type: SavedItemType.design,
            itemId: designId,
            conversationId: cid,
            designerId: widget.designerId,
          ));
        }

        setState(() {
          _sending = false;
          _pendingPhoto = null;
          _pendingDesignUrl = null;
          _pendingDesignId = null;
          _pendingDesignTitle = null;
          _pendingDesignTagline = null;
          _pendingDesignCategory = null;
        });
      } else {
        // BAŞARISIZ: text/foto kullanıcının elinde kalsın, sticky hata göster.
        setState(() => _sending = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(errorMsg ?? 'Bilinmeyen hata'),
              duration: const Duration(seconds: 10),
              backgroundColor: Colors.red.shade700,
              action: SnackBarAction(
                label: 'Tamam',
                textColor: Colors.white,
                onPressed: () => ScaffoldMessenger.of(context)
                    .hideCurrentSnackBar(),
              ),
            ),
          );
      }
      }
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

  /// Proje map'inden kategori/oda tipi etiketi üretir — "Bilgehan Ermiş
  /// Projesi" gibi tekrar eden title yerine "Oturma Odası" vb göstermek için.
  String _projectCategoryLabel(Map<String, dynamic> p) {
    for (final k in ['project_type', 'room_type', 'category']) {
      final v = (p[k] ?? '').toString().trim();
      if (v.isNotEmpty) return _prettyTrCategory(v);
    }
    final t = (p['title'] ?? '').toString().trim();
    final dn = widget.designerName.trim();
    if (t.isNotEmpty && dn.isNotEmpty && !t.toLowerCase().contains(dn.toLowerCase())) {
      return t;
    }
    return '';
  }

  String _prettyTrCategory(String raw) {
    const trMap = {
      'living_room': 'Oturma Odası',
      'bedroom': 'Yatak Odası',
      'kitchen': 'Mutfak',
      'bathroom': 'Banyo',
      'dining_room': 'Yemek Odası',
      'office': 'Çalışma Odası',
      'kids_room': 'Çocuk Odası',
      'hallway': 'Koridor / Hol',
      'balcony': 'Balkon',
      'outdoor': 'Dış Mekan',
    };
    final key = raw.toLowerCase().trim();
    if (trMap.containsKey(key)) return trMap[key]!;
    final cleaned = raw.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    if (cleaned.isEmpty) return raw;
    return cleaned
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
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
        onAskDesigner: (imageUrl) {
          Navigator.of(context).pop(); // viewer kapat
          if (!mounted) return;
          // Text boş kalır → kullanıcı ne soracağını kendisi yazsın.
          // Preview olarak tasarımın görseli input'un üstüne eklenir.
          _textController.clear();
          setState(() {
            _pendingPhoto = null;
            _pendingDesignUrl = imageUrl;
          });
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

            // Photo preview — picker'dan seçilen foto VEYA proje viewer'dan
            // attach edilen hazır görsel, send'e basana kadar burada durur.
            if (_pendingPhoto != null || _pendingDesignUrl != null)
              _buildPhotoPreview(),

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
          borderRadius: BorderRadius.circular(14),
          color: _pendingDesignId != null
              ? KoalaColors.accentSoft
              : Colors.white,
          border: _pendingDesignId != null
              ? Border.all(color: KoalaColors.accentDeep.withValues(alpha: 0.2))
              : null,
          boxShadow: _pendingDesignId != null
              ? null
              : [
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
                  child: _pendingPhoto != null
                      ? Image.memory(
                          _pendingPhoto!,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                        )
                      : Image.network(
                          _pendingDesignUrl!,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 64,
                            height: 64,
                            color: KoalaColors.surfaceAlt,
                            child: const Icon(Icons.image_rounded,
                                size: 24, color: KoalaColors.textTer),
                          ),
                        ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _pendingPhoto = null;
                      _pendingDesignUrl = null;
                      _pendingDesignId = null;
                      _pendingDesignTitle = null;
                    }),
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
              child: _pendingDesignTitle != null && _pendingDesignTitle!.isNotEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Tasarım ekleniyor',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: KoalaColors.accentDeep,
                                letterSpacing: 0.3,
                              ),
                            ),
                            if (_pendingDesignCategory != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: KoalaColors.accentDeep
                                        .withValues(alpha: 0.18),
                                  ),
                                ),
                                child: Text(
                                  _pendingDesignCategory!,
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: KoalaColors.accentDeep,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _pendingDesignTitle!,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: KoalaColors.ink,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _pendingDesignTagline ??
                              'İstersen bir not ekle, sonra gönder',
                          style: const TextStyle(
                            fontSize: 11,
                            color: KoalaColors.textSec,
                            height: 1.35,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    )
                  : const Text(
                      'Foto eklendi · isteğe bağlı bir not yazıp gönder',
                      style: TextStyle(
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
    final canSend = hasText || _pendingPhoto != null || _pendingDesignUrl != null;
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
                              // Kategori / oda tipi etiketi.
                              // "Bilgehan Ermiş Projesi" gibi tasarımcı adı
                              // tekrarı değil — "Oturma Odası" vb göstersin.
                              Builder(builder: (_) {
                                final label = _projectCategoryLabel(project);
                                if (label.isEmpty) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    label,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: KoalaColors.textSec,
                                      height: 1.25,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }),
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
    required this.onAskDesigner,
  });
  final Map<String, dynamic> project;
  final List<Map<String, dynamic>> allProjects;
  final int startIndex;
  final String designerName;
  final String designerId;
  final void Function(String imageUrl) onAskDesigner;

  @override
  State<_ProjectViewerSheet> createState() => _ProjectViewerSheetState();
}

class _ProjectViewerSheetState extends State<_ProjectViewerSheet> {
  late PageController _pageCtrl;
  late int _currentIndex;

  // Kaydedildi durumu — proje değişince yenilenir
  bool _saved = false;
  bool _savingBusy = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.startIndex;
    _pageCtrl = PageController(initialPage: widget.startIndex);
    _refreshSavedState();
  }

  @override
  void dispose() { _pageCtrl.dispose(); super.dispose(); }

  Map<String, dynamic> get _current => widget.allProjects[_currentIndex];

  String _currentId() {
    final v = (_current['id'] ?? _current['project_id'] ?? '').toString();
    return v;
  }

  Future<void> _refreshSavedState() async {
    final id = _currentId();
    if (id.isEmpty) { if (mounted) setState(() => _saved = false); return; }
    final s = await SavedItemsService.isSaved(type: SavedItemType.design, itemId: id);
    if (!mounted) return;
    setState(() => _saved = s);
  }

  Future<void> _toggleSave() async {
    if (_savingBusy) return;
    final id = _currentId();
    if (id.isEmpty) return;
    setState(() => _savingBusy = true);
    final title = (_current['title'] ?? 'Tasarım').toString();
    final imageUrl = _coverUrl(_current);
    bool ok;
    if (_saved) {
      ok = await SavedItemsService.removeItem(type: SavedItemType.design, itemId: id);
    } else {
      ok = await SavedItemsService.saveItem(
        type: SavedItemType.design,
        itemId: id,
        title: title,
        imageUrl: imageUrl.isNotEmpty ? imageUrl : null,
        subtitle: widget.designerName,
      );
    }
    if (!mounted) return;
    setState(() {
      _savingBusy = false;
      if (ok) _saved = !_saved;
    });
    if (ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          content: Text(_saved ? 'Tasarım kaydedildi' : 'Kayıt kaldırıldı'),
        ));
    }
  }

  String _coverUrl(Map<String, dynamic> p) {
    for (final k in ['cover_image_url', 'cover_url', 'image_url']) {
      final v = (p[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  void _askDesigner() {
    final imageUrl = _coverUrl(_current);
    if (imageUrl.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Bu tasarımın görseli bulunamadı.'),
        ));
      return;
    }
    widget.onAskDesigner(imageUrl);
  }

  @override
  Widget build(BuildContext context) {
    final title = (_current['title'] ?? 'Proje').toString();

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
              onPageChanged: (i) {
                setState(() => _currentIndex = i);
                _refreshSavedState();
              },
              itemBuilder: (_, i) {
                final url = _coverUrl(widget.allProjects[i]);
                if (url.isEmpty) return Container(color: KoalaColors.surfaceAlt, alignment: Alignment.center, child: const Icon(Icons.image_rounded, size: 48, color: KoalaColors.textTer));
                return Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: KoalaColors.surfaceAlt))));
              },
            ),
          ),
          // Alt aksiyonlar: tasarımcıya sor (primary) + kaydet (secondary)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _askDesigner,
                    icon: const Icon(LucideIcons.messageCircle, size: 18),
                    label: Text(
                      'Bu tasarım hakkında sor',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: KoalaColors.accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Kaydet — ikon butonu (filled/unfilled)
                SizedBox(
                  width: 52, height: 48,
                  child: Material(
                    color: _saved ? KoalaColors.accentSoft : KoalaColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: _savingBusy ? null : _toggleSave,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _saved ? KoalaColors.accent.withValues(alpha: 0.4) : KoalaColors.border),
                        ),
                        child: Center(
                          child: _savingBusy
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: KoalaColors.accent))
                              : Icon(
                                  _saved ? LucideIcons.bookmark : LucideIcons.bookmark,
                                  size: 20,
                                  color: _saved ? KoalaColors.accent : KoalaColors.textSec,
                                ),
                        ),
                      ),
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
            // Image message — tıklayınca fullscreen viewer açılır
            if (type == 'image' && message['attachment_url'] != null)
              _BubbleImage(
                url: message['attachment_url'] as String,
                heroTag: 'msg-img-${message['id'] ?? message['attachment_url']}',
                caption: content,
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
// MESSAGE IMAGE — bubble içinde küçük preview, tıklayınca fullscreen viewer
// ═══════════════════════════════════════════════════════
class _BubbleImage extends StatelessWidget {
  const _BubbleImage({
    required this.url,
    required this.heroTag,
    required this.caption,
  });

  final String url;
  final String heroTag;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
          PageRouteBuilder<void>(
            opaque: false,
            barrierColor: Colors.black,
            transitionDuration: const Duration(milliseconds: 220),
            reverseTransitionDuration: const Duration(milliseconds: 180),
            pageBuilder: (_, __, ___) => _PhotoViewerScreen(
              url: url,
              heroTag: heroTag,
              caption: caption,
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(KoalaRadius.sm),
        child: Hero(
          tag: heroTag,
          child: Image.network(
            url,
            width: 200,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(
              Icons.broken_image_rounded,
              color: KoalaColors.textTer,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// PHOTO VIEWER — fullscreen, pinch-zoom, swipe-down to dismiss
// ═══════════════════════════════════════════════════════
class _PhotoViewerScreen extends StatefulWidget {
  const _PhotoViewerScreen({
    required this.url,
    required this.heroTag,
    required this.caption,
  });

  final String url;
  final String heroTag;
  final String caption;

  @override
  State<_PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<_PhotoViewerScreen> {
  // Drag-to-dismiss durumu
  double _dragOffset = 0;
  double _dragOpacity = 1.0;

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() {
      _dragOffset += d.delta.dy;
      // Aşağı kaydırma → opacity azalt; sınırı belli tut
      _dragOpacity = (1 - (_dragOffset.abs() / 400)).clamp(0.0, 1.0);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    // Yeterince çekildi veya hızlı flick → kapat
    if (_dragOffset.abs() > 120 || d.velocity.pixelsPerSecond.dy.abs() > 700) {
      Navigator.of(context).pop();
    } else {
      // Geri yerine otur — animasyon
      setState(() {
        _dragOffset = 0;
        _dragOpacity = 1.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: _dragOpacity),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          // Foto — vertical drag dismiss + pinch zoom
          GestureDetector(
            onVerticalDragUpdate: _onDragUpdate,
            onVerticalDragEnd: _onDragEnd,
            child: Center(
              child: Transform.translate(
                offset: Offset(0, _dragOffset),
                child: Hero(
                  tag: widget.heroTag,
                  child: InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 4.0,
                    child: Image.network(
                      widget.url,
                      fit: BoxFit.contain,
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        );
                      },
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.broken_image_rounded,
                        color: Colors.white54,
                        size: 64,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Caption (varsa) — alt overlay, drag sırasında soluk
          if (widget.caption.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: _dragOpacity,
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    16 + MediaQuery.of(context).padding.bottom,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                  child: Text(
                    widget.caption,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ),
        ],
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
