import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/koala_tokens.dart';
import '../services/evlumba_live_service.dart';
import '../services/koala_tool_handler.dart';
import '../widgets/koala_widgets.dart';
import '../widgets/chat/product_carousel.dart';
import 'chat_detail_screen.dart';

// Alias — gradually migrate to KoalaColors directly
class _K {
  static const surface = KoalaColors.bg;
  static const surfaceContainerLow = KoalaColors.surfaceAlt;
  static const surfaceContainer = KoalaColors.surfaceAlt;
  static const surfaceContainerLowest = KoalaColors.surface;
  static const outlineVariant = KoalaColors.border;
  static const onSurface = KoalaColors.text;
  static const onSurfaceVariant = KoalaColors.textSec;
  static const primary = KoalaColors.accent;
  static const primaryContainer = KoalaColors.accent;
}

class _ChipOption {
  final String emoji;
  final String label;

  const _ChipOption(this.emoji, this.label);
}

class _DiscoveryCard {
  final Map<String, dynamic> project;
  final Map<String, dynamic>? designer;
  final int productCount;
  final String badge;
  final String reason;
  final double? rating;

  const _DiscoveryCard({
    required this.project,
    required this.designer,
    required this.productCount,
    required this.badge,
    required this.reason,
    this.rating,
  });
}

class _ConversationTurn {
  final String area;
  final String userMessage;
  String assistantText;
  List<_DiscoveryCard> cards;
  List<String> prompts;
  bool isLoading;
  bool isComplete;
  final int replyKey;
  List<ProductCarouselItem> products; // SerpAPI ürün sonuçları

  _ConversationTurn({
    required this.area,
    required this.userMessage,
    required this.assistantText,
    required this.cards,
    required this.prompts,
    required this.isLoading,
    required this.isComplete,
    required this.replyKey,
    List<ProductCarouselItem>? products,
  }) : products = products ?? [];
}

class ProductEntryScreen extends StatefulWidget {
  const ProductEntryScreen({super.key});

  @override
  State<ProductEntryScreen> createState() => _ProductEntryScreenState();
}

class _ProductEntryScreenState extends State<ProductEntryScreen> {
  // Chip'ler dinamik oluşturulacak (DB'deki gerçek oda tiplerine göre)
  List<_ChipOption> _chips = <_ChipOption>[];

  static const _roomEmojis = <String, String>{
    'Oturma Odası': '🛋️',
    'Salon': '🛋️',
    'Yatak Odası': '🛏️',
    'Mutfak': '🍳',
    'Banyo': '🛁',
    'Antre': '🚪',
  };

  final TextEditingController _input = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_DiscoveryCard> _allCards = <_DiscoveryCard>[];
  final List<_DiscoveryCard> _cards = <_DiscoveryCard>[];
  final List<_ConversationTurn> _turns = <_ConversationTurn>[];

  // Kullanıcının stil profili (style discovery'den)
  String? _userStyle;
  String? _userRoom;
  String? _userBudget;
  List<String> _userColors = [];

  bool _loading = true;
  final bool _fetchingReply = false;
  bool _showCards = false;
  String? _error;
  String? _selectedArea;
  String? _userMessage;
  int _replyKey = 0;

  String _projectInquiryText(_DiscoveryCard card, {String? customMessage}) {
    final title = (card.project['title'] ?? 'bu proje').toString().trim();
    final designerName = (card.designer?['full_name'] ?? 'tasarımcı').toString().trim();
    final userNote = customMessage?.trim() ?? '';
    final base =
        '$title projesi için $designerName ile iletişime geçmek istiyorum. Bu proje ve kullanılan ürünler hakkında beni yönlendir.';
    if (userNote.isEmpty) return base;
    return '$base Kullanıcının notu: $userNote';
  }

  Future<void> _openProjectChat(_DiscoveryCard card, {String? customMessage}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          initialText: _projectInquiryText(card, customMessage: customMessage),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadUserPreferences();
    _loadProjects();
  }

  Future<void> _loadUserPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _userStyle = prefs.getString('onb_style');
    _userRoom = prefs.getString('onb_room');
    _userBudget = prefs.getString('onb_budget');
    _userColors = prefs.getStringList('onb_colors') ?? [];
  }

  @override
  void dispose() {
    _input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    if (!EvlumbaLiveService.isReady) {
      setState(() {
        _loading = false;
        _error = 'Bağlantı hazır değil.';
      });
      _scrollToBottom();
      return;
    }

    try {
      // Makul havuz — bellek dostu, her alan için yeterli
      final projects = await EvlumbaLiveService.getProjects(limit: 30);

      // Her designer'ı sadece bir kez çek
      final designerCache = <String, Map<String, dynamic>?>{};

      final cards = await Future.wait(
        projects.map((project) async {
          final next = Map<String, dynamic>.from(project);
          final designerId = (project['designer_id'] ?? '').toString();
          final projectId = (project['id'] ?? '').toString();

          Map<String, dynamic>? designer;
          List<Map<String, dynamic>> products = <Map<String, dynamic>>[];

          if (designerId.isNotEmpty) {
            if (designerCache.containsKey(designerId)) {
              designer = designerCache[designerId];
            } else {
              try {
                designer = await EvlumbaLiveService.getDesigner(designerId);
                designerCache[designerId] = designer;
              } catch (_) {}
            }
            if (designer != null) next['profiles'] = designer;
          }

          if (projectId.isNotEmpty) {
            try {
              products = await EvlumbaLiveService.getProjectShopLinks(projectId);
            } catch (_) {}
          }

          return _DiscoveryCard(
            project: next,
            designer: designer,
            productCount: products.length,
            badge: _badgeForProject(next, designer),
            reason: _reasonForArea(
              area: _guessArea(next),
              designer: designer,
              productCount: products.length,
            ),
            rating: null, // Gerçek review sistemi yokken sahte rating gösterme
          );
        }),
      );

      if (!mounted) return;

      // DB'deki gerçek oda tiplerine göre dinamik chip oluştur
      final roomCounts = <String, int>{};
      for (final project in projects) {
        final pt = (project['project_type'] ?? '').toString().trim();
        if (pt.isNotEmpty) {
          roomCounts[pt] = (roomCounts[pt] ?? 0) + 1;
        }
      }

      final dynamicChips = <_ChipOption>[];
      // Kullanıcının tercih ettiği odayı önce koy
      final roomKeyToType = <String, String>{
        'salon': 'Oturma Odası',
        'yatak_odasi': 'Yatak Odası',
        'banyo': 'Banyo',
        'mutfak': 'Mutfak',
        'antre': 'Antre',
      };
      String? userPreferredType;
      if (_userRoom != null && roomKeyToType.containsKey(_userRoom)) {
        userPreferredType = roomKeyToType[_userRoom];
      }

      final sortedRooms = roomCounts.entries.toList()
        ..sort((a, b) {
          // Kullanıcının tercih ettiği oda en üste
          if (a.key == userPreferredType) return -1;
          if (b.key == userPreferredType) return 1;
          return b.value.compareTo(a.value);
        });

      for (final entry in sortedRooms) {
        if (entry.value >= 3) {
          final label = entry.key == 'Oturma Odası' ? 'Salon' : entry.key;
          final emoji = _roomEmojis[entry.key] ?? _roomEmojis[label] ?? '🏠';
          dynamicChips.add(_ChipOption(emoji, label));
        }
      }

      setState(() {
        _allCards
          ..clear()
          ..addAll(cards);
        _chips = dynamicChips;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  static String _normalize(String raw) {
    const source = 'çğıöşüÇĞİÖŞÜ';
    const target = 'cgiosuCGIOSU';
    var result = raw.trim();
    for (var i = 0; i < source.length; i++) {
      result = result.replaceAll(source[i], target[i]);
    }
    return result.toLowerCase();
  }

  static String _badgeForProject(
    Map<String, dynamic> project,
    Map<String, dynamic>? designer,
  ) {
    final type = (project['project_type'] ?? '').toString().trim();
    if (type.isNotEmpty) return type;
    if (designer != null) return 'İlham';
    return 'Seçki';
  }

  static String _guessArea(Map<String, dynamic> project) {
    final type = _normalize((project['project_type'] ?? '').toString());
    final title = _normalize((project['title'] ?? '').toString());
    final desc = _normalize((project['description'] ?? '').toString());
    final combined = '$type $title $desc';

    if (combined.contains('yatak')) return 'Yatak Odası';
    if (combined.contains('mutfak')) return 'Mutfak';
    if (combined.contains('banyo')) return 'Banyo';
    if (combined.contains('antre') || combined.contains('giris')) return 'Antre';
    if (combined.contains('oturma') || combined.contains('salon')) return 'Salon';
    // project_type alanı doğrudan kontrol
    final rawType = (project['project_type'] ?? '').toString().trim();
    if (rawType == 'Oturma Odası') return 'Salon';
    if (rawType == 'Banyo') return 'Banyo';
    if (rawType == 'Antre') return 'Antre';
    return 'Salon';
  }

  static String _reasonForArea({
    required String area,
    required Map<String, dynamic>? designer,
    required int productCount,
  }) {
    if (area == 'Yatak Odası') {
      return 'Sakin tonlar, yumuşak yüzeyler ve güvenli oranlar burada daha dinlenmiş bir his kuruyor.';
    }
    if (area == 'Mutfak') {
      return 'Net yüzeyler ve kontrollü yerleşim, mutfakta ferahlık ve kullanım kolaylığını birlikte taşıyor.';
    }
    if (area == 'Banyo') {
      return 'Temiz çizgiler ve fonksiyonel yerleşim, banyoda ferahlık ve düzen hissini güçlendiriyor.';
    }
    if (productCount > 0) {
      return 'Bu yön, uygulanabilir ürün diliyle daha güçlü; istersen ürünleri tek tek de çıkarabilirim.';
    }
    final name = (designer?['full_name'] ?? '').toString().trim();
    if (name.isNotEmpty) {
      return '$name çizgisine yakın, dengeli ve uygulanabilir bir yön seçtim.';
    }
    return 'Bu kompozisyon, alanın için dengeli ve güvenli bir başlangıç sunuyor.';
  }

  String _coverFor(Map<String, dynamic> project) {
    for (final key in ['cover_image_url', 'cover_url', 'image_url']) {
      final value = (project[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }

    final images = (project['designer_project_images'] as List?)
        ?.whereType<Map>()
        .toList();
    if (images == null || images.isEmpty) return '';

    images.sort(
      (a, b) => ((a['sort_order'] as num?)?.toInt() ?? 9999)
          .compareTo((b['sort_order'] as num?)?.toInt() ?? 9999),
    );
    return (images.first['image_url'] ?? '').toString();
  }

  void _pickArea(String label, String userMessage, {bool excludePrev = false}) {
    HapticFeedback.lightImpact();
    final turn = _ConversationTurn(
      area: label,
      userMessage: userMessage,
      assistantText: _assistantIntroTextFor(label),
      cards: <_DiscoveryCard>[],
      prompts: <String>[],
      isLoading: true,
      isComplete: false,
      replyKey: _replyKey++,
    );
    setState(() {
      _selectedArea = label;
      _turns.add(turn);
    });
    _scrollToBottom();
    _loadReplyFor(turn, excludePrev: excludePrev);
  }

  Future<void> _loadReplyFor(_ConversationTurn turn, {bool excludePrev = false}) async {
    // Ürün arama isteği mi kontrol et
    final isProductSearch = _isProductSearchQuery(turn.userMessage);

    if (isProductSearch) {
      // SerpAPI'den ürün ara
      await _searchProducts(turn);
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 850));
    if (!mounted) return;

    final matches = _filterCards(turn.area, excludePrev: excludePrev);
    setState(() {
      turn.cards
        ..clear()
        ..addAll(matches);
      turn.assistantText = _contextualAssistantReply(turn.area, matches);
      turn.prompts = _smartPrompts(
        turn.area,
        matches.any((card) => card.productCount > 0),
      );
      turn.isLoading = false;
    });
  }

  bool _isProductSearchQuery(String text) {
    final lower = _normalize(text);
    const productKeywords = [
      'abajur', 'koltuk', 'masa', 'sandalye', 'sehpa', 'tv', 'lamba',
      'perde', 'hali', 'ayna', 'raf', 'dolap', 'yatak', 'komodin',
      'aksesuar', 'dekor', 'vazo', 'kirlent', 'yastik', 'avize',
      'mobilya', 'urun', 'oner', 'bul', 'ara', 'getir', 'goster',
      'butce', 'tl', 'fiyat', 'ucuz', 'pahali', 'indirim',
    ];
    int matchCount = 0;
    for (final keyword in productKeywords) {
      if (lower.contains(keyword)) matchCount++;
    }
    return matchCount >= 2;
  }

  /// Kullanıcı mesajından arama query'si çıkar (fiiller, bütçe kısmı temizlenir)
  String _extractSearchQuery(String text) {
    var query = text.toLowerCase();
    // Bütçe kısmını çıkar (ör: "1500 TL bütçe", "2000 lira")
    query = query.replaceAll(RegExp(r'\d[\d.]*\s*(?:tl|lira)\s*(?:butce|bütçe)?'), '');
    // Fiilleri ve gereksiz kelimeleri çıkar
    const removeWords = [
      'oner', 'öner', 'bul', 'ara', 'getir', 'goster', 'göster',
      'istiyorum', 'lazim', 'lazım', 'ariyorum', 'arıyorum',
      'butce', 'bütçe', 'icin', 'için', 'salon', 'yatak', 'odasi', 'odası',
      'mutfak', 'banyo', 'antre', 'bana', 'benim', 'lütfen', 'lutfen',
    ];
    for (final word in removeWords) {
      query = query.replaceAll(RegExp('\\b$word\\b'), '');
    }
    query = query.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Çok kısaysa orijinal mesajı kullan
    if (query.length < 3) query = text;
    return query;
  }

  Future<void> _searchProducts(_ConversationTurn turn) async {
    try {
      // Bütçe çıkar
      num? maxPrice;
      final priceMatch = RegExp(r'(\d[\d.]*)\s*(?:tl|lira)', caseSensitive: false)
          .firstMatch(turn.userMessage);
      if (priceMatch != null) {
        maxPrice = num.tryParse(priceMatch.group(1)!.replaceAll('.', ''));
      }

      // Query'yi temizle
      final cleanQuery = _extractSearchQuery(turn.userMessage);
      debugPrint('ProductEntry: searching "$cleanQuery", max_price=$maxPrice');

      final result = await KoalaToolHandler.handle('search_products', {
        'query': cleanQuery,
        'room_type': turn.area,
        if (maxPrice != null) 'max_price': maxPrice,
        'limit': 4,
      });

      if (!mounted) return;

      final productsRaw = (result['products'] as List?) ?? [];
      final products = productsRaw
          .map((p) => ProductCarouselItem.fromCardData(p as Map<String, dynamic>))
          .toList();

      setState(() {
        turn.products = products;
        turn.cards.clear(); // Ürün arandığında projeler gösterme
        turn.assistantText = products.isNotEmpty
            ? 'Senin için ${products.length} ürün buldum! İşte ${turn.area.toLowerCase()} için en uygun seçenekler:'
            : 'Maalesef bu kriterlere uygun ürün bulamadım. Farklı bir arama dene!';
        turn.prompts = [
          '🔄 Farklı ürünler göster',
          '💰 Daha uygun fiyatlı seçenekler',
          '🏠 Başka bir alan seçmek istiyorum',
        ];
        turn.isLoading = false;
      });
    } catch (e) {
      debugPrint('ProductEntry: search error: $e');
      if (!mounted) return;
      setState(() {
        turn.cards.clear();
        turn.assistantText = 'Ürün ararken bir sorun oluştu. Tekrar dene!';
        turn.prompts = ['🔄 Tekrar dene', '🏠 Başka bir alan seçmek istiyorum'];
        turn.isLoading = false;
      });
    }
  }

  List<_DiscoveryCard> _filterCards(String area, {bool excludePrev = false}) {
    final normalized = _normalize(area);
    final rng = Random();

    // Alanla eşleşen projeleri bul
    final filtered = _allCards.where((card) {
      final guessed = _normalize(_guessArea(card.project));
      if (normalized.contains('yatak')) return guessed.contains('yatak');
      if (normalized.contains('mutfak')) return guessed.contains('mutfak');
      if (normalized.contains('salon') || normalized.contains('oturma')) {
        return guessed.contains('salon');
      }
      if (normalized.contains('banyo')) return guessed.contains('banyo');
      if (normalized.contains('antre')) return guessed.contains('antre');
      return true;
    }).toList();

    var candidates = filtered.isEmpty ? List<_DiscoveryCard>.from(_allCards) : filtered;

    // Önceki turnlarda gösterilen projeleri hariç tut
    if (excludePrev && _turns.isNotEmpty) {
      final prevIds = <String>{};
      for (final turn in _turns.reversed.take(3)) {
        for (final card in turn.cards) {
          final id = (card.project['id'] ?? '').toString();
          if (id.isNotEmpty) prevIds.add(id);
        }
      }
      final fresh = candidates
          .where((c) => !prevIds.contains((c.project['id'] ?? '').toString()))
          .toList();
      if (fresh.length >= 2) candidates = fresh;
    }

    // Stil profili ile skorlama
    final scored = candidates.map((card) {
      var score = 0.0;

      // Ürünü olan projelere bonus
      score += card.productCount * 3;

      // Rating bonusu
      score += card.rating ?? 0;

      // Kullanıcının tercih ettiği oda ile eşleşme bonusu
      if (_userRoom != null && _userRoom!.isNotEmpty) {
        final cardArea = _normalize(_guessArea(card.project));
        final roomMap = {
          'salon': 'salon', 'yatak_odasi': 'yatak',
          'banyo': 'banyo', 'mutfak': 'mutfak', 'antre': 'antre',
        };
        final userRoomNorm = roomMap[_userRoom] ?? _userRoom!;
        if (cardArea.contains(userRoomNorm)) score += 4;
      }

      // Proje açıklamasında stil anahtar kelimeleri eşleştir
      if (_userStyle != null && _userStyle!.isNotEmpty) {
        final desc = _normalize(
          '${card.project['description'] ?? ''} ${card.project['title'] ?? ''}',
        );
        final styleKeywords = <String, List<String>>{
          'modern': ['modern', 'minimal', 'cagdas', 'contemporary'],
          'minimalist': ['minimal', 'sade', 'temiz', 'pure'],
          'scandinavian': ['iskandinav', 'skandinav', 'nordic', 'beyaz'],
          'bohemian': ['bohem', 'bohemian', 'eklektik', 'renkli'],
          'industrial': ['endustriyel', 'industrial', 'loft', 'metal'],
          'japandi': ['japandi', 'japon', 'zen', 'dogal'],
          'classic': ['klasik', 'classic', 'geleneksel', 'elegans'],
          'luxury': ['luks', 'premium', 'luxury', 'marmer'],
        };
        final keywords = styleKeywords[_userStyle] ?? [_userStyle!];
        for (final kw in keywords) {
          if (desc.contains(kw)) {
            score += 5;
            break;
          }
        }
      }

      // Küçük rastgelelik (aynı skor grubunda çeşitlilik)
      score += rng.nextDouble() * 2;

      return MapEntry(card, score);
    }).toList();

    scored.sort((a, b) => b.value.compareTo(a.value));

    return scored.take(5).map((entry) {
      final card = entry.key;
      return _DiscoveryCard(
        project: card.project,
        designer: card.designer,
        productCount: card.productCount,
        badge: _badgeForProject(card.project, card.designer),
        reason: _reasonForArea(
          area: area,
          designer: card.designer,
          productCount: card.productCount,
        ),
        rating: card.rating,
      );
    }).toList();
  }

  String _assistantIntroText([String? area]) {
    final currentArea = area ?? _selectedArea ?? 'Salon';
    if (currentArea == 'Mutfak') {
      return 'Mutfak için ferahlığı ve kullanım rahatlığını birlikte taşıyan iki güçlü yön seçtim.';
    }
    if (_selectedArea == 'Yatak Odası') {
      return 'Yatak odası için sakinlik, doku dengesi ve kalite hissi güçlü duran iki yön seçtim.';
    }
    if (_selectedArea == 'Fotoğraf çekeyim') {
      return 'Fotoğrafını aldıktan sonra alanını daha doğru okuyup sana daha isabetli yönler çıkaracağım.';
    }
    return 'Salon için dengeli, uygulanabilir ve gözü yormayan iki güçlü yön seçtim.';
  }

  String _assistantIntroTextFor(String area) {
    if (_normalize(area).contains('mutfak')) {
      return 'Mutfak için ferahlığı ve kullanım rahatlığını birlikte taşıyan iki güçlü yön seçtim.';
    }
    if (_normalize(area).contains('yatak')) {
      return 'Yatak odası için sakinlik, doku dengesi ve kalite hissi güçlü duran iki yön seçtim.';
    }
    if (_normalize(area).contains('foto')) {
      return 'Fotoğrafını aldıktan sonra alanını daha doğru okuyup sana daha isabetli yönler çıkaracağım.';
    }
    return 'Salon için dengeli, uygulanabilir ve gözü yormayan iki güçlü yön seçtim.';
  }

  String _contextualAssistantReply(String area, List<_DiscoveryCard> matches) {
    if (matches.isEmpty) return _assistantIntroTextFor(area);

    final firstTitle = (matches.first.project['title'] ?? 'bu yön').toString().trim();
    final secondTitle = matches.length > 1
        ? (matches[1].project['title'] ?? '').toString().trim()
        : '';
    final strongProductSet = matches.where((card) => card.productCount > 0).length;

    // Stil profili varsa kişiselleştirilmiş not ekle
    final styleNote = _userStyle != null && _userStyle!.isNotEmpty
        ? ' Senin stil profiline göre en uyumlu olanları öne aldım.'
        : '';

    if (_normalize(area).contains('mutfak')) {
      return secondTitle.isNotEmpty
          ? 'Mutfak için biri daha ferah, diğeri daha karakterli duran iki ana yön seçtim: $firstTitle ve $secondTitle.$styleNote'
          : 'Mutfak için ilk bakmanı istediğim yön $firstTitle.$styleNote';
    }
    if (_normalize(area).contains('yatak')) {
      return secondTitle.isNotEmpty
          ? 'Yatak odasında sakinlik hissi en iyi çalışan iki yön öne çıktı: $firstTitle ve $secondTitle.$styleNote'
          : 'Yatak odası için en sakin ve güvenli his veren yön $firstTitle oldu.$styleNote';
    }
    if (_normalize(area).contains('banyo')) {
      return secondTitle.isNotEmpty
          ? 'Banyo için temiz çizgileri ve fonksiyonel yerleşimi güçlü duran iki yön: $firstTitle ve $secondTitle.$styleNote'
          : 'Banyo için ilk bakmanı istediğim yön $firstTitle.$styleNote';
    }
    return strongProductSet > 0
        ? 'Alanın için ürün dili güçlü duran ${matches.length} öneri süzdüm. İlk bakmanı istediğim yön $firstTitle.$styleNote'
        : 'Alanın için dengeli duran ${matches.length} öneri süzdüm. İlk bakmanı istediğim yön $firstTitle.$styleNote';
  }

  void _submit() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();

    final normalizedText = _normalize(text);
    final resolvedArea = _resolveArea(text);

    // Oda alanı tespit edilemezse → son aktif bağlamı kullan, yoksa bilgilendir
    final effectiveArea = resolvedArea
        ?? (_turns.isNotEmpty ? _turns.last.area : null);
    if (effectiveArea == null || effectiveArea == 'reset') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Lütfen bir oda tipi belirtin: Salon, Yatak Odası, Mutfak, Banyo, Antre…',
              style: const TextStyle(fontSize: 13),
            ),
            backgroundColor: const Color(0xFF4A6741),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // "Başka" / "farklı" gibi kelimeler varsa önceki sonuçları hariç tut
    final wantsDifferent = normalizedText.contains('baska') ||
        normalizedText.contains('farkli') ||
        normalizedText.contains('daha') ||
        normalizedText.contains('yeni');

    _pickArea(effectiveArea, text, excludePrev: wantsDifferent);
  }

  String? _resolveArea(String text) {
    final normalized = _normalize(text);
    if (normalized.contains('yatak')) return 'Yatak Odası';
    if (normalized.contains('mutfak')) return 'Mutfak';
    if (normalized.contains('banyo')) return 'Banyo';
    if (normalized.contains('antre') || normalized.contains('giris')) return 'Antre';
    if (normalized.contains('salon') || normalized.contains('oturma')) return 'Salon';
    if (normalized.contains('foto') || normalized.contains('fotograf')) {
      return 'Fotoğraf çekeyim';
    }
    return null;
  }

  void _onPromptTap(String prompt) {
    final normalizedPrompt = _normalize(prompt);
    final area = _selectedArea ?? 'Salon';

    // "Başka alan seçmek istiyorum" → inline chip'leri göster
    if (normalizedPrompt.contains('baska bir alan')) {
      HapticFeedback.lightImpact();
      final turn = _ConversationTurn(
        area: 'reset',
        userMessage: prompt,
        assistantText: 'Tabii, hangi alana bakmak istersin?',
        cards: <_DiscoveryCard>[],
        prompts: <String>[],
        isLoading: false,
        isComplete: true,
        replyKey: _replyKey++,
      );
      setState(() => _turns.add(turn));
      _scrollToBottom();
      return;
    }

    // "X önerileri göster" → oda değiştir
    if (normalizedPrompt.contains('onerileri goster')) {
      final resolvedArea = _resolveArea(prompt);
      if (resolvedArea != null) {
        _pickArea(resolvedArea, prompt);
        return;
      }
    }

    // "Başka projeler göster" / "farklı" / "daha" → önceki sonuçları hariç tut
    if (normalizedPrompt.contains('baska') ||
        normalizedPrompt.contains('farkli') ||
        normalizedPrompt.contains('daha')) {
      _pickArea(area, prompt, excludePrev: true);
      return;
    }

    // Ürün çıkar vb → aynı alan
    _pickArea(area, prompt);
  }

  Future<void> _openCard(_DiscoveryCard card) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.24),
      builder: (_) => _ProjectDetailSheet(
        card: card,
        onSendMessage: (message) => _openProjectChat(card, customMessage: message),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 220,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _K.surface,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                _topBar(context),
                Expanded(
                  child: _loading
                      ? const LoadingState()
                      : _error != null
                          ? _errorState()
                          : _content(),
                ),
              ],
            ),
            _bottomComposer(),
          ],
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Container(
      color: _K.surface,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).pop();
                },
                child: const Icon(
                  LucideIcons.arrowLeft,
                  size: 24,
                  color: KoalaColors.accent,
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                'Ürün Bul',
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _K.onSurface,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          const Text(
            'koala',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: KoalaColors.accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _content() => _chatContent();

  // ignore: unused_element
  Widget _legacyContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 126),
      children: [
        const _AssistantBubble(
          text:
              'Merhaba! Evini akıllıca tasarlamak için buradayım. Önce hangi alanına bakacağımızı seçelim.',
          lowSurface: true,
        ),
        const SizedBox(height: 22),
        if (_selectedArea == null)
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _chips.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final chip = _chips[index];
                return _AreaChip(
                  emoji: chip.emoji,
                  label: chip.label,
                  onTap: () => _pickArea(chip.label, '${chip.emoji} ${chip.label}'),
                );
              },
            ),
          )
        else
          _LockedAreaPill(
            emoji: _chips.firstWhere((chip) => chip.label == _selectedArea).emoji,
            label: _selectedArea!,
          ),
        if (_selectedArea != null) ...[
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerRight,
            child: _UserBubble(text: _userMessage ?? _selectedArea!),
          ),
          const SizedBox(height: 24),
          if (_fetchingReply)
            const _TypingBubble()
          else ...[
            _TypewriterBubble(
              key: ValueKey(_replyKey),
              text: _assistantIntroText(),
              onComplete: () {
                if (!mounted) return;
                setState(() => _showCards = true);
              },
            ),
            if (_showCards) ...[
              const SizedBox(height: 24),
              ..._cards.asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: _EntranceItem(
                        index: entry.key,
                        child: _ProjectCard(
                          card: entry.value,
                          coverUrl: _coverFor(entry.value.project),
                          onTap: () => _openCard(entry.value),
                        ),
                      ),
                    ),
                  ),
              _EntranceItem(
                index: _cards.length,
                child: _PromptWrap(
                  prompts: _smartPrompts(
                    _selectedArea!,
                    _cards.any((card) => card.productCount > 0),
                  ),
                  onTap: _onPromptTap,
                ),
              ),
            ],
          ],
        ],
      ],
    );
  }

  Widget _chatContent() {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 126),
      children: [
        const _AssistantBubble(
          text: 'Merhaba! Evini akıllıca tasarlamak için buradayım. Önce hangi alanına bakacağımızı seçelim.',
          lowSurface: true,
        ),
        const SizedBox(height: 22),
        if (_selectedArea == null)
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _chips.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final chip = _chips[index];
                return _AreaChip(
                  emoji: chip.emoji,
                  label: chip.label,
                  onTap: () => _pickArea(chip.label, '${chip.emoji} ${chip.label}'),
                );
              },
            ),
          ),
        if (_turns.isNotEmpty) const SizedBox(height: 24),
        ..._turns.asMap().entries.expand((entry) {
          final turn = entry.value;
          final isLastTurn = entry.key == _turns.length - 1;
          return <Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: _UserBubble(text: turn.userMessage),
            ),
            const SizedBox(height: 24),
            if (turn.isLoading)
              const _TypingBubble()
            else if (!turn.isComplete)
              _TypewriterBubble(
                key: ValueKey(turn.replyKey),
                text: turn.assistantText,
                onComplete: () {
                  if (!mounted || turn.isComplete) return;
                  setState(() => turn.isComplete = true);
                },
              )
            else
              _AssistantBubble(text: turn.assistantText),
            if (turn.isComplete) ...[
              const SizedBox(height: 24),
              // Alan seçim chip'leri (inline, chat içinde)
              if (turn.area == 'reset' && isLastTurn)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _chips.map((chip) {
                      return _AreaChip(
                        emoji: chip.emoji,
                        label: chip.label,
                        onTap: () => _pickArea(chip.label, '${chip.emoji} ${chip.label}'),
                      );
                    }).toList(),
                  ),
                ),
              if (turn.area != 'reset') ...[
                // SerpAPI ürün sonuçları varsa carousel göster
                if (turn.products.isNotEmpty)
                  _EntranceItem(
                    index: 0,
                    child: ProductCarousel(
                      title: 'Önerilen Ürünler',
                      products: turn.products,
                      onAskAI: (product, question) {
                        // Ürün hakkında soru sor
                        _pickArea(turn.area, '"${product.name}" hakkında: $question');
                      },
                    ),
                  ),
                if (turn.products.isNotEmpty) const SizedBox(height: 18),
                // Evlumba projeleri
                _EntranceItem(
                  index: turn.products.isNotEmpty ? 1 : 0,
                  child: _projectDeck(turn.cards),
                ),
                const SizedBox(height: 18),
                if (isLastTurn)
                  _EntranceItem(
                    index: 1,
                    child: _PromptWrap(
                      prompts: turn.prompts,
                      onTap: _onPromptTap,
                    ),
                  ),
              ],
              if (!isLastTurn) const SizedBox(height: 24),
            ],
            if (turn.isLoading || !turn.isComplete) const SizedBox(height: 24),
          ];
        }),
      ],
    );
  }

  Widget _projectDeck(List<_DiscoveryCard> cards) {
    if (cards.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 408,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (context, index) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final card = cards[index];
          return SizedBox(
            width: 316,
            child: _ProjectCard(
              card: card,
              coverUrl: _coverFor(card.project),
              onTap: () => _openCard(card),
            ),
          );
        },
      ),
    );
  }

  List<String> _smartPrompts(String area, bool hasProducts) {
    final prompts = <String>[];

    // Her zaman "başka proje göster" olsun
    prompts.add('Başka projeler göster');

    if (hasProducts) prompts.add('Ürünleri ayrı çıkar');

    // Alana ve stile göre bağlamsal öneriler
    if (area == 'Mutfak') {
      prompts.add('Daha sıcak tarz mutfak göster');
    } else if (area == 'Yatak Odası') {
      prompts.add('Daha sade yatak odası bul');
    } else if (area == 'Banyo') {
      prompts.add('Daha modern banyo göster');
    } else {
      prompts.add('Daha farklı tarz göster');
    }

    // Kullanıcının keşfetmediği odaları öner
    if (_userRoom != null) {
      final roomLabels = {'salon': 'Salon', 'yatak_odasi': 'Yatak Odası', 'banyo': 'Banyo', 'mutfak': 'Mutfak'};
      final currentNorm = _normalize(area);
      for (final entry in roomLabels.entries) {
        if (!currentNorm.contains(_normalize(entry.value)) && entry.key != _userRoom) {
          prompts.add('${entry.value} önerileri göster');
          break; // Sadece 1 tane farklı oda öner
        }
      }
    }

    prompts.add('Evimin başka bir alanını seçmek istiyorum');

    return prompts;
  }

  Widget _bottomComposer() {
    final bottom = MediaQuery.of(context).padding.bottom;
    final hasText = _input.text.trim().isNotEmpty;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 6, 16, bottom + 22),
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.06),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => _pickArea('Fotoğraf çekeyim', '📸 Fotoğraf çekeyim'),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.04),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.image,
                      size: 18,
                      color: _K.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _input,
                  textInputAction: TextInputAction.send,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: _selectedArea == null ? 'ürün keşfet...' : "Koala'ya sor...",
                    hintStyle: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: KoalaColors.textSec.withValues(alpha: 0.72),
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _K.onSurface,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _submit,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasText ? null : Colors.black.withValues(alpha: 0.04),
                      gradient: hasText
                          ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [KoalaColors.accent, KoalaColors.accentDark],
                            )
                          : null,
                    ),
                    child: Icon(
                      LucideIcons.arrowUp,
                      size: 18,
                      color: hasText ? Colors.white : _K.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.wifiOff,
              size: 36,
              color: _K.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Yüklenemedi',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _K.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntranceItem extends StatelessWidget {
  final Widget child;
  final int index;

  const _EntranceItem({
    required this.child,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + (index * 90)),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - value)),
            child: child,
          ),
        );
      },
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  final String text;
  final bool lowSurface;

  const _AssistantBubble({
    required this.text,
    this.lowSurface = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _K.primaryContainer.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.center,
          child: const Text('🐨', style: TextStyle(fontSize: 20)),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 312),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            decoration: BoxDecoration(
              color: lowSurface ? _K.surfaceContainerLow : _K.surfaceContainerLowest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(24),
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
              border: Border.all(
                color: _K.outlineVariant.withValues(alpha: lowSurface ? 0.10 : 0.15),
              ),
              boxShadow: lowSurface
                  ? null
                  : [
                      BoxShadow(
                        color: KoalaColors.ink.withValues(alpha: 0.04),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Koala AI',
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _K.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  text,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    height: 1.65,
                    fontWeight: FontWeight.w500,
                    color: _K.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TypewriterBubble extends StatefulWidget {
  final String text;
  final VoidCallback onComplete;

  const _TypewriterBubble({
    super.key,
    required this.text,
    required this.onComplete,
  });

  @override
  State<_TypewriterBubble> createState() => _TypewriterBubbleState();
}

class _TypewriterBubbleState extends State<_TypewriterBubble> {
  String _visible = '';
  int _index = 0;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _animate();
  }

  Future<void> _animate() async {
    while (mounted && _index < widget.text.length) {
      await Future<void>.delayed(const Duration(milliseconds: 12));
      if (!mounted) return;
      final next = (_index + 2).clamp(0, widget.text.length);
      setState(() {
        _index = next;
        _visible = widget.text.substring(0, _index);
      });
    }

    if (!_sent && mounted) {
      _sent = true;
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AssistantBubble(text: _visible);
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _K.primaryContainer.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.center,
          child: const Text('🐨', style: TextStyle(fontSize: 20)),
        ),
        const SizedBox(width: 12),
        Container(
          constraints: const BoxConstraints(minWidth: 84, maxWidth: 108),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            color: _K.surfaceContainerLowest,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(24),
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            border: Border.all(color: _K.outlineVariant.withValues(alpha: 0.15)),
            boxShadow: [
              BoxShadow(
                color: KoalaColors.ink.withValues(alpha: 0.04),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const _TypingDots(),
        ),
      ],
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final progress = (_controller.value - (index * 0.14)).clamp(0.0, 1.0);
            final opacity = 0.35 + ((1 - (progress - 0.5).abs() * 2) * 0.55);
            return Padding(
              padding: EdgeInsets.only(right: index == 2 ? 0 : 6),
              child: Opacity(
                opacity: opacity.clamp(0.22, 1.0),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _K.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _AreaChip extends StatelessWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;

  const _AreaChip({
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _K.primary.withValues(alpha: 0.82)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _K.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LockedAreaPill extends StatelessWidget {
  final String emoji;
  final String label;

  const _LockedAreaPill({
    required this.emoji,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: _K.primary,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: _K.primary.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  final String text;

  const _UserBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [KoalaColors.accentDark, KoalaColors.accentDeep],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(6),
        ),
        boxShadow: [
          BoxShadow(
            color: _K.primary.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Text(
        text,
        style: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          height: 1.45,
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final _DiscoveryCard card;
  final String coverUrl;
  final VoidCallback onTap;

  const _ProjectCard({
    required this.card,
    required this.coverUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final designerName = (card.designer?['full_name'] ?? 'Koala seçkisi').toString().trim();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _K.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _K.outlineVariant.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: SizedBox(
                height: 178,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _CardImage(url: coverUrl),
                    Positioned(
                      top: 16,
                      left: 16,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.26),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.18),
                              ),
                            ),
                            child: Text(
                              card.badge,
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (card.project['title'] ?? 'Modern salon').toString(),
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                height: 1.2,
                                fontWeight: FontWeight.w800,
                                color: _K.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    designerName,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.manrope(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _K.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: _K.outlineVariant,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                                if (card.rating != null) ...[
                                  const SizedBox(width: 8),
                                  const Icon(Icons.star_rounded, size: 16, color: _K.primary),
                                  const SizedBox(width: 2),
                                  Text(
                                    card.rating!.toStringAsFixed(1),
                                    style: GoogleFonts.manrope(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: _K.primary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (card.productCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: _K.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                LucideIcons.shoppingBag,
                                size: 18,
                                color: _K.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${card.productCount}',
                                style: GoogleFonts.manrope(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: _K.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _K.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _K.primary.withValues(alpha: 0.10)),
                    ),
                    child: Text(
                      '"${card.reason}"',
                      style: GoogleFonts.manrope(
                        fontSize: 12.5,
                        height: 1.48,
                        fontStyle: FontStyle.italic,
                        color: _K.primary,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Detayları İncele',
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _K.primary,
                        ),
                      ),
                      const Icon(
                        LucideIcons.chevronRight,
                        size: 18,
                        color: _K.primary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardImage extends StatelessWidget {
  final String url;

  const _CardImage({required this.url});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Container(
        color: _K.surfaceContainer,
        alignment: Alignment.center,
        child: const Icon(LucideIcons.image, size: 28, color: _K.onSurfaceVariant),
      );
    }

    return Container(
      color: _K.surfaceContainer,
      alignment: Alignment.center,
      child: Image.network(
        url,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: _K.surfaceContainer,
            alignment: Alignment.center,
            child: const Icon(LucideIcons.image, size: 28, color: _K.onSurfaceVariant),
          );
        },
      ),
    );
  }
}

class _PromptWrap extends StatelessWidget {
  final List<String> prompts;
  final ValueChanged<String> onTap;

  const _PromptWrap({
    required this.prompts,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: prompts.map((prompt) {
        return GestureDetector(
          onTap: () => onTap(prompt),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _K.outlineVariant.withValues(alpha: 0.30)),
            ),
            child: Text(
              prompt,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _K.onSurface,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ProjectDetailSheet extends StatefulWidget {
  final _DiscoveryCard card;
  final ValueChanged<String> onSendMessage;

  const _ProjectDetailSheet({
    required this.card,
    required this.onSendMessage,
  });

  @override
  State<_ProjectDetailSheet> createState() => _ProjectDetailSheetState();
}

class _ProjectDetailSheetState extends State<_ProjectDetailSheet> {
  List<Map<String, dynamic>> _images = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _shopLinks = <Map<String, dynamic>>[];
  final TextEditingController _messageController = TextEditingController();
  final DraggableScrollableController _sheetCtrl = DraggableScrollableController();
  bool _loading = true;

  Map<String, dynamic> get _project => widget.card.project;
  Map<String, dynamic>? get _designer =>
      widget.card.designer ?? _project['profiles'] as Map<String, dynamic>?;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _sheetCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = (_project['id'] ?? '').toString();
    if (id.isEmpty || !EvlumbaLiveService.isReady) {
      setState(() => _loading = false);
      return;
    }

    try {
      final images = await EvlumbaLiveService.getProjectImages(id);
      final links = await EvlumbaLiveService.getProjectShopLinks(id);
      if (!mounted) return;
      setState(() {
        _images = images;
        _shopLinks = links;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _coverUrl() {
    for (final key in ['cover_image_url', 'cover_url', 'image_url']) {
      final value = (_project[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    final sorted = List<Map<String, dynamic>>.from(_images)
      ..sort(
        (a, b) => ((a['sort_order'] as num?)?.toInt() ?? 9999).compareTo(
          (b['sort_order'] as num?)?.toInt() ?? 9999,
        ),
      );
    if (sorted.isEmpty) return '';
    return (sorted.first['image_url'] ?? '').toString().trim();
  }

  void _submitMessage() {
    final message = _messageController.text.trim();
    _messageController.clear();
    widget.onSendMessage(message);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final title = (_project['title'] ?? 'Proje Detayı').toString();
    final coverUrl = _coverUrl();
    final designerName = (_designer?['full_name'] ?? 'Koala seçkisi').toString().trim();
    final designerAvatar = (_designer?['avatar_url'] ?? '').toString().trim();
    final specialty = (_designer?['specialty'] ?? 'İç Mimarlık ve Dekorasyon Uzmanı')
        .toString()
        .trim();

    // Klavye açıldığında sheet'i büyüt
    if (media.viewInsets.bottom > 0 &&
        _sheetCtrl.isAttached &&
        _sheetCtrl.size < 0.9) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_sheetCtrl.isAttached) {
          _sheetCtrl.animateTo(
            0.94,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }

    return DraggableScrollableSheet(
      controller: _sheetCtrl,
      expand: false,
      minChildSize: 0.58,
      initialChildSize: 0.82,
      maxChildSize: 0.94,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: _K.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Stack(
            children: [
              CustomScrollView(
                controller: controller,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        12,
                        20,
                        (media.viewInsets.bottom > 0
                                ? media.viewInsets.bottom + 16
                                : media.padding.bottom + 36),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 54,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(28),
                                child: SizedBox(
                                  height: 220,
                                  width: double.infinity,
                                  child: coverUrl.isEmpty
                                      ? Container(
                                          color: _K.surfaceContainer,
                                          alignment: Alignment.center,
                                          child: const Icon(
                                            LucideIcons.image,
                                            size: 36,
                                            color: _K.onSurfaceVariant,
                                          ),
                                        )
                                      : Image.network(
                                          coverUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            color: _K.surfaceContainer,
                                            alignment: Alignment.center,
                                            child: const Icon(
                                              LucideIcons.image,
                                              size: 36,
                                              color: _K.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(28),
                                    gradient: const LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [Colors.transparent, Color(0x66000000)],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 30,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: GoogleFonts.manrope(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                          color: _K.onSurface,
                                          height: 1.15,
                                        ),
                                      ),
                                    ),
                                    if (widget.card.rating != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                        decoration: BoxDecoration(
                                          color: _K.surfaceContainerLow,
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.star_rounded, size: 16, color: _K.primary),
                                            const SizedBox(width: 4),
                                            Text(
                                              widget.card.rating!.toStringAsFixed(1),
                                              style: GoogleFonts.manrope(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                                color: _K.onSurface,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    _DesignerAvatar(url: designerAvatar, name: designerName),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        designerName,
                                        style: GoogleFonts.manrope(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: _K.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _InsightPanel(reason: widget.card.reason),
                          const SizedBox(height: 16),
                          _DesignerContactCard(
                            designerName: designerName,
                            specialty: specialty.isEmpty ? 'İç Mimarlık ve Dekorasyon Uzmanı' : specialty,
                            avatarUrl: designerAvatar,
                            controller: _messageController,
                            onSubmit: _submitMessage,
                          ),
                          if (_shopLinks.isNotEmpty) ...[
                            const SizedBox(height: 22),
                            Text(
                              'Kullanılan Ürünler',
                              style: GoogleFonts.manrope(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: _K.onSurface,
                              ),
                            ),
                            const SizedBox(height: 14),
                            ..._shopLinks.take(4).map(
                                  (link) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _ProductListTile(shopLink: link),
                                  ),
                                ),
                          ],
                          if (_loading) ...[
                            const SizedBox(height: 12),
                            const Center(
                              child: CircularProgressIndicator(
                                color: _K.primary,
                                strokeWidth: 2,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InsightPanel extends StatelessWidget {
  final String reason;

  const _InsightPanel({required this.reason});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: KoalaColors.accentSoft,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _K.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Icon(LucideIcons.sparkles, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Text(
                'Koala AI Tavsiyesi',
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _K.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            reason,
            style: GoogleFonts.manrope(
              fontSize: 14,
              height: 1.6,
              color: _K.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DesignerContactCard extends StatelessWidget {
  final String designerName;
  final String specialty;
  final String avatarUrl;
  final TextEditingController controller;
  final VoidCallback onSubmit;

  const _DesignerContactCard({
    required this.designerName,
    required this.specialty,
    required this.avatarUrl,
    required this.controller,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tasarımcıyla İletişime Geç',
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: KoalaColors.textSec,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _DesignerAvatar(url: avatarUrl, name: designerName, size: 54),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      designerName,
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _K.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      specialty,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: KoalaColors.textTer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: _K.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.black.withValues(alpha: 0.05), width: 0.5),
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                const Icon(LucideIcons.messageCircle, size: 18, color: _K.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSubmit(),
                    scrollPadding: const EdgeInsets.only(bottom: 120),
                    decoration: InputDecoration(
                      hintText: '$designerName için mesaj yaz...',
                      hintStyle: GoogleFonts.manrope(
                        fontSize: 14,
                        color: KoalaColors.textSec.withValues(alpha: 0.74),
                      ),
                      border: InputBorder.none,
                    ),
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _K.onSurface,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onSubmit,
                  child: Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [KoalaColors.accent, KoalaColors.accentDark],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(LucideIcons.arrowUp, size: 18, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductListTile extends StatelessWidget {
  final Map<String, dynamic> shopLink;

  const _ProductListTile({required this.shopLink});

  @override
  Widget build(BuildContext context) {
    final title = (shopLink['product_title'] ?? 'Ürün').toString();
    final price = (shopLink['product_price'] ?? '').toString();
    final imageUrl = (shopLink['product_image_url'] ?? '').toString().trim();
    final productUrl = (shopLink['product_url'] ?? '').toString().trim();

    return GestureDetector(
      onTap: () async {
        if (productUrl.isNotEmpty) {
          await launchUrl(Uri.parse(productUrl), mode: LaunchMode.inAppBrowserView);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 84,
                height: 84,
                child: imageUrl.isEmpty
                    ? Container(
                        color: _K.surfaceContainerLow,
                        alignment: Alignment.center,
                        child: const Icon(LucideIcons.shoppingBag, color: _K.onSurfaceVariant),
                      )
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: _K.surfaceContainerLow,
                          alignment: Alignment.center,
                          child: const Icon(LucideIcons.shoppingBag, color: _K.onSurfaceVariant),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _K.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (price.isNotEmpty)
                    Text(
                      price,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _K.primary,
                      ),
                    ),
                ],
              ),
            ),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _K.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(LucideIcons.plus, size: 18, color: _K.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesignerAvatar extends StatelessWidget {
  final String url;
  final String name;
  final double size;

  const _DesignerAvatar({
    required this.url,
    required this.name,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _K.primary.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        image: url.isNotEmpty ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover) : null,
      ),
      alignment: Alignment.center,
      child: url.isEmpty
          ? Text(
              name.isEmpty ? 'K' : name.characters.first.toUpperCase(),
              style: GoogleFonts.manrope(
                fontSize: size * 0.34,
                fontWeight: FontWeight.w800,
                color: _K.primary,
              ),
            )
          : null,
    );
  }
}
