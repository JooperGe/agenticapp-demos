import 'package:flutter/material.dart';

import '../model/geometry.dart';
import '../model/scene_model.dart';
import '../projection/iso_projection.dart';

/// Paints the deterministic procedural neighborhood and its interiors.
class CityRenderer {
  const CityRenderer();

  void render(
    Canvas canvas,
    SceneModel scene,
    IsoProjection projection, {
    Iterable<CityRenderItem> additionalItems = const <CityRenderItem>[],
  }) {
    _drawGround(canvas, scene, projection);
    final items = <CityRenderItem>[];
    for (final obstacle in scene.obstacles) {
      items.add(
        CityRenderItem(
          groundFoot: obstacleGroundFoot(obstacle),
          paint: () => _drawObstacle(canvas, scene, obstacle, projection),
        ),
      );
    }
    if (scene.id == SceneId.street) {
      items.addAll(_streetProps(canvas, projection));
    } else {
      items.addAll(_interiorProps(canvas, scene, projection));
    }
    items.addAll(additionalItems);
    final sortedItems = sortCityRenderItems(items);
    for (final item in sortedItems) {
      item.paint();
    }
    _drawEntrances(canvas, scene, projection);
  }

  void _drawGround(Canvas canvas, SceneModel scene, IsoProjection projection) {
    final bounds = scene.bounds;
    final corners = _rectCorners(bounds, projection);
    final ground = Paint()
      ..color = scene.id == SceneId.street
          ? const Color(0xFF6E9B73)
          : const Color(0xFFD8C9A8);
    canvas.drawPath(_polygon(corners), ground);

    if (scene.id != SceneId.street) {
      final floor = Paint()..color = const Color(0xFFE8D8B6);
      final inset = Bounds2(
        bounds.left + .35,
        bounds.top + .35,
        bounds.right - .35,
        bounds.bottom - .35,
      );
      canvas.drawPath(_polygon(_rectCorners(inset, projection)), floor);
      return;
    }

    _drawStreetNetwork(canvas, projection);
    _drawParkFlowerbed(canvas, projection);
  }

  void _drawStreetNetwork(Canvas canvas, IsoProjection projection) {
    final pavement = Paint()..color = const Color(0xFFB8B7A4);
    final road = Paint()..color = const Color(0xFF566B77);
    final roadEdge = Paint()..color = const Color(0xFF78888C);
    final paths = <List<Point2>>[
      [
        const Point2(0, 7.1),
        const Point2(24, 7.1),
        const Point2(24, 8.8),
        const Point2(0, 8.8),
      ],
      [
        const Point2(7.1, 0),
        const Point2(8.8, 0),
        const Point2(8.8, 24),
        const Point2(7.1, 24),
      ],
      [
        const Point2(14.2, 0),
        const Point2(15.9, 0),
        const Point2(15.9, 24),
        const Point2(14.2, 24),
      ],
      [
        const Point2(0, 14.2),
        const Point2(24, 14.2),
        const Point2(24, 15.9),
        const Point2(0, 15.9),
      ],
    ];
    for (final path in paths) {
      canvas.drawPath(
        _polygon(path.map(projection.worldToScreen).toList()),
        pavement,
      );
    }
    final roads = <List<Point2>>[
      [
        const Point2(0, 7.45),
        const Point2(24, 7.45),
        const Point2(24, 8.45),
        const Point2(0, 8.45),
      ],
      [
        const Point2(7.45, 0),
        const Point2(8.45, 0),
        const Point2(8.45, 24),
        const Point2(7.45, 24),
      ],
      [
        const Point2(14.55, 0),
        const Point2(15.55, 0),
        const Point2(15.55, 24),
        const Point2(14.55, 24),
      ],
      [
        const Point2(0, 14.55),
        const Point2(24, 14.55),
        const Point2(24, 15.55),
        const Point2(0, 15.55),
      ],
    ];
    for (final points in roads) {
      canvas.drawPath(
        _polygon(points.map(projection.worldToScreen).toList()),
        road,
      );
    }
    for (var i = 1; i < 24; i += 2) {
      _drawWorldLine(
        canvas,
        projection,
        Point2(i.toDouble(), 7.95),
        Point2((i + .7).toDouble(), 7.95),
        roadEdge,
        0.08,
      );
      _drawWorldLine(
        canvas,
        projection,
        Point2(7.95, i.toDouble()),
        Point2(7.95, (i + .7).toDouble()),
        roadEdge,
        0.08,
      );
      _drawWorldLine(
        canvas,
        projection,
        Point2(15.05, i.toDouble()),
        Point2(15.05, (i + .7).toDouble()),
        roadEdge,
        0.08,
      );
      _drawWorldLine(
        canvas,
        projection,
        Point2(i.toDouble(), 15.05),
        Point2((i + .7).toDouble(), 15.05),
        roadEdge,
        0.08,
      );
    }
    _drawCrossing(canvas, projection, const Point2(7.95, 6.8), false);
    _drawCrossing(canvas, projection, const Point2(6.8, 7.95), true);
    _drawCrossing(canvas, projection, const Point2(15.05, 8.8), true);
  }

  void _drawCrossing(
    Canvas canvas,
    IsoProjection projection,
    Point2 center,
    bool horizontal,
  ) {
    final paint = Paint()..color = const Color(0xFFDCE2D2);
    for (var i = -2; i <= 2; i++) {
      final offset = i * .26;
      final a = horizontal
          ? Point2(center.x + offset, center.y - .4)
          : Point2(center.x - .4, center.y + offset);
      final b = horizontal
          ? Point2(center.x + offset, center.y + .4)
          : Point2(center.x + .4, center.y + offset);
      _drawWorldLine(canvas, projection, a, b, paint, .13);
    }
  }

  void _drawParkFlowerbed(Canvas canvas, IsoProjection projection) {
    final bed = const Bounds2(9.3, 9.5, 13.3, 12.6);
    canvas.drawPath(
      _polygon(_rectCorners(bed, projection)),
      Paint()..color = const Color(0xFF557A5F),
    );
    final flower = Paint()..color = const Color(0xFFF1B66D);
    for (final point in <Point2>[
      const Point2(10, 10),
      const Point2(11.2, 11.2),
      const Point2(12.2, 10.2),
      const Point2(11, 12),
    ]) {
      canvas.drawCircle(_toOffset(projection.worldToScreen(point)), 3, flower);
      canvas.drawCircle(
        _toOffset(projection.worldToScreen(point + const Point2(.2, .1))),
        2,
        Paint()..color = const Color(0xFFEE7E87),
      );
    }
  }

  List<CityRenderItem> _streetProps(Canvas canvas, IsoProjection projection) =>
      <CityRenderItem>[
        CityRenderItem(
          groundFoot: const Point2(7.2, 6.2),
          paint: () => _drawTree(canvas, projection, const Point2(7.2, 6.2)),
        ),
        CityRenderItem(
          groundFoot: const Point2(15.8, 8.9),
          paint: () => _drawTree(canvas, projection, const Point2(15.8, 8.9)),
        ),
        CityRenderItem(
          groundFoot: const Point2(8.2, 15.9),
          paint: () => _drawTree(canvas, projection, const Point2(8.2, 15.9)),
        ),
        CityRenderItem(
          groundFoot: const Point2(15.7, 15.9),
          paint: () => _drawTree(canvas, projection, const Point2(15.7, 15.9)),
        ),
        CityRenderItem(
          groundFoot: const Point2(8.9, 7.1),
          paint: () => _drawLamp(canvas, projection, const Point2(8.9, 7.1)),
        ),
        CityRenderItem(
          groundFoot: const Point2(15.9, 14.1),
          paint: () => _drawLamp(canvas, projection, const Point2(15.9, 14.1)),
        ),
        CityRenderItem(
          groundFoot: const Point2(12.2, 13.3),
          paint: () => _drawBench(canvas, projection, const Point2(12.2, 13.3)),
        ),
        CityRenderItem(
          groundFoot: const Point2(17.2, 8.0),
          paint: () => _drawCar(
            canvas,
            projection,
            const Point2(17.2, 8.0),
            const Color(0xFFE5A56B),
          ),
        ),
        CityRenderItem(
          groundFoot: const Point2(5.2, 15.0),
          paint: () => _drawCar(
            canvas,
            projection,
            const Point2(5.2, 15.0),
            const Color(0xFF9BB6D0),
          ),
        ),
      ];

  List<CityRenderItem> _interiorProps(
    Canvas canvas,
    SceneModel scene,
    IsoProjection projection,
  ) {
    final accent = scene.id == SceneId.coffeeShop
        ? const Color(0xFFB7784C)
        : const Color(0xFF648E9C);
    return <CityRenderItem>[
      CityRenderItem(
        groundFoot: const Point2(5.4, 1.5),
        paint: () =>
            _drawCounter(canvas, projection, const Point2(5.4, 1.5), accent),
      ),
      CityRenderItem(
        groundFoot: const Point2(3.2, 3.9),
        paint: () =>
            _drawTable(canvas, projection, const Point2(3.2, 3.9), accent),
      ),
      CityRenderItem(
        groundFoot: const Point2(6.9, 4.1),
        paint: () =>
            _drawTable(canvas, projection, const Point2(6.9, 4.1), accent),
      ),
      if (scene.id == SceneId.convenienceStore)
        CityRenderItem(
          groundFoot: const Point2(8.0, 2.0),
          paint: () => _drawShelf(canvas, projection, const Point2(8.0, 2.0)),
        ),
    ];
  }

  void _drawObstacle(
    Canvas canvas,
    SceneModel scene,
    Obstacle obstacle,
    IsoProjection projection,
  ) {
    final b = obstacle.bounds;
    final base = _rectCorners(b, projection);
    final height = scene.id == SceneId.street ? 1.8 : .35;
    final roof = base
        .map(
          (point) => Point2(point.x, point.y - height * projection.tileHeight),
        )
        .toList();
    final roofPaint = Paint()
      ..color = scene.id == SceneId.street
          ? _buildingColor(b)
          : const Color(0xFFC7A87A);
    final wallLight = Paint()
      ..color = scene.id == SceneId.street
          ? const Color(0xFFBD8A62)
          : const Color(0xFFD4B78B);
    final wallShadow = Paint()
      ..color = scene.id == SceneId.street
          ? const Color(0xFF805A4B)
          : const Color(0xFFAA8967);
    canvas.drawPath(
      _polygon(<Point2>[base[0], base[1], roof[1], roof[0]]),
      wallLight,
    );
    canvas.drawPath(
      _polygon(<Point2>[base[1], base[2], roof[2], roof[1]]),
      wallShadow,
    );
    canvas.drawPath(_polygon(roof), roofPaint);
    if (scene.id == SceneId.street && b.left == 2 && b.top == 2) {
      _drawLabel(
        canvas,
        projection.worldToScreen(const Point2(4, 2)),
        'COFFEE SHOP',
      );
    }
    if (scene.id == SceneId.street && b.left == 9 && b.top == 2) {
      _drawLabel(
        canvas,
        projection.worldToScreen(const Point2(11, 2)),
        'MARKET',
      );
    }
  }

  Color _buildingColor(Bounds2 bounds) {
    if (bounds.left == 2 && bounds.top == 2) return const Color(0xFFD39A67);
    if (bounds.left == 9 && bounds.top == 2) return const Color(0xFFA6B8A0);
    if (bounds.left == 16 && bounds.top == 2) return const Color(0xFFC48C83);
    return const Color(0xFFB59B7A);
  }

  void _drawTree(Canvas canvas, IsoProjection projection, Point2 point) {
    final screen = projection.worldToScreen(point);
    canvas.drawCircle(
      _toOffset(screen + const Point2(0, -22)),
      12,
      Paint()..color = const Color(0xFF2E654F),
    );
    canvas.drawCircle(
      _toOffset(screen + const Point2(-8, -17)),
      8,
      Paint()..color = const Color(0xFF3E8059),
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: _toOffset(screen + const Point2(0, -6)),
        width: 4,
        height: 13,
      ),
      Paint()..color = const Color(0xFF72513A),
    );
  }

  void _drawLamp(Canvas canvas, IsoProjection projection, Point2 point) {
    final screen = _toOffset(projection.worldToScreen(point));
    final paint = Paint()
      ..color = const Color(0xFF27343D)
      ..strokeWidth = 2;
    canvas.drawLine(screen, screen.translate(0, -30), paint);
    canvas.drawCircle(
      screen.translate(0, -33),
      4,
      Paint()..color = const Color(0xFFFFD68A),
    );
  }

  void _drawBench(Canvas canvas, IsoProjection projection, Point2 point) {
    final screen = _toOffset(projection.worldToScreen(point));
    final paint = Paint()..color = const Color(0xFF8C5E3E);
    canvas.drawRect(
      Rect.fromCenter(center: screen.translate(0, -5), width: 22, height: 4),
      paint,
    );
    canvas.drawRect(
      Rect.fromCenter(center: screen.translate(0, -12), width: 22, height: 4),
      paint,
    );
    canvas.drawLine(
      screen.translate(-8, -3),
      screen.translate(-8, 5),
      paint..strokeWidth = 3,
    );
    canvas.drawLine(screen.translate(8, -3), screen.translate(8, 5), paint);
  }

  void _drawCar(
    Canvas canvas,
    IsoProjection projection,
    Point2 point,
    Color color,
  ) {
    final screen = _toOffset(projection.worldToScreen(point));
    canvas.drawOval(
      Rect.fromCenter(center: screen.translate(0, -5), width: 25, height: 12),
      Paint()..color = color,
    );
    canvas.drawRect(
      Rect.fromCenter(center: screen.translate(0, -9), width: 12, height: 7),
      Paint()..color = color.withValues(alpha: .85),
    );
    canvas.drawCircle(
      screen.translate(-8, 1),
      3,
      Paint()..color = const Color(0xFF303941),
    );
    canvas.drawCircle(
      screen.translate(8, 1),
      3,
      Paint()..color = const Color(0xFF303941),
    );
  }

  void _drawCounter(
    Canvas canvas,
    IsoProjection projection,
    Point2 point,
    Color color,
  ) {
    final screen = _toOffset(projection.worldToScreen(point));
    canvas.drawRect(
      Rect.fromCenter(center: screen.translate(0, -8), width: 45, height: 14),
      Paint()..color = color,
    );
    canvas.drawRect(
      Rect.fromCenter(center: screen.translate(0, -17), width: 47, height: 4),
      Paint()..color = const Color(0xFFE5D6B6),
    );
  }

  void _drawTable(
    Canvas canvas,
    IsoProjection projection,
    Point2 point,
    Color color,
  ) {
    final screen = _toOffset(projection.worldToScreen(point));
    canvas.drawOval(
      Rect.fromCenter(center: screen.translate(0, -7), width: 23, height: 13),
      Paint()..color = color,
    );
    canvas.drawLine(
      screen.translate(0, -4),
      screen.translate(0, 6),
      Paint()
        ..color = const Color(0xFF795441)
        ..strokeWidth = 3,
    );
  }

  void _drawShelf(Canvas canvas, IsoProjection projection, Point2 point) {
    final screen = _toOffset(projection.worldToScreen(point));
    final paint = Paint()..color = const Color(0xFF6A7D83);
    canvas.drawRect(
      Rect.fromCenter(center: screen.translate(0, -15), width: 25, height: 32),
      paint,
    );
    for (var i = 0; i < 3; i++) {
      canvas.drawLine(
        screen.translate(-10, -25 + i * 9),
        screen.translate(10, -25 + i * 9),
        Paint()
          ..color = const Color(0xFFD4B36E)
          ..strokeWidth = 3,
      );
    }
  }

  void _drawEntrances(
    Canvas canvas,
    SceneModel scene,
    IsoProjection projection,
  ) {
    final markerPaint = Paint()..color = const Color(0xFF65D5B3);
    for (final entrance in scene.entrances) {
      final screen = projection.worldToScreen(entrance.position);
      final path = Path()
        ..moveTo(screen.x, screen.y - 12)
        ..lineTo(screen.x + 9, screen.y - 3)
        ..lineTo(screen.x, screen.y + 6)
        ..lineTo(screen.x - 9, screen.y - 3)
        ..close();
      canvas.drawPath(path, markerPaint);
      canvas.drawCircle(
        _toOffset(screen),
        3,
        Paint()..color = const Color(0xFF23353B),
      );
    }
  }

  void _drawLabel(Canvas canvas, Point2 point, String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFFECE1C9),
          fontSize: 8,
          fontWeight: FontWeight.w700,
          letterSpacing: .8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(point.x - painter.width / 2, point.y - 38));
  }

  List<Point2> _rectCorners(Bounds2 bounds, IsoProjection projection) =>
      <Point2>[
        projection.worldToScreen(Point2(bounds.left, bounds.top)),
        projection.worldToScreen(Point2(bounds.right, bounds.top)),
        projection.worldToScreen(Point2(bounds.right, bounds.bottom)),
        projection.worldToScreen(Point2(bounds.left, bounds.bottom)),
      ];

  Path _polygon(List<Point2> points) => Path()
    ..moveTo(points.first.x, points.first.y)
    ..addPolygon(
      points.skip(1).map((point) => Offset(point.x, point.y)).toList(),
      true,
    );

  void _drawWorldLine(
    Canvas canvas,
    IsoProjection projection,
    Point2 a,
    Point2 b,
    Paint paint,
    double width,
  ) {
    final linePaint = Paint.from(paint)
      ..strokeWidth = width * projection.tileHeight;
    canvas.drawLine(
      _toOffset(projection.worldToScreen(a)),
      _toOffset(projection.worldToScreen(b)),
      linePaint,
    );
  }

  Offset _toOffset(Point2 point) => Offset(point.x, point.y);
}

class CityRenderItem {
  const CityRenderItem({required this.groundFoot, required this.paint});

  final Point2 groundFoot;
  double get depth => groundDepth(groundFoot);
  final VoidCallback paint;
}

/// Returns the isometric painter's depth for an object's ground contact point.
double groundDepth(Point2 groundFoot) => groundFoot.x + groundFoot.y;

List<CityRenderItem> sortCityRenderItems(Iterable<CityRenderItem> items) {
  final sorted = items.toList()..sort((a, b) => a.depth.compareTo(b.depth));
  return sorted;
}

/// The visible ground contact corner for a rectangular obstacle/building.
Point2 obstacleGroundFoot(Obstacle obstacle) =>
    Point2(obstacle.bounds.right, obstacle.bounds.bottom);
