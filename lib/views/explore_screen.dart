import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/theme/koala_tokens.dart';
import '../services/evlumba_live_service.dart';
import '../services/saved_items_service.dart';
import '../widgets/save_button.dart';
import '../widgets/error_state.dart';
import '../widgets/shimmer_loading.dart';

/// Keşfet ekranı — evlumba tasarımlarını grid'de göster
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  List<Map<String, dynamic>> _projects = [];
  bool _loading = true;
  bool _hasError = false;
  String? _selectedRoom;
  int _offset = 0;
  final int _limit = 20;
  final _scrollCtrl = ScrollController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  final _rooms = [
    {'key': null, 'label': 'Tümü'},
    {'key': 'salon', 'label': 'Salon'},
    {'key': 'yatak_odasi', 'label': 'Yatak Odası'},
    {'key': 'mutfak', 'label': 'Mutfak'},
    {'key': 'banyo', 'label': 'Banyo'},
    {'key': 'ofis', 'label': 'Ofis'},
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _search() async {
    if (_searchQuery.isEmpty) return _load();
    setState(() { _loading = true; _hasError = false; });
    try {
      final data = await EvlumbaLiveService.getProjects(
        limit: _limit,
        offset: 0,
        query: _searchQuery,
        projectType: _selectedRoom,
      );
      if (mounted) setState(() { _projects = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _hasError = true; });
    }
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    _offset = 0;
    setState(() { _loading = true; _hasError = false; });
    try {
      final data = await EvlumbaLiveService.getProjects(
        limit: _limit,
        offset: 0,
        projectType: _selectedRoom,
      );
      if (mounted) setState(() { _projects = data; _loading = false; });
    } catch (e) {
      debugPrint('Explore load error: $e');
      if (mounted) setState(() { _loading = false; _hasError = true; });
    }
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    _offset += _limit;
    try {
      final data = await EvlumbaLiveService.getProjects(
        limit: _limit,
        offset: _offset,
        projectType: _selectedRoom,
      );
      if (mounted && data.isNotEmpty) {
        setState(() => _projects.addAll(data));
      }
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
        title: const Text('Keşfet', style: KoalaText.h2),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.lg, vertical: KoalaSpacing.sm),
            child: TextField(
              style: KoalaText.body,
              onChanged: (v) {
                _searchQuery = v.trim();
                if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 500), () {
                  if (_searchQuery.isNotEmpty) _search(); else _load();
                });
              },
              decoration: InputDecoration(
                hintText: 'Tasarım veya tasarımcı ara...',
                hintStyle: KoalaText.hint,
                prefixIcon: const Icon(Icons.search_rounded, color: KoalaColors.textTer),
                filled: true,
                fillColor: KoalaColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KoalaRadius.xl),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.lg, vertical: KoalaSpacing.md),
              ),
            ),
          ),

          // Category chips
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.lg),
              itemCount: _rooms.length,
              separatorBuilder: (_, __) => const SizedBox(width: KoalaSpacing.sm),
              itemBuilder: (context, index) {
                final room = _rooms[index];
                final key = room['key'] as String?;
                final active = _selectedRoom == key;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedRoom = key);
                    _load();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.lg, vertical: KoalaSpacing.sm),
                    decoration: BoxDecoration(
                      color: active ? KoalaColors.accent : KoalaColors.surface,
                      borderRadius: BorderRadius.circular(KoalaRadius.pill),
                      border: Border.all(color: active ? KoalaColors.accent : KoalaColors.border),
                    ),
                    child: Center(
                      child: Text(
                        room['label'] as String,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: active ? Colors.white : KoalaColors.text,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: KoalaSpacing.md),

          // Grid
          Expanded(
            child: _loading
                ? const ShimmerGrid(itemCount: 6)
                : _hasError
                    ? ErrorState(onRetry: _load)
                    : _projects.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off_rounded, size: 48, color: KoalaColors.textTer),
                            SizedBox(height: KoalaSpacing.md),
                            Text('Bu kategoride tasarım bulunamadı', style: KoalaText.bodySec),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: KoalaColors.accent,
                        child: GridView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.lg),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: KoalaSpacing.md,
                            crossAxisSpacing: KoalaSpacing.md,
                            childAspectRatio: 0.75,
                          ),
                          itemCount: _projects.length,
                          itemBuilder: (context, index) => _ProjectCard(
                            project: _projects[index],
                            onTap: () => context.push(
                              '/project/${_projects[index]['id'] ?? index}',
                              extra: _projects[index],
                            ),
                          ),
                        ),
                      ),
          ),
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
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onTap});
  final Map<String, dynamic> project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final images = (project['designer_project_images'] as List?) ?? [];
    final imageUrl = images.isNotEmpty ? images.first['image_url'] as String? : null;
    final title = project['title'] as String? ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: KoalaDeco.cardElevated,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: KoalaColors.surfaceAlt,
                    child: imageUrl != null
                        ? Image.network(imageUrl, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.image_rounded, color: KoalaColors.textTer))
                        : const Icon(Icons.image_rounded, size: 36, color: KoalaColors.textTer),
                  ),
                  // Save button
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha:0.9),
                        shape: BoxShape.circle,
                      ),
                      child: SaveButton(
                        itemType: SavedItemType.design,
                        itemId: project['id']?.toString() ?? '',
                        title: title,
                        imageUrl: imageUrl,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.all(KoalaSpacing.sm),
              child: Text(
                title,
                style: KoalaText.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
