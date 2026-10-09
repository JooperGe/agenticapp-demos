import 'package:flutter_test/flutter_test.dart';
import 'package:urbanrun/game/input/player_input.dart';
import 'package:urbanrun/game/model/geometry.dart';
import 'package:urbanrun/game/model/scene_model.dart';
import 'package:urbanrun/game/model/world_model.dart';
import 'package:urbanrun/game/movement/collision.dart';
import 'package:urbanrun/game/movement/player_controller.dart';
import 'package:urbanrun/game/projection/iso_projection.dart';

void main() {
  test(
    'normalizes diagonal movement to the same distance as cardinal movement',
    () {
      final scene = const SceneModel(
        id: SceneId.street,
        bounds: Bounds2(0, 0, 24, 24),
        spawn: Point2(2, 2),
        obstacles: <Obstacle>[],
        entrances: <Entrance>[],
      );
      final cardinal = PlayerController(position: const Point2(2, 2));
      final diagonal = PlayerController(position: const Point2(2, 2));

      cardinal.move(const Point2(1, 0), 0.1, scene);
      diagonal.move(const Point2(1, 1), 0.1, scene);

      expect(
        (cardinal.position - const Point2(2, 2)).length,
        closeTo(0.15, 1e-9),
      );
      expect(
        (diagonal.position - const Point2(2, 2)).length,
        closeTo(0.15, 1e-9),
      );
    },
  );

  test('running uses the 1.65 movement multiplier', () {
    final scene = WorldModel.demo().scenes[SceneId.street]!;
    final player = PlayerController(position: const Point2(21, 21));

    player.move(const Point2(1, 0), 0.05, scene, running: true);

    expect(player.position.x, closeTo(21 + 3 * 0.05 * 1.65, 1e-9));
  });

  test(
    'movement resolves against an obstacle while sliding along the other axis',
    () {
      const scene = SceneModel(
        id: SceneId.street,
        bounds: Bounds2(0, 0, 24, 24),
        spawn: Point2(2, 2),
        obstacles: <Obstacle>[Obstacle(Bounds2(3, 1, 4, 4))],
        entrances: <Entrance>[],
      );
      final player = PlayerController(position: const Point2(2.8, 2));

      player.move(const Point2(1, 1), 0.5, scene);

      expect(player.position.x, lessThanOrEqualTo(3 - player.radius));
      expect(player.position.y, greaterThan(2));
    },
  );

  test('clamps a long frame to the maximum movement timestep', () {
    const scene = SceneModel(
      id: SceneId.street,
      bounds: Bounds2(0, 0, 24, 24),
      spawn: Point2(10, 10),
      obstacles: <Obstacle>[],
      entrances: <Entrance>[],
    );
    final player = PlayerController(position: const Point2(10, 10));

    player.move(const Point2(1, 0), 1, scene);

    expect(player.position.x, closeTo(10.15, 1e-9));
    expect(player.position.y, closeTo(10, 1e-9));
  });

  test('substeps prevent crossing a thin obstacle when the clamped endpoint clears it', () {
    const radius = 0.05;
    const start = Point2(4.95, 5);
    const scene = SceneModel(
      id: SceneId.street,
      bounds: Bounds2(0, 0, 24, 24),
      spawn: start,
      obstacles: <Obstacle>[Obstacle(Bounds2(5, 4, 5.05, 6))],
      entrances: <Entrance>[],
    );
    final player = PlayerController(position: start, radius: radius);
    final clampedEndpoint = Point2(start.x + 3 * 1.65 * 0.05, start.y);

    // A single clamped frame would put the center beyond the thin obstacle,
    // and that endpoint is itself standable. Only substeps can reject it.
    expect(clampedEndpoint.x, greaterThan(5.05 + radius));
    expect(Collision.canOccupy(clampedEndpoint, radius, scene), isTrue);

    player.move(const Point2(1, 0), 1, scene, running: true);

    expect(player.position.x, closeTo(start.x, 1e-9));
    expect(player.position.x, lessThanOrEqualTo(5 - player.radius));
  });

  test('demo world provides a 24 by 24 street and two indoor scenes', () {
    final world = WorldModel.demo();
    final street = world.scenes[SceneId.street]!;

    expect(street.bounds.width, 24);
    expect(street.bounds.height, 24);
    expect(
      world.scenes.keys,
      containsAll(<SceneId>[
        SceneId.street,
        SceneId.coffeeShop,
        SceneId.convenienceStore,
      ]),
    );
    expect(street.entrances.length, 2);
    for (final entrance in street.entrances) {
      expect(entrance.targetScene, isNot(SceneId.street));
      expect(world.scenes, contains(entrance.targetScene));
      expect(entrance.targetSpawn, world.scenes[entrance.targetScene]!.spawn);
      expect(
        Collision.canOccupy(
          entrance.targetSpawn,
          0.18,
          world.scenes[entrance.targetScene]!,
        ),
        isTrue,
      );
    }

    for (final scene in world.scenes.values.where(
      (scene) => scene.id != SceneId.street,
    )) {
      expect(scene.entrances, isNotEmpty);
      expect(scene.obstacles, isNotEmpty);
      expect(Collision.canOccupy(scene.spawn, 0.18, scene), isTrue);
      for (final entrance in scene.entrances) {
        expect(entrance.targetScene, SceneId.street);
        expect(world.scenes, contains(entrance.targetScene));
        final streetScene = world.scenes[entrance.targetScene]!;
        expect(streetScene.id, SceneId.street);
        expect(
          Collision.canOccupy(entrance.targetSpawn, 0.18, streetScene),
          isTrue,
        );
        expect(
          Collision.canOccupy(entrance.returnPosition, 0.18, streetScene),
          isTrue,
        );
      }
    }
  });

  test('screen keyboard direction is inverse projected into normalized ground direction', () {
    final input = PlayerInput();
    input.press('ArrowRight');
    final direction = input.groundDirection(const IsoProjection());

    expect(direction.x, closeTo(1 / 1.4142135623730951, 1e-9));
    expect(direction.y, closeTo(-1 / 1.4142135623730951, 1e-9));
  });

  test('interaction is a rising edge and clear releases all keys', () {
    final input = PlayerInput();
    input.press('e');

    expect(input.consumeInteraction(), isTrue);
    expect(input.consumeInteraction(), isFalse);
    input.release('e');
    input.press('e');
    expect(input.consumeInteraction(), isTrue);

    input.press('w');
    input.clear();
    expect(input.screenDirection, const Point2(0, 0));
    expect(input.running, isFalse);
    expect(input.consumeInteraction(), isFalse);
  });
}
