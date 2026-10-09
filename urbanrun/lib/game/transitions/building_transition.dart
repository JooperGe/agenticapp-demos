import '../input/player_input.dart';
import '../model/exploration_progress.dart';
import '../model/geometry.dart';
import '../model/scene_model.dart';
import '../model/world_model.dart';
import '../movement/collision.dart';
import '../movement/player_controller.dart';

class BuildingTransition {
  BuildingTransition({
    required this.world,
    required this.input,
    SceneId initialScene = SceneId.street,
    ExplorationProgress? progress,
  }) : _currentScene = initialScene,
       progress = progress ?? ExplorationProgress();

  final WorldModel world;
  final PlayerInput input;
  final ExplorationProgress progress;
  SceneId _currentScene;
  Point2? _savedReturnPosition;
  Point2? _savedSafeReturnPosition;
  bool _interactionLocked = false;
  String? _errorMessage;

  SceneId get currentScene => _currentScene;
  String? get errorMessage => _errorMessage;

  Entrance? nearbyEntrance(Point2 position) {
    final scene = world.scenes[_currentScene];
    if (scene == null) return null;
    for (final entrance in scene.entrances) {
      final delta = position - entrance.position;
      final radiusSquared = entrance.radius * entrance.radius;
      if (delta.x * delta.x + delta.y * delta.y <= radiusSquared) {
        return entrance;
      }
    }
    return null;
  }

  bool interact(PlayerController player) {
    if (_interactionLocked) return false;

    final entrance = nearbyEntrance(player.position);
    if (entrance == null) {
      _errorMessage = null;
      return false;
    }

    final destination = world.scenes[entrance.targetScene];
    if (destination == null) {
      _errorMessage = 'Cannot transition: destination scene is missing.';
      return false;
    }

    final destinationPosition = _destinationPosition(entrance, player.radius);
    if (destinationPosition == null ||
        !Collision.canOccupy(destinationPosition, player.radius, destination)) {
      if (_currentScene != SceneId.street &&
          entrance.targetScene == SceneId.street) {
        _errorMessage = 'Cannot return: no safe return position is available.';
      } else {
        _errorMessage = 'Cannot transition: destination spawn is blocked.';
      }
      return false;
    }

    final enteringIndoorScene =
        _currentScene == SceneId.street &&
        entrance.targetScene != SceneId.street;
    _currentScene = entrance.targetScene;
    player.position = destinationPosition;
    progress.visit(_currentScene);
    if (enteringIndoorScene) {
      _savedReturnPosition = entrance.returnPosition;
      _savedSafeReturnPosition = entrance.safeReturnPosition;
    } else if (_currentScene == SceneId.street) {
      _savedReturnPosition = null;
      _savedSafeReturnPosition = null;
    }

    input.clear();
    _errorMessage = null;
    _interactionLocked = true;
    return true;
  }

  void releaseInteraction({bool clearError = true}) {
    _interactionLocked = false;
    if (clearError) _errorMessage = null;
  }

  Point2? _destinationPosition(Entrance entrance, double playerRadius) {
    if (_currentScene == SceneId.street ||
        entrance.targetScene != SceneId.street) {
      return entrance.targetSpawn;
    }

    final destination = world.scenes[SceneId.street];
    if (destination == null) return null;

    final candidates = <Point2?>[
      _savedReturnPosition,
      _savedSafeReturnPosition,
      entrance.safeReturnPosition,
      entrance.returnPosition,
    ];
    for (final candidate in candidates) {
      if (candidate != null &&
          Collision.canOccupy(candidate, playerRadius, destination)) {
        return candidate;
      }
    }
    return null;
  }
}
