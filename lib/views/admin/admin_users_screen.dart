import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../core/theme/koala_ds.dart';
import '../../core/theme/koala_tokens.dart';
import '../../core/utils/format_utils.dart';
import '../../services/evlumba_live_service.dart';
import '../../widgets/koala_widgets.dart';

/// Admin — Kullanıcılar. Gerçek veri kaynağı: koala_user_profiles (eski boş
/// `users` tablosu DEĞİL). Profesyonel / Ev Sahibi / Admin filtresi + arama.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

enum _UserFilter { all, pro, homeowner, admin }

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  List<Map<String, dynamic>> _all = [];
  Set<String> _adminUids = {};
  bool _loading = true;
  String _search = '';
  _UserFilter _filter = _UserFilter.all;
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

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _db
          .from('koala_user_profiles')
          .select(
              'uid, display_name, mode, verified, profession, avatar_url, contact_info, created_at')
          .order('created_at', ascending: false)
          .limit(500);
      Set<String> admins = {};
      try {
        final a = await _db.from('koala_admins').select('uid');
        admins = List<Map<String, dynamic>>.from(a)
            .map((r) => (r['uid'] ?? '').toString())
            .where((s) => s.isNotEmpty)
            .toSet();
      } catch (_) {/* admin list opsiyonel */}

      // Evlumba tasarımcıları = profesyoneller (specialty = ünvan, örn İç Mimar).
      // Koala'da hesabı olmayan ama platformda görünen profesyoneller burada da
      // listelensin. Koala pro'larıyla çakışmasın diye uid 'evlumba:' prefix'li.
      final merged = List<Map<String, dynamic>>.from(rows);
      try {
        final designers = await EvlumbaLiveService.getAllDesigners(limit: 1000);
        for (final d in designers) {
          final name = (d['full_name'] ?? d['business_name'] ?? '')
              .toString()
              .trim();
          if (name.isEmpty) continue;
          merged.add({
            'uid': 'evlumba:${d['id']}',
            'display_name': name,
            'mode': 'pro',
            'verified': d['is_verified'] == true,
            'profession': (d['specialty'] ?? '').toString().trim(),
            'avatar_url': (d['avatar_url'] ?? '').toString(),
            'contact_info': const <String, dynamic>{},
            'created_at': d['created_at'],
            '_source': 'evlumba',
            '_city': (d['city'] ?? '').toString(),
          });
        }
      } catch (e) {
        debugPrint('AdminUsers: evlumba designers merge failed: $e');
      }

      if (!mounted) return;
      setState(() {
        _all = merged;
        _adminUids = admins;
        _loading = false;
      });
    } catch (e) {
      debugPrint('AdminUsers error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.toLowerCase().trim();
    return _all.where((u) {
      final uid = (u['uid'] ?? '').toString();
      final mode = (u['mode'] ?? 'homeowner').toString();
      final isAdmin = _adminUids.contains(uid);
      switch (_filter) {
        case _UserFilter.pro:
          if (mode != 'pro') return false;
          break;
        case _UserFilter.homeowner:
          if (mode == 'pro') return false;
          break;
        case _UserFilter.admin:
          if (!isAdmin) return false;
          break;
        case _UserFilter.all:
          break;
      }
      if (q.isEmpty) return true;
      final name = (u['display_name'] ?? '').toString().toLowerCase();
      final prof = (u['profession'] ?? '').toString().toLowerCase();
      final phone = u['contact_info'] is Map
          ? (u['contact_info']['phone'] ?? '').toString().toLowerCase()
          : '';
      return name.contains(q) || prof.contains(q) || phone.contains(q);
    }).toList();
  }

  int _countMode(String mode) =>
      _all.where((u) => (u['mode'] ?? 'homeowner').toString() == mode).length;

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      backgroundColor: KoalaDS.bg,
      appBar: AppBar(
        backgroundColor: KoalaDS.bg,
        surfaceTintColor: KoalaDS.bg,
        elevation: 0,
        title: const Text('Kullanıcılar', style: KoalaText.h2),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw,
                size: 18, color: KoalaDS.inkSoft),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    KoalaSpacing.lg, KoalaSpacing.sm, KoalaSpacing.lg, 0),
                child: TextField(
                  controller: _searchCtrl,
                  style: KoalaText.body,
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'İsim, meslek veya telefon ile ara…',
                    hintStyle: KoalaText.hint,
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: KoalaDS.inkFaint),
                    filled: true,
                    fillColor: KoalaDS.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(KoalaR.md),
                      borderSide: BorderSide(color: KoalaDS.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(KoalaR.md),
                      borderSide: BorderSide(color: KoalaDS.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(KoalaR.md),
                      borderSide: BorderSide(color: KoalaDS.accent),
                    ),
                  ),
                ),
              ),
              // Filtre çipleri
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                      horizontal: KoalaSpacing.lg, vertical: 8),
                  children: [
                    _chip('Tümü (${_all.length})', _UserFilter.all),
                    _chip('Profesyonel (${_countMode('pro')})', _UserFilter.pro),
                    _chip('Ev Sahibi (${_all.length - _countMode('pro')})',
                        _UserFilter.homeowner),
                    _chip('Admin (${_adminUids.length})', _UserFilter.admin),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const LoadingState()
                    : list.isEmpty
                        ? Center(
                            child: Text('Kullanıcı bulunamadı',
                                style: KoalaText.bodySec))
                        : RefreshIndicator(
                            onRefresh: _load,
                            color: KoalaDS.accent,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                  KoalaSpacing.lg, 4, KoalaSpacing.lg, 24),
                              itemCount: list.length,
                              itemBuilder: (_, i) => _userCard(list[i]),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, _UserFilter f) {
    final active = _filter == f;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = f),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: active ? KoalaDS.accentDeep : KoalaDS.surface,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
                color: active ? KoalaDS.accentDeep : KoalaDS.line,
                width: 1),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: active ? KoalaDS.onAccent : KoalaDS.ink,
            ),
          ),
        ),
      ),
    );
  }

  Widget _userCard(Map<String, dynamic> u) {
    final uid = (u['uid'] ?? '').toString();
    final name = (u['display_name'] ?? '').toString().trim();
    final mode = (u['mode'] ?? 'homeowner').toString();
    final isPro = mode == 'pro';
    final isAdmin = _adminUids.contains(uid);
    final prof = (u['profession'] ?? '').toString().trim();
    final avatar = (u['avatar_url'] ?? '').toString();
    return GestureDetector(
      onTap: () => _showDetail(u),
      child: Container(
        margin: const EdgeInsets.only(bottom: KoalaSpacing.sm),
        padding: const EdgeInsets.all(KoalaSpacing.md),
        decoration: BoxDecoration(
          color: KoalaDS.surface,
          borderRadius: BorderRadius.circular(KoalaR.lg),
          border: Border.all(color: KoalaDS.line, width: 0.5),
        ),
        child: Row(
          children: [
            ClipOval(
              child: SizedBox(
                width: 42,
                height: 42,
                child: avatar.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: avatar,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: KoalaDS.surfaceMuted,
                          child: const Icon(Icons.person_rounded,
                              color: KoalaDS.inkSoft),
                        ),
                      )
                    : Container(
                        color: KoalaDS.surfaceMuted,
                        child: const Icon(Icons.person_rounded,
                            color: KoalaDS.inkSoft),
                      ),
              ),
            ),
            const SizedBox(width: KoalaSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name.isEmpty ? 'İsimsiz' : name, style: KoalaText.label),
                  Text(
                    isPro ? (prof.isEmpty ? 'Profesyonel' : prof) : 'Ev Sahibi',
                    style: KoalaText.bodySmall,
                  ),
                ],
              ),
            ),
            if (isAdmin) _badge('Admin', KoalaDS.accent),
            if (isPro) ...[
              const SizedBox(width: 6),
              _badge('Pro', KoalaDS.cta),
            ],
          ],
        ),
      ),
    );
  }

  Widget _badge(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(t,
            style: KoalaText.labelSmall.copyWith(
                color: c, fontWeight: FontWeight.w700)),
      );

  void _showDetail(Map<String, dynamic> u) {
    final phone = u['contact_info'] is Map
        ? (u['contact_info']['phone'] ?? '').toString()
        : '';
    showModalBottomSheet(
      context: context,
      backgroundColor: KoalaDS.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(KoalaRadius.xl)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(KoalaSpacing.xl, KoalaSpacing.xl,
            KoalaSpacing.xl, MediaQuery.of(ctx).padding.bottom + KoalaSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text((u['display_name'] ?? 'İsimsiz').toString(), style: KoalaText.h2),
            const SizedBox(height: KoalaSpacing.lg),
            _DetailRow('Tür',
                (u['mode'] ?? 'homeowner') == 'pro' ? 'Profesyonel' : 'Ev Sahibi'),
            _DetailRow('Meslek', (u['profession'] ?? '-').toString()),
            _DetailRow('Doğrulanmış', u['verified'] == true ? 'Evet' : 'Hayır'),
            _DetailRow('Admin',
                _adminUids.contains((u['uid'] ?? '').toString()) ? 'Evet' : 'Hayır'),
            if (phone.isNotEmpty) _DetailRow('Telefon', phone),
            _DetailRow('Kayıt', _formatDate(u['created_at'])),
            _DetailRow('UID', (u['uid'] ?? '').toString()),
            const SizedBox(height: KoalaSpacing.sm),
            Text(
              'Profesyonel yapma / kaldırma, banlama ve silme yakında bu '
              'ekrana eklenecek.',
              style: KoalaText.bodySmall.copyWith(color: KoalaDS.inkFaint),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(dynamic val) {
    if (val == null) return '-';
    final dt = DateTime.tryParse(val.toString());
    if (dt == null) return '-';
    return formatDMYHM(dt);
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child: Text(label, style: KoalaText.bodySec)),
          Expanded(child: Text(value, style: KoalaText.bodyMedium)),
        ],
      ),
    );
  }
}
