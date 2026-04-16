import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../core/theme/koala_tokens.dart';
import '../core/utils/format_utils.dart';
import '../services/chat_persistence.dart';
import '../services/evlumba_live_service.dart';
import '../services/messaging_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../services/koala_ai_service.dart';
import '../widgets/shimmer_loading.dart';
import 'chat_detail_screen.dart';

/// Mesajlar ekranı — AI chat geçmişi + Evlumba Design + tasarımcı konuşmaları
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
    _inboundPollTimer?.cancel();
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
      final convs = _sortConversations(
        List<Map<String, dynamic>>.from(results[0] as List),
      );
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
              setState(() => _conversations = _sortConversations(
                List<Map<String, dynamic>>.from(retry),
              ));
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

  /// Sıralama: önce OKUNMAMIŞ mesajı olan conversation'lar (unread > 0),
  /// sonra last_message_at DESC. Kullanıcı okunmamış olanları en üstte görür,
  /// okundu olanlar altta tarih sırasına göre dizilir.
  List<Map<String, dynamic>> _sortConversations(
    List<Map<String, dynamic>> list,
  ) {
    final uid = MessagingService.currentUserId;
    int unreadOf(Map<String, dynamic> c) {
      final isUser = c['user_id'] == uid;
      return isUser
          ? ((c['unread_count_user'] as int?) ?? 0)
          : ((c['unread_count_designer'] as int?) ?? 0);
    }

    list.sort((a, b) {
      final au = unreadOf(a);
      final bu = unreadOf(b);
      final aHas = au > 0;
      final bHas = bu > 0;
      if (aHas != bHas) return bHas ? 1 : -1; // unread önce
      final at = DateTime.tryParse(a['last_message_at']?.toString() ?? '')
              ?.millisecondsSinceEpoch ??
          0;
      final bt = DateTime.tryParse(b['last_message_at']?.toString() ?? '')
              ?.millisecondsSinceEpoch ??
          0;
      return bt.compareTo(at); // yeni önce
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
      messenger?.hideCurrentSnackBar();
      final convCount = MessagingService.lastInboundConversations;
      final diag = MessagingService.lastInboundDiag;
      final shortId = (diag?['homeownerId']?.toString() ?? '').split('-').first;
      // Eğer hiç conversation yoksa kullanıcıya sebebini net söyle —
      // shadow user Evlumba'daki conversation'larla eşleşmiyor demektir.
      final message = synced > 0
          ? '$synced yeni mesaj geldi (conv=$convCount)'
          : convCount == 0
              ? 'Evlumba\'da konuşma bulunamadı. shadow=$shortId'
              : 'Yeni mesaj yok (conv=$convCount, shadow=$shortId)';
      messenger?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          backgroundColor: synced > 0
              ? const Color(0xFF4CAF50)
              : KoalaColors.textSec,
          content: Text(
            message,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
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
      ),
      body: _loading
          ? const ShimmerList(itemCount: 6, cardHeight: 72)
          : _hasError
              ? ErrorState(onRetry: _load)
              : (_conversations.isEmpty && _aiChats.isEmpty)
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _manualSync,
                  color: KoalaColors.accent,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.lg),
                    children: [
                      // ─── 1. Koala AI Asistan ───
                      _buildAiSection(),

                      // ─── 2. Evlumba Design (Premium) ───
                      _buildEvlumbaDesignSection(),

                      // ─── 3. Tasarımcı konuşmaları ───
                      if (_conversations.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.only(
                            top: KoalaSpacing.xl,
                            bottom: KoalaSpacing.sm,
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.forum_rounded, size: 14, color: KoalaColors.textTer),
                              SizedBox(width: 6),
                              Text('Tasarımcılar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: KoalaColors.textTer, letterSpacing: 0.5)),
                            ],
                          ),
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
  // 1. AI ASISTAN SECTION
  // ═══════════════════════════════════════════════════════
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
  // 2. EVLUMBA DESIGN (Premium)
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

    return GestureDetector(
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
                        errorBuilder: (_, __, ___) => Center(
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
