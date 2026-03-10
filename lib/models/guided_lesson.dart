class GuidedLesson {
  const GuidedLesson({
    required this.title,
    required this.opening,
    required this.whyItMatters,
    required this.coachSteps,
    required this.challenge,
    required this.checkpoint,
    required this.watchOut,
    required this.celebration,
    required this.nextMove,
  });

  final String title;
  final String opening;
  final String whyItMatters;
  final List<String> coachSteps;
  final String challenge;
  final String checkpoint;
  final String watchOut;
  final String celebration;
  final String nextMove;

  factory GuidedLesson.fromJson(Map<String, dynamic> json) {
    final dynamic rawSteps = json['coach_steps'];
    return GuidedLesson(
      title: (json['title'] as String? ?? '').trim(),
      opening: (json['opening'] as String? ?? '').trim(),
      whyItMatters: (json['why_it_matters'] as String? ?? '').trim(),
      coachSteps: rawSteps is List
          ? rawSteps.whereType<String>().map((e) => e.trim()).toList()
          : const <String>[],
      challenge: (json['challenge'] as String? ?? '').trim(),
      checkpoint: (json['checkpoint'] as String? ?? '').trim(),
      watchOut: (json['watch_out'] as String? ?? '').trim(),
      celebration: (json['celebration'] as String? ?? '').trim(),
      nextMove: (json['next_move'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'title': title,
      'opening': opening,
      'why_it_matters': whyItMatters,
      'coach_steps': coachSteps,
      'challenge': challenge,
      'checkpoint': checkpoint,
      'watch_out': watchOut,
      'celebration': celebration,
      'next_move': nextMove,
    };
  }
}
