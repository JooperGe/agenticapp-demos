import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/planet.dart';
import 'exploration_page.dart';

/// 伊瑟拉 — the "Ithara" vibe: an alien cityscape at dusk, grand towers and
/// spires on the far skyline, warm gold and cool cyan window-lights glittering
/// beneath an exotic sky. A fully painted scene with the planet's hotspots.
class CivilizationScene extends StatelessWidget {
  const CivilizationScene({
    super.key,
    required this.planet,
    required this.pointsOfInterest,
    required this.foundIds,
    required this.onTapHotspot,
  });

  final Planet planet;
  final List<PointOfInterest> pointsOfInterest;
  final Set<String> foundIds;
  final HotspotTap onTapHotspot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: CustomPaint(
                painter: _CivilizationPainter(seed: planet.id.hashCode),
              ),
            ),
            for (final poi in pointsOfInterest)
              Positioned(
                // Spec: left = x*width, top = y*height. FractionalTranslation
                // then re-centres the beacon on that exact normalized point.
                left: poi.x * w,
                top: poi.y * h,
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: ExplorationHotspot(
                    label: poi.label,
                    found: foundIds.contains(poi.id),
                    accent: StarColors.gold,
                    onTap: () => onTapHotspot(poi),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Procedural backdrop for a civilised world: an alien dusk sky, two moons and
/// three layered building skylines whose windows glow warm and cool.
class _CivilizationPainter extends CustomPainter {
  _CivilizationPainter({required this.seed});

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Alien dusk: violet zenith sinking into a warm amber horizon.
    final sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Color(0xFF140A2E),
          Color(0xFF2A1B4B),
          Color(0xFF5A3A4A),
          Color(0xFF8A5A3C),
        ],
        stops: <double>[0.0, 0.4, 0.72, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, sky);

    // Two alien moons hanging over the city — one gold, one cold cyan.
    canvas.drawCircle(
      Offset(size.width * 0.22, size.height * 0.2),
      size.shortestSide * 0.05,
      Paint()..color = const Color(0xFFF2C879).withValues(alpha: 0.85),
    );
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.14),
      size.shortestSide * 0.03,
      Paint()..color = const Color(0xFF9FD8E6).withValues(alpha: 0.7),
    );

    // Three skyline layers: farthest/lightest first, nearest/darkest last.
    _skyline(canvas, size,
        baseY: 0.52,
        color: const Color(0xFF35264F),
        lights: StarColors.cyan.withValues(alpha: 0.5),
        rng: math.Random(seed + 11),
        maxH: 0.26);
    _skyline(canvas, size,
        baseY: 0.64,
        color: const Color(0xFF241634),
        lights: StarColors.gold.withValues(alpha: 0.7),
        rng: math.Random(seed + 12),
        maxH: 0.34);
    _skyline(canvas, size,
        baseY: 0.78,
        color: const Color(0xFF150C22),
        lights: StarColors.gold.withValues(alpha: 0.9),
        rng: math.Random(seed + 13),
        maxH: 0.42);
  }

  /// Draws one depth of building silhouettes with occasional spires and a
  /// loose grid of warm window lights, then fills the ground band below.
  void _skyline(
    Canvas canvas,
    Size size, {
    required double baseY,
    required Color color,
    required Color lights,
    required math.Random rng,
    required double maxH,
  }) {
    final groundY = size.height * baseY;
    final paint = Paint()..color = color;
    final lightPaint = Paint()..color = lights;

    var x = 0.0;
    while (x < size.width) {
      final bw = size.width * (0.06 + rng.nextDouble() * 0.08);
      final bh = size.height * maxH * (0.4 + rng.nextDouble() * 0.6);
      final top = groundY - bh;
      canvas.drawRect(Rect.fromLTWH(x, top, bw, size.height - top), paint);

      // An occasional spire crowns the taller towers.
      if (rng.nextDouble() > 0.6) {
        final spire = Path()
          ..moveTo(x + bw * 0.5, top - size.height * 0.06)
          ..lineTo(x + bw * 0.35, top)
          ..lineTo(x + bw * 0.65, top)
          ..close();
        canvas.drawPath(spire, paint);
      }

      // Warm/cool window lights in a loose grid across the facade.
      for (var gy = top + 6; gy < groundY - 4; gy += 10) {
        for (var gx = x + 4; gx < x + bw - 3; gx += 8) {
          if (rng.nextDouble() > 0.45) {
            canvas.drawRect(Rect.fromLTWH(gx, gy, 2.4, 3.4), lightPaint);
          }
        }
      }
      x += bw + size.width * 0.015;
    }

    // Solid ground band so nearer skylines cleanly occlude farther ones.
    canvas.drawRect(
        Rect.fromLTRB(0, groundY, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_CivilizationPainter old) => old.seed != seed;
}


