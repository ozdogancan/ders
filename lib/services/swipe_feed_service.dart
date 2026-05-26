// ═══════════════════════════════════════════════════════════════════════════
// SWIPE FEED SERVICE — Tarzını Keşfet feed algoritması.
//
// Sorumluluk: aday kart havuzunu (Evlumba designer_projects + Koala
// koala_cards seed) puanlayıp DECK SIRASINI üretmek. Fetch/DB tarafını
// değiştirmiyor; sadece zaten elde olan batch üzerinde ranking + variety
// constraint + discovery slot + addiction-loop yerleştirmeleri uyguluyor.
//
// Performans:
//  - Pure in-memory, O(n log n) sort + tek geçişli yerleştirme.
//  - Taste profile cache: 10 like delta'da bir re-derive. RAM-only.
//  - 500'lük SharedPreferences ring buffer: son görülen kart id'leri.
//  - Tüm signature'lar sync (taste profile dışında); UI thread'i bloklamaz.
//
// Algoritma:
//  - Score(card) = taste_match*4 + room_freshness*2 + novelty*3
//                  + quality*1 + designer_exposure_bonus*2 - room_streak_penalty
//  - Discovery slot: her N (default 5) kartta bir "exploration" — taste
//    eşleşmesinden bağımsız, seeded / under-exposed öne çıkar.
//  - Variety: 10 kartlık pencerede max 3 same-designer, max 4 same-room.
//  - 200 kart içinde duplicate yok (recently-seen ring buffer).
//  - Addiction hit: kullanıcı 20+ like topladıysa, her 3. slotta high-confidence
//    taste match enjekte edilir (Pavlovian pacing).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const String _prefsSeenKey = 'swipe_feed_seen_v1';

  // ── Taste profile memoization ─────────────────────────────────────────────
  static TasteProfile? _cachedProfile;
  static int _profileLikeSnapshot = -1;
  // Re-derive eşiği: 10 yeni like geldikten sonra.
  static const int _profileRefreshDelta = 10;

  /// Mevcut taste profile snapshot'ını döndürür; gerekirse re-derive eder.
  /// Caller `currentLikeCount` parametresinden son like sayısını verirse
  /// gereksiz recompute'lardan kaçınılır.
  static Future<TasteProfile> getProfile({required int currentLikeCount}) async {
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

  /// Bir kartı "şu an gösterildi" olarak işaretle — ring buffer'a ekle.
  /// SharedPreferences yazımı arka planda yapılır; çağıran await etmemeli.
  static Future<void> markShown(String cardId) async {
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
  }) async {
    if (candidates.isEmpty) return const [];
    final profile = await getProfile(
        currentLikeCount: totalLikesAllTime < 0 ? 0 : totalLikesAllTime);
    // Caller -1 verirse profile'ın kendi sampleCount'unu kullan.
    if (totalLikesAllTime < 0) totalLikesAllTime = profile.sampleCount;

    // 1) Recently-seen dedup (son 200 kart).
    final dedup = <Map<String, dynamic>>[];
    for (final c in candidates) {
      final id = (c['id'] ?? '').toString();
      if (id.isEmpty) continue;
      if (await _isRecentlySeen(id)) continue;
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

      _Scored? pick;
      if (isAddiction) {
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
    // yoksa default 0.5.
    final q = (card['quality_score'] as num?)?.toDouble() ?? 0.5;
    s += q * 1.0;

    // (2) Taste match — kart stilleri profil top-styles ile kesişiyor mu?
    if (profile.isActive && profile.topStyles.isNotEmpty) {
      final styles = TasteProfileService.stylesOf(card);
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

    // (5) Recency boost — created_at son 30 gün ise +.
    final createdMs = _parseTime(card['created_at']);
    if (createdMs > 0) {
      final ageDays =
          (DateTime.now().millisecondsSinceEpoch - createdMs) / 86400000.0;
      if (ageDays < 30) s += (1.0 - ageDays / 30.0) * 1.0;
    }

    // (6) Küçük jitter — aynı skorlular için rotasyon, deterministic boredom
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
