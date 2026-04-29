// ═══════════════════════════════════════════════════════════════════
// MEKAN WIZARD — 4-step "Tasarımı Oluştur" config screen
//
// Kullanıcı fotoğraf seçtikten sonra bu ekran açılır. Adımlar:
//   1/4 — Oda Tipi      : Hangi oda?
//   2/4 — Stil           : Hangi tasarım stili? (Özelleştir custom prompt)
//   3/4 — Renk Paleti    : Hangi renk şeması?
//   4/4 — Yerleşim        : Orijinali koru / Yenilikçi yeniden düzenleme
//
// SnapHome flow'undan ilham, Koala estetiği:
//   - KoalaColors palette, KoalaText (Fraunces serif + Plus Jakarta Sans)
//   - Soft shadows, accent purple selected states, lucide icons
//   - PageView ile slide geçişler, üstte 4-bar progress
//
// Sonuç MekanWizardResult olarak MekanFlowScreen'e iletilir; restyle
// prompt'u kullanıcının seçimleriyle zenginleşir.
// ═══════════════════════════════════════════════════════════════════

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/koala_tokens.dart';
import '../mekan_constants.dart';
import '../mekan_flow_screen.dart';

// ─── Data models ────────────────────────────────────────────────────

class _RoomDef {
  const _RoomDef(this.key, this.tr, this.icon);
  final String key; // analyze servisi ile aynı key (snake_case)
  final String tr;
  final IconData icon;
}

const _kWizardRooms = <_RoomDef>[
  _RoomDef(kRoomKeyLiving, 'Oturma Odası', LucideIcons.sofa),
  _RoomDef(kRoomKeyBedroom, 'Yatak Odası', LucideIcons.bed),
  _RoomDef(kRoomKeyDining, 'Yemek Odası', LucideIcons.utensilsCrossed),
  _RoomDef(kRoomKeyBathroom, 'Banyo', LucideIcons.bath),
  _RoomDef(kRoomKeyKitchen, 'Mutfak', LucideIcons.chefHat),
  _RoomDef(kRoomKeyOffice, 'Çalışma Odası', LucideIcons.laptop),
  _RoomDef('kids_room', 'Çocuk Odası', LucideIcons.baby),
  _RoomDef('hall', 'Antre', LucideIcons.doorOpen),
];

class _PaletteDef {
  const _PaletteDef({
    required this.key,
    required this.tr,
    required this.colors,
    this.surprise = false,
  });
  final String key;
  final String tr;
  final List<int> colors;
  final bool surprise; // "Beni şaşırt" → AI seçer
}

const _kPalettes = <_PaletteDef>[
  _PaletteDef(
    key: 'surprise',
    tr: 'Beni şaşırt',
    colors: [],
    surprise: true,
  ),
  _PaletteDef(
    key: 'soft_neutrals',
    tr: 'Soluk Form',
    colors: [0xFFE8E4DC, 0xFFCAC2B5, 0xFF8C8478, 0xFF514B42, 0xFF2B2724],
  ),
  _PaletteDef(
    key: 'millennium_grey',
    tr: 'Milenyum Grisi',
    colors: [0xFFEAEAEA, 0xFFC2C2C2, 0xFF9C9C9C, 0xFF6E6E6E, 0xFF3D3D3D],
  ),
  _PaletteDef(
    key: 'warm_beige',
    tr: 'Rahat Bej',
    colors: [0xFFF1E8DC, 0xFFE5C9A8, 0xFFC8A07A, 0xFFA67753, 0xFF755338],
  ),
  _PaletteDef(
    key: 'earthy',
    tr: 'Dünya Sakinliği',
    colors: [0xFFE2DDD0, 0xFF9C9078, 0xFF8B7355, 0xFF5C523F, 0xFF332A22],
  ),
  _PaletteDef(
    key: 'sage_garden',
    tr: 'Sisli Bahçe',
    colors: [0xFFD0DCDB, 0xFFA9B5A2, 0xFF7F8C7C, 0xFF54635A, 0xFF2B3633],
  ),
  _PaletteDef(
    key: 'antique_sage',
    tr: 'Antika Bilge',
    colors: [0xFFD5D2BB, 0xFFA9A28A, 0xFF7F7864, 0xFF55503E, 0xFF302C22],
  ),
  _PaletteDef(
    key: 'ocean_mist',
    tr: 'Okyanus Sisi',
    colors: [0xFFC9DAE3, 0xFF98AEBA, 0xFF63798A, 0xFF394B5A, 0xFF1A2530],
  ),
  _PaletteDef(
    key: 'twilight',
    tr: 'Alacakaranlık',
    colors: [0xFF1A2238, 0xFF38384F, 0xFF6E6A93, 0xFFB7AECB, 0xFFE3DEEC],
  ),
  _PaletteDef(
    key: 'bordeaux',
    tr: 'Bordo Esinti',
    colors: [0xFF3A1F2A, 0xFF6E2D3D, 0xFFA45B6E, 0xFFD4A5B0, 0xFFEBD6DC],
  ),
];

enum LayoutMode { preserve, innovate }

/// Wizard sonucu — MekanFlowScreen tarafından okunur, restyle prompt'a inject.
class MekanWizardResult {
  const MekanWizardResult({
    required this.roomKey,
    required this.roomTr,
    required this.styleValue,
    required this.styleTr,
    this.styleCustomPrompt,
    required this.paletteKey,
    required this.paletteTr,
    required this.paletteColors,
    required this.layout,
  });

  final String roomKey;
  final String roomTr;
  final String styleValue;       // 'Modern' / 'Custom' / 'Bohemian' ...
  final String styleTr;          // 'Modern' / 'Bohem' ...
  final String? styleCustomPrompt;
  final String paletteKey;
  final String paletteTr;
  final List<int> paletteColors; // boş = surprise
  final LayoutMode layout;

  /// Restyle prompt'a inject edilecek tek-satır style hint.
  String toPromptHint() {
    final parts = <String>[];
    if (styleCustomPrompt != null && styleCustomPrompt!.trim().isNotEmpty) {
      parts.add(styleCustomPrompt!.trim());
    } else {
      parts.add(styleValue);
    }
    if (paletteColors.isNotEmpty) {
      final hex = paletteColors
          .map((c) => '#${c.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}')
          .join(', ');
      parts.add('palette: $hex');
    }
    parts.add(layout == LayoutMode.preserve
        ? 'preserve original layout, change only furniture & decor'
        : 'innovative layout, fully reimagine arrangement');
    return parts.join(' · ');
  }
}

// ─── Screen ─────────────────────────────────────────────────────────

class MekanWizardScreen extends StatefulWidget {
  const MekanWizardScreen({
    super.key,
    required this.photoBytes,
    this.targetDesignUrl,
    this.targetDesignerId,
  });
  final Uint8List photoBytes;
  /// Swipe'tan gelen referans tasarım URL'i — Gemini bu görseli "ilham" olarak
  /// kullanır, kullanıcının mekanını bu tarza göre yeniden tasarlar.
  final String? targetDesignUrl;
  /// Referans tasarımı yapan tasarımcı ID'si — RealizeScreen pre-fill için.
  final String? targetDesignerId;

  @override
  State<MekanWizardScreen> createState() => _MekanWizardScreenState();
}

class _MekanWizardScreenState extends State<MekanWizardScreen> {
  final PageController _page = PageController();
  int _step = 0;

  String? _roomKey;
  String? _roomTr;
  ThemeOption? _theme;
  String? _customPrompt;
  _PaletteDef? _palette;
  LayoutMode _layout = LayoutMode.preserve;

  static const _totalSteps = 4;

  @override
  void initState() {
    super.initState();
    // Step 2'de ana stil görsellerini hızlı göstermek için tüm 6 stilin
    // LIVING_ROOM versiyonlarını şimdiden warm-up yap (default fallback). Oda
    // seçilince spesifik versiyonlar zaten precache ediliyor.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final t in kThemes) {
        final url = t.imageFor(kRoomKeyLiving);
        if (url.isNotEmpty) {
          precacheImage(NetworkImage(url), context);
        }
      }
    });
  }

  bool get _canContinue {
    switch (_step) {
      case 0:
        return _roomKey != null;
      case 1:
        return _theme != null ||
            (_customPrompt != null && _customPrompt!.trim().isNotEmpty);
      case 2:
        return _palette != null;
      case 3:
        return true;
      default:
        return false;
    }
  }

  Future<void> _next() async {
    HapticFeedback.selectionClick();
    if (_step < _totalSteps - 1) {
      await _page.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      if (mounted) setState(() => _step++);
    } else {
      _finish();
    }
  }

  void _back() {
    HapticFeedback.selectionClick();
    if (_step == 0) {
      Navigator.of(context).pop();
      return;
    }
    _page.previousPage(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
    setState(() => _step--);
  }

  void _finish() {
    final result = MekanWizardResult(
      roomKey: _roomKey!,
      roomTr: _roomTr!,
      styleValue: _theme?.value ?? 'Custom',
      styleTr: _theme?.tr ?? 'Özel',
      styleCustomPrompt: _customPrompt,
      paletteKey: _palette!.key,
      paletteTr: _palette!.tr,
      paletteColors: _palette!.colors,
      layout: _layout,
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MekanFlowScreen(
          initialBytes: widget.photoBytes,
          wizard: result,
          targetDesignUrl: widget.targetDesignUrl,
          targetDesignerId: widget.targetDesignerId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _WizardHeader(
              step: _step,
              total: _totalSteps,
              onBack: _back,
              onClose: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: PageView(
                controller: _page,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _RoomStep(
                    selectedKey: _roomKey,
                    onSelect: (k, tr) {
                      setState(() {
                        _roomKey = k;
                        _roomTr = tr;
                      });
                      // Step 2'ye gelene kadar 6 stil görselini cache'e al →
                      // ilk açılışta da bekleme yok.
                      for (final theme in kThemes) {
                        final url = theme.imageFor(k);
                        if (url.isNotEmpty) {
                          precacheImage(NetworkImage(url), context);
                        }
                      }
                    },
                  ),
                  _StyleStep(
                    // Room key style image'ini room'a göre seçer
                    roomKey: _roomKey ?? kRoomKeyLiving,
                    selectedTheme: _theme,
                    customPrompt: _customPrompt,
                    onSelectTheme: (t) => setState(() {
                      _theme = t;
                      _customPrompt = null;
                    }),
                    onSelectCustom: (prompt) => setState(() {
                      _theme = null;
                      _customPrompt = prompt;
                    }),
                  ),
                  _PaletteStep(
                    selected: _palette,
                    onSelect: (p) => setState(() => _palette = p),
                  ),
                  _LayoutStep(
                    photoBytes: widget.photoBytes,
                    selected: _layout,
                    onSelect: (m) => setState(() => _layout = m),
                  ),
                ],
              ),
            ),
            _ContinueBar(
              enabled: _canContinue,
              isLast: _step == _totalSteps - 1,
              onTap: _next,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Header ─────────────────────────────────────────────────────────

class _WizardHeader extends StatelessWidget {
  const _WizardHeader({
    required this.step,
    required this.total,
    required this.onBack,
    required this.onClose,
  });
  final int step;
  final int total;
  final VoidCallback onBack;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        children: [
          Row(
            children: [
              _RoundIconBtn(
                icon: LucideIcons.chevronLeft,
                onTap: onBack,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'Adım ${step + 1}/$total',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: KoalaColors.text,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
              _RoundIconBtn(
                icon: LucideIcons.x,
                onTap: onClose,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(total, (i) {
              final active = i <= step;
              return Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  margin: EdgeInsets.only(right: i == total - 1 ? 0 : 8),
                  height: 4,
                  decoration: BoxDecoration(
                    color: active
                        ? KoalaColors.accentDeep
                        : KoalaColors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _RoundIconBtn extends StatelessWidget {
  const _RoundIconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: KoalaColors.surface,
      shape: const CircleBorder(),
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
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

// ─── Step 1: Room Type ──────────────────────────────────────────────

class _RoomStep extends StatelessWidget {
  const _RoomStep({required this.selectedKey, required this.onSelect});
  final String? selectedKey;
  final void Function(String key, String tr) onSelect;

  static const _subs = {
    kRoomKeyLiving: 'Konforlu ve modern\nyaşam alanları',
    kRoomKeyBedroom: 'Rahat ve huzurlu\nyatak odaları',
    kRoomKeyDining: 'Şık ve davetkar\nyemek alanları',
    kRoomKeyBathroom: 'Fonksiyonel ve\nferah banyolar',
    kRoomKeyKitchen: 'Pratik ve modern\nmutfaklar',
    kRoomKeyOffice: 'Verimli çalışma\nalanları',
    'kids_room': 'Eğlenceli ve güvenli\nçocuk odaları',
    'hall': 'Davetkar giriş\nalanları',
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Oda Tipini Seçin',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: KoalaColors.text,
              letterSpacing: -0.6,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "AI'nın senin için dönüştürmesini istediğin\nspesifik odayı seç.",
            style: TextStyle(
              fontSize: 14,
              color: KoalaColors.textSec,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.18,
            children: _kWizardRooms.map((r) {
              final selected = selectedKey == r.key;
              return _RoomCard(
                label: r.tr,
                sub: _subs[r.key] ?? '',
                icon: r.icon,
                selected: selected,
                onTap: () => onSelect(r.key, r.tr),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: KoalaColors.accentSoft.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.sparkles,
                    size: 16, color: KoalaColors.accentDeep),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'İpucu: ',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: KoalaColors.accentDeep,
                            letterSpacing: -0.1,
                          ),
                        ),
                        TextSpan(
                          text:
                              'Daha iyi sonuçlar için doğru oda tipini seçmen önerilir.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: KoalaColors.text,
                            height: 1.4,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ],
                    ),
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

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.label,
    required this.sub,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String sub;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: KoalaColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: KoalaColors.border,
              width: 0.6,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: KoalaColors.accentSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon,
                        size: 20, color: KoalaColors.accentDeep),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: KoalaColors.text,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      sub,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: KoalaColors.textSec,
                        height: 1.35,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ],
              ),
              if (selected)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: KoalaColors.accentDeep,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(LucideIcons.check,
                        size: 12, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomChip extends StatelessWidget {
  const _RoomChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? KoalaColors.accentSoft : KoalaColors.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected
                  ? KoalaColors.accentDeep
                  : KoalaColors.border,
              width: selected ? 1.4 : 0.6,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? KoalaColors.accentDeep : KoalaColors.text,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color:
                      selected ? KoalaColors.accentDeep : KoalaColors.text,
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

// ─── Step 2: Style ──────────────────────────────────────────────────

class _StyleStep extends StatelessWidget {
  const _StyleStep({
    required this.roomKey,
    required this.selectedTheme,
    required this.customPrompt,
    required this.onSelectTheme,
    required this.onSelectCustom,
  });
  final String roomKey;
  final ThemeOption? selectedTheme;
  final String? customPrompt;
  final void Function(ThemeOption) onSelectTheme;
  final void Function(String) onSelectCustom;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Stil Seç', style: KoalaText.h2),
          const SizedBox(height: 6),
          Text(
            'İdeal iç mekanı oluşturmak için istediğin tasarım stilini seç. '
            'Görseller stil havasını yansıtır — AI senin odanı bu stille tasarlar.',
            style: KoalaText.bodySec,
          ),
          const SizedBox(height: 20),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.85,
            children: [
              _CustomStyleTile(
                isSelected: customPrompt != null,
                customPrompt: customPrompt,
                onTap: () => _openCustomSheet(context),
              ),
              ...kThemes.map((t) {
                final selected =
                    selectedTheme?.value == t.value && customPrompt == null;
                return _StyleTile(
                  theme: t,
                  roomKey: roomKey,
                  selected: selected,
                  onTap: () => onSelectTheme(t),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openCustomSheet(BuildContext context) async {
    // Bottom sheet — push'a göre focus/keyboard context'i daha iyi korur.
    // (Web mobil tarayıcıda yeni route push'a gidince user-gesture context
    // kayboluyor → klavye açılmıyordu. Bottom sheet aynı route içinde overlay.)
    final result = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (_) => _CustomStylePage(initial: customPrompt),
    );
    if (result != null && result.trim().isNotEmpty) {
      onSelectCustom(result.trim());
    }
  }
}

/// SnapHome-style tile: full image bg + gradient overlay + label OVER image.
/// Selected → accent border + soft glow + check badge top-right.
class _CustomStyleTile extends StatelessWidget {
  const _CustomStyleTile({
    required this.isSelected,
    required this.customPrompt,
    required this.onTap,
  });
  final bool isSelected;
  final String? customPrompt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _StyleTileShell(
      selected: isSelected,
      onTap: onTap,
      label: isSelected ? 'Özel · seçili' : 'Özelleştir',
      sublabel: isSelected
          ? (customPrompt ?? '').replaceAll('\n', ' ')
          : 'Hayalindeki stili anlat',
      labelDark: false,
      child: _CustomGradientHero(),
    );
  }
}

class _CustomGradientHero extends StatelessWidget {
  // Editorial interior — daha sonra runtime'da renk overlay ile mor tonu binir.
  static const _bgUrl =
      'https://images.unsplash.com/photo-1618220179428-22790b461013?auto=format&fit=crop&w=600&q=70';

  Widget _fallbackGradient() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            KoalaColors.accentDeep,
            KoalaColors.accent,
            KoalaColors.accentSoft,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Real interior photo background
        Image.network(
          _bgUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallbackGradient(),
          loadingBuilder: (ctx, child, prog) {
            if (prog == null) return child;
            return _fallbackGradient();
          },
        ),
        // Editorial purple/violet overlay — keeps brand cohesion
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                KoalaColors.accentDeep.withValues(alpha: 0.78),
                KoalaColors.accent.withValues(alpha: 0.62),
                KoalaColors.accentSoft.withValues(alpha: 0.55),
              ],
            ),
          ),
        ),
        // Light radial highlight behind wand
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.05),
              radius: 0.7,
              colors: [
                Colors.white.withValues(alpha: 0.22),
                Colors.transparent,
              ],
            ),
          ),
        ),
        // Decorative sparkles
        const Positioned(
          top: 14,
          right: 18,
          child: Icon(LucideIcons.sparkles, size: 16, color: Colors.white),
        ),
        const Positioned(
          top: 36,
          right: 36,
          child: Icon(LucideIcons.sparkle, size: 8, color: Colors.white),
        ),
        const Positioned(
          bottom: 52,
          left: 18,
          child: Icon(LucideIcons.sparkle, size: 10, color: Colors.white),
        ),
        // Center wand glass orb
        Center(
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.55),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(LucideIcons.wand2,
                size: 28, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _StyleTile extends StatelessWidget {
  const _StyleTile({
    required this.theme,
    required this.roomKey,
    required this.selected,
    required this.onTap,
  });
  final ThemeOption theme;
  final String roomKey;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _StyleTileShell(
      selected: selected,
      onTap: onTap,
      label: theme.tr,
      sublabel: theme.tag,
      labelDark: true,
      child: _StyleSwatchOrImage(theme: theme, roomKey: roomKey),
    );
  }
}

class _StyleSwatchOrImage extends StatelessWidget {
  const _StyleSwatchOrImage({required this.theme, required this.roomKey});
  final ThemeOption theme;
  final String roomKey;

  @override
  Widget build(BuildContext context) {
    // Stil + oda eşleşmesi: kullanıcı banyo seçtiyse banyo+stil görseli görsün.
    // Görseller scripts/generate-style-previews.mjs ile Gemini'den üretilip
    // Vercel Blob'a yüklendi (mekan_constants.dart map'inde).
    final url = theme.imageFor(roomKey);
    if (url.isEmpty) return _gradient();
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _gradient(),
      loadingBuilder: (ctx, child, prog) {
        if (prog == null) return child;
        return _gradient();
      },
    );
  }

  Widget _gradient() {
    final colors = theme.swatch.map((c) => Color(c)).toList();
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors.length >= 2 ? colors : [Colors.grey, Colors.grey],
        ),
      ),
    );
  }
}

/// Image full-bleed + gradient + label overlay + selection check chip.
class _StyleTileShell extends StatelessWidget {
  const _StyleTileShell({
    required this.selected,
    required this.onTap,
    required this.child,
    required this.label,
    required this.sublabel,
    required this.labelDark,
  });
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final String label;
  final String sublabel;
  final bool labelDark; // true = white-on-image; false = white tile (custom)

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KoalaRadius.lg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KoalaRadius.lg),
            border: Border.all(
              color: KoalaColors.border,
              width: 0.6,
            ),
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
              // Hero image / gradient
              child,
              // Bottom gradient (label readability)
              if (labelDark)
                IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.10),
                          Colors.black.withValues(alpha: 0.55),
                        ],
                        stops: const [0.45, 0.65, 1.0],
                      ),
                    ),
                  ),
                ),
              // Label + sublabel — alt sol
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: labelDark ? Colors.white : Colors.white,
                        letterSpacing: -0.2,
                        shadows: const [
                          Shadow(
                            color: Color(0x55000000),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                    if (sublabel.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        sublabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.85),
                          letterSpacing: -0.1,
                          shadows: const [
                            Shadow(
                              color: Color(0x55000000),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Selected check chip — top-right
              if (selected)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: KoalaColors.accentDeep,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      LucideIcons.check,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// FULL-SCREEN dialog page for custom style prompt.
/// Bottom sheet'in keyboard ile yarışma sorunu kalıcı olarak çözer:
/// Scaffold + resizeToAvoidBottomInset doğal handling.
class _CustomStylePage extends StatefulWidget {
  const _CustomStylePage({required this.initial});
  final String? initial;

  @override
  State<_CustomStylePage> createState() => _CustomStylePageState();
}

class _CustomStylePageState extends State<_CustomStylePage> {
  late final TextEditingController _ctrl;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial ?? '');
    // Sayfa açılır açılmaz keyboard'u aç — kullanıcı direkt yazabilsin.
    // Web/mobil tarayıcılarda autofocus tek başına klavye açmıyor; birden çok
    // frame boyunca focus + TextInput.show çağırarak garantiye alıyoruz.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    });
    Future.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      _focusNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    });
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _focusNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return SizedBox(
      height: h * 0.92,
      child: Material(
        color: KoalaColors.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Scaffold(
      backgroundColor: KoalaColors.bg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: KoalaColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.x, color: KoalaColors.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  colors: [KoalaColors.accentDeep, KoalaColors.accent],
                ),
              ),
              child: const Icon(
                LucideIcons.sparkles,
                size: 14,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Özel Stil',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: KoalaColors.text,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        actions: const [SizedBox(width: 12)],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Hayalindeki stili kendi kelimelerinle anlat. AI bunu '
                "prompt'a iliştirip sana özel bir tasarım üretecek.",
                style: KoalaText.bodySec,
              ),
              const SizedBox(height: 16),
              // Büyük text alanı — Expanded ile kalan alanı doldurur
              Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(
                    color: KoalaColors.surface,
                    borderRadius:
                        BorderRadius.circular(KoalaRadius.lg),
                  ),
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focusNode,
                    autofocus: true,
                    maxLines: null,
                    expands: true,
                    maxLength: 300,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: KoalaColors.text,
                      height: 1.45,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Örn: sıcak ışıklı, ahşap dokular, '
                          'mavi-bej palet, akşam vibe…',
                      hintStyle: TextStyle(
                        fontSize: 15,
                        color: KoalaColors.textTer,
                        height: 1.45,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      counterText: '',
                      isCollapsed: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${_ctrl.text.length}/300',
                    style: KoalaText.labelSmall
                        .copyWith(color: KoalaColors.textTer),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      // Sticky bottom button — keyboard açıkken safe area'da kalır
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _ctrl.text.trim().isEmpty
                  ? KoalaColors.border
                  : KoalaColors.accentDeep,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(KoalaRadius.md),
              ),
            ),
            onPressed: _ctrl.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(_ctrl.text.trim()),
            child: const Text(
              'Devam et',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ),
      ),
        ),
      ),
    );
  }
}

// LEGACY — bottom sheet versiyonu (artık kullanılmıyor, _CustomStylePage tam
// ekran versiyonu kullanılıyor). İleride başka yerden çağrılırsa kalsın.
// ignore: unused_element
class _CustomStyleSheet extends StatefulWidget {
  const _CustomStyleSheet({required this.initial, required this.onSubmit});
  final String? initial;
  final void Function(String) onSubmit;

  @override
  State<_CustomStyleSheet> createState() => _CustomStyleSheetState();
}

class _CustomStyleSheetState extends State<_CustomStyleSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardH = media.viewInsets.bottom;

    // Sade, tek-blok layout: keyboard açıldığında sadece bottom padding
    // değişir, content yer değiştirmez. Preset pill'ler kaldırıldı.
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardH),
      child: Container(
        decoration: const BoxDecoration(
          color: KoalaColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          16 + (keyboardH > 0 ? 0 : media.viewPadding.bottom),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: KoalaColors.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // Header
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      colors: [
                        KoalaColors.accentDeep,
                        KoalaColors.accent,
                      ],
                    ),
                  ),
                  child: const Icon(
                    LucideIcons.sparkles,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Özel Stil', style: KoalaText.h3),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.x, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Hayalindeki stili kendi kelimelerinle anlat.',
              style: KoalaText.bodySec,
            ),
            const SizedBox(height: 14),
            // Text input
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: KoalaColors.surface,
                borderRadius: BorderRadius.circular(KoalaRadius.md),
                border: Border.all(
                  color: _ctrl.text.isNotEmpty
                      ? KoalaColors.accentDeep
                      : KoalaColors.border,
                  width: _ctrl.text.isNotEmpty ? 1.4 : 0.6,
                ),
              ),
              child: TextField(
                controller: _ctrl,
                maxLines: 5,
                minLines: 4,
                maxLength: 300,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText:
                      'Örn: sıcak ışıklı, ahşap dokular, mavi-bej palet, '
                      'akşam vibe…',
                  border: InputBorder.none,
                  counterText: '',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${_ctrl.text.length}/300',
                style: KoalaText.labelSmall
                    .copyWith(color: KoalaColors.textTer),
              ),
            ),
            const SizedBox(height: 18),
            // Devam et — her zaman görünür
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _ctrl.text.trim().isEmpty
                      ? KoalaColors.border
                      : KoalaColors.accentDeep,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(KoalaRadius.md),
                  ),
                ),
                onPressed: _ctrl.text.trim().isEmpty
                    ? null
                    : () => widget.onSubmit(_ctrl.text.trim()),
                child: const Text(
                  'Devam et',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
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

// ─── Step 3: Palette ────────────────────────────────────────────────

class _PaletteStep extends StatelessWidget {
  const _PaletteStep({required this.selected, required this.onSelect});
  final _PaletteDef? selected;
  final void Function(_PaletteDef) onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bir Renk Paleti Seçin', style: KoalaText.h2),
          const SizedBox(height: 6),
          Text(
            'Yaratıcı vizyonunu hayata geçirecek bir renk paleti seç.',
            style: KoalaText.bodySec,
          ),
          const SizedBox(height: 20),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.55,
            children: _kPalettes
                .map((p) => _PaletteTile(
                      def: p,
                      selected: selected?.key == p.key,
                      onTap: () => onSelect(p),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _PaletteTile extends StatelessWidget {
  const _PaletteTile({
    required this.def,
    required this.selected,
    required this.onTap,
  });
  final _PaletteDef def;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KoalaRadius.lg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: KoalaColors.surface,
            borderRadius: BorderRadius.circular(KoalaRadius.lg),
            border: Border.all(
              color: KoalaColors.border,
              width: 0.6,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Üstte renk şeridi (full width, 5 eşit slice)
              Expanded(
                flex: 3,
                child: def.surprise
                    ? _SurpriseHero()
                    : Row(
                        children: def.colors
                            .map(
                              (c) => Expanded(
                                child: Container(color: Color(c)),
                              ),
                            )
                            .toList(),
                      ),
              ),
              // Alt: isim + (varsa) check chip
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 12),
                color: KoalaColors.surface,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        def.tr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                          color: selected
                              ? KoalaColors.accentDeep
                              : KoalaColors.text,
                          letterSpacing: -0.15,
                        ),
                      ),
                    ),
                    if (selected)
                      Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: KoalaColors.accentDeep,
                        ),
                        child: const Icon(
                          LucideIcons.check,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Beni şaşırt" özel kart — rainbow gradient + dans eden sparkle ikon.
class _SurpriseHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFD3B6), // peach
            Color(0xFFFFAAA5), // coral
            Color(0xFFFF8B94), // rose
            Color(0xFFB9A4F0), // lavender
            Color(0xFF8FCFD6), // teal
          ],
        ),
      ),
      child: Stack(
        children: [
          // Decorative sparkles
          const Positioned(
            top: 10,
            right: 14,
            child: Icon(LucideIcons.sparkles,
                size: 14, color: Colors.white),
          ),
          const Positioned(
            bottom: 12,
            left: 14,
            child: Icon(LucideIcons.sparkle,
                size: 8, color: Colors.white),
          ),
          // Center wand
          Center(
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.30),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.55),
                  width: 1,
                ),
              ),
              child: const Icon(
                LucideIcons.wand2,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Step 4: Layout Mode ────────────────────────────────────────────

class _LayoutStep extends StatelessWidget {
  const _LayoutStep({
    required this.photoBytes,
    required this.selected,
    required this.onSelect,
  });
  final Uint8List photoBytes;
  final LayoutMode selected;
  final void Function(LayoutMode) onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bir Yerleşim Yapısı Seçin', style: KoalaText.h2),
          const SizedBox(height: 6),
          Text(
            'AI senin odanın mevcut düzenini nasıl ele alsın?',
            style: KoalaText.bodySec,
          ),
          const SizedBox(height: 18),
          // Hero image — KULLANICININ ÇEKTİĞİ FOTOĞRAF
          ClipRRect(
            borderRadius: BorderRadius.circular(KoalaRadius.lg),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(
                    photoBytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                  // Üst köşede "Senin fotoğrafın" badge
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.image,
                              size: 12, color: Colors.white),
                          SizedBox(width: 5),
                          Text(
                            'Senin fotoğrafın',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _LayoutCard(
                  icon: LucideIcons.layoutGrid,
                  title: 'Orijinalini Koru',
                  subtitle: 'Düzeni koru,\nmobilyaları değiştir',
                  selected: selected == LayoutMode.preserve,
                  onTap: () => onSelect(LayoutMode.preserve),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LayoutCard(
                  icon: LucideIcons.shuffle,
                  title: 'Yenilikçi Tasarım',
                  subtitle: 'Yeni düzen +\nyeni mobilyalar',
                  selected: selected == LayoutMode.innovate,
                  onTap: () => onSelect(LayoutMode.innovate),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LayoutCard extends StatelessWidget {
  const _LayoutCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KoalaRadius.lg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: KoalaColors.surface,
            borderRadius: BorderRadius.circular(KoalaRadius.lg),
            border: Border.all(
              color: selected
                  ? KoalaColors.accentDeep
                  : KoalaColors.border,
              width: selected ? 2.0 : 0.6,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: KoalaColors.accent.withValues(alpha: 0.22),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: KoalaColors.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: KoalaColors.accentDeep,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? KoalaColors.accentDeep
                      : KoalaColors.text,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w400,
                  color: KoalaColors.textSec,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Continue / Generate Bar ────────────────────────────────────────

class _ContinueBar extends StatelessWidget {
  const _ContinueBar({
    required this.enabled,
    required this.isLast,
    required this.onTap,
  });
  final bool enabled;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final btm = MediaQuery.of(context).viewPadding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 14 + btm),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: KoalaColors.accent.withValues(alpha: 0.32),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: enabled
                  ? KoalaColors.accentDeep
                  : KoalaColors.surfaceAlt,
              foregroundColor: Colors.white,
              disabledBackgroundColor: KoalaColors.surfaceAlt,
              disabledForegroundColor: KoalaColors.textTer,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: enabled ? onTap : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isLast ? 'Tasarımı Oluştur' : 'Devam Et',
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isLast ? LucideIcons.sparkles : LucideIcons.arrowRight,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
