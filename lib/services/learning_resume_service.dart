import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LearningResumeSnapshot {
  const LearningResumeSnapshot({
    required this.examName,
    required this.subjectName,
    required this.journeyId,
    required this.journeyName,
    required this.stageName,
    required this.progressPercent,
    required this.earnedXp,
  });

  final String examName;
  final String subjectName;
  final String journeyId;
  final String journeyName;
  final String stageName;
  final int progressPercent;
  final int earnedXp;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'examName': examName,
    'subjectName': subjectName,
    'journeyId': journeyId,
    'journeyName': journeyName,
    'stageName': stageName,
    'progressPercent': progressPercent,
    'earnedXp': earnedXp,
  };

  factory LearningResumeSnapshot.fromJson(Map<String, dynamic> json) {
    return LearningResumeSnapshot(
      examName: json['examName'] as String? ?? '',
      subjectName: json['subjectName'] as String? ?? '',
      journeyId: json['journeyId'] as String? ?? '',
      journeyName: json['journeyName'] as String? ?? '',
      stageName: json['stageName'] as String? ?? '',
      progressPercent: json['progressPercent'] as int? ?? 0,
      earnedXp: json['earnedXp'] as int? ?? 0,
    );
  }
}

class LearningResumeService {
  static const String _key = 'learning_resume_v1';

  Future<void> save(LearningResumeSnapshot snapshot) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(snapshot.toJson()));
  }

  Future<LearningResumeSnapshot?> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final Map<String, dynamic> json =
          jsonDecode(raw) as Map<String, dynamic>;
      return LearningResumeSnapshot.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
