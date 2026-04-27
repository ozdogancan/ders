import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:uuid/uuid.dart';

/// Centralized analytics service — logs events to Supabase analytics_events table.
/// Usage: Analytics.log('event_name', {'key': 'value'});
class Analytics {
  Analytics._();
  static final Analytics instance = Analytics._();

  String _sessionId = const Uuid().v4();
  String _platform = 'web';
  String _appVersion = '1.0.0';
  bool _enabled = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Call once at app start
  void init({
    String platform = 'web',
    String appVersion = '1.0.0',
    bool enabled = true,
  }) {
    _sessionId = const Uuid().v4();
    _platform = platform;
    _appVersion = appVersion;
    _enabled = enabled;
  }

  /// Start a new session (call on app resume / fresh open)
  void newSession() {
    _sessionId = const Uuid().v4();
  }

  /// Log an event
  static Future<void> log(
    String eventName, [
    Map<String, dynamic>? data,
  ]) async {
    return instance._log(eventName, data);
  }

  Future<void> _log(String eventName, Map<String, dynamic>? data) async {
    if (!_enabled) return;
    try {
      await Supabase.instance.client.from('analytics_events').insert({
        'user_id': _uid,
        'event_name': eventName,
        'event_data': data ?? {},
        'session_id': _sessionId,
        'platform': _platform,
        'app_version': _appVersion,
      });
    } catch (e) {
      debugPrint('Analytics error: $e');
    }
  }

  // ═══════════════════════════════════════════
  // CONVENIENCE METHODS
  // ═══════════════════════════════════════════

  // — App lifecycle —
  static Future<void> appOpened() => log('app_opened');
  static Future<void> appBackgrounded(int durationSeconds) =>
      log('app_backgrounded', {'session_duration_seconds': durationSeconds});

  // — Onboarding —
  static Future<void> onboardingStarted() => log('onboarding_started');
  static Future<void> onboardingCompleted(int durationSeconds) =>
      log('onboarding_completed', {'duration_seconds': durationSeconds});
  static Future<void> onboardingSkipped(int pageIndex) =>
      log('onboarding_skipped', {'page_index': pageIndex});

  // — Auth —
  static Future<void> signupStarted(String method) =>
      log('signup_started', {'method': method});
  static Future<void> signupCompleted(String method) =>
      log('signup_completed', {'method': method});
  static Future<void> signupFailed(String method, String error) =>
      log('signup_failed', {'method': method, 'error': error});
  static Future<void> loginCompleted(String method) =>
      log('login_completed', {'method': method});
  static Future<void> logoutCompleted() => log('logout_completed');

  // — Question flow —
  static Future<void> questionPhotoTaken(String source) =>
      log('question_photo_taken', {'source': source});
  static Future<void> questionSubjectDetected(
    String subject,
    bool changedByUser,
  ) => log('question_subject_detected', {
    'subject': subject,
    'changed_by_user': changedByUser,
  });
  static Future<void> questionSubmitted(String questionId, String subject) =>
      log('question_submitted', {
        'question_id': questionId,
        'subject': subject,
      });
  static Future<void> questionSolved(
    String questionId,
    int durationSeconds,
    String subject,
  ) => log('question_solved', {
    'question_id': questionId,
    'duration_seconds': durationSeconds,
    'subject': subject,
  });
  static Future<void> questionSolveError(String questionId) =>
      log('question_solve_error', {'question_id': questionId});
  static Future<void> questionDeleted(String questionId) =>
      log('question_deleted', {'question_id': questionId});

  // — Chat —
  static Future<void> chatOpened(String questionId, String subject) =>
      log('chat_opened', {'question_id': questionId, 'subject': subject});
  static Future<void> chatMessageSent(
    String questionId, {
    bool isPreset = false,
    bool isCoach = false,
  }) => log('chat_message_sent', {
    'question_id': questionId,
    'is_preset': isPreset,
    'is_coach': isCoach,
  });
  static Future<void> coachModeStarted(String questionId) =>
      log('coach_mode_started', {'question_id': questionId});
  static Future<void> solutionRated(
    String questionId,
    int rating,
    bool hasFeedback,
  ) => log('solution_rated', {
    'question_id': questionId,
    'rating': rating,
    'has_feedback': hasFeedback,
  });

  // — Credits —
  static Future<void> creditSpent(String source, int remaining) =>
      log('credit_spent', {'source': source, 'remaining_credits': remaining});
  static Future<void> creditZeroReached() => log('credit_zero_reached');
  static Future<void> purchaseScreenOpened(String trigger) =>
      log('purchase_screen_opened', {'trigger': trigger});
  static Future<void> purchaseCompleted(String productId, int credits) => log(
    'purchase_completed',
    {'product_id': productId, 'credits_received': credits},
  );

  // — Navigation —
  static Future<void> screenViewed(String screenName) =>
      log('screen_viewed', {'screen_name': screenName});
  static Future<void> searchPerformed(
    String query,
    int resultsCount,
    String screen,
  ) => log('search_performed', {
    'query': query,
    'results_count': resultsCount,
    'screen': screen,
  });
  static Future<void> filterUsed(
    String filterType,
    String value,
    String screen,
  ) => log('filter_used', {
    'filter_type': filterType,
    'value': value,
    'screen': screen,
  });

  // — Profile —
  static Future<void> profileUpdated(List<String> fields) =>
      log('profile_updated', {'fields_changed': fields});
  static Future<void> profilePhotoChanged() => log('profile_photo_changed');

  // ═══════════════════════════════════════════
  // SUCCESS FACTOR EVENTS
  // ═══════════════════════════════════════════

  // — SF1: Save signals —
  static Future<void> itemSaved(String itemType, String itemId, String title) =>
      log('item_saved', {'item_type': itemType, 'item_id': itemId, 'title': title});
  static Future<void> itemRemoved(String itemType, String itemId) =>
      log('item_removed', {'item_type': itemType, 'item_id': itemId});
  static Future<void> savedItemViewed(String itemType, String itemId) =>
      log('saved_item_viewed', {'item_type': itemType, 'item_id': itemId});

  // — SF2: Designer contact signals —
  static Future<void> designerContacted(String designerId, String source) =>
      log('designer_contacted', {'designer_id': designerId, 'source': source});
  static Future<void> designerProfileViewed(String designerId, String source) =>
      log('designer_profile_viewed', {'designer_id': designerId, 'source': source});
  static Future<void> designerMessageSent(String conversationId) =>
      log('designer_message_sent', {'conversation_id': conversationId});

  // — SF3: Product deeplink signals —
  static Future<void> productOpened(String productId, String productName, String source) =>
      log('product_opened', {'product_id': productId, 'name': productName, 'source': source});
  static Future<void> productCompared(List<String> productNames) =>
      log('product_compared', {'product_names': productNames});

  // — AI interaction signals —
  static Future<void> aiChatStarted(String intent) =>
      log('ai_chat_started', {'intent': intent});
  static Future<void> aiCardDisplayed(String cardType) =>
      log('ai_card_displayed', {'card_type': cardType});
  static Future<void> aiPhotoUploaded(String source) =>
      log('ai_photo_uploaded', {'source': source});
  static Future<void> aiErrorOccurred(String error) =>
      log('ai_error_occurred', {'error': error});
  static Future<void> aiFallbackChipUsed(String chipLabel) =>
      log('ai_fallback_chip_used', {'chip': chipLabel});

  // — Wizard signals —
  static Future<void> wizardStarted() => log('wizard_started');
  static Future<void> wizardCompleted(String room, String style, String budget) =>
      log('wizard_completed', {'room': room, 'style': style, 'budget': budget});

  // ═══════════════════════════════════════════
  // MEKAN FLOW SIGNALS — Phase 1 quality telemetry
  // ═══════════════════════════════════════════

  /// Cihaz-tarafı ContentGate verdict (selfie/food/pet block).
  /// reason: 'selfie' | 'food' | 'pet' | 'vehicle' | 'document' | 'screen' | 'clothing' | 'outdoor' | 'other'
  static Future<void> mekanContentBlocked(String reason) =>
      log('mekan_content_blocked', {'reason': reason});

  /// Backend analyze sonucu — qualityScore + issues + band dağılımı.
  /// Bu event olmadan Phase 2 (Restyle v2) kalibrasyonu kör uçuş.
  static Future<void> mekanAnalyzed({
    required bool isRoom,
    required String roomType,
    required String style,
    required double qualityScore,
    required List<String> issues,
    required String band, // 'good' | 'soft' | 'reject'
    required int latencyMs,
  }) => log('mekan_analyzed', {
        'is_room': isRoom,
        'room_type': roomType,
        'style': style,
        'quality_score': qualityScore,
        'issues': issues,
        'band': band,
        'latency_ms': latencyMs,
      });

  /// Kalite hint sheet kullanıcıya gösterildi.
  static Future<void> mekanQualityHintShown({
    required List<String> issues,
    required double qualityScore,
  }) => log('mekan_quality_hint_shown', {
        'issues': issues,
        'quality_score': qualityScore,
      });

  /// Kalite hint sheet'inde kullanıcı kararı.
  /// choice: 'retake' | 'continue'
  static Future<void> mekanQualityHintChoice({
    required String choice,
    required List<String> issues,
    required double qualityScore,
  }) => log('mekan_quality_hint_choice', {
        'choice': choice,
        'issues': issues,
        'quality_score': qualityScore,
      });

  /// Restyle başarı/başarısızlık sinyali.
  /// outcome: 'success' | 'error' | 'rejected_by_user'
  ///
  /// v2 alanları (batch/3-variant):
  ///   variant: kullanıcıya gösterilen prompt_kind ('faithful'|'editorial'|'bold')
  ///   judgeScore: Gemini judge skoru (0-1) — kalite kalibrasyonu için
  ///   variantCount: judge'tan geçen toplam variant (1-3); v1'de her zaman 1
  ///   rejectedCount: judge'ın elediği variant sayısı (0-2); v2 only
  static Future<void> mekanRestyleOutcome({
    required String outcome,
    required String theme,
    required String roomType,
    required int latencyMs,
    String? errorCode,
    String? variant,
    double? judgeScore,
    int? variantCount,
    int? rejectedCount,
  }) => log('mekan_restyle_outcome', {
        'outcome': outcome,
        'theme': theme,
        'room_type': roomType,
        'latency_ms': latencyMs,
        if (errorCode != null) 'error_code': errorCode,
        if (variant != null) 'variant': variant,
        if (judgeScore != null) 'judge_score': judgeScore,
        if (variantCount != null) 'variant_count': variantCount,
        if (rejectedCount != null) 'rejected_count': rejectedCount,
      });

  /// /api/analyze-room çağrısı başladı — kaynak: 'camera' | 'gallery'.
  /// Outcome event'i ile birlikte CLIP gate'in funnel'daki etkisini ölçer.
  static Future<void> mekanAnalyzeStarted({required String source}) =>
      log('mekan_analyze_started', {'source': source});

  /// /api/analyze-room sonucu — valid + reject reason + latency.
  /// rejectReason: backend "reason" alanı (ör. "person's face / selfie").
  static Future<void> mekanAnalyzeOutcome({
    required bool valid,
    String? rejectReason,
    double? confidence,
    int? latencyMs,
  }) => log('mekan_analyze_outcome', {
        'valid': valid,
        if (rejectReason != null) 'reject_reason': rejectReason,
        if (confidence != null) 'confidence': confidence,
        if (latencyMs != null) 'latency_ms': latencyMs,
      });

  /// Pro CTA tıklandı — restyle sonucundan profesyonele.
  static Future<void> mekanProCtaTapped({
    required String theme,
    required String roomType,
  }) => log('mekan_pro_cta_tapped', {
        'theme': theme,
        'room_type': roomType,
      });

  // ─── Style Discovery (taste-discovery swipe + reveal) ───
  // /views/mekan/style_discovery_screen.dart akışı için event'ler.
  // Funnel: started → swipe (×N) → finished → revealOpened → accepted | refined.

  static Future<void> styleDiscoveryStarted({
    required String roomTypeGuess,
  }) =>
      log('style_discovery_started', {'room_type_guess': roomTypeGuess});

  static Future<void> styleDiscoverySwipe({
    required int index,
    required bool liked,
    required String cardId,
  }) =>
      log('style_discovery_swipe', {
        'index': index,
        'liked': liked,
        'card_id': cardId,
      });

  static Future<void> styleDiscoveryFinished({
    required int swipeCount,
    required List<String> topTags,
  }) =>
      log('style_discovery_finished', {
        'swipe_count': swipeCount,
        'top_tags': topTags,
      });

  static Future<void> styleDiscoveryRevealOpened() =>
      log('style_discovery_reveal_opened');

  static Future<void> styleDiscoveryAccepted() =>
      log('style_discovery_accepted');

  static Future<void> styleDiscoveryRefined() =>
      log('style_discovery_refined');

  // ─── Swipe Deck (mekan zevkimi keşfet) ───
  // /views/mekan/swipe_screen.dart akışı için event'ler.
  // Funnel: opened → swipeCard (×N) → revealed → ctaTapped(restyle|skip).

  static Future<void> swipeDeckOpened({
    String? roomType,
    int? deckSize,
  }) =>
      log('swipe_deck_opened', {
        if (roomType != null) 'room_type': roomType,
        if (deckSize != null) 'deck_size': deckSize,
      });

  static Future<void> swipeCard({
    required String projectId,
    required bool liked,
    required int index,
  }) =>
      log('swipe_card', {
        'project_id': projectId,
        'liked': liked,
        'index': index,
      });

  static Future<void> swipeRevealed({
    required int liked,
    required int total,
    required List<String> topTags,
  }) =>
      log('swipe_revealed', {
        'liked': liked,
        'total': total,
        'top_tags': topTags,
      });

  static Future<void> swipeCtaTapped({required String action}) =>
      log('swipe_cta_tapped', {'action': action});
}
