import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import 'mekan/wizard/mekan_wizard_screen.dart';

import '../core/theme/koala_tokens.dart';
import '../services/background_gen.dart';
import '../widgets/koala_bottom_nav.dart';
import 'chat_list_screen.dart';
import 'main_shell.dart';
import 'mekan/realize_screen.dart';
import 'mekan/stages/result_stage.dart';
import 'style_discovery_live_screen.dart';

/// "Projelerim" — AI ile üretilen tasarımlar burada otomatik listelenir.
/// Trash ikonuna basınca multi-select moduna girer.
class ProjelerScreen extends StatefulWidget {
  const ProjelerScreen({super.key});

  @override
  State<ProjelerScreen> createState() => _ProjelerScreenState();
}

class _ProjelerScreenState extends State<ProjelerScreen> {
  bool _loading = true;
  String? _err;
  List<_ProjectItem> _items = const [];

  bool _selectMode = false;
  final Set<String> _selected = {};

  bool _wasPending = false;
  bool _wasCompleted = false;

  /// Aktif filtre — null = Hepsi (default).
  String? _filter;

  static const List<({String key, String label, IconData icon})> _filters = [
    (key: '', label: 'Hepsi', icon: LucideIcons.sparkles),
    (key: 'oturma', label: 'Oturma Odası', icon: LucideIcons.sofa),
    (key: 'yatak', label: 'Yatak Odası', icon: LucideIcons.bed),
    (key: 'mutfak', label: 'Mutfak', icon: LucideIcons.chefHat),
    (key: 'banyo', label: 'Banyo', icon: LucideIcons.bath),
    (key: 'yemek', label: 'Yemek Odası', icon: LucideIcons.utensilsCrossed),
    (key: 'çalışma', label: 'Çalışma', icon: LucideIcons.laptop),
    (key: 'antre', label: 'Antre', icon: LucideIcons.doorOpen),
  ];

  @override
  void initState() {
    super.initState();
    _load();
    BackgroundGen.notifier.addListener(_onBgGenChange);
    _wasPending = BackgroundGen.notifier.value != null;
    MainShell.activeTab.addListener(_onTabActivate);
  }

  void _onTabActivate() {
    if (MainShell.activeTab.value != KoalaTab.projeler) return;
    if (_filter != null && mounted) setState(() => _filter = null);
  }

  void _setFilter(String key) {
    HapticFeedback.selectionClick();
    final next = key.isEmpty ? null : key;
    if (next == _filter) return;
    setState(() => _filter = next);
  }

  List<_ProjectItem> get _visibleItems {
    if (_filter == null) return _items;
    final f = _filter!;
    return _items
        .where((p) =>
            (p.extra['room'] ?? '').toString().toLowerCase().contains(f) ||
            p.title.toLowerCase().contains(f))
        .toList();
  }

  /// Sadece anlamlı geçişlerde (pending appear/disappear, completed flip)
  /// setState çağrılır — her progress tick'te grid rebuild olmaz, kartlar
  /// titremez.
  void _onBgGenChange() {
    final state = BackgroundGen.notifier.value;
    final isPending = state != null;
    final isCompleted = state?.completed ?? false;
    final pendingChanged = isPending != _wasPending;
    final completedChanged = isCompleted != _wasCompleted;

    if (state == null && _wasPending) {
      _wasPending = false;
      _wasCompleted = false;
      _multiReload();
      _announceComplete();
      return;
    }

    if (isCompleted && !_wasCompleted) {
      _wasCompleted = true;
      // Save+upload arka planda devam ediyor olabilir — birkaç kez yenile.
      _multiReload();
    }

    if (pendingChanged && mounted) {
      _wasPending = isPending;
      setState(() {});
    }
  }

  /// Save + upload arka planda devam ettiği için, ilk reload kayıttan önce
  /// olabilir. Akıllı poll: yeni item gelene kadar bekle, sonra TEK reload.
  /// Sayfa "kendi kendine reload oluyor" hissi yok.
  void _multiReload() async {
    final beforeIds = _items.map((e) => e.itemId).toSet();
    final maxTries = 12; // ~12s
    for (int i = 0; i < maxTries; i++) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) return;
        final res = await Supabase.instance.client
            .from('saved_items')
            .select(
                'id, item_id, item_type, title, image_url, subtitle, extra_data, created_at')
            .eq('user_id', uid)
            .eq('item_type', 'project')
            .order('created_at', ascending: false)
            .limit(60);
        final list = (res as List)
            .cast<Map<String, dynamic>>()
            .map(_ProjectItem.parse)
            .where((p) => p.imageUrl.isNotEmpty)
            .toList();
        // Yeni item geldi mi?
        final newIds = list.map((e) => e.itemId).toSet();
        if (newIds.difference(beforeIds).isNotEmpty || i == maxTries - 1) {
          if (!mounted) return;
          setState(() => _items = list);
          return;
        }
      } catch (_) {}
    }
  }

  void _announceComplete() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: EdgeInsets.zero,
        duration: const Duration(seconds: 4),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: KoalaColors.text.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: KoalaColors.accentDeep,
                ),
                child: const Icon(LucideIcons.sparkles,
                    size: 14, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Tasarımın hazır ✨',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() {
          _items = const [];
          _loading = false;
        });
        return;
      }
      final db = Supabase.instance.client;
      final res = await db
          .from('saved_items')
          .select(
              'id, item_id, item_type, title, image_url, subtitle, extra_data, created_at')
          .eq('user_id', uid)
          .eq('item_type', 'project')
          .order('created_at', ascending: false)
          .limit(60);
      final list = (res as List)
          .cast<Map<String, dynamic>>()
          .map(_ProjectItem.parse)
          .where((p) => p.imageUrl.isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        _err = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _err = e.toString();
      });
    }
  }

  void _enterSelect() {
    HapticFeedback.lightImpact();
    setState(() {
      _selectMode = true;
      _selected.clear();
    });
    // Nav bar'ı gizle, select bottom bar onun yerine otursun.
    MainShell.of(context)?.setNavVisible(false);
  }

  void _exitSelect() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
    MainShell.of(context)?.setNavVisible(true);
  }

  @override
  void dispose() {
    MainShell.activeTab.removeListener(_onTabActivate);
    BackgroundGen.notifier.removeListener(_onBgGenChange);
    // Sekme değişirse nav'ı geri aç (güvenlik). State context disposed olduğu
    // için MainShell'e doğrudan setState atılmaz; null-safe çağrı yeterli.
    if (_selectMode) {
      try {
        MainShell.of(context)?.setNavVisible(true);
      } catch (_) {}
    }
    super.dispose();
  }

  void _toggle(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _selectAll() {
    HapticFeedback.lightImpact();
    setState(() {
      if (_selected.length == _items.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_items.map((e) => e.id));
      }
    });
  }

  Future<void> _confirmDelete() async {
    if (_selected.isEmpty) return;
    final n = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _DeleteDialog(count: n),
    );
    if (ok != true) return;
    HapticFeedback.lightImpact();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ids = _selected.toList();
    // Optimistic UI: anında listeden çıkar, kullanıcı bekletme.
    setState(() {
      _items =
          _items.where((p) => !ids.contains(p.id)).toList(growable: false);
    });
    _exitSelect();
    // Server'a fire-and-forget — başarısız olursa sessiz reload.
    () async {
      try {
        await Supabase.instance.client
            .from('saved_items')
            .delete()
            .inFilter('id', ids);
      } catch (_) {
        if (mounted) _load();
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      extendBody: true,
      // bottomNavigationBar MainShell tarafından sağlanıyor.
      appBar: AppBar(
        backgroundColor: KoalaColors.bg,
        surfaceTintColor: KoalaColors.bg,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        toolbarHeight: 64,
        title: Row(
          children: [
            Text(
              _selectMode ? 'Seç' : 'Projelerim',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: KoalaColors.text,
                letterSpacing: -0.5,
              ),
            ),
            const Spacer(),
            if (_selectMode)
              TextButton(
                onPressed: _exitSelect,
                style: TextButton.styleFrom(
                  foregroundColor: KoalaColors.text,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                child: const Text(
                  'İptal',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
              )
            else if (_items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Material(
                  color: KoalaColors.surface,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _enterSelect,
                    child: Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: KoalaColors.border, width: 0.6),
                      ),
                      child: const Icon(LucideIcons.trash2,
                          size: 18, color: KoalaColors.text),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (!_selectMode) _filterBar(),
          Expanded(child: _body()),
          if (_selectMode) _selectBar(),
        ],
      ),
    );
  }

  Widget _filterBar() {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = _filters[i];
          final active = (_filter ?? '') == f.key;
          return _FilterPill(
            label: f.label,
            icon: f.icon,
            active: active,
            onTap: () => _setFilter(f.key),
          );
        },
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
      child: Row(
        children: [
          Text(
            _selectMode ? 'Seç' : 'Projelerim',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: KoalaColors.text,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          if (_selectMode)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: _exitSelect,
                style: TextButton.styleFrom(
                  foregroundColor: KoalaColors.text,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                child: const Text(
                  'İptal',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ),
          if (!_selectMode)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Material(
                color: KoalaColors.surface,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _items.isEmpty ? null : _enterSelect,
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: KoalaColors.border, width: 0.6),
                    ),
                    child: Icon(
                      LucideIcons.trash2,
                      size: 18,
                      color: _items.isEmpty
                          ? KoalaColors.textTer
                          : KoalaColors.text,
                    ),
                  ),
                ),
              ),
            )
        ],
      ),
    );
  }

  Widget _selectBar() {
    final allSelected =
        _selected.length == _items.length && _items.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        color: KoalaColors.bg,
        border: Border(
          top: BorderSide(color: KoalaColors.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SelBarBtn(
              icon: allSelected
                  ? LucideIcons.xCircle
                  : LucideIcons.circle,
              label: allSelected ? 'Seçimi kaldır' : 'Tümünü Seç',
              onTap: _items.isEmpty ? null : _selectAll,
            ),
          ),
          Container(
            width: 0.5,
            height: 32,
            color: KoalaColors.border,
          ),
          Expanded(
            child: _SelBarBtn(
              icon: LucideIcons.trash2,
              label: 'Sil',
              onTap: _selected.isEmpty ? null : _confirmDelete,
              tint: _selected.isEmpty ? null : const Color(0xFFE45A55),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    if (_err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Yüklenemedi: $_err',
            textAlign: TextAlign.center,
            style: KoalaText.bodySec,
          ),
        ),
      );
    }
    final pending = BackgroundGen.notifier.value;
    final hasPending = pending != null && !pending.completed;
    final visible = _visibleItems;
    if (visible.isEmpty && !hasPending) return _empty();
    final totalCount = visible.length + (hasPending ? 1 : 0);
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.86,
        ),
        itemCount: totalCount,
        itemBuilder: (_, i) {
          if (hasPending && i == 0) {
            return const _PendingCard();
          }
          final idx = hasPending ? i - 1 : i;
          final p = visible[idx];
          return _ProjectCard(
            item: p,
            selectMode: _selectMode,
            selected: _selected.contains(p.id),
            onTap: () {
              if (_selectMode) {
                _toggle(p.id);
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProjectDetailScreen(item: p),
                  ),
                );
              }
            },
            onLongPress: () {
              if (!_selectMode) {
                _enterSelect();
                _toggle(p.id);
              }
            },
          );
        },
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
        physics: const ClampingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 3D-ish hero illustration: layered translucent purple cards.
            SizedBox(
              width: 180,
              height: 180,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    left: 18,
                    top: 30,
                    child: Transform.rotate(
                      angle: -0.20,
                      child: Container(
                        width: 100,
                        height: 130,
                        decoration: BoxDecoration(
                          color:
                              KoalaColors.accentSoft.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: KoalaColors.accent.withValues(alpha: 0.18),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 18,
                    top: 30,
                    child: Transform.rotate(
                      angle: 0.18,
                      child: Container(
                        width: 100,
                        height: 130,
                        decoration: BoxDecoration(
                          color: KoalaColors.accentDeep
                              .withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  KoalaColors.accent.withValues(alpha: 0.32),
                              blurRadius: 22,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            LucideIcons.sparkles,
                            size: 36,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 110,
                    height: 140,
                    decoration: BoxDecoration(
                      color: KoalaColors.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                          color: KoalaColors.border, width: 0.6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        LucideIcons.image,
                        size: 38,
                        color: KoalaColors.accentDeep,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Henüz proje yok',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: KoalaColors.text,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Bir mekan fotoğrafı yükle, AI ile saniyeler\niçinde yeni tasarımlar üret.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: KoalaColors.textSec,
                height: 1.5,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: KoalaColors.accentDeep,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _openPhotoPicker,
                icon: const Icon(LucideIcons.camera, size: 18),
                label: const Text(
                  'Mekan Fotoğrafı Yükle',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPhotoPicker() async {
    HapticFeedback.selectionClick();
    // Alttan kamera/galeri seçim sheet'i.
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PhotoSourceSheet(),
    );
    if (source == null || !mounted) return;
    final picker = ImagePicker();
    final f = await picker.pickImage(
      source: source,
      maxWidth: 1024,
      imageQuality: 55,
    );
    if (f == null || !mounted) return;
    final bytes = await f.readAsBytes();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MekanWizardScreen(photoBytes: bytes),
      ),
    );
  }
}

class _PhotoSourceSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: KoalaColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: KoalaColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Fotoğraf Yükle',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: KoalaColors.text,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _PickerOption(
                  icon: LucideIcons.camera,
                  label: 'Kamera',
                  onTap: () =>
                      Navigator.of(context).pop(ImageSource.camera),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PickerOption(
                  icon: LucideIcons.image,
                  label: 'Galeri',
                  onTap: () =>
                      Navigator.of(context).pop(ImageSource.gallery),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PickerOption extends StatelessWidget {
  const _PickerOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: KoalaColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: KoalaColors.border, width: 0.6),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KoalaColors.accentSoft,
                ),
                child: Icon(icon,
                    size: 22, color: KoalaColors.accentDeep),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: KoalaColors.text,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelBarBtn extends StatelessWidget {
  const _SelBarBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tint,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final color = disabled
        ? KoalaColors.textTer
        : (tint ?? KoalaColors.text);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteDialog extends StatelessWidget {
  const _DeleteDialog({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: KoalaColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: KoalaColors.surfaceAlt,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(LucideIcons.trash2,
                  size: 36, color: KoalaColors.text),
            ),
            const SizedBox(height: 18),
            Text(
              count == 1 ? '1 projeyi sil?' : '$count projeyi sil?',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: KoalaColors.text,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Bu işlem geri alınamaz, emin misin?',
              style: TextStyle(
                fontSize: 13.5,
                color: KoalaColors.textSec,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: KoalaColors.text,
                        backgroundColor: KoalaColors.surfaceAlt,
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text(
                        'İptal',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE45A55),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text(
                        'Sil',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Background üretim sırasında gösterilen kart. Notifier'a kendi içinde
/// abone olur — parent grid rebuild olmaz, sadece bu kart progress'i günceller.
class _PendingCard extends StatelessWidget {
  const _PendingCard();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BackgroundGenState?>(
      valueListenable: BackgroundGen.notifier,
      builder: (_, state, _) {
        if (state == null) return const SizedBox.shrink();
        return RepaintBoundary(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KoalaRadius.lg),
              color: KoalaColors.surface,
              border: Border.all(color: KoalaColors.border, width: 0.6),
              boxShadow: [
                BoxShadow(
                  color: KoalaColors.accent.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(state.sourceBytes, fit: BoxFit.cover),
                IgnorePointer(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.42),
                  ),
                ),
                Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 64,
                        height: 64,
                        child: TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOut,
                          tween: Tween(begin: 0, end: state.progress),
                          builder: (_, v, _) => CircularProgressIndicator(
                            value: state.completed ? 1.0 : v,
                            strokeWidth: 4,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.25),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                KoalaColors.accentDeep),
                          ),
                        ),
                      ),
                      Text(
                        state.completed
                            ? '✓'
                            : '${(state.progress * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 10,
                  bottom: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(KoalaRadius.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.sparkles,
                            size: 11, color: Colors.white),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            state.completed
                                ? 'Hazır ✓'
                                : 'Tasarlanıyor…',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProjectItem {
  final String id;
  final String itemId;
  final String title;
  final String imageUrl;
  final String subtitle;
  final Map<String, dynamic> extra;
  final DateTime createdAt;

  const _ProjectItem({
    required this.id,
    required this.itemId,
    required this.title,
    required this.imageUrl,
    required this.subtitle,
    required this.extra,
    required this.createdAt,
  });

  /// AI-generated mı yoksa gerçek tasarımcı tasarımı mı?
  bool get isAi {
    final cat = (extra['category'] ?? '').toString().toLowerCase();
    return cat == 'interior_design' ||
        cat == 'realize_request' ||
        cat == 'ai' ||
        cat.isEmpty; // default AI varsayım — eski kayıtlar
  }

  String? get designerName =>
      (extra['designer_name'] ?? extra['designer']) as String?;

  static _ProjectItem parse(Map<String, dynamic> j) {
    return _ProjectItem(
      id: (j['id'] ?? '').toString(),
      itemId: (j['item_id'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      imageUrl: (j['image_url'] ?? '').toString(),
      subtitle: (j['subtitle'] ?? '').toString(),
      extra: (j['extra_data'] is Map)
          ? Map<String, dynamic>.from(j['extra_data'] as Map)
          : <String, dynamic>{},
      createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.item,
    required this.selectMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });
  final _ProjectItem item;
  final bool selectMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(KoalaRadius.lg),
        onTap: onTap,
        onLongPress: onLongPress,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KoalaRadius.lg),
            color: KoalaColors.surface,
            border: Border.all(color: KoalaColors.border, width: 0.6),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _afterImage(item.imageUrl),
              IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.55),
                      ],
                      stops: const [0.55, 1.0],
                    ),
                  ),
                ),
              ),
              // Sol alt — tasarım kategorisi
              Positioned(
                left: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(KoalaRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.isAi ? LucideIcons.sparkles : LucideIcons.user,
                        size: 11,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        item.isAi
                            ? 'İç Mimarlık'
                            : (item.designerName ?? 'Tasarımcı'),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Sağ üst — selection circle / AI sparkle indicator
              Positioned(
                top: 10,
                right: 10,
                child: selectMode
                    ? Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected
                              ? KoalaColors.accentDeep
                              : Colors.white.withValues(alpha: 0.85),
                          border: Border.all(
                            color: selected
                                ? KoalaColors.accentDeep
                                : Colors.white,
                            width: 1.4,
                          ),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: KoalaColors.accent
                                        .withValues(alpha: 0.45),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: selected
                            ? const Icon(LucideIcons.check,
                                size: 16, color: Colors.white)
                            : null,
                      )
                    : Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                        child: Icon(
                          item.isAi ? LucideIcons.sparkles : LucideIcons.brush,
                          size: 12,
                          color: KoalaColors.accentDeep,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _afterImage(String s) {
    if (s.startsWith('data:image')) {
      try {
        final commaIdx = s.indexOf(',');
        final b = base64Decode(s.substring(commaIdx + 1));
        return Image.memory(b, fit: BoxFit.cover);
      } catch (_) {
        return Container(color: KoalaColors.surfaceAlt);
      }
    }
    return CachedNetworkImage(
      imageUrl: s,
      fit: BoxFit.cover,
      placeholder: (_, _) => Container(color: KoalaColors.surfaceAlt),
      errorWidget: (_, _, _) => Container(color: KoalaColors.surfaceAlt),
    );
  }
}

/// Proje detayı — Result_stage'in birebir kopyası: top bar + chip + before/after
/// + feedback + 2 aksiyon (İndir/Başka Tarz) + büyük "Bu tasarımı gerçeğe
/// dönüştür" CTA. Saklanmış before bytes ile kart açılır açılmaz before
/// görünür, after ile karşılaştırma çalışır.
class ProjectDetailScreen extends StatefulWidget {
  final _ProjectItem item;
  const ProjectDetailScreen({super.key, required this.item});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  Uint8List? _beforeBytes;
  bool _loadingBefore = false;

  @override
  void initState() {
    super.initState();
    _fetchBefore();
  }

  Future<void> _fetchBefore() async {
    final url = widget.item.extra['before_url']?.toString();
    if (url == null || url.isEmpty) return;
    setState(() => _loadingBefore = true);
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _beforeBytes = res.bodyBytes;
          _loadingBefore = false;
        });
      } else if (mounted) {
        setState(() => _loadingBefore = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingBefore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final room = (item.extra['room'] ?? 'Mekan').toString();
    final theme = (item.extra['theme'] ?? '').toString();
    final palette = item.extra['palette']?.toString();
    final layout = item.extra['layout']?.toString();
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      body: SafeArea(
        child: _beforeBytes != null
            ? ResultStage(
                beforeBytes: _beforeBytes!,
                afterSrc: item.imageUrl,
                room: room,
                theme: theme,
                paletteTr: palette,
                layoutTr: layout,
                mock: false,
                skipAutoSave: true,
                onRetry: () => Navigator.of(context).pop(),
                onNewStyle: () => Navigator.of(context).pop(),
                onRestart: () => Navigator.of(context).pop(),
                onPro: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RealizeScreen(
                        afterSrc: item.imageUrl,
                        room: room,
                        theme: theme,
                        themeValue: theme.toLowerCase(),
                        roomTypeTr: room,
                      ),
                    ),
                  );
                },
              )
            : _loadingFallback(),
      ),
    );
  }

  Widget _loadingFallback() {
    final item = widget.item;
    final hasBeforeUrl =
        (item.extra['before_url']?.toString() ?? '').isNotEmpty;
    if (hasBeforeUrl && _loadingBefore) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    // Eski kayıtlarda before yok — only after fallback (eski davranış).
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Tasarım Sonucu',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: KoalaColors.text,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              Material(
                color: KoalaColors.surface,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: KoalaColors.border, width: 0.6),
                    ),
                    child: const Icon(LucideIcons.x,
                        size: 18, color: KoalaColors.text),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(KoalaRadius.lg),
              child: _afterImage(item.imageUrl),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Bu tasarım eski bir kayıt — orijinal foto saklanmamış.\n'
            'Yeni üretimlerde önce/sonra karşılaştırması otomatik gelir.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: KoalaColors.textSec,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _afterImage(String s) {
    if (s.startsWith('data:image')) {
      try {
        final commaIdx = s.indexOf(',');
        final b = base64Decode(s.substring(commaIdx + 1));
        return Image.memory(b, fit: BoxFit.cover);
      } catch (_) {
        return Container(color: KoalaColors.surfaceAlt);
      }
    }
    return CachedNetworkImage(
      imageUrl: s,
      fit: BoxFit.cover,
      placeholder: (_, _) => Container(color: KoalaColors.surfaceAlt),
      errorWidget: (_, _, _) => Container(color: KoalaColors.surfaceAlt),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.icon, this.tinted = false});
  final String label;
  final IconData? icon;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: tinted ? KoalaColors.accentSoft : KoalaColors.surface,
        borderRadius: BorderRadius.circular(KoalaRadius.pill),
        border: Border.all(
          color: tinted ? Colors.transparent : KoalaColors.border,
          width: 0.6,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 13,
              color: tinted ? KoalaColors.accentDeep : KoalaColors.textSec,
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: tinted ? KoalaColors.accentDeep : KoalaColors.text,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}


class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? KoalaColors.accentDeep : KoalaColors.surface,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: active ? KoalaColors.accentDeep : KoalaColors.border,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16,
                color: active ? Colors.white : KoalaColors.textSec),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : KoalaColors.text,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

