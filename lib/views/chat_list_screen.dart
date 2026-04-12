import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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

  // Designer avatar cache
  final Map<String, String?> _avatarCache = {};

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
        _loadDesignerAvatars();
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _hasError = true; });
    }
  }

  /// Tüm tasarımcıların avatarlarını toplu yükle
  Future<void> _loadDesignerAvatars() async {
    if (_conversations.isEmpty) return;
    try {
      if (!EvlumbaLiveService.isReady) {
        await EvlumbaLiveService.waitForReady(timeout: const Duration(seconds: 5));
      }
      if (!EvlumbaLiveService.isReady) return;

      for (final conv in _conversations) {
        final designerId = (conv['designer_id'] ?? '').toString();
        if (designerId.isEmpty || _avatarCache.containsKey(designerId)) continue;
        try {
          final detail = await EvlumbaLiveService.getDesignerById(designerId);
          _avatarCache[designerId] = (detail?['avatar_url'] ?? '').toString().trim();
        } catch (_) {
          _avatarCache[designerId] = null;
        }
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

    final designerId = (conv['designer_id'] ?? '').toString();
    final avatarUrl = _avatarCache[designerId];

    return GestureDetector(
      onTap: () async {
        await context.push('/chat/dm/${conv['id']}', extra: {
          'designerId': designerId,
          'designerName': title,
          'designerAvatarUrl': avatarUrl,
        });
        _load(); // Refresh unread counts
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
