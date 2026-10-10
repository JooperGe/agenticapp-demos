import 'dart:math' as math;

import 'package:flutter/widgets.dart' show Offset;

import '../../core/vec3.dart';

export '../../core/vec3.dart';

/// Result of projecting a world point to the screen.
class Projected {
  const Projected(this.screen, this.depth, this.scale, this.visible);

  /// Screen-space position in pixels.
  final Offset screen;

  /// Camera-space depth (distance in front of the eye). Larger = farther, used
  /// for painter's-algorithm sorting (draw far first).
  final double depth;

  /// Perspective size factor (focal / depth) — multiply a world radius by this
  /// to get an on-screen radius, which is what sells the depth illusion.
  final double scale;

  /// False when the point is behind the camera / near plane (cull it).
  final bool visible;

  static const Projected hidden =
      Projected(Offset.zero, double.infinity, 0, false);
}

/// How the camera is placed and aimed.
enum CameraMode {
  /// Orbit around a target point — the "star-map overview".
  orbit,

  /// Sit at the ship and look outward — first-person cockpit.
  cockpit,
}

/// A perspective camera driven by yaw/pitch so it can be rotated by dragging.
///
/// The same projection serves both modes; only how [eye] and [forward] are
/// derived differs. This keeps one code path for the whole pipeline — the
/// thing that makes a 2D canvas read convincingly as 3D.
class Camera3D {
  Camera3D({
    this.target = const Vec3(0, 0, 0),
    this.yaw = 0,
    this.pitch = 0.35,
    this.distance = 600,
    this.fovDegrees = 60,
    this.mode = CameraMode.orbit,
    this.eyeOverride,
  });

  /// Point the orbit camera looks at (ignored in cockpit mode).
  Vec3 target;

  /// Horizontal rotation (radians).
  double yaw;

  /// Vertical rotation (radians), clamped to avoid flipping over the poles.
  double pitch;

  /// Orbit radius (overview zoom).
  double distance;

  double fovDegrees;
  CameraMode mode;

  /// Eye position used in cockpit mode (the ship's location).
  Vec3? eyeOverride;

  static const double _near = 1.0;
  static const double _maxPitch = math.pi / 2 - 0.05;

  /// Forward (look) direction from yaw/pitch.
  Vec3 get forward => Vec3(
        math.cos(pitch) * math.sin(yaw),
        math.sin(pitch),
        math.cos(pitch) * math.cos(yaw),
      );

  Vec3 get eye {
    if (mode == CameraMode.cockpit) {
      return eyeOverride ?? const Vec3(0, 0, 0);
    }
    // Orbit: sit [distance] back along the look direction from the target.
    return target - forward * distance;
  }

  void clampPitch() {
    if (pitch > _maxPitch) pitch = _maxPitch;
    if (pitch < -_maxPitch) pitch = -_maxPitch;
  }

  /// Projects a world point. [viewport] is the canvas size in pixels.
  Projected project(Vec3 p, Size2 viewport) {
    final f = forward.normalized;
    // Right-handed basis. Guard the degenerate case where forward ∥ up.
    var right = f.cross(Vec3.up);
    if (right.length < 1e-6) right = const Vec3(1, 0, 0);
    right = right.normalized;
    final camUp = right.cross(f).normalized;

    final rel = p - eye;
    final camZ = rel.dot(f); // depth in front of the eye
    if (camZ <= _near) return Projected.hidden;

    final camX = rel.dot(right);
    final camY = rel.dot(camUp);

    final focal = (viewport.height / 2) / math.tan(_fovRadians / 2);
    final sx = viewport.width / 2 + camX / camZ * focal;
    final sy = viewport.height / 2 - camY / camZ * focal;
    return Projected(Offset(sx, sy), camZ, focal / camZ, true);
  }

  double get _fovRadians => fovDegrees * math.pi / 180;
}

/// Tiny size holder so the camera stays free of Flutter painting imports
/// beyond [Offset].
class Size2 {
  const Size2(this.width, this.height);
  final double width;
  final double height;
}
