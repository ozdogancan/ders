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

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  SupabaseClient get _sb => Supabase.instance.client;

  /// Call once at app start
  void init({String platform = 'web', String appVersion = '1.0.0'}) {
    _sessionId = const Uuid().v4();
    _platform = platform;
    _appVersion = appVersion;
  }

  /// Start a new session (call on app resume / fresh open)
  void newSession() {
    _sessionId = const Uuid().v4();
  }

  /// Log an event
  static Future<void> log(String eventName, [Map<String, dynamic>? data]) async {
    return instance._log(eventName, data);
  }

  Future<void> _log(String eventName, Map<String, dynamic>? data) async {
    try {
      await _sb.from('analytics_events').insert({
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
  static Future<void> questionSubjectDetected(String subject, bool changedByUser) =>
      log('question_subject_detected', {'subject': subject, 'changed_by_user': changedByUser});
  static Future<void> questionSubmitted(String questionId, String subject) =>
      log('question_submitted', {'question_id': questionId, 'subject': subject});
  static Future<void> questionSolved(String questionId, int durationSeconds, String subject) =>
      log('question_solved', {'question_id': questionId, 'duration_seconds': durationSeconds, 'subject': subject});
  static Future<void> questionSolveError(String questionId) =>
      log('question_solve_error', {'question_id': questionId});
  static Future<void> questionDeleted(String questionId) =>
      log('question_deleted', {'question_id': questionId});

  // — Chat —
  static Future<void> chatOpened(String questionId, String subject) =>
      log('chat_opened', {'question_id': questionId, 'subject': subject});
  static Future<void> chatMessageSent(String questionId, {bool isPreset = false, bool isCoach = false}) =>
      log('chat_message_sent', {'question_id': questionId, 'is_preset': isPreset, 'is_coach': isCoach});
  static Future<void> coachModeStarted(String questionId) =>
      log('coach_mode_started', {'question_id': questionId});
  static Future<void> solutionRated(String questionId, int rating, bool hasFeedback) =>
      log('solution_rated', {'question_id': questionId, 'rating': rating, 'has_feedback': hasFeedback});

  // — Credits —
  static Future<void> creditSpent(String source, int remaining) =>
      log('credit_spent', {'source': source, 'remaining_credits': remaining});
  static Future<void> creditZeroReached() => log('credit_zero_reached');
  static Future<void> purchaseScreenOpened(String trigger) =>
      log('purchase_screen_opened', {'trigger': trigger});
  static Future<void> purchaseCompleted(String productId, int credits) =>
      log('purchase_completed', {'product_id': productId, 'credits_received': credits});

  // — Navigation —
  static Future<void> screenViewed(String screenName) =>
      log('screen_viewed', {'screen_name': screenName});
  static Future<void> searchPerformed(String query, int resultsCount, String screen) =>
      log('search_performed', {'query': query, 'results_count': resultsCount, 'screen': screen});
  static Future<void> filterUsed(String filterType, String value, String screen) =>
      log('filter_used', {'filter_type': filterType, 'value': value, 'screen': screen});

  // — Profile —
  static Future<void> profileUpdated(List<String> fields) =>
      log('profile_updated', {'fields_changed': fields});
  static Future<void> profilePhotoChanged() => log('profile_photo_changed');
}
