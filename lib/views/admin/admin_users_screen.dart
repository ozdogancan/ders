import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../../core/theme/koala_tokens.dart';
import '../../core/utils/format_utils.dart';
import '../../widgets/koala_widgets.dart';

/// Admin — Kullanıcı yönetimi
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  int _offset = 0;
  final int _limit = 20;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = true}) async {
    if (reset) _offset = 0;
    setState(() => _loading = true);
    try {
      var query = _db.from('users').select();
      if (_searchQuery.isNotEmpty) {
        query = query.ilike('email', '%$_searchQuery%');
      }
      final data = await query
          .order('created_at', ascending: false)
          .range(_offset, _offset + _limit - 1);
      if (mounted) {
        setState(() {
          _users = reset ? List<Map<String, dynamic>>.from(data) : [..._users, ...List<Map<String, dynamic>>.from(data)];
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('AdminUsers error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeRole(String userId, String newRole) async {
    try {
      await _db.from('users').update({'role': newRole}).eq('id', userId);
      // Admin log
      await _db.from('koala_admin_logs').insert({
        'admin_user_id': _db.auth.currentUser?.id ?? '',
        'action': 'user_role_change',
        'target_type': 'user',
        'target_id': userId,
        'metadata': {'new_role': newRole},
      });
      _load();
    } catch (e) {
      debugPrint('Role change error: $e');
    }
  }

  void _showUserDetail(Map<String, dynamic> user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KoalaColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(KoalaRadius.xl)),
      ),
      builder: (ctx) {
        final role = user['role'] as String? ?? 'user';
        return Padding(
          padding: const EdgeInsets.all(KoalaSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user['display_name'] as String? ?? 'İsimsiz', style: KoalaText.h2),
              const SizedBox(height: KoalaSpacing.sm),
              Text(user['email'] as String? ?? '', style: KoalaText.bodySec),
              const SizedBox(height: KoalaSpacing.lg),
              _DetailRow('Rol', role),
              _DetailRow('Kayıt', _formatDate(user['created_at'])),
              _DetailRow('Son Giriş', _formatDate(user['last_login_at'])),
              const SizedBox(height: KoalaSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _changeRole(user['id'] as String, role == 'admin' ? 'user' : 'admin');
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: KoalaSpacing.md),
                        decoration: BoxDecoration(
                          color: role == 'admin' ? KoalaColors.error.withOpacity(0.1) : KoalaColors.accentLight,
                          borderRadius: BorderRadius.circular(KoalaRadius.md),
                        ),
                        child: Center(
                          child: Text(
                            role == 'admin' ? 'Admin\'i Kaldır' : 'Admin Yap',
                            style: KoalaText.label.copyWith(
                              color: role == 'admin' ? KoalaColors.error : KoalaColors.accent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: MediaQuery.of(ctx).padding.bottom + KoalaSpacing.md),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(dynamic val) {
    if (val == null) return '-';
    final dt = DateTime.tryParse(val.toString());
    if (dt == null) return '-';
    return formatDMYHM(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      appBar: AppBar(
        backgroundColor: KoalaColors.bg,
        surfaceTintColor: KoalaColors.bg,
        elevation: 0,
        title: const Text('Kullanıcılar', style: KoalaText.h2),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.lg, vertical: KoalaSpacing.sm),
            child: TextField(
              controller: _searchCtrl,
              style: KoalaText.body,
              onSubmitted: (v) {
                _searchQuery = v.trim();
                _load();
              },
              decoration: InputDecoration(
                hintText: 'E-posta ile ara...',
                hintStyle: KoalaText.hint,
                prefixIcon: const Icon(Icons.search_rounded, color: KoalaColors.textTer),
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
              ),
            ),
          ),

          // List
          Expanded(
            child: _loading && _users.isEmpty
                ? const LoadingState()
                : RefreshIndicator(
                    onRefresh: () => _load(),
                    color: KoalaColors.accent,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.lg),
                      itemCount: _users.length + 1,
                      itemBuilder: (context, index) {
                        if (index == _users.length) {
                          return Padding(
                            padding: const EdgeInsets.all(KoalaSpacing.lg),
                            child: Center(
                              child: GestureDetector(
                                onTap: () { _offset += _limit; _load(reset: false); },
                                child: Text('Daha fazla yükle', style: KoalaText.label.copyWith(color: KoalaColors.accent)),
                              ),
                            ),
                          );
                        }
                        final u = _users[index];
                        final role = u['role'] as String? ?? 'user';
                        return GestureDetector(
                          onTap: () => _showUserDetail(u),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: KoalaSpacing.sm),
                            padding: const EdgeInsets.all(KoalaSpacing.md),
                            decoration: KoalaDeco.card,
                            child: Row(
                              children: [
                                Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: role == 'admin' ? KoalaColors.accent.withOpacity(0.15) : KoalaColors.surfaceAlt,
                                  ),
                                  child: Icon(
                                    role == 'admin' ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
                                    size: 20,
                                    color: role == 'admin' ? KoalaColors.accent : KoalaColors.textSec,
                                  ),
                                ),
                                const SizedBox(width: KoalaSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(u['display_name'] as String? ?? 'İsimsiz', style: KoalaText.label),
                                      Text(u['email'] as String? ?? '', style: KoalaText.bodySmall),
                                    ],
                                  ),
                                ),
                                if (role == 'admin')
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: KoalaColors.accentLight,
                                      borderRadius: BorderRadius.circular(KoalaRadius.pill),
                                    ),
                                    child: Text('Admin', style: KoalaText.labelSmall.copyWith(color: KoalaColors.accent)),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KoalaSpacing.sm),
      child: Row(
        children: [
          Text('$label: ', style: KoalaText.bodySec),
          Text(value, style: KoalaText.bodyMedium),
        ],
      ),
    );
  }
}
