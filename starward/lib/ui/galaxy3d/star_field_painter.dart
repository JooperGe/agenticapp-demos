import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/hyg_catalog.dart';
import 'camera3d.dart';

/// 1 / ln(10) — converts natural logs to base-10 for the magnitude rescale.
const double _invLn10 = 0.4342944819032518;

/// The magnitude rescale shared by the hot loop and [apparentMagnitude].
///
/// Takes precomputed squared distances rather than a star, so the hot loop can
/// call it without allocating — it iterates up to 109k packed stars.
double _rescaledMagnitude(double magnitude, double distEye2, double distSol2) =>
    magnitude +
    2.5 * _invLn10 * math.log((distEye2 + 1e-12) / (distSol2 + 1e-12));

/// Allocation-free render of a packed star field (the real HYG catalogue or a
/// synthetic galaxy). Precomputes the camera basis once, then iterates with
/// inline projection. Stars are pre-sorted brightest-first, so [maxDraw] keeps
/// the most important stars and bounds the work regardless of zoom.
///
/// [distanceScaled] rescales each star's apparent magnitude to the viewer's
/// actual distance (brightness ∝ 1/d²), which is what makes the sky change as
/// the ship moves. It must be **false** for the universe-overview camera: from
/// outside the volume the eye sits ~73 000 world units from every star, which
/// dims the median catalogue star by 5 magnitudes — far past the alpha ramp's
/// saturation point — rendering the universe as a near-black ball.
void drawStarField(
  Canvas canvas, {
  required Size size,
  required HygStars field,
  required Camera3D camera,
  required double worldScale,
  required int maxDraw,
  required bool distanceScaled,
}) {
  const near = 1.0;
  // Star catalogue positions are in light-years; everything else in the scene
  // (planets, ship, camera) is in world units (ly × worldScale), so scale stars
  // to match — otherwise the ship ends up far outside the star field it's
  // supposed to be sitting inside.
  final ws = worldScale;

  // Camera basis as plain doubles.
  final f = camera.forward.normalized;
  var right = f.cross(Vec3.up);
  if (right.length < 1e-6) right = const Vec3(1, 0, 0);
  right = right.normalized;
  final up = right.cross(f).normalized;
  final eye = camera.eye;
  final focal = focalFor(Size2(size.width, size.height), camera.fovDegrees);
  final cx = size.width / 2, cy = size.height / 2;
  final fx = f.x, fy = f.y, fz = f.z;
  final rx = right.x, ry = right.y, rz = right.z;
  final ux = up.x, uy = up.y, uz = up.z;

  final xyz = field.xyz;
  final mag = field.mag;
  final color = field.color;
  final paint = Paint();
  var drawn = 0;
  for (var i = 0; i < field.count && drawn < maxDraw; i++) {
    final wx = xyz[i * 3] * ws;
    final wy = xyz[i * 3 + 1] * ws;
    final wz = xyz[i * 3 + 2] * ws;
    final relx = wx - eye.x;
    final rely = wy - eye.y;
    final relz = wz - eye.z;
    final camZ = relx * fx + rely * fy + relz * fz;
    if (camZ <= near) continue;
    final camX = relx * rx + rely * ry + relz * rz;
    final camY = relx * ux + rely * uy + relz * uz;
    final invZ = focal / camZ;
    final sx = cx + camX * invZ;
    final sy = cy - camY * invZ;
    if (sx < -8 || sx > size.width + 8 || sy < -8 || sy > size.height + 8) {
      continue;
    }
    // Apparent magnitude is distance-dependent (brightness ∝ 1/d²). The
    // catalogue value is as seen from Sol; rescale it to the viewer's actual
    // distance so moving through space changes which stars dominate the sky.
    final double m;
    if (distanceScaled) {
      final distEye2 = relx * relx + rely * rely + relz * relz;
      final distSol2 = wx * wx + wy * wy + wz * wz;
      m = _rescaledMagnitude(mag[i], distEye2, distSol2);
    } else {
      m = mag[i];
    }
    // Every star — including the system's sun — is a point at these distances;
    // the host just gets an extra glow pass (see Galaxy3DPainter._drawHostStar).
    final alpha = ((6.6 - m) / 8 + 0.12).clamp(0.05, 1.0);
    final radius = (0.5 + (3.0 - m) * 0.33).clamp(0.5, 2.6);
    paint.color = Color(color[i]).withValues(alpha: alpha);
    if (m < 1.4) {
      canvas.drawCircle(
        Offset(sx, sy),
        radius * 3,
        Paint()
          ..color = paint.color.withValues(alpha: alpha * 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
    canvas.drawCircle(Offset(sx, sy), radius, paint);
    drawn++;
  }
}

/// Apparent magnitude of [n] as seen from the camera, applying the same
/// distance rescale as [drawStarField] when [distanceScaled] is set.
double apparentMagnitude({
  required HygNamed n,
  required Camera3D camera,
  required double worldScale,
  required bool distanceScaled,
}) {
  if (!distanceScaled) return n.magnitude;
  final posW = n.position * worldScale;
  final rel = posW - camera.eye;
  return _rescaledMagnitude(n.magnitude, rel.dot(rel), posW.dot(posW));
}

/// Labels only the brightest named stars, so famous landmarks (Sirius, Vega,
/// Arcturus, the synthetic galaxy's core…) are identifiable without flooding
/// the view with text. Gated on the magnitude as seen from here when
/// [distanceScaled] is set, so the bright landmarks change with the ship.
void drawFieldLabels(
  Canvas canvas, {
  required Size size,
  required HygStars field,
  required Camera3D camera,
  required double worldScale,
  required bool distanceScaled,
  double maxMagnitude = 1.6,
}) {
  final vp = Size2(size.width, size.height);
  for (final n in field.named.values) {
    final m = apparentMagnitude(
      n: n,
      camera: camera,
      worldScale: worldScale,
      distanceScaled: distanceScaled,
    );
    if (m > maxMagnitude) continue;
    final pr = camera.project(n.position * worldScale, vp);
    if (!pr.visible) continue;
    drawTextLabel(canvas, pr.screen + const Offset(6, -6), n.name,
        StarColors.muted.withValues(alpha: 0.8), 10);
  }
}

/// Draws a small text label with the app's label styling. [center] centres the
/// text horizontally on [at] instead of starting there.
void drawTextLabel(
  Canvas canvas,
  Offset at,
  String text,
  Color color,
  double size, {
  bool center = false,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style:
          TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w600),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  final offset = center ? at - Offset(tp.width / 2, 0) : at;
  tp.paint(canvas, offset);
}
