import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/ui/galaxy3d/camera3d.dart';

void main() {
  group('aimCameraAt', () {
    test('is the exact inverse of Camera3D.forward', () {
      // The reticle is drawn at the centre of the screen, the heading bar quotes
      // `forward`, and ignition flies along `forward`. If aiming and reading are
      // not exact inverses, those three disagree about where the ship points.
      final directions = <Vec3>[
        const Vec3(1, 0, 0),
        const Vec3(-1, 0, 0),
        const Vec3(0, 0, 1),
        const Vec3(0, 0, -1),
        const Vec3(0.3, 0.5, -0.8),
        const Vec3(-0.2, -0.7, 0.4),
        const Vec3(1, 0.001, 1),
      ];
      for (final d in directions) {
        final camera = Camera3D();
        aimCameraAt(camera, d);
        final want = d.normalized;
        final got = camera.forward.normalized;
        expect(got.x, closeTo(want.x, 1e-9), reason: '$d');
        expect(got.y, closeTo(want.y, 1e-9), reason: '$d');
        expect(got.z, closeTo(want.z, 1e-9), reason: '$d');
      }
    });

    test('clamps a straight-up aim rather than flipping over the pole', () {
      final camera = Camera3D();
      aimCameraAt(camera, const Vec3(0, 1, 0));
      expect(camera.pitch, lessThan(math.pi / 2));
      expect(camera.forward.y, greaterThan(0.99),
          reason: 'clamped, but still pointing essentially straight up');
    });

    test('leaves the eye and the mode alone', () {
      // `Vec3` has no `operator ==`, so `expect(camera.eyeOverride, eye)` would
      // be an *identity* check that happens to pass only because the two `const`
      // expressions canonicalise to one instance. Assert identity deliberately,
      // so the test says what it means: the aim must not replace the eye.
      const eye = Vec3(5, 6, 7);
      final camera = Camera3D()
        ..mode = CameraMode.cockpit
        ..eyeOverride = eye;
      aimCameraAt(camera, const Vec3(0, 0, 1));
      expect(camera.mode, CameraMode.cockpit);
      expect(identical(camera.eyeOverride, eye), isTrue,
          reason: 'the aim must not touch the eye');
    });

    test('a zero vector is ignored rather than producing NaN', () {
      final camera = Camera3D()..yaw = 1.2;
      aimCameraAt(camera, const Vec3(0, 0, 0));
      expect(camera.yaw, 1.2, reason: 'unchanged');
      expect(camera.forward.length, closeTo(1, 1e-9));
    });
  });
}
