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
    this.parkedPlanetId,
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

  /// The planet the ship is parked at — the only one rendered as a lit disc.
  final String? parkedPlanetId;

  @override
  void paint(Canvas canvas, Size size) {
    final vp = Size2(size.width, size.height);

    // The host star (nearest star) lights the parked planet and renders as an
    // intense point of light rather than a disc — physically, at light-year
    // distances a star is a point however bright.
    final host = _findHostStar();
    Offset? hostScreen;
    if (host != null) {
      final pr = camera.project(host.$1, vp);
      if (pr.visible) hostScreen = pr.screen;
    }

    // Star backdrop: fast path over the real HYG field plus any extra galaxies.
    if (scene.hyg != null) {
      _drawStarField(canvas, size, scene.hyg!, 5000);
    }
    for (final g in scene.extraGalaxies) {
      _drawStarField(canvas, size, g, 5200);
    }
    if (host != null && hostScreen != null) {
      _drawHostStar(canvas, hostScreen, host.$2);
    }

    // Planets. Only the parked planet is a lit disc; the rest are points.
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
      calls.add(_Draw(pr.depth, (c) => _drawPlanet(c, sp, pr, dist, hostScreen)));
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

  /// Nearest star to the ship (world position, packed colour), within a few
  /// light-years — the system's sun. Null when drifting far from any star.
  (Vec3, int)? _findHostStar() {
    final ws = scene.worldScale;
    final maxR = 5.0 * ws;
    var best2 = maxR * maxR;
    Vec3? bestPos;
    var bestColor = 0xFFFFFFFF;
    void scan(HygStars f) {
      for (var i = 0; i < f.count; i++) {
        final wx = f.xyz[i * 3] * ws;
        final wy = f.xyz[i * 3 + 1] * ws;
        final wz = f.xyz[i * 3 + 2] * ws;
        final dx = wx - shipPosition.x,
            dy = wy - shipPosition.y,
            dz = wz - shipPosition.z;
        final d2 = dx * dx + dy * dy + dz * dz;
        if (d2 < best2) {
          best2 = d2;
          bestPos = Vec3(wx, wy, wz);
          bestColor = f.color[i];
        }
      }
    }

    final hyg = scene.hyg;
    if (hyg != null) scan(hyg);
    for (final g in scene.extraGalaxies) {
      scan(g);
    }
    return bestPos == null ? null : (bestPos!, bestColor);
  }

  /// Allocation-free render of a packed star field (the real HYG catalogue or a
  /// synthetic galaxy). Precomputes the camera basis once, then iterates with
  /// inline projection. Stars are pre-sorted brightest-first, so [maxDraw]
  /// keeps the most important stars and bounds the work regardless of zoom.
  void _drawStarField(Canvas canvas, Size size, HygStars field, int maxDraw) {
    final hyg = field;
    const near = 1.0;
    // Star catalogue positions are in light-years; everything else in the
    // scene (planets, ship, camera) is in world units (ly × worldScale), so
    // scale stars to match — otherwise the ship ends up far outside the star
    // field it's supposed to be sitting inside.
    final ws = scene.worldScale;

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
      final m = mag[i];
      // Every star — including the system's sun — is a point at these
      // distances; the host just gets an extra glow pass (see _drawHostStar).
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

  /// The system's sun as an intense *point* of light with layered bloom — a
  /// star at light-year range has no visible disc, however bright, so this is a
  /// bright core plus glow rather than a big sphere.
  void _drawHostStar(Canvas canvas, Offset at, int argb) {
    final c = Color(argb);
    // Outer soft halo.
    canvas.drawCircle(
      at,
      64,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[c.withValues(alpha: 0.5), c.withValues(alpha: 0.0)],
        ).createShader(Rect.fromCircle(center: at, radius: 64))
        ..blendMode = BlendMode.screen,
    );
    // Inner bright bloom.
    canvas.drawCircle(
      at,
      22,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            Colors.white.withValues(alpha: 0.95),
            c.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: at, radius: 22))
        ..blendMode = BlendMode.screen,
    );
    // Hot core point.
    canvas.drawCircle(at, 3.2, Paint()..color = Colors.white);
  }

  /// Labels only the brightest named stars, so famous landmarks (Sirius, Vega,
  /// Arcturus, the synthetic galaxy's core…) are identifiable without flooding
  /// the view with text.
  void _drawFieldLabels(Canvas canvas, Size size, HygStars field) {
    final vp = Size2(size.width, size.height);
    final ws = scene.worldScale;
    for (final n in field.named.values) {
      if (n.magnitude > 1.6) continue;
      final pr = camera.project(n.position * ws, vp);
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

  void _drawPlanet(
      Canvas canvas, ScenePlanet sp, Projected pr, double dist, Offset? hostScreen) {
    final planet = sp.planet;
    final isSelected = planet.id == selectedId;
    final isDestination = journey?.destinationPlanetId == planet.id;
    final isParked = planet.id == parkedPlanetId;

    if (!isParked) {
      // Every other world — siblings and other systems alike — is a point of
      // light from here (like how Venus/Jupiter look from Earth), not a disc.
      if (dist > sensorRange) return;
      final r = (1.6 + 10.0 * pr.scale).clamp(1.6, 3.4);
      if (isSelected || isDestination) {
        canvas.drawCircle(
          pr.screen,
          r + 6,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = isDestination ? StarColors.gold : StarColors.cyan,
        );
      }
      canvas.drawCircle(
        pr.screen,
        r,
        Paint()..color = Color(planet.seedColor).withValues(alpha: 0.9),
      );
      return;
    }

    // The parked planet: the one foreground disc, lit from the host-star side
    // with a day/night terminator (a phase), as it would really appear.
    final worldRadius = planet.featured ? 12.0 : 8.0;
    final diameter = (worldRadius * 2 * pr.scale).clamp(8.0, 460.0);
    final r = diameter / 2;

    if (isSelected || isDestination) {
      canvas.drawCircle(
        pr.screen,
        r + 10,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = isDestination ? StarColors.gold : StarColors.cyan,
      );
    }

    canvas.save();
    canvas.translate(pr.screen.dx - r, pr.screen.dy - r);
    PlanetPainter(
      seedColor: Color(planet.seedColor),
      type: planet.type,
      noiseSeed: planet.id.hashCode,
      glow: diameter > 22,
    ).paint(canvas, Size(diameter, diameter));
    canvas.restore();

    _drawPhaseShadow(canvas, pr.screen, r, hostScreen);

    _label(
      canvas,
      pr.screen + Offset(0, r + 4),
      planet.name,
      StarColors.offWhite,
      12,
      center: true,
    );
  }

  /// Darkens the hemisphere of the parked planet facing away from the host
  /// star, producing a crescent/gibbous phase instead of a uniformly lit disc.
  void _drawPhaseShadow(
      Canvas canvas, Offset center, double r, Offset? hostScreen) {
    // Light direction in screen space (toward the star); default upper-left.
    var lx = -0.5, ly = -0.5;
    if (hostScreen != null) {
      final dx = hostScreen.dx - center.dx, dy = hostScreen.dy - center.dy;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len > 1e-3) {
        lx = dx / len;
        ly = dy / len;
      }
    }
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: r)));
    final lit = center + Offset(lx, ly) * r;
    final dark = center - Offset(lx, ly) * r;
    canvas.drawRect(
      Rect.fromCircle(center: center, radius: r),
      Paint()
        ..shader = ui.Gradient.linear(
          lit,
          dark,
          <Color>[
            Colors.black.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.55),
            Colors.black.withValues(alpha: 0.82),
          ],
          <double>[0.0, 0.42, 0.72, 1.0],
        ),
    );
    canvas.restore();
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

/// Hit-tests a tap against the *in-system* planet discs (the only planets
/// drawn). Returns the nearest planet id within a screen-space threshold.
String? pickPlanet({
  required Galaxy3DScene scene,
  required Camera3D camera,
  required Size size,
  required Offset tap,
  required Vec3 shipPosition,
  required double sensorRange,
}) {
  final vp = Size2(size.width, size.height);
  final inSystemRange = 6.0 * scene.worldScale;
  String? best;
  var bestDist = 44.0; // generous tap radius
  for (final sp in scene.planets) {
    final dist = (sp.position - shipPosition).length;
    if (dist > inSystemRange) continue; // only in-system discs are tappable
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

/// Hit-tests a tap against stars (real + extra galaxies), returning the nearest
/// star's stable id within [sensorRange] of the ship and a screen threshold —
/// used to open a star's system view and travel there.
int? pickStarId({
  required Galaxy3DScene scene,
  required Camera3D camera,
  required Size size,
  required Offset tap,
  required Vec3 shipPosition,
  required double sensorRange,
}) {
  final vp = Size2(size.width, size.height);
  final ws = scene.worldScale;
  final sensor2 = sensorRange * sensorRange;
  int? best;
  var bestDist = 40.0;
  void scan(List<HygStars> fields) {
    for (final field in fields) {
      for (var i = 0; i < field.count; i++) {
        final wx = field.xyz[i * 3] * ws;
        final wy = field.xyz[i * 3 + 1] * ws;
        final wz = field.xyz[i * 3 + 2] * ws;
        final sdx = wx - shipPosition.x,
            sdy = wy - shipPosition.y,
            sdz = wz - shipPosition.z;
        if (sdx * sdx + sdy * sdy + sdz * sdz > sensor2) continue;
        final pr = camera.project(Vec3(wx, wy, wz), vp);
        if (!pr.visible) continue;
        final d = (pr.screen - tap).distance;
        if (d < bestDist) {
          bestDist = d;
          best = field.starId[i];
        }
      }
    }
  }

  final hyg = scene.hyg;
  scan(<HygStars>[?hyg, ...scene.extraGalaxies]);
  return best;
}
