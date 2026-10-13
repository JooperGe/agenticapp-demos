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

  test('emits every generated vertex, split by the camera-facing plane', () {
    final lattice = buildShellLattice(
      centre: centre,
      radius: rWorld,
      forward: const Vec3(0, 0, 1),
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

    // Every vertex is on the side it was filed under. Forward is +z, so the
    // far half is z < 0 and the near half is z >= 0.
    for (final p in far) {
      expect(p.z, lessThan(0));
    }
    for (final p in near) {
      expect(p.z, greaterThanOrEqualTo(0));
    }
  });

  test('a run never straddles the plane', () {
    final lattice = buildShellLattice(
      centre: centre,
      radius: rWorld,
      forward: const Vec3(0, 0, 1),
    );
    for (final run in lattice.far) {
      expect(run.every((p) => p.z < 0), isTrue,
          reason: 'a far run must be entirely on the far side');
    }
    for (final run in lattice.near) {
      expect(run.every((p) => p.z >= 0), isTrue,
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
    // Forward along +x: the split is now the y/z plane at x = 0.
    final lattice = buildShellLattice(
      centre: centre,
      radius: rWorld,
      forward: const Vec3(1, 0, 0),
    );
    for (final run in lattice.far) {
      for (final p in run) {
        expect(p.x, lessThan(0));
      }
    }
    for (final run in lattice.near) {
      for (final p in run) {
        expect(p.x, greaterThanOrEqualTo(0));
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
