import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui show ImageFilter;
import 'package:crypto/crypto.dart' show sha1;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html;
import '../../../core/theme/koala_tokens.dart';
import '../../../services/background_gen.dart';
import '../../../services/feedback_service.dart';
import '../../../services/saved_items_service.dart';
import '../../../services/upload_service.dart';
import '../widgets/before_after.dart';

/// Tasarım Sonucu — sade, snaphome benzeri.
/// Top bar (Tasarım Sonucu / paylaş / X) + before/after compare + 2 aksiyon
/// (İndir / Başka Tarz) + büyük "Gerçeğe Dönüştür" CTA.
/// Sonuç oluşur oluşmaz otomatik koleksiyona kaydedilir.
class ResultStage extends StatefulWidget {
  final Uint8List beforeBytes;
  final String afterSrc;
  final String room;
  final String theme;
  final String? paletteTr;
  final String? layoutTr;
  final bool mock;
  final VoidCallback onRetry;
  final VoidCallback onNewStyle;
  final VoidCallback onRestart;
  final VoidCallback onPro;

  /// Edit sheet'ten "Yenile" basıldığında çağrılır.
  final void Function(EditDesignChange change)? onApplyEdit;

  /// Detail (Projeler'den açılan) ekranında auto-save'i atla — zaten kayıtlı.
  final bool skipAutoSave;

  const ResultStage({
    super.key,
    required this.beforeBytes,
    required this.afterSrc,
    required this.room,
    required this.theme,
    this.paletteTr,
    this.layoutTr,
    required this.mock,
    required this.onRetry,
    required this.onNewStyle,
    required this.onRestart,
    required this.onPro,
    this.onApplyEdit,
    this.skipAutoSave = false,
  });

  @override
  State<ResultStage> createState() => _ResultStageState();
}

class _ResultStageState extends State<ResultStage> {
  late final String _itemId = sha1
      .convert(
        '${widget.theme}|${widget.afterSrc}|${widget.beforeBytes.length}'
            .codeUnits,
      )
      .toString()
      .substring(0, 24);

  bool _downloading = false;
  bool? _liked; // null = no vote, true = like, false = dislike
  bool _votingNow = false;
  bool _feedbackHidden = false;

  @override
  void initState() {
    super.initState();
    if (!widget.skipAutoSave) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoSave());
    }
  }

  Future<void> _autoSave() async {
    // BackgroundGen complete'i ÖNCE fire et — pending kart %100'e atlasın,
    // before upload + DB save backend'de devam etsin (UI bloklanmasın).
    BackgroundGen.complete(afterUrl: widget.afterSrc);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      debugPrint('[ResultStage] auto-save skipped: anon/null user');
      return;
    }
    // Before upload async — başarısız olsa bile after_url ile kayıt geçsin.
    final beforeUrl = await UploadService.uploadBefore(widget.beforeBytes);
    // item_type='project' → Projelerim sekmesinde listelenir.
    // kind='ai_design' → before/after AI tasarımı (manuel proje değil).
    final ok = await SavedItemsService.saveItem(
      type: SavedItemType.project,
      itemId: _itemId,
      title: 'Yeni ${widget.room}',
      imageUrl: widget.afterSrc,
      subtitle: 'İç Mimarlık · ${widget.theme}',
      extraData: {
        'kind': 'ai_design',
        'ai_generated': true,
        'room': widget.room,
        'style': widget.theme,
        'theme': widget.theme,
        'palette': widget.paletteTr,
        'layout': widget.layoutTr,
        'after_url': widget.afterSrc,
        if (beforeUrl != null) 'before_url': beforeUrl,
        'category': 'interior_design',
        'saved_at': DateTime.now().toIso8601String(),
      },
    );
    debugPrint(
        '[ResultStage] auto-save ok=$ok err=${SavedItemsService.lastError}');
  }

  Future<void> _share() async {
    HapticFeedback.selectionClick();
    final text = 'Koala ile ${widget.theme} tarzında ${widget.room} tasarımım: '
        'https://www.koalatutor.com';
    try {
      await Share.share(text);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      _toast('Bağlantı kopyalandı');
    }
  }

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    HapticFeedback.selectionClick();
    try {
      final src = widget.afterSrc;
      Uint8List rawBytes;
      if (src.startsWith('data:image')) {
        final commaIdx = src.indexOf(',');
        rawBytes = Uint8List.fromList(base64Decode(src.substring(commaIdx + 1)));
      } else {
        // Network fetch — Supabase storage CORS allowed.
        final resp = await http.get(Uri.parse(src));
        if (resp.statusCode != 200) throw 'fetch_failed_${resp.statusCode}';
        rawBytes = resp.bodyBytes;
      }

      final optimized = await _optimizeForDownload(rawBytes);
      final filename = 'koala-${DateTime.now().millisecondsSinceEpoch}.jpg';

      if (kIsWeb) {
        // Web (özellikle iOS Safari): Web Share Files API → native iOS share
        // sheet → "Save Image" → Photos. Browser destekliyorsa share, yoksa
        // anchor download fallback.
        final supportsShare =
            html.window.navigator.share != null;
        if (supportsShare) {
          try {
            await Share.shareXFiles(
              [
                XFile.fromData(optimized,
                    mimeType: 'image/jpeg', name: filename)
              ],
              text: 'Koala tasarımım',
            );
            if (!mounted) return;
            _toast('Paylaş > Resmi Kaydet ile galerine ekle',
                icon: LucideIcons.checkCircle2);
            return;
          } catch (_) {
            // Share iptal edildiyse veya destek yoksa → anchor fallback
          }
        }
        // Anchor + download attribute — Downloads klasörüne iner.
        final blob = html.Blob([optimized], 'image/jpeg');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', filename)
          ..click();
        html.Url.revokeObjectUrl(url);
        if (!mounted) return;
        _toast('Tasarım indirildi', icon: LucideIcons.checkCircle2);
      } else {
        // Mobil native: gal ile direkt film rulosuna.
        final hasAccess = await Gal.hasAccess();
        if (!hasAccess) await Gal.requestAccess();
        await Gal.putImageBytes(optimized, name: filename);
        if (!mounted) return;
        _toast('Galerine kaydedildi', icon: LucideIcons.checkCircle2);
      }
    } catch (e) {
      if (!mounted) return;
      _toast('İndirilemedi: $e', icon: LucideIcons.alertCircle);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// 1280 long-edge'e indirir, JPEG q80 — dosya boyutu ~150-300KB.
  Future<Uint8List> _optimizeForDownload(Uint8List input) async {
    try {
      final decoded = img.decodeImage(input);
      if (decoded == null) return input;
      const maxEdge = 1280;
      final w = decoded.width;
      final h = decoded.height;
      img.Image scaled = decoded;
      if (w > maxEdge || h > maxEdge) {
        if (w >= h) {
          scaled = img.copyResize(decoded, width: maxEdge);
        } else {
          scaled = img.copyResize(decoded, height: maxEdge);
        }
      }
      return Uint8List.fromList(img.encodeJpg(scaled, quality: 80));
    } catch (_) {
      return input;
    }
  }

  Future<void> _vote(bool liked) async {
    if (_votingNow) return;
    HapticFeedback.lightImpact();
    setState(() {
      _liked = liked;
      _votingNow = true;
    });
    // Toast'u ANINDA göster — backend response'u beklemeye gerek yok.
    _showPrettyToast(
      liked
          ? 'Teşekkürler — bu tarzdan daha fazla göstereceğiz'
          : 'Aldık, daha iyisini deneyeceğiz',
      icon: liked ? LucideIcons.thumbsUp : LucideIcons.thumbsDown,
      tint: liked ? KoalaColors.accentDeep : KoalaColors.textSec,
    );
    // Yavaşça kaybolsun
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _feedbackHidden = true);
    });
    // Backend'e fire-and-forget — anonymousta sessizce skip et
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      unawaited(FeedbackService.submit(
        designId: _itemId,
        liked: liked,
        room: widget.room,
        theme: widget.theme,
        palette: widget.paletteTr,
        layout: widget.layoutTr,
        afterUrl: widget.afterSrc,
      ));
    }
    if (mounted) setState(() => _votingNow = false);
  }

  void _showPrettyToast(String msg, {IconData? icon, Color? tint}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        padding: EdgeInsets.zero,
        duration: const Duration(milliseconds: 2400),
        content: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: KoalaColors.text.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(14),
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
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: Colors.white),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      msg,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toast(String msg, {IconData? icon}) =>
      _showPrettyToast(msg, icon: icon);

  Future<void> _openEditSheet() async {
    HapticFeedback.selectionClick();
    final change = await showModalBottomSheet<EditDesignChange>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EditDesignSheet(
        room: widget.room,
        theme: widget.theme,
        palette: widget.paletteTr ?? 'Beni şaşırt',
        layout: widget.layoutTr ?? 'Orijinalini Koru',
      ),
    );
    if (change == null || !mounted) return;
    if (widget.onApplyEdit != null) {
      widget.onApplyEdit!(change);
    } else if (change.styleValue != null) {
      widget.onNewStyle();
    } else {
      widget.onRetry();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ─── Top bar ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Tasarım Sonucu',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: KoalaColors.text,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              _IconBtn(icon: LucideIcons.x, onTap: widget.onRestart),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              return SingleChildScrollView(
                // İçerik viewport'a sığarsa scroll YOK; aşarsa normal scroll.
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  KoalaSpacing.xl,
                  8,
                  KoalaSpacing.xl,
                  16,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: 0,
                    maxHeight: constraints.maxHeight + 0.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MiniChip(
                      icon: LucideIcons.home,
                      label: widget.room,
                      tinted: true,
                    ),
                    _MiniChip(
                      icon: LucideIcons.palette,
                      label: widget.theme,
                    ),
                  ],
                ),
                const SizedBox(height: KoalaSpacing.md),
                BeforeAfter(
                  beforeBytes: widget.beforeBytes,
                  afterSrc: widget.afterSrc,
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.easeOutCubic,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    child: _feedbackHidden
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(
                                top: KoalaSpacing.md),
                            child: _FeedbackRow(
                              liked: _liked,
                              busy: _votingNow,
                              onVote: _vote,
                            ),
                          ),
                  ),
                ),
                if (widget.mock) ...[
                  const SizedBox(height: KoalaSpacing.md),
                  _MockBanner(),
                ],
              ],
            ),
                  ),
                );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _ActionTile(
                        icon: _downloading
                            ? LucideIcons.loader
                            : LucideIcons.download,
                        label: 'İndir',
                        onTap: _download,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionTile(
                        icon: LucideIcons.sliders,
                        label: 'Başka Tarz',
                        onTap: _openEditSheet,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: KoalaColors.accentDeep,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: widget.onPro,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Bu tasarımı gerçeğe dönüştür',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(LucideIcons.arrowRight, size: 18),
                      ],
                    ),
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

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: KoalaColors.surface,
      shape: const CircleBorder(),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: KoalaColors.border, width: 0.6),
          ),
          child: Icon(icon, size: 20, color: KoalaColors.text),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.icon,
    required this.label,
    this.tinted = false,
  });
  final IconData icon;
  final String label;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
          Icon(
            icon,
            size: 14,
            color: tinted ? KoalaColors.accentDeep : KoalaColors.textSec,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: tinted ? KoalaColors.accentDeep : KoalaColors.text,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
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
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: KoalaColors.border, width: 0.6),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: KoalaColors.text),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: KoalaColors.text,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedbackRow extends StatelessWidget {
  const _FeedbackRow({
    required this.liked,
    required this.busy,
    required this.onVote,
  });
  final bool? liked;
  final bool busy;
  final void Function(bool) onVote;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: KoalaColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KoalaColors.border, width: 0.6),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Bu tasarımı beğendin mi?',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: KoalaColors.text,
                letterSpacing: -0.1,
              ),
            ),
          ),
          _VoteButton(
            icon: LucideIcons.thumbsUp,
            active: liked == true,
            disabled: busy,
            onTap: () => onVote(true),
          ),
          const SizedBox(width: 8),
          _VoteButton(
            icon: LucideIcons.thumbsDown,
            active: liked == false,
            disabled: busy,
            onTap: () => onVote(false),
          ),
        ],
      ),
    );
  }
}

class _VoteButton extends StatelessWidget {
  const _VoteButton({
    required this.icon,
    required this.active,
    required this.disabled,
    required this.onTap,
  });
  final IconData icon;
  final bool active;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? KoalaColors.accentSoft : Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: disabled ? null : onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: active
                  ? KoalaColors.accentDeep
                  : KoalaColors.border,
              width: active ? 1.4 : 0.8,
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: active ? KoalaColors.accentDeep : KoalaColors.textSec,
          ),
        ),
      ),
    );
  }
}

class _MockBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KoalaSpacing.md,
        vertical: KoalaSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: KoalaColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(KoalaRadius.md),
        border: Border.all(
          color: KoalaColors.warning.withValues(alpha: 0.45),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.info, size: 16, color: KoalaColors.warning),
          const SizedBox(width: KoalaSpacing.sm),
          Expanded(
            child: Text(
              'Demo · sunucuda anahtar ayarlandığında gerçek görseller gelir.',
              style: KoalaText.bodySmall.copyWith(
                color: KoalaColors.warning,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Edit sheet'ten flow'a yansıtılacak konfigürasyon değişiklikleri.
class EditDesignChange {
  final String? roomTr;
  final String? layoutTr;
  final String? styleTr;
  final String? styleValue; // İngilizce slug — restyle prompt için
  final String? paletteTr;

  const EditDesignChange({
    this.roomTr,
    this.layoutTr,
    this.styleTr,
    this.styleValue,
    this.paletteTr,
  });
}

/// Snaphome benzeri "Ayarlar" sheet — 4 alanın HEPSİ değiştirilebilir.
/// Her satır tıklanınca alttan bir sub-sheet açılır, kullanıcı seçer.
class _EditDesignSheet extends StatefulWidget {
  final String room;
  final String theme;
  final String palette;
  final String layout;

  const _EditDesignSheet({
    required this.room,
    required this.theme,
    required this.palette,
    required this.layout,
  });

  @override
  State<_EditDesignSheet> createState() => _EditDesignSheetState();
}

class _EditDesignSheetState extends State<_EditDesignSheet> {
  late String _room = widget.room;
  late String _theme = widget.theme;
  late String _palette = widget.palette;
  late String _layout = widget.layout;
  String? _styleValue; // değişirse set edilir

  static const _rooms = <_PickerOption>[
    _PickerOption('living_room', 'Oturma Odası', icon: LucideIcons.sofa),
    _PickerOption('bedroom', 'Yatak Odası', icon: LucideIcons.bed),
    _PickerOption('dining_room', 'Yemek Odası', icon: LucideIcons.utensilsCrossed),
    _PickerOption('bathroom', 'Banyo', icon: LucideIcons.bath),
    _PickerOption('kitchen', 'Mutfak', icon: LucideIcons.chefHat),
    _PickerOption('office', 'Çalışma Odası', icon: LucideIcons.laptop),
    _PickerOption('kids_room', 'Çocuk Odası', icon: LucideIcons.baby),
    _PickerOption('hall', 'Antre', icon: LucideIcons.doorOpen),
  ];

  static const _layouts = <_PickerOption>[
    _PickerOption('preserve', 'Orijinalini Koru',
        icon: LucideIcons.lock,
        description: 'Mimari aynı, sadece dekor değişir'),
    _PickerOption('innovate', 'Yenilikçi',
        icon: LucideIcons.shuffle,
        description: 'Yerleşim ve mobilya yeniden düşünülür'),
  ];

  static const _themes = <_PickerOption>[
    _PickerOption('Minimalist', 'Minimalist',
        imageSlug: 'minimalist', tag: 'Temiz çizgi, az eşya'),
    _PickerOption('Scandinavian', 'Skandinav',
        imageSlug: 'scandinavian', tag: 'Açık ahşap, sıcak'),
    _PickerOption('Japandi', 'Japandi',
        imageSlug: 'japandi', tag: 'Wabi-sabi, sade huzur'),
    _PickerOption('Modern', 'Modern',
        imageSlug: 'modern', tag: 'Düz çizgi, metal, cam'),
    _PickerOption('Bohemian', 'Bohem',
        imageSlug: 'bohemian', tag: 'Desenli, bitki, renkli'),
    _PickerOption('Industrial', 'Endüstriyel',
        imageSlug: 'industrial', tag: 'Tuğla, beton, koyu'),
  ];

  static const _palettes = <_PickerOption>[
    _PickerOption('surprise', 'Beni şaşırt', surprise: true),
    _PickerOption('soft_neutrals', 'Soluk Form',
        swatch: [0xFFE8E4DC, 0xFFCAC2B5, 0xFF8C8478, 0xFF514B42, 0xFF2B2724]),
    _PickerOption('millennium_grey', 'Milenyum Grisi',
        swatch: [0xFFEAEAEA, 0xFFC2C2C2, 0xFF9C9C9C, 0xFF6E6E6E, 0xFF3D3D3D]),
    _PickerOption('warm_beige', 'Rahat Bej',
        swatch: [0xFFF1E8DC, 0xFFE5C9A8, 0xFFC8A07A, 0xFFA67753, 0xFF755338]),
    _PickerOption('earthy', 'Dünya Sakinliği',
        swatch: [0xFFE2DDD0, 0xFF9C9078, 0xFF8B7355, 0xFF5C523F, 0xFF332A22]),
    _PickerOption('sage_garden', 'Sisli Bahçe',
        swatch: [0xFFD0DCDB, 0xFFA9B5A2, 0xFF7F8C7C, 0xFF54635A, 0xFF2B3633]),
    _PickerOption('antique_sage', 'Antika Bilge',
        swatch: [0xFFD5D2BB, 0xFFA9A28A, 0xFF7F7864, 0xFF55503E, 0xFF302C22]),
    _PickerOption('ocean_mist', 'Okyanus Sisi',
        swatch: [0xFFC9DAE3, 0xFF98AEBA, 0xFF63798A, 0xFF394B5A, 0xFF1A2530]),
    _PickerOption('twilight', 'Alacakaranlık',
        swatch: [0xFF1A2238, 0xFF38384F, 0xFF6E6A93, 0xFFB7AECB, 0xFFE3DEEC]),
    _PickerOption('bordeaux', 'Bordo Esinti',
        swatch: [0xFF3A1F2A, 0xFF6E2D3D, 0xFFA45B6E, 0xFFD4A5B0, 0xFFEBD6DC]),
  ];

  Future<void> _openPicker({
    required String title,
    required List<_PickerOption> options,
    required String selected,
    required _PickerKind kind,
    required void Function(String value, String label) onPick,
    String? roomSlug,
  }) async {
    HapticFeedback.selectionClick();
    final picked = await showModalBottomSheet<_PickerOption>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PickerSheet(
        title: title,
        options: options,
        selectedLabel: selected,
        kind: kind,
        roomSlug: roomSlug,
      ),
    );
    if (picked == null) return;
    onPick(picked.value, picked.label);
  }

  void _apply() {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(
      EditDesignChange(
        roomTr: _room == widget.room ? null : _room,
        layoutTr: _layout == widget.layout ? null : _layout,
        styleTr: _theme == widget.theme ? null : _theme,
        styleValue: _styleValue,
        paletteTr: _palette == widget.palette ? null : _palette,
      ),
    );
  }

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: KoalaColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Ayarlar',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: KoalaColors.text,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.x, color: KoalaColors.text),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _row(LucideIcons.layers, 'Oda Tipi', _room, () {
            _openPicker(
              title: 'Oda Tipi',
              options: _rooms,
              selected: _room,
              kind: _PickerKind.room,
              onPick: (_, label) => setState(() => _room = label),
            );
          }),
          _divider(),
          _row(LucideIcons.box, 'Yapı', _layout, () {
            _openPicker(
              title: 'Yapı',
              options: _layouts,
              selected: _layout,
              kind: _PickerKind.layout,
              onPick: (_, label) => setState(() => _layout = label),
            );
          }),
          _divider(),
          _row(LucideIcons.brush, 'Tarz', _theme, () {
            _openPicker(
              title: 'Tarz',
              options: _themes,
              selected: _theme,
              kind: _PickerKind.style,
              roomSlug: _roomSlugFor(_room),
              onPick: (value, label) => setState(() {
                _theme = label;
                _styleValue = value;
              }),
            );
          }),
          _divider(),
          _row(LucideIcons.palette, 'Renk', _palette, () {
            _openPicker(
              title: 'Renk',
              options: _palettes,
              selected: _palette,
              kind: _PickerKind.palette,
              onPick: (_, label) => setState(() => _palette = label),
            );
          }),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: KoalaColors.accentDeep,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _apply,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text(
                'Yenile',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: KoalaColors.text),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: KoalaColors.text,
                  letterSpacing: -0.1,
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: KoalaColors.textSec,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: KoalaColors.textSec,
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Container(
        height: 0.5,
        color: KoalaColors.border,
      );

  String _roomSlugFor(String roomTr) {
    final r = roomTr.toLowerCase();
    if (r.contains('yatak')) return 'bedroom';
    if (r.contains('mutf')) return 'kitchen';
    if (r.contains('banyo')) return 'bathroom';
    if (r.contains('yemek')) return 'dining_room';
    if (r.contains('çal') || r.contains('cal')) return 'office';
    if (r.contains('çocuk') || r.contains('cocuk')) return 'kids_room';
    if (r.contains('antre')) return 'hall';
    return 'living_room';
  }
}

class _PickerOption {
  final String value;
  final String label;
  final IconData? icon;
  final String? imageSlug; // Tarz için: minimalist, scandinavian...
  final String? tag; // Tarz altyazısı
  final List<int>? swatch; // Renk hex'leri
  final bool surprise;
  final String? description;

  const _PickerOption(
    this.value,
    this.label, {
    this.icon,
    this.imageSlug,
    this.tag,
    this.swatch,
    this.surprise = false,
    this.description,
  });
}

enum _PickerKind { room, layout, style, palette }

/// Görsel alt-sayfa picker — wizard'daki 2'li grid kartları taklit eder.
class _PickerSheet extends StatelessWidget {
  final String title;
  final List<_PickerOption> options;
  final String selectedLabel;
  final _PickerKind kind;
  final String? roomSlug; // style picker'da hangi oda görseli

  const _PickerSheet({
    required this.title,
    required this.options,
    required this.selectedLabel,
    required this.kind,
    this.roomSlug,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: KoalaColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 14, 16, MediaQuery.of(context).padding.bottom + 16),
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
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: KoalaColors.text,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.x, color: KoalaColors.text),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(child: _grid(context)),
        ],
      ),
    );
  }

  Widget _grid(BuildContext context) {
    if (kind == _PickerKind.layout) {
      return GridView.count(
        shrinkWrap: true,
        crossAxisCount: 1,
        mainAxisSpacing: 12,
        childAspectRatio: 3.5,
        padding: const EdgeInsets.only(bottom: 12),
        children: options.map((o) => _LayoutCard(o: o, selected: o.label == selectedLabel)).toList(),
      );
    }
    final aspect = switch (kind) {
      _PickerKind.style => 0.78,
      _PickerKind.palette => 1.55,
      _PickerKind.room => 1.05,
      _PickerKind.layout => 3.5,
    };
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: aspect,
      padding: const EdgeInsets.only(bottom: 12),
      children: options.map((o) {
        final selected = o.label == selectedLabel;
        switch (kind) {
          case _PickerKind.style:
            return _StyleCard(o: o, selected: selected, roomSlug: roomSlug ?? 'living_room');
          case _PickerKind.palette:
            return _PaletteCard(o: o, selected: selected);
          case _PickerKind.room:
            return _RoomCard(o: o, selected: selected);
          case _PickerKind.layout:
            return _LayoutCard(o: o, selected: selected);
        }
      }).toList(),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.selected,
    required this.child,
    this.padding,
    this.borderOnSelect = true,
  });
  final bool selected;
  final Widget child;
  final EdgeInsets? padding;
  // false ise seçili olsa bile mor border yok (wizard'daki tarz/renk kartları
  // bu davranışta — sadece tik chip'i ile feedback).
  final bool borderOnSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(KoalaRadius.lg),
        onTap: () {
          final stateContext = context;
          if (Navigator.canPop(stateContext)) {
            Navigator.of(stateContext).pop(_pickedFromContext.of(context));
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: padding,
          decoration: BoxDecoration(
            color: KoalaColors.surface,
            borderRadius: BorderRadius.circular(KoalaRadius.lg),
            border: Border.all(
              color: borderOnSelect && selected
                  ? KoalaColors.accentDeep
                  : KoalaColors.border,
              width: borderOnSelect && selected ? 1.5 : 0.6,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }
}

class _pickedFromContext {
  static _PickerOption? of(BuildContext context) {
    return context.findAncestorWidgetOfExactType<_OptionInherited>()?.option;
  }
}

class _OptionInherited extends InheritedWidget {
  const _OptionInherited({required this.option, required super.child});
  final _PickerOption option;

  @override
  bool updateShouldNotify(_OptionInherited oldWidget) =>
      oldWidget.option != option;
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.o, required this.selected});
  final _PickerOption o;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    return _OptionInherited(
      option: o,
      child: _CardShell(
        selected: selected,
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? KoalaColors.accentSoft
                    : KoalaColors.surfaceAlt,
              ),
              child: Icon(
                o.icon ?? LucideIcons.home,
                size: 22,
                color:
                    selected ? KoalaColors.accentDeep : KoalaColors.text,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              o.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color:
                    selected ? KoalaColors.accentDeep : KoalaColors.text,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LayoutCard extends StatelessWidget {
  const _LayoutCard({required this.o, required this.selected});
  final _PickerOption o;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    return _OptionInherited(
      option: o,
      child: _CardShell(
        selected: selected,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? KoalaColors.accentSoft
                    : KoalaColors.surfaceAlt,
              ),
              child: Icon(
                o.icon,
                size: 18,
                color:
                    selected ? KoalaColors.accentDeep : KoalaColors.text,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    o.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected
                          ? KoalaColors.accentDeep
                          : KoalaColors.text,
                    ),
                  ),
                  if (o.description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      o.description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: KoalaColors.textSec,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              const Icon(LucideIcons.check,
                  size: 18, color: KoalaColors.accentDeep),
          ],
        ),
      ),
    );
  }
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.o,
    required this.selected,
    required this.roomSlug,
  });
  final _PickerOption o;
  final bool selected;
  final String roomSlug;

  @override
  Widget build(BuildContext context) {
    final url =
        'https://xgefjepaqnghaotqybpi.supabase.co/storage/v1/object/public/style-previews-sm/${o.imageSlug}-$roomSlug.jpg';
    return _OptionInherited(
      option: o,
      child: _CardShell(
        selected: selected,
        borderOnSelect: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(color: KoalaColors.surfaceAlt),
              loadingBuilder: (ctx, child, prog) =>
                  prog == null ? child : Container(color: KoalaColors.surfaceAlt),
            ),
            // Bottom gradient + label
            Container(
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
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    o.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (o.tag != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      o.tag!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: KoalaColors.accentDeep,
                  ),
                  child: const Icon(LucideIcons.check,
                      size: 12, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PaletteCard extends StatelessWidget {
  const _PaletteCard({required this.o, required this.selected});
  final _PickerOption o;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    return _OptionInherited(
      option: o,
      child: _CardShell(
        selected: selected,
        borderOnSelect: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: o.surprise
                  ? Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFFFFD3B6),
                            Color(0xFFFFAAA5),
                            Color(0xFFFF8B94),
                            Color(0xFFB9A4F0),
                            Color(0xFF8FCFD6),
                          ],
                        ),
                      ),
                      child: const Center(
                        child: Icon(LucideIcons.wand2,
                            size: 22, color: Colors.white),
                      ),
                    )
                  : Row(
                      children: (o.swatch ?? const [])
                          .map((c) =>
                              Expanded(child: Container(color: Color(c))))
                          .toList(),
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
              color: KoalaColors.surface,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      o.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                        color: selected
                            ? KoalaColors.accentDeep
                            : KoalaColors.text,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                  if (selected)
                    const Icon(
                      LucideIcons.check,
                      size: 14,
                      color: KoalaColors.accentDeep,
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
