import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/theme.dart';
import 'camera3d.dart';

/// The heading as a compass-style readout: a bearing in the galactic plane and
/// an elevation above it.
///
/// Bearing is measured from +Z toward +X, which is the convention
/// [Camera3D.forward] already uses (`yaw == atan2(x, z)`). Using the same one
/// matters: a ship aimed at a star has to read the bearing the star map would
/// give that star, or the readout is decoration.
///
/// Elevation is signed — `+45°` up, `−45°` down — rather than a second scale
/// measured from a pole, so "which way is up" is never ambiguous. The minus is
/// U+2212, not a hyphen: it lines up with the digits at this size.
({String bearing, String elevation}) headingLabel(Vec3 heading) {
  final d = heading.normalized;
  if (d.length <= 0) return (bearing: '—', elevation: '—');
  var bearing = math.atan2(d.x, d.z) * 180 / math.pi;
  if (bearing < 0) bearing += 360;
  // `atan2(-0.0, z)` is `-0.0`, which is not `< 0`, so it skips the wrap above
  // and `toStringAsFixed` would render the bearing `-0`. Fold it to `+0`.
  if (bearing == 0) bearing = 0;
  final elevation = math.asin(d.y.clamp(-1.0, 1.0)) * 180 / math.pi;
  final sign = elevation < 0 ? '−' : '+';
  return (
    bearing: '${bearing.toStringAsFixed(0)}°',
    elevation: '$sign${elevation.abs().toStringAsFixed(0)}°',
  );
}

/// The angle between the ship's current course and a proposed heading, in whole
/// degrees.
///
/// The same angle `GameController.turnAngleTo` prices the turn on — same
/// normalisation, same `acos` of the clamped dot product — so the number the
/// readout shows and the number the fee is computed from cannot drift apart.
///
/// Whole degrees because it is a readout, not a measurement: the fee is a step
/// function of the angle, so quoting `36.87°` next to a `63 EN` price invites
/// the reader to check arithmetic that does not exist.
///
/// A zero-length [current] means the ship has no course (it is parked), which
/// `turnAngleTo` reads as 0; a zero-length [proposed] means the caller has no
/// heading to offer. Both are 0.
int headingDeviationDegrees({
  required Vec3 current,
  required Vec3 proposed,
}) {
  final from = current.normalized;
  final to = proposed.normalized;
  if (from.length <= 0 || to.length <= 0) return 0;
  return (math.acos(from.dot(to).clamp(-1.0, 1.0)) * 180 / math.pi).round();
}

/// Where [world] lands on screen, in logical pixels, or null when it is at or
/// behind the camera's near plane.
///
/// Thin wrapper over [Camera3D.project] so the HUD and the scene painter cannot
/// disagree about the projection — there is one convention in this codebase and
/// it lives in `camera3d.dart`. The null case is the whole reason this exists:
/// `Camera3D.project` culls a point behind the eye to `Projected.hidden`, whose
/// `screen` is `Offset.zero`, so passing that through would park the marker in
/// the top-left corner of the screen.
Offset? hudMarkerPoint({
  required Camera3D camera,
  required Vec3 world,
  required Size2 viewport,
}) {
  final p = camera.project(world, viewport);
  return p.visible ? p.screen : null;
}

/// How far the marker's world point sits ahead of the eye. Only the direction
/// matters for where it lands — the screen offset is `focal · tan(angle)`,
/// independent of distance — but the point has to be beyond the near plane.
const double _headingMarkerDistance = 400;

/// Nudges the marked direction toward the aim so a course exactly abeam still
/// has a forward component to project.
///
/// `Camera3D.project` culls at `camZ <= 1.0`, and at [_headingMarkerDistance] the
/// raw `camZ` is only `400·cos θ` — so without the nudge every course from
/// `acos(1/400) = 89.86°` off the aim out to dead astern is culled, which is the
/// whole rear hemisphere and not a sliver around abeam. The nudge moves that
/// boundary out to 104.33°, and that ~14.5° is what it buys.
const double _headingMarkerForwardNudge = 0.25;

/// Where a HUD point lands once it is kept clear of the cockpit frame and the
/// bottom control panel, plus whether it had to move.
///
/// The clamp is the point: [hudMarkerPoint] returns null only at or behind the
/// near plane, so a point in front of the camera but outside the field of view
/// projects to coordinates outside the canvas, where drawing is invisible. A
/// clamped point still answers "which way", which is the question the player is
/// asking.
///
/// Shared by every HUD layer so the two painters cannot disagree about the safe
/// area. `_CockpitPainter` insets its window by 14 on the sides and a further
/// 48 / 40 at the top and bottom; the bottom margin also has to clear
/// `_BottomControls`, the panel pinned to the bottom of the screen.
({Offset at, bool offScreen}) clampHudPoint(Offset at, Size2 size) {
  final clamped = Offset(
    at.dx.clamp(26.0, size.width - 26.0),
    at.dy.clamp(74.0, size.height - 132.0),
  );
  return (at: clamped, offScreen: clamped != at);
}

/// Where the current-heading triangle sits, or null when there is no course to
/// mark.
///
/// A heading still culled after the nudge — anything past 104.33° off the aim, a
/// 75.7° band around dead astern — is pinned to the bottom edge, the conventional
/// "behind you" position. The readout beside it carries the exact angle, so
/// nothing is lost that the player needs.
///
/// Reports `offScreen` alongside the point rather than returning the point alone.
/// The point is clamped here, so a caller that re-clamped it would get
/// `clamped == at` and an `offScreen` of `false` in every reachable state —
/// which is how the triangle's dimming would come to be dead code.
({Offset at, bool offScreen})? headingMarkerPoint({
  required Camera3D camera,
  required Vec3 heading,
  required Size2 viewport,
}) {
  final h = heading.normalized;
  if (h.length <= 0) return null;
  final nudged = (h + camera.forward * _headingMarkerForwardNudge).normalized;
  final at = hudMarkerPoint(
    camera: camera,
    world: camera.eye + nudged * _headingMarkerDistance,
    viewport: viewport,
  );
  if (at == null) {
    return clampHudPoint(Offset(viewport.width / 2, viewport.height), viewport);
  }
  return clampHudPoint(at, viewport);
}

/// One thing worth pointing at from the cockpit.
class HudMarker {
  const HudMarker({
    required this.world,
    required this.label,
    required this.color,
  });

  final Vec3 world;
  final String label;
  final Color color;
}

/// Draws a ring and a label for each marker, clamped to the viewport edge when
/// the marker is outside the field of view.
///
/// The clamping is the point. [hudMarkerPoint] returns null only for a point at
/// or behind the camera's near plane, so a point that is in front of the camera
/// but outside the field of view projects to coordinates outside the canvas —
/// drawing there is invisible, which is exactly the defect the free-cruise
/// feature exists to fix. A clamped marker still answers "which way", which is
/// the question the player is asking.
class CockpitHudPainter extends CustomPainter {
  const CockpitHudPainter({
    required this.camera,
    required this.markers,
    this.heading,
    this.headingColor = StarColors.cyan,
  });

  final Camera3D camera;
  final List<HudMarker> markers;

  /// The ship's current course, marked with a filled triangle. Null when the
  /// bar is not offering a turn — parked, or dormant — which is the same
  /// condition the bar's own button uses.
  final Vec3? heading;
  final Color headingColor;

  @override
  void paint(Canvas canvas, Size size) {
    final vp = Size2(size.width, size.height);
    for (final m in markers) {
      final at = hudMarkerPoint(camera: camera, world: m.world, viewport: vp);
      if (at == null) continue;

      // Keep clear of the cockpit frame — `_CockpitPainter` insets its window
      // by 14 on the sides and by a further 48 / 40 at the top and bottom — and
      // of `_BottomControls`, the panel pinned to the bottom of the screen.
      final c = clampHudPoint(at, vp);
      final offScreen = c.offScreen;

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = offScreen ? 1.2 : 1.8
        ..color = m.color.withValues(alpha: offScreen ? 0.45 : 0.85);

      if (offScreen) {
        // A chevron pointing the way, so an off-screen marker reads as a
        // direction rather than as a target sitting at the edge.
        final dir = at - c.at;
        final len = dir.distance;
        if (len > 1e-6) {
          final u = dir / len;
          final tip = c.at + u * 11;
          final left = c.at + Offset(-u.dy, u.dx) * 7;
          final right = c.at + Offset(u.dy, -u.dx) * 7;
          canvas.drawPath(
            Path()
              ..moveTo(tip.dx, tip.dy)
              ..lineTo(left.dx, left.dy)
              ..lineTo(right.dx, right.dy)
              ..close(),
            paint,
          );
        }
      } else {
        canvas.drawCircle(c.at, 9, paint);
        canvas.drawCircle(c.at, 2, Paint()..color = m.color);
      }

      final text = TextPainter(
        text: TextSpan(
          text: m.label,
          style: TextStyle(
            color: m.color.withValues(alpha: offScreen ? 0.5 : 0.85),
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // The label sits to the right of the marker, but a marker clamped at the
      // right edge would run its label past `size.width`, where it is clipped
      // away; flip it to the left of the marker when it would overflow.
      final labelX = c.at.dx + 14 + text.width > size.width
          ? c.at.dx - 14 - text.width
          : c.at.dx + 14;
      text.paint(canvas, Offset(labelX, c.at.dy - 6));
    }

    final h = heading?.normalized;
    if (h != null && h.length > 0) {
      final p = headingMarkerPoint(camera: camera, heading: h, viewport: vp);
      if (p != null) {
        // Read off `p`, not recomputed: the point is already clamped, so
        // `clampHudPoint(p.at, vp).offScreen` is `false` by construction and the
        // dimming below would never fire.
        final at = p.at;
        final paint = Paint()
          ..color = headingColor.withValues(alpha: p.offScreen ? 0.45 : 0.9);
        // A filled triangle, deliberately unlike the ring markers: the current
        // course must never read as a destination.
        canvas.drawPath(
          Path()
            ..moveTo(at.dx, at.dy - 9)
            ..lineTo(at.dx - 7.5, at.dy + 5.5)
            ..lineTo(at.dx + 7.5, at.dy + 5.5)
            ..close(),
          paint,
        );
      }
    }
  }

  // Always true: `Vec3` has no `==`, so any equality check here would compare
  // identities rather than positions.
  @override
  bool shouldRepaint(CockpitHudPainter oldDelegate) => true;
}
