import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/koala_ai_service.dart';
import '../services/koala_image_service.dart';
import '../services/chat_persistence.dart';
import '../services/messaging_service.dart';
import '../services/saved_plans_service.dart';
import '../services/saved_items_service.dart';
import '../services/analytics_service.dart';
import '../services/profile_feedback_service.dart';
import '../core/theme/koala_tokens.dart';
import '../widgets/save_button.dart';
import '../widgets/chat/product_carousel.dart';
import '../widgets/offline_banner.dart';
import 'conversation_detail_screen.dart';
import 'designers_screen.dart';

const _accent = KoalaColors.accentDeep;
const _accentLight = KoalaColors.accentSoft;
const _ink = KoalaColors.ink;
const _R = 18.0;

Color _hex(String h) {
  final clean = h.replaceAll('#', '');
  return Color(
    int.tryParse('FF$clean', radix: 16) ?? KoalaColors.accentDeep.toARGB32(),
  );
}

class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({
    super.key,
    this.initialText,
    this.initialPhoto,
    this.intent,
    this.intentParams,
    this.chatId,
    this.fromDiscovery = false,
  });

  final String? initialText;
  final Uint8List? initialPhoto;
  final KoalaIntent? intent;
  final Map<String, String>? intentParams;
  final String? chatId;
  final bool fromDiscovery;

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
  /// Tasarımcı arama akışında şehir bekleniyor mu?
  bool _awaitingDesignerCity = false;
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
          widget.initialPhoto != null) {
        // Photo analysis — send photo directly to AI
        _chatTitle = 'Fotoğraf Analizi';
        _sendToAI(
          text: widget.initialText ?? 'Bu odayı analiz et',
          photo: widget.initialPhoto,
        );
      } else if (widget.intent != null) {
        _chatTitle = _intentTitle(widget.intent!);
        _sendToAIWithIntent(
          intent: widget.intent!,
          params: widget.intentParams ?? {},
        );
      } else if (widget.initialText != null || widget.initialPhoto != null) {
        _sendToAI(text: widget.initialText, photo: widget.initialPhoto);
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
    _scroll.removeListener(_onScrollChanged);
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
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
        final profileColors = (profile['preferred_colors'] ?? profile['colors'] as List?)
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
      setState(() {
        _msgs.add(_Msg(role: 'koala', text: null, isError: true, errorMsg: _friendlyError(e)));
        _loading = false;
      });
    }
    _scrollDown();
    _persist();
  }

  // ── AI ──
  Future<void> _sendToAI({String? text, Uint8List? photo}) async {
    if (text == null && photo == null) return;
    if (_loading) return; // Önceki istek bitmeden yeni istek gönderme
    if (_msgs.isEmpty) {
      Analytics.aiChatStarted(photo != null ? 'photo' : 'text');
      if (text != null && text.length > 3) {
        _chatTitle = text.length > 30 ? '${text.substring(0, 30)}...' : text;
      }
    }

    setState(() {
      _msgs.add(_Msg(role: 'user', text: text, photo: photo));
      _loading = true;
    });
    _scrollDown();
    if (text != null) _history.add({'role': 'user', 'content': text});

    try {
      if (photo != null) {
        // Fotoğraf analizi → non-stream (image payload)
        final resp = await _ai.askWithPhoto(photo, text: text, history: _history);
        _history.add({'role': 'model', 'content': resp.message});
        // Fotoğraf analiz bağlamını sakla — follow-up chip'ler için
        _extractPhotoContext(resp);
        if (!mounted) return;
        setState(() {
          _msgs.add(_Msg(role: 'koala', text: resp.message, cards: resp.cards));
          _loading = false;
        });
      } else {
        // Follow-up: fotoğraf analiz bağlamı varsa prompt'a ekle
        String? enrichedText = text;
        if (text != null && _photoAnalysisContext != null) {
          final ctx = _photoAnalysisContext!;
          enrichedText = '[Önceki fotoğraf analizi bağlamı — '
              'Oda: ${ctx['room'] ?? 'bilinmiyor'}, '
              'Stil: ${ctx['style'] ?? 'bilinmiyor'}, '
              'Renkler: ${ctx['colors'] ?? 'bilinmiyor'}] '
              'Kullanıcı isteği: $text';
        }
        // Function-calling destekli istek — gerçek ürün/tasarımcı/proje verisi getirebilir
        final resp = await _ai.askWithIntent(
          intent: KoalaIntent.freeChat,
          freeText: enrichedText,
          history: _history,
        );
        _history.add({'role': 'model', 'content': resp.message});
        if (!mounted) return;
        setState(() {
          _msgs.add(_Msg(role: 'koala', text: resp.message, cards: resp.cards));
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('AI error: $e');
      Analytics.aiErrorOccurred(e.toString().substring(0, 200.clamp(0, e.toString().length)));
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
    if (s.contains('500') || s.contains('server') || s.contains('internal')) {
      return 'Sunucuda geçici bir sorun var. Biraz sonra tekrar dene.';
    }
    if (s.contains('format') || s.contains('parse') || s.contains('json')) {
      return 'Yanıt beklenmeyen formatta geldi. Tekrar dener misin?';
    }
    return 'Bir sorun oluştu. Tekrar denemek için butona dokun.';
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
      setState(() {
        _msgs.add(_Msg(role: 'koala', text: resp.message, cards: resp.cards));
        _loading = false;
      });
    } catch (e) {
      debugPrint('AI intent error: $e');
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
    final lastUser = _msgs.lastWhere(
      (m) => m.role == 'user',
      orElse: () => _Msg(role: 'user'),
    );
    if (lastUser.text != null || lastUser.photo != null) {
      if (_history.isNotEmpty) _history.removeLast();
      _msgs.removeLast(); // Remove user msg (will be re-added)
      _sendToAI(text: lastUser.text, photo: lastUser.photo);
    }
  }

  /// Fotoğraf analiz yanıtından oda/stil/renk bağlamını çıkar
  void _extractPhotoContext(KoalaResponse resp) {
    final cards = resp.cards;
    if (cards.isEmpty) return;
    final ctx = <String, String>{};
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
    // Oda tipi: önce kartlardan, sonra message'dan
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
    if (ctx.isNotEmpty) _photoAnalysisContext = ctx;
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

    // "Uzman öner" akışını tespit et
    if (lower.contains('uzman öner') || lower.contains('uzman bul') || lower.contains('tasarımcı öner')) {
      _awaitingDesignerCity = true;
      _sendToAI(text: chipText);
      return;
    }

    // Tasarımcı şehir seçimi bekliyorsa → direkt designerMatch intent'ine yönlendir
    if (_awaitingDesignerCity) {
      _awaitingDesignerCity = false;
      final style = _photoAnalysisContext?['style'] ?? 'modern';
      // Kullanıcı mesajını ekrana ekle
      setState(() {
        _msgs.add(_Msg(role: 'user', text: chipText));
      });
      _history.add({'role': 'user', 'content': chipText});
      _sendToAIWithIntent(
        intent: KoalaIntent.designerMatch,
        params: {'style': style, 'budget': chipText},
      );
      return;
    }

    // Normal chip — function-calling destekli intent olarak gönder
    _sendToAI(text: chipText);
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
      maxWidth: 1920,
      imageQuality: 85,
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
              'assets/images/koalas.png',
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
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: Stack(
              children: [
                _msgs.isEmpty && !_loading
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
          if (_pendingPhoto != null) _buildPhotoPreview(),
          // Quick action chips — show when chat has messages and not loading
          if (_msgs.isNotEmpty && !_loading) _buildQuickActions(),
          _buildInputBar(btm),
        ],
      ),
    );
  }

  // ── Quick action chips above input ──
  Widget _buildQuickActions() => Container(
    padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _quickChip(Icons.color_lens_rounded, 'Renk öner', () => _sendToAI(text: 'Bu odaya renk öner')),
          _quickChip(Icons.shopping_bag_rounded, 'Ürün bul', () => _sendToAI(text: 'Bana ürün öner')),
          _quickChip(Icons.person_rounded, 'Uzman bul', () => _sendToAI(text: 'Bana tasarımcı öner')),
          _quickChip(Icons.auto_awesome_rounded, 'Stil analizi', () => _sendToAI(text: 'Tarzımı analiz et')),
        ],
      ),
    ),
  );

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
              'assets/images/koalas.png',
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

    // If we have profile data, personalize the suggestions
    if (style != null && style.isNotEmpty) {
      final roomLabel = room ?? 'Odamı';
      return [
        _suggestionChip(Icons.palette_rounded, '$style tarzda $roomLabel yenile', KoalaColors.accentDeep,
          () => _sendToAI(text: '$roomLabel $style tarzda yeniden tasarla')),
        _suggestionChip(Icons.color_lens_rounded, '$roomLabel için 3 renk öner', KoalaColors.pink,
          () => _sendToAI(text: '$roomLabel için $style tarzıma uygun 3 renk öner')),
        if (budget != null && budget.isNotEmpty)
          _suggestionChip(Icons.account_balance_wallet_rounded, '$budget bütçeyle plan', KoalaColors.greenAlt,
            () => _sendToAI(text: '$roomLabel için $budget bütçeyle $style dekorasyon planı çıkar')),
        _suggestionChip(Icons.person_search_rounded, 'Bana uygun tasarımcı', KoalaColors.blue,
          () => _sendToAI(text: '$style tarzda çalışan bir iç mimar öner')),
      ];
    }

    // Default starters (no profile)
    return [
      _suggestionChip(Icons.home_rounded, 'Odamı yenile', KoalaColors.accentDeep,
        () => _sendToAI(text: 'Odamı yeniden tasarla')),
      _suggestionChip(Icons.color_lens_rounded, 'Renk öner', KoalaColors.pink,
        () => _sendToAI(text: 'Odama renk öner')),
      _suggestionChip(Icons.account_balance_wallet_rounded, 'Bütçe planla', KoalaColors.greenAlt,
        () => _sendToAI(text: 'Bütçeme uygun dekorasyon planı')),
      _suggestionChip(Icons.person_search_rounded, 'Tasarımcı bul', KoalaColors.blue,
        () => _sendToAI(text: 'Bana uygun tasarımcı öner')),
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
                      child: Text(
                        msg.text!,
                        style: TextStyle(
                          fontSize: 14,
                          color: isUser ? Colors.white : _ink,
                          height: 1.5,
                        ),
                      ),
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
              _fallbackChip(Icons.color_lens_rounded, 'Renk öner', () => _sendToAI(text: 'Bu odaya renk öner')),
              _fallbackChip(Icons.shopping_bag_rounded, 'Ürün bul', () => _sendToAI(text: 'Bana ürün öner')),
              _fallbackChip(Icons.person_rounded, 'Uzman bul', () => _sendToAI(text: 'Bana tasarımcı öner')),
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
      'assets/images/koalas.png',
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
    margin: const EdgeInsets.fromLTRB(14, 0, 14, 4),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      color: Colors.white,
    ),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(
            _pendingPhoto!,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Fotoğraf hazır',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ),
        GestureDetector(
          onTap: () => setState(() => _pendingPhoto = null),
          child: Icon(
            Icons.close_rounded,
            size: 18,
            color: Colors.grey.shade400,
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
                  hintText: _loading ? 'Koala düşünüyor...' : 'Koala\'ya sor...',
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
            onPressed: () => Navigator.of(context).pushNamed('/saved'),
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

  Widget _renderCard(KoalaCard card) {
    Analytics.aiCardDisplayed(card.type);
    switch (card.type) {
      case 'question_chips':
        return _QuestionChips(card.data, onTap: _onChipTap);
      case 'style_analysis':
        return _StyleAnalysis(card.data);
      case 'product_grid':
        final productsRaw = card.data['products'] as List<dynamic>? ?? [];
        final carouselItems = productsRaw
            .map(
              (p) =>
                  ProductCarouselItem.fromCardData(p as Map<String, dynamic>),
            )
            .toList();
        return ProductCarousel(
          title: card.data['title'] as String? ?? 'Önerilen Ürünler',
          products: carouselItems,
          onAskAI: (product, question) {
            _sendToAI(text: '"${product.name}" hakkında: $question');
          },
        );
      case 'color_palette':
        return _ColorPalette(card.data);
      case 'designer_card':
        return _DesignerCards(card.data);
      case 'budget_plan':
        return _BudgetPlan(card.data);
      case 'quick_tips':
        return _QuickTips(card.data);
      case 'before_after':
        return _BeforeAfter(card.data);
      case 'image_prompt':
        return _ImagePrompt(card.data, onGenerate: _generateImage);
      case 'architect_cta':
        return _ArchitectCTA(card.data);
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
          child: Text(title, style: const TextStyle(fontSize: 13, color: _ink)),
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
        duration: const Duration(milliseconds: 400),
      )..repeat(reverse: true),
    );
    for (var i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 150), () {
        if (mounted) _c[i].forward();
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
        builder: (_, _) => Transform.translate(
          offset: Offset(0, -3 * _c[i].value),
          child: Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.lerp(KoalaColors.accentLight, _accent, _c[i].value),
            ),
          ),
        ),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════
// QUESTION CHIPS
// ═══════════════════════════════════════════════════════
class _QuestionChips extends StatefulWidget {
  const _QuestionChips(this.d, {required this.onTap});
  final Map<String, dynamic> d;
  final void Function(String) onTap;

  @override
  State<_QuestionChips> createState() => _QuestionChipsState();
}

class _QuestionChipsState extends State<_QuestionChips> {
  String? _selectedChip;

  @override
  Widget build(BuildContext context) {
    final question = widget.d['question'] as String? ?? widget.d['title'] as String? ?? '';
    final raw = widget.d['chips'] ?? widget.d['options'] ?? [];
    if (raw is! List || (raw).isEmpty) return const SizedBox.shrink();

    final chips = <Map<String, String>>[];
    for (final item in raw) {
      if (item is String) {
        chips.add({'label': item, 'value': item});
      } else if (item is Map) {
        final label = (item['label'] ?? item['text'] ?? item.values.first ?? '')
            .toString();
        final value = (item['value'] ?? item['label'] ?? label).toString();
        chips.add({'label': label, 'value': value});
      }
    }

    final bool answered = _selectedChip != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        border: Border.all(color: KoalaColors.accentLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (question.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                question,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips
                .map(
                  (chip) {
                    final isSelected = _selectedChip == chip['label'];
                    return GestureDetector(
                      onTap: answered ? null : () {
                        setState(() => _selectedChip = chip['label']);
                        widget.onTap(chip['label']!);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          color: isSelected
                              ? _accent
                              : answered
                                  ? KoalaColors.surfaceMuted
                                  : _accentLight,
                          border: Border.all(
                            color: isSelected
                                ? _accent
                                : answered
                                    ? Colors.grey.shade200
                                    : _accent.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Text(
                          chip['label']!,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : answered
                                    ? Colors.grey.shade400
                                    : _accent,
                          ),
                        ),
                      ),
                    );
                  },
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// STYLE ANALYSIS
// ═══════════════════════════════════════════════════════
class _StyleAnalysis extends StatelessWidget {
  const _StyleAnalysis(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final colors =
        (d['color_palette'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final tags = (d['tags'] as List?)?.cast<String>() ?? [];
    final desc = d['description'] as String? ?? '';
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_R),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              gradient: LinearGradient(
                colors: [KoalaColors.accentDeep, KoalaColors.accentMuted],
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    d['style_name'] ?? 'Stil',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Colors
          if (colors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: colors
                    .map(
                      (c) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Column(
                            children: [
                              Container(
                                height: 44,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: _hex(c['hex'] ?? '#000'),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                c['name'] ?? '',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          // Description
          if (desc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                desc,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
              ),
            ),
          // Tags
          if (tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: tags
                    .map(
                      (t) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          color: _accentLight,
                        ),
                        child: Text(
                          t,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _accent,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// COLOR PALETTE
// ═══════════════════════════════════════════════════════
class _ColorPalette extends StatelessWidget {
  const _ColorPalette(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final colors = (d['colors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_R),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            d['title'] ?? 'Renk Paleti',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: colors
                .map(
                  (c) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        children: [
                          Container(
                            height: 52,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: _hex(c['hex'] ?? '#000'),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            c['name'] ?? '',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (c['usage'] != null)
                            Text(
                              c['usage'],
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.grey.shade400,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                            ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          if (d['tip'] != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: _accentLight,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('💡', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      d['tip'],
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// DESIGNER CARDS — with avatar, portfolio link
// ═══════════════════════════════════════════════════════
class _DesignerCards extends StatelessWidget {
  const _DesignerCards(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    // Gemini bazen designers dizisi yerine flat data gönderir — her iki formatı da handle et
    List<Map<String, dynamic>> designers;
    final rawDesigners = d['designers'];
    if (rawDesigners is List && rawDesigners.isNotEmpty) {
      designers = rawDesigners.cast<Map<String, dynamic>>();
    } else if (d['name'] != null) {
      // Flat format — kart kendisi tek bir tasarımcı
      designers = [d];
    } else {
      designers = [];
    }
    if (designers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Tasarımcı bilgisi yüklenemedi.', style: TextStyle(color: Colors.grey)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            'Sana Uygun Tasarımcılar',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
        ),
        ...designers.map((ds) {
          final name = ds['name'] as String? ?? '';
          final initials = name
              .split(' ')
              .map((w) => w.isNotEmpty ? w[0] : '')
              .take(2)
              .join()
              .toUpperCase();
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_R),
              color: Colors.white,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [_accent, KoalaColors.accentMuted],
                        ),
                      ),
                      child: Center(
                        child: Text(
                          initials,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
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
                            name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                          Text(
                            '${ds['title'] ?? 'İç Mimar'} · ${ds['specialty'] ?? ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (ds['rating'] != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: const Color(0xFFFFF7ED),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: KoalaColors.star,
                            ),
                            Text(
                              ' ${ds['rating']}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: KoalaColors.star,
                              ),
                            ),
                          ],
                        ),
                      ),
                    SaveButton(
                      itemType: SavedItemType.designer,
                      itemId: ds['id']?.toString() ?? name,
                      title: name,
                      subtitle: ds['title'] as String? ?? 'İç Mimar',
                      size: 20,
                      onToggled: (isSaved) {
                        if (isSaved) {
                          ProfileFeedbackService.recordSaveSignal(
                            itemTitle: name,
                            style: ds['specialty'] as String?,
                          );
                        }
                      },
                    ),
                  ],
                ),
                if (ds['bio'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      ds['bio'],
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                      maxLines: 2,
                    ),
                  ),
                // Response time indicator
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 8, height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: KoalaColors.greenAlt,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        ds['city'] != null ? 'Genellikle 24 saat içinde yanıtlar · ${ds['city']}' : 'Genellikle 24 saat içinde yanıtlar',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
                // Portfolio görselleri
                if (ds['portfolio_images'] != null && (ds['portfolio_images'] as List).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: SizedBox(
                      height: 72,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: (ds['portfolio_images'] as List).length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            (ds['portfolio_images'] as List)[i] as String,
                            width: 96,
                            height: 72,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 96, height: 72,
                              color: KoalaColors.surfaceMuted,
                              child: Icon(Icons.image_rounded, color: KoalaColors.textTer),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (ds['min_budget'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'Min: ${ds['min_budget']}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                // Primary CTA — Tasarımcıya Yaz (full-width)
                GestureDetector(
                  onTap: () async {
                    final designerId = ds['id']?.toString() ?? '';
                    if (designerId.isEmpty) return;
                    HapticFeedback.lightImpact();
                    final conv = await MessagingService.getOrCreateConversation(
                      designerId: designerId,
                      contextType: 'designer',
                      contextId: designerId,
                      contextTitle: name,
                    );
                    if (conv != null && context.mounted) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ConversationDetailScreen(
                            conversationId: conv['id'] as String,
                            designerName: name,
                            designerAvatarUrl: ds['avatar_url']?.toString(),
                          ),
                        ),
                      );
                    } else if (context.mounted) {
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: KoalaColors.errorBright,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          duration: const Duration(seconds: 3),
                          content: const Row(
                            children: [
                              Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Expanded(child: Text('Bağlantı kurulamadı. Lütfen tekrar deneyin.', style: TextStyle(color: Colors.white, fontSize: 13))),
                            ],
                          ),
                        ),
                      );
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: KoalaColors.greenAlt,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_rounded, size: 15, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'Tasarımcıya Yaz',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Secondary — Profili Gör (full-width outline)
                GestureDetector(
                  onTap: () {
                    final designerId = ds['id']?.toString() ?? '';
                    final profileUrl = designerId.isNotEmpty
                        ? 'https://www.evlumba.com/tasarimci/$designerId'
                        : 'https://www.evlumba.com/tasarimcilar';
                    launchUrl(
                      Uri.parse(profileUrl),
                      mode: LaunchMode.inAppBrowserView,
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _accent.withValues(alpha: 0.25)),
                    ),
                    child: const Center(
                      child: Text(
                        'Profili Gör',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _accent,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
// BUDGET PLAN
// ═══════════════════════════════════════════════════════
class _BudgetPlan extends StatelessWidget {
  const _BudgetPlan(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final items = (d['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_R),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [KoalaColors.accentDeep, KoalaColors.accentMuted],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('💰', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text(
                'Bütçe Planı',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: Colors.white.withValues(alpha:0.2),
                ),
                child: Text(
                  d['total_budget'] ?? '',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...items.map(
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i['priority'] == 'high'
                          ? KoalaColors.greenBright
                          : Colors.white.withValues(alpha:0.4),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      i['category'] ?? '',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Text(
                    i['amount'] ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha:0.9),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (d['tip'] != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Colors.white.withValues(alpha:0.12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('💡', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      d['tip'],
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha:0.85),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// QUICK TIPS
// ═══════════════════════════════════════════════════════
class _QuickTips extends StatelessWidget {
  const _QuickTips(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final tips = (d['tips'] as List?) ?? [];
    // Parse tips — could be strings, maps with text/emoji/title, etc.
    final parsed = <String>[];
    for (final t in tips) {
      if (t is String && t.trim().isNotEmpty) {
        parsed.add(t);
      } else if (t is Map) {
        final text = t['text'] ?? t['description'] ?? t['title'] ?? '';
        final emoji = t['emoji'] ?? '';
        final combined = '$emoji $text'.trim();
        if (combined.isNotEmpty) parsed.add(combined);
      }
    }
    if (parsed.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_R),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '💡 İpuçları',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          const SizedBox(height: 10),
          ...parsed.map(
            (tip) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 7),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _accent.withValues(alpha:0.5),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tip,
                      style: const TextStyle(
                        fontSize: 13,
                        color: KoalaColors.ink,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// BEFORE/AFTER
// ═══════════════════════════════════════════════════════
class _BeforeAfter extends StatelessWidget {
  const _BeforeAfter(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final changes = (d['changes'] as List?)?.cast<String>() ?? [];
    final imageUrl = d['image_url'] as String? ?? '';
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_R),
        gradient: const LinearGradient(
          colors: [KoalaColors.accentSoft, KoalaColors.greenLight],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Proje görseli
          if (imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(_R)),
              child: Image.network(
                imageUrl,
                width: double.infinity,
                height: 160,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          Text(
            d['title'] ?? '',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          const SizedBox(height: 10),
          ...changes.map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: KoalaColors.greenDark,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      c,
                      style: const TextStyle(
                        fontSize: 13,
                        color: KoalaColors.ink,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (d['estimated_budget'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Tahmini: ${d['estimated_budget']}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _accent,
                ),
              ),
            ),
          // Tasarımcıyla iletişim — designer_id varsa göster
          if (d['designer_id'] != null && (d['designer_id'] as String).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: GestureDetector(
                onTap: () async {
                  final designerId = d['designer_id'] as String;
                  final title = d['title'] as String? ?? 'Tasarım';
                  HapticFeedback.lightImpact();
                  final conv = await MessagingService.getOrCreateConversation(
                    designerId: designerId,
                    contextType: 'project',
                    contextId: designerId,
                    contextTitle: title,
                  );
                  if (conv != null && context.mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ConversationDetailScreen(
                          conversationId: conv['id'] as String,
                          designerName: d['designer_name'] as String? ?? 'Tasarımcı',
                        ),
                      ),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: KoalaColors.greenAlt,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          duration: const Duration(seconds: 4),
                          content: const Row(
                            children: [
                              Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Expanded(child: Text('Mesajınız iletildi! Genellikle 24 saat içinde dönüş yapılır.', style: TextStyle(color: Colors.white, fontSize: 13))),
                            ],
                          ),
                        ),
                      );
                    }
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: KoalaColors.greenAlt,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_rounded, size: 14, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'Bu Tasarımcıyla Çalış',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
              ],
            ),
          ), // close inner Padding
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// IMAGE PROMPT — generate button
// ═══════════════════════════════════════════════════════
class _ImagePrompt extends StatelessWidget {
  const _ImagePrompt(this.d, {required this.onGenerate});
  final Map<String, dynamic> d;
  final void Function(String) onGenerate;
  @override
  Widget build(BuildContext context) {
    final title = d['title'] as String? ?? 'Tasarım Görseli';
    final prompt = d['prompt'] as String? ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_R),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [KoalaColors.accentSoft, const Color(0xFFE8F4FD)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 18, color: _accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () => onGenerate(prompt),
              icon: const Icon(Icons.brush_rounded, size: 18),
              label: const Text(
                'Görseli Oluştur',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArchitectCTA extends StatelessWidget {
  const _ArchitectCTA(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [KoalaColors.accentDeep, KoalaColors.accentMuted, KoalaColors.accentMuted],
        ),
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
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white.withValues(alpha:0.2),
                ),
                child: const Icon(
                  Icons.videocam_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'İç Mimarla Konuş',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'evlumba uzmanlarından biri sana yardımcı olsun',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              SizedBox(
                width: 72,
                height: 28,
                child: Stack(
                  children: [
                    _dot(0, KoalaColors.pink),
                    _dot(18, KoalaColors.blue),
                    _dot(36, KoalaColors.greenAlt),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Uzman iç mimarlar seni bekliyor',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha:0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DesignersScreen()),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
              ),
              child: const Center(
                child: Text(
                  'Uzman Bul ve Ücretsiz Görüş',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: KoalaColors.accentDeep,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(double left, Color color) => Positioned(
    left: left,
    child: Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white.withValues(alpha:0.3), width: 2),
      ),
      child: const Icon(Icons.person_rounded, size: 14, color: Colors.white),
    ),
  );
}

class _ShimmerBlock extends StatefulWidget {
  const _ShimmerBlock({required this.width, required this.height, this.radius = 14});
  final double width, height, radius;
  @override
  State<_ShimmerBlock> createState() => _ShimmerBlockState();
}

class _ShimmerBlockState extends State<_ShimmerBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, _) => Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        gradient: LinearGradient(
          begin: Alignment(-1.0 + 2.0 * _ctrl.value, 0),
          end: Alignment(-1.0 + 2.0 * _ctrl.value + 1, 0),
          colors: const [
            KoalaColors.accentSoft,
            KoalaColors.accentLight,
            KoalaColors.accentSoft,
          ],
        ),
      ),
    ),
  );
}
