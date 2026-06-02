// ═══════════════════════════════════════════════════════════════════════════
// SWIPE FEED SERVICE — Tarzını Keşfet feed algoritması.
//
// Sorumluluk: aday kart havuzunu (Evlumba designer_projects + Koala
// koala_cards seed) puanlayıp DECK SIRASINI üretmek. Fetch/DB tarafını
// değiştirmiyor; sadece zaten elde olan batch üzerinde ranking + variety
// constraint + discovery slot + addiction-loop yerleştirmeleri uyguluyor.
//
// Faz 1.5 (2026-05-27): dwell-time decay penalty, designer cooldown,
// style novelty boost (anti-monotony), epsilon-greedy exploration (15%).
// Faz 2 (opsiyonel): server-side `koala_rank_feed` RPC — cosine sim üzerinden
// embedding-based ranking; pgvector kullanır. `rankFromServer` ile çağırılır.
// Evlumba-must-be-first kuralı KALDIRILDI — seeded kartlar normal ranking
// üzerinden akar.
//
// Performans:
//  - Pure in-memory, O(n log n) sort + tek geçişli yerleştirme.
//  - Taste profile cache: 10 like delta'da bir re-derive. RAM-only.
//  - 500'lük SharedPreferences ring buffer: son görülen kart id'leri.
//  - Tüm signature'lar sync (taste profile dışında); UI thread'i bloklamaz.
//
// Algoritma (client-side):
//  - Score(card) = quality*1 + taste_match*4 - skip_decay_penalty*3
//                  + room_match*1 + designer_exposure*2 + recency*1
//                  - designer_cooldown_penalty*2 + novelty_boost*2 + jitter
//  - Discovery slot: her N (default 5) kartta bir "exploration" — taste
//    eşleşmesinden bağımsız, seeded / under-exposed öne çıkar.
//  - Addiction slot: kullanıcı 20+ like topladıysa, her 3. slotta
//    high-confidence taste match enjekte edilir (Pavlovian pacing).
//  - Epsilon-greedy: %15 slotta wider pool'dan rastgele kart (Reels surprise).
//  - Variety: 10 kartlık pencerede max 3 same-designer, max 4 same-room.
//  - 200 kart içinde duplicate yok (recently-seen ring buffer).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:firebase_auth/firebase_auth.dart';

import 'taste_profile_service.dart';

class SwipeFeedService {
  SwipeFeedService._();

  // Tuning constants — değişiklikleri burada yapın, screen'e dokunmayın.
  static const int _discoverySlotEvery = 5;
  static const int _addictionSlotEvery = 3;
  static const int _addictionMinLikes = 20;
  static const int _windowSize = 10;
  static const int _maxSameDesignerInWindow = 3;
  static const int _maxSameRoomInWindow = 4;
  static const int _seenRingCap = 500;
  static const int _noRepeatWithin = 200;
  static const double _epsilonExploration = 0.15; // %15 random surprise slot
  static const int _designerCooldownWindow = 20; // skipped → 20 kart soğusun
  static const int _recencyDays = 14;
  static const String _prefsSeenKey = 'swipe_feed_seen_v1';

  // ── Taste profile memoization ─────────────────────────────────────────────
  static TasteProfile? _cachedProfile;
  static int _profileLikeSnapshot = -1;
  // Re-derive eşiği: 10 yeni like geldikten sonra.
  static const int _profileRefreshDelta = 10;

  // ── Dwell / skip-decay signal state ───────────────────────────────────────
  // Style key (lowercase) → skip count (session). Her style için `1-exp(-n/3)`
  // penalty hesaplanır — sık skip edilen style harder cezalanır.
  static final Map<String, int> _styleSkipCount = {};
  // designer_id → kalan cooldown slot sayısı. _designerCooldownWindow'dan
  // başlar, her placement'ta -1. >0 ise o tasarımcının kartına penalty.
  static final Map<String, int> _designerCooldown = {};
  // designer_id → ardışık skip sayısı (cooldown trigger için, >=2 → cooldown).
  static final Map<String, int> _designerRecentSkips = {};
  // Son N rendered card'ın baskın style'ı — novelty boost için.
  static final List<String> _recentStyleWindow = [];
  static const int _noveltyWindow = 5;

  // ── Sosyal boost (2026-06-02) ──────────────────────────────────────────────
  // Profesyonel tasarımcı (koala_user_profiles.mode='pro') yazarlara ve
  // kullanıcının TAKİP ettiklerine feed'de pozitif ağırlık. NOT: buradaki
  // "pro" PROFESYONEL TASARIMCI'dır — ücretli abone (billing isPro) DEĞİL.
  static final Set<String> _proAuthorIds = {};
  static final Set<String> _followedIds = {};
  static bool _socialLoaded = false;
  static const double _followBoost = 3.0; // takip edilen yazar
  static const double _proBoost = 2.0; // profesyonel tasarımcı yazar

  /// Pro-yazar + takip listesi set'lerini bir kez (session) yükle. Ranking
  /// öncesi getProfile'dan çağrılır → skorlama anında hazır.
  static Future<void> _ensureSocialBoosts() async {
    if (_socialLoaded) return;
    _socialLoaded = true;
    try {
      final sb = Supabase.instance.client;
      final pros = await sb
          .from('koala_user_profiles')
          .select('uid')
          .eq('mode', 'pro')
          .limit(1000);
      for (final r in List<Map<String, dynamic>>.from(pros)) {
        final u = (r['uid'] ?? '').toString();
        if (u.isNotEmpty) _proAuthorIds.add(u);
      }
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        final fol = await sb
            .from('koala_follows')
            .select('designer_id')
            .eq('user_id', uid)
            .limit(1000);
        for (final r in List<Map<String, dynamic>>.from(fol)) {
          final d = (r['designer_id'] ?? '').toString();
          if (d.isNotEmpty) _followedIds.add(d);
        }
      }
    } catch (_) {/* sessiz — boost opsiyonel */}
  }

  /// Mevcut taste profile snapshot'ını döndürür; gerekirse re-derive eder.
  /// Caller `currentLikeCount` parametresinden son like sayısını verirse
  /// gereksiz recompute'lardan kaçınılır.
  static Future<TasteProfile> getProfile({required int currentLikeCount}) async {
    await _ensureSocialBoosts();
    if (_cachedProfile != null &&
        _profileLikeSnapshot >= 0 &&
        (currentLikeCount - _profileLikeSnapshot).abs() < _profileRefreshDelta) {
      return _cachedProfile!;
    }
    final p = await TasteProfileService.computeProfile();
    _cachedProfile = p;
    _profileLikeSnapshot = currentLikeCount;
    return p;
  }

  /// Cache invalidation — kullanıcı reset / hesap değişikliği vb. sonrası.
  static void invalidateProfileCache() {
    _cachedProfile = null;
    _profileLikeSnapshot = -1;
    _styleSkipCount.clear();
    _designerCooldown.clear();
    _designerRecentSkips.clear();
    _recentStyleWindow.clear();
    _hasEmbeddingCache.clear();
    _proAuthorIds.clear();
    _followedIds.clear();
    _socialLoaded = false;
  }

  // ── Seen ring buffer ──────────────────────────────────────────────────────
  static List<String>? _seenRingMem;

  static Future<List<String>> _loadSeen() async {
    if (_seenRingMem != null) return _seenRingMem!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsSeenKey);
      if (raw == null || raw.isEmpty) {
        _seenRingMem = <String>[];
        return _seenRingMem!;
      }
      final list = (jsonDecode(raw) as List).cast<String>();
      _seenRingMem = list;
      return list;
    } catch (_) {
      _seenRingMem = <String>[];
      return _seenRingMem!;
    }
  }

  /// Bir kartı "şu an görüldü/swipe edildi" olarak işaretle —
  /// ring buffer'a ekle, in-memory skip/cooldown sinyallerini güncelle,
  /// Supabase `ingest_swipe_v2` RPC'sini fire-and-forget tetikle.
  ///
  /// [dwellMs] kullanıcının karta baktığı süre (ms). [liked] like ise true,
  /// pass ise false. Hem caller hem servis defensive — exception yutulur.
  static Future<void> markShown(
    String cardId, {
    int? dwellMs,
    bool liked = false,
    Map<String, dynamic>? card,
  }) async {
    if (cardId.isEmpty) return;
    final ring = await _loadSeen();
    ring.add(cardId);
    while (ring.length > _seenRingCap) {
      ring.removeAt(0);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsSeenKey, jsonEncode(ring));
    } catch (_) {}

    // In-memory signal update — sadece kart payload'ı verilmişse.
    if (card != null) {
      final designerId = (card['designer_id'] ?? '').toString();
      final styles = TasteProfileService.stylesOf(card);
      if (liked) {
        // Like geldiyse cooldown sayaçlarını sıfırla — bu tasarımcı affedildi.
        _designerRecentSkips.remove(designerId);
        if (styles.isNotEmpty) _recentStyleWindow.add(styles.first);
      } else {
        // Skip → style skip count++ (her style için ayrı).
        for (final s in styles) {
          _styleSkipCount[s] = (_styleSkipCount[s] ?? 0) + 1;
        }
        if (designerId.isNotEmpty) {
          final n = (_designerRecentSkips[designerId] ?? 0) + 1;
          _designerRecentSkips[designerId] = n;
          if (n >= 2) {
            // İki ardışık skip → cooldown başlat.
            _designerCooldown[designerId] = _designerCooldownWindow;
            _designerRecentSkips[designerId] = 0;
          }
        }
        if (styles.isNotEmpty) _recentStyleWindow.add(styles.first);
      }
      while (_recentStyleWindow.length > _noveltyWindow) {
        _recentStyleWindow.removeAt(0);
      }
    }

    // Supabase ML pipeline — fire-and-forget.
    unawaited(_persistSwipeSignal(
      cardId: cardId,
      dwellMs: dwellMs,
      liked: liked,
    ));
  }

  static Future<void> _persistSwipeSignal({
    required String cardId,
    required int? dwellMs,
    required bool liked,
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      // ingest_swipe RPC SADECE 'right'|'left'|'up'|'down' kabul eder.
      // 'like'/'pass' RAISE EXCEPTION fırlatır → user_taste vektör güncellenmez.
      // (2026-05-27 fix — Part D).
      await Supabase.instance.client.rpc('ingest_swipe_v2', params: {
        'p_user_id': uid,
        'p_card_id': cardId,
        'p_direction': liked ? 'right' : 'left',
        'p_context': 'style_discovery_live',
        'p_swipe_velocity': 0,
        'p_dwell_time_ms': dwellMs ?? 0,
        'p_idempotency_key': '${uid}_${cardId}_${DateTime.now().millisecondsSinceEpoch}',
      });
    } catch (_) {
      // RPC bulunmayabilir veya kart koala_cards'ta olmayabilir — sessizce geç.
    }
  }

  /// Son [_noRepeatWithin] içinde gösterilen mi?
  static Future<bool> _isRecentlySeen(String cardId) async {
    if (cardId.isEmpty) return false;
    final ring = await _loadSeen();
    if (ring.length <= _noRepeatWithin) return ring.contains(cardId);
    final start = ring.length - _noRepeatWithin;
    for (var i = start; i < ring.length; i++) {
      if (ring[i] == cardId) return true;
    }
    return false;
  }

  // ── Server-side ranker (Faz 2) ────────────────────────────────────────────
  /// Per-session cache — `userHasEmbedding(uid)` cache'i. uid → bool.
  /// Aynı session içinde tekrar tekrar `select exists` atmayı önler.
  /// Cache invalidation: [invalidateProfileCache] çağrısı sıfırlar.
  static final Map<String, bool> _hasEmbeddingCache = <String, bool>{};

  /// `koala_user_taste.embedding` non-null mı?
  /// Server-side ranker'ı default açmadan önce caller check eder.
  /// Cold-start (embedding yok) veya çok az swipe → false döner → client fallback.
  ///
  /// Cheap `select exists` — hata durumunda false döner, deck'i bozmaz.
  static Future<bool> userHasEmbedding(String uid) async {
    if (uid.isEmpty) return false;
    final cached = _hasEmbeddingCache[uid];
    if (cached != null) return cached;
    try {
      final res = await Supabase.instance.client
          .from('koala_user_taste')
          .select('user_id')
          .eq('user_id', uid)
          .not('embedding', 'is', null)
          .limit(1)
          .maybeSingle();
      final has = res != null;
      _hasEmbeddingCache[uid] = has;
      return has;
    } catch (e) {
      if (kDebugMode) debugPrint('SwipeFeed: userHasEmbedding failed → $e');
      return false;
    }
  }

  /// `koala_rank_feed` RPC'sini çağırır. Cosine similarity üzerinden
  /// embedding-based sıralama döner. Hata / boş sonuç → null (caller
  /// client-side ranker'a fallback yapar).
  static Future<List<Map<String, dynamic>>?> rankFromServer({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return null;
      final data = await Supabase.instance.client.rpc('koala_rank_feed',
          params: {'p_user_id': uid, 'p_limit': limit, 'p_offset': offset});
      if (data == null) return null;
      final list = List<Map<String, dynamic>>.from(
          (data as List).map((e) => Map<String, dynamic>.from(e as Map)));
      return list;
    } catch (e) {
      if (kDebugMode) debugPrint('SwipeFeed: rankFromServer fallback → $e');
      return null;
    }
  }

  // ── Public API: bir batch'i puanla ve sırala ──────────────────────────────

  /// [candidates] üzerinde puanlama + variety + discovery + addiction
  /// kuralları uygulayıp final ordered deck listesini döndürür.
  ///
  /// [currentDeckTail] var olan deck'in son [_windowSize] kartı — variety
  /// constraint'inin sınır geçişine devamlılık sağlar (yeni batch eklerken
  /// önceki kartlardaki designer/room'ları da say).
  static Future<List<Map<String, dynamic>>> rankBatch({
    required List<Map<String, dynamic>> candidates,
    List<Map<String, dynamic>> currentDeckTail = const [],
    int totalLikesAllTime = -1,
    bool bypassRecency = false,
  }) async {
    if (candidates.isEmpty) return const [];
    final profile = await getProfile(
        currentLikeCount: totalLikesAllTime < 0 ? 0 : totalLikesAllTime);
    // Caller -1 verirse profile'ın kendi sampleCount'unu kullan.
    if (totalLikesAllTime < 0) totalLikesAllTime = profile.sampleCount;

    // 1) Recently-seen dedup (son 200 kart). [bypassRecency]=true ise atlanır —
    //    tüm taze kartlar tükendi, kullanıcının durmaması için tekrar göster.
    final dedup = <Map<String, dynamic>>[];
    for (final c in candidates) {
      final id = (c['id'] ?? '').toString();
      if (id.isEmpty) continue;
      if (!bypassRecency && await _isRecentlySeen(id)) continue;
      dedup.add(c);
    }
    if (dedup.isEmpty) return const [];

    // 2) Score her aday için.
    final scored = <_Scored>[];
    for (final c in dedup) {
      scored.add(_Scored(card: c, score: _score(c, profile)));
    }

    // 3) Genel sıralama: yüksek skor önce.
    scored.sort((a, b) => b.score.compareTo(a.score));

    // 4) High-pool / exploration-pool ayır.
    //    High = üst yarı (taste match güçlü).
    //    Explore = alt yarı + seeded + low-view (under-exposed) bias.
    final half = (scored.length / 2).ceil();
    final highPool = scored.take(half).toList();
    final explorePool = scored.skip(half).toList();
    // Explore havuzunu under-exposed bias'la karıştır:
    //  - seeded (source='gemini-seed' veya designer_id='evlumba-design') öne
    //  - view_count düşük olanlar öne
    explorePool.sort((a, b) {
      final sa = _isSeeded(a.card) ? 1 : 0;
      final sb = _isSeeded(b.card) ? 1 : 0;
      if (sa != sb) return sb - sa;
      final va = (a.card['view_count'] as num?)?.toDouble() ?? 0;
      final vb = (b.card['view_count'] as num?)?.toDouble() ?? 0;
      return va.compareTo(vb);
    });
    // Epsilon-greedy "surprise" pool — entire scored set, shuffled.
    final surprisePool = List<_Scored>.from(scored)..shuffle(_rng);
    int surpIdx = 0;

    // 5) Variety + slot pacing ile final yerleştirme.
    final result = <Map<String, dynamic>>[];
    final designerWindow = <String>[];
    final roomWindow = <String>[];
    // currentDeckTail'in son N'ini pencereye doldur — boundary continuity.
    for (final t in currentDeckTail
        .skip(math.max(0, currentDeckTail.length - _windowSize))) {
      designerWindow.add((t['designer_id'] ?? '').toString());
      roomWindow.add(_roomKey(t));
    }

    int hiIdx = 0;
    int exIdx = 0;
    final useAddiction = totalLikesAllTime >= _addictionMinLikes;

    // Yerleştirme: her slot için
    // - %15 epsilon → surprise pool (random kart, variety constraint zorunlu)
    // - addiction slot mu? high-confidence taste match al
    // - discovery slot mu? explore pool'dan al
    // - değilse yüksek skordan al
    // - variety constraint ihlal ediyorsa sıradakini dene
    final totalSlots = scored.length;
    for (var slot = 0; slot < totalSlots; slot++) {
      final globalSlot = currentDeckTail.length + result.length;
      final isAddiction = useAddiction &&
          globalSlot > 0 &&
          globalSlot % _addictionSlotEvery == 0;
      final isDiscovery = globalSlot > 0 && globalSlot % _discoverySlotEvery == 0;
      // Epsilon-greedy: addiction/discovery slot DEĞİLSE %15 ihtimalle random.
      final isSurprise = !isAddiction &&
          !isDiscovery &&
          _rng.nextDouble() < _epsilonExploration;

      _Scored? pick;
      if (isSurprise) {
        pick = _pickFromPool(
          surprisePool, surpIdx,
          designerWindow, roomWindow,
        );
        if (pick != null) {
          surpIdx = surprisePool.indexOf(pick) + 1;
          // High/explore pool index'lerini de senkronize tut — duplicate önle.
          final hi = highPool.indexOf(pick);
          if (hi >= hiIdx) hiIdx = hi + 1;
          final ex = explorePool.indexOf(pick);
          if (ex >= exIdx) exIdx = ex + 1;
        }
      }
      if (pick == null && isAddiction) {
        pick = _pickFromPool(
          highPool, hiIdx,
          designerWindow, roomWindow,
          requireTasteHit: true, profile: profile,
        );
        if (pick != null) hiIdx = highPool.indexOf(pick) + 1;
      }
      if (pick == null && isDiscovery) {
        pick = _pickFromPool(
          explorePool, exIdx,
          designerWindow, roomWindow,
        );
        if (pick != null) exIdx = explorePool.indexOf(pick) + 1;
      }
      if (pick == null) {
        pick = _pickFromPool(
          highPool, hiIdx,
          designerWindow, roomWindow,
        );
        if (pick != null) hiIdx = highPool.indexOf(pick) + 1;
      }
      if (pick == null) {
        pick = _pickFromPool(
          explorePool, exIdx,
          designerWindow, roomWindow,
        );
        if (pick != null) exIdx = explorePool.indexOf(pick) + 1;
      }
      if (pick == null) {
        // Variety pencereye uymadı; ilk uygunu bul (sliding constraint relax).
        pick = _firstNonNull(highPool, hiIdx, explorePool, exIdx);
        if (pick != null) {
          if (highPool.contains(pick)) {
            hiIdx = highPool.indexOf(pick) + 1;
          } else {
            exIdx = explorePool.indexOf(pick) + 1;
          }
        }
      }
      if (pick == null) break;

      result.add(pick.card);
      // Designer cooldown'unu placement başına decrement et.
      _designerCooldown.forEach((k, v) {
        if (v > 0) _designerCooldown[k] = v - 1;
      });
      designerWindow.add((pick.card['designer_id'] ?? '').toString());
      roomWindow.add(_roomKey(pick.card));
      if (designerWindow.length > _windowSize) designerWindow.removeAt(0);
      if (roomWindow.length > _windowSize) roomWindow.removeAt(0);
    }

    if (kDebugMode) {
      debugPrint(
        'SwipeFeed: ranked ${candidates.length}→${result.length} '
        '(likes=$totalLikesAllTime profile=${profile.isActive ? profile.topStyles.map((s) => s.style).join(",") : "inactive"})',
      );
    }
    return result;
  }

  // ── internals ─────────────────────────────────────────────────────────────

  static double _score(Map<String, dynamic> card, TasteProfile profile) {
    var s = 0.0;
    // (1) Quality baseline — koala_cards.quality_score; designer_projects'te
    // yoksa default 0.5. Ağırlık 1.5 (önceden 1.0) — yüksek kaliteli kartları
    // daha agresif promote et.
    final q = (card['quality_score'] as num?)?.toDouble() ?? 0.5;
    s += q * 1.5;

    final styles = TasteProfileService.stylesOf(card);

    // (2) Taste match — kart stilleri profil top-styles ile kesişiyor mu?
    if (profile.isActive && profile.topStyles.isNotEmpty) {
      var match = 0.0;
      for (final ts in profile.topStyles) {
        if (styles.contains(ts.style)) {
          match += ts.share * 4.0; // baskın stilde +4'e kadar
        }
      }
      // Blocklist (5+ pass) ise sert ceza.
      for (final b in profile.blockedStyles) {
        if (styles.contains(b)) match -= 3.0;
      }
      s += match;
    }

    // (2b) Skip-decay penalty — bu stilde ne kadar çok skip'lendiyse o kadar
    //      sert düş. weight = 1 - exp(-skip_count/3). 3 skip = ~0.63, 6 = ~0.86.
    for (final st in styles) {
      final n = _styleSkipCount[st] ?? 0;
      if (n > 0) {
        final w = 1.0 - math.exp(-n / 3.0);
        s -= w * 3.0;
      }
    }

    // (3) Room match — top room'larda yer alıyorsa hafif bonus.
    if (profile.isActive && profile.topRooms.isNotEmpty) {
      final r = _roomKey(card);
      if (r.isNotEmpty && profile.topRooms.contains(r)) s += 1.0;
    }

    // (4) Designer exposure bonus — düşük view_count tasarımcılarına +.
    //     view_count yoksa varsay 0 → tam bonus (seeded de buraya düşer).
    final views = (card['view_count'] as num?)?.toDouble() ?? 0;
    if (views < 50) {
      s += 2.0 * (1.0 - (views / 50.0));
    }

    // (4b) Designer cooldown — son 2 kartı skip edilenler bir süre düşük.
    final did = (card['designer_id'] ?? '').toString();
    if (did.isNotEmpty && (_designerCooldown[did] ?? 0) > 0) {
      s -= 2.0;
    }

    // (5) Recency boost — created_at son 14 gün ise +. Bias toward fresh.
    final createdMs = _parseTime(card['created_at']);
    if (createdMs > 0) {
      final ageDays =
          (DateTime.now().millisecondsSinceEpoch - createdMs) / 86400000.0;
      if (ageDays < _recencyDays) {
        s += (1.0 - ageDays / _recencyDays) * 1.0;
      }
    }

    // (4c) Evlumba seed boost — 2026-05-28 FIX 3c. Boost'u +5.0 cold-start,
    // +1.0 mature taste'e çıkardık (önceki: +2.5 → +0.5). Variety constraint
    // ve normal ranking altında seed kartlar yine de görünür kalmalı.
    if (_isSeeded(card)) {
      final samples = profile.sampleCount;
      // Cold start (≤20 likes) → +5.0. Mature taste (≥40 likes) → +1.0.
      double boost;
      if (samples <= 20) {
        boost = 5.0;
      } else if (samples >= 40) {
        boost = 1.0;
      } else {
        boost = 5.0 - ((samples - 20) / 20.0) * 4.0;
      }
      s += boost;
    }

    // (5b) Novelty boost — son 5 kart aynı style ise farklı style'a +2.
    if (_recentStyleWindow.length >= _noveltyWindow) {
      final dominant = _recentStyleWindow.first;
      final allSame = _recentStyleWindow.every((x) => x == dominant);
      if (allSame && styles.isNotEmpty && !styles.contains(dominant)) {
        s += 2.0;
      }
    }

    // (7) Sosyal boost (2026-06-02) — profesyonel tasarımcı yazarlar + takip
    //     ettiklerin feed'de öne çıksın. authorId: kullanıcı paylaşımında
    //     user_id, Evlumba projesinde designer_id. (Buradaki "pro" PROFESYONEL
    //     tasarımcı; ücretli abone DEĞİL.)
    final authorId =
        (card['user_id'] ?? card['designer_id'] ?? '').toString();
    if (authorId.isNotEmpty) {
      if (_followedIds.contains(authorId)) s += _followBoost;
      if (_proAuthorIds.contains(authorId)) s += _proBoost;
    }

    // (8) Küçük jitter — aynı skorlular için rotasyon, deterministic boredom
    //     önler.
    s += _rng.nextDouble() * 0.3;
    return s;
  }

  static _Scored? _pickFromPool(
    List<_Scored> pool,
    int fromIdx,
    List<String> designerWindow,
    List<String> roomWindow, {
    bool requireTasteHit = false,
    TasteProfile? profile,
  }) {
    for (var i = fromIdx; i < pool.length; i++) {
      final s = pool[i];
      final did = (s.card['designer_id'] ?? '').toString();
      final rk = _roomKey(s.card);
      // Variety constraint
      final desCount = designerWindow.where((d) => d == did && d.isNotEmpty).length;
      if (desCount >= _maxSameDesignerInWindow) continue;
      final roomCount = roomWindow.where((r) => r == rk && r.isNotEmpty).length;
      if (roomCount >= _maxSameRoomInWindow) continue;
      if (requireTasteHit && profile != null && profile.isActive) {
        final styles = TasteProfileService.stylesOf(s.card);
        final hit = profile.topStyles.any((t) => styles.contains(t.style));
        if (!hit) continue;
      }
      return s;
    }
    return null;
  }

  static _Scored? _firstNonNull(
    List<_Scored> a, int aIdx,
    List<_Scored> b, int bIdx,
  ) {
    if (aIdx < a.length) return a[aIdx];
    if (bIdx < b.length) return b[bIdx];
    return null;
  }

  static String _roomKey(Map<String, dynamic> card) {
    final pt = (card['project_type'] ?? '').toString().toLowerCase().trim();
    return pt;
  }

  static bool _isSeeded(Map<String, dynamic> card) {
    if (card['_seed'] == true) return true;
    if ((card['designer_id'] ?? '').toString() == 'evlumba-design') return true;
    if ((card['source'] ?? '').toString() == 'gemini-seed') return true;
    return false;
  }

  static int _parseTime(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is String) {
      try {
        return DateTime.parse(v).millisecondsSinceEpoch;
      } catch (_) {
        return 0;
      }
    }
    return 0;
  }

  static final math.Random _rng = math.Random();
}

class _Scored {
  final Map<String, dynamic> card;
  final double score;
  _Scored({required this.card, required this.score});
}
