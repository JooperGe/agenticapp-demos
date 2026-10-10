/// Status of an in-app training course run.
enum TrainingStatus { notStarted, inProgress, completed }

TrainingStatus trainingStatusFromName(String name) =>
    TrainingStatus.values.firstWhere((s) => s.name == name,
        orElse: () => TrainingStatus.notStarted);

/// A record of a training course attempt. [rewardClaimed] guards against
/// granting energy twice for the same completed session.
class TrainingSession {
  const TrainingSession({
    required this.id,
    required this.courseId,
    required this.startedAt,
    this.completedAt,
    required this.status,
    required this.rewardClaimed,
  });

  final String id;
  final String courseId;
  final DateTime startedAt;
  final DateTime? completedAt;
  final TrainingStatus status;
  final bool rewardClaimed;

  factory TrainingSession.fromJson(Map<String, dynamic> json) =>
      TrainingSession(
        id: json['id'] as String,
        courseId: json['courseId'] as String,
        startedAt:
            DateTime.fromMillisecondsSinceEpoch(json['startedAt'] as int),
        completedAt: json['completedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(json['completedAt'] as int),
        status: trainingStatusFromName(json['status'] as String),
        rewardClaimed: json['rewardClaimed'] as bool,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'courseId': courseId,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'completedAt': completedAt?.millisecondsSinceEpoch,
        'status': status.name,
        'rewardClaimed': rewardClaimed,
      };
}

/// Static definition of a training course. Rewards are fixed per course.
class TrainingCourse {
  const TrainingCourse({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.durationLabel,
    required this.steps,
    required this.reward,
    required this.seedColor,
  });

  final String id;
  final String name;
  final String subtitle;
  final String durationLabel;

  /// Ordered guided steps the player taps through to complete the course.
  final List<String> steps;
  final int reward;
  final int seedColor;
}
