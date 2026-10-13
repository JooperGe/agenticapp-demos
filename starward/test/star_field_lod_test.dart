import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/hyg_catalog.dart';
import 'package:starward/ui/galaxy3d/camera3d.dart';
import 'package:starward/ui/galaxy3d/star_field_painter.dart';

/// The universe-overview camera sees the whole catalogue from ~73 000 world
/// units away. The star-map painter rescales each star's magnitude to the
/// viewer's distance — right when the ship is among the stars, catastrophic
/// from outside: it dims the median catalogue star by 5 magnitudes, which
/// saturates the alpha ramp and renders the universe a near-black ball.
/// These tests pin the switch that prevents that, and pin the star map's
/// existing behaviour so the extraction provably changed nothing.
void main() {
  const double ws = 12;
  const double rWorld = 36792;

  /// Eye at (0, 0, -100), looking toward +z.
  Camera3D orbitCamera() => Camera3D(
        target: const Vec3(0, 0, 0),
        yaw: 0,
        pitch: 0,
        distance: 100,
        mode: CameraMode.orbit,
      );

  /// Eye at 2.3R along −z, looking at the origin.
  Camera3D overviewCamera() => Camera3D(
        target: const Vec3(0, 0, 0),
        yaw: 0,
        pitch: 0,
        distance: 2.3 * rWorld,
        mode: CameraMode.overview,
      );

  HygNamed starAt(Vec3 posLy, double magnitude) => HygNamed(
        id: 1,
        name: 'Test',
        position: posLy,
        magnitude: magnitude,
        color: 0xFFFFFFFF,
      );

  test('distanceScaled: true reproduces the star map exactly (regression)', () {
    // Star at 10 ly along +x → 120 world units. rel = (120, 0, 100).
    // d_eye² = 24400, d_sol² = 14400, ratio = 1.6944444.
    // 2.5 * log10(1.6944444) = 0.5726...
    final m = apparentMagnitude(
      n: starAt(const Vec3(10, 0, 0), 2.5),
      camera: orbitCamera(),
      worldScale: ws,
      distanceScaled: true,
    );
    expect(m, closeTo(3.0726, 0.001));
  });

  test('distanceScaled: false returns the catalogue magnitude verbatim', () {
    final m = apparentMagnitude(
      n: starAt(const Vec3(10, 0, 0), 2.5),
      camera: orbitCamera(),
      worldScale: ws,
      distanceScaled: false,
    );
    expect(m, 2.5);
  });

  test('the rescale would black the universe out from outside', () {
    // A star 703 ly from Sol (the catalogue's p50) is dimmed 5.0 magnitudes;
    // the alpha ramp ((6.6 - m) / 8 + 0.12) clamps at 0.05 for anything above
    // m = 6.16, so a dimmed sky collapses to the floor.
    final m = apparentMagnitude(
      n: starAt(const Vec3(703, 0, 0), 3.0),
      camera: overviewCamera(),
      worldScale: ws,
      distanceScaled: true,
    );
    expect(m, closeTo(8.0175, 0.02)); // 3.0 + 5.0175
    expect(((6.6 - m) / 8 + 0.12).clamp(0.05, 1.0), 0.05);
  });

  test('without the rescale a bright landmark stays visible from outside', () {
    // Sirius: magnitude −1.46.
    final m = apparentMagnitude(
      n: starAt(const Vec3(8.6, 0, 0), -1.46),
      camera: overviewCamera(),
      worldScale: ws,
      distanceScaled: false,
    );
    expect(m, -1.46);
    expect(((6.6 - m) / 8 + 0.12).clamp(0.05, 1.0), greaterThan(0.9));
  });
}
