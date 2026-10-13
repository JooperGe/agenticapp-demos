import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starward/ui/galaxy3d/camera3d.dart';
import 'package:starward/ui/galaxy3d/universe_shell.dart';

/// The shell's geometry is pure — no Flutter state, no game state — so it can
/// be tested without building a widget. Every count and side assignment is
/// pinned; the draw order it enables is what makes the globe read as hollow
/// rather than as a ball the stars are painted onto.
void main() {
  const double rWorld = 36792;
  const Vec3 centre = Vec3(0, 0, 0);

  test('files each vertex by which side of the sphere is nearer the eye', () {
    // The camera sits behind the sphere's centre and looks at it:
    //   eye = target − forward·d.
    // With the centre at the origin, forward = +z and d = 25, the eye is at
    // (0, 0, −25). The distance from the eye to a surface point P is
    //   |P − eye|² = R² + d² + 2d·(P·forward),
    // which *grows* with P·forward — so the vertex with negative P·forward is
    // the near one. (The eye formula makes it easy to assume the opposite, and
    // an inverted split silently reverses the shell's two-pass draw order.)
    const Vec3 forward = Vec3(0, 0, 1);
    const Vec3 eye = Vec3(0, 0, -25);
    const double r = 10;

    // The two poles of the split, worked by hand:
    //   P_near = (0, 0, −10) → |P_near − eye| = 15, (P_near − C)·forward = −10
    //   P_far  = (0, 0, +10) → |P_far  − eye| = 35, (P_far  − C)·forward = +10
    expect((const Vec3(0, 0, -10) - eye).length, closeTo(15, 1e-9));
    expect((const Vec3(0, 0, 10) - eye).length, closeTo(35, 1e-9));

    final lattice = buildShellLattice(
      centre: centre,
      radius: r,
      forward: forward,
    );

    final far = <Vec3>[];
    final near = <Vec3>[];
    for (final run in lattice.far) {
      far.addAll(run);
    }
    for (final run in lattice.near) {
      near.addAll(run);
    }

    // 12 meridians × 33 points + 6 parallels × 49 points.
    expect(far.length + near.length, 12 * 33 + 6 * 49);

    // (0, 0, ∓10) are both generated vertices (the meridian through the ±z
    // axis), so the split must file the closer one as near and the farther as
    // far. Pinned as a distance comparison, not a raw sign, so re-inverting the
    // predicate fails here instead of silently swapping the draw order.
    final all = <Vec3>[...near, ...far];
    var nearest = all.first;
    var farthest = all.first;
    for (final p in all) {
      if ((p - eye).length < (nearest - eye).length) nearest = p;
      if ((p - eye).length > (farthest - eye).length) farthest = p;
    }
    expect(near, contains(nearest));
    expect(far, contains(farthest));
    expect((nearest - eye).length, closeTo(15, 1e-6));
    expect((farthest - eye).length, closeTo(35, 1e-6));

    // Every vertex filed as near is no farther from the eye than every vertex
    // filed as far — the ordering the two-pass draw order depends on. The
    // tolerance absorbs vertices sitting on the plane itself, whose side is
    // decided by a floating-point sign rather than by geometry.
    var maxNear = 0.0;
    for (final p in near) {
      final d = (p - eye).length;
      if (d > maxNear) maxNear = d;
    }
    var minFar = double.infinity;
    for (final p in far) {
      final d = (p - eye).length;
      if (d < minFar) minFar = d;
    }
    expect(maxNear, lessThan(minFar + 1e-6));
  });

  test('a run never straddles the plane', () {
    final lattice = buildShellLattice(
      centre: centre,
      radius: rWorld,
      forward: const Vec3(0, 0, 1),
    );
    // Forward is +z, so the eye is on the −z side: the near half is z <= 0 and
    // the far half is z > 0.
    for (final run in lattice.far) {
      expect(run.every((p) => p.z > 0), isTrue,
          reason: 'a far run must be entirely on the far side');
    }
    for (final run in lattice.near) {
      expect(run.every((p) => p.z <= 0), isTrue,
          reason: 'a near run must be entirely on the near side');
    }
  });

  test('every vertex sits exactly on the sphere', () {
    final lattice = buildShellLattice(
      centre: centre,
      radius: rWorld,
      forward: const Vec3(0, 0, 1),
    );
    for (final run in <List<Vec3>>[...lattice.far, ...lattice.near]) {
      for (final p in run) {
        expect((p - centre).length, closeTo(rWorld, 1));
      }
    }
  });

  test('rotating the camera moves the split with it', () {
    // Forward along +x, so the eye (target − forward·d) sits on the −x side and
    // the split is the y/z plane at x = 0. The far half is x > 0.
    final lattice = buildShellLattice(
      centre: centre,
      radius: rWorld,
      forward: const Vec3(1, 0, 0),
    );
    for (final run in lattice.far) {
      for (final p in run) {
        expect(p.x, greaterThan(0));
      }
    }
    for (final run in lattice.near) {
      for (final p in run) {
        expect(p.x, lessThanOrEqualTo(0));
      }
    }
  });

  group('UniverseShell.limbRadius', () {
    UniverseShell shell() =>
        UniverseShell(centre: centre, radius: rWorld, forward: const Vec3(0, 0, 1));

    Camera3D cameraAt(double distance) => Camera3D(
          target: centre,
          yaw: 0,
          pitch: 0,
          distance: distance,
          mode: CameraMode.overview,
        );

    test('matches the exact limb formula at the framing distance', () {
      // d = 2R, 800×600 → exactly h/2 = 300.
      expect(
        shell().limbRadius(cameraAt(2 * rWorld), const Size2(800, 600)),
        closeTo(300, 0.1),
      );
    });

    test('is infinite once the eye is inside the sphere', () {
      expect(
        shell().limbRadius(cameraAt(0.5 * rWorld), const Size2(800, 600)),
        double.infinity,
      );
    });

    test('draws nothing at all once the eye is inside the sphere', () async {
      // The spec's "球内不画" requirement, asserted on real pixels rather than
      // on the gate: the shell is painted unconditionally here, so this
      // exercises its own alpha maths, not a copy of the caller's condition.
      Future<int> opaquePixels(double distance) async {
        final fade = shellFade(radius: rWorld, distance: distance);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 800, 600));
        final vp = const Size2(800, 600);
        shell().paintFarHalf(canvas,
            camera: cameraAt(distance), viewport: vp, fade: fade);
        shell().paintNearHalf(canvas,
            camera: cameraAt(distance), viewport: vp, fade: fade);
        final image = recorder.endRecording().toImageSync(800, 600);
        final bytes =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        final data = bytes!.buffer.asUint8List();
        var count = 0;
        for (var i = 3; i < data.length; i += 4) {
          if (data[i] != 0) count++;
        }
        return count;
      }

      expect(await opaquePixels(2.3 * rWorld), greaterThan(0));
      expect(await opaquePixels(0.5 * rWorld), 0);
    });
  });
}
