import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models/planet.dart';

/// A procedurally painted planet disc — the single source of planet art across
/// the whole app (map, details, journey, exploration, log). Deliberately not a
/// flat colour circle: it layers a lit sphere, limb shading, an atmosphere
/// halo and type-specific surface detail so planets read as real worlds.
///
/// Everything derives from [Planet.seedColor] + [Planet.id], so a given planet
/// looks identical everywhere and on every launch. Drop-in bitmap art could
/// replace this later without changing call sites.
class PlanetDisc extends StatelessWidget {
  const PlanetDisc({
    super.key,
    required this.planet,
    required this.size,
    this.rotation = 0,
    this.glow = true,
  });

  final Planet planet;
  final double size;

  /// Surface rotation phase (radians) for subtle spin on live scenes.
  final double rotation;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: PlanetPainter(
          seedColor: Color(planet.seedColor),
          type: planet.type,
          noiseSeed: planet.id.hashCode,
          rotation: rotation,
          glow: glow,
        ),
      ),
    );
  }
}

class PlanetPainter extends CustomPainter {
  PlanetPainter({
    required this.seedColor,
    required this.type,
    required this.noiseSeed,
    this.rotation = 0,
    this.glow = true,
  });

  final Color seedColor;
  final PlanetType type;
  final int noiseSeed;
  final double rotation;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 * 0.78;
    final rng = math.Random(noiseSeed);

    // Atmosphere / outer glow.
    if (glow) {
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            seedColor.withValues(alpha: 0.42),
            seedColor.withValues(alpha: 0.0),
          ],
          stops: const <double>[0.55, 1.0],
        ).createShader(
            Rect.fromCircle(center: center, radius: radius * 1.5));
      canvas.drawCircle(center, radius * 1.5, glowPaint);
    }

    // Base lit sphere: light from the upper-left, shadow to lower-right.
    final lightDir = Offset(-0.45, -0.5);
    final bodyRect = Rect.fromCircle(center: center, radius: radius);
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment(lightDir.dx, lightDir.dy),
        radius: 1.1,
        colors: <Color>[
          _lighten(seedColor, 0.32),
          seedColor,
          _darken(seedColor, 0.55),
        ],
        stops: const <double>[0.0, 0.55, 1.0],
      ).createShader(bodyRect);
    canvas.drawCircle(center, radius, bodyPaint);

    // Clip subsequent surface detail to the sphere.
    canvas.save();
    canvas.clipPath(Path()..addOval(bodyRect));
    switch (type) {
      case PlanetType.dead:
        _paintCraters(canvas, center, radius, rng);
        break;
      case PlanetType.alive:
        _paintContinents(canvas, center, radius, rng);
        break;
      case PlanetType.civilization:
        _paintCityLights(canvas, center, radius, rng);
        break;
    }
    canvas.restore();

    // Terminator shadow (the unlit crescent) for a 3D read.
    final shadow = Paint()
      ..shader = RadialGradient(
        center: Alignment(-lightDir.dx, -lightDir.dy),
        radius: 1.0,
        colors: <Color>[
          Colors.black.withValues(alpha: 0.0),
          Colors.black.withValues(alpha: 0.55),
        ],
        stops: const <double>[0.45, 1.0],
      ).createShader(bodyRect);
    canvas.drawCircle(center, radius, shadow);

    // Rim light along the lit edge.
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.045
      ..color = _lighten(seedColor, 0.5).withValues(alpha: 0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawArc(
        bodyRect.deflate(radius * 0.02), math.pi * 0.9, math.pi * 0.9, false, rim);
  }

  // --- Surface detail per type --------------------------------------------

  void _paintCraters(
      Canvas canvas, Offset center, double radius, math.Random rng) {
    for (var i = 0; i < 9; i++) {
      final a = rng.nextDouble() * math.pi * 2;
      final d = rng.nextDouble() * radius * 0.8;
      final p = center + Offset(math.cos(a), math.sin(a)) * d;
      final r = radius * (0.06 + rng.nextDouble() * 0.14);
      canvas.drawCircle(
          p, r, Paint()..color = _darken(seedColor, 0.3).withValues(alpha: 0.5));
      canvas.drawCircle(
          p.translate(-r * 0.2, -r * 0.2),
          r * 0.8,
          Paint()..color = _lighten(seedColor, 0.1).withValues(alpha: 0.25));
    }
  }

  void _paintContinents(
      Canvas canvas, Offset center, double radius, math.Random rng) {
    final land = _darken(seedColor, 0.18);
    for (var i = 0; i < 6; i++) {
      final a = rng.nextDouble() * math.pi * 2;
      final d = rng.nextDouble() * radius * 0.7;
      final p = center + Offset(math.cos(a), math.sin(a)) * d;
      final blob = Path();
      final blobR = radius * (0.18 + rng.nextDouble() * 0.22);
      const sides = 7;
      for (var s = 0; s <= sides; s++) {
        final ang = s / sides * math.pi * 2;
        final rr = blobR * (0.7 + rng.nextDouble() * 0.5);
        final pt = p + Offset(math.cos(ang), math.sin(ang)) * rr;
        if (s == 0) {
          blob.moveTo(pt.dx, pt.dy);
        } else {
          blob.lineTo(pt.dx, pt.dy);
        }
      }
      blob.close();
      canvas.drawPath(
          blob, Paint()..color = land.withValues(alpha: 0.55));
    }
  }

  void _paintCityLights(
      Canvas canvas, Offset center, double radius, math.Random rng) {
    // Faint banding plus warm night-side lights clustered on the dark edge.
    final glowPaint = Paint()..color = _lighten(seedColor, 0.4).withValues(alpha: 0.6);
    for (var i = 0; i < 40; i++) {
      final a = rng.nextDouble() * math.pi * 2;
      final d = radius * (0.3 + rng.nextDouble() * 0.65);
      final p = center + Offset(math.cos(a), math.sin(a)) * d;
      canvas.drawCircle(p, radius * 0.012, glowPaint);
    }
  }

  Color _lighten(Color c, double amt) =>
      Color.lerp(c, Colors.white, amt.clamp(0, 1))!;
  Color _darken(Color c, double amt) =>
      Color.lerp(c, Colors.black, amt.clamp(0, 1))!;

  @override
  bool shouldRepaint(PlanetPainter old) =>
      old.seedColor != seedColor ||
      old.type != type ||
      old.rotation != rotation ||
      old.noiseSeed != noiseSeed;
}
