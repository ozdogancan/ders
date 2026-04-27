import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/koala_tokens.dart';
import '../../../services/messaging_service.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Sprint 4 — Pro'dan kullanıcıya structured teklif kartı.
///
/// quote_json şeması (MessagingService.sendQuote):
/// ```
/// {
///   "items": [{"label": "Boya + duvar kağıdı", "qty": 45, "unit": "m²", "unit_price": 280}, ...],
///   "total": 42500,
///   "currency": "TRY",
///   "duration_days": 14,
///   "valid_until": "2026-05-10T00:00:00Z",
///   "notes": "İşçilik dahil, malzeme hariç."
/// }
/// ```
///
/// UI davranışı:
/// - Kullanıcı tarafı + conversation.accepted_quote_id null  → Onayla/Pazarlık/Reddet butonları
/// - Onaylandıysa (messageId == accepted_quote_id)           → "Onaylandı ✅" rozet
/// - Süresi geçtiyse (valid_until < now)                     → "Süresi doldu" soluk
/// - Pro tarafı                                              → salt-gösterim (kendi teklifi)
class QuoteCard extends StatefulWidget {
  const QuoteCard({
    super.key,
    required this.messageId,
    required this.conversationId,
    required this.quoteJson,
    required this.isOwnMessage,
    required this.acceptedQuoteId,
    this.onAccepted,
    this.onNegotiate,
    this.onRejected,
  });

  /// koala_direct_messages.id — accept/reject sırasında DB'ye yazılır.
  final String messageId;
  final String conversationId;
  final Map<String, dynamic> quoteJson;

  /// Bu mesajı biz mi gönderdik (pro tarafı ise true). True ise CTA yok.
  final bool isOwnMessage;

  /// koala_conversations.accepted_quote_id — null ise hiçbir teklif kabul
  /// edilmemiş. Eşitse bu kartın tarzının onaylı göstermesi gerekir.
  final String? acceptedQuoteId;

  /// Kart state değiştikten sonra chat UI'ın refresh tetiklemesi için.
  final VoidCallback? onAccepted;
  final VoidCallback? onNegotiate;
  final VoidCallback? onRejected;

  @override
  State<QuoteCard> createState() => _QuoteCardState();
}

class _QuoteCardState extends State<QuoteCard> {
  bool _accepting = false;

  bool get _isAccepted => widget.acceptedQuoteId == widget.messageId;
  bool get _anotherAccepted =>
      widget.acceptedQuoteId != null &&
      widget.acceptedQuoteId != widget.messageId;

  DateTime? get _validUntil {
    final raw = widget.quoteJson['valid_until'];
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  bool get _expired {
    final d = _validUntil;
    return d != null && d.isBefore(DateTime.now());
  }

  String get _currency => (widget.quoteJson['currency'] as String?) ?? 'TRY';
  String get _currencySym => _currency == 'TRY' ? '₺' : _currency;

  double get _total {
    final t = widget.quoteJson['total'];
    if (t is num) return t.toDouble();
    return 0;
  }

  int? get _durationDays {
    final d = widget.quoteJson['duration_days'];
    if (d is num) return d.toInt();
    return null;
  }

  List<_QuoteItem> get _items {
    final raw = widget.quoteJson['items'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map(_QuoteItem.fromJson).toList();
  }

  @override
  Widget build(BuildContext context) {
    final locked = _isAccepted || _anotherAccepted || _expired;
    final items = _items;

    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(KoalaRadius.lg),
        border: Border.all(
          color: _isAccepted
              ? KoalaColors.green.withValues(alpha: 0.4)
              : KoalaColors.border,
          width: _isAccepted ? 1.2 : 0.5,
        ),
        boxShadow: KoalaShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(),
          if (items.isNotEmpty) _itemsList(items),
          _totalBlock(),
          if (widget.quoteJson['notes'] is String &&
              (widget.quoteJson['notes'] as String).trim().isNotEmpty)
            _notes(widget.quoteJson['notes'] as String),
          if (!widget.isOwnMessage && !locked) _actions(),
          if (_isAccepted) _acceptedBadge(),
          if (_anotherAccepted && !_isAccepted) _supersededBadge(),
          if (_expired && !_isAccepted && !_anotherAccepted) _expiredBadge(),
        ],
      ),
    ).animate().fadeIn(duration: 240.ms).slideY(begin: 0.04, end: 0);
  }

  // ── Subviews ──────────────────────────────────────────────

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        KoalaSpacing.lg,
        KoalaSpacing.md,
        KoalaSpacing.lg,
        KoalaSpacing.sm,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF3F0FF), Color(0xFFFAF8FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(KoalaRadius.lg),
          topRight: Radius.circular(KoalaRadius.lg),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: KoalaColors.accentDeep,
              borderRadius: BorderRadius.circular(KoalaRadius.sm),
            ),
            child: const Icon(
              LucideIcons.fileText,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: KoalaSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Teklif',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: KoalaColors.accentDeep,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _durationDays != null
                      ? '$_durationDays iş günü tahmini süre'
                      : 'Yapım süresi tasarımcıyla netleşir',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: KoalaColors.ink,
                  ),
                ),
              ],
            ),
          ),
          if (_validUntil != null && !_expired)
            _countdownChip(_validUntil!),
        ],
      ),
    );
  }

  Widget _countdownChip(DateTime until) {
    final days = until.difference(DateTime.now()).inDays;
    final label = days <= 0 ? 'Bugün son' : '$days gün geçerli';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(KoalaRadius.pill),
        border: Border.all(color: KoalaColors.border, width: 0.5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: KoalaColors.textSec,
        ),
      ),
    );
  }

  Widget _itemsList(List<_QuoteItem> items) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KoalaSpacing.lg,
        KoalaSpacing.sm,
        KoalaSpacing.lg,
        0,
      ),
      child: Column(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: KoalaColors.ink,
                          ),
                        ),
                        if (item.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            item.subtitle!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: KoalaColors.textSec,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$_currencySym${_formatAmount(item.subtotal)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: KoalaColors.ink,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _totalBlock() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KoalaSpacing.lg,
        KoalaSpacing.md,
        KoalaSpacing.lg,
        KoalaSpacing.md,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KoalaSpacing.md,
          vertical: KoalaSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: KoalaColors.accentSoft,
          borderRadius: BorderRadius.circular(KoalaRadius.sm),
        ),
        child: Row(
          children: [
            const Text(
              'Toplam',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: KoalaColors.textMed,
              ),
            ),
            const Spacer(),
            Text(
              '$_currencySym${_formatAmount(_total)}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: KoalaColors.accentDeep,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notes(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KoalaSpacing.lg,
        0,
        KoalaSpacing.lg,
        KoalaSpacing.md,
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: KoalaColors.textSec,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _actions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        KoalaSpacing.sm,
        0,
        KoalaSpacing.sm,
        KoalaSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: KoalaColors.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: _accepting ? null : widget.onRejected,
              style: TextButton.styleFrom(
                foregroundColor: KoalaColors.textSec,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              child: const Text(
                'Reddet',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          Container(
            width: 1,
            height: 20,
            color: KoalaColors.border,
          ),
          Expanded(
            child: TextButton(
              onPressed: _accepting ? null : widget.onNegotiate,
              style: TextButton.styleFrom(
                foregroundColor: KoalaColors.ink,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              child: const Text(
                'Pazarlık',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4, left: 4),
              child: ElevatedButton(
                onPressed: _accepting ? null : _handleAccept,
                style: ElevatedButton.styleFrom(
                  backgroundColor: KoalaColors.accentDeep,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(KoalaRadius.md),
                  ),
                ),
                child: _accepting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Onayla',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _acceptedBadge() => _statusStrip(
        icon: LucideIcons.checkCircle,
        text: 'Teklif onaylandı',
        color: KoalaColors.green,
      );

  Widget _supersededBadge() => _statusStrip(
        icon: LucideIcons.history,
        text: 'Başka bir teklif kabul edildi',
        color: KoalaColors.textSec,
      );

  Widget _expiredBadge() => _statusStrip(
        icon: LucideIcons.clock,
        text: 'Teklif süresi doldu',
        color: KoalaColors.warning,
      );

  Widget _statusStrip({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: KoalaSpacing.lg,
        vertical: KoalaSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(KoalaRadius.lg),
          bottomRight: Radius.circular(KoalaRadius.lg),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────

  Future<void> _handleAccept() async {
    if (_accepting) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Teklifi onayla?'),
        content: Text(
          'Toplam $_currencySym${_formatAmount(_total)} tutarındaki teklifi '
          'onaylamak istediğine emin misin? Tasarımcıya bildirim gider.',
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KoalaRadius.md),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: KoalaColors.accentDeep,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Evet, onayla'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _accepting = true);
    final ok = await MessagingService.acceptQuote(
      conversationId: widget.conversationId,
      messageId: widget.messageId,
      totalAmount: _total,
      currency: _currency,
    );
    if (!mounted) return;
    setState(() => _accepting = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Teklif onaylandı ✅'),
          backgroundColor: KoalaColors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      widget.onAccepted?.call();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            MessagingService.lastSendError ?? 'Teklif onaylanamadı.',
          ),
          backgroundColor: KoalaColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

// ── Helpers ─────────────────────────────────────────────────

class _QuoteItem {
  final String label;
  final double qty;
  final String? unit;
  final double unitPrice;
  final double? overrideSubtotal;

  _QuoteItem({
    required this.label,
    required this.qty,
    required this.unit,
    required this.unitPrice,
    this.overrideSubtotal,
  });

  factory _QuoteItem.fromJson(Map m) {
    double asDouble(Object? v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0;
      return 0;
    }

    return _QuoteItem(
      label: (m['label'] ?? '').toString(),
      qty: asDouble(m['qty']),
      unit: m['unit']?.toString(),
      unitPrice: asDouble(m['unit_price']),
      overrideSubtotal:
          m['subtotal'] is num ? (m['subtotal'] as num).toDouble() : null,
    );
  }

  double get subtotal => overrideSubtotal ?? (qty * unitPrice);

  /// "45 m² × ₺280" gibi alt satır. Qty yoksa null.
  String? get subtitle {
    if (qty <= 0 && unitPrice <= 0) return null;
    final qtyStr = qty == qty.roundToDouble()
        ? qty.toInt().toString()
        : qty.toStringAsFixed(1);
    final unitStr = unit != null && unit!.isNotEmpty ? ' $unit' : '';
    if (unitPrice <= 0) return '$qtyStr$unitStr';
    return '$qtyStr$unitStr × ₺${_formatAmount(unitPrice)}';
  }
}

String _formatAmount(double v) {
  // Basit TR formatı: binlik için nokta, ondalık yoksa yazma.
  final rounded = v.roundToDouble() == v ? v.toInt() : v;
  final s = rounded.toString();
  if (rounded is int) {
    final buf = StringBuffer();
    final str = rounded.toString();
    for (int i = 0; i < str.length; i++) {
      final remaining = str.length - i;
      buf.write(str[i]);
      if (remaining > 1 && remaining % 3 == 1) buf.write('.');
    }
    return buf.toString();
  }
  return s;
}
