import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/drift.dart';
import 'package:starward/core/vec3.dart';

void expectVec(Vec3 actual, Vec3 expected, {double tol = 0.01}) {
  expect(actual.x, closeTo(expected.x, tol));
  expect(actual.y, closeTo(expected.y, tol));
  expect(actual.z, closeTo(expected.z, tol));
}

void main() {
  group('driftPositionAt', () {
    test('a parked ship never moves, however long it waits', () {
      const start = Vec3(10, 20, 30);
      final p = driftPositionAt(
        start: start,
        velocity: const Vec3(0, 0, 0),
        elapsedSeconds: 1e6,
        bound: 100,
      );
      expectVec(p, start);
    });

    test('inside the shell it just flies straight', () {
      final p = driftPositionAt(
        start: const Vec3(0, 0, 0),
        velocity: const Vec3(1, 0, 0),
        elapsedSeconds: 10,
        bound: 100,
      );
      expectVec(p, const Vec3(10, 0, 0));
    });

    test('it reaches the shell at the right moment and then slides', () {
      // From (50,0,0) heading +Y at 1 ly/s inside a 100 ly sphere: the shell is
      // hit when 50² + s² = 100², i.e. s = sqrt(7500) = 86.6025 s.
      const start = Vec3(50, 0, 0);
      const v = Vec3(0, 1, 0);

      final justBefore = driftPositionAt(
          start: start, velocity: v, elapsedSeconds: 86.6025, bound: 100);
      expectVec(justBefore, const Vec3(50, 86.6025, 0));

      // 13.3975 s later it has slid along the great circle, still on the shell.
      final after = driftPositionAt(
          start: start, velocity: v, elapsedSeconds: 100, bound: 100);
      expect(after.length, closeTo(100, 0.001));
      expectVec(after, const Vec3(44.0904, 89.7552, 0));
    });

    test('lapping the shell stays on it', () {
      // Two full laps' worth of arc after the impact.
      final p = driftPositionAt(
        start: const Vec3(50, 0, 0),
        velocity: const Vec3(0, 1, 0),
        elapsedSeconds: 86.6025 + 2 * 2 * math.pi * 100 / 0.5,
        bound: 100,
      );
      expect(p.length, closeTo(100, 0.001));
      // Back where it hit, having gone all the way round twice.
      expectVec(p, const Vec3(50, 86.6025, 0));
    });

    test('a purely radial impact sticks to one point on the shell', () {
      // Headed straight out from the centre: once it touches the shell the
      // tangential component is zero, so it stops there rather than sliding.
      // Degenerate, but correct — pinned so nobody "fixes" it later.
      final p = driftPositionAt(
        start: const Vec3(50, 0, 0),
        velocity: const Vec3(1, 0, 0),
        elapsedSeconds: 200,
        bound: 100,
      );
      expectVec(p, const Vec3(100, 0, 0));
    });

    test('a ship that starts outside the shell is never teleported inward', () {
      // bound is expected to be max(universeRadius, |start|) at the call site;
      // even handed a smaller one, the ship keeps its own radius.
      final p = driftPositionAt(
        start: const Vec3(0, 0, 300),
        velocity: const Vec3(1, 0, 0),
        elapsedSeconds: 100,
        bound: 100,
      );
      expect(p.length, closeTo(300, 0.001));
      // Radius 300, tangential speed 1 ly/s, 100 s of arc → θ = 100/300 rad,
      // so p = 300·(sin θ, 0, cos θ) = (98.158, 0, 283.487).
      expectVec(p, const Vec3(98.1584, 0, 283.4871));
    });
  });
}
