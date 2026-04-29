import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' show sha1;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/koala_tokens.dart';
import '../../widgets/koala_bottom_nav.dart';
import '../main_shell.dart';
import '../../services/background_gen.dart';
import '../../services/saved_items_service.dart';
import '../../services/upload_service.dart';
import '../../services/analytics_service.dart';
import '../../services/content_gate_service.dart';
import '../../services/mekan_analyze_service.dart';
import '../../services/replicate_service.dart';
import '../../services/restyle_prefetch_service.dart';
import '../../services/swipe_deck_service.dart';
import '../../services/taste_service.dart';
import '../style_discovery_screen.dart';
import 'mekan_constants.dart';
import 'realize_screen.dart';
import 'swipe_screen.dart' as mekan_swipe;
import 'stages/analysis_reveal_stage.dart';
import 'stages/generating_stage.dart';
import 'stages/moodboard_stage.dart';
import 'stages/result_stage.dart';
import 'stages/style_stage.dart';
import 'widgets/mekan_ui.dart';
import 'widgets/quality_hint_sheet.dart';
import 'widgets/style_swipe_sheet.dart';
import 'wizard/mekan_wizard_screen.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Mekan akışı state machine — foto HomeScreen'den geliyor.
/// Açılışta /api/analyze-room ile oda tespiti → style → generating → result.
///
/// 2026-04-27: `wizard` parametresi eklendi. MekanWizardScreen kullanıcı
/// tercihlerini topladıktan sonra buraya iletir — restyle prompt bu
/// seçimlerle zenginleştirilir (next round'da consume edilecek).
class MekanFlowScreen extends StatefulWidget {
  final Uint8List initialBytes;
  final MekanWizardResult? wizard;
  /// Swipe'tan gelen referans tasarım — Gemini'ye "şu tarzda yap" inspiration.
  final String? targetDesignUrl;
  final String? targetDesignerId;
  const MekanFlowScreen({
    super.key,
    required this.initialBytes,
    this.wizard,
    this.targetDesignUrl,
    this.targetDesignerId,
  });

  @override
  State<MekanFlowScreen> createState() => _MekanFlowScreenState();
}

enum _Phase { analyzing, notMekan, reveal, moodboard, style, generating, result, error }

/// "Bu bir mekan değil" reddi için sebep — mesaj tonlaması için.
enum _RejectReason { selfie, food, pet, vehicle, document, screen, clothing, outdoor, other }

class _MekanFlowScreenState extends State<MekanFlowScreen> {
  _Phase _phase = _Phase.analyzing;
  late Uint8List _bytes;
  AnalyzeResult? _analysis;
  ThemeOption? _theme;
  String? _afterSrc;
  bool _mock = false;
  String? _errorMsg;
  _RejectReason _rejectReason = _RejectReason.other;

  /// Taste'a göre çıkarılan inferred theme — moodboard'dan direkt tasarla'ya
  /// geçince kullanılır. Null ise kullanıcı manuel stil seçer.
  ThemeOption? _inferredTheme;

  /// Son hesaplanan taste kararı — reveal CTA'sında doğru rotayı seçmek için.
  /// Analiz ile paralel hesaplanır; CTA basılana kadar hazır olur çoğu durumda.
  /// Hazır değilse CTA anında bekler (genelde <200ms).
  TasteDecision? _tasteDecision;
  Future<TasteDecision>? _tasteFuture;

  /// `StyleSwipeSheet`'ten dönen "loved tags". Restyle prompt'unu
  /// zenginleştirmek için saklıyoruz — parent style stage / generate
  /// adımı bu listeyi okuyup prompt'a iliştirebilir. Boş ise enrich yok.
  List<String> _swipeLovedTags = const [];

  /// /api/analyze-room çağrısının döndürdüğü stil sinyalleri. Restyle
  /// hand-off'undan hemen önce hesaplanır, theme metnine sessizce
  /// appendlenir. Kullanıcıya görünmez — sadece prompt enrichment.
  StyleHints? _styleHints;

  @override
  void initState() {
    super.initState();
    _bytes = widget.initialBytes;
    _analyze();
  }

  Future<void> _analyze() async {
    setState(() {
      _phase = _Phase.analyzing;
      _errorMsg = null;
      // Retry senaryosunda cache'ı sıfırla — eski taste kararını kullanıp
      // yanlış rotaya sapmayalım.
      _tasteDecision = null;
      _tasteFuture = null;
      _inferredTheme = null;
    });
    final analyzeStartedAt = DateTime.now();
    try {
      // 1) Cihaz-tarafı ContentGate v2 — face + image labeling paralel.
      // Selfie, kedi, yemek, araba, belge, ekran, giysi, manzara fotolarını
      // 80-150ms'de eler. Her ret Gemini'de ~$0.003 tasarruf.
      final gate = await ContentGateService.check(_bytes);
      if (gate.shouldBlock) {
        if (!mounted) return;
        unawaited(
          Analytics.mekanContentBlocked(_mapRejectReason(gate).name),
        );
        setState(() {
          _rejectReason = _mapRejectReason(gate);
          _phase = _Phase.notMekan;
        });
        return;
      }

      // 2) Gemini ile ayrıntılı analiz — oda mı, renk, stil.
      final r = await MekanAnalyzeService.analyze(_bytes);
      if (!mounted) return;

      // Telemetry: backend analyze sonucu — Phase 2 kalibrasyonu için kritik.
      final latencyMs = DateTime.now().difference(analyzeStartedAt).inMilliseconds;
      unawaited(
        Analytics.mekanAnalyzed(
          isRoom: r.isRoom,
          roomType: r.roomType,
          style: r.style,
          qualityScore: r.qualityScore,
          issues: r.issues.map((i) => i.name).toList(),
          band: r.qualityBand.name,
          latencyMs: latencyMs,
        ),
      );

      if (r.isNotMekan) {
        setState(() {
          _analysis = r;
          _rejectReason = _RejectReason.other;
          _phase = _Phase.notMekan;
        });
        return;
      }

      // 3) Kalite kontrolü — oda kabul edildi ama foto bulanık/karanlık/parçalı
      // olabilir. Soft band ise kullanıcıya öneri sun, ama "yine de devam et"
      // hep açık. Hard-block etmiyoruz: agency kullanıcıda, telemetrede
      // restyle output skoruyla korelasyon takip edilecek.
      if (r.qualityBand == QualityBand.soft && mounted) {
        final issueNames = r.issues.map((i) => i.name).toList();
        unawaited(
          Analytics.mekanQualityHintShown(
            issues: issueNames,
            qualityScore: r.qualityScore,
          ),
        );
        final shouldContinue = await QualityHintSheet.show(
          context,
          bytes: _bytes,
          issues: r.issues,
          qualityScore: r.qualityScore,
        );
        if (!mounted) return;
        unawaited(
          Analytics.mekanQualityHintChoice(
            choice: shouldContinue == true ? 'continue' : 'retake',
            issues: issueNames,
            qualityScore: r.qualityScore,
          ),
        );
        if (shouldContinue != true) {
          // Kullanıcı "Yeniden çek" dedi → flow'dan çık. HomeScreen'in picker'ı
          // yeni foto için tekrar açılacak. State'i bırak (sayfa kapanıyor).
          Navigator.of(context).pop();
          return;
        }
        // shouldContinue == true → user override, normal akışa devam.
      }

      // 4) Analiz başarılı.
      // Wizard provided ise: kullanıcı zaten oda/stil/palet/yerleşim
      // seçimlerini yapmış → reveal/moodboard/style aşamalarını ATLA,
      // direkt generating'e geç. analyze sonucundan sadece "is_room" gate
      // kullanıldı; restyle prompt wizard tercihleriyle inşa edilecek.
      if (widget.wizard != null) {
        if (!mounted) return;
        setState(() {
          _analysis = r;
        });
        final synthTheme = _wizardToTheme(widget.wizard!);
        unawaited(_generate(synthTheme));
        return;
      }

      // Wizard yoksa: REVEAL ekranı. Taste kararı ve prefetch kullanıcı
      // foto'yu okurken ARKA PLANDA hesaplanır, CTA'ya basınca doğru
      // rotaya atılır.
      setState(() {
        _analysis = r;
        _phase = _Phase.reveal;
      });

      // Arka plan: taste + prefetch (sessiz başarısızlık).
      final roomKey = r.roomType.isNotEmpty ? r.roomType : 'living_room';
      unawaited(_prepareTasteAndPrefetch(roomKey));
    } on MekanAnalyzeException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = '${e.code} · ${e.detail}';
        _phase = _Phase.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = e.toString();
        _phase = _Phase.error;
      });
    }
  }

  /// Analiz başarılı olunca arka planda taste karar + prefetch hazırla.
  /// Kullanıcı reveal ekranında foto okurken bu iş paralel döner; CTA'ya
  /// basıldığında (genelde 1-2 sn sonra) veri hazırdır → 0ms latency.
  Future<void> _prepareTasteAndPrefetch(String roomKey) async {
    // Aynı anda çoğaltma — _tasteFuture varsa tekrar başlatma.
    if (_tasteFuture != null) return;
    final future = TasteService.decideForRoom(roomKey);
    _tasteFuture = future;
    try {
      final decision = await future;
      if (!mounted) return;
      ThemeOption? inferred;
      if (decision.style != null) {
        final themeValue = TasteService.tasteKeyToThemeValue(decision.style!);
        if (themeValue != null) {
          for (final t in kThemes) {
            if (t.value == themeValue) {
              inferred = t;
              break;
            }
          }
        }
      }
      _tasteDecision = decision;
      _inferredTheme = inferred;

      // Prefetch — taste güçlü (>=%55) ise kullanıcı reveal + moodboard
      // izlerken arkada restyle hazırlansın. "Tasarla"da 0 ms.
      //
      // KALİTE GATE: foto kalitesi soft band'da ise prefetch atla. Sebep:
      // (a) düşük kalite input → output da zayıf çıkacak, prefetch'i kullanıcı
      //     muhtemelen reddedecek (boşa $0.04)
      // (b) kullanıcı "yine de devam et" dedi ama tek shot için bekleyebilir
      // (c) Phase 2'de 3-variant'a geçince soft band → 1 variant'a düşürülecek
      final qualityOk = _analysis?.qualityBand == QualityBand.good;
      if (decision.shouldPrefetch && inferred != null && qualityOk) {
        final roomLabel = roomKey.replaceAll('_', ' ');
        unawaited(
          RestylePrefetchService.prefetch(
            imageBytes: _bytes,
            room: roomLabel,
            theme: inferred.value,
          ).catchError((_) {
            return RestyleResult(output: '', mock: false);
          }),
        );
      }
    } catch (_) {
      // Taste pipeline hata verirse swipe'a düşeceğiz — sessiz kal.
    }
  }

  /// Reveal ekranından "Zevkime göre yeniden tasarla" aksiyonu.
  /// Taste kararına göre:
  ///   - Confident + inferred theme → moodboard reveal (doğrudan üretime yakın)
  ///   - Low confidence                → swipe (style discovery), dönüşte
  ///                                      tekrar decide + moodboard
  ///   - Taste henüz gelmediyse        → bekle (genelde <200ms)
  Future<void> _onAutoDesign() async {
    // Taste henüz yoksa bekle — geç gelenin kullanıcıyı yanıltmasın diye
    // kısa bir loading state'ine geçiyoruz.
    var decision = _tasteDecision;
    if (decision == null && _tasteFuture != null) {
      try {
        decision = await _tasteFuture;
      } catch (_) {
        decision = null;
      }
      if (!mounted) return;
    }

    if (decision != null && decision.isConfident && _inferredTheme != null) {
      setState(() => _phase = _Phase.moodboard);
      return;
    }

    // Düşük güven → "Tarzını Keşfedelim" swipe-sheet'i. Inline modal,
    // 6 kart, sevdim/atla; reveal'da prefetch zaten arkada koşuyor.
    // Sheet null dönerse (atla) mevcut taste-swipe akışına düşeriz.
    final swiped = await _maybeShowStyleSwipe();
    if (!mounted) return;
    if (swiped != null) {
      // Sheet onaylandı → enrich + moodboard'a geç. Restyle prefetch
      // zaten 5. swipe'tan sonra fire edildi.
      setState(() {
        _swipeLovedTags = swiped.preview.lovedTags;
        // Inferred theme yoksa style picker'a düşmeyelim — moodboard kullanıcıya
        // daha düşük yük; theme inference parent tarafından sonradan eklenecek.
        _phase = _inferredTheme != null ? _Phase.moodboard : _Phase.style;
      });
      return;
    }

    // Sheet açılmadı veya kullanıcı atladı → eski taste-swipe akışı.
    await _navigateToSwipeForTaste();
  }

  /// Stil güveni düşükse `StyleSwipeSheet`'i göster. Yeterli aday yoksa
  /// (TODO: API hazır olunca dolacak), sessizce null dön — caller fallback
  /// akışına yönlensin.
  ///
  /// "Düşük güven" şu an `style.isEmpty` heuristiği — backend `confidence`
  /// alanı ekleyene dek. Hedef eşik: `confidence < 0.65`.
  Future<StyleSwipeResult?> _maybeShowStyleSwipe() async {
    final a = _analysis;
    if (a == null) return null;

    // TODO(confidence): /api/analyze-room `confidence` alanı eklensin;
    // burada `a.confidence < 0.65` kontrolü yapılacak. Şimdilik style
    // boşsa düşük güven kabul ediyoruz.
    final lowConfidence = a.style.trim().isEmpty;
    if (!lowConfidence) return null;

    // /api/swipe-deck hayata geçti → kullanıcıyı yeni full-screen
    // SwipeScreen'e yönlendir. Eski `StyleSwipeSheet` (modal candidate
    // listesiyle) artık dead path; aşağıdaki dönüş onun yerine geçiyor.
    // Hand-off: SwipeResult? gelir → loved tags'i swipe state'ine yaz,
    // theme prompt'una caller tarafından eklenir.
    final roomKeyTr = _mapRoomKeyToTr(a.roomType);
    final result = await Navigator.of(context).push<SwipeResult>(
      MaterialPageRoute(
        builder: (_) => mekan_swipe.SwipeScreen(
          roomTypeHint: roomKeyTr,
          prefetchTrigger: () {
            // 5. like'ta tetiklenir — mevcut prefetch kuralları aynı.
            final qualityOk = _analysis?.qualityBand == QualityBand.good;
            final theme = _inferredTheme;
            if (theme == null || !qualityOk) return;
            final roomKey = a.roomType.isNotEmpty
                ? a.roomType
                : 'living_room';
            unawaited(
              RestylePrefetchService.prefetch(
                imageBytes: _bytes,
                room: roomKey.replaceAll('_', ' '),
                theme: theme.value,
              ).catchError((_) => RestyleResult(output: '', mock: false)),
            );
          },
        ),
      ),
    );
    if (!mounted) return null;
    if (result == null) return null;
    // SwipeResult → eski StyleSwipeResult shape'ine adapte et. Caller
    // sadece preview.lovedTags okuyor; diğer alanları dolduruyoruz.
    return StyleSwipeResult(
      confirmed: true,
      preview: StyleDiscoveryPreview(lovedTags: result.lovedTags),
      lovedProjectIds: result.lovedProjectIds,
    );
  }

  Future<void> _navigateToSwipeForTaste() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const StyleDiscoveryScreen(entryPoint: 'mekan_flow'),
      ),
    );
    if (!mounted) return;

    // Swipe'tan dönünce taste'i yeniden hesapla.
    final roomKey = _analysis?.roomType.isNotEmpty == true
        ? _analysis!.roomType
        : 'living_room';
    try {
      final decision = await TasteService.decideForRoom(roomKey);
      if (!mounted) return;
      ThemeOption? inferred;
      if (decision.style != null) {
        final themeValue = TasteService.tasteKeyToThemeValue(decision.style!);
        if (themeValue != null) {
          for (final t in kThemes) {
            if (t.value == themeValue) {
              inferred = t;
              break;
            }
          }
        }
      }
      _tasteDecision = decision;
      _inferredTheme = inferred;

      // Prefetch tetikle — swipe sonrası taste güçlendiyse moodboard izlenirken
      // restyle hazırlansın. (Kalite gate: yukarıdaki ile aynı mantık.)
      final qualityOk = _analysis?.qualityBand == QualityBand.good;
      if (decision.shouldPrefetch && inferred != null && qualityOk) {
        unawaited(
          RestylePrefetchService.prefetch(
            imageBytes: _bytes,
            room: roomKey.replaceAll('_', ' '),
            theme: inferred.value,
          ).catchError((_) => RestyleResult(output: '', mock: false)),
        );
      }

      setState(() {
        // Artık güven varsa moodboard'a çık; hâlâ belirsizse kullanıcıya manuel
        // picker ver — boş swipe loop'una sokmayalım.
        _phase = (decision.isConfident && inferred != null)
            ? _Phase.moodboard
            : _Phase.style;
      });
    } catch (_) {
      if (!mounted) return;
      // Hata durumunda manuel picker — kullanıcı akışta tıkanmasın.
      setState(() => _phase = _Phase.style);
    }
  }

  /// Wizard sonucunu restyle için ThemeOption'a sar. `value` field'ı doğrudan
  /// Gemini prompt'una giden style metni — wizard'ın `toPromptHint()` çıktısı
  /// (style + palette HEX + layout mode) tek satır halinde inject edilir.
  ThemeOption _wizardToTheme(MekanWizardResult w) {
    final swatch = w.paletteColors.isNotEmpty
        ? w.paletteColors.take(3).toList()
        : const [0xFFEEEEEE, 0xFFCCCCCC, 0xFF999999];
    return ThemeOption(
      w.toPromptHint(),
      w.styleTr,
      'Wizard ${w.styleTr}',
      swatch,
      const {},
    );
  }

  Future<void> _generate(ThemeOption theme) async {
    final a = _analysis;
    if (a == null) return;

    // ───── /api/analyze-room (stil sinyalleri) ─────
    // Restyle hand-off'undan HEMEN önce. Kullanıcı stil seçti, görsel restyle
    // edilmeden önce CLIP gate + style hints çek. valid:true → sessizce stash,
    // valid:false → dostane Türkçe sheet ile picker'a yönlendir, network/500
    // → aynı sheet ama "Tekrar dene" callback'i bu çağrıyı retry eder.
    if (_styleHints == null) {
      final ok = await _ensureRoomAnalysis(theme);
      if (!mounted || !ok) return;
    }

    setState(() {
      _phase = _Phase.generating;
      _theme = theme;
      _errorMsg = null;
    });
    final restyleStartedAt = DateTime.now();
    try {
      // Oda tipi: WIZARD ÖNCELİKLİ. Kullanıcı seçtiyse onun seçimini al,
      // analiz'in tahminini override et — kullanıcı agency'si > AI tahmini.
      final room = widget.wizard?.roomKey.isNotEmpty == true
          ? widget.wizard!.roomKey
          : (a.roomType.isNotEmpty ? a.roomType : 'living room');

      // Prefetch hit → arka tarafta bitmişse anında sonuç, çalışıyorsa bekle.
      // Miss → taze çağrı. Her durumda cache'e yazar.
      final cached = RestylePrefetchService.take(
        imageBytes: _bytes,
        theme: theme.value,
      );
      final RestyleResult r;
      if (cached != null) {
        r = cached;
      } else {
        final pending = RestylePrefetchService.pending(
          imageBytes: _bytes,
          theme: theme.value,
        );
        r = pending != null
            ? await pending
            : await RestylePrefetchService.prefetch(
                imageBytes: _bytes,
                room: room.replaceAll('_', ' '),
                theme: theme.value,
                styleHints: _styleHints,
                referenceUrl: widget.targetDesignUrl,
              );
      }
      // Background gen aktifse (kullanıcı küçülttüyse) sonucu bildir +
      // koleksiyona kaydet (mounted false olsa da çalışsın).
      if (BackgroundGen.notifier.value != null) {
        // ÖNCE complete'i fire et — pending kart hemen %100'e atlasın,
        // upload/save'i arka planda çalıştır. Aksi halde upload süresi
        // boyunca kart %95'te tıkanıyor.
        BackgroundGen.complete(afterUrl: r.output);
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && !user.isAnonymous) {
          final designId = sha1
              .convert(
                '${theme.value}|${r.output}|${_bytes.length}'.codeUnits,
              )
              .toString()
              .substring(0, 24);
          final roomTr = widget.wizard?.roomTr ?? a.roomLabelTr;
          final bytesCopy = _bytes;
          unawaited(() async {
            final beforeUrl = await UploadService.uploadBefore(bytesCopy);
            await SavedItemsService.saveItem(
              type: SavedItemType.design,
              itemId: designId,
              title: 'Yeni $roomTr',
              imageUrl: r.output,
              subtitle: 'İç Mimarlık · ${theme.tr}',
              extraData: {
                'room': roomTr,
                'theme': theme.tr,
                'after_url': r.output,
                if (beforeUrl != null) 'before_url': beforeUrl,
                'category': 'interior_design',
                'saved_at': DateTime.now().toIso8601String(),
              },
            );
          }());
        }
      }
      if (!mounted) return;
      final restyleLatencyMs =
          DateTime.now().difference(restyleStartedAt).inMilliseconds;
      // v2 batch hazırsa zenginleştirilmiş telemetri al — judge skoru kalite
      // kalibrasyonu için en kritik sinyal.
      final batch = RestylePrefetchService.takeBatch(
        imageBytes: _bytes,
        theme: theme.value,
      );
      unawaited(
        Analytics.mekanRestyleOutcome(
          outcome: 'success',
          theme: theme.value,
          roomType: a.roomType,
          latencyMs: restyleLatencyMs,
          variant: batch?.best.promptKind,
          judgeScore: batch?.best.judgeScore,
          variantCount: batch?.variants.length,
          rejectedCount: batch?.rejectedCount,
        ),
      );
      // Kullanıcı küçülttüyse mounted=false — setState atma. Background gen
      // ZATEN complete edildi yukarıda; sessizce bitir.
      if (!mounted) return;
      setState(() {
        _afterSrc = r.output;
        _mock = r.mock;
        _phase = _Phase.result;
      });
    } on ReplicateException catch (e) {
      // Background gen aktifse hata bildir → kart kaybolsun, kullanıcı takılı kalmasın.
      if (BackgroundGen.notifier.value != null) {
        BackgroundGen.fail('${e.code} · ${e.detail}');
        // Kısa süre sonra temizle
        Future.delayed(const Duration(milliseconds: 1200), BackgroundGen.clear);
      }
      if (!mounted) return;
      final restyleLatencyMs =
          DateTime.now().difference(restyleStartedAt).inMilliseconds;
      unawaited(
        Analytics.mekanRestyleOutcome(
          outcome: 'error',
          theme: theme.value,
          roomType: a.roomType,
          latencyMs: restyleLatencyMs,
          errorCode: e.code,
        ),
      );
      setState(() {
        _errorMsg = '${e.code} · ${e.detail}';
        _phase = _Phase.error;
      });
    } catch (e) {
      if (BackgroundGen.notifier.value != null) {
        BackgroundGen.fail(e.toString());
        Future.delayed(const Duration(milliseconds: 1200), BackgroundGen.clear);
      }
      if (!mounted) return;
      final restyleLatencyMs =
          DateTime.now().difference(restyleStartedAt).inMilliseconds;
      unawaited(
        Analytics.mekanRestyleOutcome(
          outcome: 'error',
          theme: theme.value,
          roomType: a.roomType,
          latencyMs: restyleLatencyMs,
          errorCode: 'unknown',
        ),
      );
      setState(() {
        _errorMsg = e.toString();
        _phase = _Phase.error;
      });
    }
  }

  /// /api/analyze-room çağrısı + valid/invalid/error UI rotası.
  /// true dönerse caller restyle'e devam edebilir; false ise sheet
  /// kullanıcıyı zaten yönlendirdi (picker'a pop ya da retry).
  Future<bool> _ensureRoomAnalysis(ThemeOption theme) async {
    while (true) {
      // Loading: mevcut analiz shimmer'ını yeniden kullan (fotonun üstünde
      // mor tarama çizgisi). Yeni component icat etmiyoruz.
      setState(() {
        _phase = _Phase.analyzing;
        _errorMsg = null;
      });

      final dataUrl = 'data:image/jpeg;base64,${base64Encode(_bytes)}';
      final analyzeStartedAt = DateTime.now();
      // Picker kaynağı parent'tan taşınmıyor — default 'gallery'.
      // Camera/gallery ayrımı eklenirse widget param olarak iletilmeli.
      unawaited(Analytics.mekanAnalyzeStarted(source: 'gallery'));

      try {
        final result = await MekanAnalyzeService.analyzeRoom(
          imageDataUrlOrHttps: dataUrl,
        );
        if (!mounted) return false;
        final latencyMs =
            DateTime.now().difference(analyzeStartedAt).inMilliseconds;

        if (result is RoomAnalysisValid) {
          unawaited(
            Analytics.mekanAnalyzeOutcome(
              valid: true,
              confidence: result.style.confidence,
              latencyMs: result.latencyMs ?? latencyMs,
            ),
          );
          // Sessizce stash — kullanıcıya görünmez, restyle prompt'unda kullanılacak.
          _styleHints = result.style;
          return true;
        }

        if (result is RoomAnalysisInvalid) {
          unawaited(
            Analytics.mekanAnalyzeOutcome(
              valid: false,
              rejectReason: result.reason,
              confidence: result.confidence,
              latencyMs: result.latencyMs ?? latencyMs,
            ),
          );
          await _showAnalyzeRejectSheet(
            body: 'Bir iç mekan fotoğrafı dene — geniş açı, oda görünür olsun.',
          );
          if (!mounted) return false;
          // Picker'a geri dön.
          Navigator.of(context).pop();
          return false;
        }
        return false;
      } catch (e) {
        if (!mounted) return false;
        final latencyMs =
            DateTime.now().difference(analyzeStartedAt).inMilliseconds;
        unawaited(
          Analytics.mekanAnalyzeOutcome(
            valid: false,
            rejectReason: 'error:${e.runtimeType}',
            latencyMs: latencyMs,
          ),
        );
        final retry = await _showAnalyzeRejectSheet(
          body: 'Bir şey ters gitti, internet bağlantını kontrol et.',
        );
        if (!mounted) return false;
        if (retry == true) {
          // Aynı çağrıyı tekrar dene — while loop bir sonraki turda.
          continue;
        }
        Navigator.of(context).pop();
        return false;
      }
    }
  }

  /// Ortak reject/error sheet — başlık sabit, body değişken.
  /// `true` → tekrar dene, `false`/null → kapatıldı.
  Future<bool?> _showAnalyzeRejectSheet({required String body}) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: KoalaColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(KoalaRadius.xl),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          KoalaSpacing.xl,
          KoalaSpacing.xl,
          KoalaSpacing.xl,
          KoalaSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle — diğer Koala sheet'leri ile tutarlı.
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: KoalaColors.border,
                  borderRadius: BorderRadius.circular(KoalaRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: KoalaSpacing.lg),
            const Text(
              'Görsel mekan olarak okunmadı',
              style: KoalaText.h2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KoalaSpacing.sm),
            Text(
              body,
              style: KoalaText.bodySec,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KoalaSpacing.xl),
            MekanPrimaryButton(
              label: 'Tekrar dene',
              onTap: () => Navigator.of(ctx).pop(true),
              trailing: LucideIcons.refreshCw,
            ),
          ],
        ),
      ),
    );
  }

  /// Edit sheet'ten gelen değişiklikleri uygular. Şu an sadece style change
  /// generate'i tetikliyor; oda/yapı/palette değişikleri için flow refactor
  /// gerek (wizard final). Görsel state olarak yine de kullanıcıya yansıtılır.
  void _onApplyEdit(EditDesignChange change) {
    if (change.styleValue != null) {
      // Backend prompt için ThemeOption objesi gerek; mevcut kThemes'tan eşleştir.
      final match = kThemes.where(
        (t) => t.value.toLowerCase() == change.styleValue!.toLowerCase(),
      );
      if (match.isNotEmpty) {
        // Cache'i temizle ki yeni stil için taze çağrı yapılsın
        RestylePrefetchService.clear();
        _theme = match.first;
        _generate(match.first);
        return;
      }
    }
    // Style değişmediyse, mevcut config ile yenile (cache invalidate edip).
    if (_theme != null) {
      RestylePrefetchService.clear();
      _generate(_theme!);
    }
  }

  void _onPro() {
    // Kullanıcı "Bu tasarımı gerçeğe dönüştür" bastı → vurucu Realize ekranı.
    // Ekran içinde: ürün listesi (api/products/search) + "Profesyonele Sor"
    // (mevcut ProMatchSheet'i açar) + "Tasarımı Sakla".
    final restyle = _afterSrc;
    final theme = _theme?.value ?? _inferredTheme?.value;
    if (restyle == null || restyle.isEmpty || theme == null) {
      return;
    }
    final roomTypeTr = _mapRoomKeyToTr(_analysis?.roomType);
    unawaited(
      Analytics.mekanProCtaTapped(
        theme: theme,
        roomType: _analysis?.roomType ?? 'unknown',
      ),
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RealizeScreen(
          afterSrc: restyle,
          room: widget.wizard?.roomTr ?? _analysis?.roomLabelTr ?? 'Mekan',
          theme: widget.wizard?.styleTr ?? _theme?.tr ?? '',
          themeValue: theme,
          roomTypeTr: roomTypeTr,
          preferredDesignerId: widget.targetDesignerId,
        ),
      ),
    );
  }

  /// _analysis.roomType (English snake) → match-designers'ın beklediği
  /// Türkçe etiket. Bilinmeyen değerlerde Oturma Odası fallback'i — agresif
  /// filtrelemekten ziyade kullanıcıya bir liste sunmak öncelik.
  String _mapRoomKeyToTr(String? key) {
    switch (key?.toLowerCase()) {
      case 'living_room':
        return 'Oturma Odası';
      case 'bedroom':
        return 'Yatak Odası';
      case 'kitchen':
        return 'Mutfak';
      case 'bathroom':
        return 'Banyo';
      case 'dining_room':
        return 'Oturma Odası'; // evlumba'da yok, en yakın eşleşme
      case 'office':
        return 'Konut';
      case 'entry':
      case 'hallway':
        return 'Antre';
      default:
        return 'Oturma Odası';
    }
  }

  /// ContentGate verdict → UX reject reason map'i.
  _RejectReason _mapRejectReason(ContentVerdict v) {
    if (v.kind == ContentKind.selfie) return _RejectReason.selfie;
    switch (v.nonRoomCategory) {
      case 'person':
        return _RejectReason.selfie;
      case 'food':
        return _RejectReason.food;
      case 'pet':
        return _RejectReason.pet;
      case 'vehicle':
        return _RejectReason.vehicle;
      case 'document':
        return _RejectReason.document;
      case 'screen':
        return _RejectReason.screen;
      case 'clothing':
        return _RejectReason.clothing;
      case 'outdoor':
        return _RejectReason.outdoor;
      default:
        return _RejectReason.other;
    }
  }

  @override
  Widget build(BuildContext context) {
    // analyzing/generating/result fazlarında app bar gösterme — tam ekran,
    // sade bir akış. Result kendi top bar'ını çiziyor, analyzing/generating
    // ise kasıtlı olarak çıkışsız (kullanıcı işlemi durduramasın).
    final hideAppBar = _phase == _Phase.analyzing ||
        _phase == _Phase.generating ||
        _phase == _Phase.result;
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      appBar: hideAppBar
          ? null
          : AppBar(
              backgroundColor: KoalaColors.bg,
              surfaceTintColor: KoalaColors.bg,
              elevation: 0,
              leading: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(LucideIcons.arrowLeft),
              ),
              title: const Text('Mekan', style: KoalaText.h2),
            ),
      body: SafeArea(
        top: !hideAppBar,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _buildPhase(),
        ),
      ),
    );
  }

  Widget _buildPhase() {
    switch (_phase) {
      case _Phase.analyzing:
        return _analyzingView();
      case _Phase.notMekan:
        return _notMekanView();
      case _Phase.reveal:
        return AnalysisRevealStage(
          key: const ValueKey('reveal'),
          bytes: _bytes,
          analysis: _analysis!,
          onAutoDesign: _onAutoDesign,
          onManualPick: () => setState(() => _phase = _Phase.style),
        );
      case _Phase.moodboard:
        return MoodboardStage(
          key: const ValueKey('moodboard'),
          onContinue: () {
            // Inferred theme varsa direkt generate — zaten prefetch edildi.
            if (_inferredTheme != null) {
              _generate(_inferredTheme!);
            } else {
              setState(() => _phase = _Phase.style);
            }
          },
          onRefine: () => setState(() => _phase = _Phase.style),
        );
      case _Phase.style:
        return StyleStage(
          key: const ValueKey('style'),
          bytes: _bytes,
          analysis: _analysis!,
          onSubmit: _generate,
        );
      case _Phase.generating:
        return GeneratingStage(
          key: const ValueKey('generating'),
          bytes: _bytes,
          room: _analysis?.roomLabelTr ?? 'Mekan',
          theme: _theme?.tr ?? '',
          themeValue: _theme?.value,
        );
      case _Phase.result:
        // Wizard varsa kullanıcının seçtiği oda adı + stil; yoksa analiz.
        return ResultStage(
          key: const ValueKey('result'),
          beforeBytes: _bytes,
          afterSrc: _afterSrc!,
          room: widget.wizard?.roomTr ??
              _analysis?.roomLabelTr ??
              'Mekan',
          theme: widget.wizard?.styleTr ?? _theme?.tr ?? '',
          paletteTr: widget.wizard?.paletteTr,
          layoutTr: widget.wizard == null
              ? null
              : (widget.wizard!.layout == LayoutMode.preserve
                  ? 'Orijinalini Koru'
                  : 'Yenilikçi'),
          mock: _mock,
          onRetry: () => _generate(_theme!),
          onNewStyle: () => setState(() => _phase = _Phase.style),
          onRestart: () {
            // Yeni üretilen tasarımdan çıkınca kullanıcıyı Projelerim'e götür.
            Navigator.of(context).popUntil((r) => r.isFirst);
            MainShell.of(context)?.switchTab(KoalaTab.projeler);
          },
          onPro: _onPro,
          onApplyEdit: _onApplyEdit,
        );
      case _Phase.error:
        return _errorView();
    }
  }

  Widget _analyzingView() {
    return _AnalyzingView(
      key: const ValueKey('analyzing'),
      bytes: _bytes,
      referenceUrl: widget.targetDesignUrl,
    );
  }

  Widget _notMekanView() {
    // ContentGate kategoriye göre espirili ton ayarla. Hepsi aynı mesaj
    // tek tip "bu bir oda değil" değil; kullanıcıyla göz kırpıyoruz.
    final (title, msg) = switch (_rejectReason) {
      _RejectReason.selfie => (
          'Yakışıklısın ama 😄',
          'Burada bir yüz görüyorum — Koala\'nın tasarladığı şey oda. '
              'Salonun, yatak odan, mutfağın bir fotoğrafını çek.'
        ),
      _RejectReason.food => (
          'Afiyet olsun 🍽️',
          'Yemek fotoğrafını tasarlayamam ama mutfağını restyle edebilirim. '
              'Mutfağın geniş bir fotoğrafını yükler misin?'
        ),
      _RejectReason.pet => (
          'Sevimli dostun var 🐾',
          'Evcil hayvanın tasarımcısı değilim ama odanınkiyim. Onun '
              'uyuduğu odanın bir fotoğrafını dener misin?'
        ),
      _RejectReason.vehicle => (
          'Garaj mı tasarlayalım? 🚗',
          'Araç fotoğrafı görüyorum. Koala iç mekanlarda daha iyi — salon, '
              'yatak odası, mutfak dener misin?'
        ),
      _RejectReason.document => (
          'Bu bir belge 📄',
          'Metin/belge fotoğrafı görüyorum. Bir odanın geniş açı '
              'fotoğrafını yüklersen seni daha iyi anlarım.'
        ),
      _RejectReason.screen => (
          'Ekrana zoom 📱',
          'Bir ekran fotoğrafı görüyorum. Ekran yerine odanın kendisini '
              'çekmeyi dener misin?'
        ),
      _RejectReason.clothing => (
          'Stil iyi ama ben oda stilistim 👗',
          'Kıyafet fotoğrafını tasarlayamam — gardırobunun açık hali mi '
              'olsun? Dolap odanı bütün haliyle çekebilirsin.'
        ),
      _RejectReason.outdoor => (
          'Güzel manzara 🌄',
          'Dış mekan görüyorum — Koala şimdilik iç mekan uzmanı. '
              'Evin içinden bir fotoğraf yükler misin?'
        ),
      _RejectReason.other => (
          'Bunu tasarlayamam 🐨',
          (_analysis?.caption.trim().isNotEmpty ?? false)
              ? _analysis!.caption.trim()
              : 'İç mekan görmüyorum bu karede. Salonun, yatak odan, '
                  'mutfağın — bir oda fotoğrafı yükler misin?'
        ),
    };
    return Padding(
      key: const ValueKey('notMekan'),
      padding: const EdgeInsets.fromLTRB(
          KoalaSpacing.xl, KoalaSpacing.md, KoalaSpacing.xl, KoalaSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Küçük foto önizleme — kullanıcı ne yüklediğini görsün.
          Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(KoalaRadius.lg),
                image: DecorationImage(
                  image: MemoryImage(_bytes),
                  fit: BoxFit.cover,
                ),
                border: Border.all(color: KoalaColors.border, width: 0.5),
              ),
            ),
          ),
          const SizedBox(height: KoalaSpacing.xl),
          Text(title,
              style: KoalaText.h1, textAlign: TextAlign.center),
          const SizedBox(height: KoalaSpacing.sm),
          Text(
            msg,
            style: KoalaText.bodySec,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: KoalaSpacing.xxl),
          MekanPrimaryButton(
            label: 'Başka fotoğraf seç',
            onTap: () => Navigator.of(context).pop(),
            trailing: LucideIcons.image,
          ),
        ],
      ),
    );
  }

  ({String title, String body}) _humanError() {
    final m = _errorMsg ?? '';
    final lower = m.toLowerCase();
    if (lower.contains('insufficient credit') ||
        lower.contains('402') ||
        lower.contains('billing')) {
      return (
        title: 'Şu an tasarım yapamıyoruz',
        body: 'Görsel üretimi için kapasite geçici olarak doldu. '
            'Birazdan tekrar dener misin?',
      );
    }
    if (lower.contains('429') || lower.contains('rate limit')) {
      return (
        title: 'Biraz yoğunuz',
        body: 'Çok sayıda istek geldi. 30 saniye sonra tekrar dener misin?',
      );
    }
    if (lower.contains('load failed') ||
        lower.contains('clientexception') ||
        lower.contains('network') ||
        lower.contains('socketexception')) {
      return (
        title: 'İnternete ulaşamadım',
        body: 'Bağlantını kontrol edip tekrar dener misin?',
      );
    }
    return (
      title: 'Bir şey ters gitti',
      body: m.isEmpty ? 'Bilinmeyen hata' : m,
    );
  }

  Widget _errorView() {
    final e = _humanError();
    return Padding(
      key: const ValueKey('error'),
      padding: const EdgeInsets.fromLTRB(
          KoalaSpacing.xl, KoalaSpacing.md, KoalaSpacing.xl, KoalaSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: KoalaColors.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(LucideIcons.alertCircle,
                  color: KoalaColors.error, size: 32),
            ),
          ),
          const SizedBox(height: KoalaSpacing.xl),
          Text(e.title,
              style: KoalaText.h1, textAlign: TextAlign.center),
          const SizedBox(height: KoalaSpacing.sm),
          Text(
            e.body,
            style: KoalaText.bodySec,
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: KoalaSpacing.xxl),
          MekanPrimaryButton(
            label: 'Tekrar dene',
            onTap: () {
              if (_analysis == null) {
                _analyze();
              } else if (_theme != null) {
                _generate(_theme!);
              } else {
                _analyze();
              }
            },
            trailing: LucideIcons.refreshCw,
          ),
          const SizedBox(height: KoalaSpacing.md),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Geri dön',
                style: KoalaText.label.copyWith(
                  color: KoalaColors.textSec,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Analiz yüklenirken gösterilen ekran — fotonun üstünde soldan sağa
/// süzülen mor tarama çizgisi + dönen durum metni. "AI gerçekten bakıyor"
/// hissi verir; 3-5 saniyelik bir beklemeyi sıkmadan geçirir.
class _AnalyzingView extends StatefulWidget {
  final Uint8List bytes;
  final String? referenceUrl;
  const _AnalyzingView({super.key, required this.bytes, this.referenceUrl});

  @override
  State<_AnalyzingView> createState() => _AnalyzingViewState();
}

class _AnalyzingViewState extends State<_AnalyzingView>
    with TickerProviderStateMixin {
  static const _statuses = [
    'Odayı okuyorum',
    'Renkleri eşliyorum',
    'Mobilyaları tanıyorum',
    'Havayı yakalıyorum',
  ];

  late final AnimationController _scan;
  late final AnimationController _pulse;
  Timer? _timer;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    _scan = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!mounted) return;
      setState(() => _i = (_i + 1) % _statuses.length);
    });
  }

  @override
  void dispose() {
    _scan.dispose();
    _pulse.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KoalaSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
          // Referans tasarım varsa: 2 görsel + ortada "+", yoksa tek görsel.
          if (widget.referenceUrl != null && widget.referenceUrl!.isNotEmpty)
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, _) {
                final t = _pulse.value;
                return SizedBox(
                  height: 160,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Sol: kullanıcının fotoğrafı
                          Container(
                            width: 140,
                            height: 160,
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(KoalaRadius.xl),
                              boxShadow: [
                                BoxShadow(
                                  color: KoalaColors.accent.withValues(
                                      alpha: 0.18 + 0.08 * t),
                                  blurRadius: 24 + 10 * t,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(KoalaRadius.xl),
                              child: Image.memory(widget.bytes,
                                  fit: BoxFit.cover),
                            ),
                          ),
                          const SizedBox(width: 56),
                          // Sağ: swipe'tan gelen referans
                          Container(
                            width: 140,
                            height: 160,
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(KoalaRadius.xl),
                              boxShadow: [
                                BoxShadow(
                                  color: KoalaColors.accent.withValues(
                                      alpha: 0.18 + 0.08 * t),
                                  blurRadius: 24 + 10 * t,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(KoalaRadius.xl),
                              child: Image.network(
                                widget.referenceUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                    color: KoalaColors.surfaceAlt),
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Orta: + işareti
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              KoalaColors.accentDeep,
                              KoalaColors.accent,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  KoalaColors.accent.withValues(alpha: 0.5),
                              blurRadius: 16 + 6 * t,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(LucideIcons.plus,
                            color: Colors.white, size: 22),
                      ),
                    ],
                  ),
                );
              },
            )
          else
            AnimatedBuilder(
            animation: _pulse,
            builder: (_, _) {
              final t = _pulse.value;
              return Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(KoalaRadius.xl),
                  boxShadow: [
                    BoxShadow(
                      color: KoalaColors.accent
                          .withValues(alpha: 0.18 + 0.10 * t),
                      blurRadius: 30 + 14 * t,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(KoalaRadius.xl),
                  child: Image.memory(widget.bytes, fit: BoxFit.cover),
                ),
              );
            },
          ),
          const SizedBox(height: KoalaSpacing.xxl),
          Text(
            widget.referenceUrl != null && widget.referenceUrl!.isNotEmpty
                ? 'Tasarımın hazırlanıyor'
                : 'Fotoğrafın inceleniyor',
            style: KoalaText.h2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: KoalaSpacing.sm),
          SizedBox(
            height: 20,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 380),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.3),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: Text(
                '${_statuses[_i]}…',
                key: ValueKey(_i),
                style: KoalaText.bodySec,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: KoalaSpacing.xl),
          SizedBox(
            width: 140,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(KoalaRadius.pill),
              child: const LinearProgressIndicator(
                minHeight: 3,
                backgroundColor: KoalaColors.surfaceAlt,
                valueColor:
                    AlwaysStoppedAnimation<Color>(KoalaColors.accentDeep),
              ),
            ),
          ),
          // Süreci Küçült kaldırıldı (2026-04-28).
          ],
        ),
      ),
    );
  }
}

/// Fotonun üstünde yukarı-aşağı süzülen 2px'lik mor çizgi + altı aydınlatan
/// yumuşak glow. Sadelik için tek sıfır-1 ilerleme değeriyle çalışır.
class _ScanLinePainter extends CustomPainter {
  final double progress;
  _ScanLinePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;
    // Glow
    final glow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          KoalaColors.accentDeep.withValues(alpha: 0.28),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, y - 18, size.width, 36));
    canvas.drawRect(Rect.fromLTWH(0, y - 18, size.width, 36), glow);
    // Çizgi
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
  }

  @override
  bool shouldRepaint(covariant _ScanLinePainter old) =>
      old.progress != progress;
}

/// Kamera vizör köşeleri — fotonun 4 köşesine minik L'ler.
class _CornerFrame extends StatelessWidget {
  const _CornerFrame();

  @override
  Widget build(BuildContext context) {
    const c = KoalaColors.accentDeep;
    Widget corner(
            {bool top = false, bool left = false, bool right = false, bool bottom = false}) =>
        Positioned(
          top: top ? 10 : null,
          left: left ? 10 : null,
          right: right ? 10 : null,
          bottom: bottom ? 10 : null,
          child: CustomPaint(
            size: const Size(18, 18),
            painter: _CornerPainter(
                top: top, left: left, right: right, bottom: bottom, color: c),
          ),
        );
    return Stack(
      children: [
        corner(top: true, left: true),
        corner(top: true, right: true),
        corner(bottom: true, left: true),
        corner(bottom: true, right: true),
      ],
    );
  }
}

class _CornerPainter extends CustomPainter {
  final bool top, left, right, bottom;
  final Color color;
  _CornerPainter({
    required this.top,
    required this.left,
    required this.right,
    required this.bottom,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final w = size.width, h = size.height;
    if (top && left) {
      canvas.drawLine(const Offset(0, 0), Offset(w * 0.7, 0), p);
      canvas.drawLine(const Offset(0, 0), Offset(0, h * 0.7), p);
    } else if (top && right) {
      canvas.drawLine(Offset(w, 0), Offset(w * 0.3, 0), p);
      canvas.drawLine(Offset(w, 0), Offset(w, h * 0.7), p);
    } else if (bottom && left) {
      canvas.drawLine(Offset(0, h), Offset(w * 0.7, h), p);
      canvas.drawLine(Offset(0, h), Offset(0, h * 0.3), p);
    } else if (bottom && right) {
      canvas.drawLine(Offset(w, h), Offset(w * 0.3, h), p);
      canvas.drawLine(Offset(w, h), Offset(w, h * 0.3), p);
    }
  }

  @override
  bool shouldRepaint(covariant _CornerPainter old) =>
      old.color != color;
}
