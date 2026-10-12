import 'dart:math' as math;

import 'vec3.dart';

/// Constant-velocity drift through a universe that is bounded but edgeless.
///
/// A coasting ship flies in a straight line until it meets the shell of radius
/// [bound], then slides along that shell on a great circle. It therefore never
/// reaches anywhere emptier than the shell — which is the whole point: an
/// unconstrained drift ends up in a void with nothing left to visit.
///
/// Both legs are closed-form. The position after a week offline costs exactly
/// one evaluation, and there is no stored state to drift out of sync: the
/// answer is always just a function of (start, velocity, elapsed, bound).
Vec3 driftPositionAt({
  required Vec3 start,
  required Vec3 velocity, // light-years per second
  required double elapsedSeconds,
  required double bound,
}) {
  if (elapsedSeconds <= 0) return start;

  final a = velocity.dot(velocity);
  // Parked. This is what the game's deep-space hover has always been, so the
  // zero-velocity case reproduces the old static behaviour exactly.
  if (a == 0) return start;

  final startLen = start.length;

  // Already on (or beyond) the shell: slide from here, on the radius the ship
  // actually has. Never teleport it inward to `bound` — a player who spawned
  // outside the shell keeps their own radius, they just stop widening it.
  if (startLen >= bound) {
    return _slide(start, velocity, elapsedSeconds, startLen);
  }

  // |start + v·s|² = bound²  →  a·s² + b·s + c = 0
  final b = 2 * start.dot(velocity);
  final c = startLen * startLen - bound * bound;
  final disc = b * b - 4 * a * c;
  // c < 0 here (the ship starts inside), so disc > 0 always; this is belt and
  // braces against a NaN from a degenerate caller.
  if (disc <= 0) return start;
  final hitSeconds = (-b + math.sqrt(disc)) / (2 * a);

  if (elapsedSeconds <= hitSeconds) {
    return start + velocity * elapsedSeconds;
  }
  return _slide(
    start + velocity * hitSeconds,
    velocity,
    elapsedSeconds - hitSeconds,
    bound,
  );
}

/// Moves [point] along the great circle of radius [radius] defined by the
/// tangential part of [velocity], sweeping for [seconds].
Vec3 _slide(Vec3 point, Vec3 velocity, double seconds, double radius) {
  final n = point.normalized;
  final tangential = velocity - n * velocity.dot(n);
  final speed = tangential.length;
  // Purely radial impact — no tangential component to slide with, so the ship
  // sits at this point on the shell. Degenerate and intentional; see the test.
  if (speed < 1e-12) return point;
  final tangent = tangential.normalized;
  final theta = speed * seconds / radius;
  return (n * math.cos(theta) + tangent * math.sin(theta)) * radius;
}
