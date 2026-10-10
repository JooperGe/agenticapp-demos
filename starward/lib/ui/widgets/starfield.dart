import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// One star in the field. Positions are normalised (0..1) so the field scales
/// to any size. [layer] drives parallax depth for the journey view.
class _Star {
  _Star(this.x, this.y, this.radius, this.brightness, this.layer, this.phase);
  final double x;
  final double y;
  final double radius;
  final double brightness;
  final double layer; // 0 = far, 1 = near
  final double phase; // twinkle offset
}

class _Nebula {
  _Nebula(this.x, this.y, this.radius, this.color);
  final double x;
  final double y;
  final double radius;
  final Color color;
}

List<_Star> _generateStars(int seed, int count) {
  final rng = math.Random(seed);
  return List<_Star>.generate(count, (_) {
    final layer = rng.nextDouble();
    return _Star(
      rng.nextDouble(),
      rng.nextDouble(),
      0.4 + layer * 1.6,
      0.3 + rng.nextDouble() * 0.7,
      layer,
      rng.nextDouble() * math.pi * 2,
    );
  });
}

List<_Nebula> _generateNebulae(int seed) {
  final rng = math.Random(seed);
  const palette = <Color>[
    Color(0xFF3A2A6B),
    Color(0xFF1E3A6B),
    Color(0xFF2A5A5E),
  ];
  return List<_Nebula>.generate(3, (i) {
    return _Nebula(
      rng.nextDouble(),
      rng.nextDouble(),
      0.3 + rng.nextDouble() * 0.35,
      palette[i % palette.length],
    );
  });
}

/// A calm, slowly twinkling deep-space backdrop. Used on the splash, journey
/// and exploration scenes. Stars drift almost imperceptibly so the screen is
/// never static but never busy either.
class StarfieldBackground extends StatefulWidget {
  const StarfieldBackground({
    super.key,
    this.seed = 7,
    this.starCount = 150,
    this.scrollSpeed = 0.0,
    this.drift = true,
  });

  final int seed;
  final int starCount;

  /// If > 0, stars stream downward (parallax by layer) to convey forward
  /// flight — used by the journey scene.
  final double scrollSpeed;
  final bool drift;

  @override
  State<StarfieldBackground> createState() => _StarfieldBackgroundState();
}

class _StarfieldBackgroundState extends State<StarfieldBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Star> _stars;
  late final List<_Nebula> _nebulae;

  @override
  void initState() {
    super.initState();
    _stars = _generateStars(widget.seed, widget.starCount);
    _nebulae = _generateNebulae(widget.seed + 99);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: StarGradients.space),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            size: Size.infinite,
            painter: _StarfieldPainter(
              stars: _stars,
              nebulae: _nebulae,
              t: _controller.value,
              scrollSpeed: widget.scrollSpeed,
              drift: widget.drift,
            ),
          );
        },
      ),
    );
  }
}

class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter({
    required this.stars,
    required this.nebulae,
    required this.t,
    required this.scrollSpeed,
    required this.drift,
  });

  final List<_Star> stars;
  final List<_Nebula> nebulae;
  final double t;
  final double scrollSpeed;
  final bool drift;

  @override
  void paint(Canvas canvas, Size size) {
    // Soft nebula clouds first, behind the stars.
    for (final n in nebulae) {
      final center = Offset(n.x * size.width, n.y * size.height);
      final radius = n.radius * size.shortestSide;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            n.color.withValues(alpha: 0.28),
            n.color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..blendMode = BlendMode.screen;
      canvas.drawCircle(center, radius, paint);
    }

    final starPaint = Paint();
    for (final s in stars) {
      // Parallax streaming for the journey view; near layers move faster.
      final scroll = scrollSpeed * (0.3 + s.layer);
      var y = (s.y + scroll) % 1.0;
      // Gentle idle drift.
      if (drift) {
        y = (y + 0.01 * s.layer * math.sin(t * math.pi * 2 + s.phase)) % 1.0;
      }
      final dx = s.x * size.width;
      final dy = y * size.height;
      final twinkle =
          0.65 + 0.35 * math.sin(t * math.pi * 2 * 2 + s.phase);
      starPaint.color =
          StarColors.offWhite.withValues(alpha: s.brightness * twinkle);
      canvas.drawCircle(Offset(dx, dy), s.radius, starPaint);
    }
  }

  @override
  bool shouldRepaint(_StarfieldPainter old) => true;
}
