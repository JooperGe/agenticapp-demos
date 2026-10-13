import 'package:flutter_test/flutter_test.dart';
import 'package:starward/ui/galaxy3d/camera3d.dart';

/// The framing maths behind the universe-overview camera. Every number here is
/// derived by hand in the spec (§4.2, §5.2) and pinned so a refactor that
/// changes the framing is caught rather than shipped.
void main() {
  // A sample radius in world units (3066 ly × worldScale 12). Everything below
  // is radius-agnostic — the framing maths never sees the catalogue — so this
  // stands in for whatever `Universe.universeRadius` happens to yield.
  const double rWorld = 36792;
  const double fov = 60;
  const Size2 landscape = Size2(800, 600);
  const Size2 portrait = Size2(400, 800);

  group('focalFor', () {
    test('derives from viewport height only', () {
      // (600 / 2) / tan(30°) = 300 / 0.5773502692
      expect(focalFor(landscape, fov), closeTo(519.6152, 0.001));
      // Width does not enter the focal length.
      expect(focalFor(const Size2(1600, 600), fov), closeTo(519.6152, 0.001));
    });
  });

  group('fitDistanceForSphere', () {
    test('landscape fits at exactly 2R, independent of viewport size', () {
      // focal comes from the viewport height, so at 60° the height constraint
      // reduces to d = R / sin(30°) = 2R.
      expect(
        fitDistanceForSphere(
            radius: rWorld, viewport: landscape, fovDegrees: fov),
        closeTo(73584, 1),
      );
      expect(
        fitDistanceForSphere(
            radius: rWorld, viewport: const Size2(1600, 600), fovDegrees: fov),
        closeTo(73584, 1),
      );
    });

    test('portrait is width-bound and needs sqrt(13) * R for a 1:2 viewport', () {
      expect(
        fitDistanceForSphere(radius: rWorld, viewport: portrait, fovDegrees: fov),
        closeTo(132655, 2),
      );
    });
  });

  group('limbScreenRadius', () {
    test('uses the exact form, not focal * R / d', () {
      final exact = limbScreenRadius(
        radius: rWorld,
        distance: 2 * rWorld,
        viewport: landscape,
        fovDegrees: fov,
      );
      // At d = 2R the sphere is inscribed in the height, so the limb is h/2.
      expect(exact, closeTo(300, 0.1));

      final naive = focalFor(landscape, fov) * rWorld / (2 * rWorld);
      expect(naive, closeTo(259.8, 0.1));
      // The naive form under-draws by 13.4% — the ratio is exactly sqrt(3)/2.
      expect(naive / exact, closeTo(0.8660254, 0.0001));
    });

    test('is infinite at or inside the limb', () {
      expect(
        limbScreenRadius(
            radius: rWorld, distance: rWorld, viewport: landscape, fovDegrees: fov),
        double.infinity,
      );
      expect(
        limbScreenRadius(
            radius: rWorld,
            distance: 0.5 * rWorld,
            viewport: landscape,
            fovDegrees: fov),
        double.infinity,
      );
    });
  });

  group('shellFade', () {
    test('fully drawn clear of the surface, gone at or inside it', () {
      // 2.3R is well clear of the ramp, so this is exactly 1.0.
      expect(shellFade(radius: rWorld, distance: 2.3 * rWorld), 1.0);
      // 1.15R sits exactly on the ramp's end, where floating point lands a
      // hair under 1.0 — hence the tolerance.
      expect(shellFade(radius: rWorld, distance: 1.15 * rWorld),
          closeTo(1.0, 0.001));
      expect(shellFade(radius: rWorld, distance: rWorld), 0.0);
      expect(shellFade(radius: rWorld, distance: 0.5 * rWorld), 0.0);
    });

    test('ramps over the last 15% of the approach', () {
      // (1.075R / R − 1) / 0.15 = 0.5
      expect(shellFade(radius: rWorld, distance: 1.075 * rWorld), closeTo(0.5, 0.01));
    });

    test('a zero radius draws nothing instead of dividing by zero', () {
      expect(shellFade(radius: 0, distance: 100), 0.0);
    });
  });

  group('the overview camera', () {
    test('shares the orbit eye formula, putting the eye outside the volume', () {
      final cam = Camera3D(
        target: const Vec3(0, 0, 0),
        yaw: 0,
        pitch: 0,
        distance: 2.3 * rWorld,
        mode: CameraMode.overview,
      );
      expect(cam.eye.length, closeTo(2.3 * rWorld, 1));
      expect(cam.eye.length, greaterThan(rWorld));
    });

    test('projects the origin (the sphere centre) to the screen centre', () {
      final cam = Camera3D(
        target: const Vec3(0, 0, 0),
        yaw: 0.6,
        pitch: 0.35,
        distance: 2.3 * rWorld,
        mode: CameraMode.overview,
      );
      final p = cam.project(const Vec3(0, 0, 0), landscape);
      expect(p.visible, isTrue);
      expect(p.screen.dx, closeTo(400, 0.5));
      expect(p.screen.dy, closeTo(300, 0.5));
    });
  });

  group('the default framing', () {
    // d_default = 1.15 * d_fit — the page's _overviewDefaultDistance.
    double defaultDistance(Size2 vp) =>
        1.15 * fitDistanceForSphere(radius: rWorld, viewport: vp, fovDegrees: fov);

    test('leaves a margin: the limb stays inside the short edge', () {
      for (final vp in <Size2>[landscape, portrait]) {
        final d = defaultDistance(vp);
        final limb = limbScreenRadius(
          radius: rWorld,
          distance: d,
          viewport: vp,
          fovDegrees: fov,
        );
        final shortEdge = vp.width < vp.height ? vp.width : vp.height;
        expect(limb, lessThanOrEqualTo(shortEdge / 2 + 0.001));
      }
    });

    test('the zoom bound clears the default framing in BOTH orientations', () {
      // The regression this guards: d_default is viewport-dependent (2.3R
      // landscape, 4.15R portrait), so a bound picked by eye for landscape
      // would clamp the camera CLOSER than the framing distance on a phone —
      // slicing the shell open on entry. The bound must be derived, not chosen.
      const upperBound = 5 * rWorld;
      final landscapeDefault = defaultDistance(landscape);
      final portraitDefault = defaultDistance(portrait);
      expect(landscapeDefault, lessThan(upperBound));
      expect(portraitDefault, lessThan(upperBound));
      // And they really do differ — otherwise this test would pass vacuously.
      expect(portraitDefault, greaterThan(landscapeDefault));
      // 1.15 × 2R exactly, and 1.15 × √13 R = 4.146384R.
      expect(landscapeDefault, closeTo(2.3 * rWorld, 1));
      expect(portraitDefault, closeTo(4.146384 * rWorld, 1));
    });
  });

  group('maxDistanceFor', () {
    test('overview is bounded at 5R, orbit and cockpit stay at 1800', () {
      expect(maxDistanceFor(CameraMode.overview, rWorld), closeTo(5 * rWorld, 1));
      expect(maxDistanceFor(CameraMode.orbit, rWorld), 1800.0);
      expect(maxDistanceFor(CameraMode.cockpit, rWorld), 1800.0);
    });

    test('an empty catalogue still yields a valid clamp range', () {
      // Universe.universeRadius returns 0 with no stars; clamp(70, 0) throws.
      expect(maxDistanceFor(CameraMode.overview, 0), kMinZoomDistance);
    });

    test('the bound clears the default framing in both orientations', () {
      // The regression §4.3 names: d_default is viewport-dependent, so a bound
      // picked by eye for landscape would clamp the camera closer than the
      // framing on a phone and cut the shell open on entry.
      for (final vp in <Size2>[landscape, portrait]) {
        expect(1.15 * fitDistanceForSphere(radius: rWorld, viewport: vp, fovDegrees: fov),
            lessThan(maxDistanceFor(CameraMode.overview, rWorld)));
      }
    });
  });

  group('placeCamera', () {
    const ship = Vec3(1200, 40, -300);

    test('overview looks at the origin from the framing distance', () {
      final cam = Camera3D();
      placeCamera(
        cam,
        mode: CameraMode.overview,
        shipPosition: ship,
        overviewDistance: 84622,
      );
      expect(cam.mode, CameraMode.overview);
      expect(cam.target.x, 0);
      expect(cam.target.y, 0);
      expect(cam.target.z, 0);
      expect(cam.distance, 84622);
      // Which puts the eye outside the sphere the page just framed.
      expect(cam.eye.length, closeTo(84622, 1));
      expect(cam.eye.length, greaterThan(rWorld));
    });

    test('orbit looks at the ship', () {
      final cam = Camera3D();
      placeCamera(
        cam,
        mode: CameraMode.orbit,
        shipPosition: ship,
        overviewDistance: 84622,
      );
      expect(cam.mode, CameraMode.orbit);
      expect(cam.target.x, closeTo(ship.x, 0.001));
      expect(cam.target.y, closeTo(ship.y, 0.001));
      expect(cam.target.z, closeTo(ship.z, 0.001));
      expect(cam.distance, 520);
    });

    test('cockpit sits at the ship', () {
      final cam = Camera3D();
      placeCamera(
        cam,
        mode: CameraMode.cockpit,
        shipPosition: ship,
        overviewDistance: 84622,
      );
      expect(cam.mode, CameraMode.cockpit);
      expect(cam.eye.x, closeTo(ship.x, 0.001));
      expect(cam.eye.y, closeTo(ship.y, 0.001));
      expect(cam.eye.z, closeTo(ship.z, 0.001));
    });
  });

  group('placeCameraForRoute', () {
    test('focus-route framing fits a 25.4 ly route to 60% of the short edge', () {
      // 25.4 ly → 304.8 world units. At 400×800 the focal is 692.82 px, so the
      // route needs 304.8 * 692.82 / (0.6 * 400) ≈ 880 world units of distance,
      // and the camera aims at the route's midpoint.
      final cam = Camera3D();
      placeCameraForRoute(
        cam,
        from: const Vec3(0, 0, 0),
        to: const Vec3(304.8, 0, 0),
        viewport: portrait,
        fovDegrees: fov,
      );
      expect(cam.distance, closeTo(880, 5));
      expect(cam.target.x, closeTo(152.4, 0.01));
      expect(cam.target.y, 0);
      expect(cam.target.z, 0);
    });
  });
}
