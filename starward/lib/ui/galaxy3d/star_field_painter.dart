import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/hyg_catalog.dart';
import 'camera3d.dart';

/// 1 / ln(10) — converts natural logs to base-10 for the magnitude rescale.
const double _invLn10 = 0.4342944819032518;

/// [drawStarField]'s `maxDraw` for a synthetic galaxy, in the star map and the
/// universe overview alike.
///
/// The catalogue's own cap thins 109 000 stars down to a few thousand; a
/// synthetic galaxy is only a few thousand to begin with and is the subject of
/// the view, so it has to be drawn **whole**. Stars are pre-sorted
/// brightest-first and a galaxy's magnitude rises with radius, so clipping one
/// discards its faintest stars first — which is to say its outer disk, the very
/// fade that keeps it from ending in a hard edge. At the old 5200, SG-2 (6000
/// stars) lost its outer half and rendered to 292 ly of its 611 ly radius.
///
/// `test/synthetic_galaxy_test.dart` pins that every galaxy fits under it, so
/// adding a bigger one fails loudly here instead of silently truncating.
const int kGalaxyMaxDraw = 8000;

/// How one packed star field's magnitude becomes pixels: opacity, radius, and
/// the magnitude below which a star gets a glow pass.
///
/// A field's brightness range decides which of its colours a viewer actually
/// sees, so this has to be per-field. The real catalogue spans a handful of
/// magnitudes and is drawn as a sky; a synthetic galaxy spans 3.2–9.8 and is
/// the subject of the view, and under the catalogue's ramp every one of its
/// stars landed on the 0.5px radius floor at or near the 0.05 alpha floor —
/// flattened into one colour. See [galaxy].
class StarFieldStyle {
  const StarFieldStyle({
    this.alphaRef = 6.6,
    this.alphaSpan = 8.0,
    this.alphaBase = 0.12,
    this.alphaFloor = 0.05,
    this.radiusBase = 0.5,
    this.radiusRef = 3.0,
    this.radiusSpan = 0.33,
    this.radiusFloor = 0.5,
    this.radiusCeiling = 2.6,
    this.bloomBelow = 1.4,
  });

  /// Alpha falls to [alphaBase] at magnitude [alphaRef] and rises by
  /// 1/[alphaSpan] per magnitude brighter from there.
  final double alphaRef;
  final double alphaSpan;
  final double alphaBase;
  final double alphaFloor;

  /// Radius is [radiusBase] at [radiusRef] and grows by [radiusSpan] per
  /// magnitude brighter.
  final double radiusBase;
  final double radiusRef;
  final double radiusSpan;
  final double radiusFloor;
  final double radiusCeiling;

  /// Stars brighter than this get an extra blurred glow pass.
  final double bloomBelow;

  double alphaFor(double m) =>
      ((alphaRef - m) / alphaSpan + alphaBase).clamp(alphaFloor, 1.0);

  double radiusFor(double m) =>
      (radiusBase + (radiusRef - m) * radiusSpan)
          .clamp(radiusFloor, radiusCeiling);

  /// The ramp the painter has always used, for the real HYG catalogue. Every
  /// field is its default, so this reproduces the previous inline expressions
  /// exactly — `test/star_field_style_test.dart` pins the numbers.
  static const catalogue = StarFieldStyle();

  /// For a synthetic galaxy.
  ///
  /// The point is to **compress** the ramp, not to brighten it. A galaxy's
  /// bulge is 1.8–2.8 magnitudes brighter than its disk and its stars are warm,
  /// so any ramp with a wide dynamic range hands the warm core most of the
  /// light and the blue arms go unseen: SG-1's light-weighted mean colour came
  /// out `#e8d7be`, a warm beige, though 53% of its stars are blue. Raising the
  /// floor alone would not fix that either — it would lift the faint disk
  /// without narrowing the gap to the bulge. Measured on SG-1, across the
  /// galaxy's whole magnitude range the spread drops from 10.9× to 2.5×, the
  /// young (arm) share of the light rises 40.4% → 47.7%, and the stars pinned
  /// to the alpha floor fall 1558 → 1087 of 5200. The core still reads as a
  /// core because it is *dense* (14% of the stars inside 0.22 of the radius),
  /// not because it is bright.
  ///
  /// The radius ramp stays deliberately shallow for the same reason: radius is
  /// squared in the light each star contributes, so a steep "brighter is
  /// bigger" ramp amplifies the warm bulge exactly as alpha does. Measured, a
  /// radius ramp of 0.5–1.0 cost 4.3 points of young share on its own — more
  /// than the alpha ramp gained. Its job here is only to lift galaxy stars off
  /// the sub-pixel 0.5px floor they all sat on.
  ///
  /// Note that no ramp can make SG-1 read *blue*: even a perfectly flat one
  /// leaves the light-weighted mean at `#e1d7cb`, because the palette pools
  /// themselves bound how much blue there is to see. Widening the pools, and
  /// the star-forming knots that give the arms internal contrast, are separate
  /// changes.
  ///
  /// [bloomBelow] stays at the catalogue's 1.4, so no galaxy star blooms — the
  /// brightest is 3.2. Lowering it is the knob for a glowing core.
  static const galaxy = StarFieldStyle(
    alphaRef: 9.0,
    alphaSpan: 9.0,
    alphaBase: 0.15,
    alphaFloor: 0.32,
    radiusBase: 0.62,
    radiusRef: 9.0,
    radiusSpan: 0.02,
    radiusFloor: 0.62,
    radiusCeiling: 1.0,
  );
}

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
///
/// [style] is the field's own magnitude → pixel ramp. It defaults to the
/// catalogue's; the synthetic galaxies pass [StarFieldStyle.galaxy].
void drawStarField(
  Canvas canvas, {
  required Size size,
  required HygStars field,
  required Camera3D camera,
  required double worldScale,
  required int maxDraw,
  required bool distanceScaled,
  StarFieldStyle style = StarFieldStyle.catalogue,
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
    final alpha = style.alphaFor(m);
    final radius = style.radiusFor(m);
    paint.color = Color(color[i]).withValues(alpha: alpha);
    if (m < style.bloomBelow) {
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
