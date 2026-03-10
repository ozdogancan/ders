import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart' hide User;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../services/supabase_storage_service.dart';

enum QStatus { solving, solved, error, waitingAnswer }

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
  Uint8List imageBytes;
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

  bool _loaded = false;
  bool get loaded => _loaded;

  String? get _uid {
    final firebaseUid = FirebaseAuth.instance.currentUser?.uid;
    return firebaseUid;
  }

  SupabaseClient get _sb => Supabase.instance.client;

  LocalQuestion? getById(String id) {
    for (final q in _questions) {
      if (q.id == id) return q;
    }
    return null;
  }

  Future<void> loadFromSupabase({bool force = false}) async {
    if (_loaded && !force) return;
    _loaded = false;
    final uid = _uid;
    if (uid == null) {
      debugPrint('loadFromSupabase: No user, skipping.');
      _loaded = true;
      notifyListeners();
      return;
    }
    _questions.clear();

    try {
      final rows = await _sb
          .from('questions')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false);

      for (final row in rows) {
        final id = row['id'] as String;
        if (getById(id) != null) continue;

        final imageUrl = row['image_url'] as String?;
        Uint8List imageBytes = Uint8List(0);

        if (imageUrl != null && imageUrl.isNotEmpty) {
          try {
            final response = await http.get(Uri.parse(imageUrl));
            if (response.statusCode == 200) {
              imageBytes = response.bodyBytes;
            }
          } catch (e) {
            debugPrint('Image download failed for $id: $e');
          }
        }

        final statusStr = row['status'] as String? ?? 'solving';
        QStatus status;
        switch (statusStr) {
          case 'solved':
            status = QStatus.solved;
            break;
          case 'error':
            status = QStatus.error;
            break;
          default:
            status = QStatus.solving;
        }

        final aiAnswer = row['ai_answer'] as String?;
        StructuredAnswer? structured;
        final structuredJson = row['structured_answer'];
        if (structuredJson != null && structuredJson is Map<String, dynamic>) {
          try {
            structured = StructuredAnswer.fromJson(structuredJson);
          } catch (_) {}
        }
        if (structured == null && aiAnswer != null) {
          structured = StructuredAnswer.tryParse(aiAnswer);
        }

        final q = LocalQuestion(
          id: id,
          imageBytes: imageBytes,
          subject: row['subject'] as String? ?? 'Matematik',
          createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
          status: status,
          answer: aiAnswer,
          structuredAnswer: structured,
          imageUrl: imageUrl,
        );

        _questions.add(q);
      }

      await _loadChatsFromDb();
      await _loadRatingsFromDb();

      _loaded = true;
      notifyListeners();
      debugPrint('loadFromSupabase: ${_questions.length} questions loaded.');
    } catch (e) {
      debugPrint('loadFromSupabase error: $e');
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> _loadChatsFromDb() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final rows = await _sb
          .from('chat_messages')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: true);

      for (final row in rows) {
        final qId = row['question_id'] as String?;
        if (qId == null) continue;
        final q = getById(qId);
        if (q == null) continue;
        final msg = ChatMsg(
          role: row['role'] as String? ?? 'ai',
          text: row['content'] as String? ?? '',
          time: DateTime.tryParse(row['created_at'] as String? ?? ''),
        );
        q.chatMessages = [...q.chatMessages, msg];
      }
    } catch (e) {
      debugPrint('Load chats error: $e');
    }
  }

  Future<void> _loadRatingsFromDb() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final rows = await _sb
          .from('question_ratings')
          .select()
          .eq('user_id', uid);

      for (final row in rows) {
        final qId = row['question_id'] as String?;
        if (qId == null) continue;
        final q = getById(qId);
        if (q == null) continue;
        q.rating = row['rating'] as int?;
      }
    } catch (e) {
      debugPrint('Load ratings error: $e');
    }
  }

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
    _uploadAndSave(q, imageBytes);
    return q;
  }

  Future<void> _uploadAndSave(LocalQuestion q, Uint8List imageBytes) async {
    final uid = _uid;
    if (uid == null) {
      await _saveQuestionToDb(q);
      return;
    }
    try {
      final storageService = SupabaseStorageService();
      final url = await storageService.uploadQuestionImageBytes(
        bytes: imageBytes,
        userId: uid,
      );
      q.imageUrl = url;
      notifyListeners();
      await _saveQuestionToDb(q);
      debugPrint('Question saved with image: $url');
    } catch (e) {
      debugPrint('Upload failed, saving without image: $e');
      await _saveQuestionToDb(q);
    }
  }

  void solve(String id, String answer) {
    final q = getById(id);
    if (q == null) return;
    q.status = QStatus.solved;
    q.answer = answer;
    q.structuredAnswer = StructuredAnswer.tryParse(answer);
    q.chatMessages = [ChatMsg(role: 'ai', text: answer)];
    notifyListeners();
    _updateQuestionInDb(q);
    _saveChatToDb(q.id, 'ai', answer, false);
  }

  void remove(String id) {
    _questions.removeWhere((q) => q.id == id);
    notifyListeners();
    _deleteQuestionFromDb(id);
  }

  void setWaitingAnswer(String id) {
    final q = getById(id);
    if (q == null) return;
    q.status = QStatus.waitingAnswer;
    notifyListeners();
  }

  void setError(String id) {
    final q = getById(id);
    if (q == null) return;
    q.status = QStatus.error;
    q.answer = null;
    q.chatMessages = [ChatMsg(role: 'ai', text: 'Cozum sirasinda bir hata olustu. Harcanan kredin hesabina iade edildi. Tekrar denemek icin yeni soru gonderebilirsin.')];
    notifyListeners();
    _updateQuestionStatusInDb(id, 'error');
  }

  void addChat(String id, ChatMsg msg) {
    final q = getById(id);
    if (q == null) return;
    q.chatMessages = [...q.chatMessages, msg];
    notifyListeners();
    _saveChatToDb(id, msg.role, msg.text, false);
  }

  void rate(String id, int stars) {
    final q = getById(id);
    if (q == null) return;
    q.rating = stars;
    notifyListeners();
    _saveRatingToDb(id, stars, null);
  }

  void rateWithFeedback(String id, int stars, String feedback) {
    final q = getById(id);
    if (q == null) return;
    q.rating = stars;
    notifyListeners();
    _saveRatingToDb(id, stars, feedback);
  }

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
  if (s.contains('fiz')) return 'Asli Hoca';
  if (s.contains('kim')) return 'Kaan Hoca';
  if (s.contains('bio')) return 'Mert Hoca';
  if (s.contains('ede') || s.contains('turk')) return 'Selin Hoca';
  if (s.contains('tar')) return 'Elif Hoca';
  if (s.contains('cog')) return 'Ayse Hoca';
  if (s.contains('fel')) return 'Defne Hoca';
  if (s.contains('ing')) return 'Cem Hoca';
  return 'Kaan Hoca';
}





