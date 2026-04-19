import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/utils/format_utils.dart';
import '../services/chat_persistence.dart';
import '../services/evlumba_live_service.dart';
import '../services/global_message_listener.dart';
import '../services/messaging_service.dart';
import '../widgets/error_state.dart';
import '../widgets/shimmer_loading.dart';
import 'chat_detail_screen.dart';

// ═══════════════════════════════════════════════════════════════════
// ChatListScreenV2 — "Editorial Warmth"
// ─────────────────────────────────────────────────────────────────
// Tasarım notu: v1 (mor gradient hero + yığılı sections) karmaşıktı.
// v2 iç-mimari dergisi havasında: Fraunces serif başlık, sıcak off-white
// dokuyu koruyor ama tek baskın accent (koyu mürekkep + ince altın çizgi),
// AI geçmişi dense sekonder liste, tasarımcılar ana kahraman.
// Rollback: `chat_list_screen.dart` içinde `kUseChatListV2 = false`.
// ═══════════════════════════════════════════════════════════════════

// ─── v2 design tokens (scoped — global tema'yı kirletmemek için) ───
abstract final class _V2 {
  // Warm neutral palette — restrained, editorial
  static const bg       = Color(0xFFF4EEE5); // slightly warmer cream than v1
  static const paper    = Color(0xFFFBF7F1); // card surface — aged paper
  static const line     = Color(0x14000000); // hairlines, 8% black
  static const lineSoft = Color(0x0A000000); // soft dividers
  static const ink      = Color(0xFF181613); // body/headline ink
  static const inkSoft  = Color(0xFF4A423A); // secondary text
  static const inkMute  = Color(0xFF8A8278); // tertiary, timestamps
  static const rust     = Color(0xFFB0502E); // single warm accent (unread bar)
  static const gold     = Color(0xFF8E6B2A); // premium thread
  static const goldSoft = Color(0xFFD4AE6B);

  // Serif display — google_fonts Fraunces (variable, editorial)
  static TextStyle serif({double size = 34, FontWeight weight = FontWeight.w400, Color? color, double spacing = -0.8}) =>
      GoogleFonts.fraunces(
        fontSize: size,
        fontWeight: weight,
        color: color ?? ink,
        letterSpacing: spacing,
        height: 1.05,
        // Opsz 144 → tighter, more display-like
        fontFeatures: const [FontFeature('ss01'), FontFeature('ss02')],
      );

  // Body — Manrope (clean humanist, pairs well with Fraunces)
  static TextStyle body({double size = 14, FontWeight weight = FontWeight.w400, Color? color, double spacing = 0, double? height}) =>
      GoogleFonts.manrope(
        fontSize: size,
        fontWeight: weight,
        color: color ?? ink,
        letterSpacing: spacing,
        height: height,
      );

  // Uppercase label
  static TextStyle eyebrow({Color? color}) => GoogleFonts.manrope(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: color ?? inkMute,
        letterSpacing: 1.6,
      );
}

class ChatListScreenV2 extends StatefulWidget {
  const ChatListScreenV2({super.key});
  @override
  State<ChatListScreenV2> createState() => _ChatListScreenV2State();
}

class _ChatListScreenV2State extends State<ChatListScreenV2> {
  // ─── state (v1 ile aynı) ───
  List<Map<String, dynamic>> _conversations = [];
  List<ChatSummary> _aiChats = [];
  bool _loading = true;
  bool _hasError = false;
  bool _showAllAi = false;

  final Map<String, Map<String, String?>> _designerCache = {};

  void Function(Map<String, dynamic>)? _convListener;

  // Hidden debug (5-tap on title)
  int _titleTapCount = 0;
  DateTime? _firstTapAt;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _subscribeConversations();
      } catch (e) {
        debugPrint('ChatListScreenV2: subscribe error $e');
      }
      // İlk açılışta tek sync — sonrası GlobalMessageListener yönetiyor.
      _syncInboundThenReload();
    });
    // Inbound polling ve Evlumba realtime artık GlobalMessageListener'da
    // merkezi. Sadece tick'e abone olup sessiz reload yapıyoruz.
    GlobalMessageListener.syncTick.addListener(_onGlobalSyncTick);
  }

  void _onGlobalSyncTick() {
    if (!mounted) return;
    _load(silent: true);
  }

  @override
  void dispose() {
    GlobalMessageListener.syncTick.removeListener(_onGlobalSyncTick);
    try {
      MessagingService.unsubscribeFromConversations(listener: _convListener);
    } catch (_) {}
    super.dispose();
  }

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
      final convs = _sortConversations(rawConvs);
      final ais = results[1] as List<ChatSummary>;
      setState(() {
        _conversations = convs;
        _aiChats = ais;
        _loading = false;
      });
      _loadDesignerAvatars();

      if (convs.isEmpty && ais.isNotEmpty) {
        Future<void>.delayed(const Duration(milliseconds: 1500), () async {
          if (!mounted) return;
          try {
            final retry = await MessagingService.getConversations();
            if (mounted && retry.isNotEmpty) {
              final retryList = List<Map<String, dynamic>>.from(retry);
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

  List<Map<String, dynamic>> _sortConversations(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      final at = DateTime.tryParse(a['last_message_at']?.toString() ?? '')
              ?.millisecondsSinceEpoch ?? 0;
      final bt = DateTime.tryParse(b['last_message_at']?.toString() ?? '')
              ?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });
    return list;
  }

  void _subscribeConversations() {
    _convListener = (record) {
      if (!mounted) return;
      final uid = MessagingService.currentUserId;
      final userId = record['user_id'];
      final designerId = record['designer_id'];
      if (userId != uid && designerId != uid) return;

      final convId = record['id']?.toString();
      if (convId == null) return;

      if ((record['status'] ?? 'active') != 'active') {
        setState(() {
          _conversations.removeWhere((c) => c['id']?.toString() == convId);
        });
        return;
      }

      setState(() {
        final idx = _conversations.indexWhere((c) => c['id']?.toString() == convId);
        if (idx >= 0) {
          _conversations[idx] = {..._conversations[idx], ...record};
        } else {
          _conversations.insert(0, Map<String, dynamic>.from(record));
        }
        _conversations = _sortConversations(_conversations);
      });
      _loadDesignerAvatars();
    };
    MessagingService.subscribeToConversations(onUpdate: _convListener!);
  }

  Future<void> _syncInboundThenReload() async {
    final synced = await MessagingService.pullInbound();
    if (synced > 0 && mounted) {
      await _load(silent: true);
    }
  }

  Future<void> _manualSync() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final synced = await MessagingService.pullInbound();
      await _load();
      if (!mounted) return;
      messenger?.hideCurrentSnackBar();
      if (synced > 0) {
        messenger?.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: _V2.ink,
            content: Text(
              '$synced yeni mesaj',
              style: _V2.body(color: Colors.white, weight: FontWeight.w600),
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
              style: _V2.body(color: Colors.white)),
        ),
      );
    }
  }

  Future<void> _loadDesignerAvatars() async {
    if (_conversations.isEmpty) return;
    try {
      if (!EvlumbaLiveService.isReady) {
        await EvlumbaLiveService.waitForReady(timeout: const Duration(seconds: 5));
      }
      if (!EvlumbaLiveService.isReady) return;

      final missingIds = <String>[];
      for (final conv in _conversations) {
        final designerId = (conv['designer_id'] ?? '').toString();
        if (designerId.isNotEmpty && !_designerCache.containsKey(designerId)) {
          missingIds.add(designerId);
        }
      }
      if (missingIds.isEmpty) return;

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
      for (final id in missingIds) {
        _designerCache.putIfAbsent(id, () => {'name': null, 'avatar': null});
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

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
    await MessagingService.pullInbound();
    if (!mounted) return;
    final diag = MessagingService.lastInboundDiag;
    final convCount = MessagingService.lastInboundConversations;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mesaj Senkron Debug'),
        content: Text(
          'conv=$convCount\n'
          'firebaseUid=${diag?['firebaseUid'] ?? '-'}\n'
          'homeownerId=${diag?['homeownerId'] ?? '-'}\n'
          'reason=${diag?['reason'] ?? '-'}',
          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Kapat')),
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

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _V2.bg,
      body: Stack(
        children: [
          // Subtle grain / warm overlay
          const Positioned.fill(child: _GrainBackground()),

          SafeArea(
            bottom: false,
            child: _loading
                ? const ShimmerList(itemCount: 6, cardHeight: 72)
                : _hasError
                    ? ErrorState(onRetry: _load)
                    : (_conversations.isEmpty && _aiChats.isEmpty)
                        ? _buildEmpty()
                        : RefreshIndicator(
                            onRefresh: _manualSync,
                            color: _V2.rust,
                            backgroundColor: _V2.paper,
                            child: CustomScrollView(
                              physics: const AlwaysScrollableScrollPhysics(
                                parent: BouncingScrollPhysics(),
                              ),
                              slivers: [
                                _buildHeader(),
                                _buildKoalaAiRow(),
                                _buildEvlumbaStrip(),
                                if (_conversations.isNotEmpty) ...[
                                  _buildSectionLabel('Tasarımcılar', count: _conversations.length),
                                  SliverList.separated(
                                    itemCount: _conversations.length,
                                    separatorBuilder: (_, __) => const _HairLine(indent: 72),
                                    itemBuilder: (_, i) => _buildConversationTile(_conversations[i]),
                                  ),
                                ],
                                if (_aiChats.isNotEmpty) ...[
                                  _buildSectionLabel(
                                    'AI Geçmişi',
                                    count: _aiChats.length,
                                    trailing: _aiChats.length > 3 && !_showAllAi
                                        ? GestureDetector(
                                            onTap: () => setState(() => _showAllAi = true),
                                            child: Text(
                                              'tümünü aç',
                                              style: _V2.body(
                                                size: 11,
                                                weight: FontWeight.w600,
                                                color: _V2.rust,
                                              ),
                                            ),
                                          )
                                        : null,
                                  ),
                                  SliverList.separated(
                                    itemCount: _showAllAi
                                        ? _aiChats.length
                                        : (_aiChats.length > 3 ? 3 : _aiChats.length),
                                    separatorBuilder: (_, __) => const _HairLine(indent: 24),
                                    itemBuilder: (_, i) => _buildAiChatRow(_aiChats[i]),
                                  ),
                                ],
                                const SliverToBoxAdapter(child: SizedBox(height: 96)),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  // ─── Header (serif title + back) ───
  Widget _buildHeader() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 20, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconButton(
              onPressed: _goBackHome,
              icon: const Icon(Icons.arrow_back_rounded, size: 22, color: _V2.ink),
              style: IconButton.styleFrom(
                padding: const EdgeInsets.all(10),
                minimumSize: const Size(40, 40),
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: _maybeOpenDebug,
              child: Text(
                'Mesajlar',
                style: _V2.serif(size: 34, weight: FontWeight.w300, spacing: -1.0),
              ),
            ),
            const Spacer(),
            // Count chip
            if (_conversations.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: _V2.line, width: 0.8),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '${_conversations.length}',
                  style: _V2.body(size: 12, weight: FontWeight.w600, color: _V2.inkSoft),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Koala AI — slim featured row (ex-hero) ───
  Widget _buildKoalaAiRow() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
        child: GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ChatDetailScreen()),
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            decoration: BoxDecoration(
              color: _V2.paper,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _V2.line, width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.025),
                  blurRadius: 14,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                // Koala avatar — circular with subtle ink ring
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _V2.ink,
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/koalas.webp',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.auto_awesome,
                        color: _V2.goldSoft,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Koala AI', style: _V2.serif(size: 18, weight: FontWeight.w500, spacing: -0.3)),
                          const SizedBox(width: 8),
                          // tiny sparkle mark
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _V2.ink,
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              'asistan',
                              style: _V2.body(
                                size: 9.5,
                                weight: FontWeight.w700,
                                color: _V2.goldSoft,
                                spacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Odanı fotoğrafla · stil bul · ürün öner',
                        style: _V2.body(size: 12.5, color: _V2.inkSoft, weight: FontWeight.w400),
                      ),
                    ],
                  ),
                ),
                // Gold thread hint
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _V2.bg,
                    shape: BoxShape.circle,
                    border: Border.all(color: _V2.goldSoft.withValues(alpha: 0.5), width: 0.8),
                  ),
                  child: const Icon(Icons.arrow_outward_rounded, size: 15, color: _V2.ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Evlumba Design strip (slim, gold) ───
  Widget _buildEvlumbaStrip() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: GestureDetector(
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const _EvlumbaSheetV2(),
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _V2.goldSoft.withValues(alpha: 0.45), width: 0.8),
            ),
            child: Row(
              children: [
                // Diamond glyph
                Icon(Icons.auto_awesome_outlined, size: 14, color: _V2.gold),
                const SizedBox(width: 10),
                Text(
                  'Evlumba Design',
                  style: _V2.body(
                    size: 12.5,
                    weight: FontWeight.w700,
                    color: _V2.gold,
                    spacing: 0.2,
                  ),
                ),
                const SizedBox(width: 8),
                Container(width: 3, height: 3, decoration: const BoxDecoration(color: _V2.gold, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'uzman iç mimarlardan 1 sa içinde yanıt',
                    style: _V2.body(size: 12, color: _V2.inkSoft),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 18, color: _V2.gold),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Section label (eyebrow + count) ───
  Widget _buildSectionLabel(String label, {required int count, Widget? trailing}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(label.toUpperCase(), style: _V2.eyebrow()),
            const SizedBox(width: 8),
            // tiny serif numeric
            Text(
              count.toString(),
              style: _V2.serif(size: 13, weight: FontWeight.w400, color: _V2.inkMute, spacing: 0),
            ),
            const Spacer(),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  // ─── Conversation tile — primary list item ───
  Widget _buildConversationTile(Map<String, dynamic> conv) {
    final lastMessage = conv['last_message'] as String? ?? '';
    final projectTitle = (conv['title'] as String? ?? '').trim();
    final lastAt = DateTime.tryParse(conv['last_message_at']?.toString() ?? '');

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

    final hasUnread = unread > 0;

    return InkWell(
      onTap: () async {
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
          MessagingService.markAsRead(convId).then((ok) {
            if (!mounted || ok) return;
            final messenger = ScaffoldMessenger.maybeOf(context);
            final err = MessagingService.lastMarkAsReadError ?? 'bilinmeyen hata';
            messenger?.showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                backgroundColor: const Color(0xFFB00020),
                content: Text('Okundu işaretleme başarısız: $err',
                    style: _V2.body(color: Colors.white)),
              ),
            );
          });
        }
        await context.push('/chat/dm/${conv['id']}', extra: {
          'designerId': designerId,
          'designerName': designerName,
          'designerAvatarUrl': avatarUrl,
          'projectTitle': projectTitle.isNotEmpty ? projectTitle : null,
          'unreadOnEntry': unread,
        });
        _load(silent: true);
      },
      splashColor: _V2.ink.withValues(alpha: 0.04),
      highlightColor: _V2.ink.withValues(alpha: 0.02),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Unread bar — 2px rust vertical line (editorial touch)
            Container(
              width: 2,
              height: 44,
              decoration: BoxDecoration(
                color: hasUnread ? _V2.rust : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 14),
            // Avatar — monogram on paper, no gradient
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _V2.paper,
                border: Border.all(color: _V2.line, width: 0.8),
              ),
              clipBehavior: Clip.antiAlias,
              child: avatarUrl != null && avatarUrl.isNotEmpty
                  ? Image.network(
                      avatarUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _MonogramTile(initials: initials),
                    )
                  : _MonogramTile(initials: initials),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          designerName,
                          style: _V2.body(
                            size: 15,
                            weight: hasUnread ? FontWeight.w700 : FontWeight.w600,
                            color: _V2.ink,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (projectTitle.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '· $projectTitle',
                            style: _V2.body(
                              size: 12,
                              color: _V2.inkMute,
                              weight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (lastMessage.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      lastMessage,
                      style: _V2.body(
                        size: 13,
                        color: hasUnread ? _V2.inkSoft : _V2.inkMute,
                        weight: hasUnread ? FontWeight.w500 : FontWeight.w400,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Timestamp + badge column
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (lastAt != null)
                  Text(
                    timeAgo(lastAt),
                    style: _V2.body(
                      size: 11,
                      weight: hasUnread ? FontWeight.w700 : FontWeight.w500,
                      color: hasUnread ? _V2.rust : _V2.inkMute,
                      spacing: 0.2,
                    ),
                  ),
                if (hasUnread) ...[
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _V2.ink,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      unread > 9 ? '9+' : '$unread',
                      style: _V2.body(
                        size: 10.5,
                        weight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.0,
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

  // ─── AI chat row — dense, secondary ───
  Widget _buildAiChatRow(ChatSummary chat) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatDetailScreen(chatId: chat.id)),
      ),
      splashColor: _V2.ink.withValues(alpha: 0.04),
      highlightColor: _V2.ink.withValues(alpha: 0.02),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 9, 22, 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Minimal bullet — smaller than conv tiles
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _V2.inkMute.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat.title,
                    style: _V2.body(size: 13.5, weight: FontWeight.w600, color: _V2.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (chat.lastMessage != null && chat.lastMessage!.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      chat.lastMessage!,
                      style: _V2.body(size: 11.5, color: _V2.inkMute),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              timeAgo(chat.updatedAt),
              style: _V2.body(size: 10.5, color: _V2.inkMute, weight: FontWeight.w500, spacing: 0.2),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Empty state — editorial card ───
  Widget _buildEmpty() {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        _buildHeader(),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Text(
                  'Bir\nsohbet\nbaşlat',
                  style: _V2.serif(size: 52, weight: FontWeight.w300, spacing: -2.0).copyWith(height: 0.98),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: 280,
                  child: Text(
                    'Koala AI ile odanı analiz et, uzman iç mimarlardan saatler içinde yanıt al.',
                    style: _V2.body(size: 14.5, color: _V2.inkSoft, height: 1.5),
                  ),
                ),
                const SizedBox(height: 28),
                _buildKoalaAiRowEmbedded(),
                const SizedBox(height: 12),
                _buildEvlumbaStripEmbedded(),
                const Spacer(),
                // Tiny editorial signature
                Row(
                  children: [
                    Container(
                      width: 22, height: 0.8,
                      color: _V2.line,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'koala · evlumba',
                      style: _V2.body(
                        size: 10,
                        weight: FontWeight.w600,
                        color: _V2.inkMute,
                        spacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Helper: Koala AI row as non-sliver widget (for empty state)
  Widget _buildKoalaAiRowEmbedded() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ChatDetailScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        decoration: BoxDecoration(
          color: _V2.paper,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _V2.line, width: 0.8),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: const BoxDecoration(color: _V2.ink, shape: BoxShape.circle),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/koalas.webp',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.auto_awesome, color: _V2.goldSoft, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Koala AI', style: _V2.serif(size: 18, weight: FontWeight.w500, spacing: -0.3)),
                  const SizedBox(height: 2),
                  Text(
                    'yeni sohbet başlat',
                    style: _V2.body(size: 12.5, color: _V2.inkSoft),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_outward_rounded, size: 18, color: _V2.ink),
          ],
        ),
      ),
    );
  }

  Widget _buildEvlumbaStripEmbedded() {
    return GestureDetector(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _EvlumbaSheetV2(),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _V2.goldSoft.withValues(alpha: 0.45), width: 0.8),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome_outlined, size: 14, color: _V2.gold),
            const SizedBox(width: 10),
            Text(
              'Evlumba Design',
              style: _V2.body(size: 12.5, weight: FontWeight.w700, color: _V2.gold, spacing: 0.2),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded, size: 18, color: _V2.gold),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Supporting widgets
// ═══════════════════════════════════════════════════════════════════

/// Tile başlık harfleri — ink zeminde krem yazı
class _MonogramTile extends StatelessWidget {
  final String initials;
  const _MonogramTile({required this.initials});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _V2.ink,
      alignment: Alignment.center,
      child: Text(
        initials.isEmpty ? '·' : initials,
        style: _V2.serif(
          size: 15,
          weight: FontWeight.w400,
          color: _V2.bg,
          spacing: 0.2,
        ),
      ),
    );
  }
}

/// İnce hairline separator
class _HairLine extends StatelessWidget {
  final double indent;
  const _HairLine({this.indent = 0});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent, right: 20),
      child: Container(height: 0.6, color: _V2.lineSoft),
    );
  }
}

/// Çok ince warm overlay — grain efekti yerine CPU-ucuz radial wash
class _GrainBackground extends StatelessWidget {
  const _GrainBackground();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.6, -0.8),
            radius: 1.4,
            colors: [
              _V2.paper.withValues(alpha: 0.7),
              _V2.bg,
              _V2.bg,
            ],
            stops: const [0, 0.55, 1.0],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Evlumba bottom sheet — editorial re-skin of premium service card
// ═══════════════════════════════════════════════════════════════════
class _EvlumbaSheetV2 extends StatelessWidget {
  const _EvlumbaSheetV2();

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(28, 14, 28, bottomPad + 24),
      decoration: const BoxDecoration(
        color: _V2.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 3.5,
              decoration: BoxDecoration(
                color: _V2.line,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Evlumba', style: _V2.serif(size: 38, weight: FontWeight.w300, spacing: -1.2).copyWith(height: 1.0)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Design',
                  style: _V2.serif(
                    size: 20,
                    weight: FontWeight.w400,
                    color: _V2.gold,
                    spacing: -0.3,
                  ).copyWith(fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'uzman iç mimarlardan projenize özel çözüm',
            style: _V2.body(size: 14, color: _V2.inkSoft),
          ),
          const SizedBox(height: 26),
          _SheetFeature(number: '01', title: '1 saat içinde yanıt', desc: 'uzmanlarımız hızlıca döner'),
          const SizedBox(height: 14),
          _SheetFeature(number: '02', title: 'sertifikalı kadro', desc: 'deneyimli iç mimarlar ağı'),
          const SizedBox(height: 14),
          _SheetFeature(number: '03', title: 'kişiye özel çözüm', desc: 'projene göre önerilerle'),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: _V2.ink,
                    content: Text(
                      'Evlumba Design yakında',
                      style: _V2.body(color: Colors.white, weight: FontWeight.w600),
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _V2.ink,
                foregroundColor: _V2.bg,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                'sohbet başlat',
                style: _V2.body(size: 14.5, weight: FontWeight.w700, color: _V2.bg, spacing: 0.4),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'ilk danışma ücretsiz',
              style: _V2.body(size: 11.5, color: _V2.inkMute, spacing: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetFeature extends StatelessWidget {
  final String number;
  final String title;
  final String desc;
  const _SheetFeature({required this.number, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 40,
          child: Text(
            number,
            style: _V2.serif(
              size: 22,
              weight: FontWeight.w300,
              color: _V2.goldSoft,
              spacing: 0,
            ).copyWith(fontStyle: FontStyle.italic),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: _V2.body(size: 14.5, weight: FontWeight.w700, color: _V2.ink)),
              const SizedBox(height: 2),
              Text(desc, style: _V2.body(size: 12.5, color: _V2.inkSoft)),
            ],
          ),
        ),
      ],
    );
  }
}
