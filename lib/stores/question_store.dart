import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart' hide User;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

enum QStatus { solving, solved, error }

class SolutionStep {
  SolutionStep({required this.explanation, this.formula, this.isAnswer = false});
  final String explanation;
  final String? formula;
  final bool isAnswer;

  factory SolutionStep.fromJson(Map<String, dynamic> json) {
    return SolutionStep(
      explanation: (json['explanation'] as String? ?? '').trim(),
      formula: (json['formula'] as String?)?.trim(),
      isAnswer: json['is_answer'] as bool? ?? false,
    );
  }
}

class StructuredAnswer {
  StructuredAnswer({required this.summary, required this.steps, required this.finalAnswer, this.tip});
  final String summary;
  final List<SolutionStep> steps;
  final String finalAnswer;
  final String? tip;

  factory StructuredAnswer.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'] as List<dynamic>? ?? [];
    return StructuredAnswer(
      summary: (json['summary'] as String? ?? '').trim(),
      steps: rawSteps.map((s) => SolutionStep.fromJson(s as Map<String, dynamic>)).toList(),
      finalAnswer: (json['final_answer'] as String? ?? '').trim(),
      tip: (json['tip'] as String?)?.trim(),
    );
  }

  static StructuredAnswer? tryParse(String raw) {
    try {
      final cleaned = raw
          .replaceAll(RegExp(r'^```json\s*', caseSensitive: false), '')
          .replaceAll(RegExp(r'^```\s*', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s*```$'), '')
          .trim();
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(cleaned);
      if (match == null) return null;
      final decoded = jsonDecode(match.group(0)!) as Map<String, dynamic>;
      return StructuredAnswer.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}

class LocalQuestion {
  LocalQuestion({
    required this.id,
    required this.imageBytes,
    required this.subject,
    required this.createdAt,
    this.status = QStatus.solving,
    this.answer,
    this.structuredAnswer,
    this.chatMessages = const [],
    this.rating,
    this.imageUrl,
  });

  final String id;
  final Uint8List imageBytes;
  final String subject;
  final DateTime createdAt;
  QStatus status;
  String? answer;
  StructuredAnswer? structuredAnswer;
  List<ChatMsg> chatMessages;
  int? rating;
  String? imageUrl;
}

class ChatMsg {
  ChatMsg({required this.role, required this.text, DateTime? time})
      : time = time ?? DateTime.now();
  final String role;
  final String text;
  final DateTime time;
}

class QuestionStore extends ChangeNotifier {
  QuestionStore._();
  static final QuestionStore instance = QuestionStore._();

  final List<LocalQuestion> _questions = [];
  List<LocalQuestion> get questions => List.unmodifiable(_questions);

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  SupabaseClient get _sb => Supabase.instance.client;

  LocalQuestion? getById(String id) {
    for (final q in _questions) {
      if (q.id == id) return q;
    }
    return null;
  }

  /// Add a new question (local + Supabase)
  LocalQuestion add({required Uint8List imageBytes, required String subject, String? imageUrl}) {
    final q = LocalQuestion(
      id: 'q_${DateTime.now().millisecondsSinceEpoch}',
      imageBytes: imageBytes,
      subject: subject,
      createdAt: DateTime.now(),
      imageUrl: imageUrl,
    );
    _questions.insert(0, q);
    notifyListeners();

    // Async save to Supabase
    _saveQuestionToDb(q);

    return q;
  }

  /// Mark question as solved
  void solve(String id, String answer) {
    final q = getById(id);
    if (q == null) return;
    q.status = QStatus.solved;
    q.answer = answer;
    q.structuredAnswer = StructuredAnswer.tryParse(answer);
    q.chatMessages = [ChatMsg(role: 'ai', text: answer)];
    notifyListeners();

    // Async update Supabase
    _updateQuestionInDb(q);
    // Save the first AI chat message
    _saveChatToDb(q.id, 'ai', answer, false);
  }

  /// Remove question
  void remove(String id) {
    _questions.removeWhere((q) => q.id == id);
    notifyListeners();

    // Async delete from Supabase
    _deleteQuestionFromDb(id);
  }

  /// Set error status
  void setError(String id) {
    final q = getById(id);
    if (q == null) return;
    q.status = QStatus.error;
    notifyListeners();

    _updateQuestionStatusInDb(id, 'error');
  }

  /// Add chat message
  void addChat(String id, ChatMsg msg) {
    final q = getById(id);
    if (q == null) return;
    q.chatMessages = [...q.chatMessages, msg];
    notifyListeners();

    // Async save chat to Supabase
    _saveChatToDb(id, msg.role, msg.text, false);
  }

  /// Rate a question
  void rate(String id, int stars) {
    final q = getById(id);
    if (q == null) return;
    q.rating = stars;
    notifyListeners();

    // Async save rating to Supabase
    _saveRatingToDb(id, stars, null);
  }

  /// Rate with feedback
  void rateWithFeedback(String id, int stars, String feedback) {
    final q = getById(id);
    if (q == null) return;
    q.rating = stars;
    notifyListeners();

    _saveRatingToDb(id, stars, feedback);
  }

  // ═══════════════════════════════════════════
  // SUPABASE DB OPERATIONS
  // ═══════════════════════════════════════════

  Future<void> _saveQuestionToDb(LocalQuestion q) async {
    if (_uid == null) return;
    try {
      await _sb.from('questions').insert({
        'id': q.id,
        'user_id': _uid!,
        'subject': q.subject,
        'image_url': q.imageUrl ?? '',
        'status': 'solving',
        'created_at': q.createdAt.toIso8601String(),
      });
    } catch (e) {
      debugPrint('Save question error: $e');
    }
  }

  Future<void> _updateQuestionInDb(LocalQuestion q) async {
    if (_uid == null) return;
    try {
      final structured = q.structuredAnswer;
      Map<String, dynamic>? structuredJson;
      if (structured != null) {
        structuredJson = {
          'summary': structured.summary,
          'steps': structured.steps.map((s) => {
            'explanation': s.explanation,
            'formula': s.formula,
          }).toList(),
          'final_answer': structured.finalAnswer,
          'tip': structured.tip,
        };
      }

      await _sb.from('questions').update({
        'status': 'solved',
        'ai_answer': q.answer,
        'structured_answer': structuredJson,
        'solved_at': DateTime.now().toIso8601String(),
        'solve_duration_seconds': DateTime.now().difference(q.createdAt).inSeconds,
      }).eq('id', q.id);
    } catch (e) {
      debugPrint('Update question error: $e');
    }
  }

  Future<void> _updateQuestionStatusInDb(String id, String status) async {
    if (_uid == null) return;
    try {
      await _sb.from('questions').update({'status': status}).eq('id', id);
    } catch (e) {
      debugPrint('Update status error: $e');
    }
  }

  Future<void> _deleteQuestionFromDb(String id) async {
    if (_uid == null) return;
    try {
      await _sb.from('questions').delete().eq('id', id);
    } catch (e) {
      debugPrint('Delete question error: $e');
    }
  }

  Future<void> _saveChatToDb(String questionId, String role, String content, bool isCoach) async {
    if (_uid == null) return;
    try {
      await _sb.from('chat_messages').insert({
        'question_id': questionId,
        'user_id': _uid!,
        'role': role,
        'content': content,
        'is_coach_mode': isCoach,
      });
    } catch (e) {
      debugPrint('Save chat error: $e');
    }
  }

  Future<void> _saveRatingToDb(String questionId, int stars, String? feedback) async {
    if (_uid == null) return;
    try {
      await _sb.from('question_ratings').insert({
        'question_id': questionId,
        'user_id': _uid!,
        'rating': stars,
        'feedback_text': feedback,
      });
    } catch (e) {
      debugPrint('Save rating error: $e');
    }
  }
}

String tutorAssetForSubject(String subject) {
  final s = subject.toLowerCase();
  if (s.contains('mat') || s.contains('geo')) return 'assets/tutors/Matematik Man.png';
  if (s.contains('fiz')) return 'assets/tutors/Fizik Woman.png';
  if (s.contains('kim')) return 'assets/tutors/Kimya Woman.png';
  if (s.contains('bio') || s.contains('biyo')) return 'assets/tutors/Biyoloji Man.png';
  if (s.contains('ede') || s.contains('turk')) return 'assets/tutors/Edebiyat Woman.png';
  if (s.contains('tar')) return 'assets/tutors/Tarih Woman.png';
  if (s.contains('cog')) return 'assets/tutors/Geometri Man.png';
  if (s.contains('fel')) return 'assets/tutors/Felsefe Woman.png';
  return 'assets/tutors/Matematik Man.png';
}

String tutorNameForSubject(String subject) {
  final s = subject.toLowerCase();
  if (s.contains('mat')) return 'Kaan Hoca';
  if (s.contains('geo')) return 'Emre Hoca';
  if (s.contains('fiz')) return 'Asl\u0131 Hoca';
  if (s.contains('kim')) return 'Kaan Hoca';
  if (s.contains('bio')) return 'Mert Hoca';
  if (s.contains('ede') || s.contains('turk')) return 'Selin Hoca';
  if (s.contains('tar')) return 'Elif Hoca';
  if (s.contains('cog')) return 'Ay\u015fe Hoca';
  if (s.contains('fel')) return 'Defne Hoca';
  if (s.contains('ing')) return 'Cem Hoca';
  return 'Kaan Hoca';
}
