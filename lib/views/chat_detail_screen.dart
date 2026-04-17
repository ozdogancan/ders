import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/koala_ai_service.dart';
import '../services/koala_image_service.dart';
import '../services/chat_persistence.dart';
import '../services/saved_plans_service.dart';
import '../services/analytics_service.dart';
import '../services/profile_feedback_service.dart';
import '../core/theme/koala_tokens.dart';
import '../services/evlumba_live_service.dart';
import '../services/saved_items_service.dart';
import '../widgets/chat/designer_chat_popup.dart';
import '../widgets/chat/product_carousel.dart';
import '../widgets/offline_banner.dart';
import '../widgets/projects_gallery_popup.dart';
import '../widgets/share_sheet.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../helpers/web_drop.dart' as web_drop;
import 'chat/widgets/chat_widgets.dart';

const _accent = KoalaColors.accentDeep;
const _accentLight = KoalaColors.accentSoft;
const _ink = KoalaColors.ink;

class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({
    super.key,
    this.initialText,
    this.initialPhoto,
    this.intent,
    this.intentParams,
    this.chatId,
    this.fromDiscovery = false,
    this.hiddenContext,
    this.testAssetPhoto = false,
  });

  final String? initialText;
  final Uint8List? initialPhoto;
  final KoalaIntent? intent;
  final Map<String, String>? intentParams;
  final String? chatId;
  final bool fromDiscovery;
  /// AI'a gönderilecek ama kullanıcıya gösterilmeyecek gizli bağlam
  /// (örn: görsel URL, tasarımcı bilgileri)
  final String? hiddenContext;

  /// true ise assets/images/test_room.webp'den test görseli yükler
  final bool testAssetPhoto;

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen>
    with TickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _picker = ImagePicker();
  final _ai = KoalaAIService();
  final _imgService = KoalaImageService();

  final List<_Msg> _msgs = [];
  final List<Map<String, String>> _history = [];
  Uint8List? _pendingPhoto;
  bool _loading = false;
  bool _showScrollToBottom = false;
  bool _isDragHovering = false;
  late String _chatId;
  String _chatTitle = 'Yeni Sohbet';

  /// Fotoğraf analizi sonrası bağlam — follow-up chip'lerde kullanılır
  Map<String, String>? _photoAnalysisContext;

  @override
  void initState() {
    super.initState();
    Analytics.screenViewed('chat_detail');
    _chatId = widget.chatId ?? 'chat_${DateTime.now().millisecondsSinceEpoch}';
    _loadUserPreferences();
    _scroll.addListener(_onScrollChanged);
    if (kIsWeb) {
      web_drop.registerWebDrop(
        onDrop: (bytes) {
          if (!mounted) return;
          setState(() => _pendingPhoto = bytes);
        },
        onHover: (hovering) {
          if (!mounted) return;
          setState(() => _isDragHovering = hovering);
        },
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.chatId != null) await _loadMessages();

      if (widget.fromDiscovery) {
        // Stil keşfinden döndü — köprü mesajı ile başla (kullanıcıya gösterme)
        _chatTitle = 'Stil Keşfi';
        _sendBridgeMessage(
          'Stil keşfimi tamamladım. Beğendiğim mekanları gördün. '
          'Tarzımı kısaca özetle ve bana uygun bir ilk öneri sun.',
        );
      } else if (widget.intent == KoalaIntent.photoAnalysis &&
          (widget.initialPhoto != null || widget.testAssetPhoto)) {
        // Photo analysis — send photo directly to AI
        _chatTitle = 'Fotoğraf Analizi';
        if (widget.testAssetPhoto) {
          // Load test image from bundled assets
          _loadTestAssetAndAnalyze();
        } else {
          _sendToAI(
            text: widget.initialText ?? 'Bu odayı analiz et',
            photo: widget.initialPhoto,
          );
        }
      } else if (widget.intent != null) {
        _chatTitle = _intentTitle(widget.intent!);
        _sendToAIWithIntent(
          intent: widget.intent!,
          params: widget.intentParams ?? {},
        );
      } else if (widget.initialText != null || widget.initialPhoto != null) {
        _sendToAI(
          text: widget.initialText,
          photo: widget.initialPhoto,
          hiddenContext: widget.hiddenContext,
        );
      }
    });
  }

  void _onScrollChanged() {
    if (!_scroll.hasClients) return;
    final distanceFromBottom =
        _scroll.position.maxScrollExtent - _scroll.offset;
    final shouldShow = distanceFromBottom > 200;
    if (shouldShow != _showScrollToBottom) {
      setState(() => _showScrollToBottom = shouldShow);
    }
  }

  @override
  void dispose() {
    if (kIsWeb) web_drop.unregisterWebDrop();
    _ai.dispose();
    _scroll.removeListener(_onScrollChanged);
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── Test asset photo loader ──
  Future<void> _loadTestAssetAndAnalyze() async {
    try {
      final data = await rootBundle.load('assets/images/test_room.webp');
      final bytes = data.buffer.asUint8List();
      _sendToAI(
        text: widget.initialText ?? 'Bu odayı analiz et',
        photo: bytes,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msgs.add(_Msg(
          role: 'koala',
          text: 'Test görseli yüklenemedi: $e',
        ));
      });
    }
  }

  // ── User Preferences → AI context ──
  Future<void> _loadUserPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final rawProfile = prefs.getString('koala_style_profile');
    String? style;
    String? room;
    String? budget;
    String? colors;

    String? dislikedStyles;
    String? dislikedColors;
    String? likedDetailsText;

    if (rawProfile != null && rawProfile.isNotEmpty) {
      try {
        final profile = jsonDecode(rawProfile) as Map<String, dynamic>;
        style =
            (profile['primary_style'] ?? profile['secondary_style'] ?? profile['style']) as String?;
        room = (profile['preferred_room'] ?? profile['room']) as String?;
        budget = (profile['budget_band'] ?? profile['budget']) as String?;
        final profileColors =
            ((profile['preferred_colors'] ?? profile['colors']) as List?)
                ?.cast<String>();
        if (profileColors != null && profileColors.isNotEmpty) {
          colors = profileColors.join(', ');
        }
        final ds = (profile['disliked_styles'] as List?)?.cast<String>();
        if (ds != null && ds.isNotEmpty) dislikedStyles = ds.join(', ');
        final dc = (profile['disliked_colors'] as List?)?.cast<String>();
        if (dc != null && dc.isNotEmpty) dislikedColors = dc.join(', ');

        final likedDetails = profile['liked_details'] as List?;
        if (likedDetails != null && likedDetails.isNotEmpty) {
          final lines = likedDetails.map((d) {
            final m = d as Map<String, dynamic>;
            final cardColors = (m['colors'] as List?)?.join(', ') ?? '';
            return '- ${m['title']} (${m['style']}, ${m['room']}, ${m['budget']}) — ${m['subtitle']}. Renkler: $cardColors';
          }).toList();
          likedDetailsText = lines.join('\n');
        }

        // Chat etkileşimlerinden güçlendirilen stil
        final reinforced = profile['reinforced_style'] as String?;
        if (reinforced != null && reinforced.isNotEmpty && reinforced != style) {
          style = '$style (son etkileşimlerde $reinforced de ilgisini çekiyor)';
        }
        final reinforcedColors = (profile['reinforced_colors'] as List?)?.cast<String>();
        if (reinforcedColors != null && reinforcedColors.isNotEmpty) {
          final extra = reinforcedColors.where((c) => !(colors ?? '').contains(c)).join(', ');
          if (extra.isNotEmpty) {
            colors = colors != null ? '$colors, $extra' : extra;
          }
        }
      } catch (_) {}
    }

    final legacyColors = prefs.getStringList('onb_colors');
    colors ??= legacyColors != null && legacyColors.isNotEmpty
        ? legacyColors.join(', ')
        : prefs.getString('onb_colors');

    final legacyDislikedStyles = prefs.getStringList('onb_disliked_styles');
    dislikedStyles ??= legacyDislikedStyles != null && legacyDislikedStyles.isNotEmpty
        ? legacyDislikedStyles.join(', ')
        : null;
    final legacyDislikedColors = prefs.getStringList('onb_disliked_colors');
    dislikedColors ??= legacyDislikedColors != null && legacyDislikedColors.isNotEmpty
        ? legacyDislikedColors.join(', ')
        : null;

    _ai.setUserPreferences(
      style: style ?? prefs.getString('onb_style'),
      colors: colors,
      room: room ?? prefs.getString('onb_room'),
      budget: budget ?? prefs.getString('onb_budget'),
      dislikedStyles: dislikedStyles,
      dislikedColors: dislikedColors,
      likedDetailsText: likedDetailsText,
    );
  }

  Future<void> _openStyleDiscovery() async {
    final result = await context.push(
      '/style-discovery',
      extra: {'entryPoint': 'chat'},
    );
    await _loadUserPreferences();
    if (!mounted) return;
    if (result == 'completed') {
      // Köprü mesajı: stil keşfi tamamlandı, AI'a öğrendiğini özetle ve ilk öneriyi ver
      _sendBridgeMessage(
        'Stil keşfimi tamamladım. Beğendiğim mekanları gördün. '
        'Tarzımı kısaca özetle ve bana uygun bir ilk öneri sun.',
      );
    } else if (result == 'skipped') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'İstersen bu stil ikonundan zevkini daha sonra da hızlıca anlatabilirsin.',
          ),
        ),
      );
    }
  }

  // ── Persistence ──
  Future<void> _loadMessages() async {
    final saved = await ChatPersistence.loadMessages(_chatId);
    for (final m in saved) {
      _msgs.add(
        _Msg(
          role: m['role'] as String? ?? 'koala',
          text: m['text'] as String?,
          cards: _parseCards(m['cards']),
        ),
      );
      if (m['text'] != null && (m['text'] as String).isNotEmpty) {
        _history.add({
          'role': m['role'] == 'user' ? 'user' : 'model',
          'content': m['text'] as String,
        });
      }
    }
    if (mounted) setState(() {});
    _scrollDown();
  }

  List<KoalaCard>? _parseCards(dynamic raw) {
    if (raw == null || raw is! List) return null;
    return (raw).map((c) {
      final m = c is Map<String, dynamic>
          ? c
          : Map<String, dynamic>.from(c as Map);
      return KoalaCard.fromJson(m);
    }).toList();
  }

  Future<void> _persist() async {
    final serialized = _msgs
        .where((m) => m.text != null || m.cards != null)
        .map(
          (m) => <String, dynamic>{
            'role': m.role,
            'text': m.text,
            'cards': m.cards?.map((c) => c.toJson()).toList(),
          },
        )
        .toList();
    await ChatPersistence.saveMessages(_chatId, serialized);
    final lastText = _msgs
        .lastWhere(
          (m) => m.text != null && m.text!.isNotEmpty,
          orElse: () => _Msg(role: 'koala'),
        )
        .text;
    await ChatPersistence.saveConversationSummary(
      ChatSummary(
        id: _chatId,
        title: _chatTitle,
        lastMessage: lastText,
        intent: widget.intent?.name,
        updatedAt: DateTime.now(),
      ),
    );
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _intentTitle(KoalaIntent intent) {
    switch (intent) {
      case KoalaIntent.styleExplore:
        return 'Stil Keşfet';
      case KoalaIntent.roomRenovation:
        return 'Oda Yenileme';
      case KoalaIntent.colorAdvice:
        return 'Renk Önerisi';
      case KoalaIntent.designerMatch:
        return 'Tasarımcı Bul';
      case KoalaIntent.budgetPlan:
        return 'Bütçe Planı';
      case KoalaIntent.beforeAfter:
        return 'Önce-Sonra';
      case KoalaIntent.pollResult:
        return 'Stil Testi';
      case KoalaIntent.photoAnalysis:
        return 'Fotoğraf Analizi';
      case KoalaIntent.freeChat:
        return 'Sohbet';
      case KoalaIntent.colorPaletteFromPhoto:
        return 'Renk Paleti';
      case KoalaIntent.styleAnalysisFromPhoto:
        return 'Stil Analizi';
    }
  }

  // ── Bridge message: AI'a gönder ama kullanıcı balonu gösterme ──
  Future<void> _sendBridgeMessage(String text) async {
    setState(() => _loading = true);
    _scrollDown();
    _history.add({'role': 'user', 'content': text});
    try {
      final resp = await _ai.askWithIntent(
        intent: KoalaIntent.freeChat,
        freeText: text,
        history: _history,
      );
      _history.add({'role': 'model', 'content': resp.message});
      if (!mounted) return;
      setState(() {
        _msgs.add(_Msg(role: 'koala', text: resp.message, cards: resp.cards));
        _loading = false;
      });
    } catch (e) {
      debugPrint('AI bridge error: $e');
      if (!mounted) return;
      setState(() {
        _msgs.add(_Msg(role: 'koala', text: null, isError: true, errorMsg: _friendlyError(e)));
        _loading = false;
      });
    }
    _scrollDown();
    _persist();
  }

  // ── AI ──
  // [photo]           → kullanıcı yeni foto yükledi, balonu foto ile göster
  // [referencePhoto]  → önceki fotoya referans, balonu SADECE text olarak göster
  //                     ama API'ye vision ile gönder ("renk öner", "stil analizi" için)
  Future<void> _sendToAI({String? text, Uint8List? photo, Uint8List? referencePhoto, String? hiddenContext}) async {
    if (text == null && photo == null && referencePhoto == null) return;
    if (_loading) return; // Önceki istek bitmeden yeni istek gönderme
    if (_msgs.isEmpty) {
      Analytics.aiChatStarted((photo ?? referencePhoto) != null ? 'photo' : 'text');
      if (text != null && text.length > 3) {
        _chatTitle = text.length > 30 ? '${text.substring(0, 30)}...' : text;
      }
    }

    // Kullanıcı balonu: referencePhoto DEĞİL, sadece photo görünür (aksi halde foto
    // her chip tıklandığında tekrar tekrar görünür)
    setState(() {
      _msgs.add(_Msg(role: 'user', text: text, photo: photo));
      _loading = true;
    });
    _scrollDown();

    // AI'a gönderilecek text: gizli bağlam varsa ekle
    final aiText = hiddenContext != null && text != null
        ? '[$hiddenContext]\n\nKullanıcı isteği: $text'
        : text;
    if (aiText != null) _history.add({'role': 'user', 'content': aiText});

    // Vision çağrısında kullanılacak foto: yeni yüklenen > referans
    final visionPhoto = photo ?? referencePhoto;

    try {
      if (visionPhoto != null) {
        // Fotoğraf analizi → non-stream (image payload)
        final resp = await _ai.askWithPhoto(visionPhoto, text: text, history: _history);
        _history.add({'role': 'model', 'content': resp.message});
        // Fotoğraf analiz bağlamını sakla — follow-up chip'ler için
        _extractPhotoContext(resp);
        if (!mounted) return;
        setState(() {
          _msgs.add(_Msg(role: 'koala', text: resp.message, cards: resp.cards));
          _loading = false;
        });
      } else {
        // Function-calling destekli istek — gerçek ürün/tasarımcı/proje verisi getirebilir
        // hiddenContext zaten _history'de AI'a gönderildi, ekstra eklemeye gerek yok
        final resp = await _ai.askWithIntent(
          intent: KoalaIntent.freeChat,
          freeText: text,
          history: _history,
        );
        _history.add({'role': 'model', 'content': resp.message});
        // Metin sohbetinden de context çıkar (kartlarda stil/oda bilgisi varsa)
        if (resp.cards.isNotEmpty && _photoAnalysisContext == null) {
          _extractPhotoContext(resp);
        }
        if (!mounted) return;
        setState(() {
          _msgs.add(_Msg(role: 'koala', text: resp.message, cards: resp.cards));
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('AI error: $e');
      Analytics.aiErrorOccurred(e.toString().substring(0, 200.clamp(0, e.toString().length)));
      if (!mounted) return;
      setState(() {
        _msgs.add(
          _Msg(
            role: 'koala',
            text: null,
            isError: true,
            errorMsg: _friendlyError(e),
          ),
        );
        _loading = false;
      });
    }
    _scrollDown();
    _persist();
  }

  /// Hata mesajını kullanıcı dostu Türkçe'ye çevir
  static String _friendlyError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('timeout') || s.contains('timed out')) {
      return 'Yanıt almak biraz uzun sürdü. Tekrar dener misin?';
    }
    if (s.contains('socket') || s.contains('connection') || s.contains('network')) {
      return 'İnternet bağlantın kopmuş olabilir. Bağlantını kontrol edip tekrar dene.';
    }
    if (s.contains('429') || s.contains('rate limit')) {
      return 'Çok fazla istek gönderildi. Birkaç saniye bekleyip tekrar dene.';
    }
    if (s.contains('503') || s.contains('unavailable') || s.contains('high demand')) {
      return 'AI servisi şu an yoğun. Birkaç saniye bekleyip tekrar dene.';
    }
    if (s.contains('500') || s.contains('server') || s.contains('internal')) {
      return 'Sunucuda geçici bir sorun var. Biraz sonra tekrar dene.';
    }
    if (s.contains('400') || s.contains('invalid')) {
      return 'Fotoğraf işlenemedi. Farklı bir fotoğraf deneyebilir misin?';
    }
    if (s.contains('format') || s.contains('parse') || s.contains('json')) {
      return 'Yanıt beklenmeyen formatta geldi. Tekrar dener misin?';
    }
    if (s.contains('fotoğraf analizi başarısız')) {
      return e.toString().replaceAll('Exception: ', '');
    }
    return 'Bir sorun oluştu ($s). Tekrar denemek için butona dokun.';
  }

  Future<void> _sendToAIWithIntent({
    required KoalaIntent intent,
    Map<String, String> params = const {},
  }) async {
    setState(() => _loading = true);
    _scrollDown();
    try {
      final resp = await _ai.askWithIntent(
        intent: intent,
        params: params,
        history: _history,
      );
      _history.add({'role': 'model', 'content': resp.message});
      if (!mounted) return;
      setState(() {
        _msgs.add(_Msg(role: 'koala', text: resp.message, cards: resp.cards));
        _loading = false;
      });
    } catch (e) {
      debugPrint('AI intent error: $e');
      if (!mounted) return;
      setState(() {
        _msgs.add(
          _Msg(
            role: 'koala',
            text: null,
            isError: true,
            errorMsg: _friendlyError(e),
            intent: intent,
            intentParams: params,
          ),
        );
        _loading = false;
      });
    }
    _scrollDown();
    _persist();
  }

  void _retry() {
    // Error mesajını bul ve retry stratejisini belirle
    final errorIdx = _msgs.lastIndexWhere((m) => m.isError);
    if (errorIdx < 0) return;

    final errorMsg = _msgs[errorIdx];
    setState(() {
      _msgs.removeAt(errorIdx);
    });

    // Intent-based hata ise intent'i tekrar gönder
    if (errorMsg.intent != null) {
      _sendToAIWithIntent(
        intent: errorMsg.intent!,
        params: errorMsg.intentParams ?? {},
      );
      return;
    }

    // Text-based hata ise son user mesajını tekrar gönder
    final lastUserIdx = _msgs.lastIndexWhere((m) => m.role == 'user');
    if (lastUserIdx < 0) return;
    final lastUser = _msgs[lastUserIdx];
    if (lastUser.text != null || lastUser.photo != null) {
      // History'den sadece hata olan user mesajını kaldır (model yanıtı eklenmemişti)
      if (_history.isNotEmpty && _history.last['role'] == 'user') {
        _history.removeLast();
      }
      setState(() {
        _msgs.removeAt(lastUserIdx);
      });
      _sendToAI(text: lastUser.text, photo: lastUser.photo);
    }
  }

  /// Fotoğraf analiz yanıtından oda/stil/renk bağlamını çıkar
  void _extractPhotoContext(KoalaResponse resp) {
    final cards = resp.cards;
    final ctx = <String, String>{};

    // 1) Kartlardan stil/renk/mood çıkar
    for (final card in cards) {
      if (card.type == 'style_analysis') {
        final styleName = card.data['style_name'] ?? card.data['style'] ?? '';
        if (styleName.toString().isNotEmpty) ctx['style'] = styleName.toString();
        final palette = card.data['color_palette'];
        if (palette is List && palette.isNotEmpty) {
          ctx['colors'] = palette.take(4).map((c) {
            if (c is Map) return c['name'] ?? c['color'] ?? c.toString();
            return c.toString();
          }).join(', ');
        }
        final mood = card.data['mood']?.toString();
        if (mood != null && mood.isNotEmpty) ctx['mood'] = mood;
      }
    }

    // 2) Oda tipi: önce kartlardan, sonra message'dan
    for (final card in cards) {
      if (card.type == 'style_analysis') {
        final roomType = card.data['room_type']?.toString();
        if (roomType != null && roomType.isNotEmpty) {
          ctx['room'] = roomType;
          break;
        }
      }
    }
    if (!ctx.containsKey('room')) {
      final msg = resp.message.toLowerCase();
      for (final room in ['salon', 'yatak odası', 'mutfak', 'banyo', 'ofis', 'çocuk odası', 'balkon', 'antre']) {
        if (msg.contains(room)) { ctx['room'] = room; break; }
      }
    }

    // 3) Stil: kartlardan bulunamadıysa message'dan çıkar
    if (!ctx.containsKey('style')) {
      final msg = resp.message.toLowerCase();
      for (final style in _knownStyles) {
        if (msg.contains(style)) { ctx['style'] = style; break; }
      }
      // Ek stiller — kartlardaki standart listede olmayan
      if (!ctx.containsKey('style')) {
        for (final style in ['eklektik', 'eclectic', 'retro', 'art deco', 'mid-century', 'coastal', 'farmhouse', 'transitional']) {
          if (msg.contains(style)) { ctx['style'] = style; break; }
        }
      }
    }

    if (ctx.isNotEmpty) _photoAnalysisContext = ctx;
    debugPrint('PhotoContext: $ctx');
  }

  static const _knownStyles = {
    'japandi', 'minimalist', 'minimal', 'bohemian', 'bohem', 'boho',
    'modern', 'scandinavian', 'skandinav', 'industrial', 'endustriyel',
    'classic', 'klasik', 'luxury', 'luks', 'lüks', 'rustic', 'rustik',
  };

  void _onChipTap(String chipText) {
    HapticFeedback.lightImpact();
    final lower = chipText.toLowerCase();
    for (final style in _knownStyles) {
      if (lower.contains(style)) {
        ProfileFeedbackService.recordStyleInterest(style);
        break;
      }
    }

    final ctx = _photoAnalysisContext;
    // Profile fallback'leri: foto analizi > onboarding profili > son çare default
    final profileStyle = ctx?['style'] ?? _ai.userStyle;
    final profileRoom = ctx?['room'] ?? _ai.userRoom;
    final profileBudget = _ai.userBudget;

    // "Uzman/tasarımcı/iç mimar öner" → designerMatch intent'i (search_designers garanti)
    if (lower.contains('uzman') ||
        lower.contains('tasarımcı') ||
        lower.contains('iç mimar') ||
        lower.contains('mimar öner') ||
        lower.contains('mimar bul') ||
        lower.contains('mimar ara')) {
      _dispatchIntent(
        chipText,
        KoalaIntent.designerMatch,
        {'style': profileStyle ?? 'modern'},
      );
      return;
    }

    // "Fotoğraf çekeyim 📸" → kamera/galeri picker aç, AI'a gönderme
    if (lower.contains('fotoğraf çek') || lower.contains('fotoğraf çekeyim')) {
      setState(() {
        _msgs.add(_Msg(role: 'user', text: chipText));
      });
      _scrollDown();
      _showPicker();
      return;
    }

    // "Yeniden tasarla" / "Odamı yenile" → roomRenovation intent'i
    if (lower.contains('yeniden tasarla') ||
        (lower.contains('yenile') && (lower.contains('oda') || lower.contains('salon') ||
            lower.contains('mutfak') || lower.contains('banyo') || lower.contains('evim')))) {
      _dispatchIntent(
        chipText,
        KoalaIntent.roomRenovation,
        {
          'room': profileRoom ?? 'salon',
          'style': profileStyle ?? 'modern',
        },
      );
      return;
    }

    // "Bütçe planı" / "30K bütçem var" → budgetPlan intent'i
    final isBudgetRequest = lower.contains('bütçe') &&
        (lower.contains('plan') || lower.contains('planla') ||
            RegExp(r'\d+\s*k\b').hasMatch(lower) || lower.contains('tl'));
    if (isBudgetRequest) {
      _dispatchIntent(
        chipText,
        KoalaIntent.budgetPlan,
        {
          if (profileRoom != null) 'room': profileRoom,
          if (profileBudget != null) 'budget': profileBudget,
        },
      );
      return;
    }

    // "Renk paleti / renk öner" → colorAdvice intent'i
    if (lower.contains('renk paleti') || lower.contains('renk öner') ||
        (lower.contains('renk') && lower.contains('tarz'))) {
      _dispatchIntent(
        chipText,
        KoalaIntent.colorAdvice,
        {if (profileRoom != null) 'room': profileRoom},
      );
      return;
    }

    // "Önce-sonra / dönüşüm" → beforeAfter intent'i
    if (lower.contains('önce-sonra') || lower.contains('önce sonra') ||
        lower.contains('dönüşüm') || lower.contains('ilham')) {
      _dispatchIntent(chipText, KoalaIntent.beforeAfter, const {});
      return;
    }

    // Diğer chip'ler: kullanıcı temiz text görür, AI bağlamı hiddenContext ile alır
    _sendToAI(text: chipText, hiddenContext: _buildHiddenContext());
  }

  /// Chip metnini kullanıcı balonuna ekler + history'ye yazar + intent çağırır.
  /// _onChipTap içindeki tekrar eden boilerplate'i azaltır.
  void _dispatchIntent(
    String chipText,
    KoalaIntent intent,
    Map<String, String> params,
  ) {
    setState(() {
      _msgs.add(_Msg(role: 'user', text: chipText));
      _loading = true;
    });
    _history.add({'role': 'user', 'content': chipText});
    _scrollDown();
    _sendToAIWithIntent(intent: intent, params: params);
  }

  Future<void> _generateImage(String prompt) async {
    setState(() {
      _loading = true;
    });
    _scrollDown();
    try {
      final bytes = await _imgService.generateRoomDesign(
        roomType: 'salon',
        style: 'modern',
        additionalDetails: prompt,
      );
      setState(() {
        if (bytes != null) {
          _msgs.add(
            _Msg(role: 'koala', text: '🏠 İşte tasarım önerim:', photo: bytes),
          );
        } else {
          _msgs.add(
            _Msg(
              role: 'koala',
              text:
                  'Görsel şu an oluşturulamadı ama önerilerimi kullanabilirsin 🐨',
            ),
          );
        }
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _msgs.add(
          _Msg(role: 'koala', text: 'Görsel oluşturma şu an çalışmıyor 🐨'),
        );
        _loading = false;
      });
    }
    _scrollDown();
    _persist();
  }

  void _submitText() {
    if (_loading) return; // AI yanıt verirken gönderme
    final t = _ctrl.text.trim();
    if (t.isEmpty && _pendingPhoto == null) return;
    _ctrl.clear();
    final p = _pendingPhoto;
    setState(() => _pendingPhoto = null);
    _sendToAI(text: t.isNotEmpty ? t : null, photo: p);
  }

  void _showPicker() {
    HapticFeedback.lightImpact();

    // Web'de kamera yok, doğrudan galeriyi aç
    if (kIsWeb) {
      _doPick(ImageSource.gallery);
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: Colors.grey.shade300,
              ),
            ),
            const SizedBox(height: 16),
            // Photo upload guidance
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: _accentLight,
              ),
              child: const Row(
                children: [
                  Icon(Icons.auto_awesome, size: 18, color: _accent),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Odanın fotoğrafını çek, sana özel renk, mobilya ve stil önerileri sunayım!',
                      style: TextStyle(fontSize: 13, color: _ink, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _pickBtn(Icons.camera_alt_rounded, 'Kamera', () {
                    Navigator.pop(context);
                    _doPick(ImageSource.camera);
                  }),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _pickBtn(Icons.photo_library_rounded, 'Galeri', () {
                    Navigator.pop(context);
                    _doPick(ImageSource.gallery);
                  }),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _doPick(ImageSource src) async {
    final f = await _picker.pickImage(
      source: src,
      maxWidth: 1024,
      imageQuality: 55,
    );
    if (f == null) return;
    Analytics.aiPhotoUploaded(src == ImageSource.camera ? 'camera' : 'gallery');
    final bytes = await f.readAsBytes();
    setState(() => _pendingPhoto = bytes);
  }

  Widget _pickBtn(IconData icon, String label, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: _accentLight,
          ),
          child: Column(
            children: [
              Icon(icon, size: 28, color: _accent),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: KoalaColors.ink,
                ),
              ),
            ],
          ),
        ),
      );

  // ═══════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final btm = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: KoalaColors.surfaceMuted,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _ink),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Tarzını Güncelle',
            onPressed: _openStyleDiscovery,
            icon: const Icon(Icons.auto_awesome_rounded, color: _accent),
          ),
        ],
        title: Row(
          children: [
            Image.asset(
              'assets/images/koalas.webp',
              width: 28,
              height: 28,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, _, _) => Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [_accent, KoalaColors.accentMuted],
                  ),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _chatTitle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              const OfflineBanner(),
              Expanded(
                child: Stack(
                  children: [
                    // Welcome state: SADECE yeni sohbet (chatId yok) için.
                    // Mevcut sohbete girerken _loadMessages() async çalışırken
                    // welcome state flash etmesin diye chatId varsa boş bırak.
                    _msgs.isEmpty && !_loading && widget.chatId == null
                        ? _buildEmptyState()
                        : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        itemCount: _msgs.length + (_loading ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i == _msgs.length) return _buildLoading();
                          return _buildMsg(_msgs[i]);
                        },
                      ),
                // Scroll-to-bottom FAB
                if (_showScrollToBottom)
                  Positioned(
                    bottom: 8,
                    right: 12,
                    child: GestureDetector(
                      onTap: _scrollDown,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 22,
                          color: _accent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Quick action chips — show when chat has messages and not loading
          if (_msgs.isNotEmpty && !_loading) _buildQuickActions(),
          // Photo preview — shown directly above the input bar after picker
          if (_pendingPhoto != null) _buildPhotoPreview(),
          _buildInputBar(btm),
        ],
          ),
          // Drag-and-drop overlay
          if (_isDragHovering)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: _accent.withValues(alpha: 0.12),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: _accent.withValues(alpha: 0.25),
                            blurRadius: 24,
                          ),
                        ],
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_photo_alternate_rounded,
                              size: 48, color: _accent),
                          SizedBox(height: 12),
                          Text(
                            'Fotoğrafı buraya bırak',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Chat'teki en son kullanıcı fotoğrafını bul (yoksa null).
  Uint8List? _latestUserPhoto() {
    for (int i = _msgs.length - 1; i >= 0; i--) {
      final m = _msgs[i];
      if (m.role == 'user' && m.photo != null) return m.photo;
    }
    return null;
  }

  /// "Renk öner", "Ürün bul", "Stil analizi" gibi foto-bağımlı chip'ler.
  /// Her tıklamada en son fotoyu vision ile yeniden yorumlar — stale text
  /// context'e güvenmez. Foto yoksa picker açılır.
  ///
  /// [intent] parametresi verilirse dar-amaçlı intent (colorPaletteFromPhoto,
  /// styleAnalysisFromPhoto) üzerinden çağırır. null ise photoAnalysis (ürün/tasarımcı
  /// tool'lu genel vision).
  void _onPhotoChip(String text, {KoalaIntent? intent}) {
    final latest = _latestUserPhoto();
    if (latest == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Önce odanın fotoğrafını paylaşırsan sana özel öneri yapabilirim'),
          duration: Duration(seconds: 3),
        ),
      );
      _showPicker();
      return;
    }
    if (intent != null) {
      _sendPhotoIntent(text: text, photo: latest, intent: intent);
    } else {
      _sendToAI(text: text, referencePhoto: latest);
    }
  }

  /// Dar-amaçlı foto intent'i gönder (renk paleti, stil analizi — tool'suz).
  /// Kullanıcı balonuna yalnızca text yazılır; foto zaten geçmişte var.
  Future<void> _sendPhotoIntent({
    required String text,
    required Uint8List photo,
    required KoalaIntent intent,
  }) async {
    if (_loading) return;
    setState(() {
      _msgs.add(_Msg(role: 'user', text: text));
      _loading = true;
    });
    _history.add({'role': 'user', 'content': text});
    _scrollDown();

    try {
      final resp = await _ai.askWithIntent(
        intent: intent,
        freeText: text,
        photo: photo,
        history: _history,
      );
      _history.add({'role': 'model', 'content': resp.message});
      _extractPhotoContext(resp);
      if (!mounted) return;
      setState(() {
        _msgs.add(_Msg(role: 'koala', text: resp.message, cards: resp.cards));
        _loading = false;
      });
    } catch (e) {
      debugPrint('AI photo-intent error: $e');
      Analytics.aiErrorOccurred(e.toString().substring(0, 200.clamp(0, e.toString().length)));
      if (!mounted) return;
      setState(() {
        _msgs.add(_Msg(
          role: 'koala',
          text: null,
          isError: true,
          errorMsg: _friendlyError(e),
        ));
        _loading = false;
      });
    }
    _scrollDown();
    _persist();
  }

  // ── Hidden context builder — AI'a gönderilir ama kullanıcıya gösterilmez ──
  String? _buildHiddenContext() {
    final ctx = _photoAnalysisContext;
    if (ctx == null || ctx.isEmpty) return null;
    final room = ctx['room'];
    final style = ctx['style'];
    final colors = ctx['colors'];
    final parts = <String>[];
    if (room != null) parts.add('Oda: $room');
    if (style != null) parts.add('Stil: $style');
    if (colors != null) parts.add('Renkler: $colors');
    if (parts.isEmpty) return null;
    return 'Fotoğraf analizi bağlamı — ${parts.join(', ')}';
  }

  // ── Quick action chips above input ──
  Widget _buildQuickActions() {
    final ctx = _photoAnalysisContext;
    final room = ctx?['room'];
    final style = ctx?['style'];

    final colorLabel = room != null ? 'Renk öner' : 'Renk öner';
    final productLabel = style != null ? 'Ürün bul' : 'Ürün bul';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            _quickChip(Icons.color_lens_rounded, colorLabel,
              () => _onPhotoChip('Bu odaya uygun renk paleti öner',
                  intent: KoalaIntent.colorPaletteFromPhoto)),
            _quickChip(Icons.shopping_bag_rounded, productLabel,
              () => _onPhotoChip('Bu oda ve stile uygun ürün öner')),
            _quickChip(Icons.person_rounded, 'Uzman öner', () {
              // Direkt designerMatch intent'i — search_designers function call'ını garanti eder
              final ctx = _photoAnalysisContext;
              final style = ctx?['style'] ?? 'modern';
              const userText = 'Bu oda için uzman tasarımcı öner';
              setState(() {
                _msgs.add(_Msg(role: 'user', text: userText));
                _loading = true;
              });
              // History'e de ekle ki servis tarafında lastUserText "Devam et" default'una
              // düşüp yanlış yere sapmasın (casual escape bug'ı)
              _history.add({'role': 'user', 'content': userText});
              _scrollDown();
              _sendToAIWithIntent(
                intent: KoalaIntent.designerMatch,
                params: {'style': style},
              );
            }),
            _quickChip(Icons.auto_awesome_rounded, 'Stil analizi',
              () => _onPhotoChip('Bu odanın stilini detaylı analiz et',
                  intent: KoalaIntent.styleAnalysisFromPhoto)),
          ],
        ),
      ),
    );
  }

  Widget _quickChip(IconData icon, String label, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            color: _accentLight,
            border: Border.all(color: _accent.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: _accent),
              const SizedBox(width: 5),
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _accent)),
          ],
        ),
      ),
    ),
    ),
  );

  // ── Empty state with profile-aware suggestion chips ──
  Widget _buildEmptyState() {
    // Build personalized suggestions based on user profile
    final starters = _getProfileAwareStarters();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/koalas.webp',
              width: 64,
              height: 64,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.auto_awesome, size: 48, color: _accent),
            ),
            const SizedBox(height: 16),
            const Text(
              'Merhaba! Ben Koala 🐨',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'İç mekan tasarımı hakkında\nher şeyi sorabilirsin',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            // Camera prompt
            GestureDetector(
              onTap: _showPicker,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    colors: [KoalaColors.accentDeep, KoalaColors.accentMuted],
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.camera_alt_rounded, size: 18, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Odanın fotoğrafını çek, analiz edeyim',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: starters,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _getProfileAwareStarters() {
    final style = _ai.userStyle;
    final room = _ai.userRoom;
    final budget = _ai.userBudget;

    // If we have profile data, personalize the suggestions.
    // _onChipTap → dedicated intent router (designerMatch, roomRenovation, colorAdvice, budgetPlan)
    if (style != null && style.isNotEmpty) {
      final roomLabel = room ?? 'Odamı';
      return [
        _suggestionChip(Icons.palette_rounded, '$style tarzda $roomLabel yenile', KoalaColors.accentDeep,
          () => _onChipTap('$roomLabel $style tarzda yeniden tasarla')),
        _suggestionChip(Icons.color_lens_rounded, '$roomLabel için 3 renk öner', KoalaColors.pink,
          () => _onChipTap('$roomLabel için $style tarzıma uygun renk paleti öner')),
        if (budget != null && budget.isNotEmpty)
          _suggestionChip(Icons.account_balance_wallet_rounded, '$budget bütçeyle plan', KoalaColors.greenAlt,
            () => _onChipTap('$roomLabel için $budget bütçeyle $style dekorasyon bütçe planı çıkar')),
        _suggestionChip(Icons.person_search_rounded, 'Bana uygun tasarımcı', KoalaColors.blue,
          () => _onChipTap('$style tarzda çalışan bir iç mimar öner')),
      ];
    }

    // Default starters (no profile) — _onChipTap intent router'a gidiyor
    return [
      _suggestionChip(Icons.home_rounded, 'Odamı yenile', KoalaColors.accentDeep,
        () => _onChipTap('Odamı yeniden tasarla')),
      _suggestionChip(Icons.color_lens_rounded, 'Renk öner', KoalaColors.pink,
        () => _onChipTap('Odama uygun renk paleti öner')),
      _suggestionChip(Icons.account_balance_wallet_rounded, 'Bütçe planla', KoalaColors.greenAlt,
        () => _onChipTap('Bütçe planı çıkar')),
      _suggestionChip(Icons.person_search_rounded, 'Tasarımcı bul', KoalaColors.blue,
        () => _onChipTap('Bana uygun tasarımcı öner')),
    ];
  }

  Widget _suggestionChip(IconData icon, String label, Color color, VoidCallback onTap) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: color.withValues(alpha: 0.06),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  // ── Loading ──
  Widget _buildLoading() => Padding(
    padding: const EdgeInsets.only(top: 16, left: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _koalaAvatar(),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TypingDots(),
              const SizedBox(width: 10),
              Text(
                widget.intent == KoalaIntent.photoAnalysis && _msgs.length <= 1
                    ? 'fotoğrafı analiz ediyorum...'
                    : 'düşünüyor...',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  // ── Message ──
  Widget _buildMsg(_Msg msg) {
    final isUser = msg.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // Photo
          if (msg.photo != null && isUser)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image(
                    image: msg.cachedImage!,
                    width: 200,
                    height: 150,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => Container(
                      width: 200,
                      height: 150,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                ),
              ),
            ),
          // Generated image (koala response)
          if (msg.photo != null && !isUser)
            Padding(
              padding: const EdgeInsets.only(left: 40, bottom: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280, maxWidth: 320),
                  child: Image(
                    image: msg.cachedImage!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          // Error with retry
          if (msg.isError) _buildErrorCard(msg),
          // Text
          if (msg.text != null && msg.text!.isNotEmpty)
            Row(
              mainAxisAlignment: isUser
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isUser) ...[_koalaAvatar(), const SizedBox(width: 8)],
                Flexible(
                  child: GestureDetector(
                    onLongPress: !isUser ? () {
                      HapticFeedback.lightImpact();
                      Clipboard.setData(ClipboardData(text: msg.text!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: KoalaColors.accentDeep,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          duration: const Duration(seconds: 1),
                          content: const Text(
                            'Mesaj kopyalandı',
                            style: TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),
                      );
                    } : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isUser ? _accent : Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(isUser ? 18 : 4),
                          bottomRight: Radius.circular(isUser ? 4 : 18),
                        ),
                      ),
                      child: isUser
                          ? Text(
                              msg.text!,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white,
                                height: 1.5,
                              ),
                            )
                          : _buildSimpleMarkdown(msg.text!, _ink),
                    ),
                  ),
                ),
              ],
            ),
          // Timestamp
          Padding(
            padding: EdgeInsets.only(
              top: 4,
              left: isUser ? 0 : 42,
              right: isUser ? 4 : 0,
            ),
            child: Align(
              alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
              child: Text(
                '${msg.time.hour.toString().padLeft(2, '0')}:${msg.time.minute.toString().padLeft(2, '0')}',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
              ),
            ),
          ),
          // Cards with staggered animation
          if (msg.cards != null)
            ...msg.cards!.asMap().entries.map((entry) {
              final idx = entry.key;
              final card = entry.value;
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 400 + idx * 100),
                curve: Curves.easeOutCubic,
                builder: (_, val, child) => Opacity(
                  opacity: val,
                  child: Transform.translate(
                    offset: Offset(0, 12 * (1 - val)),
                    child: child,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 40, top: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [_renderCard(card), _cardActions(card)],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildErrorCard(_Msg msg) => Padding(
    padding: const EdgeInsets.only(left: 40),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFFFFF7ED),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sentiment_neutral_rounded, size: 20, color: Color(0xFFEA580C)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  msg.errorMsg ?? 'Şu an bu konuda yardımcı olamıyorum, ama şunları deneyebilirsin:',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF9A3412), height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _fallbackChip(Icons.refresh_rounded, 'Tekrar dene', _retry),
              _fallbackChip(Icons.color_lens_rounded, 'Renk öner',
                () => _onPhotoChip('Bu odaya uygun renk paleti öner',
                    intent: KoalaIntent.colorPaletteFromPhoto)),
              _fallbackChip(Icons.shopping_bag_rounded, 'Ürün bul',
                () => _onPhotoChip('Bu oda ve stile uygun ürün öner')),
              _fallbackChip(Icons.person_rounded, 'Uzman bul', () {
                // Stil sırası: foto analizi > onboarding profili > varsayılan modern
                final style = _photoAnalysisContext?['style'] ??
                    _ai.userStyle ??
                    'modern';
                setState(() {
                  _msgs.add(_Msg(role: 'user', text: 'Bu tarz için uzman tasarımcı öner'));
                  _loading = true;
                });
                _scrollDown();
                _sendToAIWithIntent(
                  intent: KoalaIntent.designerMatch,
                  params: {'style': style},
                );
              }),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _fallbackChip(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        Analytics.aiFallbackChipUsed(label);
        final errorIdx = _msgs.lastIndexWhere((m) => m.isError);
        if (errorIdx >= 0) setState(() => _msgs.removeAt(errorIdx));
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: Colors.white,
          border: Border.all(color: const Color(0xFFFED7AA)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: _accent),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF9A3412))),
          ],
        ),
      ),
    );
  }

  Widget _koalaAvatar() => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Image.asset(
      'assets/images/koalas.webp',
      width: 32,
      height: 32,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, _, _) => Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [_accent, KoalaColors.accentMuted]),
        ),
        child: const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
      ),
    ),
  );

  Widget _buildPhotoPreview() => Container(
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Thumbnail
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                _pendingPhoto!,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
              ),
            ),
            // X button overlay on thumbnail
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => setState(() => _pendingPhoto = null),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        // Caption hint
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.check_circle_rounded, size: 14, color: _accent),
                  const SizedBox(width: 5),
                  Text(
                    'Fotoğraf seçildi',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Metin ekleyebilir veya doğrudan gönderebilirsin.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildInputBar(double btm) {
    final has = _ctrl.text.isNotEmpty || _pendingPhoto != null;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, btm + 8),
      decoration: const BoxDecoration(color: Colors.white),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: KoalaColors.accentSoft,
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: _showPicker,
              child: Padding(
                padding: const EdgeInsets.only(left: 5),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha:0.7),
                  ),
                  child: Icon(
                    Icons.camera_alt_rounded,
                    size: 18,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ),
            Expanded(
              child: TextField(
                controller: _ctrl,
                enabled: !_loading,
                decoration: InputDecoration(
                  hintText: _loading
                      ? 'Koala düşünüyor...'
                      : _pendingPhoto != null
                          ? 'Fotoğrafa mesaj ekle (isteğe bağlı)...'
                          : 'Koala\'ya sor...',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: _loading ? Colors.grey.shade300 : Colors.grey.shade400,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 14,
                  ),
                ),
                style: const TextStyle(fontSize: 14, color: _ink),
                onSubmitted: (_) => _submitText(),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (has)
              GestureDetector(
                onTap: _submitText,
                child: Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: _accent,
                    ),
                    child: const Icon(
                      Icons.arrow_upward_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // CARD RENDERER
  // ═══════════════════════════════════════════════════════
  void _saveCard(KoalaCard card) async {
    HapticFeedback.lightImpact();
    final title =
        card.data['title'] as String? ??
        card.data['style_name'] as String? ??
        card.type;
    final plan = SavedPlan(
      id: '${card.type}_${DateTime.now().millisecondsSinceEpoch}',
      type: card.type,
      title: title,
      data: card.data,
    );
    await SavedPlansService.save(plan);
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: KoalaColors.accentDeep,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 3),
          content: Text(
            '$title kaydedildi',
            style: const TextStyle(color: Colors.white),
          ),
          action: SnackBarAction(
            label: 'Kaydedilenlerimi Gör',
            textColor: Colors.white,
            onPressed: () => GoRouter.of(context).push('/saved'),
          ),
        ),
      );
    }
  }

  void _shareCard(KoalaCard card) {
    HapticFeedback.lightImpact();
    final title =
        card.data['title'] as String? ??
        card.data['style_name'] as String? ??
        '';
    final buf = StringBuffer('🐨 Koala - $title\n');
    if (card.type == 'color_palette') {
      final colors = (card.data['colors'] as List?) ?? [];
      for (final co in colors) {
        if (co is Map) buf.writeln('${co['name']}: ${co['hex']}');
      }
    }
    buf.writeln('\nevlumba.com');
    Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: KoalaColors.greenAlt,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: const Text(
            'Panoya kopyalandı ✨',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }
  }

  Widget _cardActions(KoalaCard card) {
    const saveable = [
      'style_analysis',
      'color_palette',
      'product_grid',
      'budget_plan',
      'designer_card',
      'before_after',
    ];
    if (!saveable.contains(card.type)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _miniAction(Icons.favorite_border_rounded, 'Kaydet', KoalaColors.accentDeep, () => _saveCard(card)),
          const SizedBox(width: 6),
          _miniAction(Icons.copy_rounded, 'Paylaş', KoalaColors.greenAlt, () => _shareCard(card)),
        ],
      ),
    );
  }

  Widget _miniAction(IconData icon, String tooltip, Color color, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Tooltip(
      message: tooltip,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.08),
        ),
        child: Icon(icon, size: 14, color: color),
      ),
    ),
  );

  /// Parses simple markdown: **bold**, *italic*, and bullet points (* item)
  Widget _buildSimpleMarkdown(String text, Color color) {
    final lines = text.split('\n');
    final children = <Widget>[];

    for (final line in lines) {
      final trimmed = line.trim();
      // Bullet point
      if (trimmed.startsWith('* ') || trimmed.startsWith('- ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('• ', style: TextStyle(fontSize: 14, color: color, height: 1.5)),
              Expanded(child: _buildInlineMarkdown(trimmed.substring(2), color)),
            ],
          ),
        ));
      } else if (trimmed.isNotEmpty) {
        children.add(_buildInlineMarkdown(trimmed, color));
      } else {
        children.add(const SizedBox(height: 6));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  /// Handles inline **bold** and *italic* within a single line
  Widget _buildInlineMarkdown(String text, Color color) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*');
    int lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      // Text before this match
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      if (match.group(1) != null) {
        // **bold**
        spans.add(TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ));
      } else if (match.group(2) != null) {
        // *italic*
        spans.add(TextSpan(
          text: match.group(2),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      }
      lastEnd = match.end;
    }

    // Remaining text
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 14, color: color, height: 1.5),
        children: spans.isEmpty ? [TextSpan(text: text)] : spans,
      ),
    );
  }

  Widget _renderCard(KoalaCard card) {
    Analytics.aiCardDisplayed(card.type);
    switch (card.type) {
      case 'question_chips':
        return QuestionChips(card.data, onTap: _onChipTap);
      case 'style_analysis':
        return StyleAnalysis(card.data);
      case 'product_grid':
        final productsRaw = card.data['products'] as List<dynamic>? ?? [];
        // Görselsiz ürünleri gizle — bagaj gibi duran boş kartlar gelmesin.
        final carouselItems = productsRaw
            .map(
              (p) =>
                  ProductCarouselItem.fromCardData(p as Map<String, dynamic>),
            )
            .where((item) => item.imageUrl.trim().isNotEmpty)
            .toList();
        if (carouselItems.isEmpty) {
          return const SizedBox.shrink();
        }
        return ProductCarousel(
          title: card.data['title'] as String? ?? 'Önerilen Ürünler',
          products: carouselItems,
          onAskAI: (product, question) {
            // Ürün context'i hiddenContext olarak geçsin, AI yeni ürün aramasın
            // sadece kullanıcının sorduğu şeye bilgilendirici cevap versin.
            final ctx = StringBuffer()
              ..writeln('BAĞLAM: Kullanıcı aşağıdaki ürün hakkında bilgi soruyor.')
              ..writeln('- Ürün: ${product.name}')
              ..writeln('- Mağaza: ${product.shopName}')
              ..writeln('- Fiyat: ${product.price}')
              ..writeln('- URL: ${product.url}')
              ..writeln('')
              ..writeln('KURAL: search_products TOOL\'UNU KULLANMA. '
                  'Yeni ürün arama yapma. Benzer ürün öneri çıkarma. '
                  'Sadece kullanıcının sorduğu soruya bu ürün özelinde '
                  'bilgilendirici, pratik ve kısa bir cevap ver.');
            _sendToAI(
              text: '"${product.name}" hakkında: $question',
              hiddenContext: ctx.toString(),
            );
          },
        );
      case 'color_palette':
        return ColorPalette(card.data);
      case 'designer_card':
        return DesignerCards(card.data);
      case 'project_card':
        return _ProjectCardInline(data: card.data);
      case 'budget_plan':
        return BudgetPlan(card.data);
      case 'quick_tips':
        return QuickTips(card.data);
      case 'before_after':
        return BeforeAfter(card.data);
      case 'image_prompt':
        return ImagePrompt(card.data, onGenerate: _generateImage);
      case 'architect_cta':
        return ArchitectCTA(card.data);
      default:
        // Fallback — show as text card
        final title =
            card.data['title'] as String? ??
            card.data['question'] as String? ??
            '';
        if (title.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white,
          ),
          child: Text(title, style: TextStyle(fontSize: 13, color: KoalaColors.ink)),
        );
    }
  }
}

// ═══════════════════════════════════════════════════════
// MSG MODEL
// ═══════════════════════════════════════════════════════
class _Msg {
  final String role;
  final String? text;
  final Uint8List? photo;
  /// Fotoğraf için cache'lenmiş MemoryImage — her rebuild'de decode önler
  MemoryImage? _cachedImage;
  MemoryImage? get cachedImage {
    if (_cachedImage != null) return _cachedImage;
    if (photo != null) _cachedImage = MemoryImage(photo!);
    return _cachedImage;
  }
  final List<KoalaCard>? cards;
  final bool isError;
  final String? errorMsg;
  /// Retry için: bu mesajı üreten intent
  final KoalaIntent? intent;
  final Map<String, String>? intentParams;
  final DateTime time;
  _Msg({
    required this.role,
    this.text,
    this.photo,
    this.cards,
    this.isError = false,
    this.errorMsg,
    this.intent,
    this.intentParams,
  }) : time = DateTime.now();
}

// ═══════════════════════════════════════════════════════
// TYPING DOTS
// ═══════════════════════════════════════════════════════
class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with TickerProviderStateMixin {
  late final List<AnimationController> _c;
  @override
  void initState() {
    super.initState();
    _c = List.generate(
      3,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      ),
    );
    for (var i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 180), () {
        if (mounted) _c[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _c) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(
      3,
      (i) => AnimatedBuilder(
        animation: _c[i],
        builder: (_, __) {
          final t = Curves.easeInOut.transform(_c[i].value);
          return Transform.translate(
            offset: Offset(0, -5 * t),
            child: Opacity(
              opacity: 0.45 + 0.55 * t,
              child: Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.lerp(KoalaColors.accentLight, _accent, t),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

// Card widgets extracted to lib/views/chat/widgets/

// ═══════════════════════════════════════════════════════
// PROJECT CARD INLINE — salon bul / oturma odası önerileri için
// Kategori badge + görsel + tasarımcı adı. Tıklayınca detay.
// ═══════════════════════════════════════════════════════
String _prettyTrProjectCategory(String raw) {
  const trMap = {
    'living_room': 'Oturma Odası',
    'bedroom': 'Yatak Odası',
    'kitchen': 'Mutfak',
    'bathroom': 'Banyo',
    'kids_room': 'Çocuk Odası',
    'office': 'Çalışma Odası',
    'dining_room': 'Yemek Odası',
    'hallway': 'Antre',
    'balcony': 'Balkon',
    'outdoor': 'Dış Mekan',
  };
  final key = raw.toLowerCase().trim();
  if (trMap.containsKey(key)) return trMap[key]!;
  final cleaned = raw.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  if (cleaned.isEmpty) return 'Proje';
  return cleaned
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

class _ProjectCardInline extends StatelessWidget {
  const _ProjectCardInline({required this.data});
  final Map<String, dynamic> data;

  Future<void> _openGallery(BuildContext context) async {
    final projectId = (data['id'] ?? '').toString();
    final designerId = (data['designer_id'] ?? '').toString();
    final imageUrl = (data['image_url'] ?? '').toString();
    final title = (data['title'] ?? '').toString();
    final category = (data['category'] ?? '').toString();
    final designerName = (data['designer_name'] ?? '').toString();

    final baseProject = <String, dynamic>{
      'id': projectId,
      'title': title,
      'cover_image_url': imageUrl,
      'image_url': imageUrl,
      'project_type': category,
      'designer_id': designerId,
      'designer_name': designerName,
    };

    List<Map<String, dynamic>> projects = [baseProject];
    int initialIndex = 0;
    Map<String, dynamic>? designer;
    if (designerId.isNotEmpty && EvlumbaLiveService.isReady) {
      try {
        final fetched = await EvlumbaLiveService.getDesignerProjects(
          designerId,
          limit: 12,
        );
        if (fetched.isNotEmpty) {
          final idx = fetched.indexWhere((p) => (p['id'] ?? '').toString() == projectId);
          if (idx >= 0) {
            projects = fetched;
            initialIndex = idx;
          } else {
            projects = [baseProject, ...fetched];
          }
        }
        final d = await EvlumbaLiveService.getDesignerById(designerId);
        if (d != null) designer = d;
      } catch (_) {}
    }
    if (!context.mounted) return;
    await ProjectsGalleryPopup.show(
      context,
      projects: projects,
      initialIndex: initialIndex,
      designer: designer ??
          {
            'id': designerId,
            'full_name': designerName,
          },
    );
  }

  void _askDesigner(BuildContext context) {
    final designerId = (data['designer_id'] ?? '').toString();
    if (designerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tasarımcı bilgisi bulunamadı')),
      );
      return;
    }
    final designerName = (data['designer_name'] ?? '').toString();
    final projectId = (data['id'] ?? '').toString();
    final category = (data['category'] ?? '').toString();
    final cat = _prettyTrProjectCategory(category);
    HapticFeedback.lightImpact();
    DesignerChatPopup.show(
      context,
      designerId: designerId,
      designerName: designerName,
      contextType: 'project',
      contextId: projectId,
      contextTitle: cat,
    );
  }

  Future<void> _saveProject(BuildContext context) async {
    final projectId = (data['id'] ?? '').toString();
    if (projectId.isEmpty) return;
    HapticFeedback.lightImpact();
    final cat = _prettyTrProjectCategory((data['category'] ?? '').toString());
    final ok = await SavedItemsService.saveItem(
      type: SavedItemType.design,
      itemId: projectId,
      title: cat,
      imageUrl: (data['image_url'] ?? '').toString(),
      subtitle: (data['designer_name'] ?? '').toString(),
      extraData: {'designer_id': (data['designer_id'] ?? '').toString()},
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(ok ? 'Kaydedildi' : 'Kaydedilemedi, tekrar dene'),
        backgroundColor: ok ? KoalaColors.greenAlt : Colors.red.shade700,
        duration: const Duration(seconds: 2),
      ));
  }

  void _shareProject(BuildContext context) {
    final projectId = (data['id'] ?? '').toString();
    if (projectId.isEmpty) return;
    HapticFeedback.lightImpact();
    final cat = _prettyTrProjectCategory((data['category'] ?? '').toString());
    ShareSheet.show(
      context,
      itemType: SavedItemType.design,
      itemId: projectId,
      title: cat,
      imageUrl: (data['image_url'] ?? '').toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final category = (data['category'] ?? '').toString();
    final designerName = (data['designer_name'] ?? '').toString();
    final imageUrl = (data['image_url'] ?? '').toString();
    final projectId = (data['id'] ?? '').toString();
    final designerId = (data['designer_id'] ?? '').toString();
    final prettyCat = category.isEmpty ? '' : _prettyTrProjectCategory(category);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KoalaColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageUrl.isNotEmpty)
            GestureDetector(
              onTap: projectId.isEmpty ? null : () => _openGallery(context),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: KoalaColors.surfaceMuted,
                    child: const Icon(Icons.image_not_supported_outlined,
                        color: KoalaColors.textMuted),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (prettyCat.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: KoalaColors.accentSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      prettyCat,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: KoalaColors.accentDeep,
                      ),
                    ),
                  ),
                if (designerName.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.person_outline_rounded,
                          size: 14, color: KoalaColors.textMuted),
                      const SizedBox(width: 4),
                      Flexible(
                        child: GestureDetector(
                          onTap: designerId.isEmpty
                              ? null
                              : () => context.push('/designer/$designerId'),
                          child: Text(
                            designerName,
                            style: const TextStyle(
                              fontSize: 12,
                              color: KoalaColors.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    _ProjectActionIconButton(
                      icon: LucideIcons.messageCircle,
                      tooltip: 'Sor',
                      onTap: () => _askDesigner(context),
                    ),
                    const SizedBox(width: 8),
                    _ProjectActionIconButton(
                      icon: LucideIcons.bookmark,
                      tooltip: 'Kaydet',
                      onTap: () => _saveProject(context),
                    ),
                    const SizedBox(width: 8),
                    _ProjectActionIconButton(
                      icon: LucideIcons.share2,
                      tooltip: 'Paylaş',
                      onTap: () => _shareProject(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectActionIconButton extends StatefulWidget {
  const _ProjectActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_ProjectActionIconButton> createState() =>
      _ProjectActionIconButtonState();
}

class _ProjectActionIconButtonState extends State<_ProjectActionIconButton> {
  double _scale = 1.0;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _scale = 0.9),
        onTapCancel: () => setState(() => _scale = 1.0),
        onTapUp: (_) => setState(() => _scale = 1.0),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 120),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: KoalaColors.accentSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 16, color: KoalaColors.accentDeep),
          ),
        ),
      ),
    );
  }
}
