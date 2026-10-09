import '../model/geometry.dart';
import '../model/scene_model.dart';

class Collision {
  const Collision._();

  static bool canOccupy(Point2 center, double radius, SceneModel scene) {
    final bounds = scene.bounds;
    if (center.x - radius < bounds.left ||
        center.x + radius > bounds.right ||
        center.y - radius < bounds.top ||
        center.y + radius > bounds.bottom) {
      return false;
    }

    for (final obstacle in scene.obstacles) {
      final rectangle = obstacle.bounds;
      final nearestX = center.x
          .clamp(rectangle.left, rectangle.right)
          .toDouble();
      final nearestY = center.y
          .clamp(rectangle.top, rectangle.bottom)
          .toDouble();
      final dx = center.x - nearestX;
      final dy = center.y - nearestY;
      if (dx * dx + dy * dy < radius * radius) return false;
    }
    return true;
  }
}
