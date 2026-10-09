import 'package:flutter_test/flutter_test.dart';
import 'package:urbanrun/game/input/player_input.dart';
import 'package:urbanrun/game/model/exploration_progress.dart';
import 'package:urbanrun/game/model/geometry.dart';
import 'package:urbanrun/game/model/scene_model.dart';
import 'package:urbanrun/game/model/world_model.dart';
import 'package:urbanrun/game/movement/collision.dart';
import 'package:urbanrun/game/movement/player_controller.dart';
import 'package:urbanrun/game/transitions/building_transition.dart';

class _BuildingSpec {
  const _BuildingSpec(this.footprint, this.entranceId, this.interior);

  final Bounds2 footprint;
  final String entranceId;
  final SceneId interior;
}

/// Footprint -> interior mapping mirrors building_sprites.dart.
const _buildings = <_BuildingSpec>[
  _BuildingSpec(Bounds2(2, 2, 6, 6), 'coffee-shop', SceneId.coffeeShop),
  _BuildingSpec(
    Bounds2(9, 2, 13, 6),
    'convenience-store',
    SceneId.convenienceStore,
  ),
  _BuildingSpec(Bounds2(16, 2, 20, 6), 'office-a', SceneId.officeA),
  _BuildingSpec(Bounds2(2, 9, 6, 13), 'residential-a', SceneId.residentialA),
  _BuildingSpec(Bounds2(16, 9, 20, 13), 'residential-b', SceneId.residentialB),
  _BuildingSpec(Bounds2(2, 16, 6, 20), 'corner-shop-a', SceneId.cornerShopA),
  _BuildingSpec(Bounds2(9, 16, 13, 20), 'office-b', SceneId.officeB),
  _BuildingSpec(Bounds2(16, 16, 20, 20), 'corner-shop-b', SceneId.cornerShopB),
];

Entrance _streetEntrance(WorldModel world, String id) =>
    world.scenes[SceneId.street]!.entrances.firstWhere((e) => e.id == id);

bool _edgeFacesFootprint(Point2 position, Bounds2 b) {
  // The entrance should sit just outside one of the building edges, i.e. its
  // nearest point on the footprint is on an edge within the player's reach.
  final nearestX = position.x.clamp(b.left, b.right).toDouble();
  final nearestY = position.y.clamp(b.top, b.bottom).toDouble();
  final dx = position.x - nearestX;
  final dy = position.y - nearestY;
  final distance = dx * dx + dy * dy;
  return distance > 0 && distance < 1.0 * 1.0;
}

void main() {
  test('every street building maps to a distinct interior scene', () {
    final world = WorldModel.demo();
    final interiors = _buildings.map((b) => b.interior).toSet();
    expect(interiors.length, 8);
    for (final spec in _buildings) {
      expect(
        world.scenes.containsKey(spec.interior),
        isTrue,
        reason: 'missing interior scene for ${spec.entranceId}',
      );
    }
  });

  for (final spec in _buildings) {
    test('building ${spec.entranceId} is enterable and exitable', () {
      final world = WorldModel.demo();
      final street = world.scenes[SceneId.street]!;
      final transition = BuildingTransition(
        world: world,
        input: PlayerInput(),
        progress: ExplorationProgress(total: 8),
      );
      final entrance = _streetEntrance(world, spec.entranceId);

      // The entrance targets this building's interior and sits just outside the
      // footprint, on a tile the player can actually stand on.
      expect(entrance.targetScene, spec.interior);
      expect(_edgeFacesFootprint(entrance.position, spec.footprint), isTrue);

      final player = PlayerController(position: entrance.position);
      expect(
        Collision.canOccupy(player.position, player.radius, street),
        isTrue,
        reason: 'entrance for ${spec.entranceId} is blocked',
      );
      expect(transition.nearbyEntrance(player.position)?.id, spec.entranceId);

      // Enter: lands in the right interior and marks it visited.
      expect(transition.interact(player), isTrue);
      expect(transition.currentScene, spec.interior);
      expect(transition.progress.visitedCount, 1);
      final interior = world.scenes[spec.interior]!;
      expect(
        Collision.canOccupy(player.position, player.radius, interior),
        isTrue,
      );

      // Exit: returns to the street next to the building, unblocked.
      final exit = interior.entrances.single;
      expect(exit.targetScene, SceneId.street);
      player.position = exit.position;
      transition.releaseInteraction();
      expect(transition.interact(player), isTrue);
      expect(transition.currentScene, SceneId.street);
      expect(
        Collision.canOccupy(player.position, player.radius, street),
        isTrue,
        reason: 'return position for ${spec.entranceId} is blocked',
      );
      expect(player.position, entrance.returnPosition);
      expect(_edgeFacesFootprint(player.position, spec.footprint), isTrue);
    });
  }

  test('visiting all eight interiors completes exploration (8/8)', () {
    final world = WorldModel.demo();
    final transition = BuildingTransition(
      world: world,
      input: PlayerInput(),
      progress: ExplorationProgress(total: 8),
    );
    final player = PlayerController(
      position: world.scenes[SceneId.street]!.spawn,
    );

    for (final spec in _buildings) {
      final entrance = _streetEntrance(world, spec.entranceId);
      player.position = entrance.position;
      transition.releaseInteraction();
      expect(transition.interact(player), isTrue);
      expect(transition.currentScene, spec.interior);

      // Step back out onto the street before entering the next building.
      final exit = world.scenes[spec.interior]!.entrances.single;
      player.position = exit.position;
      transition.releaseInteraction();
      expect(transition.interact(player), isTrue);
      expect(transition.currentScene, SceneId.street);
    }

    expect(transition.progress.visitedCount, 8);
    expect(transition.progress.complete, isTrue);
  });
}
