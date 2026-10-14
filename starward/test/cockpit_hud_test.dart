import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/ui/galaxy3d/camera3d.dart';
import 'package:starward/ui/galaxy3d/cockpit_hud.dart';

/// A camera at the origin looking down +Z, with a 60° field of view.
Camera3D _lookingForward() => Camera3D()
  ..mode = CameraMode.cockpit
  ..eyeOverride = const Vec3(0, 0, 0)
  ..yaw = 0
  ..pitch = 0
  ..fovDegrees = 60;

const Size2 _vp = Size2(400, 800);

void main() {
  group('headingLabel', () {
    test('reads a bearing from +Z toward +X, the same convention as forward',
        () {
      // `Camera3D.forward` is `(cos(p)sin(y), sin(p), cos(p)cos(y))`, so
      // `yaw == atan2(x, z)`. The readout has to use the same convention or a
      // ship aimed at a star reads a bearing the star map would not give it.
      expect(headingLabel(const Vec3(0, 0, 1)).bearing, '0°');
      expect(headingLabel(const Vec3(1, 0, 0)).bearing, '90°');
      expect(headingLabel(const Vec3(0, 0, -1)).bearing, '180°');
      expect(headingLabel(const Vec3(-1, 0, 0)).bearing, '270°');
    });

    test('reads elevation above and below the galactic plane', () {
      expect(headingLabel(const Vec3(0, 0, 1)).elevation, '+0°');
      expect(headingLabel(const Vec3(0, 1, 0)).elevation, '+90°');
      expect(headingLabel(const Vec3(0, -1, 0)).elevation, '−90°');
      // 45° up, and the same 45° below reads with a minus sign, not a second
      // "down" scale.
      expect(headingLabel(const Vec3(0, 1, 1)).elevation, '+45°');
      expect(headingLabel(const Vec3(0, -1, 1)).elevation, '−45°');
    });

    test('does not care how long the vector is', () {
      // Unnormalised, `asin(3)` saturates the clamp and reads `+90°`; only a
      // normalised vector gives the true `asin(3/5) = 36.87°`, which the
      // readout rounds to `+37°`.
      expect(headingLabel(const Vec3(0, 3, 4)).elevation, '+37°');
    });

    test('a zero vector reads as no heading rather than as NaN', () {
      expect(headingLabel(const Vec3(0, 0, 0)).bearing, '—');
      expect(headingLabel(const Vec3(0, 0, 0)).elevation, '—');
    });

    test('a negative-zero heading reads as 0° rather than -0°', () {
      // `atan2(-0.0, 1.0)` is `-0.0`, which is not `< 0`, so it skips the wrap
      // and `toStringAsFixed` renders it `-0`. That is a bearing, not a sign.
      expect(headingLabel(const Vec3(-0.0, 0, 1)).bearing, '0°');
    });
  });

  group('hudMarkerPoint', () {
    test('puts a point dead ahead in the centre of the screen', () {
      final at = hudMarkerPoint(
          camera: _lookingForward(), world: const Vec3(0, 0, 100), viewport: _vp);
      expect(at, isNotNull);
      expect(at!.dx, closeTo(200, 1e-6));
      expect(at.dy, closeTo(400, 1e-6));
    });

    test('puts a point off to the right of centre, and one above it above', () {
      // Which world direction is "screen right" is a property of the camera
      // basis, and it is not the one you would guess. `Camera3D.project` builds
      // `right = forward × up`, which for a forward of +Z is **−X** — so world
      // −X is screen-right here, and +X lands left of centre. Verified by
      // projecting both: `(10, 0, 100)` → `dx ≈ 130.72`, `(−10, 0, 100)` →
      // `dx ≈ 269.28`, against a centre of 200.
      //
      // Pinned here because nothing else pins it: the existing
      // `galaxy3d_projection_test.dart` states the magnitude `|dx − centre| > 1`
      // but not its sign, and the HUD's markers and the scene painter have to
      // agree on it.
      final right = hudMarkerPoint(
          camera: _lookingForward(), world: const Vec3(-10, 0, 100), viewport: _vp);
      final up = hudMarkerPoint(
          camera: _lookingForward(), world: const Vec3(0, 10, 100), viewport: _vp);
      expect(right!.dx, greaterThan(200));
      expect(right.dy, closeTo(400, 1e-6));
      // Screen y grows downward, so "above the camera" is a smaller y.
      expect(up!.dy, lessThan(400));
      expect(up.dx, closeTo(200, 1e-6));
    });

    test('projects through the real perspective divide, not a flat scale', () {
      // At 60° FOV over an 800 px tall viewport, `focal = 400 / tan(30°)`.
      // A point 10 units off-axis at 100 units deep is `focal * 0.1` px from
      // centre: `400 / tan(30°) * 0.1 = 69.282...`. Off-axis is −X on screen,
      // per the convention above, so the centre is displaced the other way.
      final at = hudMarkerPoint(
          camera: _lookingForward(), world: const Vec3(-10, 0, 100), viewport: _vp);
      expect(at!.dx, closeTo(200 + 69.2820323, 1e-4));
      // Twice as deep, the same offset is half the displacement: `focal * 0.05
      // = 34.641...`. A flat per-unit scale would give `69.282...` at both
      // depths, so this is what pins the divide.
      final deeper = hudMarkerPoint(
          camera: _lookingForward(), world: const Vec3(-10, 0, 200), viewport: _vp);
      expect(deeper!.dx, closeTo(200 + 34.6410162, 1e-4));
    });

    test('drops anything level with or behind the camera', () {
      final camera = _lookingForward();
      // Behind: `project` culls it to `Projected.hidden`, whose `screen` is
      // `Offset.zero`, so without the null the marker would be drawn in the
      // top-left corner and read as a marker sitting there.
      expect(
          hudMarkerPoint(
              camera: camera, world: const Vec3(0, 0, -100), viewport: _vp),
          isNull);
      // At the eye itself.
      expect(hudMarkerPoint(camera: camera, world: const Vec3(0, 0, 0), viewport: _vp),
          isNull);
      // Exactly on the camera plane, level with the eye's own right vector:
      // the perspective divide has no answer for it, so it is dropped rather
      // than drawn at infinity.
      expect(
          hudMarkerPoint(
              camera: camera, world: const Vec3(50, 0, 0), viewport: _vp),
          isNull);
    });

    test('follows the camera when it turns', () {
      final camera = _lookingForward()..yaw = math.pi / 2; // now looking +X
      final at = hudMarkerPoint(
          camera: camera, world: const Vec3(100, 0, 0), viewport: _vp);
      expect(at!.dx, closeTo(200, 1e-6), reason: 'now dead ahead');
      expect(at.dy, closeTo(400, 1e-6));
    });
  });

  test('headingDeviationDegrees is the angle the turn is priced on', () {
    // A level quarter turn: +Z to +X.
    expect(
      headingDeviationDegrees(
          current: const Vec3(0, 0, 1), proposed: const Vec3(1, 0, 0)),
      90,
    );
    // Lengths are irrelevant — the helper normalises both sides, which is what
    // `turnAngleTo` does before pricing.
    expect(
      headingDeviationDegrees(
          current: const Vec3(0, 0, 3), proposed: const Vec3(7, 0, 0)),
      90,
    );
    expect(
      headingDeviationDegrees(
          current: const Vec3(1, 0, 0), proposed: const Vec3(1, 0, 0)),
      0,
    );
    expect(
      headingDeviationDegrees(
          current: const Vec3(1, 0, 0), proposed: const Vec3(-1, 0, 0)),
      180,
    );
    // A parked ship has no course to deviate from. `turnAngleTo` returns 0 for
    // it, and the readout has to agree with the price.
    expect(
      headingDeviationDegrees(
          current: const Vec3(0, 0, 0), proposed: const Vec3(1, 0, 0)),
      0,
    );
  });

  group('clampHudPoint', () {
    test('leaves a point inside the safe area alone', () {
      final r = clampHudPoint(const Offset(200, 400), _vp);
      expect(r.at, const Offset(200, 400));
      expect(r.offScreen, isFalse);
    });

    test('pins each edge at the frame and bottom-panel margin', () {
      // 26 clear of the sides, 74 below the top strut, 132 above the bottom.
      expect(clampHudPoint(const Offset(-40, 400), _vp).at, const Offset(26, 400));
      expect(clampHudPoint(const Offset(900, 400), _vp).at, const Offset(374, 400));
      expect(clampHudPoint(const Offset(200, -10), _vp).at, const Offset(200, 74));
      expect(clampHudPoint(const Offset(200, 900), _vp).at, const Offset(200, 668));
    });

    test('reports whether it had to move', () {
      expect(clampHudPoint(const Offset(-40, 400), _vp).offScreen, isTrue);
      expect(clampHudPoint(const Offset(26, 400), _vp).offScreen, isFalse);
    });
  });

  group('headingMarkerPoint', () {
    test('sits on the reticle when the course is the aim', () {
      final p = headingMarkerPoint(
        camera: _lookingForward(),
        heading: const Vec3(0, 0, 1),
        viewport: _vp,
      )!;
      expect(p.at.dx, moreOrLessEquals(200, epsilon: 0.5));
      expect(p.at.dy, moreOrLessEquals(400, epsilon: 0.5));
      expect(p.offScreen, isFalse);
    });

    test('pins to the side edge for a course abeam', () {
      // The whole reason for the forward nudge. The raw point at exactly 90° has
      // `camZ == 0` and is culled — and so is every course out to dead astern,
      // because the cull is at `camZ <= 1.0` and the raw `camZ` is only
      // `400·cos θ`. The nudge moves that boundary out to 104.33°, so a course
      // abeam gets a real screen position instead of the bottom-edge fallback.
      //
      // It lands on the **left** edge, not the right. `Camera3D.project` builds
      // `right = forward × up`, which for a forward of +Z is −X — so world −X is
      // screen-right, and a +X course lands left of centre. The existing
      // 'puts a point off to the right of centre' test pins that convention for
      // the same reason: it is not the one you would guess.
      //
      // The point being clamped is also why the triangle draws dimmed: it sits
      // at the edge rather than at its true direction.
      final p = headingMarkerPoint(
        camera: _lookingForward(),
        heading: const Vec3(1, 0, 0),
        viewport: _vp,
      )!;
      expect(p.at, const Offset(26, 400));
      expect(p.offScreen, isTrue);
    });

    test('pins to the top edge for a course straight up', () {
      final p = headingMarkerPoint(
        camera: _lookingForward(),
        heading: const Vec3(0, 1, 0),
        viewport: _vp,
      )!;
      expect(p.at, const Offset(200, 74));
      expect(p.offScreen, isTrue);
    });

    test('pins to the bottom edge for a course dead astern', () {
      final p = headingMarkerPoint(
        camera: _lookingForward(),
        heading: const Vec3(0, 0, -1),
        viewport: _vp,
      )!;
      expect(p.at, const Offset(200, 668));
      expect(p.offScreen, isTrue);
    });

    test('has no position without a course', () {
      expect(
        headingMarkerPoint(
            camera: _lookingForward(),
            heading: const Vec3(0, 0, 0),
            viewport: _vp),
        isNull,
      );
    });
  });
}
