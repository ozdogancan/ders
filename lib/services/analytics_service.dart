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
}
