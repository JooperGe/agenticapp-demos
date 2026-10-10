import 'package:flutter_test/flutter_test.dart';
import 'package:starward/ui/galaxy3d/camera3d.dart';

/// Verifies the perspective projection that makes the 2D canvas read as 3D:
/// centring, perspective sizing, depth ordering and behind-camera culling.
void main() {
  const vp = Size2(800, 600);

  Camera3D frontFacing() => Camera3D(
        target: const Vec3(0, 0, 0),
        yaw: 0,
        pitch: 0,
        distance: 100,
        mode: CameraMode.orbit,
      );

  test('a point at the look target projects to screen centre', () {
    final cam = frontFacing();
    final p = cam.project(const Vec3(0, 0, 0), vp);
    expect(p.visible, isTrue);
    expect(p.screen.dx, closeTo(400, 0.5));
    expect(p.screen.dy, closeTo(300, 0.5));
  });

  test('points behind the camera are culled', () {
    final cam = frontFacing(); // eye sits at z = -100 looking toward +z
    final behind = cam.project(const Vec3(0, 0, -200), vp);
    expect(behind.visible, isFalse);
  });

  test('farther points have greater depth and smaller scale', () {
    final cam = frontFacing();
    final near = cam.project(const Vec3(0, 0, 0), vp); // depth 100
    final far = cam.project(const Vec3(0, 0, 60), vp); // depth 160
    expect(near.visible && far.visible, isTrue);
    expect(far.depth, greaterThan(near.depth));
    expect(far.scale, lessThan(near.scale));
  });

  test('an off-axis point projects away from centre horizontally', () {
    final cam = frontFacing();
    final p = cam.project(const Vec3(20, 0, 0), vp);
    expect(p.visible, isTrue);
    expect((p.screen.dx - 400).abs(), greaterThan(1));
    expect(p.screen.dy, closeTo(300, 0.5)); // no vertical component
  });

  test('pitch clamping prevents flipping over the poles', () {
    final cam = Camera3D(pitch: 10)..clampPitch();
    expect(cam.pitch, lessThan(1.6));
    cam
      ..pitch = -10
      ..clampPitch();
    expect(cam.pitch, greaterThan(-1.6));
  });
}
