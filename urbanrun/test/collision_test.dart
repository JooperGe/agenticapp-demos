import 'package:flutter_test/flutter_test.dart';
import 'package:urbanrun/game/model/geometry.dart';
import 'package:urbanrun/game/model/scene_model.dart';
import 'package:urbanrun/game/movement/collision.dart';

void main() {
  test('rejects a player circle outside the scene bounds', () {
    const scene = SceneModel(
      id: SceneId.street,
      bounds: Bounds2(0, 0, 24, 24),
      spawn: Point2(2, 2),
      obstacles: <Obstacle>[],
      entrances: <Entrance>[],
    );

    expect(Collision.canOccupy(Point2(-1, 2), 0.18, scene), isFalse);
    expect(Collision.canOccupy(Point2(0.18, 2), 0.18, scene), isTrue);
  });

  test('rejects a circle intersecting an axis-aligned obstacle', () {
    const scene = SceneModel(
      id: SceneId.street,
      bounds: Bounds2(0, 0, 24, 24),
      spawn: Point2(2, 2),
      obstacles: <Obstacle>[Obstacle(Bounds2(4, 4, 6, 6))],
      entrances: <Entrance>[],
    );

    expect(Collision.canOccupy(Point2(3.9, 5), 0.18, scene), isFalse);
    expect(Collision.canOccupy(Point2(3.7, 5), 0.18, scene), isTrue);
  });

  test('checks the nearest corner for a circle near an obstacle corner', () {
    const scene = SceneModel(
      id: SceneId.street,
      bounds: Bounds2(0, 0, 24, 24),
      spawn: Point2(2, 2),
      obstacles: <Obstacle>[Obstacle(Bounds2(4, 4, 6, 6))],
      entrances: <Entrance>[],
    );

    expect(Collision.canOccupy(Point2(3.9, 3.9), 0.18, scene), isFalse);
    expect(Collision.canOccupy(Point2(3.8, 3.8), 0.18, scene), isTrue);
  });

  test('rejects a circle center inside an obstacle', () {
    const scene = SceneModel(
      id: SceneId.street,
      bounds: Bounds2(0, 0, 24, 24),
      spawn: Point2(2, 2),
      obstacles: <Obstacle>[Obstacle(Bounds2(4, 4, 6, 6))],
      entrances: <Entrance>[],
    );

    expect(Collision.canOccupy(Point2(5, 5), 0.01, scene), isFalse);
  });
}
