import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../core/theme/koala_tokens.dart';
import '../core/utils/format_utils.dart';
import '../services/chat_persistence.dart';
import '../services/evlumba_live_service.dart';
import '../services/global_message_listener.dart';
import '../services/messaging_service.dart';
import '../widgets/error_state.dart';
import '../services/koala_ai_service.dart';
import '../widgets/shimmer_loading.dart';
import 'chat_detail_screen.dart';

/// [v1 — archived] Mesajlar ekranı — ilk jenerasyon (mor AI hero + yığılı
/// bölümler). `chat_list_screen.dart` içindeki `kUseChatListV2 = false`
/// yapılarak geri aktive edilebilir. Üretim için v2 kullanılıyor.
class ChatListScreenV1 extends StatefulWidget {
  const ChatListScreenV1({super.key});
  @override
  State<ChatListScreenV1> createState() => _ChatListScreenV1State();
}

class _ChatListScreenV1State extends State<ChatListScreenV1> {
  List<Map<String, dynamic>> _conversations = [];
  List<ChatSummary> _aiChats = [];
  bool _loading = true;
  bool _hasError = false;
  bool _showAllAi = false;

  // Arama — query boş değilse listeler filtrelenir, bölücüler gizlenir.
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Designer profil cache: id → { 'name': ..., 'avatar': ... }
  final Map<String, Map<String, String?>> _designerCache = {};

  // Realtime listener referansı — dispose'da aynı referansla kapatılır.
  void Function(Map<String, dynamic>)? _convListener;
  Timer? _inboundPollTimer;
  RealtimeChannel? _evlumbaChannel;

  @override
  void initState() {
    super.initState();
    _load();
    // Realtime + inbound sync'i post-frame'e ertele ki ilk render bloklanmasın.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _subscribeConversations();
      } catch (e) {
        debugPrint('ChatListScreen: subscribe error $e');
      }
      _syncInboundThenReload();
      _subscribeEvlumbaLive();
      // Kullanıcı mesajlar sayfasındayken agresif polling — 1.5 sn'de bir.
      // Evlumba realtime zaten var ama RLS nedeniyle event düşebiliyor; polling
      // güvenli fallback. Designer mesajları böylece max ~1.5s lag ile iner.
      _inboundPollTimer = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => _syncInboundThenReload(),
      );
    });
    // GlobalMessageListener her pullInbound sonrası tick — liste sessiz reload.
    GlobalMessageListener.syncTick.addListener(_onGlobalSyncTick);
  }

  void _onGlobalSyncTick() {
    if (!mounted) return;
    _load(silent: true);
  }

  /// Evlumba DB'sine direkt realtime abone ol — messages INSERT event'i
  /// geldiği an inbound sync çağır. 1.5s polling'i beklemeden anlık getirir.
  Future<void> _subscribeEvlumbaLive() async {
    try {
      if (!EvlumbaLiveService.isReady) {
        final ok = await EvlumbaLiveService.waitForReady(
          timeout: const Duration(seconds: 6),
        );
        if (!ok) return;
      }
      if (_evlumbaChannel != null) return;
      final client = EvlumbaLiveService.client;
      final ch = client.channel('koala_chatlist_inbound_messages');
      ch.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (_) => _syncInboundThenReload(),
      ).subscribe();
      _evlumbaChannel = ch;
      debugPrint('ChatListScreen: Evlumba realtime subscribed');
    } catch (e) {
      debugPrint('ChatListScreen: Evlumba subscribe failed: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _inboundPollTimer?.cancel();
    GlobalMessageListener.syncTick.removeListener(_onGlobalSyncTick);
    try {
      MessagingService.unsubscribeFromConversations(listener: _convListener);
    } catch (_) {}
    try {
      if (_evlumbaChannel != null && EvlumbaLiveService.isReady) {
        EvlumbaLiveService.client.removeChannel(_evlumbaChannel!);
      }
      _evlumbaChannel = null;
    } catch (_) {}
    super.dispose();
  }

  /// [silent] true ise shimmer/spinner gösterme — background refresh için.
  /// WhatsApp gibi: gelen mesaj var diye ekran "yükleniyor"a flash atmaz,
  /// sadece sessizce liste merge olur.
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _hasError = false;
      });
    }
    try {
      final convFuture = MessagingService.getConversations();
      final aiFuture = ChatPersistence.loadConversations();
      final results = await Future.wait([convFuture, aiFuture]);
      if (!mounted) return;
      final rawConvs = List<Map<String, dynamic>>.from(results[0] as List);
      // unread_count_user alanı backend bazen eksik/stale kalabiliyor.
      // Doğrudan mesajları sayıp conv map'e enjekte et — sort+badge true value.
      await _injectComputedUnread(rawConvs);
      final convs = _sortConversations(rawConvs);
      final ais = results[1] as List<ChatSummary>;
      setState(() {
        _conversations = convs;
        _aiChats = ais;
        _loading = false;
      });
      _loadDesignerAvatars();

      // Auth restore henüz tamamlanmamış olabilir → conversations boş gelmiş
      // olabilir ama DB'de gerçekte var. 1.5s sonra sessizce bir kez daha dene.
      if (convs.isEmpty && ais.isNotEmpty) {
        Future<void>.delayed(const Duration(milliseconds: 1500), () async {
          if (!mounted) return;
          try {
            final retry = await MessagingService.getConversations();
            if (mounted && retry.isNotEmpty) {
              final retryList = List<Map<String, dynamic>>.from(retry);
              await _injectComputedUnread(retryList);
              setState(() => _conversations = _sortConversations(retryList));
              _loadDesignerAvatars();
            }
          } catch (_) {}
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _loading = false;
          _hasError = true;
        });
      }
    }
  }

  /// No-op: unread artik getConversations sonucundaki unread_count_user /
  /// unread_count_designer kolonlarindan geliyor. (read_at kolonu yok.)
  Future<void> _injectComputedUnread(List<Map<String, dynamic>> _) async {}

  /// Sıralama: sadece `last_message_at DESC` (WhatsApp mantığı).
  ///
  /// Neden unread-first DEĞİL: Unread-first sort yapılırsa kullanıcı bir
  /// mesaj okuduğunda unread=0 olup conv aşağıya "düşüyor" (yerini değiştiriyor).
  /// Time-based sort'ta:
  ///   - Yeni mesaj gelir → last_message_at güncellenir → otomatik en üste.
  ///   - Kullanıcı okur → last_message_at değişmez → conv yerinde kalır.
  /// Unread badge'i zaten her tile'da gösteriliyor — sıralamayla karıştırmaya
  /// gerek yok.
  List<Map<String, dynamic>> _sortConversations(
    List<Map<String, dynamic>> list,
  ) {
    list.sort((a, b) {
      final at = DateTime.tryParse(a['last_message_at']?.toString() ?? '')
              ?.millisecondsSinceEpoch ??
          0;
      final bt = DateTime.tryParse(b['last_message_at']?.toString() ?? '')
              ?.millisecondsSinceEpoch ??
          0;
      return bt.compareTo(at);
    });
    return list;
  }

  /// ChatListScreen açılınca koala_conversations tablosundaki
  /// last_message / unread_count değişikliklerini canlı dinle.
  /// Designer mesajı geldiğinde (inbound endpoint'ten sonra realtime) listeyi
  /// ANINDA merge edip resort et — DB roundtrip yok, kullanıcı anında görür.
  void _subscribeConversations() {
    _convListener = (record) {
      if (!mounted) return;
      final uid = MessagingService.currentUserId;
      final userId = record['user_id'];
      final designerId = record['designer_id'];
      if (userId != uid && designerId != uid) return;

      final convId = record['id']?.toString();
      if (convId == null) return;

      // Archive edilmişse listeden kaldır
      if ((record['status'] ?? 'active') != 'active') {
        setState(() {
          _conversations.removeWhere((c) => c['id']?.toString() == convId);
        });
        return;
      }

      // Toast gösterimi için lokal kod YOK — GlobalMessageListener uygulama
      // seviyesinde zaten toast gösteriyor (her ekranda çalışsın diye).
      setState(() {
        final idx = _conversations.indexWhere((c) => c['id']?.toString() == convId);
        if (idx >= 0) {
          _conversations[idx] = {..._conversations[idx], ...record};
        } else {
          _conversations.insert(0, Map<String, dynamic>.from(record));
        }
        _conversations = _sortConversations(_conversations);
      });

      // Designer avatar'ı henüz cache'lenmemişse getir (yeni conv için)
      _loadDesignerAvatars();
    };
    MessagingService.subscribeToConversations(onUpdate: _convListener!);
  }

  /// Inbound sync'i arka planda çalıştır. Başarı durumunda DB tetikleyeceği
  /// realtime UPDATE listesi otomatik merge edecek; fakat realtime event'leri
  /// bazen düşebiliyor — güvenli taraf olarak yeni senkron varsa SESSİZCE
  /// (shimmer göstermeden) merge reload yap. WhatsApp gibi: ekran flashlamaz.
  Future<void> _syncInboundThenReload() async {
    final synced = await MessagingService.pullInbound();
    if (synced > 0 && mounted) {
      await _load(silent: true);
    }
  }

  /// Kullanıcı refresh butonuna / pull-to-refresh'e bastığında görünür
  /// feedback ver — senkronun başarılı mı, kaç mesaj geldi, hata mı gibi.
  // Hidden debug: "Mesajlar" başlığına 5 kere ard arda tıklayınca diag dialog
  // açılır. Release build'de de çalışır — user problem bildirimi için.
  int _titleTapCount = 0;
  DateTime? _firstTapAt;

  void _maybeOpenDebug() {
    final now = DateTime.now();
    if (_firstTapAt == null ||
        now.difference(_firstTapAt!) > const Duration(seconds: 3)) {
      _firstTapAt = now;
      _titleTapCount = 1;
      return;
    }
    _titleTapCount++;
    if (_titleTapCount >= 5) {
      _titleTapCount = 0;
      _firstTapAt = null;
      _showInboundDiag();
    }
  }

  Future<void> _showInboundDiag() async {
    // Tazelenmiş diag için bir sync tetikle
    await MessagingService.pullInbound();
    if (!mounted) return;
    final diag = MessagingService.lastInboundDiag;
    final convCount = MessagingService.lastInboundConversations;
    final firebaseUid = diag?['firebaseUid']?.toString() ?? '-';
    final email = diag?['email']?.toString() ?? '-';
    final homeownerId = diag?['homeownerId']?.toString() ?? '-';
    final shadowIds =
        (diag?['shadowIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final realEvlumbaIds =
        (diag?['realEvlumbaIds'] as List?)?.map((e) => e.toString()).toList() ??
        [];
    final reason = diag?['reason']?.toString();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mesaj Senkron Debug'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('firebaseUid: $firebaseUid', style: const TextStyle(fontSize: 11)),
              const SizedBox(height: 4),
              Text('email: $email', style: const TextStyle(fontSize: 11)),
              const SizedBox(height: 4),
              Text('canonical shadow: $homeownerId',
                  style: const TextStyle(fontSize: 11)),
              const SizedBox(height: 8),
              Text('shadowIds (${shadowIds.length}):',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              for (final id in shadowIds)
                Text('• $id', style: const TextStyle(fontSize: 11)),
              const SizedBox(height: 8),
              Text('realEvlumbaIds (${realEvlumbaIds.length}):',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              for (final id in realEvlumbaIds)
                Text('• $id', style: const TextStyle(fontSize: 11)),
              const SizedBox(height: 8),
              Text('Evlumba conversations: $convCount',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (reason != null) ...[
                const SizedBox(height: 4),
                Text('reason: $reason',
                    style: const TextStyle(fontSize: 11, color: Color(0xFFB00020))),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  Future<void> _manualSync() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final synced = await MessagingService.pullInbound();
      await _load();
      if (!mounted) return;
      // Yeni mesaj yoksa sessiz ol — SnackBar açma, liste yenilenmesi
      // zaten yeterli feedback. Sadece gerçekten YENİ mesaj geldiyse bildir.
      if (synced > 0) {
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            backgroundColor: const Color(0xFF4CAF50),
            content: Text(
              synced == 1 ? '1 yeni mesaj' : '$synced yeni mesaj',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFB00020),
          content: Text('Senkron hatası: $e',
              style: const TextStyle(color: Colors.white)),
        ),
      );
    }
  }

  /// Tüm tasarımcıların profil bilgilerini tek sorguda yükle (N+1 → 1)
  Future<void> _loadDesignerAvatars() async {
    if (_conversations.isEmpty) return;
    try {
      if (!EvlumbaLiveService.isReady) {
        await EvlumbaLiveService.waitForReady(timeout: const Duration(seconds: 5));
      }
      if (!EvlumbaLiveService.isReady) return;

      // Eksik profilleri topla
      final missingIds = <String>[];
      for (final conv in _conversations) {
        final designerId = (conv['designer_id'] ?? '').toString();
        if (designerId.isNotEmpty && !_designerCache.containsKey(designerId)) {
          missingIds.add(designerId);
        }
      }
      if (missingIds.isEmpty) return;

      // Tek sorguda tüm profilleri getir
      final profiles = await EvlumbaLiveService.getDesignersByIds(missingIds);
      for (final p in profiles) {
        final id = p['id'].toString();
        final name = (p['full_name'] ?? p['business_name'] ?? '').toString().trim();
        final avatar = (p['avatar_url'] ?? '').toString().trim();
        _designerCache[id] = {
          'name': name.isEmpty ? null : name,
          'avatar': avatar.isEmpty ? null : avatar,
        };
      }
      // Bulunamayan ID'ler için null set et
      for (final id in missingIds) {
        _designerCache.putIfAbsent(id, () => {'name': null, 'avatar': null});
      }
      if (mounted) setState(() {});
    } catch (_) {}
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
        title: GestureDetector(
          // Title'a 5x tıklama → debug dialog (gizli — user'ı rahatsız etmez)
          onTap: _maybeOpenDebug,
          child: const Text('Mesajlar', style: KoalaText.h2),
        ),
        // Refresh butonu kaldırıldı — WhatsApp gibi anlık olmalı. Pull-to-refresh
        // gizli yedek olarak duruyor (RefreshIndicator body'de).
        // "Yeni" butonu kaldırıldı — yeni AI sorusu anasayfadan başlatılıyor.
      ),
      body: _loading
          ? const ShimmerList(itemCount: 6, cardHeight: 72)
          : _hasError
              ? ErrorState(onRetry: _load)
              : (_conversations.isEmpty &&
                      _aiChats.isEmpty &&
                      _searchQuery.isEmpty)
                  ? _buildEmpty()
                  : RefreshIndicator(
                      onRefresh: _manualSync,
                      color: KoalaColors.accent,
                      child: _buildListBody(),
                    ),
    );
  }

  /// Ana liste gövdesi. Arama boşsa: Koala panel → bölücü → Evlumba →
  /// bölücü → tasarımcılar. Arama doluysa: filtrelenmiş sonuçlar.
  Widget _buildListBody() {
    final q = _searchQuery.trim().toLowerCase();
    final filteredConvs = q.isEmpty
        ? _conversations
        : _conversations.where((c) {
            final designerId = (c['designer_id'] ?? '').toString();
            final name = (_designerCache[designerId]?['name'] ?? '').toString().toLowerCase();
            final last = (c['last_message'] as String? ?? '').toLowerCase();
            final title = (c['title'] as String? ?? '').toLowerCase();
            return name.contains(q) || last.contains(q) || title.contains(q);
          }).toList();

    final filteredAi = q.isEmpty
        ? _aiChats
        : _aiChats.where((a) {
            final t = a.title.toLowerCase();
            final m = (a.lastMessage ?? '').toLowerCase();
            return t.contains(q) || m.contains(q);
          }).toList();

    if (q.isNotEmpty) {
      // Search mode — filtered flat results (search bar always at top)
      if (filteredConvs.isEmpty && filteredAi.isEmpty) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(
            KoalaSpacing.lg,
            KoalaSpacing.sm,
            KoalaSpacing.lg,
            KoalaSpacing.xxxl,
          ),
          children: [
            _buildSearchBar(),
            const SizedBox(height: KoalaSpacing.xxl),
            Center(
              child: Column(
                children: [
                  Icon(Icons.search_off_rounded,
                      size: 48, color: KoalaColors.textTer),
                  const SizedBox(height: KoalaSpacing.md),
                  Text('"$_searchQuery" için sonuç yok',
                      style: KoalaText.bodySec),
                ],
              ),
            ),
          ],
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          KoalaSpacing.lg,
          KoalaSpacing.sm,
          KoalaSpacing.lg,
          KoalaSpacing.xxxl,
        ),
        children: [
          _buildSearchBar(),
          if (filteredConvs.isNotEmpty) ...[
            _buildSectionDivider('Tasarımcılar'),
            ...filteredConvs.map(_buildConversationTile),
          ],
          if (filteredAi.isNotEmpty) ...[
            _buildSectionDivider('AI Sohbet Geçmişi'),
            ...filteredAi.map(_buildAiChatResultTile),
          ],
        ],
      );
    }

    // Normal mode — compact "hızlı erişim" services + sohbetler
    // (Koala AI panelinin büyük CTA'sı → bottom FAB'a taşındı)
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        KoalaSpacing.lg,
        KoalaSpacing.sm,
        KoalaSpacing.lg,
        KoalaSpacing.xxxl,
      ),
      children: [
        _buildSearchBar(),
        _buildServicesGrid(),
        if (_aiChats.isNotEmpty) ...[
          const SizedBox(height: KoalaSpacing.sm),
          _buildAiHistoryChip(),
        ],
        if (_conversations.isNotEmpty) ...[
          _buildSectionDivider('Tasarımcılar'),
          ..._conversations.map(_buildConversationTile),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // ARAMA KUTUSU — home input ile aynı görünüm (focus border yok),
  // ListView'in ilk elemanı olarak içeri taşındı → scroll ile beraber gider.
  // ═══════════════════════════════════════════════════════
  Widget _buildSearchBar() {
    OutlineInputBorder flatBorder() => OutlineInputBorder(
          borderRadius: BorderRadius.circular(KoalaRadius.md),
          borderSide: const BorderSide(
            color: KoalaColors.border,
            width: 0.5,
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: KoalaSpacing.md),
      child: TextField(
        controller: _searchController,
        style: KoalaText.body.copyWith(fontSize: 14),
        cursorColor: KoalaColors.accent,
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          filled: true,
          fillColor: KoalaColors.surface,
          hintText: 'Ara — tasarımcı, sohbet, mesaj...',
          hintStyle: KoalaText.hint.copyWith(fontSize: 13.5),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 18,
            color: KoalaColors.textTer,
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 38, minHeight: 38),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  child: const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: KoalaColors.textTer,
                  ),
                ),
          suffixIconConstraints:
              const BoxConstraints(minWidth: 38, minHeight: 38),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          // Tüm state'lerde aynı ince gri border → focus'ta mor çerçeve YOK
          border: flatBorder(),
          enabledBorder: flatBorder(),
          focusedBorder: flatBorder(),
          disabledBorder: flatBorder(),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // MODERN BÖLÜCÜ — ince çizgi + ortada küçük etiket
  // ═══════════════════════════════════════════════════════
  Widget _buildSectionDivider(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: KoalaSpacing.xl, horizontal: KoalaSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Container(height: 0.5, color: KoalaColors.borderSolid),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.md),
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: KoalaColors.textTer,
                letterSpacing: 1.4,
              ),
            ),
          ),
          Expanded(
            child: Container(height: 0.5, color: KoalaColors.borderSolid),
          ),
        ],
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
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.lg),
      child: Column(
        children: [
          const SizedBox(height: KoalaSpacing.xl),

          // ─── Koala AI Hero Card ───
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChatDetailScreen()),
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: KoalaColors.accentGradient,
                borderRadius: BorderRadius.circular(KoalaRadius.xl),
                boxShadow: KoalaShadows.accentGlow,
              ),
              child: Column(
                children: [
                  // Koala avatar
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/koalas.png',
                        width: 48, height: 48,
                        errorBuilder: (_, _, _) => const Icon(Icons.auto_awesome_rounded, size: 32, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Koala AI Asistan',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Odanı fotoğrafla, stil analizi yap, ürün bul\nveya uzman tasarımcı önerisi al',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.85), height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  // CTA buton
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(KoalaRadius.pill),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_rounded, size: 16, color: KoalaColors.accentDeep),
                        SizedBox(width: 8),
                        Text(
                          'Sohbet Başlat',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: KoalaColors.accentDeep),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ─── Hızlı eylem butonları ───
          Row(
            children: [
              Expanded(
                child: _emptyActionCard(
                  icon: Icons.camera_alt_rounded,
                  label: 'Odamı Analiz Et',
                  color: KoalaColors.accent,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ChatDetailScreen(
                        intent: KoalaIntent.photoAnalysis,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _emptyActionCard(
                  icon: Icons.person_search_rounded,
                  label: 'Tasarımcı Bul',
                  color: KoalaColors.greenAlt,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatDetailScreen(
                        initialText: 'Tasarımcı öner',
                        intent: KoalaIntent.designerMatch,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ─── Evlumba Design Premium ───
          _buildEvlumbaDesignSection(),

          const SizedBox(height: KoalaSpacing.xxxl),
        ],
      ),
    );
  }

  Widget _emptyActionCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: KoalaColors.surface,
          borderRadius: BorderRadius.circular(KoalaRadius.lg),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: KoalaColors.text),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // [legacy] KOALA AI PANEL — full-width büyük CTA'lı panel.
  // Compact 2-up services grid'e taşındı (_buildServicesGrid). Rollback için
  // korunuyor, şuan çağrılmıyor.
  // ═══════════════════════════════════════════════════════
  // ignore: unused_element
  Widget _buildKoalaAiPanel() {
    final hasHistory = _aiChats.isNotEmpty;
    final latest = hasHistory ? _aiChats.first : null;
    final previewText = latest?.lastMessage?.trim().isNotEmpty == true
        ? latest!.lastMessage!
        : 'Odanı fotoğrafla · stil bul · ürün öner';

    return Container(
      margin: const EdgeInsets.only(top: KoalaSpacing.sm),
      padding: const EdgeInsets.all(KoalaSpacing.lg),
      decoration: BoxDecoration(
        color: KoalaColors.accentLight, // very light purple wash
        borderRadius: BorderRadius.circular(KoalaRadius.lg),
        border: Border.all(
          color: KoalaColors.accent.withValues(alpha: 0.18),
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          // ── Üst satır: avatar, isim, preview, timestamp ──
          InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatDetailScreen(chatId: latest?.id),
              ),
            ),
            borderRadius: BorderRadius.circular(KoalaRadius.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  // Sparkle avatar — mor gradient daire, beyaz ikon, hafif glow
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: KoalaColors.accentGradient,
                      boxShadow: [
                        BoxShadow(
                          color: KoalaColors.accent.withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        LucideIcons.sparkles,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: KoalaSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('Koala AI', style: KoalaText.h4),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: KoalaColors.accent,
                                borderRadius:
                                    BorderRadius.circular(KoalaRadius.pill),
                              ),
                              child: const Text(
                                'asistan',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          previewText,
                          style: KoalaText.bodySec,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (latest != null)
                    Text(timeAgo(latest.updatedAt),
                        style: KoalaText.labelSmall),
                ],
              ),
            ),
          ),
          const SizedBox(height: KoalaSpacing.md),
          // Divider — panelin içinde ince çizgi
          Container(
            height: 0.6,
            color: KoalaColors.accent.withValues(alpha: 0.15),
          ),
          const SizedBox(height: KoalaSpacing.md),
          // ── Alt aksiyon şeridi: 2 buton ──
          Row(
            children: [
              Expanded(
                child: _koalaActionButton(
                  icon: LucideIcons.sparkles,
                  label: 'Yeni soru sor',
                  primary: true,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ChatDetailScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: KoalaSpacing.sm),
              Expanded(
                child: _koalaActionButton(
                  icon: Icons.history_rounded,
                  label: hasHistory ? 'Geçmiş · ${_aiChats.length}' : 'Geçmiş',
                  primary: false,
                  onTap: hasHistory ? _openAiHistorySheet : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Koala panel içindeki aksiyon butonu — primary mor, secondary beyaz.
  /// Legacy — compact services grid'e geçildi, bu buton kullanılmıyor.
  // ignore: unused_element
  Widget _koalaActionButton({
    required IconData icon,
    required String label,
    required bool primary,
    required VoidCallback? onTap,
  }) {
    final disabled = onTap == null;
    final bg = primary
        ? KoalaColors.accent
        : KoalaColors.surface;
    final fg = primary
        ? Colors.white
        : (disabled ? KoalaColors.textTer : KoalaColors.accent);
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: disabled ? 0.6 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(KoalaRadius.md),
            border: primary
                ? null
                : Border.all(
                    color: KoalaColors.accent.withValues(alpha: 0.2),
                    width: 0.8,
                  ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: fg,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // HIZLI ERİŞİM — Koala AI + Evlumba Design compact 50/50 kart
  // (eski full-width panel + Evlumba row'un yerini alıyor)
  // ═══════════════════════════════════════════════════════
  Widget _buildServicesGrid() {
    final latestAi = _aiChats.isNotEmpty ? _aiChats.first : null;
    final aiCount = _aiChats.length;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _buildServiceCard(
              // Card tap:
              //   - Geçmiş varsa → son AI sohbetini aç
              //   - Yoksa → history sheet (empty state guidance gösterir)
              // Yeni sohbet oluşturma burada YAPILMIYOR — user anasayfadan yapıyor.
              onTap: latestAi != null
                  ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ChatDetailScreen(chatId: latestAi.id),
                        ),
                      )
                  : _openAiHistorySheet,
              gradient: KoalaColors.accentGradient,
              icon: LucideIcons.sparkles,
              title: 'Koala AI',
              pill: 'asistan',
              pillBg: KoalaColors.accent,
              subtitle: latestAi != null
                  ? 'Son · ${timeAgo(latestAi.updatedAt)}'
                  : 'Odanı fotoğrafla · stil bul',
              trailing: aiCount > 0 ? '$aiCount sohbet' : null,
              highlightBg: KoalaColors.accentLight,
              borderColor: KoalaColors.accent.withValues(alpha: 0.18),
            ),
          ),
          const SizedBox(width: KoalaSpacing.sm),
          Expanded(
            child: _buildServiceCard(
              onTap: _openEvlumbaDesign,
              gradient: const LinearGradient(
                colors: [Color(0xFFD4A853), Color(0xFFB8874A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              icon: LucideIcons.home,
              title: 'Evlumba Design',
              pill: 'uzman',
              pillBg: const Color(0xFFB8874A),
              subtitle: 'İç mimardan destek',
              trailing: '≤ 1 sa yanıt',
              trailingDot: true, // küçük yeşil pulse — "müsait"
              highlightBg: const Color(0xFFFDF8EC),
              borderColor: const Color(0xFFD4A853).withValues(alpha: 0.25),
            ),
          ),
        ],
      ),
    );
  }

  /// Tek bir hızlı erişim kartı. Koala AI ve Evlumba Design bu widget'ı
  /// paylaşıyor → tutarlı hiyerarşi, compact layout.
  Widget _buildServiceCard({
    required VoidCallback onTap,
    required Gradient gradient,
    required IconData icon,
    required String title,
    required String pill,
    required Color pillBg,
    required String subtitle,
    String? trailing,
    bool trailingDot = false,
    required Color highlightBg,
    required Color borderColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(KoalaSpacing.md),
        decoration: BoxDecoration(
          color: highlightBg,
          borderRadius: BorderRadius.circular(KoalaRadius.lg),
          border: Border.all(color: borderColor, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Üst: avatar + pill
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: gradient,
                  ),
                  child: Center(
                    child: Icon(icon, size: 18, color: Colors.white),
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: pillBg,
                    borderRadius: BorderRadius.circular(KoalaRadius.pill),
                  ),
                  child: Text(
                    pill,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(title,
                style: KoalaText.h4.copyWith(fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: KoalaText.bodySec.copyWith(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (trailing != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (trailingDot) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF22C55E),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: Text(
                      trailing,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: KoalaColors.textSec,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.arrow_forward_rounded,
                      size: 12, color: KoalaColors.textTer),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// AI sohbet geçmişi — ince tek-satır şerit, Koala AI kartının altında.
  /// Kullanıcı "36 sohbeti" görüp tıklayabilir.
  Widget _buildAiHistoryChip() {
    return GestureDetector(
      onTap: _openAiHistorySheet,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: KoalaSpacing.md, vertical: 10),
        decoration: BoxDecoration(
          color: KoalaColors.surface,
          borderRadius: BorderRadius.circular(KoalaRadius.md),
          border: Border.all(color: KoalaColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: KoalaColors.accentSoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(LucideIcons.sparkles,
                  size: 12, color: KoalaColors.accent),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Koala AI sohbet geçmişi',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: KoalaColors.text,
                  letterSpacing: 0.1,
                ),
              ),
            ),
            Text(
              '${_aiChats.length}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: KoalaColors.accent,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: KoalaColors.textTer),
          ],
        ),
      ),
    );
  }

  /// [legacy] Bottom-right FAB: "Yeni AI sorusu" — kaldırıldı (kullanıcı
  /// kafa karıştırıcı buldu, Koala AI kartı zaten tap → yeni/son sohbet).
  /// Rollback için korunuyor.
  // ignore: unused_element
  Widget _buildAiFab() {
    return FloatingActionButton.extended(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ChatDetailScreen()),
      ),
      backgroundColor: KoalaColors.accent,
      foregroundColor: Colors.white,
      elevation: 4,
      highlightElevation: 6,
      icon: const Icon(LucideIcons.sparkles, size: 18),
      label: const Text(
        'Yeni soru',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  /// Arama modunda AI chat match satırı — küçük, ikinci sınıf
  Widget _buildAiChatResultTile(ChatSummary chat) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatDetailScreen(chatId: chat.id)),
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
              child: const Icon(LucideIcons.sparkles,
                  size: 14, color: KoalaColors.accent),
            ),
            const SizedBox(width: KoalaSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(chat.title,
                      style: KoalaText.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (chat.lastMessage != null && chat.lastMessage!.isNotEmpty)
                    Text(chat.lastMessage!,
                        style: KoalaText.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Text(timeAgo(chat.updatedAt), style: KoalaText.labelSmall),
          ],
        ),
      ),
    );
  }

  /// Sohbet arşivle (soft delete) — status='archived'. Realtime event
  /// zaten listeden kaldıracak ama optimistic için burada da çıkıyoruz.
  /// Soft-delete koala_conversations row. Caller (Dismissible.onDismissed)
  /// handles the list removal → burada setState YOK, aksi halde Dismissible
  /// animasyonu child'ı kaybedip assertion fırlatır.
  Future<bool> _archiveConversation(String convId) async {
    try {
      await Supabase.instance.client
          .from('koala_conversations')
          .update({'status': 'archived'}).eq('id', convId);
      return true;
    } catch (e) {
      debugPrint('archive failed: $e');
      return false;
    }
  }

  void _removeConversationLocal(String convId) {
    if (!mounted) return;
    setState(() {
      _conversations.removeWhere((c) => c['id']?.toString() == convId);
    });
  }

  /// Silme onay bottom sheet — modern action sheet
  Future<bool> _confirmDelete({required String title}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(
            KoalaSpacing.xl,
            KoalaSpacing.lg,
            KoalaSpacing.xl,
            MediaQuery.of(ctx).padding.bottom + KoalaSpacing.lg),
        decoration: const BoxDecoration(
          color: KoalaColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: KoalaColors.borderSolid,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: KoalaSpacing.lg),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: KoalaColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline_rounded,
                  color: KoalaColors.error, size: 28),
            ),
            const SizedBox(height: KoalaSpacing.md),
            const Text('Sohbeti sil', style: KoalaText.h3),
            const SizedBox(height: 6),
            Text(
              '"$title" sohbeti listeden kalkacak.',
              textAlign: TextAlign.center,
              style: KoalaText.bodySec,
            ),
            const SizedBox(height: KoalaSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx, false),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(vertical: KoalaSpacing.md),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: KoalaColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(KoalaRadius.md),
                      ),
                      child: Text(
                        'İptal',
                        style: KoalaText.label.copyWith(
                            color: KoalaColors.text,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: KoalaSpacing.md),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx, true),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(vertical: KoalaSpacing.md),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: KoalaColors.error,
                        borderRadius: BorderRadius.circular(KoalaRadius.md),
                      ),
                      child: const Text(
                        'Sil',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  // ═══════════════════════════════════════════════════════
  // [legacy] _buildKoalaAiRow — artık _buildKoalaAiPanel kullanılıyor.
  // Eski tek-satır versiyonu, referans/rollback için kalıyor.
  // ═══════════════════════════════════════════════════════
  // ignore: unused_element
  Widget _buildKoalaAiRow() {
    final hasHistory = _aiChats.isNotEmpty;
    final latest = hasHistory ? _aiChats.first : null;
    final previewText = latest?.lastMessage?.trim().isNotEmpty == true
        ? latest!.lastMessage!
        : 'Odanı fotoğrafla · stil bul · ürün öner';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(chatId: latest?.id),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(top: KoalaSpacing.sm),
        padding: const EdgeInsets.all(KoalaSpacing.lg),
        decoration: KoalaDeco.card,
        child: Row(
          children: [
            // Avatar — mor gradient daire, koala asset içinde
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: KoalaColors.accentGradient,
              ),
              child: ClipOval(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Image.asset(
                    'assets/images/koalas.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: KoalaSpacing.md),
            // Name + preview
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Text('Koala AI', style: KoalaText.h4),
                      SizedBox(width: 6),
                      Icon(Icons.auto_awesome_rounded,
                          size: 13, color: KoalaColors.accent),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    previewText,
                    style: KoalaText.bodySec,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Time (en son AI chat timestamp) — diğer satırlarla aynı format
            if (latest != null)
              Text(timeAgo(latest.updatedAt), style: KoalaText.labelSmall),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // [legacy] _buildAiSection — artık kullanılmıyor, build() içinde
  // _buildKoalaAiRow() tek satır olarak çağrılıyor. Referans/rollback için
  // korunuyor.
  // ═══════════════════════════════════════════════════════
  // ignore: unused_element
  Widget _buildAiSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: KoalaSpacing.sm, bottom: KoalaSpacing.sm),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 14, color: KoalaColors.textTer),
              SizedBox(width: 6),
              Text('AI Asistan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: KoalaColors.textTer, letterSpacing: 0.5)),
            ],
          ),
        ),
        // Yeni AI sohbet başlat — hero card
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
              boxShadow: KoalaShadows.accentGlow,
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

  // ═══════════════════════════════════════════════════════
  // [legacy] EVLUMBA DESIGN — eski tek-satır full-width card. Artık
  // _buildServicesGrid içinde Koala AI yanında compact kart olarak duruyor.
  // Empty state geriye dönük olarak bunu kullanabiliyor.
  // ═══════════════════════════════════════════════════════
  // ignore: unused_element
  Widget _buildEvlumbaDesignRow() {
    const gold = Color(0xFFD4A853);
    return GestureDetector(
      onTap: _openEvlumbaDesign,
      child: Container(
        margin: const EdgeInsets.only(top: KoalaSpacing.sm),
        padding: const EdgeInsets.all(KoalaSpacing.lg),
        decoration: KoalaDeco.card,
        child: Row(
          children: [
            // Avatar — altın gradient, diamond ikonu
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [gold, Color(0xFFE8C76A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(Icons.diamond_rounded,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: KoalaSpacing.md),
            // Name + description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Text('Evlumba Design', style: KoalaText.h4),
                      SizedBox(width: 6),
                      Icon(Icons.verified_rounded, size: 13, color: gold),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Uzman iç mimarlardan 1 saat içinde yanıt',
                    style: KoalaText.bodySec,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // "1 saat" badge — küçük, conversation time ile aynı yerde
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFDF8EC),
                borderRadius: BorderRadius.circular(KoalaRadius.pill),
                border: Border.all(color: gold.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule_rounded, size: 10, color: gold),
                  SizedBox(width: 3),
                  Text('1 sa',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: gold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // AI SOHBET GEÇMİŞİ — altta ince link satırı (bottom sheet açar)
  // Artık _buildKoalaAiPanel içindeki "Geçmiş" butonu kullanılıyor,
  // bu fn rollback referansı için duruyor.
  // ═══════════════════════════════════════════════════════
  // ignore: unused_element
  Widget _buildAiHistoryLink() {
    final count = _aiChats.length;
    return GestureDetector(
      onTap: _openAiHistorySheet,
      child: Container(
        margin: const EdgeInsets.only(top: KoalaSpacing.md),
        padding: const EdgeInsets.symmetric(
            horizontal: KoalaSpacing.lg, vertical: KoalaSpacing.md),
        child: Row(
          children: [
            const Icon(Icons.history_rounded,
                size: 16, color: KoalaColors.textTer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'AI sohbet geçmişi',
                style: KoalaText.bodySec.copyWith(
                  color: KoalaColors.textSec,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text('$count',
                style: KoalaText.labelSmall.copyWith(
                    fontWeight: FontWeight.w600, color: KoalaColors.textSec)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: KoalaColors.textTer),
          ],
        ),
      ),
    );
  }

  void _openAiHistorySheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AiHistorySheet(
        initialChats: _aiChats,
        onSelect: (id) {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ChatDetailScreen(chatId: id)),
          );
        },
        onDelete: _deleteAiChat,
      ),
    );
  }

  /// AI sohbet sil → hem SharedPreferences hem Supabase'den kaldır.
  /// Parent listeyi senkron tutmak için setState ile _aiChats'ten de çıkarıyoruz.
  Future<bool> _deleteAiChat(String chatId) async {
    try {
      await ChatPersistence.deleteConversation(chatId);
      if (mounted) {
        setState(() {
          _aiChats.removeWhere((c) => c.id == chatId);
        });
      }
      return true;
    } catch (e) {
      debugPrint('AI chat delete failed: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // [legacy] _buildEvlumbaDesignSection — artık kullanılmıyor, build()
  // içinde _buildEvlumbaDesignRow() çağrılıyor. Empty state için korunuyor.
  // ═══════════════════════════════════════════════════════
  Widget _buildEvlumbaDesignSection() {
    return Padding(
      padding: const EdgeInsets.only(top: KoalaSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_rounded, size: 14, color: Color(0xFFD4A853)),
              SizedBox(width: 6),
              Text('Evlumba Design', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFD4A853), letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: KoalaSpacing.sm),
          GestureDetector(
            onTap: _openEvlumbaDesign,
            child: Container(
              padding: const EdgeInsets.all(KoalaSpacing.lg),
              decoration: BoxDecoration(
                color: KoalaColors.surface,
                borderRadius: BorderRadius.circular(KoalaRadius.lg),
                border: Border.all(color: const Color(0xFFD4A853).withValues(alpha: 0.3), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFD4A853).withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Premium icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFD4A853), Color(0xFFE8C76A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(KoalaRadius.sm),
                    ),
                    child: const Icon(Icons.diamond_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: KoalaSpacing.md),
                  // Text
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Profesyonel Destek',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: KoalaColors.text,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Uzman iç mimarlardan 1 saat içinde yanıt',
                          style: TextStyle(fontSize: 12, color: KoalaColors.textSec),
                        ),
                      ],
                    ),
                  ),
                  // Badge + arrow
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDF8EC),
                          borderRadius: BorderRadius.circular(KoalaRadius.pill),
                          border: Border.all(color: const Color(0xFFD4A853).withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.schedule_rounded, size: 11, color: Color(0xFFD4A853)),
                            SizedBox(width: 3),
                            Text('1 saat', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFD4A853))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFFD4A853)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openEvlumbaDesign() {
    // TODO: Sonraki iterasyonda WhatsApp entegrasyonu ile birlikte
    // Şimdilik bilgi popup'ı göster
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _EvlumbaDesignSheet(),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 3. TASARIMCI KONUŞMA TILE
  // ═══════════════════════════════════════════════════════
  Widget _buildConversationTile(Map<String, dynamic> conv) {
    final lastMessage = conv['last_message'] as String? ?? '';
    final projectTitle = (conv['title'] as String? ?? '').trim();
    final lastAt = DateTime.tryParse(conv['last_message_at']?.toString() ?? '');

    // Unread count (current user perspective)
    final uid = MessagingService.currentUserId;
    final isUser = conv['user_id'] == uid;
    final unread = isUser
        ? (conv['unread_count_user'] as int?) ?? 0
        : (conv['unread_count_designer'] as int?) ?? 0;

    final designerId = (conv['designer_id'] ?? '').toString();
    final cached = _designerCache[designerId];
    final designerName = (cached?['name'] ?? '').toString().trim().isEmpty
        ? 'Tasarımcı'
        : cached!['name']!;
    final avatarUrl = cached?['avatar'];

    final initials = designerName
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();

    final convIdForKey = (conv['id'] ?? '').toString();

    return Dismissible(
      key: ValueKey('conv-$convIdForKey'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        if (convIdForKey.isEmpty) return false;
        final ok = await _confirmDelete(title: designerName);
        if (!ok) return false;
        // Server archive (soft-delete). setState'i onDismissed içinde
        // yapıyoruz — confirmDismiss true dönerse Dismissible child'ı
        // önce animate-out edecek, sonra onDismissed tetiklenecek.
        return await _archiveConversation(convIdForKey);
      },
      onDismissed: (_) {
        if (convIdForKey.isNotEmpty) {
          _removeConversationLocal(convIdForKey);
        }
      },
      background: Container(
        margin: const EdgeInsets.only(top: KoalaSpacing.sm),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.xl),
        decoration: BoxDecoration(
          color: KoalaColors.error,
          borderRadius: BorderRadius.circular(KoalaRadius.lg),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.delete_outline_rounded, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text(
              'Sil',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
      child: GestureDetector(
      onTap: () async {
        // Optimistic: tıklanır tıklanmaz rozet sıfıra insin — DB update
        // geç kalırsa bile kullanıcı 0 görsün.
        final convId = conv['id']?.toString();
        if (convId != null) {
          setState(() {
            final idx = _conversations.indexWhere((c) => c['id']?.toString() == convId);
            if (idx >= 0) {
              _conversations[idx] = {
                ..._conversations[idx],
                'unread_count_user': 0,
                'unread_count_designer': 0,
              };
            }
          });
          // Server'a yaz. Başarısız olursa (RLS vs.) optimistic değeri
          // realtime güncellemesi eventually geri çevirebilir — bunu
          // kullanıcıya göstermek için hata durumunda SnackBar.
          MessagingService.markAsRead(convId).then((ok) {
            if (!mounted || ok) return;
            final messenger = ScaffoldMessenger.maybeOf(context);
            final err = MessagingService.lastMarkAsReadError ?? 'bilinmeyen hata';
            messenger?.showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 5),
                backgroundColor: const Color(0xFFB00020),
                content: Text(
                  'Okundu işaretleme başarısız: $err',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            );
          });
        }
        await context.push('/chat/dm/${conv['id']}', extra: {
          'designerId': designerId,
          'designerName': designerName,
          'designerAvatarUrl': avatarUrl,
          'projectTitle': projectTitle.isNotEmpty ? projectTitle : null,
          // markAsRead() yukarıda zaten tetiklendi — DB'de unread=0 olacak.
          // Detail screen'de "Yeni mesajlar" divider'ı gösterebilmek için
          // okunmamış sayısını navigation extra'sıyla gönderiyoruz. Aksi
          // halde getConversation() race nedeniyle 0 görüp divider'ı
          // göstermiyordu.
          'unreadOnEntry': unread,
        });
        // Refresh unread counts — sessiz, shimmer yok.
        _load(silent: true);
      },
      child: Container(
        margin: const EdgeInsets.only(top: KoalaSpacing.sm),
        padding: const EdgeInsets.all(KoalaSpacing.lg),
        decoration: KoalaDeco.card,
        child: Row(
          children: [
            // Avatar — profil fotosu varsa göster
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [KoalaColors.accent, KoalaColors.accentMuted],
                ),
              ),
              child: avatarUrl != null && avatarUrl.isNotEmpty
                  ? ClipOval(
                      child: Image.network(
                        avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Center(
                          child: Text(initials, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(initials, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
            ),
            const SizedBox(width: KoalaSpacing.md),

            // Name + project context pill + last message
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(designerName, style: KoalaText.h4),
                  if (projectTitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: KoalaColors.accentSoft,
                        borderRadius: BorderRadius.circular(KoalaRadius.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.folder_rounded, size: 11, color: KoalaColors.accent),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              projectTitle,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: KoalaColors.accent,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (lastMessage.isNotEmpty) ...[
                    const SizedBox(height: 4),
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
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// EVLUMBA DESIGN — Bilgi & Başlat Sheet
// ═══════════════════════════════════════════════════════
class _EvlumbaDesignSheet extends StatelessWidget {
  const _EvlumbaDesignSheet();

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 16, 24, bottomPad + 24),
      decoration: const BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: KoalaColors.borderSolid, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 24),

          // Icon
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFD4A853), Color(0xFFE8C76A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(KoalaRadius.lg),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD4A853).withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.diamond_rounded, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 20),

          // Title
          const Text(
            'Evlumba Design',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: KoalaColors.text, letterSpacing: -0.3),
          ),
          const SizedBox(height: 8),
          const Text(
            'Uzman iç mimarlarımız projenize özel çözümler sunar',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: KoalaColors.textSec, height: 1.4),
          ),
          const SizedBox(height: 28),

          // Feature list
          _buildFeatureRow(Icons.schedule_rounded, '1 Saat İçinde Yanıt', 'Uzmanlarımız hızlıca döner'),
          const SizedBox(height: 16),
          _buildFeatureRow(Icons.verified_rounded, 'Sertifikalı Uzmanlar', 'Deneyimli iç mimarlar'),
          const SizedBox(height: 16),
          _buildFeatureRow(Icons.design_services_rounded, 'Kişiye Özel Çözüm', 'Projenize göre tasarlanmış öneriler'),
          const SizedBox(height: 28),

          // CTA Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                // TODO: WhatsApp entegrasyonu gelecek
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Evlumba Design yakında aktif olacak!'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4A853),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KoalaRadius.md)),
              ),
              child: const Text('Sohbet Başlat', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 12),

          // Subtle note
          const Text(
            'İlk danışma ücretsizdir',
            style: TextStyle(fontSize: 12, color: KoalaColors.textTer),
          ),
        ],
      ),
    );
  }

  static Widget _buildFeatureRow(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFFDF8EC),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: const Color(0xFFD4A853)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: KoalaColors.text)),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: KoalaColors.textSec)),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
// AI SOHBET GEÇMİŞİ — bottom sheet
// Stateful: sheet açıkken swipe-to-delete yapıldığında listeyi
// optimistik olarak günceller, parent'tan silme callback'ini çağırır.
// ═══════════════════════════════════════════════════════
class _AiHistorySheet extends StatefulWidget {
  final List<ChatSummary> initialChats;
  final void Function(String chatId) onSelect;
  final Future<bool> Function(String chatId) onDelete;

  const _AiHistorySheet({
    required this.initialChats,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  State<_AiHistorySheet> createState() => _AiHistorySheetState();
}

class _AiHistorySheetState extends State<_AiHistorySheet> {
  late List<ChatSummary> _chats;

  @override
  void initState() {
    super.initState();
    _chats = List.of(widget.initialChats);
  }

  Future<bool> _confirmDelete(String title) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(
            KoalaSpacing.xl,
            KoalaSpacing.lg,
            KoalaSpacing.xl,
            MediaQuery.of(ctx).padding.bottom + KoalaSpacing.lg),
        decoration: const BoxDecoration(
          color: KoalaColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: KoalaColors.borderSolid,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: KoalaSpacing.lg),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: KoalaColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline_rounded,
                  color: KoalaColors.error, size: 28),
            ),
            const SizedBox(height: KoalaSpacing.md),
            const Text('AI sohbetini sil', style: KoalaText.h3),
            const SizedBox(height: 6),
            Text(
              '"$title" sohbeti kalıcı olarak silinecek.',
              textAlign: TextAlign.center,
              style: KoalaText.bodySec,
            ),
            const SizedBox(height: KoalaSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx, false),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(vertical: KoalaSpacing.md),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: KoalaColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(KoalaRadius.md),
                      ),
                      child: Text(
                        'İptal',
                        style: KoalaText.label.copyWith(
                            color: KoalaColors.text,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: KoalaSpacing.md),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx, true),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(vertical: KoalaSpacing.md),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: KoalaColors.error,
                        borderRadius: BorderRadius.circular(KoalaRadius.md),
                      ),
                      child: const Text(
                        'Sil',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: KoalaColors.borderSolid,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(
                KoalaSpacing.lg, KoalaSpacing.md, KoalaSpacing.lg, KoalaSpacing.sm),
            child: Row(
              children: [
                const Icon(Icons.history_rounded,
                    size: 18, color: KoalaColors.accent),
                const SizedBox(width: 8),
                const Text('AI Sohbet Geçmişi', style: KoalaText.h3),
                const Spacer(),
                Text('${_chats.length}',
                    style: KoalaText.bodySec
                        .copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          // Küçük yardım metni — silme ipucu
          Padding(
            padding: const EdgeInsets.fromLTRB(
                KoalaSpacing.lg, 0, KoalaSpacing.lg, KoalaSpacing.sm),
            child: Row(
              children: const [
                Icon(Icons.swipe_left_rounded,
                    size: 13, color: KoalaColors.textTer),
                SizedBox(width: 6),
                Text(
                  'Silmek için sola kaydır',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: KoalaColors.textTer,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: KoalaColors.border),
          // List
          Flexible(
            child: _chats.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: KoalaSpacing.xxl),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.chat_bubble_outline_rounded,
                              size: 40, color: KoalaColors.textTer),
                          const SizedBox(height: KoalaSpacing.sm),
                          Text('Henüz sohbet yok',
                              style: KoalaText.bodySec),
                          const SizedBox(height: 4),
                          Text(
                            'Ana sayfadan Koala AI\'ya soru sorabilirsin',
                            style: KoalaText.labelSmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.fromLTRB(KoalaSpacing.sm,
                        KoalaSpacing.sm, KoalaSpacing.sm, bottomPad + 16),
                    itemCount: _chats.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 2),
                    itemBuilder: (_, i) {
                      final chat = _chats[i];
                      return Dismissible(
                        key: ValueKey('ai-${chat.id}'),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) async {
                          final ok = await _confirmDelete(chat.title);
                          if (!ok) return false;
                          final success = await widget.onDelete(chat.id);
                          return success;
                        },
                        onDismissed: (_) {
                          setState(() {
                            _chats.removeWhere((c) => c.id == chat.id);
                          });
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(
                              horizontal: KoalaSpacing.xl),
                          decoration: BoxDecoration(
                            color: KoalaColors.error,
                            borderRadius:
                                BorderRadius.circular(KoalaRadius.md),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.delete_outline_rounded,
                                  color: Colors.white, size: 20),
                              SizedBox(width: 6),
                              Text(
                                'Sil',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => widget.onSelect(chat.id),
                            borderRadius:
                                BorderRadius.circular(KoalaRadius.md),
                            child: Padding(
                              padding:
                                  const EdgeInsets.all(KoalaSpacing.md),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: KoalaColors.accentSoft,
                                      borderRadius: BorderRadius.circular(
                                          KoalaRadius.sm),
                                    ),
                                    child: const Icon(
                                        LucideIcons.sparkles,
                                        size: 14,
                                        color: KoalaColors.accent),
                                  ),
                                  const SizedBox(width: KoalaSpacing.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          chat.title,
                                          style: KoalaText.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (chat.lastMessage != null &&
                                            chat.lastMessage!.isNotEmpty)
                                          Text(
                                            chat.lastMessage!,
                                            style: KoalaText.bodySmall,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                  Text(timeAgo(chat.updatedAt),
                                      style: KoalaText.labelSmall),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
