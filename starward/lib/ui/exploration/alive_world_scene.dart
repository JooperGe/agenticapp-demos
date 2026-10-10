import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/planet.dart';
import 'exploration_page.dart';

/// 蓝雾星 — the "azure veil" vibe: glowing flora, teal-green water, drifting
/// spores and soft distant mountains under a dreamy haze. A painted scene with
/// a handful of animated floating particles layered over it.
class AliveWorldScene extends StatefulWidget {
  const AliveWorldScene({
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
  State<AliveWorldScene> createState() => _AliveWorldSceneState();
}

class _AliveWorldSceneState extends State<AliveWorldScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final List<_Spore> _spores;

  @override
  void initState() {
    super.initState();
    // Seed the particles from the planet id so a given world drifts the same
    // way every visit, matching the project's "never re-randomise" principle.
    final rng = math.Random(widget.planet.id.hashCode);
    _spores = List<_Spore>.generate(
      18,
      (_) => _Spore(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        radius: 1.2 + rng.nextDouble() * 2.6,
        speed: 0.2 + rng.nextDouble() * 0.5,
        phase: rng.nextDouble() * math.pi * 2,
      ),
    );
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

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
                painter: _AliveWorldPainter(seed: widget.planet.id.hashCode),
              ),
            ),
            // Animated spores drift upward above the painted world.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (context, _) => CustomPaint(
                    painter: _SporePainter(spores: _spores, t: _anim.value),
                  ),
                ),
              ),
            ),
            for (final poi in widget.pointsOfInterest)
              Positioned(
                // Spec: left = x*width, top = y*height. FractionalTranslation
                // then re-centres the beacon on that exact normalized point.
                left: poi.x * w,
                top: poi.y * h,
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: ExplorationHotspot(
                    label: poi.label,
                    found: widget.foundIds.contains(poi.id),
                    accent: StarColors.flora,
                    onTap: () => widget.onTapHotspot(poi),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A single drifting spore/particle. Positions are normalised (0..1) so the
/// field scales to any scene size.
class _Spore {
  const _Spore({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.phase,
  });

  final double x;
  final double y;
  final double radius;
  final double speed;
  final double phase;
}

/// Paints the spores drifting upward with a gentle sideways sway and a soft
/// twinkling glow, wrapping back around once they leave the top.
class _SporePainter extends CustomPainter {
  _SporePainter({required this.spores, required this.t});

  final List<_Spore> spores;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in spores) {
      final progress = (s.y - t * s.speed) % 1.0;
      final y = progress * size.height;
      final sway = math.sin(t * math.pi * 2 + s.phase) * 14;
      final x = s.x * size.width + sway;
      final glow =
          0.4 + 0.4 * (0.5 + 0.5 * math.sin(t * math.pi * 4 + s.phase));
      canvas.drawCircle(Offset(x, y), s.radius * 2.4,
          Paint()..color = StarColors.flora.withValues(alpha: 0.12 * glow));
      canvas.drawCircle(Offset(x, y), s.radius,
          Paint()..color = StarColors.cyan.withValues(alpha: 0.7 * glow));
    }
  }

  @override
  bool shouldRepaint(_SporePainter old) => true;
}

/// Procedural backdrop for a living world: a dreamy teal sky with a soft bloom,
/// rolling distant mountains, a glassy water body and glowing shoreline plants.
class _AliveWorldPainter extends CustomPainter {
  _AliveWorldPainter({required this.seed});

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Dreamy sky: deep teal up top melting into a luminous green haze.
    final sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Color(0xFF0C2436),
          Color(0xFF114B4A),
          Color(0xFF1E6E57),
        ],
        stops: <double>[0.0, 0.5, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, sky);

    // Soft hazy bloom behind the mountains for the "梦幻柔光" feel.
    final bloom = Offset(size.width * 0.32, size.height * 0.3);
    final bloomR = size.shortestSide * 0.4;
    canvas.drawCircle(
      bloom,
      bloomR,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            StarColors.flora.withValues(alpha: 0.28),
            StarColors.flora.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: bloom, radius: bloomR))
        ..blendMode = BlendMode.screen,
    );

    final rng = math.Random(seed);

    // Rolling distant mountains — soft rounded silhouettes, two depths.
    _mountains(canvas, size,
        baseY: 0.52,
        color: const Color(0xFF143A3E),
        rng: math.Random(seed + 5),
        humps: 4);
    _mountains(canvas, size,
        baseY: 0.6,
        color: const Color(0xFF0E2B33),
        rng: math.Random(seed + 6),
        humps: 3);

    // Water body across the lower third with a glassy vertical gradient.
    final waterTop = size.height * 0.72;
    final waterRect = Rect.fromLTRB(0, waterTop, size.width, size.height);
    canvas.drawRect(
      waterRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            const Color(0xFF1C7E74).withValues(alpha: 0.92),
            const Color(0xFF093240),
          ],
        ).createShader(waterRect),
    );

    // Reflective shimmer lines on the water surface.
    final shimmer = Paint()
      ..color = StarColors.cyan.withValues(alpha: 0.22)
      ..strokeWidth = 1.4;
    for (var i = 0; i < 6; i++) {
      final y = waterTop + (size.height - waterTop) * (i + 1) / 7;
      final x0 = rng.nextDouble() * size.width * 0.4;
      canvas.drawLine(Offset(x0, y), Offset(x0 + size.width * 0.3, y), shimmer);
    }

    // Glowing plants rising from the shoreline.
    for (var i = 0; i < 7; i++) {
      final x = size.width * (0.08 + rng.nextDouble() * 0.84);
      final baseY = waterTop + 4;
      final hgt = size.height * (0.06 + rng.nextDouble() * 0.1);
      canvas.drawLine(
        Offset(x, baseY),
        Offset(x, baseY - hgt),
        Paint()
          ..color = StarColors.flora.withValues(alpha: 0.75)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(Offset(x, baseY - hgt), 7,
          Paint()..color = StarColors.cyan.withValues(alpha: 0.25));
      canvas.drawCircle(Offset(x, baseY - hgt), 3.4,
          Paint()..color = StarColors.cyan.withValues(alpha: 0.9));
    }
  }

  /// Draws one band of soft, rounded mountains filled to the bottom.
  void _mountains(
    Canvas canvas,
    Size size, {
    required double baseY,
    required Color color,
    required math.Random rng,
    required int humps,
  }) {
    final startY = size.height * baseY;
    final path = Path()..moveTo(0, startY);
    for (var i = 0; i < humps; i++) {
      final x1 = size.width * (i + 0.5) / humps;
      final peak = startY - size.height * (0.08 + rng.nextDouble() * 0.12);
      final x2 = size.width * (i + 1) / humps;
      path.quadraticBezierTo(x1, peak, x2, startY);
    }
    path
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_AliveWorldPainter old) => old.seed != seed;
}


