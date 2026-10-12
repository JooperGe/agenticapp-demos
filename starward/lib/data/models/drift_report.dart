import '../../core/drift.dart';
import '../../core/vec3.dart';

/// What a drift report is about.
enum DriftReportKind {
  /// A voyage that ran out of fuel. The window is the *powered* leg — that is
  /// the part that just happened, and the part the player wants named.
  fuelOut,

  /// A stretch of coasting, either recomputed after the game was closed or
  /// asked for from the coasting screen.
  drift,
}

DriftReportKind driftReportKindFromName(String name) =>
    DriftReportKind.values.firstWhere(
      (k) => k.name == name,
      orElse: () => DriftReportKind.drift,
    );

/// What happened during one window of a ship's travels.
///
/// One class for both kinds: they differ only in which window they describe,
/// and the numbers a player cares about — how long, how far, where to, what it
/// went past — are the same numbers either way.
class DriftReport {
  const DriftReport({
    required this.kind,
    required this.from,
    required this.to,
    required this.elapsed,
    required this.distanceLy,
    required this.fromPos,
    required this.toPos,
    required this.passedCount,
    required this.nearest,
    required this.hitBoundary,
  });

  final DriftReportKind kind;
  final DateTime from;
  final DateTime to;
  final Duration elapsed;

  /// Distance actually flown, arc length included — not the straight-line gap
  /// between [fromPos] and [toPos].
  final double distanceLy;

  final Vec3 fromPos;
  final Vec3 toPos;

  /// Distinct systems that came within the pass radius during the window.
  final int passedCount;

  /// The closest few, ascending by distance, for naming.
  final List<PassedSystem> nearest;

  /// Whether the window includes the ship reaching and sliding along the shell.
  final bool hitBoundary;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind.name,
        'from': from.millisecondsSinceEpoch,
        'to': to.millisecondsSinceEpoch,
        'elapsedMs': elapsed.inMilliseconds,
        'distanceLy': distanceLy,
        'fromX': fromPos.x,
        'fromY': fromPos.y,
        'fromZ': fromPos.z,
        'toX': toPos.x,
        'toY': toPos.y,
        'toZ': toPos.z,
        'passedCount': passedCount,
        'nearest': nearest
            .map((p) => <String, dynamic>{
                  'hygId': p.hygId,
                  'distanceLy': p.distanceLy,
                  'seconds': p.seconds,
                })
            .toList(),
        'hitBoundary': hitBoundary,
      };

  factory DriftReport.fromJson(Map<String, dynamic> json) => DriftReport(
        kind: driftReportKindFromName(json['kind'] as String),
        from: DateTime.fromMillisecondsSinceEpoch(json['from'] as int),
        to: DateTime.fromMillisecondsSinceEpoch(json['to'] as int),
        elapsed: Duration(milliseconds: json['elapsedMs'] as int),
        distanceLy: (json['distanceLy'] as num).toDouble(),
        fromPos: Vec3(
          (json['fromX'] as num).toDouble(),
          (json['fromY'] as num).toDouble(),
          (json['fromZ'] as num).toDouble(),
        ),
        toPos: Vec3(
          (json['toX'] as num).toDouble(),
          (json['toY'] as num).toDouble(),
          (json['toZ'] as num).toDouble(),
        ),
        passedCount: json['passedCount'] as int,
        nearest: (json['nearest'] as List<dynamic>)
            .map((e) => e as Map<String, dynamic>)
            .map((e) => PassedSystem(
                  hygId: e['hygId'] as int,
                  distanceLy: (e['distanceLy'] as num).toDouble(),
                  seconds: (e['seconds'] as num).toDouble(),
                ))
            .toList(),
        hitBoundary: json['hitBoundary'] as bool,
      );
}
