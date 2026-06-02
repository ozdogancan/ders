import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../../core/theme/koala_tokens.dart';
import '../../widgets/koala_widgets.dart';

/// Admin Dashboard — yonetici icin tum KPI / metrik ozeti.
///
/// Tum sayilar tek `koala_admin_dashboard()` RPC cagrisindan gelir
/// (analytics_events + user_profiles + koala_* tablolari, server-side).
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key, this.onNavigate});

  /// AdminShell'in alt sekmesini degistirir (hizli erisim kartlari icin).
  final void Function(int index)? onNavigate;

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = {};

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _db.rpc('koala_admin_dashboard');
      if (mounted) {
        setState(() {
          _data = Map<String, dynamic>.from(res as Map);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('AdminDashboard error: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  int _v(String section, String key) {
    final s = _data[section];
    if (s is Map) {
      final x = s[key];
      if (x is num) return x.toInt();
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      appBar: AppBar(
        backgroundColor: KoalaColors.bg,
        surfaceTintColor: KoalaColors.bg,
        elevation: 0,
        title: const Text('Yönetim Paneli', style: KoalaText.h2),
        automaticallyImplyLeading: false,
      ),
      body: _loading
          ? const LoadingState()
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: RefreshIndicator(
              onRefresh: _load,
              color: KoalaColors.accent,
              child: ListView(
                padding: const EdgeInsets.all(KoalaSpacing.lg),
                children: _error != null
                    ? [_errorBox(_error!)]
                    : [
                        _hero(),
                        _summary(),
                        _users(),
                        _pro(),
                        _engagement(),
                        _ai(),
                        _messaging(),
                        _content(),
                        _platform(),
                        _topEvents(),
                        _quickAccess(),
                        const SizedBox(height: KoalaSpacing.xl),
                      ],
              ),
            ),
              ),
            ),
    );
  }

  Widget _errorBox(String msg) => Container(
        padding: const EdgeInsets.all(KoalaSpacing.lg),
        decoration: BoxDecoration(
          color: KoalaColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(KoalaRadius.md),
        ),
        child: Text('Panel yüklenemedi: $msg', style: KoalaText.bodySec),
      );

  // ─── Hero — aktif kullanıcılar ───
  Widget _hero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(KoalaSpacing.xl),
      decoration: BoxDecoration(
        gradient: KoalaColors.accentGradientV,
        borderRadius: BorderRadius.circular(KoalaRadius.xl),
        boxShadow: KoalaShadows.accentGlow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded,
                  size: 16, color: Colors.white70),
              const SizedBox(width: 4),
              Text(
                'AKTİF KULLANICILAR',
                style: KoalaText.caption.copyWith(color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: KoalaSpacing.lg),
          Row(
            children: [
              _heroStat('Bugün', _v('active', 'dau')),
              _heroDivider(),
              _heroStat('7 gün', _v('active', 'wau')),
              _heroDivider(),
              _heroStat('30 gün', _v('active', 'mau')),
            ],
          ),
          const SizedBox(height: KoalaSpacing.lg),
          Container(height: 0.5, color: Colors.white24),
          const SizedBox(height: KoalaSpacing.md),
          Row(
            children: [
              const Icon(Icons.groups_rounded,
                  size: 15, color: Colors.white70),
              const SizedBox(width: 6),
              Text(
                'Toplam ${_v('active', 'total_users')} kullanıcı uygulamayı kullandı',
                style: KoalaText.bodySmall.copyWith(color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, int value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: KoalaText.labelSmall.copyWith(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _heroDivider() =>
      Container(width: 0.5, height: 38, color: Colors.white24);

  // ─── Genel Özet (en çok merak edilen sayılar) ───
  Widget _summary() {
    return _section('Genel Özet', [
      _StatCard(
        icon: Icons.groups_rounded,
        color: KoalaColors.accent,
        label: 'Toplam kullanıcı',
        value: _v('summary', 'total_users'),
      ),
      _StatCard(
        icon: Icons.workspace_premium_rounded,
        color: KoalaColors.star,
        label: 'Profesyonel',
        value: _v('summary', 'professionals'),
      ),
      _StatCard(
        icon: Icons.home_rounded,
        color: KoalaColors.blue,
        label: 'Ev sahibi',
        value: _v('summary', 'homeowners'),
      ),
      _StatCard(
        icon: Icons.image_rounded,
        color: KoalaColors.green,
        label: 'Toplam tasarım',
        value: _v('summary', 'shared_designs'),
      ),
      _StatCard(
        icon: Icons.verified_rounded,
        color: KoalaColors.greenAlt,
        label: 'Doğrulanmış',
        value: _v('summary', 'verified'),
      ),
      _StatCard(
        icon: Icons.how_to_reg_rounded,
        color: KoalaColors.warning,
        label: 'Bekleyen başvuru',
        value: _v('summary', 'pro_applications_pending'),
      ),
      _StatCard(
        icon: Icons.favorite_rounded,
        color: KoalaColors.pink,
        label: 'Takip',
        value: _v('summary', 'follows'),
      ),
      _StatCard(
        icon: Icons.forum_rounded,
        color: KoalaColors.accentMuted,
        label: 'Toplam mesaj',
        value: _v('summary', 'messages'),
      ),
    ]);
  }

  // ─── Kullanıcılar ───
  Widget _users() {
    return _section('Kullanıcılar', [
      _StatCard(
        icon: Icons.people_alt_rounded,
        color: KoalaColors.accent,
        label: 'Toplam kullanıcı',
        value: _v('active', 'total_users'),
      ),
      _StatCard(
        icon: Icons.person_add_rounded,
        color: KoalaColors.green,
        label: 'Yeni — bugün',
        value: _v('new_users', 'today'),
      ),
      _StatCard(
        icon: Icons.trending_up_rounded,
        color: KoalaColors.greenAlt,
        label: 'Yeni — 7 gün',
        value: _v('new_users', 'd7'),
      ),
      _StatCard(
        icon: Icons.calendar_month_rounded,
        color: KoalaColors.blue,
        label: 'Yeni — 30 gün',
        value: _v('new_users', 'd30'),
      ),
    ]);
  }

  // ─── Pro & dönüşüm ───
  Widget _pro() {
    final views = _v('pro', 'paywall_views_7d');
    final cta = _v('pro', 'paywall_cta_7d');
    final conv = views > 0 ? (cta / views * 100) : 0.0;
    return _section('Pro & Dönüşüm (7 gün)', [
      _StatCard(
        icon: Icons.workspace_premium_rounded,
        color: KoalaColors.star,
        label: 'Aktif Pro üye',
        value: _v('pro', 'active'),
      ),
      _StatCard(
        icon: Icons.visibility_rounded,
        color: KoalaColors.accentMuted,
        label: 'Paywall gösterimi',
        value: views,
      ),
      _StatCard(
        icon: Icons.ads_click_rounded,
        color: KoalaColors.pink,
        label: 'Paywall CTA tıklaması',
        value: cta,
      ),
      _StatCard(
        icon: Icons.percent_rounded,
        color: KoalaColors.green,
        label: 'CTA dönüşümü',
        valueText: '${conv.toStringAsFixed(1)}%',
      ),
    ]);
  }

  // ─── Etkileşim ───
  Widget _engagement() {
    final likes = _v('engagement', 'likes_7d');
    final passes = _v('engagement', 'passes_7d');
    final likeRate =
        (likes + passes) > 0 ? (likes / (likes + passes) * 100) : 0.0;
    return _section('Etkileşim (7 gün)', [
      _StatCard(
        icon: Icons.favorite_rounded,
        color: KoalaColors.like,
        label: 'Tarz beğenisi',
        value: likes,
      ),
      _StatCard(
        icon: Icons.thumb_down_rounded,
        color: KoalaColors.dislike,
        label: 'Tarz geçişi',
        value: passes,
      ),
      _StatCard(
        icon: Icons.insights_rounded,
        color: KoalaColors.green,
        label: 'Beğeni oranı',
        valueText: '${likeRate.toStringAsFixed(0)}%',
      ),
      _StatCard(
        icon: Icons.bookmark_rounded,
        color: KoalaColors.accent,
        label: 'Toplam kaydetme',
        value: _v('engagement', 'saves_total'),
      ),
      _StatCard(
        icon: Icons.ios_share_rounded,
        color: KoalaColors.blue,
        label: 'Paylaşım',
        value: _v('engagement', 'shares_7d'),
      ),
      _StatCard(
        icon: Icons.touch_app_rounded,
        color: KoalaColors.accentMuted,
        label: 'Bugün uygulama açılışı',
        value: _v('engagement', 'app_opens_today'),
      ),
    ]);
  }

  // ─── AI kullanımı ───
  Widget _ai() {
    final chats = _v('ai', 'chats_7d');
    final rooms = _v('ai', 'rooms_analyzed_7d');
    final restyles = _v('ai', 'restyles_7d');
    final errors = _v('ai', 'errors_7d');
    final totalAi = chats + rooms + restyles;
    final errRate = totalAi > 0 ? (errors / totalAi * 100) : 0.0;
    return _section('AI Kullanımı (7 gün)', [
      _StatCard(
        icon: Icons.chat_bubble_rounded,
        color: KoalaColors.accent,
        label: 'AI sohbet',
        value: chats,
      ),
      _StatCard(
        icon: Icons.photo_camera_rounded,
        color: KoalaColors.blue,
        label: 'Oda analizi',
        value: rooms,
      ),
      _StatCard(
        icon: Icons.auto_awesome_rounded,
        color: KoalaColors.star,
        label: 'Restyle üretimi',
        value: restyles,
      ),
      _StatCard(
        icon: Icons.error_outline_rounded,
        color: errors > 0 ? KoalaColors.error : KoalaColors.green,
        label: 'AI hatası',
        value: errors,
        sub: '%${errRate.toStringAsFixed(1)} hata oranı',
      ),
    ]);
  }

  // ─── Mesajlaşma & SLA ───
  Widget _messaging() {
    final breached = _v('sla', 'breached');
    final warning = _v('sla', 'warning');
    final escalated = _v('sla', 'escalated');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Mesajlaşma'),
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: KoalaSpacing.md,
          crossAxisSpacing: KoalaSpacing.md,
          childAspectRatio: 1.7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _StatCard(
              icon: Icons.forum_rounded,
              color: KoalaColors.accent,
              label: 'Aktif konuşma',
              value: _v('messaging', 'conversations_active'),
            ),
            _StatCard(
              icon: Icons.mark_chat_unread_rounded,
              color: KoalaColors.pink,
              label: 'Bugün mesaj',
              value: _v('messaging', 'messages_today'),
            ),
          ],
        ),
        const SizedBox(height: KoalaSpacing.md),
        // SLA durum şeridi — SLA sekmesine götürür.
        GestureDetector(
          onTap: () => widget.onNavigate?.call(3),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.all(KoalaSpacing.md),
            decoration: BoxDecoration(
              color: KoalaColors.surface,
              borderRadius: BorderRadius.circular(KoalaRadius.md),
              border: Border.all(
                color: breached > 0
                    ? KoalaColors.error.withValues(alpha: 0.4)
                    : KoalaColors.border,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.timer_rounded,
                    size: 20,
                    color: breached > 0
                        ? KoalaColors.error
                        : KoalaColors.textSec),
                const SizedBox(width: KoalaSpacing.sm),
                const Expanded(
                  child: Text('SLA durumu', style: KoalaText.label),
                ),
                _slaPill('$breached', '24s+', KoalaColors.error),
                const SizedBox(width: 6),
                _slaPill('$warning', 'uyarı', KoalaColors.warning),
                const SizedBox(width: 6),
                _slaPill('$escalated', 'eskale', KoalaColors.blue),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: KoalaColors.textTer),
              ],
            ),
          ),
        ),
        const SizedBox(height: KoalaSpacing.xl),
      ],
    );
  }

  Widget _slaPill(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(KoalaRadius.sm),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: color)),
          Text(label,
              style: TextStyle(fontSize: 8, color: color)),
        ],
      ),
    );
  }

  // ─── İçerik ───
  Widget _content() {
    final cards = _v('content', 'feed_cards_published');
    return _section('İçerik', [
      _StatCard(
        icon: Icons.dashboard_customize_rounded,
        color: KoalaColors.accentDeep,
        label: 'Yayında feed kartı',
        value: cards,
      ),
      _StatCard(
        icon: Icons.collections_rounded,
        color: KoalaColors.accentMuted,
        label: 'Toplam feed kartı',
        value: _v('content', 'feed_cards_total'),
      ),
    ]);
  }

  // ─── Platform dağılımı ───
  Widget _platform() {
    final p = _data['platform_30d'];
    final map = p is Map ? Map<String, dynamic>.from(p) : <String, dynamic>{};
    int asInt(dynamic x) => x is num ? x.toInt() : 0;
    final web = asInt(map['web']);
    final android = asInt(map['android']);
    final other = map.entries
        .where((e) => e.key != 'web' && e.key != 'android')
        .fold<int>(0, (s, e) => s + asInt(e.value));
    final total = (web + android + other).clamp(1, 1 << 30);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Platform Dağılımı (30 gün)'),
        Container(
          padding: const EdgeInsets.all(KoalaSpacing.lg),
          decoration: KoalaDeco.cardElevated,
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(KoalaRadius.pill),
                child: Row(
                  children: [
                    if (android > 0)
                      Expanded(
                        flex: android,
                        child: Container(
                            height: 12, color: KoalaColors.green),
                      ),
                    if (web > 0)
                      Expanded(
                        flex: web,
                        child: Container(
                            height: 12, color: KoalaColors.accent),
                      ),
                    if (other > 0)
                      Expanded(
                        flex: other,
                        child: Container(
                            height: 12, color: KoalaColors.textTer),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: KoalaSpacing.md),
              Row(
                children: [
                  _legend(KoalaColors.green, 'Android', android,
                      android / total),
                  _legend(KoalaColors.accent, 'Web', web, web / total),
                  if (other > 0)
                    _legend(KoalaColors.textTer, 'Diğer', other,
                        other / total),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: KoalaSpacing.xl),
      ],
    );
  }

  Widget _legend(Color color, String label, int value, double frac) {
    return Expanded(
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$label  $value (%${(frac * 100).toStringAsFixed(0)})',
              style: KoalaText.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ─── En çok olay ───
  Widget _topEvents() {
    final raw = _data['top_events_7d'];
    final list = raw is List ? raw : const [];
    if (list.isEmpty) return const SizedBox.shrink();
    int countOf(dynamic e) =>
        (e is Map && e['count'] is num) ? (e['count'] as num).toInt() : 0;
    final maxCount = list
        .map(countOf)
        .fold<int>(1, (m, c) => c > m ? c : m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('En Çok Olay (7 gün)'),
        Container(
          padding: const EdgeInsets.all(KoalaSpacing.lg),
          decoration: KoalaDeco.cardElevated,
          child: Column(
            children: [
              for (final e in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: KoalaSpacing.md),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(
                          (e is Map ? e['name']?.toString() : '') ?? '',
                          style: KoalaText.labelSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(KoalaRadius.pill),
                          child: LinearProgressIndicator(
                            value: countOf(e) / maxCount,
                            minHeight: 8,
                            backgroundColor: KoalaColors.surfaceAlt,
                            valueColor: const AlwaysStoppedAnimation(
                                KoalaColors.accent),
                          ),
                        ),
                      ),
                      const SizedBox(width: KoalaSpacing.sm),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '${countOf(e)}',
                          textAlign: TextAlign.right,
                          style: KoalaText.label,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: KoalaSpacing.xl),
      ],
    );
  }

  // ─── Hızlı erişim ───
  Widget _quickAccess() {
    final items = <(IconData, String, int)>[
      (Icons.people_rounded, 'Kullanıcılar', 1),
      (Icons.chat_rounded, 'Mesajlar', 2),
      (Icons.timer_rounded, 'SLA İzleme', 3),
      (Icons.campaign_rounded, 'Bildirim', 4),
      (Icons.analytics_rounded, 'Analitik', 5),
      (Icons.settings_rounded, 'Ayarlar', 6),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Hızlı Erişim'),
        GridView.count(
          crossAxisCount: 3,
          mainAxisSpacing: KoalaSpacing.md,
          crossAxisSpacing: KoalaSpacing.md,
          childAspectRatio: 1.05,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final it in items)
              GestureDetector(
                onTap: () => widget.onNavigate?.call(it.$3),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  decoration: KoalaDeco.card,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(it.$1, size: 24, color: KoalaColors.accent),
                      const SizedBox(height: KoalaSpacing.sm),
                      Text(it.$2,
                          textAlign: TextAlign.center,
                          style: KoalaText.labelSmall),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ─── Ortak: bölüm ───
  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(
            top: KoalaSpacing.xl, bottom: KoalaSpacing.md),
        child: Text(title.toUpperCase(), style: KoalaText.caption),
      );

  Widget _section(String title, List<Widget> cards) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(title),
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: KoalaSpacing.md,
          crossAxisSpacing: KoalaSpacing.md,
          childAspectRatio: 1.7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: cards,
        ),
      ],
    );
  }
}

/// Tek metrik karti — ikon, deger, etiket, opsiyonel alt-metin.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.color,
    required this.label,
    this.value,
    this.valueText,
    this.sub,
  });

  final IconData icon;
  final Color color;
  final String label;
  final int? value;
  final String? valueText;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KoalaSpacing.md),
      decoration: KoalaDeco.cardElevated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(KoalaRadius.xs),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                valueText ?? '${value ?? 0}',
                style: KoalaText.h1.copyWith(color: KoalaColors.text),
              ),
              Text(label,
                  style: KoalaText.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              if (sub != null)
                Text(sub!,
                    style: KoalaText.labelSmall
                        .copyWith(color: color, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
            ],
          ),
        ],
      ),
    );
  }
}
