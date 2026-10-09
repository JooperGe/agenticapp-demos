import 'package:flutter_test/flutter_test.dart';
import 'package:urbanrun/game/input/player_input.dart';
import 'package:urbanrun/game/model/geometry.dart';
import 'package:urbanrun/game/model/scene_model.dart';
import 'package:urbanrun/game/model/world_model.dart';
import 'package:urbanrun/game/movement/player_controller.dart';
import 'package:urbanrun/game/transitions/building_transition.dart';

void main() {
  test('finds an entrance only within its squared radius', () {
    final transition = BuildingTransition(
      world: WorldModel.demo(),
      input: PlayerInput(),
    );
    final entrance = transition.nearbyEntrance(const Point2(6.75, 4));

    expect(entrance?.id, 'coffee-shop');
    expect(transition.nearbyEntrance(const Point2(6.75 + 0.7001, 4)), isNull);
  });

  test(
    'enters coffee shop at its target spawn and remembers street return',
    () {
      final world = WorldModel.demo();
      final transition = BuildingTransition(world: world, input: PlayerInput());
      final player = PlayerController(position: const Point2(6.75, 4));

      expect(transition.interact(player), isTrue);
      expect(transition.currentScene, SceneId.coffeeShop);
      expect(player.position, const Point2(2, 6));

      player.position = const Point2(1, 6);
      transition.releaseInteraction();
      expect(transition.interact(player), isTrue);
      expect(transition.currentScene, SceneId.street);
      expect(player.position, const Point2(6.75, 4));
    },
  );

  test('suppresses repeated interaction until release', () {
    final transition = BuildingTransition(
      world: WorldModel.demo(),
      input: PlayerInput(),
    );
    final player = PlayerController(position: const Point2(6.75, 4));

    expect(transition.interact(player), isTrue);
    expect(transition.interact(player), isFalse);

    transition.releaseInteraction();
    player.position = const Point2(1, 6);
    expect(transition.interact(player), isTrue);
  });

  test('requires and retains the input used to clear transitions', () {
    final input = PlayerInput();
    final transition = BuildingTransition(
      world: WorldModel.demo(),
      input: input,
    );

    expect(transition.input, same(input));
  });

  test(
    'clears held movement and running input after a successful scene switch',
    () {
      final input = PlayerInput()
        ..press('w')
        ..press('shift');
      final transition = BuildingTransition(
        world: WorldModel.demo(),
        input: input,
      );
      final player = PlayerController(position: const Point2(6.75, 4));

      expect(transition.interact(player), isTrue);
      expect(input.screenDirection, const Point2(0, 0));
      expect(input.running, isFalse);
    },
  );

  test('rejects a missing destination without moving the player', () {
    const scene = SceneModel(
      id: SceneId.street,
      bounds: Bounds2(0, 0, 10, 10),
      spawn: Point2(1, 1),
      obstacles: <Obstacle>[],
      entrances: <Entrance>[
        Entrance(
          id: 'missing',
          position: Point2(2, 2),
          radius: 1,
          targetScene: SceneId.coffeeShop,
          targetSpawn: Point2(3, 3),
          returnPosition: Point2(2, 2),
        ),
      ],
    );
    final transition = BuildingTransition(
      world: const WorldModel(
        scenes: <SceneId, SceneModel>{SceneId.street: scene},
      ),
      input: PlayerInput(),
    );
    final player = PlayerController(position: const Point2(2, 2));

    expect(transition.interact(player), isFalse);
    expect(transition.currentScene, SceneId.street);
    expect(player.position, const Point2(2, 2));
    expect(transition.errorMessage, contains('destination'));
  });

  test('rejects an occupied target spawn before switching scenes', () {
    const street = SceneModel(
      id: SceneId.street,
      bounds: Bounds2(0, 0, 10, 10),
      spawn: Point2(1, 1),
      obstacles: <Obstacle>[],
      entrances: <Entrance>[
        Entrance(
          id: 'enter',
          position: Point2(2, 2),
          radius: 1,
          targetScene: SceneId.coffeeShop,
          targetSpawn: Point2(3, 3),
          returnPosition: Point2(2, 2),
        ),
      ],
    );
    const interior = SceneModel(
      id: SceneId.coffeeShop,
      bounds: Bounds2(0, 0, 10, 10),
      spawn: Point2(1, 1),
      obstacles: <Obstacle>[Obstacle(Bounds2(2, 2, 4, 4))],
      entrances: <Entrance>[],
    );
    final transition = BuildingTransition(
      world: const WorldModel(
        scenes: <SceneId, SceneModel>{
          SceneId.street: street,
          SceneId.coffeeShop: interior,
        },
      ),
      input: PlayerInput(),
    );
    final player = PlayerController(position: const Point2(2, 2));

    expect(transition.interact(player), isFalse);
    expect(transition.currentScene, SceneId.street);
    expect(player.position, const Point2(2, 2));
    expect(transition.errorMessage, contains('spawn'));
  });

  test('uses safe return fallback when saved return is blocked', () {
    const street = SceneModel(
      id: SceneId.street,
      bounds: Bounds2(0, 0, 10, 10),
      spawn: Point2(1, 1),
      obstacles: <Obstacle>[Obstacle(Bounds2(2, 2, 4, 4))],
      entrances: <Entrance>[
        Entrance(
          id: 'enter',
          position: Point2(1, 1),
          radius: 1,
          targetScene: SceneId.coffeeShop,
          targetSpawn: Point2(1, 1),
          returnPosition: Point2(3, 3),
          safeReturnPosition: Point2(3, 3),
        ),
      ],
    );
    const interior = SceneModel(
      id: SceneId.coffeeShop,
      bounds: Bounds2(0, 0, 10, 10),
      spawn: Point2(1, 1),
      obstacles: <Obstacle>[],
      entrances: <Entrance>[
        Entrance(
          id: 'exit',
          position: Point2(1, 1),
          radius: 1,
          targetScene: SceneId.street,
          targetSpawn: Point2(1, 1),
          returnPosition: Point2(3, 3),
          safeReturnPosition: Point2(5, 5),
        ),
      ],
    );
    final transition = BuildingTransition(
      world: const WorldModel(
        scenes: <SceneId, SceneModel>{
          SceneId.street: street,
          SceneId.coffeeShop: interior,
        },
      ),
      input: PlayerInput(),
    );
    final player = PlayerController(position: const Point2(1, 1));

    expect(transition.interact(player), isTrue);
    expect(transition.interact(player), isFalse);
    transition.releaseInteraction();
    expect(transition.interact(player), isTrue);
    expect(player.position, const Point2(5, 5));
  });

  test('remains indoors when both return positions are unsafe', () {
    const street = SceneModel(
      id: SceneId.street,
      bounds: Bounds2(0, 0, 4, 4),
      spawn: Point2(1, 1),
      obstacles: <Obstacle>[Obstacle(Bounds2(1, 1, 3, 3))],
      entrances: <Entrance>[
        Entrance(
          id: 'enter',
          position: Point2(1, 1),
          radius: 1,
          targetScene: SceneId.coffeeShop,
          targetSpawn: Point2(1, 1),
          returnPosition: Point2(2, 2),
          safeReturnPosition: Point2(2, 2),
        ),
      ],
    );
    const interior = SceneModel(
      id: SceneId.coffeeShop,
      bounds: Bounds2(0, 0, 4, 4),
      spawn: Point2(1, 1),
      obstacles: <Obstacle>[],
      entrances: <Entrance>[
        Entrance(
          id: 'exit',
          position: Point2(1, 1),
          radius: 1,
          targetScene: SceneId.street,
          targetSpawn: Point2(1, 1),
          returnPosition: Point2(2, 2),
          safeReturnPosition: Point2(2, 2),
        ),
      ],
    );
    final transition = BuildingTransition(
      world: const WorldModel(
        scenes: <SceneId, SceneModel>{
          SceneId.street: street,
          SceneId.coffeeShop: interior,
        },
      ),
      input: PlayerInput(),
    );
    final player = PlayerController(position: const Point2(1, 1));

    expect(transition.interact(player), isTrue);
    expect(transition.interact(player), isFalse);
    transition.releaseInteraction();
    expect(transition.interact(player), isFalse);
    expect(transition.currentScene, SceneId.coffeeShop);
    expect(transition.errorMessage, contains('return'));

    player.position = const Point2(3, 3);
    transition.releaseInteraction();
    expect(transition.errorMessage, isNull);
  });
}
