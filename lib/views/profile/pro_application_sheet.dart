// Profesyonel başvuru — 3 adımlı premium sheet.
// 2026-05-27: profile_tab_screen.dart içinden taşındı + redesign.
//
// Step 1 — Sen        : ad soyad, şehir, doğum yılı (opsiyonel)
// Step 2 — İşin       : meslek (autocomplete suggestion'lı free-text),
//                       deneyim yılı (slider), uzmanlık (chip multi-add).
// Step 3 — Vitrinin   : Instagram, portfolio, neden Koala'da story.
//
// UI: hero görsel her step için, soft fade to bg. Underline-only inputlar,
// pill progress (3 dot), Devam/Geri/Gönder action bar, page slide+fade.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/koala_tokens.dart';
import '../../services/user_profile_service.dart';

// ─── Türkiye'nin 81 ili (alfabetik) ──────────────────────────────────
// 2026-05-28 FIX 4: il seçici için sabit liste. Popüler iller (İstanbul,
// Ankara, İzmir, Bursa, Antalya) seçici sheet'inde ayrı bir bölümde önce
// gösterilir, ardından alfabetik tam liste gelir.
const List<String> _kTurkishProvinces = <String>[
  'Adana', 'Adıyaman', 'Afyonkarahisar', 'Ağrı', 'Aksaray', 'Amasya',
  'Ankara', 'Antalya', 'Ardahan', 'Artvin', 'Aydın', 'Balıkesir',
  'Bartın', 'Batman', 'Bayburt', 'Bilecik', 'Bingöl', 'Bitlis', 'Bolu',
  'Burdur', 'Bursa', 'Çanakkale', 'Çankırı', 'Çorum', 'Denizli',
  'Diyarbakır', 'Düzce', 'Edirne', 'Elazığ', 'Erzincan', 'Erzurum',
  'Eskişehir', 'Gaziantep', 'Giresun', 'Gümüşhane', 'Hakkari', 'Hatay',
  'Iğdır', 'Isparta', 'İstanbul', 'İzmir', 'Kahramanmaraş', 'Karabük',
  'Karaman', 'Kars', 'Kastamonu', 'Kayseri', 'Kilis', 'Kırıkkale',
  'Kırklareli', 'Kırşehir', 'Kocaeli', 'Konya', 'Kütahya', 'Malatya',
  'Manisa', 'Mardin', 'Mersin', 'Muğla', 'Muş', 'Nevşehir', 'Niğde',
  'Ordu', 'Osmaniye', 'Rize', 'Sakarya', 'Samsun', 'Şanlıurfa', 'Siirt',
  'Sinop', 'Sivas', 'Şırnak', 'Tekirdağ', 'Tokat', 'Trabzon', 'Tunceli',
  'Uşak', 'Van', 'Yalova', 'Yozgat', 'Zonguldak',
];

const List<String> _kPopularProvinces = <String>[
  'İstanbul', 'Ankara', 'İzmir', 'Bursa', 'Antalya',
];

/// Profesyonel başvuru sheet'ini açar. Settings ekranı bunu kullanır.
Future<bool?> showProApplicationSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: KoalaColors.bg,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    useSafeArea: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.88,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      child: ProApplicationSheet(),
    ),
  );
}

class ProApplicationSheet extends ConsumerStatefulWidget {
  const ProApplicationSheet({super.key});
  @override
  ConsumerState<ProApplicationSheet> createState() =>
      _ProApplicationSheetState();
}

class _ProApplicationSheetState extends ConsumerState<ProApplicationSheet>
    with TickerProviderStateMixin {
  // ─── Gemini hero görselleri ────────────────────────────────────────
  // Step 1: zaten üretilmiş (seed-pro-cta). 2-3 fallback'e düşer.
  static const String _hero1 =
      'https://xgefjepaqnghaotqybpi.supabase.co/storage/v1/object/public/koala-seed/pro-cta/hero-v1.webp';
  // Step 2/3 görselleri henüz üretilmedi — null = fallback gradient.
  static const String? _hero2 = null;
  static const String? _hero3 = null;

  static const int _totalSteps = 3;

  late final PageController _pageCtl;
  int _step = 0;

  // ─── Form state ────────────────────────────────────────────────────
  // Step 1
  final _fullName = TextEditingController();
  final _city = TextEditingController();

  // Step 2
  final _profession = TextEditingController();
  int _experienceYears = 3;
  final Set<String> _specialties = <String>{};
  final _specialtyInput = TextEditingController();

  // Step 3
  final _instagram = TextEditingController();
  final _portfolio = TextEditingController();
  final _reason = TextEditingController();

  static const List<String> _professionSuggestions = [
    'İç Mimar',
    'Mimar',
    'Dekoratör',
    'Tasarımcı',
    'Mobilyacı',
    'Boyacı',
    'Renovasyon',
  ];

  bool _submitting = false;
  bool _success = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pageCtl = PageController();
    final u = FirebaseAuth.instance.currentUser;
    if ((u?.displayName ?? '').isNotEmpty) _fullName.text = u!.displayName!;
  }

  @override
  void dispose() {
    _pageCtl.dispose();
    _fullName.dispose();
    _city.dispose();
    _profession.dispose();
    _specialtyInput.dispose();
    _instagram.dispose();
    _portfolio.dispose();
    _reason.dispose();
    super.dispose();
  }

  // ─── Step navigation ───────────────────────────────────────────────
  bool _validateStep(int step) {
    switch (step) {
      case 0:
        if (_fullName.text.trim().isEmpty) {
          _error = 'Adını yazar mısın?';
          return false;
        }
        if (_city.text.trim().isEmpty) {
          _error = 'Hangi şehirdesin?';
          return false;
        }
        return true;
      case 1:
        if (_profession.text.trim().isEmpty) {
          _error = 'Mesleğini seçer misin?';
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  void _next() {
    if (!_validateStep(_step)) {
      setState(() {});
      HapticFeedback.selectionClick();
      return;
    }
    setState(() => _error = null);
    if (_step < _totalSteps - 1) {
      setState(() => _step++);
      _pageCtl.animateToPage(
        _step,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
      HapticFeedback.lightImpact();
    }
  }

  void _back() {
    if (_step == 0) return;
    setState(() {
      _step--;
      _error = null;
    });
    _pageCtl.animateToPage(
      _step,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  void _addSpecialty() {
    final s = _specialtyInput.text.trim();
    if (s.isEmpty) return;
    if (_specialties.length >= 6) return;
    setState(() {
      _specialties.add(s);
      _specialtyInput.clear();
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_validateStep(0) || !_validateStep(1)) {
      setState(() {});
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    // Specialty + experience'ı profession kuyruğuna iliştir
    // (backend tek string alıyor — eski davranışla uyumlu).
    final specPart = _specialties.isEmpty
        ? ''
        : ' — ${_specialties.join(', ')}';
    final expPart = ' ($_experienceYears yıl deneyim)';
    final professionPayload =
        '${_profession.text.trim()}$specPart$expPart';

    bool ok = false;
    try {
      ok = await UserProfileService.applyForPro(
        fullName: _fullName.text.trim(),
        profession: professionPayload,
        city: _city.text.trim(),
        igUrl: _instagram.text.trim(),
        portfolioUrl: _portfolio.text.trim(),
        reason: _reason.text.trim().isEmpty
            ? null
            : _reason.text.trim(),
      );
    } catch (e) {
      debugPrint('[pro_app] applyForPro threw: $e');
      ok = false;
    }
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _submitting = false;
        _error = 'Gönderilemedi. Tekrar deneyelim mi?';
      });
      _showRetrySnackBar();
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _submitting = false;
      _success = true;
    });
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  void _showRetrySnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Bir sorun oldu, internet bağlantını kontrol et.'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Tekrar dene',
          textColor: Colors.white,
          onPressed: _submit,
        ),
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context);
    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: insets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: KoalaColors.border,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              // Progress dots
              _ProgressDots(current: _step, total: _totalSteps),
              const SizedBox(height: 10),
              // Page content
              Flexible(
                child: PageView(
                  controller: _pageCtl,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _step = i),
                  children: [
                    _StepWrapper(
                      hero: _hero1,
                      child: _buildStep1(),
                    ),
                    _StepWrapper(
                      hero: _hero2,
                      child: _buildStep2(),
                    ),
                    _StepWrapper(
                      hero: _hero3,
                      child: _buildStep3(),
                    ),
                  ],
                ),
              ),
              // Bottom action bar
              _buildActionBar(),
            ],
          ),
        ),
        // ─── Success overlay ─────────────────────────────────────────
        if (_success)
          Positioned.fill(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: 1,
              child: Container(
                color: KoalaColors.bg.withValues(alpha: 0.96),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: KoalaColors.accentDeep.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        LucideIcons.check,
                        size: 36,
                        color: KoalaColors.accentDeep,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Başvurun alındı 🎉',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: KoalaColors.text,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'Değerlendirme sonrası sana bildirim göndereceğiz.',
                        textAlign: TextAlign.center,
                        style: KoalaText.bodySec,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── Step builders ─────────────────────────────────────────────────
  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepHeader(
          title: 'Sen',
          subtitle: 'Önce seni tanıyalım — kısa tutuyoruz.',
        ),
        const SizedBox(height: 22),
        _UnderlineField(
          controller: _fullName,
          label: 'Ad Soyad',
          icon: LucideIcons.user,
        ),
        const SizedBox(height: 22),
        // 2026-05-28 FIX 4: konum çek pill + 81 il picker.
        Align(
          alignment: Alignment.centerLeft,
          child: _LocationPill(onTap: _fillCityFromLocation),
        ),
        const SizedBox(height: 10),
        _CityPickerField(
          controller: _city,
          onTap: _openCityPicker,
        ),
      ],
    );
  }

  // ─── FIX 4: il seçici sheet ──────────────────────────────────────
  Future<void> _openCityPicker() async {
    HapticFeedback.selectionClick();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KoalaColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CityPickerSheet(current: _city.text.trim()),
    );
    if (picked != null && picked.isNotEmpty) {
      setState(() => _city.text = picked);
    }
  }

  // ─── FIX 4: konum çek (geolocator yok → bilgi snackbar) ──────────
  Future<void> _fillCityFromLocation() async {
    HapticFeedback.selectionClick();
    if (!mounted) return;
    // geolocator paketi henüz pubspec'te yok; kullanıcıyı manuel seçime
    // yönlendir ama akışı bloklamadan.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('Konum servisi yakında — şimdilik listeden seçebilirsin.'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
    await _openCityPicker();
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepHeader(
          title: 'İşin',
          subtitle: 'Ne yapıyorsun ve ne kadardır?',
        ),
        const SizedBox(height: 22),
        _UnderlineField(
          controller: _profession,
          label: 'Mesleğin',
          icon: LucideIcons.briefcase,
        ),
        const SizedBox(height: 10),
        // Profession suggestion chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _professionSuggestions.map((s) {
            final selected = _profession.text.trim().toLowerCase() ==
                s.toLowerCase();
            return GestureDetector(
              onTap: () {
                setState(() {
                  _profession.text = s;
                  _profession.selection = TextSelection.collapsed(
                      offset: s.length);
                });
                HapticFeedback.selectionClick();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: selected
                      ? KoalaColors.accentDeep.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected
                        ? KoalaColors.accentDeep
                        : KoalaColors.borderSolid,
                    width: 1,
                  ),
                ),
                child: Text(
                  s,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? KoalaColors.accentDeep
                        : KoalaColors.textSec,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        _miniDivider(LucideIcons.clock),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text(
              'Deneyim',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: KoalaColors.textSec,
              ),
            ),
            const Spacer(),
            Text(
              '$_experienceYears yıl',
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: KoalaColors.accentDeep,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: KoalaColors.accentDeep,
            inactiveTrackColor: KoalaColors.border,
            thumbColor: KoalaColors.accentDeep,
            overlayColor: KoalaColors.accentDeep.withValues(alpha: 0.12),
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
          ),
          child: Slider(
            value: _experienceYears.toDouble(),
            min: 0,
            max: 30,
            divisions: 30,
            onChanged: (v) {
              setState(() => _experienceYears = v.round());
            },
          ),
        ),
        const SizedBox(height: 12),
        _miniDivider(LucideIcons.sparkles),
        const SizedBox(height: 8),
        const Text(
          'Uzmanlık alanların',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: KoalaColors.textSec,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _UnderlineField(
                controller: _specialtyInput,
                label: 'Yaz ve ekle (ör. Mutfak)',
                icon: LucideIcons.plus,
                onSubmitted: (_) => _addSpecialty(),
              ),
            ),
            const SizedBox(width: 8),
            _CircleIconButton(
              icon: LucideIcons.plus,
              onTap: _addSpecialty,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_specialties.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _specialties.map((s) {
              return _SpecialtyChip(
                label: s,
                onRemove: () =>
                    setState(() => _specialties.remove(s)),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepHeader(
          title: 'Vitrinin',
          subtitle: 'İşlerini nerede görebiliriz?',
        ),
        const SizedBox(height: 22),
        _UnderlineField(
          controller: _instagram,
          label: 'Instagram',
          icon: LucideIcons.instagram,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 22),
        _UnderlineField(
          controller: _portfolio,
          label: 'Portfolyo / web sitesi',
          icon: LucideIcons.link,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 26),
        _miniDivider(LucideIcons.heart),
        const SizedBox(height: 10),
        _UnderlineField(
          controller: _reason,
          label: 'Neden Koala\'da olmak istiyorsun?',
          icon: LucideIcons.messageCircle,
          maxLines: 3,
        ),
      ],
    );
  }

  // ─── Reusable UI bits ──────────────────────────────────────────────
  Widget _stepHeader({required String title, required String subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: KoalaColors.text,
            letterSpacing: -0.6,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: KoalaColors.textSec,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _miniDivider(IconData icon) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: KoalaColors.accentDeep.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 14, color: KoalaColors.accentDeep),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0xFFF1F3F5), width: 1),
              ),
            ),
            child: SizedBox(height: 1),
          ),
        ),
      ],
    );
  }

  Widget _buildActionBar() {
    final isLast = _step == _totalSteps - 1;
    return Container(
      decoration: const BoxDecoration(
        color: KoalaColors.bg,
        border: Border(
          top: BorderSide(color: Color(0xFFF1F3F5), width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: KoalaColors.error,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
            Row(
              children: [
                if (_step > 0) ...[
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _submitting ? null : _back,
                        icon: const Icon(LucideIcons.arrowLeft, size: 16),
                        label: const Text('Geri'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: KoalaColors.text,
                          side: const BorderSide(
                              color: KoalaColors.borderSolid),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: 5,
                  child: isLast
                      ? _GradientPrimaryButton(
                          label: _submitting
                              ? 'Gönderiliyor…'
                              : 'Başvuruyu gönder',
                          icon: LucideIcons.sparkles,
                          onPressed: _submitting ? null : _submit,
                        )
                      : _SolidPrimaryButton(
                          label: 'Devam et',
                          onPressed: _submitting ? null : _next,
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

// ─── Progress dots ───────────────────────────────────────────────────
class _ProgressDots extends StatelessWidget {
  final int current;
  final int total;
  const _ProgressDots({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final active = i == current;
        final done = i < current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 28 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active || done
                ? KoalaColors.accentDeep
                : KoalaColors.border,
            borderRadius: BorderRadius.circular(100),
          ),
        );
      }),
    );
  }
}

// ─── Step wrapper with hero ──────────────────────────────────────────
class _StepWrapper extends StatelessWidget {
  final String? hero;
  final Widget child;
  const _StepWrapper({required this.hero, required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepHero(imageUrl: hero),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _StepHero extends StatelessWidget {
  final String? imageUrl;
  const _StepHero({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 130,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null && imageUrl!.isNotEmpty)
            CachedNetworkImage(
              imageUrl: imageUrl!,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 250),
              placeholder: (_, _) => const _HeroFallback(),
              errorWidget: (_, _, _) => const _HeroFallback(),
            )
          else
            const _HeroFallback(),
          // Soft fade-to-bg at bottom
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x00F6F1EB),
                  Color(0x88F6F1EB),
                  Color(0xFFF6F1EB),
                ],
                stops: [0.4, 0.78, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroFallback extends StatelessWidget {
  const _HeroFallback();
  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFEDE7FB),
            Color(0xFFDFD1FF),
            Color(0xFFF6F1EB),
          ],
          stops: [0.0, 0.6, 1.0],
        ),
      ),
      child: Center(
        child: Icon(
          LucideIcons.sparkles,
          size: 36,
          color: Color(0xFF9B5CFF),
        ),
      ),
    );
  }
}

// ─── Underline-only text field (ultra-minimal) ───────────────────────
class _UnderlineField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;
  const _UnderlineField({
    required this.controller,
    required this.label,
    this.icon,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.onSubmitted,
  });

  @override
  State<_UnderlineField> createState() => _UnderlineFieldState();
}

class _UnderlineFieldState extends State<_UnderlineField> {
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus != _focused) {
        setState(() => _focused = _focus.hasFocus);
      }
    });
    widget.controller.addListener(_onTextChanged);
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.isNotEmpty;
    final floatLabel = _focused || hasText;
    final accentColor =
        _focused ? KoalaColors.accentDeep : KoalaColors.textSec;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: floatLabel ? 11 : 14,
            fontWeight: FontWeight.w600,
            color: accentColor,
            letterSpacing: floatLabel ? 0.4 : 0,
          ),
          child: Text(
            floatLabel ? widget.label.toUpperCase() : widget.label,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (widget.icon != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Icon(
                  widget.icon,
                  size: 16,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                maxLines: widget.maxLines,
                maxLength: widget.maxLength,
                keyboardType: widget.keyboardType,
                onSubmitted: widget.onSubmitted,
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: KoalaColors.text,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  border: InputBorder.none,
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(
                        color: KoalaColors.borderSolid, width: 1),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(
                        color: KoalaColors.accentDeep, width: 1.5),
                  ),
                  contentPadding:
                      const EdgeInsets.only(bottom: 8, top: 2),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Small UI atoms ──────────────────────────────────────────────────
class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: KoalaColors.accentDeep,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const SizedBox(
            width: 34,
            height: 34,
            child: Icon(LucideIcons.plus, size: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _SpecialtyChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _SpecialtyChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
      decoration: BoxDecoration(
        color: KoalaColors.accentDeep,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(LucideIcons.x,
                  size: 11, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _SolidPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _SolidPrimaryButton({required this.label, required this.onPressed});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: KoalaColors.accentDeep,
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              KoalaColors.accentDeep.withValues(alpha: 0.4),
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}

class _GradientPrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  const _GradientPrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [KoalaColors.accentDeep, KoalaColors.accent],
        ),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: KoalaColors.accentDeep.withValues(alpha: 0.36),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: KoalaColors.accent.withValues(alpha: 0.22),
                  blurRadius: 36,
                  spreadRadius: -4,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: SizedBox(
        height: 52,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 16, color: Colors.white),
          label: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 2026-05-28 FIX 4 — Şehir seçici: tap'lı picker field + 81 il sheet +
// "Konumumdan çek" pill. geolocator paketi eklenirse _LocationPill içinde
// kullanılabilir; şimdilik snackbar bilgi mesajı + manuel seçim.
// ═══════════════════════════════════════════════════════════════════════

class _LocationPill extends StatelessWidget {
  final VoidCallback onTap;
  const _LocationPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: KoalaColors.accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: KoalaColors.accentDeep.withValues(alpha: 0.30),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(LucideIcons.mapPin,
                  size: 13, color: KoalaColors.accentDeep),
              SizedBox(width: 6),
              Text(
                'Konumumdan çek',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: KoalaColors.accentDeep,
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

/// Tap-only field that visually matches `_UnderlineField` but opens the
/// city picker sheet instead of accepting keyboard input.
class _CityPickerField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onTap;
  const _CityPickerField({required this.controller, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasText = controller.text.trim().isNotEmpty;
    final accentColor =
        hasText ? KoalaColors.accentDeep : KoalaColors.textSec;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: hasText ? 11 : 14,
                fontWeight: FontWeight.w600,
                color: accentColor,
                letterSpacing: hasText ? 0.4 : 0,
              ),
              child: Text(hasText ? 'ŞEHİR' : 'Şehir'),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Icon(
                    LucideIcons.mapPin,
                    size: 16,
                    color: accentColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8, top: 4),
                    child: Text(
                      hasText ? controller.text : 'İlini seç',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: hasText
                            ? KoalaColors.text
                            : KoalaColors.textTer,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Icon(
                    LucideIcons.chevronDown,
                    size: 16,
                    color: accentColor,
                  ),
                ),
              ],
            ),
            Container(
              height: 1,
              color: hasText
                  ? KoalaColors.accentDeep.withValues(alpha: 0.50)
                  : KoalaColors.border,
            ),
          ],
        ),
      ),
    );
  }
}

class _CityPickerSheet extends StatefulWidget {
  final String current;
  const _CityPickerSheet({required this.current});

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  final TextEditingController _searchCtl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  List<String> get _filteredAll {
    if (_q.isEmpty) return _kTurkishProvinces;
    final lq = _q.toLowerCase().trim();
    return _kTurkishProvinces
        .where((p) => p.toLowerCase().contains(lq))
        .toList(growable: false);
  }

  List<String> get _filteredPopular {
    if (_q.isEmpty) return _kPopularProvinces;
    final lq = _q.toLowerCase().trim();
    return _kPopularProvinces
        .where((p) => p.toLowerCase().contains(lq))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxH = mq.size.height * 0.82;
    final popular = _filteredPopular;
    final all = _filteredAll;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
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
              const SizedBox(height: 12),
              const Text('İlini seç', style: KoalaText.h2),
              const SizedBox(height: 12),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchCtl,
                  autofocus: false,
                  onChanged: (v) => setState(() => _q = v),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(LucideIcons.search,
                        size: 18, color: KoalaColors.textSec),
                    hintText: 'Ara… (örn. İstanbul)',
                    isDense: true,
                    filled: true,
                    fillColor: KoalaColors.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: KoalaColors.accentDeep,
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  children: [
                    if (popular.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(12, 12, 12, 6),
                        child: Text(
                          'POPÜLER',
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: KoalaColors.textSec,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      ...popular.map((p) => _row(p, popular: true)),
                      const Divider(
                        height: 18,
                        thickness: 0.5,
                        indent: 12,
                        endIndent: 12,
                      ),
                    ],
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 4, 12, 6),
                      child: Text(
                        'TÜM İLLER',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: KoalaColors.textSec,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    if (all.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'Sonuç yok',
                            style: TextStyle(color: KoalaColors.textSec),
                          ),
                        ),
                      )
                    else
                      ...all.map((p) => _row(p, popular: false)),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String name, {required bool popular}) {
    final selected = name == widget.current;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).pop(name);
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(
              popular ? LucideIcons.star : LucideIcons.mapPin,
              size: 16,
              color: popular ? KoalaColors.accentDeep : KoalaColors.textSec,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 15,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                  color: KoalaColors.text,
                ),
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
