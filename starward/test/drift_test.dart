import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/drift.dart';
import 'package:starward/core/vec3.dart';
import 'package:starward/data/hyg_catalog.dart';
import 'package:starward/data/universe.dart';

void expectVec(Vec3 actual, Vec3 expected, {double tol = 0.01}) {
  expect(actual.x, closeTo(expected.x, tol));
  expect(actual.y, closeTo(expected.y, tol));
  expect(actual.z, closeTo(expected.z, tol));
}

/// A handful of stars at hand-picked positions — no catalogue, no assets, so
/// every distance below is exact.
HygStars _synthetic(List<Vec3> positions) {
  final n = positions.length;
  final xyz = Float32List(n * 3);
  final ids = Int32List(n);
  for (var i = 0; i < n; i++) {
    xyz[i * 3] = positions[i].x;
    xyz[i * 3 + 1] = positions[i].y;
    xyz[i * 3 + 2] = positions[i].z;
    ids[i] = 1000 + i;
  }
  return HygStars(
    count: n,
    starId: ids,
    xyz: xyz,
    mag: Float32List(n),
    color: Int32List(n),
    named: const <String, HygNamed>{},
    indexById: <int, int>{for (var i = 0; i < n; i++) 1000 + i: i},
  );
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

  group('DriftPath', () {
    test('stays on the leg before the shell and on the shell after', () {
      final path = DriftPath(
        start: const Vec3(50, 0, 0),
        velocity: const Vec3(0, 1, 0),
        bound: 100,
      );
      expect(path.hitSeconds, closeTo(86.6025, 0.0001));
      expect(path.shellRadius, 100);
      // Before the shell hit the ship is still on the straight leg.
      expectVec(path.positionAt(40), const Vec3(50, 40, 0), tol: 1e-9);
      // Past it the ship rides the shell, so its distance from the origin is
      // the shell radius exactly.
      expect(path.positionAt(100).length, closeTo(100, 1e-9));
      expect(path.positionAt(900).length, closeTo(100, 1e-9));
    });

    test('closest approach on the straight leg, clamped to the leg', () {
      final path = DriftPath(
        start: const Vec3(0, 0, 0),
        velocity: const Vec3(1, 0, 0),
        // Huge shell: the whole window is straight-line flight.
        bound: 1e9,
      );
      // Star 10 ly off the track, level with s = 50.
      final near = path.closestApproach(const Vec3(50, 10, 0), 100);
      expect(near.distanceLy, closeTo(10, 1e-9));
      expect(near.seconds, closeTo(50, 1e-9));

      // Star behind the start: the nearest point is s = 0, not s = -20.
      final behind = path.closestApproach(const Vec3(-20, 5, 0), 100);
      expect(behind.distanceLy, closeTo(math.sqrt(425), 1e-9));
      expect(behind.seconds, 0);
    });

    test('closest approach on the arc, at the star\'s own bearing', () {
      // Same geometry as the driftPositionAt tests: shell hit at s = 86.6025
      // on (50, 86.6025, 0), sliding at 0.5 ly/s around a 100 ly circle.
      final path = DriftPath(
        start: const Vec3(50, 0, 0),
        velocity: const Vec3(0, 1, 0),
        bound: 100,
      );

      // A star sitting exactly on the arc, 90° round from the impact point.
      final onArc = path.closestApproach(const Vec3(-86.6025, 50, 0), 500);
      expect(onArc.distanceLy, closeTo(0, 0.001));
      // 86.6025 + 100·(π/2)/0.5
      expect(onArc.seconds, closeTo(400.7618, 0.001));

      // A star 30 ly off the arc's plane, at 30° round.
      final offArc = path.closestApproach(const Vec3(0, 100, 30), 500);
      expect(offArc.distanceLy, closeTo(30, 0.001));
      // 86.6025 + 100·(π/6)/0.5
      expect(offArc.seconds, closeTo(191.3223, 0.001));
    });

    test('a window that stops early clamps to the end of the arc', () {
      final path = DriftPath(
        start: const Vec3(50, 0, 0),
        velocity: const Vec3(0, 1, 0),
        bound: 100,
      );
      // The star's own bearing is at s ≈ 191.3, past this window.
      final cut = path.closestApproach(const Vec3(0, 100, 30), 150);
      expect(cut.distanceLy, closeTo(36.4056, 0.001));
      expect(cut.seconds, closeTo(150, 1e-9));
    });

    test('a window that starts late clamps to the start of the arc', () {
      final path = DriftPath(
        start: const Vec3(50, 0, 0),
        velocity: const Vec3(0, 1, 0),
        bound: 100,
      );
      // The star's own bearing is at s ≈ 191.3, before this window opens.
      final cut = path.closestApproach(const Vec3(0, 100, 30), 500,
          fromSeconds: 300);
      // Arc at s = 300 → θ = 0.5·(300-86.6025)/100 = 1.0669873 rad.
      expect(cut.seconds, closeTo(300, 1e-9));
      expect(cut.distanceLy, closeTo(61.4879, 0.001));
    });

    test('a long window still finds the bearing on a later lap', () {
      // This star sits exactly on the great circle at bearing 0, so the true
      // minimum is 0 once per revolution. The window opens past the first few
      // revolutions, so only a bearing generated from the window's own range
      // (here t = 6π) reaches it.
      final path = DriftPath(
        start: const Vec3(50, 0, 0),
        velocity: const Vec3(0, 1, 0),
        bound: 100,
      );
      final passed = path.closestApproach(const Vec3(50, 86.6025, 0), 4170.6,
          fromSeconds: 3228.2);
      expect(passed.distanceLy, closeTo(0, 0.001));
    });

    test('travelledBetween adds up both legs', () {
      final path = DriftPath(
        start: const Vec3(50, 0, 0),
        velocity: const Vec3(0, 1, 0),
        bound: 100,
      );
      // Wholly on the straight leg: 1 ly/s.
      expect(path.travelledBetween(0, 40), closeTo(40, 1e-9));
      // Straddling the shell hit: 86.6025 ly of line at 1 ly/s, then the rest
      // of the window as arc at 0.5 ly/s.
      expect(path.travelledBetween(0, 100), closeTo(93.3013, 1e-3));
      // A slice that starts exactly at the hit is arc only: 100 s at 0.5 ly/s.
      expect(path.travelledBetween(path.hitSeconds, path.hitSeconds + 100),
          closeTo(50, 1e-9));
      // A parked ship covers no ground.
      expect(
        DriftPath(
          start: const Vec3(50, 0, 0),
          velocity: const Vec3(0, 0, 0),
          bound: 100,
        ).travelledBetween(0, 1e6),
        0,
      );
    });
  });

  group('passedSystemsAlong', () {
    // One path, four stars: two essentially on it, one 30 ly off, one far away.
    final path = DriftPath(
      start: const Vec3(50, 0, 0),
      velocity: const Vec3(0, 1, 0),
      bound: 100,
    );
    final stars = _synthetic(<Vec3>[
      const Vec3(50, 10, 4), // 4 ly off the straight leg
      const Vec3(-86.6025, 50, 0), // on the arc, 90° round
      const Vec3(0, 100, 30), // 30 ly off the arc
      const Vec3(0, 0, 5000), // nowhere near
    ]);
    final universe = Universe(stars);

    test('counts every system inside the radius, closest first', () {
      final passed = universe.passedSystemsAlong(
        path: path,
        upToSeconds: 500,
        radiusLy: 35,
      );
      expect(passed.count, 3, reason: 'the far star is not passed');
      expect(passed.nearest.length, 3);
      expect(passed.nearest.map((p) => p.hygId).toList(), <int>[1001, 1000, 1002]);
      expect(passed.nearest[0].distanceLy, closeTo(0, 0.001));
      expect(passed.nearest[1].distanceLy, closeTo(4, 0.001));
      expect(passed.nearest[2].distanceLy, closeTo(30, 0.001));
      expect(passed.nearest[1].seconds, closeTo(10, 0.001));
    });

    test('a tighter radius drops the distant ones', () {
      final passed = universe.passedSystemsAlong(
        path: path,
        upToSeconds: 500,
        radiusLy: 20,
      );
      expect(passed.count, 2);
      expect(passed.nearest.map((p) => p.hygId).toList(), <int>[1001, 1000]);
    });

    test('the window bounds what counts as passed', () {
      // At 150 s the ship has only just started sliding, so the arc star 90°
      // round is still 117 ly away — but the 30 ly star is nearly in reach.
      final passed = universe.passedSystemsAlong(
        path: path,
        upToSeconds: 150,
        radiusLy: 40,
      );
      expect(passed.nearest.map((p) => p.hygId).toList(), <int>[1000, 1002]);
      expect(passed.count, 2);
    });

    test('a slice window excludes what an earlier report already covered', () {
      // The first report covered s ∈ [0, 200]; this one picks up from there,
      // so only the arc star at s ≈ 400.8 is still ahead.
      final passed = universe.passedSystemsAlong(
        path: path,
        upToSeconds: 500,
        fromSeconds: 200,
        radiusLy: 25,
      );
      expect(passed.count, 1);
      expect(passed.nearest.single.hygId, 1001);
      expect(passed.nearest.single.seconds, closeTo(400.7618, 0.001));
    });

    test('names at most `named`, but counts them all', () {
      final passed = universe.passedSystemsAlong(
        path: path,
        upToSeconds: 500,
        radiusLy: 35,
        named: 2,
      );
      expect(passed.count, 3);
      expect(passed.nearest.length, 2);
      expect(passed.nearest.map((p) => p.hygId).toList(), <int>[1001, 1000]);
    });
  });
}
