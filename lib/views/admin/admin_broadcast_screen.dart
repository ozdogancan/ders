import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../../core/theme/koala_tokens.dart';

/// Admin — Toplu bildirim gönderme
class AdminBroadcastScreen extends StatefulWidget {
  const AdminBroadcastScreen({super.key});

  @override
  State<AdminBroadcastScreen> createState() => _AdminBroadcastScreenState();
}

class _AdminBroadcastScreenState extends State<AdminBroadcastScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String _target = 'all'; // all, active_7d, active_30d
  int _estimatedCount = 0;
  bool _sending = false;
  bool _counting = false;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _countTarget();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _countTarget() async {
    setState(() => _counting = true);
    try {
      var query = _db.from('users').select('id');

      if (_target == 'active_7d') {
        query = query.gte('last_login_at', DateTime.now().subtract(const Duration(days: 7)).toIso8601String());
      } else if (_target == 'active_30d') {
        query = query.gte('last_login_at', DateTime.now().subtract(const Duration(days: 30)).toIso8601String());
      }

      final res = await query;
      if (mounted) setState(() { _estimatedCount = (res as List).length; _counting = false; });
    } catch (e) {
      if (mounted) setState(() { _estimatedCount = 0; _counting = false; });
    }
  }

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty) return;

    setState(() => _sending = true);

    try {
      // Get target user IDs
      var query = _db.from('users').select('id');
      if (_target == 'active_7d') {
        query = query.gte('last_login_at', DateTime.now().subtract(const Duration(days: 7)).toIso8601String());
      } else if (_target == 'active_30d') {
        query = query.gte('last_login_at', DateTime.now().subtract(const Duration(days: 30)).toIso8601String());
      }

      final users = List<Map<String, dynamic>>.from(await query);

      // Batch insert notifications
      final notifications = users.map((u) => {
        'user_id': u['id'],
        'type': 'system',
        'title': title,
        'body': body.isEmpty ? null : body,
      }).toList();

      // Insert in batches of 50
      for (var i = 0; i < notifications.length; i += 50) {
        final batch = notifications.sublist(i, (i + 50).clamp(0, notifications.length));
        await _db.from('koala_notifications').insert(batch);
      }

      // Admin log
      await _db.from('koala_admin_logs').insert({
        'admin_user_id': _db.auth.currentUser?.id ?? '',
        'action': 'notification_broadcast',
        'target_type': 'broadcast',
        'metadata': {
          'title': title,
          'target': _target,
          'recipient_count': users.length,
        },
      });

      if (mounted) {
        setState(() => _sending = false);
        _titleCtrl.clear();
        _bodyCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${users.length} kullanıcıya bildirim gönderildi')),
        );
      }
    } catch (e) {
      debugPrint('Broadcast error: $e');
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gönderme hatası')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      appBar: AppBar(
        backgroundColor: KoalaColors.bg,
        surfaceTintColor: KoalaColors.bg,
        elevation: 0,
        title: const Text('Bildirim Gönder', style: KoalaText.h2),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(KoalaSpacing.lg),
        children: [
          // Target selector
          const Text('Hedef Kitle', style: KoalaText.caption),
          const SizedBox(height: KoalaSpacing.sm),
          Wrap(
            spacing: KoalaSpacing.sm,
            children: [
              _TargetChip('Tüm Kullanıcılar', 'all'),
              _TargetChip('Son 7 Gün Aktif', 'active_7d'),
              _TargetChip('Son 30 Gün Aktif', 'active_30d'),
            ],
          ),
          const SizedBox(height: KoalaSpacing.sm),
          _counting
              ? const Text('Hesaplanıyor...', style: KoalaText.bodySmall)
              : Text('Tahmini alıcı: $_estimatedCount', style: KoalaText.bodySec),

          const SizedBox(height: KoalaSpacing.xl),

          // Title
          const Text('Başlık', style: KoalaText.caption),
          const SizedBox(height: KoalaSpacing.sm),
          TextField(
            controller: _titleCtrl,
            style: KoalaText.body,
            decoration: _inputDeco('Bildirim başlığı'),
          ),

          const SizedBox(height: KoalaSpacing.lg),

          // Body
          const Text('Açıklama (opsiyonel)', style: KoalaText.caption),
          const SizedBox(height: KoalaSpacing.sm),
          TextField(
            controller: _bodyCtrl,
            style: KoalaText.body,
            maxLines: 3,
            decoration: _inputDeco('Bildirim açıklaması'),
          ),

          const SizedBox(height: KoalaSpacing.xxl),

          // Send button
          GestureDetector(
            onTap: _sending ? null : _send,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: KoalaSpacing.lg),
              decoration: BoxDecoration(
                color: _sending ? KoalaColors.accentLight : KoalaColors.accent,
                borderRadius: BorderRadius.circular(KoalaRadius.md),
              ),
              child: Center(
                child: _sending
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Gönder', style: KoalaText.button),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _TargetChip(String label, String value) {
    final active = _target == value;
    return GestureDetector(
      onTap: () {
        setState(() => _target = value);
        _countTarget();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.md, vertical: KoalaSpacing.sm),
        decoration: BoxDecoration(
          color: active ? KoalaColors.accent : KoalaColors.surface,
          borderRadius: BorderRadius.circular(KoalaRadius.pill),
          border: Border.all(color: active ? KoalaColors.accent : KoalaColors.border),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: active ? Colors.white : KoalaColors.text,
        )),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: KoalaText.hint,
    filled: true,
    fillColor: KoalaColors.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(KoalaRadius.md),
      borderSide: BorderSide(color: KoalaColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(KoalaRadius.md),
      borderSide: BorderSide(color: KoalaColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(KoalaRadius.md),
      borderSide: BorderSide(color: KoalaColors.accent),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.lg, vertical: KoalaSpacing.md),
  );
}
