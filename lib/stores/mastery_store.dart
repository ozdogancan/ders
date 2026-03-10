import 'dart:typed_data';
import 'package:flutter/material.dart';

enum MasteryLevel { cirak, kalfa, usta }
enum PhaseStatus { locked, active, done }
enum TopicStatus { notStarted, inProgress, completed }

class MasteryPhase {
  MasteryPhase({
    required this.id,
    required this.title,
    required this.description,
    this.status = PhaseStatus.locked,
    this.questionsTotal = 5,
    this.questionsCorrect = 0,
    this.questionsDone = 0,
  });

  final String id;
  final String title;
  final String description;
  PhaseStatus status;
  int questionsTotal;
  int questionsCorrect;
  int questionsDone;

  double get progress => questionsTotal > 0 ? questionsDone / questionsTotal : 0;
}

class MasteryTopic {
  MasteryTopic({
    required this.id,
    required this.title,
    required this.subject,
    required this.teacherName,
    this.level = MasteryLevel.cirak,
    this.imageBytes,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now() {
    phases = [
      MasteryPhase(id: 'discover', title: 'Konuyu Tan\u0131', description: 'Temel kavramlar\u0131 \u00f6\u011fren', status: PhaseStatus.active),
      MasteryPhase(id: 'remember', title: 'Hat\u0131rla', description: 'Temel kurallar\u0131 hat\u0131rla'),
      MasteryPhase(id: 'apply', title: 'Uygula', description: 'Sorular\u0131 \u00e7\u00f6zerek pratik yap'),
      MasteryPhase(id: 'analyze', title: 'Analiz Et', description: 'Neden sorular\u0131yla derinle\u015f'),
      MasteryPhase(id: 'master', title: 'Ustala\u015f', description: 'Zor ve yarat\u0131c\u0131 problemler'),
    ];
  }

  final String id;
  final String title;
  final String subject;
  final String teacherName;
  final DateTime createdAt;
  Uint8List? imageBytes;
  MasteryLevel level;
  late List<MasteryPhase> phases;
  int streak = 0;
  int totalCorrect = 0;
  int totalQuestions = 0;
  int wrongInRow = 0;

  TopicStatus get status {
    if (phases.every((p) => p.status == PhaseStatus.done)) return TopicStatus.completed;
    if (phases.any((p) => p.status != PhaseStatus.locked)) return TopicStatus.inProgress;
    return TopicStatus.notStarted;
  }

  double get overallProgress {
    final total = phases.fold<int>(0, (s, p) => s + p.questionsTotal);
    final done = phases.fold<int>(0, (s, p) => s + p.questionsDone);
    return total > 0 ? done / total : 0;
  }

  int get progressPercent => (overallProgress * 100).round();

  MasteryPhase? get activePhase {
    for (final p in phases) {
      if (p.status == PhaseStatus.active) return p;
    }
    return null;
  }

  String get levelLabel {
    switch (level) {
      case MasteryLevel.cirak: return '\u00c7\u0131rak';
      case MasteryLevel.kalfa: return 'Kalfa';
      case MasteryLevel.usta: return 'Usta';
    }
  }
}

class MasteryStore extends ChangeNotifier {
  MasteryStore._();
  static final MasteryStore instance = MasteryStore._();

  final List<MasteryTopic> _topics = [];
  List<MasteryTopic> get topics => List.unmodifiable(_topics);

  MasteryTopic? getById(String id) {
    for (final t in _topics) {
      if (t.id == id) return t;
    }
    return null;
  }

  MasteryTopic addTopic({
    required String title,
    required String subject,
    required String teacherName,
    Uint8List? imageBytes,
  }) {
    final t = MasteryTopic(
      id: 'm_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      subject: subject,
      teacherName: teacherName,
      imageBytes: imageBytes,
    );
    _topics.insert(0, t);
    notifyListeners();
    return t;
  }

  void removeTopic(String id) {
    _topics.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  /// Skip completed phases based on placement test result.
  /// [skipCount] phases will be marked as done, the next one becomes active.
  void skipToPhase(String topicId, int skipCount) {
    final t = getById(topicId);
    if (t == null) return;

    for (int i = 0; i < t.phases.length; i++) {
      if (i < skipCount) {
        t.phases[i].status = PhaseStatus.done;
        // Mark as if questions were answered correctly
        t.phases[i].questionsDone = t.phases[i].questionsTotal;
        t.phases[i].questionsCorrect = t.phases[i].questionsTotal;
      } else if (i == skipCount) {
        t.phases[i].status = PhaseStatus.active;
      } else {
        t.phases[i].status = PhaseStatus.locked;
      }
    }

    // Update level based on skipped phases
    _updateLevel(t);
    notifyListeners();
  }

  void answerCorrect(String topicId) {
    final t = getById(topicId);
    if (t == null) return;
    final phase = t.activePhase;
    if (phase == null) return;

    phase.questionsCorrect++;
    phase.questionsDone++;
    t.totalCorrect++;
    t.totalQuestions++;
    t.streak++;
    t.wrongInRow = 0;

    // Check phase completion
    if (phase.questionsDone >= phase.questionsTotal) {
      phase.status = PhaseStatus.done;
      _unlockNext(t);
    }

    // Update level
    _updateLevel(t);
    notifyListeners();
  }

  void answerWrong(String topicId) {
    final t = getById(topicId);
    if (t == null) return;
    final phase = t.activePhase;
    if (phase == null) return;

    phase.questionsDone++;
    t.totalQuestions++;
    t.streak = 0;
    t.wrongInRow++;
    notifyListeners();
  }

  void _unlockNext(MasteryTopic t) {
    for (int i = 0; i < t.phases.length - 1; i++) {
      if (t.phases[i].status == PhaseStatus.done && t.phases[i + 1].status == PhaseStatus.locked) {
        t.phases[i + 1].status = PhaseStatus.active;
        break;
      }
    }
  }

  void _updateLevel(MasteryTopic t) {
    final doneCount = t.phases.where((p) => p.status == PhaseStatus.done).length;
    if (doneCount >= 4) {
      t.level = MasteryLevel.usta;
    } else if (doneCount >= 2) {
      t.level = MasteryLevel.kalfa;
    } else {
      t.level = MasteryLevel.cirak;
    }
  }

  // Stats
  int get completedCount => _topics.where((t) => t.status == TopicStatus.completed).length;
  int get avgProgress {
    if (_topics.isEmpty) return 0;
    return (_topics.fold<double>(0, (s, t) => s + t.overallProgress) / _topics.length * 100).round();
  }
}
