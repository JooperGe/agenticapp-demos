import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/hyg_catalog.dart';
import '../../data/models/journey.dart';
import '../widgets/planet_disc.dart';
import 'camera3d.dart';
import 'galaxy3d_scene.dart';

/// Renders the 3D galaxy to a 2D canvas via perspective projection + painter's
/// algorithm. This is the core of the "2D-faked 3D": depth-sorted draw order,
/// perspective sizing and brightness falloff are what read as real volume.
class Galaxy3DPainter extends CustomPainter {
  Galaxy3DPainter({
    required this.scene,
    required this.camera,
    required this.selectedId,
    required this.shipPosition,
    required this.sensorRange,
    required this.journey,
    required this.journeyProgress,
    required this.repaint,
  }) : super(repaint: repaint);

  final Galaxy3DScene scene;
  final Camera3D camera;
  final String? selectedId;
  final Vec3 shipPosition;

  /// How far (world units) the current ship's sensors resolve detail.
  final double sensorRange;
  final Journey? journey;
  final double journeyProgress;
  final Listenable repaint;

  @override
  void paint(Canvas canvas, Size size) {
    final vp = Size2(size.width, size.height);

    // Star backdrop: fast path over the real HYG field plus any extra galaxies.
    if (scene.hyg != null) {
      _drawStarField(canvas, size, scene.hyg!, 5000);
    }
    for (final g in scene.extraGalaxies) {
      _drawStarField(canvas, size, g, 5200);
    }

    // Planets (billboarded procedural discs), depth-sorted among themselves.
    final calls = <_Draw>[];
    if (scene.hyg == null) {
      for (final s in scene.stars) {
        final pr = camera.project(s.position, vp);
        if (!pr.visible) continue;
        final dist = (s.position - shipPosition).length;
        calls.add(_Draw(pr.depth, (c) => _drawStar(c, s, pr, dist)));
      }
    }
    for (final sp in scene.planets) {
      final pr = camera.project(sp.position, vp);
      if (!pr.visible) continue;
      final dist = (sp.position - shipPosition).length;
      calls.add(_Draw(pr.depth, (c) => _drawPlanet(c, sp, pr, dist)));
    }

    calls.sort((a, b) => b.depth.compareTo(a.depth));

    _drawRoute(canvas, vp);
    for (final d in calls) {
      d.draw(canvas);
    }
    if (scene.hyg != null) _drawFieldLabels(canvas, size, scene.hyg!);
    for (final g in scene.extraGalaxies) {
      _drawFieldLabels(canvas, size, g);
    }
    _drawShip(canvas, vp);
  }

  /// Allocation-free render of a packed star field (the real HYG catalogue or a
  /// synthetic galaxy). Precomputes the camera basis once, then iterates with
  /// inline projection. Stars are pre-sorted brightest-first, so [maxDraw]
  /// keeps the most important stars and bounds the work regardless of zoom.
  void _drawStarField(Canvas canvas, Size size, HygStars field, int maxDraw) {
    final hyg = field;
    const near = 1.0;

    // Camera basis as plain doubles.
    final f = camera.forward.normalized;
    var right = f.cross(Vec3.up);
    if (right.length < 1e-6) right = const Vec3(1, 0, 0);
    right = right.normalized;
    final up = right.cross(f).normalized;
    final eye = camera.eye;
    final focal = (size.height / 2) / math.tan(camera.fovDegrees * math.pi / 360);
    final cx = size.width / 2, cy = size.height / 2;
    final fx = f.x, fy = f.y, fz = f.z;
    final rx = right.x, ry = right.y, rz = right.z;
    final ux = up.x, uy = up.y, uz = up.z;

    final xyz = hyg.xyz;
    final mag = hyg.mag;
    final color = hyg.color;
    final paint = Paint();
    var drawn = 0;
    for (var i = 0; i < hyg.count && drawn < maxDraw; i++) {
      final relx = xyz[i * 3] - eye.x;
      final rely = xyz[i * 3 + 1] - eye.y;
      final relz = xyz[i * 3 + 2] - eye.z;
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
      final m = mag[i];
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

  /// Labels only the brightest named stars, so famous landmarks (Sirius, Vega,
  /// Arcturus, the synthetic galaxy's core…) are identifiable without flooding
  /// the view with text.
  void _drawFieldLabels(Canvas canvas, Size size, HygStars field) {
    final vp = Size2(size.width, size.height);
    for (final n in field.named.values) {
      if (n.magnitude > 1.6) continue;
      final pr = camera.project(n.position, vp);
      if (!pr.visible) continue;
      _label(canvas, pr.screen + const Offset(6, -6), n.name,
          StarColors.muted.withValues(alpha: 0.8), 10);
    }
  }

  void _drawStar(Canvas canvas, SceneStar s, Projected pr, double dist) {
    // Brightness from magnitude; dimmer the farther past the sensor range.
    final base = (1.6 - (s.magnitude / 8)).clamp(0.12, 1.0);
    final rangeFade =
        dist <= sensorRange ? 1.0 : (sensorRange / dist).clamp(0.25, 1.0);
    final alpha = (base * rangeFade).clamp(0.0, 1.0);
    var radius = (0.6 + base * 2.4) * (0.6 + pr.scale * 40).clamp(0.6, 2.4);
    if (s.isSun) radius *= 1.6;

    final color = Color(s.color).withValues(alpha: alpha);
    if (s.magnitude < 2 || s.isSun) {
      // Bright stars get a soft bloom.
      canvas.drawCircle(
        pr.screen,
        radius * 3.2,
        Paint()
          ..color = color.withValues(alpha: alpha * 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
    canvas.drawCircle(pr.screen, radius, Paint()..color = color);

    // Label the brightest real stars when they are reasonably close in.
    if (s.name != null && s.magnitude < 1.6 && pr.scale > 0.015) {
      _label(canvas, pr.screen + const Offset(6, -6), s.name!,
          StarColors.muted.withValues(alpha: alpha), 10);
    }
  }

  void _drawPlanet(Canvas canvas, ScenePlanet sp, Projected pr, double dist) {
    final planet = sp.planet;
    final resolved = dist <= sensorRange;
    // True perspective sizing: give each planet a world-space radius and let
    // the projection's scale factor (focal / depth) do the work, so discs grow
    // when you zoom/approach and shrink into the distance — instead of all
    // clamping to one size. Hero worlds read a little larger.
    final worldRadius = planet.featured ? 16.0 : 10.0;
    final diameter = (worldRadius * 2 * pr.scale).clamp(1.5, 460.0);

    if (!resolved) {
      // Beyond this ship's sensor range: an unidentified blip, not a world.
      canvas.drawCircle(
        pr.screen,
        3,
        Paint()..color = StarColors.faint.withValues(alpha: 0.6),
      );
      return;
    }

    // Selection / destination ring.
    final isSelected = planet.id == selectedId;
    final isDestination = journey?.destinationPlanetId == planet.id;
    if (isSelected || isDestination) {
      canvas.drawCircle(
        pr.screen,
        diameter / 2 + 8,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = isDestination ? StarColors.gold : StarColors.cyan,
      );
    }

    // Reuse the exact procedural planet art, scaled by depth.
    canvas.save();
    canvas.translate(pr.screen.dx - diameter / 2, pr.screen.dy - diameter / 2);
    PlanetPainter(
      seedColor: Color(planet.seedColor),
      type: planet.type,
      noiseSeed: planet.id.hashCode,
      glow: diameter > 22,
    ).paint(canvas, Size(diameter, diameter));
    canvas.restore();

    // Name only for featured / larger discs to limit clutter.
    if ((planet.featured || diameter > 26) && diameter > 12) {
      _label(
        canvas,
        pr.screen + Offset(0, diameter / 2 + 2),
        planet.name,
        StarColors.offWhite,
        11,
        center: true,
      );
    }
  }

  void _drawRoute(Canvas canvas, Size2 vp) {
    final j = journey;
    if (j == null) return;
    final from = scene.positionOf(j.originPlanetId);
    final to = scene.positionOf(j.destinationPlanetId);
    final pf = camera.project(from, vp);
    final pt = camera.project(to, vp);
    if (!pf.visible || !pt.visible) return;
    canvas.drawLine(
      pf.screen,
      pt.screen,
      Paint()
        ..color = StarColors.cyan.withValues(alpha: 0.6)
        ..strokeWidth = 1.5,
    );
    final marker = Offset.lerp(pf.screen, pt.screen, journeyProgress)!;
    canvas.drawCircle(marker, 4, Paint()..color = StarColors.gold);
  }

  void _drawShip(Canvas canvas, Size2 vp) {
    if (camera.mode == CameraMode.cockpit) return; // we ARE the ship
    final pr = camera.project(shipPosition, vp);
    if (!pr.visible) return;
    canvas.drawCircle(
      pr.screen,
      5,
      Paint()..color = StarColors.offWhite,
    );
    canvas.drawCircle(
      pr.screen,
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = StarColors.cyan,
    );
  }

  void _label(Canvas canvas, Offset at, String text, Color color, double size,
      {bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            color: color, fontSize: size, fontWeight: FontWeight.w600),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final offset = center ? at - Offset(tp.width / 2, 0) : at;
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(Galaxy3DPainter old) => true;
}

class _Draw {
  _Draw(this.depth, this.draw);
  final double depth;
  final void Function(Canvas) draw;
}

/// Hit-tests a tap against planets by projecting them and returning the nearest
/// within [sensorRange] and a screen-space threshold. Shared with the page so
/// selection uses the identical projection the painter draws with.
String? pickPlanet({
  required Galaxy3DScene scene,
  required Camera3D camera,
  required Size size,
  required Offset tap,
  required Vec3 shipPosition,
  required double sensorRange,
}) {
  final vp = Size2(size.width, size.height);
  String? best;
  var bestDist = 44.0; // generous tap radius
  for (final sp in scene.planets) {
    final dist = (sp.position - shipPosition).length;
    if (dist > sensorRange) continue;
    final pr = camera.project(sp.position, vp);
    if (!pr.visible) continue;
    final d = (pr.screen - tap).distance;
    if (d < bestDist) {
      bestDist = d;
      best = sp.planet.id;
    }
  }
  return best;
}
