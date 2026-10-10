import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/planet.dart';
import 'exploration_page.dart';

/// 灰烬之境 — the "ashen reach" vibe: cold grey-blue rock under a distant, weak
/// star. Vast, silent and lonely, yet quietly magnificent. A fully painted
/// scene (not text + buttons) with the planet's hotspots laid over it.
class DeadWorldScene extends StatelessWidget {
  const DeadWorldScene({
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
                painter: _DeadWorldPainter(seed: planet.id.hashCode),
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
                    accent: StarColors.cyanDim,
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

/// Procedural backdrop for a dead world: a cold sky, a weak distant star,
/// sparse faint stars and layered rocky ridges fading into shadow.
class _DeadWorldPainter extends CustomPainter {
  _DeadWorldPainter({required this.seed});

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Cold sky: near-black navy sinking to a desaturated grey-blue horizon.
    final sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Color(0xFF070B16),
          Color(0xFF0E1428),
          Color(0xFF28334A),
        ],
        stops: <double>[0.0, 0.55, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, sky);

    final rng = math.Random(seed);

    // Sparse, faint stars — this is a lonely, quiet place, not a busy sky.
    final starPaint = Paint();
    for (var i = 0; i < 36; i++) {
      final dx = rng.nextDouble() * size.width;
      final dy = rng.nextDouble() * size.height * 0.6;
      starPaint.color =
          StarColors.offWhite.withValues(alpha: 0.2 + rng.nextDouble() * 0.4);
      canvas.drawCircle(Offset(dx, dy), 0.3 + rng.nextDouble() * 1.1, starPaint);
    }

    // The distant, weak star with a cold halo, low energy and far away.
    final sunCenter = Offset(size.width * 0.74, size.height * 0.2);
    final sunR = size.shortestSide * 0.028;
    canvas.drawCircle(
      sunCenter,
      sunR * 5,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            const Color(0xFFBFD2E8).withValues(alpha: 0.32),
            const Color(0xFFBFD2E8).withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: sunCenter, radius: sunR * 5)),
    );
    canvas.drawCircle(sunCenter, sunR,
        Paint()..color = const Color(0xFFE6EEF8).withValues(alpha: 0.9));

    // Layered rocky ridges — each lower band darker and more foreground.
    _ridge(canvas, size,
        baseY: 0.62,
        amp: 0.05,
        color: const Color(0xFF3A4765),
        rng: math.Random(seed + 1),
        segments: 7);
    _ridge(canvas, size,
        baseY: 0.74,
        amp: 0.07,
        color: const Color(0xFF2B3550),
        rng: math.Random(seed + 2),
        segments: 6);
    _ridge(canvas, size,
        baseY: 0.86,
        amp: 0.09,
        color: const Color(0xFF1B2238),
        rng: math.Random(seed + 3),
        segments: 5);

    // Cold vignette to deepen the sense of lonely vastness.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.9,
          colors: <Color>[
            Colors.transparent,
            StarColors.abyss.withValues(alpha: 0.45),
          ],
          stops: const <double>[0.6, 1.0],
        ).createShader(rect),
    );
  }

  /// Draws one jagged rock ridge filled down to the bottom of the canvas.
  void _ridge(
    Canvas canvas,
    Size size, {
    required double baseY,
    required double amp,
    required Color color,
    required math.Random rng,
    required int segments,
  }) {
    final startY = size.height * baseY;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, startY);
    for (var i = 0; i <= segments; i++) {
      final x = size.width * i / segments;
      final y = startY - size.height * amp * rng.nextDouble();
      path.lineTo(x, y);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DeadWorldPainter old) => old.seed != seed;
}


