import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../../core/theme/koala_tokens.dart';
import '../../core/utils/format_utils.dart';
import '../../widgets/koala_widgets.dart';

/// Admin — Mesaj moderasyonu
class AdminMessagesScreen extends StatefulWidget {
  const AdminMessagesScreen({super.key});

  @override
  State<AdminMessagesScreen> createState() => _AdminMessagesScreenState();
}

class _AdminMessagesScreenState extends State<AdminMessagesScreen> {
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  int _offset = 0;
  final int _limit = 20;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = true}) async {
    if (reset) _offset = 0;
    setState(() => _loading = true);
    try {
      final data = await _db
          .from('koala_direct_messages')
          .select('*, koala_conversations!inner(user_id, designer_id, status)')
          .order('created_at', ascending: false)
          .range(_offset, _offset + _limit - 1);
      if (mounted) {
        setState(() {
          _messages = reset ? List<Map<String, dynamic>>.from(data) : [..._messages, ...List<Map<String, dynamic>>.from(data)];
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('AdminMessages error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteMessage(String id, int index) async {
    try {
      await _db.from('koala_direct_messages').delete().eq('id', id);
      await _db.from('koala_admin_logs').insert({
        'admin_user_id': _db.auth.currentUser?.id ?? '',
        'action': 'content_delete',
        'target_type': 'message',
        'target_id': id,
      });
      setState(() => _messages.removeAt(index));
    } catch (e) {
      debugPrint('Delete message error: $e');
    }
  }

  Future<void> _changeConversationStatus(String convId, String status) async {
    try {
      await _db.from('koala_conversations').update({'status': status}).eq('id', convId);
      await _db.from('koala_admin_logs').insert({
        'admin_user_id': _db.auth.currentUser?.id ?? '',
        'action': 'user_ban',
        'target_type': 'conversation',
        'target_id': convId,
        'metadata': {'new_status': status},
      });
      _load();
    } catch (e) {
      debugPrint('Change status error: $e');
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
        title: const Text('Mesaj Moderasyonu', style: KoalaText.h2),
        automaticallyImplyLeading: false,
      ),
      body: _loading && _messages.isEmpty
          ? const LoadingState()
          : RefreshIndicator(
              onRefresh: () => _load(),
              color: KoalaColors.accent,
              child: ListView.builder(
                padding: const EdgeInsets.all(KoalaSpacing.lg),
                itemCount: _messages.length + 1,
                itemBuilder: (context, index) {
                  if (index == _messages.length) {
                    return Padding(
                      padding: const EdgeInsets.all(KoalaSpacing.lg),
                      child: Center(
                        child: GestureDetector(
                          onTap: () { _offset += _limit; _load(reset: false); },
                          child: Text('Daha fazla', style: KoalaText.label.copyWith(color: KoalaColors.accent)),
                        ),
                      ),
                    );
                  }
                  final msg = _messages[index];
                  final content = msg['content'] as String? ?? '';
                  final senderId = msg['sender_id'] as String? ?? '';
                  final convId = msg['conversation_id'] as String? ?? '';
                  final conv = msg['koala_conversations'] as Map<String, dynamic>?;
                  final convStatus = conv?['status'] as String? ?? 'active';
                  final createdAt = DateTime.tryParse(msg['created_at']?.toString() ?? '');

                  return Container(
                    margin: const EdgeInsets.only(bottom: KoalaSpacing.sm),
                    padding: const EdgeInsets.all(KoalaSpacing.md),
                    decoration: BoxDecoration(
                      color: KoalaColors.surface,
                      borderRadius: BorderRadius.circular(KoalaRadius.md),
                      border: Border.all(
                        color: convStatus == 'blocked' ? KoalaColors.error.withOpacity(0.3) : KoalaColors.border,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Gönderen: ${senderId.substring(0, senderId.length.clamp(0, 8))}...',
                                style: KoalaText.labelSmall,
                              ),
                            ),
                            if (createdAt != null)
                              Text(
                                formatDMHM(createdAt),
                                style: KoalaText.labelSmall,
                              ),
                          ],
                        ),
                        const SizedBox(height: KoalaSpacing.sm),
                        Text(content, style: KoalaText.body, maxLines: 3, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: KoalaSpacing.sm),
                        Row(
                          children: [
                            // Status badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: convStatus == 'active' ? KoalaColors.greenLight : KoalaColors.error.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(KoalaRadius.pill),
                              ),
                              child: Text(
                                convStatus,
                                style: KoalaText.labelSmall.copyWith(
                                  color: convStatus == 'active' ? KoalaColors.green : KoalaColors.error,
                                ),
                              ),
                            ),
                            const Spacer(),
                            // Actions
                            GestureDetector(
                              onTap: () => _changeConversationStatus(
                                convId,
                                convStatus == 'active' ? 'blocked' : 'active',
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  convStatus == 'active' ? Icons.block_rounded : Icons.check_circle_rounded,
                                  size: 20,
                                  color: convStatus == 'active' ? KoalaColors.error : KoalaColors.green,
                                ),
                              ),
                            ),
                            const SizedBox(width: KoalaSpacing.sm),
                            GestureDetector(
                              onTap: () => _deleteMessage(msg['id'] as String, index),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.delete_rounded, size: 20, color: KoalaColors.error),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}
