import 'dart:math' as math;

import '../model/geometry.dart';
import '../model/scene_model.dart';
import 'collision.dart';

class PlayerController {
  PlayerController({required this.position, this.radius = 0.18})
    : facing = const Point2(1, 0);

  Point2 position;
  final double radius;
  Point2 facing;

  void move(
    Point2 groundDirection,
    double dt,
    SceneModel scene, {
    bool running = false,
  }) {
    if (groundDirection.length == 0 || dt <= 0) return;
    final direction = groundDirection.normalized();
    facing = direction;
    final frameDt = math.min(dt, 0.05);
    final speed = 3 * (running ? 1.65 : 1);
    final displacement = direction.scaled(speed * frameDt);
    final distance = displacement.length;
    final maxStep = math.max(radius / 2, 1e-9);
    final stepCount = math.max(1, (distance / maxStep).ceil());
    final step = displacement.scaled(1 / stepCount);

    for (var i = 0; i < stepCount; i++) {
      final xCandidate = Point2(position.x + step.x, position.y);
      if (Collision.canOccupy(xCandidate, radius, scene)) {
        position = xCandidate;
      }
      final yCandidate = Point2(position.x, position.y + step.y);
      if (Collision.canOccupy(yCandidate, radius, scene)) {
        position = yCandidate;
      }
    }
  }
}
