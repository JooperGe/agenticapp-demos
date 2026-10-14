import 'dart:math' as math;

import 'package:flutter/widgets.dart';

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
  const CockpitHudPainter({required this.camera, required this.markers});

  final Camera3D camera;
  final List<HudMarker> markers;

  @override
  void paint(Canvas canvas, Size size) {
    final vp = Size2(size.width, size.height);
    for (final m in markers) {
      final at = hudMarkerPoint(camera: camera, world: m.world, viewport: vp);
      if (at == null) continue;

      // Keep clear of the cockpit frame — `_CockpitPainter` insets its window
      // by 14 on the sides and by a further 48 / 40 at the top and bottom — and
      // of `_BottomControls`, the panel pinned to the bottom of the screen.
      final clamped = Offset(
        at.dx.clamp(26.0, size.width - 26.0),
        at.dy.clamp(74.0, size.height - 132.0),
      );
      final offScreen = clamped != at;

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = offScreen ? 1.2 : 1.8
        ..color = m.color.withValues(alpha: offScreen ? 0.45 : 0.85);

      if (offScreen) {
        // A chevron pointing the way, so an off-screen marker reads as a
        // direction rather than as a target sitting at the edge.
        final dir = at - clamped;
        final len = dir.distance;
        if (len > 1e-6) {
          final u = dir / len;
          final tip = clamped + u * 11;
          final left = clamped + Offset(-u.dy, u.dx) * 7;
          final right = clamped + Offset(u.dy, -u.dx) * 7;
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
        canvas.drawCircle(clamped, 9, paint);
        canvas.drawCircle(clamped, 2, Paint()..color = m.color);
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
      // right edge would start its label past `size.width`, where it is clipped
      // away; flip it to the left of the marker when it would overflow.
      final labelX = clamped.dx + 14 + text.width > size.width
          ? clamped.dx - 14 - text.width
          : clamped.dx + 14;
      text.paint(canvas, Offset(labelX, clamped.dy - 6));
    }
  }

  // Always true: `Vec3` has no `==`, so any equality check here would compare
  // identities rather than positions.
  @override
  bool shouldRepaint(CockpitHudPainter oldDelegate) => true;
}
