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

  /// Sit outside the universe's boundary sphere and look in — the "universe
  /// overview". Reuses [orbit]'s eye formula; only the target's meaning and how
  /// far the camera may be pulled differ.
  overview,
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

    final focal = focalFor(viewport, fovDegrees);
    final sx = viewport.width / 2 + camX / camZ * focal;
    final sy = viewport.height / 2 - camY / camZ * focal;
    return Projected(Offset(sx, sy), camZ, focal / camZ, true);
  }
}

/// Tiny size holder so the camera stays free of Flutter painting imports
/// beyond [Offset].
class Size2 {
  const Size2(this.width, this.height);
  final double width;
  final double height;
}

/// Focal length in pixels for a viewport. Always derived from the viewport
/// height, which is why the height constraint on framing is aspect-independent.
double focalFor(Size2 viewport, double fovDegrees) =>
    (viewport.height / 2) / math.tan(fovDegrees * math.pi / 360);

/// Screen radius (pixels) of the limb of a sphere of [radius] whose centre lies
/// [distance] in front of the eye.
///
/// This is `focal * radius / sqrt(distance² - radius²)`, NOT the tempting
/// `focal * radius / distance`. The naive form under-draws by 13.4% at
/// `distance == 2 * radius` (the ratio is exactly `sqrt(3)/2`) and diverges as
/// the eye approaches the surface, so it cannot be used to size the shell.
///
/// Returns [double.infinity] when the eye is at or inside the limb, where a
/// limb radius is not defined.
double limbScreenRadius({
  required double radius,
  required double distance,
  required Size2 viewport,
  required double fovDegrees,
}) {
  final gap = distance * distance - radius * radius;
  if (gap <= 0) return double.infinity;
  return focalFor(viewport, fovDegrees) * radius / math.sqrt(gap);
}

/// The orbit distance at which a sphere of [radius] centred on the camera's
/// target exactly fits inside [viewport], touching the nearer edge.
///
/// Solves [limbScreenRadius] for `limb == min(width, height) / 2`. Both edges
/// are solved and the larger distance wins, so portrait and landscape are both
/// correct:
///
/// - Landscape: the height constraint binds and the answer is
///   `radius / sin(fov/2)` — at 60° that is exactly `2 * radius`, independent of
///   the viewport size.
/// - Portrait: the width constraint binds and the answer grows with the aspect
///   ratio (a 400×800 viewport needs `sqrt(13) * radius`).
double fitDistanceForSphere({
  required double radius,
  required Size2 viewport,
  required double fovDegrees,
}) {
  final half = fovDegrees * math.pi / 360;
  final byHeight = radius / math.sin(half);
  final aspect = viewport.height / viewport.width;
  final tanHalf = math.tan(half);
  final byWidth = radius * math.sqrt(1 + (aspect * aspect) / (tanHalf * tanHalf));
  return math.max(byHeight, byWidth);
}

/// How strongly to draw the universe shell at a given camera [distance]:
/// 1 when clear of the surface, 0 at or inside it, ramping over the last 15% of
/// the approach.
///
/// The shell is only ever drawn from outside. Once the eye is inside the sphere
/// the limb is no longer a circle, so there is no silhouette to draw — and the
/// "focus route" framing puts the camera deep inside on purpose.
double shellFade({required double radius, required double distance}) {
  if (radius <= 0) return 0;
  if (distance <= radius) return 0;
  return ((distance / radius - 1) / 0.15).clamp(0.0, 1.0);
}

/// Places [camera] for [mode] — what both "switch to this mode" and "recentre"
/// mean. Sets [Camera3D.mode] as well as the position, so a caller cannot leave
/// the two out of sync.
///
/// - [CameraMode.orbit]: look at the ship from a fixed standoff.
/// - [CameraMode.cockpit]: sit at the ship (the caller aims it).
/// - [CameraMode.overview]: look at Sol (the origin) from outside the boundary
///   sphere. This is also the way back out of a focused route.
///
/// [overviewDistance] is passed in rather than derived here because it depends
/// on the viewport, which only the page knows.
void placeCamera(
  Camera3D camera, {
  required CameraMode mode,
  required Vec3 shipPosition,
  required double overviewDistance,
  double orbitDistance = 520,
}) {
  camera.mode = mode;
  switch (mode) {
    case CameraMode.overview:
      camera.target = const Vec3(0, 0, 0);
      camera.distance = overviewDistance;
    case CameraMode.orbit:
      camera.target = shipPosition;
      camera.distance = orbitDistance;
    case CameraMode.cockpit:
      camera.eyeOverride = shipPosition;
  }
}

/// Fraction of the viewport's short edge that a focused route spans.
const double kRouteFrameFraction = 0.6;

/// Frames the route [from]→[to] so it spans [kRouteFrameFraction] of
/// [viewport]'s short edge, aiming the camera at the route's midpoint.
///
/// The floor keeps a degenerate (zero-length) route from collapsing the camera
/// onto the target.
void placeCameraForRoute(
  Camera3D camera, {
  required Vec3 from,
  required Vec3 to,
  required Size2 viewport,
  required double fovDegrees,
}) {
  final lengthWorld = (to - from).length;
  final focal = focalFor(viewport, fovDegrees);
  final shortEdge = math.min(viewport.width, viewport.height);
  camera.target = (from + to) * 0.5;
  camera.distance = math.max(
      lengthWorld * focal / (kRouteFrameFraction * shortEdge), kMinZoomDistance);
}

/// Zoom-in limit for every mode, in world units. Shared so the page's clamp and
/// the route-focus framing cannot drift apart.
const double kMinZoomDistance = 70;

/// Zoom-out limit for [CameraMode.orbit] and [CameraMode.cockpit].
const double kOrbitMaxDistance = 1800;

/// The overview zoom-out limit is this multiple of the universe radius.
const double kOverviewMaxDistanceFactor = 5;

/// Zoom-out limit for [mode], in world units — the upper end of the page's
/// drag-zoom clamp.
///
/// Overview is bounded by the framing distance, which is viewport-dependent: a
/// landscape viewport frames the sphere at 2.3R and a portrait one at 4.15R. A
/// bound picked by eye for landscape would sit *inside* the portrait framing
/// distance, so entering the mode on a phone would clamp the camera closer than
/// the framing and slice the shell open. Deriving it from R is the fix.
///
/// A zero-radius universe (empty catalogue) must still yield a valid clamp
/// range — `num.clamp` throws when the upper limit is below the lower one — so
/// the result never drops below [kMinZoomDistance].
double maxDistanceFor(CameraMode mode, double universeRadiusWorld) {
  if (mode != CameraMode.overview) return kOrbitMaxDistance;
  return math.max(
      kMinZoomDistance, kOverviewMaxDistanceFactor * universeRadiusWorld);
}
