import 'dart:math' as math;

import 'vec3.dart';

/// Constant-velocity drift through a universe that is bounded but edgeless.
///
/// A coasting ship flies in a straight line until it meets the shell of radius
/// [bound], then slides along that shell on a great circle. It therefore never
/// reaches anywhere emptier than the shell — which is the whole point: an
/// unconstrained drift ends up in a void with nothing left to visit.
///
/// Thin wrapper over [DriftPath]; kept because "where is the ship now" is the
/// question callers ask most, and it reads better without the object.
Vec3 driftPositionAt({
  required Vec3 start,
  required Vec3 velocity, // light-years per second
  required double elapsedSeconds,
  required double bound,
}) =>
    DriftPath(start: start, velocity: velocity, bound: bound)
        .positionAt(elapsedSeconds);

/// A coasting ship's trajectory: a straight leg out to the shell, then a
/// great-circle slide along it.
///
/// Both legs are closed-form, which is what lets the game ask "where was the
/// ship at time t" and "which systems did it pass" without ever stepping
/// through the motion. Nothing is accumulated: the path is a pure function of
/// its three inputs, so a week offline costs one evaluation.
class DriftPath {
  DriftPath({
    required this.start,
    required this.velocity,
    required double bound,
  })  : _speed = velocity.length,
        // A ship that starts outside the shell keeps its own radius rather
        // than being teleported inward to `bound` — it simply stops widening.
        shellRadius = math.max(bound, start.length) {
    if (_speed == 0) {
      hitSeconds = 0;
      _tangentialSpeed = 0;
      _normal = const Vec3(0, 0, 0);
      _tangent = const Vec3(0, 0, 0);
      return;
    }
    final startLen = start.length;
    if (startLen >= bound) {
      // Already on (or beyond) the shell: there is no straight leg.
      hitSeconds = 0;
    } else {
      // |start + v·s|² = bound²  →  a·s² + b·s + c = 0, with c < 0 here (the
      // ship starts inside), so the positive root is always the exit.
      final a = _speed * _speed;
      final b = 2 * start.dot(velocity);
      final c = startLen * startLen - bound * bound;
      final disc = b * b - 4 * a * c;
      hitSeconds = disc <= 0 ? 0 : (-b + math.sqrt(disc)) / (2 * a);
    }
    final hit = start + velocity * hitSeconds;
    final n = hit.normalized;
    _normal = n;
    final tangential = velocity - n * velocity.dot(n);
    _tangentialSpeed = tangential.length;
    _tangent =
        _tangentialSpeed < 1e-12 ? const Vec3(0, 0, 0) : tangential.normalized;
  }

  final Vec3 start;
  final Vec3 velocity;

  /// The radius the ship is actually confined to: `max(bound, |start|)`.
  final double shellRadius;

  /// Seconds from the start of the drift until the shell is met. Zero when the
  /// ship already begins on the shell; the straight leg is empty then.
  late final double hitSeconds;

  final double _speed;
  late final double _tangentialSpeed;
  late final Vec3 _normal;
  late final Vec3 _tangent;

  /// Where the ship is [elapsedSeconds] into the drift.
  Vec3 positionAt(double elapsedSeconds) {
    if (elapsedSeconds <= 0 || _speed == 0) return start;
    if (elapsedSeconds <= hitSeconds) return start + velocity * elapsedSeconds;
    return _onShell(elapsedSeconds - hitSeconds);
  }

  /// Position after [seconds] of sliding along the shell.
  Vec3 _onShell(double seconds) {
    final hit = start + velocity * hitSeconds;
    // Purely radial impact — no tangential component to slide with, so the
    // ship sits at this point. Degenerate and intentional; see the test.
    if (_tangentialSpeed < 1e-12) return hit;
    final theta = _tangentialSpeed * seconds / shellRadius;
    return (_normal * math.cos(theta) + _tangent * math.sin(theta)) *
        shellRadius;
  }

  /// How close [star] comes to the path between [fromSeconds] and
  /// [upToSeconds] of it, and when.
  ///
  /// The window matters because reports cover a slice of a drift rather than
  /// the whole thing: a long coast that laps the shell would otherwise report
  /// the same system again on every report.
  ///
  /// One evaluation per star — no stepping — which is what makes it affordable
  /// to run over the whole catalogue.
  ClosestApproach closestApproach(
    Vec3 star,
    double upToSeconds, {
    double fromSeconds = 0,
  }) {
    final to = math.max(upToSeconds, 0.0);
    final from = fromSeconds.clamp(0.0, to);
    if (to <= 0 || _speed == 0) {
      return ClosestApproach((star - start).length, 0);
    }

    var bestSeconds = from;
    var bestDistance = double.infinity;

    // --- straight leg: s in [from, min(to, hitSeconds)] ---
    final straightEnd = math.min(to, hitSeconds);
    if (straightEnd > from) {
      final d0 = start - star;
      // |d0 + v·s|² is minimised at s* = -(d0·v)/|v|², clamped to the leg.
      final s = (-d0.dot(velocity) / (_speed * _speed)).clamp(from, straightEnd);
      bestSeconds = s;
      bestDistance = (d0 + velocity * s).length;
    } else {
      bestSeconds = from;
      bestDistance = (star - positionAt(from)).length;
    }

    // --- arc leg: s in (max(from, hitSeconds), to] ---
    if (to > hitSeconds && _tangentialSpeed >= 1e-12) {
      final fromArc = math.max(from, hitSeconds);
      final thetaFrom = _tangentialSpeed * (fromArc - hitSeconds) / shellRadius;
      final thetaTo = _tangentialSpeed * (to - hitSeconds) / shellRadius;
      final wn = star.dot(_normal);
      final wt = star.dot(_tangent);
      if (wn * wn + wt * wt > 0) {
        // The star's bearing in the great circle's plane. The distance to the
        // circle is minimised there, so the answer over a bounded arc is either
        // that bearing or one of the arc's two ends — evaluate both ends and
        // every equivalent bearing that lands inside, take the best.
        final bearing = math.atan2(wt, wn);
        final candidates = <double>[thetaFrom, thetaTo];
        for (var lap = -1; lap <= 2; lap++) {
          final t = bearing + 2 * math.pi * lap;
          if (t > thetaFrom && t < thetaTo) candidates.add(t);
        }
        for (final t in candidates) {
          final p = (_normal * math.cos(t) + _tangent * math.sin(t)) *
              shellRadius;
          final d = (p - star).length;
          if (d < bestDistance) {
            bestDistance = d;
            bestSeconds = hitSeconds + t * shellRadius / _tangentialSpeed;
          }
        }
      }
    }

    return ClosestApproach(bestDistance, bestSeconds);
  }

  /// How far the ship travels between [fromSeconds] and [toSeconds] of the
  /// drift, in light-years.
  ///
  /// Arc length, not the straight-line distance between the two points: on the
  /// shell those differ, and "how far did I fly" means the former.
  double travelledBetween(double fromSeconds, double toSeconds) {
    final to = math.max(toSeconds, 0.0);
    final from = fromSeconds.clamp(0.0, to);
    if (_speed == 0 || to <= from) return 0;
    final straight =
        math.max(math.min(to, hitSeconds) - math.min(from, hitSeconds), 0.0);
    final arc = math.max(to - math.max(from, hitSeconds), 0.0);
    return _speed * straight + _tangentialSpeed * arc;
  }
}

/// How close something came to a [DriftPath], and when.
class ClosestApproach {
  const ClosestApproach(this.distanceLy, this.seconds);

  final double distanceLy;

  /// Seconds from the start of the drift to the closest moment.
  final double seconds;
}

/// A star system a drift passed close to.
class PassedSystem {
  const PassedSystem({
    required this.hygId,
    required this.distanceLy,
    required this.seconds,
  });

  final int hygId;
  final double distanceLy;
  final double seconds;
}

/// What a drift passed.
class PassedSystems {
  const PassedSystems({required this.count, required this.nearest});

  /// Distinct systems that came within the pass radius. A lapping drift counts
  /// each system once no matter how many times it went by, because the distance
  /// used is the closest approach over the whole window.
  final int count;

  /// The closest few, ascending by distance.
  final List<PassedSystem> nearest;

  static const PassedSystems none =
      PassedSystems(count: 0, nearest: <PassedSystem>[]);
}
