import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../../core/theme/koala_ds.dart';
import '../../core/theme/koala_tokens.dart';
import '../../core/utils/format_utils.dart';
import '../../widgets/koala_widgets.dart';

/// Admin — 24 saat SLA izleme.
///
/// `koala_sla_overview()` RPC'sini gosterir: gercek tasarimciya atilmis,
/// yanit bekleyen konusmalar + son 14 gunde eskale edilenler. Eskalasyon
/// otomasyonunu (`/api/cron/escalate-stale`, 3 saatte bir) gozle takip
/// etmek icin — salt okunur.
class AdminSlaScreen extends StatefulWidget {
  const AdminSlaScreen({super.key});

  @override
  State<AdminSlaScreen> createState() => _AdminSlaScreenState();
}

enum _Bucket { breached, warning, fresh, escalated }

class _SlaRow {
  _SlaRow(Map<String, dynamic> m)
      : conversationId = m['conversation_id'] as String? ?? '',
        userId = m['user_id'] as String? ?? '',
        designerId = m['designer_id'] as String? ?? '',
        designerName = m['designer_name'] as String? ?? 'Tasarımcı',
        lastMessage = m['last_message'] as String? ?? '',
        lastMessageAt =
            DateTime.tryParse(m['last_message_at']?.toString() ?? ''),
        hoursWaiting =
            double.tryParse(m['hours_waiting']?.toString() ?? '') ?? 0,
        awaiting = m['awaiting_designer'] == true,
        escalated = m['escalated'] == true;

  final String conversationId;
  final String userId;
  final String designerId;
  final String designerName;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final double hoursWaiting;
  final bool awaiting;
  final bool escalated;

  _Bucket get bucket {
    if (awaiting && hoursWaiting >= 24) return _Bucket.breached;
    if (awaiting && hoursWaiting >= 12) return _Bucket.warning;
    if (awaiting) return _Bucket.fresh;
    return _Bucket.escalated;
  }
}

class _AdminSlaScreenState extends State<AdminSlaScreen> {
  List<_SlaRow> _rows = [];
  bool _loading = true;
  String? _error;

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
      final data = await _db.rpc('koala_sla_overview');
      final list = (data as List)
          .map((e) => _SlaRow(Map<String, dynamic>.from(e as Map)))
          .toList();
      // Aciliyet sirasi: breached > warning > escalated > fresh, icinde saat azalan.
      const order = {
        _Bucket.breached: 0,
        _Bucket.warning: 1,
        _Bucket.escalated: 2,
        _Bucket.fresh: 3,
      };
      list.sort((a, b) {
        final c = order[a.bucket]!.compareTo(order[b.bucket]!);
        if (c != 0) return c;
        return b.hoursWaiting.compareTo(a.hoursWaiting);
      });
      if (mounted) {
        setState(() {
          _rows = list;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('AdminSla error: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  int _count(_Bucket b) => _rows.where((r) => r.bucket == b).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaDS.bg,
      appBar: AppBar(
        backgroundColor: KoalaDS.bg,
        surfaceTintColor: KoalaDS.bg,
        elevation: 0,
        title: const Text('SLA İzleme', style: KoalaText.h2),
        automaticallyImplyLeading: false,
      ),
      body: _loading && _rows.isEmpty
          ? const LoadingState()
          : RefreshIndicator(
              onRefresh: _load,
              color: KoalaDS.accent,
              child: ListView(
                padding: const EdgeInsets.all(KoalaSpacing.lg),
                children: [
                  _summary(),
                  const SizedBox(height: KoalaSpacing.lg),
                  if (_error != null)
                    _errorBox(_error!)
                  else if (_rows.isEmpty)
                    _emptyBox()
                  else
                    ..._rows.map(_card),
                ],
              ),
            ),
    );
  }

  Widget _summary() {
    return Row(
      children: [
        _stat('24s+ aşıldı', _count(_Bucket.breached), KoalaDS.danger),
        const SizedBox(width: KoalaSpacing.sm),
        _stat('Uyarı (12-24s)', _count(_Bucket.warning), KoalaDS.star),
        const SizedBox(width: KoalaSpacing.sm),
        _stat('Eskale', _count(_Bucket.escalated), KoalaDS.clay),
      ],
    );
  }

  Widget _stat(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: KoalaSpacing.md,
          horizontal: KoalaSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: KoalaDS.surface,
          borderRadius: BorderRadius.circular(KoalaRadius.md),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: KoalaText.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBox(String msg) {
    return Container(
      padding: const EdgeInsets.all(KoalaSpacing.lg),
      decoration: BoxDecoration(
        color: KoalaDS.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(KoalaRadius.md),
      ),
      child: Text('Yüklenemedi: $msg', style: KoalaText.bodySec),
    );
  }

  Widget _emptyBox() {
    return Padding(
      padding: const EdgeInsets.only(top: KoalaSpacing.xxxl),
      child: Column(
        children: [
          const Icon(Icons.check_circle_rounded,
              size: 56, color: KoalaDS.cta),
          const SizedBox(height: KoalaSpacing.md),
          Text('Bekleyen konuşma yok', style: KoalaText.h3),
          const SizedBox(height: KoalaSpacing.xs),
          Text('Tüm tasarımcılar güncel.', style: KoalaText.bodySec),
        ],
      ),
    );
  }

  Color _bucketColor(_Bucket b) {
    switch (b) {
      case _Bucket.breached:
        return KoalaDS.danger;
      case _Bucket.warning:
        return KoalaDS.star;
      case _Bucket.escalated:
        return KoalaDS.clay;
      case _Bucket.fresh:
        return KoalaDS.cta;
    }
  }

  String _bucketLabel(_Bucket b) {
    switch (b) {
      case _Bucket.breached:
        return '24s+ aşıldı';
      case _Bucket.warning:
        return 'Uyarı';
      case _Bucket.escalated:
        return 'Eskale edildi';
      case _Bucket.fresh:
        return 'Bekliyor';
    }
  }

  Widget _card(_SlaRow r) {
    final color = _bucketColor(r.bucket);
    final hours = r.hoursWaiting;
    final waitText = hours >= 24
        ? '${(hours / 24).floor()}g ${(hours % 24).round()}s'
        : '${hours.toStringAsFixed(hours < 10 ? 1 : 0)}s';

    return GestureDetector(
      onTap: () => _openThread(r),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: KoalaSpacing.sm),
        padding: const EdgeInsets.all(KoalaSpacing.md),
        decoration: BoxDecoration(
          color: KoalaDS.surface,
          borderRadius: BorderRadius.circular(KoalaRadius.md),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.designerName,
                    style: KoalaText.h4,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(KoalaRadius.pill),
                  ),
                  child: Text(
                    '$waitText bekliyor',
                    style: KoalaText.labelSmall.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: KoalaSpacing.xs),
            Row(
              children: [
                _tag(_bucketLabel(r.bucket), color),
                if (r.escalated && r.bucket != _Bucket.escalated) ...[
                  const SizedBox(width: KoalaSpacing.xs),
                  _tag('eskale ✓', KoalaDS.clay),
                ],
              ],
            ),
            const SizedBox(height: KoalaSpacing.sm),
            Text(
              r.lastMessage,
              style: KoalaText.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: KoalaSpacing.sm),
            Row(
              children: [
                Icon(Icons.person_outline_rounded,
                    size: 13, color: KoalaDS.inkFaint),
                const SizedBox(width: 3),
                Text(
                  r.userId.substring(0, r.userId.length.clamp(0, 8)),
                  style: KoalaText.labelSmall,
                ),
                const Spacer(),
                if (r.lastMessageAt != null)
                  Text(formatDMHM(r.lastMessageAt!),
                      style: KoalaText.labelSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(KoalaRadius.xs),
      ),
      child: Text(
        text,
        style: KoalaText.labelSmall
            .copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  void _openThread(_SlaRow r) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KoalaDS.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(KoalaRadius.xl)),
      ),
      builder: (_) => _ThreadSheet(row: r),
    );
  }
}

/// Konusmanin son ~30 mesajini salt-okunur gosterir.
class _ThreadSheet extends StatefulWidget {
  const _ThreadSheet({required this.row});
  final _SlaRow row;

  @override
  State<_ThreadSheet> createState() => _ThreadSheetState();
}

class _ThreadSheetState extends State<_ThreadSheet> {
  List<Map<String, dynamic>> _msgs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await Supabase.instance.client
          .from('koala_direct_messages')
          .select('sender_id, content, created_at, metadata')
          .eq('conversation_id', widget.row.conversationId)
          .order('created_at', ascending: false)
          .limit(30);
      if (mounted) {
        setState(() {
          _msgs = List<Map<String, dynamic>>.from(data).reversed.toList();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('ThreadSheet error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: KoalaSpacing.sm),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: KoalaDS.line,
                borderRadius: BorderRadius.circular(KoalaRadius.pill),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(KoalaSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.designerName, style: KoalaText.h3),
                        const SizedBox(height: 2),
                        Text('Müşteri: ${r.userId}',
                            style: KoalaText.labelSmall),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    color: KoalaDS.inkSoft,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: KoalaDS.line),
            Expanded(
              child: _loading
                  ? const LoadingState()
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(KoalaSpacing.lg),
                      itemCount: _msgs.length,
                      itemBuilder: (context, i) {
                        final m = _msgs[i];
                        final senderId = m['sender_id'] as String? ?? '';
                        final isUser = senderId == r.userId;
                        final meta = m['metadata'];
                        final isEscalation = meta is Map &&
                            meta['escalation'] == true;
                        final createdAt = DateTime.tryParse(
                            m['created_at']?.toString() ?? '');
                        return Align(
                          alignment: isUser
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          child: Container(
                            margin:
                                const EdgeInsets.only(bottom: KoalaSpacing.sm),
                            padding: const EdgeInsets.all(KoalaSpacing.md),
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.78,
                            ),
                            decoration: BoxDecoration(
                              color: isEscalation
                                  ? KoalaDS.clay.withValues(alpha: 0.08)
                                  : isUser
                                      ? KoalaDS.surfaceMuted
                                      : KoalaDS.accentTint,
                              borderRadius:
                                  BorderRadius.circular(KoalaRadius.md),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isUser
                                      ? 'Müşteri'
                                      : (isEscalation
                                          ? 'Otomatik eskalasyon'
                                          : 'Tasarımcı'),
                                  style: KoalaText.labelSmall.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: isEscalation
                                        ? KoalaDS.clay
                                        : KoalaDS.inkSoft,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(m['content'] as String? ?? '',
                                    style: KoalaText.body),
                                if (createdAt != null) ...[
                                  const SizedBox(height: 3),
                                  Text(formatDMHM(createdAt),
                                      style: KoalaText.labelSmall),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
