import 'geometry.dart';

enum SceneId { street, coffeeShop, convenienceStore }

class Bounds2 {
  const Bounds2(this.left, this.top, this.right, this.bottom)
    : assert(right >= left),
      assert(bottom >= top);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;

  bool contains(Point2 point) =>
      point.x >= left &&
      point.x <= right &&
      point.y >= top &&
      point.y <= bottom;
}

class Obstacle {
  const Obstacle(this.bounds);

  final Bounds2 bounds;

  /// Ground contact corner used for isometric painter's ordering.
  Point2 get groundFoot => Point2(bounds.right, bounds.bottom);
}

class Entrance {
  const Entrance({
    required this.id,
    required this.position,
    required this.radius,
    required this.targetScene,
    required this.targetSpawn,
    required this.returnPosition,
    this.safeReturnPosition,
  });

  final String id;
  final Point2 position;
  final double radius;
  final SceneId targetScene;
  final Point2 targetSpawn;
  final Point2 returnPosition;
  final Point2? safeReturnPosition;
}

class SceneModel {
  const SceneModel({
    required this.id,
    required this.bounds,
    required this.spawn,
    required this.obstacles,
    required this.entrances,
  });

  final SceneId id;
  final Bounds2 bounds;
  final Point2 spawn;
  final List<Obstacle> obstacles;
  final List<Entrance> entrances;
}
