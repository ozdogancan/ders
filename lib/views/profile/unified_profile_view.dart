// ═══════════════════════════════════════════════════════════════════════
// UnifiedProfileView — SS5 visual pattern (avatar + name + role + stats +
// Takip et + Hakkında + Tasarımları grid) shared across:
//   • Swipe card tap → designer profile (was DesignerProfileSheet)
//   • Mini profile sheet "Profili gör"
//   • Own profile tab (ownerEditable: true)
//
// When `viewedDesignId` is non-null, the matching tile in the Tasarımları
// grid gets a subtle dark overlay (alpha 0.30) + "Bunu görüntülediniz" pill
// at the top-left of that tile.
//
// When `ownerEditable` is true and the viewer is the same user, the follow
// row is replaced by an "Profili düzenle" + "Paylaş" row, and an "AI
// Stüdyom →" pill appears above the design grid when AI designs exist.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, FileOptions;

import '../../core/theme/koala_tokens.dart';
import '../../services/designer_reviews_service.dart';
import '../../services/evlumba_live_service.dart';
import '../../services/follow_service.dart';
import '../../services/koala_seed_service.dart';
import '../../services/saved_items_service.dart';
import '../../services/shared_design_service.dart';
import '../../services/user_profile_service.dart';
import '../../widgets/free_consult_sheet.dart';
import '../../widgets/koala_ai_badge.dart';
import '../../widgets/verified_badge.dart';
import '../conversation_detail_screen.dart';
import '../share/share_upload_screen.dart' show openShareUploadSheet;
import 'follow_list_sheet.dart';
import 'pro_application_sheet.dart';
import 'profile_design_tile.dart';

class UnifiedProfileView extends StatefulWidget {
  final String profileId;
  final String? viewedDesignId;
  final bool ownerEditable;

  /// Optional override of the displayed profile (e.g. for designer cards from
  /// swipe deck where the row has already been hydrated). Falls back to a
  /// network fetch when null.
  final Map<String, dynamic>? seedProfile;

  /// Optional pre-loaded project pool — used by evlumba-design swipe deck.
  final List<Map<String, dynamic>>? seedPool;

  /// Called when the user long-presses the avatar (own profile → settings).
  final VoidCallback? onAvatarLongPress;

  /// Called when the owner taps "Profili düzenle".
  final VoidCallback? onEditProfile;

  /// Called when the owner taps the "AI Stüdyom →" pill.
  final VoidCallback? onOpenAiStudio;

  /// Called when a design tile is tapped — receives the tapped design map
  /// and the full list. If null, no-op.
  final void Function(List<Map<String, dynamic>> items, int index)? onTapDesign;

  /// Optional external scroll controller. DraggableScrollableSheet içinde
  /// açıldığında sheet'in scrollController'ı geçilir — böylece liste tepedeyken
  /// aşağı çekince sheet kapanır (drag-to-dismiss). Null ise kendi controller'ı.
  final ScrollController? scrollController;

  const UnifiedProfileView({
    super.key,
    required this.profileId,
    this.viewedDesignId,
    this.ownerEditable = false,
    this.seedProfile,
    this.seedPool,
    this.onAvatarLongPress,
    this.onEditProfile,
    this.onOpenAiStudio,
    this.onTapDesign,
    this.scrollController,
  });

  @override
  State<UnifiedProfileView> createState() => _UnifiedProfileViewState();
}

class _UnifiedProfileViewState extends State<UnifiedProfileView> {
  KoalaUserProfile? _profile;
  Map<String, dynamic>? _designerRow; // From profiles table (designers)
  /// Server-side toplam tasarım sayısı (count exact). Header için "N adet"
  /// göstermek için doğrudan kullanılır.
  int? _designTotalCount;
  /// AI tasarımları (owner-only) — ayrı sekmede yüklenir.
  bool _hasAnyAi = false;
  bool _loading = true;

  FollowState _follow = FollowState.empty;
  bool _followBusy = false;
  ({int followers, int following}) _counts = (followers: 0, following: 0);

  DesignerReviewsResult _reviews = DesignerReviewsResult.empty;

  // FIX 2 (2026-05-28): Own profile role view ('homeowner' | 'pro').
  // Only meaningful when user is Pro — the segmented switch lets them flip
  // their public face. Persisted via SharedPreferences.
  static const String _kRoleSwitchPrefKey = 'profile_role_view';
  String _viewRole = 'homeowner';
  // 2026-06-02: Kullanıcı rolü elle seçti mi? Seçmediyse Pro kullanıcı kendi
  // profilinde VARSAYILAN olarak 'pro' görünümde açılır.
  bool _roleExplicitlySet = false;

  // Profesyonel başvuru durumu (own profile). 'pending' iken tekrar başvuru
  // alınmaz — "Profesyonel başvurunuz incelenmekte" gösterilir.
  ProApplicationStatus _proApp = ProApplicationStatus.none;

  // ─── Design grid state (CustomScrollView + SliverGrid) ─────────────────
  // KRİTİK MIMARI: GridView.shrinkWrap'i ListView'ün içine sarmak iç içe
  // viewport hatası verdiği için 2026-05-28'de proper Slivers'a geçildi.
  // Dışarıdan (sheet) verilen controller varsa onu kullan — drag-to-dismiss.
  late final ScrollController _scrollCtrl =
      widget.scrollController ?? ScrollController();
  final List<Map<String, dynamic>> _loadedDesigns = <Map<String, dynamic>>[];
  dynamic _designsCursor;
  // _loadProfile()'in paylaşılan future'ı — _designerRow set edilmeden grid
  // fetch'i branch kararı veremez (designer'lar yanlışlıkla "civil kullanıcı"
  // dalına düşüp boş dönüyordu). _loadInitialDesigns bunu bekler.
  Future<void>? _profileReady;
  bool _loadingInitialDesigns = true;
  bool _loadingMoreDesigns = false;
  bool _hasMoreDesigns = true;

  // ─── Kategori filtresi (popup grid) ────────────────────────────────────
  // null = "Tümü". Yüklenmiş tasarımlardan türetilen kompakt pill row ile
  // grid client-side filtrelenir. Sayfalama devam ettikçe yeni kategoriler
  // pill row'a eklenir.
  String? _categoryFilter;

  /// Yüklü tasarımlardan benzersiz kategori etiketleri (görünme sırasıyla).
  List<String> get _availableCategories {
    final seen = <String>{};
    final out = <String>[];
    for (final p in _loadedDesigns) {
      final label = _categoryLabel(p);
      if (label.isEmpty || seen.contains(label)) continue;
      seen.add(label);
      out.add(label);
    }
    return out;
  }

  /// Aktif filtreye göre grid'de gösterilecek tasarımlar.
  List<Map<String, dynamic>> get _visibleDesigns {
    final f = _categoryFilter;
    if (f == null) return _loadedDesigns;
    return _loadedDesigns
        .where((p) => _categoryLabel(p) == f)
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _restoreRole();
    // seedProfile varsa _designerRow'u SENKRON kur — branch kararı (designer
    // vs civil kullanıcı) ilk frame'de doğru olsun.
    if (widget.seedProfile != null) {
      _designerRow = Map<String, dynamic>.from(widget.seedProfile!);
    }
    // _loadProfile'ı bir kez başlat, future'ı paylaş. _loadAll ve
    // _loadInitialDesigns ikisi de aynı future'ı bekler — çift fetch yok.
    _profileReady = _loadProfile();
    _loadAll();
    _loadInitialDesigns();
    _loadProApplication();
  }

  /// Own profile: en son profesyonel başvuru durumunu çek. 'pending' ise
  /// CTA yerine "incelenmekte" rozeti gösterilir.
  Future<void> _loadProApplication() async {
    if (!widget.ownerEditable) return;
    if (_currentUid == null || _currentUid != widget.profileId) return;
    final status = await UserProfileService.latestApplication();
    if (mounted) setState(() => _proApp = status);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    // Sadece kendi oluşturduğumuz controller'ı dispose et — sheet'inki değil.
    if (widget.scrollController == null) _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitialDesigns() async {
    try {
      // _designerRow çözülmeden branch seçilmesin (designer→boş grid bug'ı).
      await _profileReady;
      final page = await _fetchDesignsPage(null);
      if (!mounted) return;
      final seen = <String>{};
      final fresh = <Map<String, dynamic>>[];
      for (final m in page.items) {
        final id =
            (m['id'] ?? m['item_id'] ?? m['cover_image_url'] ?? '').toString();
        if (id.isEmpty || seen.contains(id)) continue;
        seen.add(id);
        fresh.add(m);
      }
      setState(() {
        _loadedDesigns
          ..clear()
          ..addAll(fresh);
        _reorderViewedFirst();
        _designsCursor = page.cursor;
        _hasMoreDesigns = page.hasMore;
        _loadingInitialDesigns = false;
      });
      debugPrint(
          '[profile-grid] fetch initial returned ${page.items.length} hasMore=${page.hasMore}');
    } catch (e) {
      debugPrint('[profile-grid] initial load failed: $e');
      if (!mounted) return;
      setState(() {
        _loadingInitialDesigns = false;
        _hasMoreDesigns = false;
      });
    }
  }

  /// Swipe'tan açıldıysa, görüntülenen tasarımı grid'in başına taşır —
  /// kullanıcı geldiği kartı ilk sırada görür ("Bunu görüntülediniz").
  void _reorderViewedFirst() {
    final vid = widget.viewedDesignId;
    if (vid == null || vid.isEmpty) return;
    final i = _loadedDesigns.indexWhere((m) =>
        (m['id'] ?? m['item_id'] ?? '').toString() == vid);
    if (i > 0) {
      final item = _loadedDesigns.removeAt(i);
      _loadedDesigns.insert(0, item);
    }
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.maxScrollExtent - pos.pixels <= 320 &&
        !_loadingMoreDesigns &&
        _hasMoreDesigns) {
      _loadMoreDesigns();
    }
  }

  Future<void> _loadMoreDesigns() async {
    if (_loadingMoreDesigns || !_hasMoreDesigns) return;
    setState(() => _loadingMoreDesigns = true);
    try {
      final page = await _fetchDesignsPage(_designsCursor);
      if (!mounted) return;
      final seen = <String>{
        for (final m in _loadedDesigns)
          (m['id'] ?? m['item_id'] ?? m['cover_image_url'] ?? '').toString()
      };
      final fresh = <Map<String, dynamic>>[];
      for (final m in page.items) {
        final id =
            (m['id'] ?? m['item_id'] ?? m['cover_image_url'] ?? '').toString();
        if (id.isEmpty || seen.contains(id)) continue;
        seen.add(id);
        fresh.add(m);
      }
      setState(() {
        _loadedDesigns.addAll(fresh);
        _reorderViewedFirst();
        _designsCursor = page.cursor;
        _hasMoreDesigns = page.hasMore;
        _loadingMoreDesigns = false;
      });
      debugPrint(
          '[profile-grid] fetch more returned ${page.items.length} hasMore=${page.hasMore}');
    } catch (e) {
      debugPrint('[profile-grid] load more failed: $e');
      if (!mounted) return;
      setState(() {
        _loadingMoreDesigns = false;
        _hasMoreDesigns = false;
      });
    }
  }

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  bool get _isSelf => _currentUid != null && _currentUid == widget.profileId;

  /// FIX 4 (2026-05-28): own profile renders premium 2-col grid (large
  /// tiles, portrait aspect), other profiles keep the compact 3-col grid.
  bool get _isOwnGrid => widget.ownerEditable && _isSelf;
  // Tüm profillerde (popup dahil) tasarım grid'i 2 kolon, kişinin kendi
  // profilindeki premium görünümle aynı.
  int get _gridCols => 2;

  Future<void> _loadAll() async {
    // PART B — `koala_profile_bundle` ile counts + reviews tek RPC'de.
    // Follow state + profile + ai-presence hâlâ ayrı. RPC fail → fallback.
    try {
      final bundle = await UserProfileService.loadBundle(widget.profileId);
      if (bundle != null) {
        final results = await Future.wait([
          _profileReady ?? _loadProfile(),
          _preloadAiPresence(),
          FollowService.stateFor(widget.profileId),
        ], eagerError: false);
        if (!mounted) return;
        setState(() {
          _counts =
              (followers: bundle.followers, following: bundle.following);
          _follow = results[2] as FollowState;
          _reviews = bundle.reviewsCount > 0
              ? DesignerReviewsResult(
                  reviews: bundle.reviewsLatest
                      .map((m) => DesignerReview(
                            id: (m['id'] ?? '').toString(),
                            designerId: widget.profileId,
                            reviewerId: (m['user_id'] ?? '').toString(),
                            rating: (m['rating'] as num?)?.toInt() ?? 0,
                            comment: m['comment']?.toString(),
                            createdAt: DateTime.tryParse(
                                    (m['created_at'] ?? '').toString()) ??
                                DateTime.now(),
                          ))
                      .toList(),
                  avg: bundle.reviewsAvgRating ?? 0.0,
                  count: bundle.reviewsCount,
                )
              : DesignerReviewsResult.empty;
          _loading = false;
        });
        unawaited(_loadDesignTotal());
        return;
      }
    } catch (e) {
      debugPrint('[unified_profile] bundle fallback: $e');
    }
    // ─── Fallback: orijinal 5-parallel path ───
    final results = await Future.wait([
      _profileReady ?? _loadProfile(),
      _preloadAiPresence(),
      FollowService.counts(widget.profileId),
      FollowService.stateFor(widget.profileId),
      DesignerReviewsService.getForDesigner(widget.profileId),
    ], eagerError: false);
    if (!mounted) return;
    setState(() {
      _counts = results[2] as ({int followers, int following});
      _follow = results[3] as FollowState;
      _reviews = results[4] as DesignerReviewsResult;
      _loading = false;
    });
    unawaited(_loadDesignTotal());
  }

  /// Sadece owner için: AI Stüdyom pill'ini göstermek için bir tane olsun yeter.
  Future<void> _preloadAiPresence() async {
    if (!(widget.ownerEditable && _isSelf)) return;
    try {
      final page = await SavedItemsService.getByTypePaged(
        SavedItemType.project,
        limit: 1,
      );
      _hasAnyAi = page.items.isNotEmpty;
    } catch (_) {
      _hasAnyAi = false;
    }
  }

  /// Designs section'ı için server-side exact total — header'da "N adet"
  /// göstermek için. Best-effort, fail durumunda null bırakılır ve fallback
  /// "_designCountSeen" değeri kullanılır.
  Future<void> _loadDesignTotal() async {
    try {
      if (widget.profileId == KoalaSeedService.evlumbaDesignerId) {
        final c = await KoalaSeedService.evlumbaCardsTotalCount();
        if (mounted) setState(() => _designTotalCount = c);
        return;
      }
      if (widget.ownerEditable && _isSelf) {
        final results = await Future.wait([
          SharedDesignService.totalCount(),
          SavedItemsService.totalCountForType(SavedItemType.project),
        ]);
        if (mounted) {
          setState(() => _designTotalCount = results[0] + results[1]);
        }
        return;
      }
      // Other user / designer — public only.
      final results = await Future.wait([
        SharedDesignService.totalCount(ownerUid: widget.profileId),
        SavedItemsService.totalCountForType(
          SavedItemType.project,
          ownerUid: widget.profileId,
          publicOnly: true,
        ),
        // Evlumba marketplace tasarımcılarının projeleri ayrı DB'de —
        // Koala SharedDesignService 0 döner. Evlumba sayısını da ekle.
        EvlumbaLiveService.designerProjectsCount(widget.profileId),
      ]);
      if (mounted) {
        setState(() =>
            _designTotalCount = results[0] + results[1] + results[2]);
      }
    } catch (e) {
      debugPrint('[unified_profile] design total count failed: $e');
    }
  }

  Future<void> _loadProfile() async {
    // Try koala_user_profiles first; designers also have a row in `profiles`.
    try {
      final ups = await UserProfileService.getMany([widget.profileId]);
      if (ups.isNotEmpty) {
        _profile = ups.first;
      } else {
        _profile = KoalaUserProfile(uid: widget.profileId);
      }
    } catch (_) {
      _profile = KoalaUserProfile(uid: widget.profileId);
    }
    // 2026-06-02: Profesyonel kullanıcı kendi profilinde VARSAYILAN olarak
    // "profesyonel" görünümde gelsin (elle başka seçim yapmadıysa).
    if (widget.ownerEditable &&
        _profile?.isPro == true &&
        !_roleExplicitlySet) {
      _viewRole = 'pro';
    }
    // Designer row (profiles) — best-effort; richer fields than koala_user_profiles.
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select(
              'id, full_name, business_name, avatar_url, profession, specialty, city, bio, about')
          .eq('id', widget.profileId)
          .maybeSingle();
      if (row != null) _designerRow = Map<String, dynamic>.from(row);
    } catch (_) {/* swallow */}

    // Evlumba fallback — `profiles` Koala DB'de yoksa Evlumba marketplace
    // DB'sinden bilgileri çek. evlumba-design + diğer Evlumba designer'ları
    // için bio/about + avatar tarafından hidrasyon.
    if (_designerRow == null ||
        widget.profileId == 'evlumba-design' ||
        ((_designerRow?['bio'] ?? '').toString().trim().isEmpty &&
            (_designerRow?['about'] ?? '').toString().trim().isEmpty)) {
      try {
        final ev = await EvlumbaLiveService.getDesigner(widget.profileId);
        if (ev != null) {
          final merged = <String, dynamic>{
            ...(ev),
            if (_designerRow != null) ..._designerRow!,
          };
          // Eğer Koala row bio boşsa Evlumba bio'yu üstüne yaz.
          if (((merged['bio'] ?? '').toString().trim().isEmpty) &&
              ((ev['bio'] ?? '').toString().trim().isNotEmpty)) {
            merged['bio'] = ev['bio'];
          }
          if (((merged['about'] ?? '').toString().trim().isEmpty) &&
              ((ev['about'] ?? '').toString().trim().isNotEmpty)) {
            merged['about'] = ev['about'];
          }
          _designerRow = merged;
        }
      } catch (e) {
        debugPrint('[unified_profile] evlumba fallback failed: $e');
      }
    }

    // Override with seed if provided.
    if (widget.seedProfile != null) {
      _designerRow ??= Map<String, dynamic>.from(widget.seedProfile!);
    }
  }

  /// Tasarım gridini besleyen tek fetch fonksiyonu. Owner için
  /// (paylaşımlar+AI birleştirilmiş) sırayla shared sayfası, sonra AI sayfası
  /// yüklenir. Other-user / designer için sadece designer_projects (ya da
  /// evlumba seed) yüklenir.
  ///
  /// Cursor şekli: Map { 'phase': 'shared'|'ai'|'designer', 'cursor': String? }
  /// — owner two-source paginate edilebilmesi için. Diğer durumda phase yok,
  /// cursor düz String?.
  Future<({List<Map<String, dynamic>> items, bool hasMore, dynamic cursor})>
      _fetchDesignsPage(dynamic cursor) async {
    try {
      if (widget.ownerEditable && _isSelf) {
        debugPrint('[profile-grid] fetch self cursor=$cursor hasAnyAi=$_hasAnyAi');
        // Owner two-phase: önce shared, bittiğinde AI.
        // BUG FIX (2026-05-28): shared page bombası empty olunca LazyGridView
        // fresh.isEmpty → _hasMore=false yapıyordu ve AI fazına HİÇ geçilmiyordu.
        // Çözüm: shared empty + !hasMore ise burada hemen AI fazına geç ve
        // ilk AI sayfasını döndür.
        final state = (cursor is Map)
            ? Map<String, dynamic>.from(cursor)
            : <String, dynamic>{'phase': 'shared', 'cursor': null};
        var phase = (state['phase'] ?? 'shared').toString();
        var c = state['cursor'] as String?;

        if (phase == 'shared') {
          final page = await SharedDesignService.mySharedPaged(
            limit: 18,
            beforeCreatedAt: c,
          );
          final items = page.items
              .map((s) => {...s.toMapForProfileTab(), 'is_ai': false})
              .toList();
          if (items.isEmpty && !page.hasMore) {
            // Shared yok → direkt AI fazına geç ve AI ilk sayfasını dön.
            phase = 'ai';
            c = null;
            debugPrint(
                '[profile-grid] shared empty, jumping to ai phase');
            final aiPage = await SavedItemsService.getByTypePaged(
              SavedItemType.project,
              limit: 18,
              beforeCreatedAt: c,
            );
            final aiItems =
                aiPage.items.map((m) => {...m, 'is_ai': true}).toList();
            return (
              items: aiItems,
              hasMore: aiPage.hasMore,
              cursor: {'phase': 'ai', 'cursor': aiPage.cursor},
            );
          }
          // Shared bittiğinde phase'i 'ai'ye geçir, cursor'u null'la sıfırla.
          final nextCursor = page.hasMore
              ? {'phase': 'shared', 'cursor': page.cursor}
              : {'phase': 'ai', 'cursor': null};
          // hasMore: shared'da daha varsa true; yoksa AI varlığına bak.
          final hasMore = page.hasMore || _hasAnyAi;
          return (items: items, hasMore: hasMore, cursor: nextCursor);
        } else {
          // AI phase
          final page = await SavedItemsService.getByTypePaged(
            SavedItemType.project,
            limit: 18,
            beforeCreatedAt: c,
          );
          final items = page.items
              .map((m) => {...m, 'is_ai': true})
              .toList();
          return (
            items: items,
            hasMore: page.hasMore,
            cursor: {'phase': 'ai', 'cursor': page.cursor},
          );
        }
      }

      // Other user — Evlumba synthetic
      if (widget.profileId == KoalaSeedService.evlumbaDesignerId) {
        // Swipe ekranı seed havuzunu geçtiyse doğrudan onu kullan — ağ turu
        // YOK (anında açılır) + kart id'leri swipe'taki ile birebir aynı, bu
        // sayede "Bunu görüntülediniz" + ilk-sıra reorder evlumba'da da çalışır.
        final sp = widget.seedPool;
        if (sp != null && sp.isNotEmpty && cursor == null) {
          debugPrint('[profile-grid] evlumba from seedPool (${sp.length})');
          return (
            items: List<Map<String, dynamic>>.from(sp),
            hasMore: false,
            cursor: null,
          );
        }
        debugPrint('[profile-grid] fetch evlumba cursor=$cursor');
        final page = await KoalaSeedService.evlumbaCardsPaged(
          limit: 18,
          beforeCreatedAt: cursor as String?,
        );
        return (
          items: page.items,
          hasMore: page.hasMore,
          cursor: page.cursor,
        );
      }

      // Other user (not designer) — public shared_designs + public AI projects.
      // _designerRow null ise civil kullanıcı profili.
      if (_designerRow == null) {
        debugPrint(
            '[profile-grid] fetch other-user public cursor=$cursor uid=${widget.profileId}');
        // Tek fazlı: shared_designs (status=published) — AI public yoksa boş.
        final state = (cursor is Map)
            ? Map<String, dynamic>.from(cursor)
            : <String, dynamic>{'phase': 'shared', 'cursor': null};
        final phase = (state['phase'] ?? 'shared').toString();
        final c = state['cursor'] as String?;
        if (phase == 'shared') {
          final page = await SharedDesignService.publicByUidPaged(
            widget.profileId,
            limit: 18,
            beforeCreatedAt: c,
          );
          final items = page.items
              .map((s) => {...s.toMapForProfileTab(), 'is_ai': false})
              .toList();
          if (items.isEmpty && !page.hasMore) {
            // Direkt AI public fazına geç.
            final aiPage = await SavedItemsService.getByTypePaged(
              SavedItemType.project,
              limit: 18,
              ownerUid: widget.profileId,
              publicOnly: true,
            );
            final aiItems =
                aiPage.items.map((m) => {...m, 'is_ai': true}).toList();
            return (
              items: aiItems,
              hasMore: aiPage.hasMore,
              cursor: {'phase': 'ai', 'cursor': aiPage.cursor},
            );
          }
          return (
            items: items,
            hasMore: page.hasMore || true,
            cursor: page.hasMore
                ? {'phase': 'shared', 'cursor': page.cursor}
                : {'phase': 'ai', 'cursor': null},
          );
        } else {
          final aiPage = await SavedItemsService.getByTypePaged(
            SavedItemType.project,
            limit: 18,
            beforeCreatedAt: c,
            ownerUid: widget.profileId,
            publicOnly: true,
          );
          final aiItems =
              aiPage.items.map((m) => {...m, 'is_ai': true}).toList();
          return (
            items: aiItems,
            hasMore: aiPage.hasMore,
            cursor: {'phase': 'ai', 'cursor': aiPage.cursor},
          );
        }
      }

      // Other designer
      debugPrint('[profile-grid] fetch designer cursor=$cursor uid=${widget.profileId}');
      final page = await EvlumbaLiveService.getDesignerProjectsPaged(
        widget.profileId,
        limit: 18,
        beforeCreatedAt: cursor as String?,
      );
      return (
        items: page.items,
        hasMore: page.hasMore,
        cursor: page.cursor,
      );
    } catch (e) {
      debugPrint('[unified_profile] designs page fetch failed: $e');
      return (items: <Map<String, dynamic>>[], hasMore: false, cursor: null);
    }
  }

  Future<void> _restoreRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final r = prefs.getString(_kRoleSwitchPrefKey);
      if (r != null) {
        _roleExplicitlySet = true;
        if (mounted) setState(() => _viewRole = r);
      }
    } catch (_) {/* swallow */}
  }

  Future<void> _saveRole(String role) async {
    HapticFeedback.selectionClick();
    _roleExplicitlySet = true;
    if (mounted) setState(() => _viewRole = role);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRoleSwitchPrefKey, role);
    } catch (_) {/* swallow */}
  }

  Future<void> _openProApplication() async {
    // Zaten beklemede bir başvuru varsa tekrar açma — tek başvuru hakkı.
    if (_proApp.isPending) return;
    HapticFeedback.selectionClick();
    final submitted = await showProApplicationSheet(context);
    if (submitted == true && mounted) {
      // Backend kaydı işlenene kadar UI'ı iyimser şekilde 'pending'e çek.
      setState(() => _proApp = const ProApplicationStatus(status: 'pending'));
      _loadProApplication();
    }
  }

  Future<void> _onFollowTap() async {
    if (_followBusy) return;
    HapticFeedback.selectionClick();
    setState(() => _followBusy = true);
    final next = await FollowService.toggle(widget.profileId);
    if (!mounted) return;
    setState(() {
      _follow = next;
      _followBusy = false;
    });
  }

  Future<void> _onReviewSubmit(int rating, String comment) async {
    if (_isSelf) return;
    final ok = await DesignerReviewsService.submit(
      designerId: widget.profileId,
      rating: rating,
      comment: comment.isEmpty ? null : comment,
    );
    if (!mounted) return;
    if (ok) {
      // Optimistic insert.
      final uid = _currentUid ?? '';
      final stub = DesignerReview(
        id: 'local-${DateTime.now().millisecondsSinceEpoch}',
        designerId: widget.profileId,
        reviewerId: uid,
        rating: rating,
        comment: comment.isEmpty ? null : comment,
        createdAt: DateTime.now(),
      );
      final updated = [stub, ..._reviews.reviews];
      final sum = updated.fold<int>(0, (a, r) => a + r.rating);
      setState(() {
        _reviews = DesignerReviewsResult(
          reviews: updated,
          avg: sum / updated.length,
          count: updated.length,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Yorumun alındı, teşekkürler 🙌'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yorum gönderilemedi, tekrar dene.')),
      );
    }
  }

  // ─── Derived fields ───
  String get _name {
    final p = _profile;
    final d = _designerRow;
    final stored = (p?.displayName ?? '').trim();
    if (stored.isNotEmpty) return stored;
    final n =
        ((d?['full_name'] ?? d?['business_name'] ?? '') as String).trim();
    if (n.isNotEmpty) return n;
    // Evlumba resmî stüdyo — profil koala_user_profiles'ta yok, isim sabit.
    if (widget.profileId == KoalaSeedService.evlumbaDesignerId) {
      return 'Evlumba Design';
    }
    // FIX 1 (2026-05-28): own profile fallback — auth displayName → email prefix.
    if (_isSelf) {
      final auth = FirebaseAuth.instance.currentUser;
      final authName = (auth?.displayName ?? '').trim();
      if (authName.isNotEmpty) return authName;
      final email = (auth?.email ?? '').trim();
      if (email.isNotEmpty && email.contains('@')) {
        final prefix = email.split('@').first.trim();
        if (prefix.isNotEmpty) return prefix;
      }
    }
    return 'Profil';
  }

  String get _avatarUrl {
    // Own profile: FirebaseAuth.photoURL en taze kaynak — settings'ten avatar
    // upload edildikten sonra koala_user_profiles row'u henüz invalidate
    // edilmemiş olabilir, ama auth photoURL anında güncellenir.
    if (_isSelf) {
      final authPhoto =
          (FirebaseAuth.instance.currentUser?.photoURL ?? '').trim();
      if (authPhoto.isNotEmpty) return authPhoto;
    }
    final fromProfile = (_profile?.avatarUrl ?? '').trim();
    if (fromProfile.isNotEmpty) return fromProfile;
    return ((_designerRow?['avatar_url'] ?? '') as String).trim();
  }

  String get _about {
    final fromProfile = (_profile?.about ?? '').trim();
    if (fromProfile.isNotEmpty) return fromProfile;
    final d = _designerRow;
    final fromRow = ((d?['bio'] ?? d?['about'] ?? '') as String).trim();
    if (fromRow.isNotEmpty) return fromRow;
    // FIX 4: Evlumba için hardcoded fallback — profiles tablosunda bio yok.
    if (widget.profileId == KoalaSeedService.evlumbaDesignerId) {
      return 'Evlumba Design, modern ve fonksiyonel iç mekan tasarımları sunan '
          'genç bir stüdyo. Her projeyi yaşam tarzınıza ve mekânınızın ruhuna '
          'göre kişiselleştiriyor. Salon, yatak odası, mutfak ve çocuk odası '
          'dönüşümlerinde 200+ projeyi tamamladık. İlk danışma her zaman '
          'ücretsiz — bir fikirle gel, hayalini birlikte gerçekleştirelim.';
    }
    return '';
  }

  String get _role {
    final d = _designerRow;
    final prof =
        ((d?['profession'] ?? d?['specialty'] ?? '') as String).trim();
    if (prof.isNotEmpty) return prof;
    if (widget.profileId == KoalaSeedService.evlumbaDesignerId) {
      return 'İç Mimari Stüdyosu';
    }
    // 2026-06-02: Pro kullanıcı için başvuruda girilen mesleği göster
    // (örn. "İç Mimar"); yoksa jenerik "Profesyonel Tasarımcı". Deneyim yılı
    // gibi parantez/virgül/tire içindeki ekleri ("(3 yıl deneyim)") gösterme —
    // sadece meslek adı kalsın.
    if (_profile?.isPro == true) {
      var p = (_profile?.profession ?? '').trim();
      if (p.isNotEmpty) {
        p = p.replaceAll(RegExp(r'\s*\(.*?\)'), '');
        p = p.split(RegExp(r'\s*[,\-–—]\s*')).first.trim();
      }
      return p.isNotEmpty ? p : 'Profesyonel Tasarımcı';
    }
    // "Ev Sahibi" etiketi YALNIZCA kullanıcının KENDİ profili için. Başka
    // birinin (tasarımcı) profilini açarken yanlışlıkla "Ev Sahibi" yazma.
    if (!_isSelf) return _designerRow != null ? 'Tasarımcı' : '';
    return 'Ev Sahibi';
  }

  String get _city => ((_designerRow?['city'] ?? '') as String).trim();

  bool get _isDesignerOrPro =>
      _designerRow != null || (_profile?.isPro == true);

  // ignore: unused_element
  bool get _hasAiDesigns => _hasAnyAi;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(
              color: KoalaColors.accentDeep, strokeWidth: 2),
        ),
      );
    }
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom;
    // 2026-06-02 FIX: Profil sekmesinde (sheet DEĞİL → scrollController == null)
    // body, extendBody:true KoalaBottomNav'ın (yükseklik 64) arkasına uzuyor;
    // son tasarım navbar'ın altında kalıyordu. Sekmede navbar yüksekliği kadar
    // ek boşluk bırak. Popup/sheet kullanımında (scrollController != null) navbar
    // olmadığı için ek boşluğa gerek yok.
    final navReserve = widget.scrollController == null ? 64.0 : 0.0;
    debugPrint(
        '[profile-grid] sliver build items=${_loadedDesigns.length} loadingInit=$_loadingInitialDesigns loadingMore=$_loadingMoreDesigns hasMore=$_hasMoreDesigns');
    // 2026-06-01: Mor (purple) gradient kaldırıldı (kullanıcı direktifi) —
    // popup düz `bg` zemin. Rounded-top için ClipRRect korunuyor.
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: DecoratedBox(
      decoration: const BoxDecoration(color: KoalaColors.bg),
      child: CustomScrollView(
        controller: _scrollCtrl,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(child: _hero()),
          SliverToBoxAdapter(child: _stats()),
          SliverToBoxAdapter(child: _actionsRow()),
          if (_about.isNotEmpty) SliverToBoxAdapter(child: _aboutSection()),
          // 2026-05-28 FIX 2: Reviews INLINE'dan kaldırıldı — sadece
          // "Değerlendirme" stat tap'iyle açılan bottom sheet'te gösteriliyor.
          // 2026-05-28: SPEC 12 — AI Stüdyom pill kaldırıldı. AI tasarımlar
          // doğrudan birleşik grid'te listeleniyor, tile'da küçük "AI" rozeti.
          SliverToBoxAdapter(child: _projectsHeader()),
          ..._buildDesignsSlivers(),
          SliverToBoxAdapter(
              child: SizedBox(height: bottomPad + navReserve + 32)),
        ],
      ),
      ),
    );
  }

  /// CRITICAL fix — true SliverGrid (NOT GridView wrapped in shrinkWrap).
  /// Loading / empty / grid + (optional) loadingMore / endcap slivers.
  List<Widget> _buildDesignsSlivers() {
    if (_loadingInitialDesigns) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: CircularProgressIndicator(
                color: KoalaColors.accentDeep,
                strokeWidth: 2,
              ),
            ),
          ),
        ),
      ];
    }
    if (_loadedDesigns.isEmpty) {
      return [SliverToBoxAdapter(child: _emptyDesignsState())];
    }
    final visible = _visibleDesigns;
    // Tüm profillerde premium grid: 2-col, portrait, 12px gaps, 16h padding.
    final out = <Widget>[
      if (_availableCategories.length >= 2)
        SliverToBoxAdapter(child: _categoryFilterRow()),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid(
          // 2026-06-02: Tile ebatı ORİJİNALE döndürüldü (kullanıcı isteği —
          // popup görsel boyutu değişmesin). 0.78 portre.
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _gridCols,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.78,
          ),
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => _designTile(visible, i),
            childCount: visible.length,
          ),
        ),
      ),
    ];
    if (_loadingMoreDesigns) {
      out.add(const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: KoalaColors.accentDeep,
                strokeWidth: 2,
              ),
            ),
          ),
        ),
      ));
    } else if (!_hasMoreDesigns &&
        _loadedDesigns.isNotEmpty &&
        !(widget.ownerEditable && _isSelf)) {
      out.add(const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 22),
          child: Center(
            child: Text(
              'Hepsi bu kadar 🐨',
              style: KoalaText.labelSmall,
            ),
          ),
        ),
      ));
    }
    return out;
  }

  Widget _emptyDesignsState() {
    if (widget.ownerEditable && _isSelf) {
      // FIX 6 (2026-05-28): emotional empty state — large illustration +
      // headline + CTA. WHOLE block tappable → opens share modal sheet.
      return _OwnEmptyShareCta(
        onTap: () async {
          HapticFeedback.selectionClick();
          await openShareUploadSheet(context);
        },
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      child: Center(
        child: Text(
          'Henüz yayınlanmış tasarım yok.',
          style: KoalaText.bodySec,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  // ─── Hero — SS5 ─────────────────────────────────────────────────────
  Widget _hero() {
    final isEvlumba = widget.profileId == 'evlumba-design';
    // FIX 5: Hero gradient bottom sheet rounded-top'ı respect etsin diye
    // ClipRRect ile saralım. ProfileTab dışında her zaman bottom-sheet
    // konteynerinde açılıyor (radius 24-28).
    // 2026-05-28 FIX 1: Hero gradient'i kuvvetlendir — popup'ın rounded
    // top'una yapışmış kalın bir lavender blok hissi. Solid stop bandı
    // (0..0.55) sonra bg'ye yumuşak geçiş.
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Container(
      width: double.infinity,
      // 2026-06-02: Header'ı sıkılaştır — tasarım grid'i fold'a daha yakın
      // gelsin (kullanıcı: "1 tasarım görünüyor"). Tile ebadına dokunulmadı.
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      // Mor/lavender hero gradient kaldırıldı — düz bg, temiz görünüm.
      decoration: const BoxDecoration(color: KoalaColors.bg),
      child: Column(
        children: [
          _avatar(isEvlumba),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _name,
                  style: KoalaText.h2,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isVerifiedDesignerId(widget.profileId) ||
                  _profile?.verified == true) ...[
                const SizedBox(width: 6),
                const VerifiedBadge(size: 18),
              ],
              // 2026-06-02: İsmin yanındaki "Pro" pill KALDIRILDI (kullanıcı
              // isteği). Profesyonellik alt başlıktaki meslek + verified rozeti
              // ile zaten belli; ayrıca "Pro" yazmaya gerek yok.
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [_role, if (_city.isNotEmpty) _city]
                .where((s) => s.isNotEmpty)
                .join(' · '),
            style: KoalaText.bodySec,
            textAlign: TextAlign.center,
          ),
          // FIX 2 (2026-05-28): Own profile — Pro CTA pill OR role switch.
          if (widget.ownerEditable && _isSelf) ...[
            const SizedBox(height: 10),
            _profile?.isPro == true
                ? _RoleSegmentedSwitch(
                    current: _viewRole,
                    onChange: _saveRole,
                  )
                : (_proApp.isPending
                    ? const _ProPendingPill()
                    : _ProUpsellPill(onTap: _openProApplication)),
          ],
        ],
      ),
    ),
    );
  }

  Widget _avatar(bool isEvlumba) {
    final url = _avatarUrl;
    final hasUrl = url.isNotEmpty;
    final canEdit = widget.ownerEditable && _isSelf;
    final inner = Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isEvlumba
            ? const SweepGradient(
                colors: [
                  KoalaColors.accentDeep,
                  KoalaColors.brandLight,
                  Color(0xFFFFC44C),
                  KoalaColors.accent,
                  KoalaColors.accentDeep,
                ],
              )
            : null,
        color: isEvlumba ? null : Colors.transparent,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: EdgeInsets.all(isEvlumba ? 3 : 0),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hasUrl ? Colors.white : KoalaColors.accentSoft,
        ),
        clipBehavior: Clip.antiAlias,
        child: hasUrl
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, _) =>
                    Container(color: KoalaColors.accentSoft),
                errorWidget: (_, _, _) => const Center(
                    child: Icon(LucideIcons.user,
                        size: 36, color: KoalaColors.accentDeep)),
              )
            : const Center(
                child: Icon(LucideIcons.user,
                    size: 36, color: KoalaColors.accentDeep),
              ),
      ),
    );

    // Own profile: avatar tappable → foto değiştir; sağ-alt kamera rozeti +
    // upload sırasında spinner overlay. onLongPress (ayarlar) korunur.
    if (canEdit) {
      return GestureDetector(
        onTap: _uploadingAvatar ? null : _openAvatarActions,
        onLongPress: widget.onAvatarLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                widget.onAvatarLongPress!();
              },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            inner,
            if (_uploadingAvatar)
              Positioned.fill(
                child: ClipOval(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.35),
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.4),
                    ),
                  ),
                ),
              )
            else
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KoalaColors.accentDeep,
                    border:
                        Border.all(color: KoalaColors.bg, width: 2.5),
                  ),
                  child: const Icon(LucideIcons.camera,
                      size: 14, color: Colors.white),
                ),
              ),
          ],
        ),
      );
    }

    if (widget.onAvatarLongPress == null) return inner;
    return GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
        widget.onAvatarLongPress!();
      },
      child: inner,
    );
  }

  // ─── Profil fotoğrafı upload/remove (own profile) ──────────────────────
  bool _uploadingAvatar = false;

  Future<void> _openAvatarActions() async {
    if (_uploadingAvatar) return;
    HapticFeedback.selectionClick();
    final hasPhoto = _avatarUrl.isNotEmpty;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: KoalaColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: KoalaColors.border,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const SizedBox(height: 10),
            if (!kIsWeb)
              ListTile(
                leading: const Icon(LucideIcons.camera,
                    color: KoalaColors.accentDeep),
                title: const Text('Fotoğraf çek'),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
            ListTile(
              leading:
                  const Icon(LucideIcons.image, color: KoalaColors.accentDeep),
              title: const Text('Galeriden seç'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(LucideIcons.trash2,
                    color: KoalaColors.error),
                title: const Text('Mevcut fotoğrafı kaldır',
                    style: TextStyle(color: KoalaColors.error)),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            ListTile(
              leading: const Icon(LucideIcons.x, color: KoalaColors.textSec),
              title: const Text('İptal'),
              onTap: () => Navigator.pop(ctx),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'camera':
        await _pickAndUploadAvatar(ImageSource.camera);
        break;
      case 'gallery':
        await _pickAndUploadAvatar(ImageSource.gallery);
        break;
      case 'remove':
        await _confirmRemoveAvatar();
        break;
    }
  }

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 720,
        imageQuality: 80,
      );
      if (picked == null || !mounted) return;
      setState(() => _uploadingAvatar = true);
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('not_authenticated');
      final Uint8List bytes = await picked.readAsBytes();
      final objectPath = '$uid/avatar.webp';
      final storage = Supabase.instance.client.storage.from('avatars');
      await storage.uploadBinary(
        objectPath,
        bytes,
        fileOptions: const FileOptions(
          upsert: true,
          contentType: 'image/webp',
        ),
      );
      final v = DateTime.now().millisecondsSinceEpoch;
      final publicUrl = '${storage.getPublicUrl(objectPath)}?v=$v';
      await Future.wait([
        FirebaseAuth.instance.currentUser!.updatePhotoURL(publicUrl),
        UserProfileService.setAvatarUrl(publicUrl),
      ]);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profil fotoğrafın güncellendi'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('[unified-avatar] upload failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fotoğraf yüklenemedi')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _confirmRemoveAvatar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fotoğrafı kaldır'),
        content:
            const Text('Profil fotoğrafını kaldırmak istediğine emin misin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: KoalaColors.error),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _uploadingAvatar = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        try {
          await Supabase.instance.client.storage
              .from('avatars')
              .remove(['$uid/avatar.webp']);
        } catch (_) {/* swallow */}
      }
      await Future.wait([
        FirebaseAuth.instance.currentUser!.updatePhotoURL(null),
        UserProfileService.setAvatarUrl(null),
      ]);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profil fotoğrafı kaldırıldı.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('[unified-avatar] remove failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fotoğraf kaldırılamadı')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  // ─── Stats — 3 columns: Tasarım / Değerlendirme / Yanıt ──────────────
  // 2026-05-28: Takipçi/Takip stat row'dan kaldırıldı; bu erişim ⋯ menüye
  // taşındı. Yanıt süresi `koala_designer_stats` henüz şemada yok →
  // defansif olarak "—" gösterilir; Evlumba için sabit "24s".
  Widget _stats() {
    // Server-side exact total varsa onu kullan; ama yüklenen karttan küçükse
    // (örn. Evlumba tasarımcısı, count başka DB'de 0 döndü) gözlenen sayıya
    // düş — "0 tasarım ama 2 kart" çelişkisini engeller.
    final seen = _loadedDesigns.length;
    final total = _designTotalCount;
    final String designValue;
    if (total != null && total >= seen && total > 0) {
      designValue = '$total';
    } else if (seen > 0) {
      designValue = _hasMoreDesigns ? '$seen+' : '$seen';
    } else {
      designValue = '0';
    }
    final ratingValue = _reviews.count > 0
        ? '${_reviews.avg.toStringAsFixed(1)}★'
        : '0';
    // 2026-05-28 FIX 4: Yanıt stat semantics.
    //  • Evlumba (sentetik) → ⚡ <1 saat (responds faster than designers).
    //  • Other Pro/designer profiles → "24s" default (until
    //    koala_designer_stats.avg_response_time_sec is wired in).
    //  • Non-designer users → "—" (no meaningful response stat).
    final isEvlumba = widget.profileId == 'evlumba-design';
    final showResponseStat = isEvlumba || _isDesignerOrPro;
    final responseValue =
        isEvlumba ? '<1 saat' : (_isDesignerOrPro ? '24s' : '—');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
      child: Row(
        children: [
          _stat(
            label: 'Tasarım',
            value: designValue,
            onTap: _scrollToDesigns,
          ),
          // 2026-06-02: "Görüntülenme" stat'ı kaldırıldı (kullanıcı vazgeçti).
          _statDiv(),
          _stat(
            label: 'Değerlendirme',
            value: ratingValue,
            onTap: _openReviewsSheet,
          ),
          if (showResponseStat) ...[
            _statDiv(),
            isEvlumba
                ? _statEvlumbaResponse(
                    label: 'Yanıt',
                    onTap: _showResponseTooltip,
                  )
                : _stat(
                    label: 'Yanıt',
                    value: responseValue,
                    onTap: _showResponseTooltip,
                  ),
          ],
        ],
      ),
    );
  }

  /// 2026-05-28 FIX 4: Evlumba'ya özel "⚡ <1 saat" compact widget — diğer
  /// tasarımcılardan daha hızlı yanıt verdiğini görsel olarak vurgular.
  Widget _statEvlumbaResponse({
    required String label,
    VoidCallback? onTap,
  }) {
    final body = Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(LucideIcons.zap, size: 14, color: Color(0xFFE0A300)),
            SizedBox(width: 4),
            Text(
              '<1 saat',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: KoalaColors.text,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: KoalaText.labelSmall),
      ],
    );
    if (onTap == null) return Expanded(child: body);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: body,
        ),
      ),
    );
  }

  void _scrollToDesigns() {
    HapticFeedback.selectionClick();
    // Designs section yukarıdaki ListView içinde; PrimaryScrollController
    // sheet'in scroll controller'ını sağlar — basit Scrollable.ensureVisible
    // burada Container key olmadan zor, snackbar ile no-op davranışı yerine
    // ListView'i programatik kaydırmıyoruz — kullanıcı doğal scroll'la iner.
  }

  void _showResponseTooltip() {
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ortalama yanıt süresi'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// FIX 5 — Değerlendirme stat tap → reviews bottom sheet:
  /// drag handle + header + 4 filter chips + scrollable list + sticky CTA.
  /// "Değerlendir" CTA tap → ayrı bir bottom sheet (form-on-form push) açar.
  Future<void> _openReviewsSheet() async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: KoalaColors.bg,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          final mq = MediaQuery.of(ctx);
          final maxH = mq.size.height * 0.88;
          final avg = _reviews.avg.toStringAsFixed(1);
          // 2026-05-28 FIX 2: Sort/filter chips kaldırıldı. Reviews her zaman
          // newest-first (createdAt DESC) gösterilir.
          final filtered = List<DesignerReview>.from(_reviews.reviews)
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          // FIX 3: Self değilse her zaman Değerlendir CTA görünür (Pro/designer
          // kısıtlaması kaldırıldı — kullanıcılar her profili değerlendirebilir).
          final showCta = !_isSelf;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: KoalaColors.border,
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Değerlendirmeler', style: KoalaText.h2),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(LucideIcons.star,
                                size: 14, color: Color(0xFFEFA01F)),
                            const SizedBox(width: 4),
                            Text(
                              _reviews.count > 0
                                  ? '$avg★ (${_reviews.count} değerlendirme)'
                                  : 'Henüz değerlendirme yok',
                              style: KoalaText.bodySec,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: filtered.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 32, horizontal: 24),
                            child: Center(
                              child: Text(
                                _reviews.count == 0
                                    ? 'Henüz değerlendirme yok.'
                                    : 'Bu filtreye uygun değerlendirme yok.',
                                style: KoalaText.bodySec,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) => _reviewCard(filtered[i]),
                          ),
                  ),
                  if (showCta)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                          20, 8, 20, mq.padding.bottom + 12),
                      child: _DegerlendirCta(
                        onTap: () async {
                          HapticFeedback.selectionClick();
                          Navigator.of(ctx).pop();
                          await _openRateSheet();
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Future<void> _openFollowList(FollowListMode mode) async {
    HapticFeedback.selectionClick();
    await FollowListSheet.open(
      context,
      ownerUid: widget.profileId,
      mode: mode,
    );
    if (!mounted) return;
    // Refresh counts after the list closes (user may have followed/unfollowed).
    try {
      final c = await FollowService.counts(widget.profileId);
      if (!mounted) return;
      setState(() => _counts = c);
    } catch (_) {/* swallow */}
  }

  Widget _stat({
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    final body = Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: KoalaColors.text,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: KoalaText.labelSmall),
      ],
    );
    if (onTap == null) {
      return Expanded(child: body);
    }
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: body,
        ),
      ),
    );
  }

  Widget _statDiv() =>
      Container(width: 1, height: 26, color: KoalaColors.border);

  // ─── Actions row ────────────────────────────────────────────────────
  Widget _actionsRow() {
    if (widget.ownerEditable && _isSelf) {
      return Padding(
        // 2026-06-02: tasarımlar daha yukarıda görünsün diye kompakt.
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: ElevatedButton(
                  onPressed: widget.onEditProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KoalaColors.accentDeep,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Profili Düzenle',
                    style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    // Other-user view → follow pill + message icon + ⋯ menu.
    // 2026-05-28 FIX 4: Message icon eklendi (kendi profilimizde değilse).
    final following = _follow.following;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _followBusy ? null : _onFollowTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: following
                      ? KoalaColors.surface
                      : KoalaColors.accentDeep,
                  foregroundColor:
                      following ? KoalaColors.text : Colors.white,
                  disabledBackgroundColor: KoalaColors.surfaceAlt,
                  padding: const EdgeInsets.symmetric(vertical: 0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: following
                        ? const BorderSide(
                            color: KoalaColors.borderSolid, width: 1)
                        : BorderSide.none,
                  ),
                  elevation: 0,
                ),
                icon: Icon(
                  following ? LucideIcons.check : LucideIcons.userPlus,
                  size: 18,
                ),
                label: Text(
                  following ? 'Takipte' : 'Takip Et',
                  style: KoalaText.button.copyWith(
                    color: following ? KoalaColors.text : Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Mesaj butonu — dolu gradient CTA: belirgin, marka moru, beyaz ikon.
          Consumer(builder: (ctx, ref, _) {
            return Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    KoalaColors.accentDeep,
                    KoalaColors.accentDeepDark,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: KoalaColors.accentDeep.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _onMessageTap(ref),
                  child: const Center(
                    child: Icon(LucideIcons.messageCircle,
                        size: 21, color: Colors.white),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(width: 10),
          SizedBox(
            width: 44,
            height: 44,
            child: Material(
              color: KoalaColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(
                    color: KoalaColors.borderSolid, width: 1),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _openMoreMenu,
                child: const Center(
                  child: Icon(LucideIcons.moreHorizontal,
                      size: 20, color: KoalaColors.text),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// FIX 4 — message icon tap routing.
  ///  - Evlumba designer → enterEvlumbaConversation (paywall/free-consult sheet).
  ///  - Other designer (designerRow non-null) → push ConversationDetailScreen.
  ///  - Regular user → TODO snackbar.
  Future<void> _onMessageTap(WidgetRef ref) async {
    HapticFeedback.selectionClick();
    if (widget.profileId == KoalaSeedService.evlumbaDesignerId) {
      await enterEvlumbaConversation(context, ref);
      return;
    }
    if (_designerRow != null) {
      final name =
          ((_designerRow?['full_name'] ?? _designerRow?['business_name'] ?? '')
                  as String)
              .trim();
      final avatar =
          ((_designerRow?['avatar_url'] ?? '') as String).trim();
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ConversationDetailScreen(
            designerId: widget.profileId,
            designerName: name.isNotEmpty ? name : 'Tasarımcı',
            designerAvatarUrl: avatar.isNotEmpty ? avatar : null,
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Yakında — kullanıcı sohbeti'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// ⋯ menü — diğer kullanıcı profilinde takip pill'inin yanında.
  /// Hakkında / bildirim sessize / takipçi listesi / takip listesi /
  /// engelle / şikayet. Engelle ve şikayet için tablolar henüz yok →
  /// defansif "Yakında" snackbar.
  Future<void> _openMoreMenu() async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: KoalaColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: KoalaColors.border,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const SizedBox(height: 12),
            // 2026-06-01: "Hakkında" + "Takipçileri/Takip ettiklerini gör"
            // menüden kaldırıldı (kullanıcı direktifi).
            if (_follow.following)
              ListTile(
                leading: Icon(
                  _follow.muted ? LucideIcons.bell : LucideIcons.bellOff,
                  color: KoalaColors.accentDeep,
                ),
                title: Text(
                  _follow.muted
                      ? 'Bildirimleri aç'
                      : 'Bildirimleri sessize al',
                  style: KoalaText.bodyMedium,
                ),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final next =
                      await FollowService.muteToggle(widget.profileId);
                  if (!mounted) return;
                  setState(() => _follow = next);
                },
              ),
            if (_isDesignerOrPro && !_isSelf)
              ListTile(
                leading: const Icon(LucideIcons.star,
                    color: KoalaColors.accentDeep),
                title:
                    const Text('Değerlendir', style: KoalaText.bodyMedium),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openRateSheet();
                },
              ),
            const Divider(height: 12),
            ListTile(
              leading:
                  const Icon(LucideIcons.ban, color: KoalaColors.error),
              title: const Text(
                'Engelle',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: KoalaColors.error,
                ),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _confirmBlock();
              },
            ),
            ListTile(
              leading:
                  const Icon(LucideIcons.flag, color: KoalaColors.error),
              title: const Text(
                'Şikayet et',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: KoalaColors.error,
                ),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _openReportSheet();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showAboutSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KoalaColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KoalaColors.border,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Hakkında', style: KoalaText.h2),
              const SizedBox(height: 12),
              Text(_about, style: KoalaText.body),
            ],
          ),
        ),
      ),
    );
  }

  /// Engelle — koala_blocks tablosu henüz yok. TODO: şema önerisi:
  ///   koala_blocks(blocker_uid text, blocked_uid text, created_at timestamptz,
  ///                primary key (blocker_uid, blocked_uid))
  Future<void> _confirmBlock() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Engelle'),
        content: const Text(
            'Bu kullanıcıyı engellemek istediğine emin misin? Profilini ve '
            'içeriklerini bir daha görmeyeceksin.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: KoalaColors.error),
            child: const Text('Engelle'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Engelleme yakında — şu an aktif değil'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Şikayet — koala_reports tablosu henüz yok. TODO: şema önerisi:
  ///   koala_reports(id uuid, reporter_uid text, target_uid text,
  ///                 reason text, comment text, created_at timestamptz)
  Future<void> _openReportSheet() async {
    final reasonCtrl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: KoalaColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final insets = MediaQuery.viewInsetsOf(ctx);
        return Padding(
          padding: EdgeInsets.only(bottom: insets.bottom),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: KoalaColors.border,
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Şikayet sebebi', style: KoalaText.h2),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Sebebi kısaca yaz…',
                      filled: true,
                      fillColor: KoalaColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: KoalaColors.borderSolid, width: 0.8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Şikayet aldık, teşekkürler 🙌'),
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: KoalaColors.accentDeep,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: const Text('Gönder', style: KoalaText.button),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openRateSheet() async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: KoalaColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final insets = MediaQuery.viewInsetsOf(ctx);
        return Padding(
          padding: EdgeInsets.only(bottom: insets.bottom),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: KoalaColors.border,
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Değerlendir', style: KoalaText.h2),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _RateAndCommentBar(onSubmit: (r, c) async {
                    await _onReviewSubmit(r, c);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── About ──────────────────────────────────────────────────────────
  // 2026-05-28: SPEC 10 — Hakkında bölümü her zaman görünür (bio non-empty).
  // Başlık UPPERCASE 11px w700 textTer ls 1.2 + paragraf 13px w500 textMed
  // lineHeight 1.5, max 4 satır + Daha fazla expand.
  Widget _aboutSection() {
    return _AboutBlock(text: _about);
  }

  // FIX 2: Inline _reviewsBlock kaldırıldı — reviews artık sadece
  // "Değerlendirme" stat tap'iyle açılan bottom sheet'te gösterilir.


  String _relativeTime(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'az önce';
    if (d.inMinutes < 60) return '${d.inMinutes} dk';
    if (d.inHours < 24) return '${d.inHours} sa';
    if (d.inDays < 7) return '${d.inDays} gün';
    if (d.inDays < 30) return '${(d.inDays / 7).floor()} hf';
    if (d.inDays < 365) return '${(d.inDays / 30).floor()} ay';
    return '${(d.inDays / 365).floor()} yıl';
  }

  // ─── Reviewer pseudo-identity helpers (FIX 3) ─────────────────────────
  // Stable from a seed string: same seed → same initials, color, avatar.
  static const List<String> _firstLetters = [
    'A','B','C','D','E','F','G','H','K','M','N','O','P','R','S','T','U','V','Y','Z'
  ];
  static const List<String> _lastLetters = [
    'A','B','D','E','K','L','M','N','R','S','T','Y','Z'
  ];
  static const List<String> _pravatarUrls = [
    'https://i.pravatar.cc/100?u=1',
    'https://i.pravatar.cc/100?u=2',
    'https://i.pravatar.cc/100?u=3',
    'https://i.pravatar.cc/100?u=4',
    'https://i.pravatar.cc/100?u=5',
    'https://i.pravatar.cc/100?u=6',
  ];
  static const List<Color> _avatarBgColors = [
    Color(0xFF6C5CE7), // accentDeep
    Color(0xFFE17055), // soft coral
    Color(0xFF00B894), // teal
    Color(0xFFEFA01F), // amber
    Color(0xFF0984E3), // blue
    Color(0xFFD63031), // red
    Color(0xFF6F42C1), // violet
    Color(0xFF20C997), // mint
  ];

  int _stableHash(String s) {
    // FNV-1a 32-bit for stability across runs (String.hashCode is randomized).
    int h = 0x811c9dc5;
    for (int i = 0; i < s.length; i++) {
      h ^= s.codeUnitAt(i);
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  String _pseudoInitials(String seed) {
    if (seed.isEmpty) return 'A. K.';
    final h = _stableHash(seed);
    final first = _firstLetters[h % _firstLetters.length];
    final last = _lastLetters[(h ~/ _firstLetters.length) % _lastLetters.length];
    return '$first. $last.';
  }

  bool _useAvatarForSeed(String seed) {
    if (seed.isEmpty) return false;
    return _stableHash(seed) % 3 == 0; // ~33%
  }

  String _avatarUrlForSeed(String seed) {
    final h = _stableHash(seed);
    return _pravatarUrls[h % _pravatarUrls.length];
  }

  Color _avatarBgColorForSeed(String seed) {
    if (seed.isEmpty) return KoalaColors.accentDeep;
    final h = _stableHash(seed);
    return _avatarBgColors[h % _avatarBgColors.length];
  }

  Widget _reviewCard(DesignerReview r) {
    final seed = (r.reviewerId.isNotEmpty ? r.reviewerId : r.id);
    final initials = _pseudoInitials(seed);
    final useAvatar = _useAvatarForSeed(seed);
    final avatarUrl = useAvatar ? _avatarUrlForSeed(seed) : null;
    final bgColor = _avatarBgColorForSeed(seed);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KoalaColors.borderSolid, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bgColor,
                ),
                clipBehavior: Clip.antiAlias,
                child: avatarUrl != null
                    ? CachedNetworkImage(
                        imageUrl: avatarUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(color: bgColor),
                        errorWidget: (_, _, _) => Center(
                          child: Text(
                            initials,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          initials,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: KoalaColors.text,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              Text(
                _relativeTime(r.createdAt),
                style: KoalaText.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: List.generate(
              5,
              (i) => Icon(
                i < r.rating
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                size: 14,
                color: const Color(0xFFEFA01F),
              ),
            ),
          ),
          if ((r.comment ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              r.comment!,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: KoalaColors.text,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── AI Stüdyom pill (owner only, when AI designs exist) ────────────
  // 2026-05-28: SPEC 12 — Profilden kaldırıldı. Code kalır ki ileride geri
  // getirilmek istenirse hazır olsun.
  // ignore: unused_element
  Widget _aiStudioPill() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Material(
        color: KoalaColors.accentSoft,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onOpenAiStudio?.call();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: KoalaColors.accentDeep.withValues(alpha: 0.18),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.sparkles,
                    size: 16, color: KoalaColors.accentDeep),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'AI Stüdyom',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: KoalaColors.accentDeep,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                const Icon(LucideIcons.chevronRight,
                    size: 18, color: KoalaColors.accentDeep),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Projects header & grid ─────────────────────────────────────────
  /// FIX 5 (2026-05-28): premium uppercase header — "TASARIMLARIM" /
  /// "TASARIMLARI". Right-side count uses textTer 12px w600.
  Widget _projectsHeader() {
    final title = _isSelf ? 'TASARIMLARIM' : 'TASARIMLARI';
    // Align horizontal padding with the grid below (16 on own, 20 elsewhere).
    final hPad = _isOwnGrid ? 16.0 : 20.0;
    String? countLabel;
    if (_designTotalCount != null && _designTotalCount! > 0) {
      countLabel = '${_designTotalCount!} adet';
    } else if (_loadedDesigns.isNotEmpty) {
      countLabel = (_hasMoreDesigns && _loadedDesigns.isNotEmpty)
          ? '${_loadedDesigns.length}+ adet'
          : '${_loadedDesigns.length} adet';
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 2, hPad, 6),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: KoalaColors.textTer,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (countLabel != null)
            Text(
              countLabel,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: KoalaColors.textTer,
                letterSpacing: -0.1,
              ),
            ),
        ],
      ),
    );
  }

  /// Kompakt kategori filtre pill row'u — grid üstünde yatay kayan şerit.
  /// "Tümü" + yüklü tasarımlardan türeyen benzersiz kategoriler. Seçim
  /// client-side filtreler; aktif pill mor dolu, diğerleri çerçeveli.
  Widget _categoryFilterRow() {
    final cats = _availableCategories;
    final hPad = _isOwnGrid ? 16.0 : 20.0;
    Widget pill(String label, String? value) {
      final active = _categoryFilter == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _categoryFilter = value);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 34,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: active ? KoalaColors.accentDeep : KoalaColors.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: active
                    ? KoalaColors.accentDeep
                    : KoalaColors.borderSolid,
                width: 1,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.0,
                color: active ? Colors.white : KoalaColors.textSec,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ),
      );
    }

    // Pill satırı + altına grid başlamadan önce nefes alacak boşluk.
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 0),
          physics: const BouncingScrollPhysics(),
          children: [
            pill('Tümü', null),
            for (final c in cats) pill(c, c),
          ],
        ),
      ),
    );
  }

  /// Tek bir tasarım tile'ı — SliverGrid'in `SliverChildBuilderDelegate`
  /// callback'inden çağrılır. Görünür (filtreli) liste + indeks geçilir;
  /// tap callback'inde aynı liste + index forward edilir.
  Widget _designTile(List<Map<String, dynamic>> list, int i) {
          final p = list[i];
          final cover = _coverOf(p);
          final id = (p['id'] ?? p['item_id'] ?? '').toString();
          // Tüm profillerde premium tile görünümü (radius 14 + kategori
          // overlay) — popup da kişinin kendi profili gibi görünsün.
          final isViewed = widget.viewedDesignId != null &&
              widget.viewedDesignId!.isNotEmpty &&
              widget.viewedDesignId == id;
          final isAiTile = p['is_ai'] == true;
          final categoryLabel = _categoryLabel(p);
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onTapDesign?.call(list, i);
            },
            onLongPress: (widget.ownerEditable && _isSelf)
                ? () {
                    HapticFeedback.mediumImpact();
                    _showOwnTileActionSheet(p);
                  }
                : null,
            behavior: HitTestBehavior.opaque,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (cover.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: cover,
                      fit: BoxFit.cover,
                      memCacheWidth: 400,
                      placeholder: (_, _) =>
                          Container(color: KoalaColors.surfaceAlt),
                      errorWidget: (_, _, _) =>
                          Container(color: KoalaColors.surfaceAlt),
                    )
                  else
                    Container(color: KoalaColors.surfaceAlt),
                  // Standard bottom gradient for title legibility.
                  Positioned.fill(
                    child: DecoratedBox(
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
                  // Subtle "Bunu görüntülediniz" overlay.
                  if (isViewed) ...[
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.30),
                      ),
                    ),
                    Positioned(
                      left: 6,
                      top: 6,
                      // FIX 7: koyu pill + beyaz text (önceki versiyon ters
                      // renkliydi).
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: KoalaColors.text.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Bunu görüntülediniz',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: -0.05,
                          ),
                        ),
                      ),
                    ),
                  ],
                  // OWN profile: only category text overlay (bottom-left,
                  // white 13px w700, no AI/Gizli badges).
                  if (categoryLabel.isNotEmpty)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 10,
                      child: Text(
                        categoryLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                  // 2026-06-02: Koala AI ile üretildiyse sağ üstte küçük rozet.
                  if (isAiTile)
                    const Positioned(
                      top: 8,
                      right: 8,
                      child: KoalaAiBadge(size: 30),
                    ),
                ],
              ),
            ),
          );
  }

  /// 2026-05-28 FIX 3 — Own design tile long-press action sheet.
  /// Public/private toggle removed; only Düzenle / Sil / İptal.
  Future<void> _showOwnTileActionSheet(Map<String, dynamic> p) async {
    final isAi = p['is_ai'] == true;
    final id = (p['id'] ?? p['item_id'] ?? '').toString();
    if (id.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: KoalaColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: KoalaColors.border,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(LucideIcons.pencil,
                  color: KoalaColors.accentDeep),
              title: const Text('Düzenle', style: KoalaText.bodyMedium),
              subtitle: Text(
                'Başlık veya açıklamayı değiştir',
                style: KoalaText.labelSmall,
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _editTile(p);
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.trash2,
                  color: KoalaColors.error),
              title: const Text('Sil', style: KoalaText.bodyMedium),
              subtitle: Text(
                'Bu tasarım profilden kaldırılır',
                style: KoalaText.labelSmall,
              ),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _confirmAndDeleteTile(p, isAi: isAi, id: id);
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.x,
                  color: KoalaColors.textSec),
              title: const Text('İptal', style: KoalaText.bodyMedium),
              onTap: () => Navigator.of(ctx).pop(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Edit tile — opens a simple title/description editor.
  Future<void> _editTile(Map<String, dynamic> p) async {
    final titleCtl = TextEditingController(
      text: (p['title'] ?? '').toString(),
    );
    final descCtl = TextEditingController(
      text: (p['description'] ?? p['caption'] ?? '').toString(),
    );
    final isAi = p['is_ai'] == true;
    final id = (p['id'] ?? p['item_id'] ?? '').toString();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: KoalaColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: KoalaColors.border,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Tasarımı düzenle', style: KoalaText.h2),
            const SizedBox(height: 16),
            TextField(
              controller: titleCtl,
              decoration: const InputDecoration(
                labelText: 'Başlık',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Açıklama',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('İptal'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Kaydet'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final newTitle = titleCtl.text.trim();
    final newDesc = descCtl.text.trim();
    bool ok = false;
    try {
      if (isAi) {
        ok = await SavedItemsService.updateItem(
          type: SavedItemType.project,
          itemId: id,
          title: newTitle,
        );
      } else {
        ok = await SharedDesignService.update(
          id,
          title: newTitle.isEmpty ? null : newTitle,
          description: newDesc.isEmpty ? null : newDesc,
        );
      }
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (ok) {
      setState(() {
        p['title'] = newTitle;
        if (!isAi) p['description'] = newDesc;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Güncellendi'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Güncellenemedi, tekrar dene')),
      );
    }
  }

  /// Delete tile with a confirmation dialog.
  Future<void> _confirmAndDeleteTile(
    Map<String, dynamic> p, {
    required bool isAi,
    required String id,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bu tasarımı silmek istiyor musun?'),
        content: const Text(
            'Bu işlem geri alınamaz. Tasarım profilinden kalıcı olarak kaldırılır.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: KoalaColors.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    bool ok = false;
    try {
      if (isAi) {
        ok = await SavedItemsService.removeItem(
          type: SavedItemType.project,
          itemId: id,
        );
      } else {
        ok = await SharedDesignService.delete(id);
      }
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (ok) {
      setState(() {
        _loadedDesigns.removeWhere(
          (e) => (e['id'] ?? e['item_id'] ?? '').toString() == id,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tasarım silindi'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silinemedi, tekrar dene')),
      );
    }
  }

  /// FIX 4 (2026-05-28): build a short, friendly category label for the
  /// own-profile tile overlay. Prefer explicit `category`, fall back to
  /// `room_type` (translated TR), then first style tag.
  String _categoryLabel(Map<String, dynamic> p) {
    // Oda tipini temiz TR etikete çevirir — İngilizce/snake_case/aksanlı tüm
    // varyantları map'ler; bilinmeyende alt çizgileri boşluğa çevirip her
    // kelimeyi büyütür. Asla ham "Yatak_odasi" göstermez.
    String pretty(String raw) {
      final r =
          raw.trim().toLowerCase().replaceAll('_', ' ').replaceAll('i̇', 'i');
      if (r.isEmpty) return '';
      const map = {
        'living room': 'Oturma Odası',
        'salon': 'Oturma Odası',
        'oturma odasi': 'Oturma Odası',
        'bedroom': 'Yatak Odası',
        'yatak odasi': 'Yatak Odası',
        'kitchen': 'Mutfak',
        'bathroom': 'Banyo',
        'kids room': 'Çocuk Odası',
        'cocuk odasi': 'Çocuk Odası',
        'office': 'Çalışma Odası',
        'ofis': 'Çalışma Odası',
        'calisma odasi': 'Çalışma Odası',
        'dining room': 'Yemek Odası',
        'yemek odasi': 'Yemek Odası',
        'hallway': 'Antre',
        'antre': 'Antre',
        'hall': 'Hol',
        'hol': 'Hol',
        'balcony': 'Balkon',
        'balkon': 'Balkon',
        'terrace': 'Teras',
        'teras': 'Teras',
        'garden': 'Bahçe',
        'bahce': 'Bahçe',
        'walk in closet': 'Giyinme Odası',
        'giyinme odasi': 'Giyinme Odası',
      };
      final hit = map[r];
      if (hit != null) return hit;
      return r
          .split(' ')
          .where((w) => w.isNotEmpty)
          .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');
    }

    // Seed kartları (evlumba) yalnızca project_type taşır — ÖNCE onu dene.
    final pt = (p['project_type'] ?? '').toString().trim();
    if (pt.isNotEmpty) return pretty(pt);
    final cat = (p['category'] ?? '').toString().trim();
    if (cat.isNotEmpty) return pretty(cat);
    final room = (p['room_type'] ?? p['roomType'] ?? '').toString().trim();
    if (room.isNotEmpty) return pretty(room);
    final tags = p['tags'];
    if (tags is List && tags.isNotEmpty) {
      final t = tags.first.toString().trim();
      if (t.isNotEmpty) return pretty(t);
    }
    final style = (p['style'] ?? '').toString().trim();
    if (style.isNotEmpty) return pretty(style);
    // 2026-06-02: AI tasarımlarda oda tipi alanı boş olabilir; başlıktan türet
    // ("Yeni Yemek Odası" → "Yemek Odası"). Böylece AI tile'larında da sol-altta
    // kategori görünür.
    final title = (p['title'] ?? '').toString().trim();
    if (title.isNotEmpty) {
      final stripped =
          title.replaceFirst(RegExp(r'^\s*[Yy]eni\s+'), '').trim();
      if (stripped.isNotEmpty) return pretty(stripped);
    }
    return '';
  }

  String _coverOf(Map<String, dynamic> p) {
    for (final k in ['cover_image_url', 'cover_url', 'image_url']) {
      final v = (p[k] ?? '').toString().trim();
      if (v.isNotEmpty && !v.startsWith('data:')) return v;
    }
    final imgs = p['designer_project_images'] as List?;
    if (imgs != null && imgs.isNotEmpty) {
      final sorted = List<Map<String, dynamic>>.from(
        imgs.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
      )..sort((a, b) => ((a['sort_order'] as num?)?.toInt() ?? 9999)
          .compareTo((b['sort_order'] as num?)?.toInt() ?? 9999));
      return (sorted.first['image_url'] ?? '').toString();
    }
    return '';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// RateAndCommentBar — elegant inline review input.
// 5 interactive stars (40px tap targets, animated tap) + single-line
// TextField that expands on focus + small "Gönder" pill below.
// ═══════════════════════════════════════════════════════════════════════
class _RateAndCommentBar extends StatefulWidget {
  final Future<void> Function(int rating, String comment) onSubmit;
  const _RateAndCommentBar({required this.onSubmit});

  @override
  State<_RateAndCommentBar> createState() => _RateAndCommentBarState();
}

class _RateAndCommentBarState extends State<_RateAndCommentBar> {
  int _rating = 0;
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _focused = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() => _focused = _focus.hasFocus);
    });
    _ctrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting && _rating > 0 && _ctrl.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    HapticFeedback.lightImpact();
    await widget.onSubmit(_rating, _ctrl.text.trim());
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _rating = 0;
      _ctrl.clear();
      _focused = false;
    });
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: KoalaColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: KoalaColors.borderSolid, width: 0.6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bu profil için bir yorum bırak',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: KoalaColors.textSec,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: List.generate(5, (i) {
                final idx = i + 1;
                final filled = idx <= _rating;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _rating = idx);
                  },
                  child: AnimatedScale(
                    scale: filled ? 1.0 : 0.94,
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      child: Icon(
                        filled
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 28,
                        color: filled
                            ? const Color(0xFFEFA01F)
                            : KoalaColors.border,
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                maxLines: _focused ? 4 : 1,
                minLines: 1,
                style: const TextStyle(fontSize: 14, color: KoalaColors.text),
                decoration: InputDecoration(
                  hintText: 'Bir şeyler yaz...',
                  hintStyle: const TextStyle(
                    fontSize: 14,
                    color: KoalaColors.textTer,
                  ),
                  filled: true,
                  fillColor: KoalaColors.surfaceAlt,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Material(
                color: _canSubmit
                    ? KoalaColors.accentDeep
                    : KoalaColors.surfaceAlt,
                borderRadius: BorderRadius.circular(99),
                child: InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: _canSubmit ? _submit : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 9),
                    child: Text(
                      _submitting ? 'Gönderiliyor…' : 'Gönder',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _canSubmit
                            ? Colors.white
                            : KoalaColors.textTer,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Suppress unused import warning when ProfileDesignTile isn't needed yet —
// kept imported for future extension (consistent profile design tile look).
// ignore: unused_element
void _keep() => ProfileDesignTile;

/// FIX 5 — Reviews sheet'in altındaki sticky "Değerlendir" CTA. Premium
/// gradient pill, tam genişlik (accentDeep → accent).
class _DegerlendirCta extends StatelessWidget {
  final VoidCallback onTap;
  const _DegerlendirCta({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [KoalaColors.accentDeep, KoalaColors.accent],
            ),
            borderRadius: BorderRadius.circular(99),
            boxShadow: [
              BoxShadow(
                color: KoalaColors.accentDeep.withValues(alpha: 0.30),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Container(
            height: 50,
            alignment: Alignment.center,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.star, size: 18, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'Değerlendir',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// SPEC 10 — About block with collapse/expand (4 lines clamp + "Daha fazla").
class _AboutBlock extends StatefulWidget {
  final String text;
  const _AboutBlock({required this.text});

  @override
  State<_AboutBlock> createState() => _AboutBlockState();
}

class _AboutBlockState extends State<_AboutBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    const headerStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: KoalaColors.textTer,
      letterSpacing: 1.2,
    );
    const paragraphStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: KoalaColors.textMed,
      height: 1.5,
      letterSpacing: -0.05,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('HAKKINDA', style: headerStyle),
          const SizedBox(height: 6),
          LayoutBuilder(builder: (ctx, cs) {
            final tp = TextPainter(
              text: TextSpan(text: widget.text, style: paragraphStyle),
              maxLines: 4,
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: cs.maxWidth);
            final overflow = tp.didExceedMaxLines;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.text,
                  style: paragraphStyle,
                  maxLines: _expanded ? null : 4,
                  overflow: _expanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                ),
                if (overflow)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _expanded = !_expanded);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _expanded ? 'Daha az' : 'Daha fazla',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: KoalaColors.accentDeep,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

/// Başvuru beklemedeyken gösterilen bilgi rozeti — tıklanamaz. Kullanıcı
/// yalnızca bir kez başvurabilir; inceleme bitene kadar bu görünür.
class _ProPendingPill extends StatelessWidget {
  const _ProPendingPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: const Color(0xFFD4A853).withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.clock, size: 13, color: Color(0xFFB8874A)),
          SizedBox(width: 6),
          Text(
            'Profesyonel başvurunuz incelenmekte',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFFB8874A),
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// FIX 2 (2026-05-28) — Pro upsell pill shown on own profile when user is
/// NOT pro. Subtle gold gradient, transitions to Pro application sheet.
class _ProUpsellPill extends StatelessWidget {
  final VoidCallback onTap;
  const _ProUpsellPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(100),
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E8),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: const Color(0xFFD4A853).withValues(alpha: 0.35),
              width: 0.8,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '✨ Profesyonel ol',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFD4A853),
                  letterSpacing: -0.1,
                ),
              ),
              SizedBox(width: 4),
              Icon(LucideIcons.arrowRight, size: 14, color: Color(0xFFD4A853)),
            ],
          ),
        ),
      ),
    );
  }
}

/// FIX 2 (2026-05-28) — Segmented role switch (Ev Sahibi | Profesyonel) for
/// users that already are Pro and toggle their public face.
class _RoleSegmentedSwitch extends StatelessWidget {
  final String current; // 'homeowner' | 'pro'
  final ValueChanged<String> onChange;
  const _RoleSegmentedSwitch({required this.current, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: KoalaColors.borderSolid, width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg('Ev Sahibi', current == 'homeowner', () => onChange('homeowner')),
          _seg('Profesyonel', current == 'pro', () => onChange('pro')),
        ],
      ),
    );
  }

  Widget _seg(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: active ? KoalaColors.accentDeep : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : KoalaColors.textSec,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }
}

/// FIX 6 (2026-05-28) — Emotional empty state for own profile when no
/// designs exist. Large 3D-style illustration (fallback to gradient +
/// sparkles when the seed URL hasn't been generated yet) + headline +
/// subtitle. WHOLE block tappable, opens the share upload modal.
class _OwnEmptyShareCta extends StatelessWidget {
  final VoidCallback onTap;
  const _OwnEmptyShareCta({required this.onTap});

  // TODO(koala-seed): Generate the dedicated 3D empty-state image via the
  // seed-empty-state endpoint once it exists. For now CachedNetworkImage
  // falls back to a soft gradient + sparkles icon if the URL 404s.
  static const String _illustrationUrl =
      'https://xgefjepaqnghaotqybpi.supabase.co/storage/v1/object/public/koala-seed/empty/own-designs-3d.webp';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 200,
                  height: 200,
                  child: CachedNetworkImage(
                    imageUrl: _illustrationUrl,
                    fit: BoxFit.contain,
                    placeholder: (_, _) => _fallback(),
                    errorWidget: (_, _, _) => _fallback(),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'İlk tasarımını paylaş ✨',
                  style: KoalaText.h3,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                const Text(
                  'AI ile üret ya da kendi mekânının fotoğrafını yükle',
                  style: KoalaText.bodySec,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  decoration: BoxDecoration(
                    color: KoalaColors.accentDeep,
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: [
                      BoxShadow(
                        color: KoalaColors.accentDeep.withValues(alpha: 0.30),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.plus, size: 16, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'Paylaş',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            KoalaColors.accentSoft,
            KoalaColors.accentDeep.withValues(alpha: 0.18),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: KoalaColors.accentDeep.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Center(
        child: Icon(LucideIcons.sparkles,
            size: 72, color: KoalaColors.accentDeep),
      ),
    );
  }
}

/// SPEC 7 — Premium empty state for own profile: soft purple gradient circle
/// + title + subtitle + iki pill (AI ile üret / Paylaş).
/// FIX 6 (2026-05-28): Superseded by `_OwnEmptyShareCta`. Kept for ref.
// ignore: unused_element
class _PremiumOwnEmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  final VoidCallback onShare;
  const _PremiumOwnEmptyState({
    required this.onCreate,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  KoalaColors.accentSoft,
                  KoalaColors.accentDeep.withValues(alpha: 0.18),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: KoalaColors.accentDeep.withValues(alpha: 0.15),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Center(
              child: Icon(LucideIcons.sparkles,
                  size: 48, color: KoalaColors.accentDeep),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Henüz tasarımın yok',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: KoalaColors.text,
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            'İlk AI tasarımını üret veya kendi mekânını paylaş',
            style: KoalaText.bodySec,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: onCreate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: KoalaColors.accentDeep,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                  elevation: 0,
                ),
                icon: const Icon(LucideIcons.sparkles, size: 16),
                label: const Text(
                  'AI ile üret',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: onShare,
                style: OutlinedButton.styleFrom(
                  foregroundColor: KoalaColors.accentDeep,
                  side: BorderSide(
                    color: KoalaColors.accentDeep.withValues(alpha: 0.4),
                    width: 1,
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
                icon: const Icon(LucideIcons.upload, size: 16),
                label: const Text(
                  'Paylaş',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
