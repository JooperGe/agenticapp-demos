import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'input/player_input.dart';
import 'model/exploration_progress.dart';
import 'model/geometry.dart';
import 'model/scene_model.dart';
import 'model/world_model.dart';
import 'movement/player_controller.dart';
import 'projection/iso_projection.dart';
import 'render/city_renderer.dart';
import 'render/interaction_renderer.dart';
import 'render/player_renderer.dart';
import 'transitions/building_transition.dart';
import 'hud/urbanrun_hud.dart';

export 'hud/urbanrun_hud.dart' show GameHudState;

class UrbanrunGame extends FlameGame {
  UrbanrunGame({WorldModel? world})
    : worldModel = world ?? WorldModel.demo(),
      projection = const IsoProjection(),
      input = PlayerInput(),
      hudState = ValueNotifier<GameHudState>(const GameHudState.street());

  final WorldModel worldModel;
  final IsoProjection projection;
  final PlayerInput input;
  final ValueNotifier<GameHudState> hudState;
  final CityRenderer cityRenderer = const CityRenderer();
  final PlayerRenderer playerRenderer = const PlayerRenderer();
  final InteractionRenderer interactionRenderer = const InteractionRenderer();

  late final PlayerController player;
  late final BuildingTransition transition;
  double _animationTime = 0;
  double _cameraX = 0;
  double _cameraY = 0;
  bool _hasFocus = true;
  bool _interacting = false;
  bool _gameStateReady = false;
  bool _interactionRequested = false;
  String? _feedbackMessage;
  bool _feedbackIsError = false;
  double _feedbackRemaining = 0;
  bool _completionFeedbackShown = false;
  bool _disposed = false;

  SceneModel get scene => worldModel.scenes[transition.currentScene]!;
  double get cameraX => _cameraX;
  double get cameraY => _cameraY;

  @override
  Future<void> onLoad() async {
    player = PlayerController(
      position: worldModel.scenes[SceneId.street]!.spawn,
    );
    transition = BuildingTransition(
      world: worldModel,
      input: input,
      progress: ExplorationProgress(),
    );
    _gameStateReady = true;
    if (_interactionRequested) {
      _interactionRequested = false;
      _performInteraction();
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_gameStateReady) _publishHud();
    });
  }

  @override
  void update(double dt) {
    super.update(dt);
    _advanceFeedback(dt);
    if (!_hasFocus) return;
    final direction = input.groundDirection(projection);
    final moving = direction.length > 0;
    player.move(direction, dt, scene, running: input.running);
    _animationTime += moving ? dt : 0;
    if (input.consumeInteraction()) {
      input.release('e');
      _performInteraction();
    }
    if (_interactionRequested) {
      _interactionRequested = false;
      _performInteraction();
    }
    if (_interacting && !input.screenDirection.length.isFinite) {
      _interacting = false;
    }
    final target = projection.worldToScreen(player.position);
    final smoothing = (dt * 8).clamp(0.0, 1.0);
    _cameraX += (target.x - _cameraX) * smoothing;
    _cameraY += (target.y - _cameraY) * smoothing;
    _publishHud();
  }

  @override
  void render(ui.Canvas canvas) {
    super.render(canvas);
    final size = canvasSize;
    canvas.drawColor(const ui.Color(0xFF0B1018), ui.BlendMode.src);
    final sceneBounds = _projectedBounds(scene);
    final viewportCenter = Point2(size.x / 2, size.y / 2);
    final sceneCenter = Point2(
      (sceneBounds.left + sceneBounds.right) / 2,
      (sceneBounds.top + sceneBounds.bottom) / 2,
    );
    final offset = cameraOffsetForTarget(
      cameraTarget: Point2(_cameraX, _cameraY),
      bounds: sceneBounds,
      viewportWidth: size.x,
      viewportHeight: size.y,
      sceneCenter: sceneCenter,
      viewportCenter: viewportCenter,
    );
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    final playerScreen = projection.worldToScreen(player.position);
    cityRenderer.render(
      canvas,
      scene,
      projection,
      additionalItems: <CityRenderItem>[
        CityRenderItem(
          groundFoot: player.position,
          paint: () => playerRenderer.render(
            canvas,
            playerScreen,
            player.facing,
            _animationTime,
            input.groundDirection(projection).length > 0,
          ),
        ),
      ],
    );
    final entrance = transition.nearbyEntrance(player.position);
    if (entrance != null) {
      interactionRenderer.render(
        canvas,
        playerScreen,
        'E  ${entrance.targetScene == SceneId.street ? 'EXIT' : 'ENTER'}',
      );
    }
    canvas.restore();
  }

  void requestInteraction() {
    if (!_gameStateReady) {
      _interactionRequested = true;
      return;
    }
    _performInteraction();
  }

  void onKeyDown(LogicalKeyboardKey key) {
    input.press(_keyName(key));
  }

  void onKeyUp(LogicalKeyboardKey key) {
    input.release(_keyName(key));
    if (key == LogicalKeyboardKey.keyE) {
      _releaseInteraction();
    }
  }

  void clearInput() {
    input.clear();
    if (_gameStateReady && !_disposed) {
      transition.releaseInteraction();
      _interacting = false;
      if (_feedbackIsError) {
        _feedbackMessage = null;
        _feedbackRemaining = 0;
        _feedbackIsError = false;
      }
      _publishHud();
    }
    _hasFocus = false;
  }

  void resumeInput() {
    _hasFocus = true;
  }

  void _performInteraction() {
    final completedBefore = transition.progress.complete;
    _interacting = transition.interact(player);
    if (_interacting) {
      // Input edge detection is the one-shot guard. Release the transition
      // lock here so pointer-up and keyboard paths have the same result.
      transition.releaseInteraction();
      if (_feedbackIsError) _clearFeedback();
      if (!completedBefore && transition.progress.complete &&
          !_completionFeedbackShown) {
        _completionFeedbackShown = true;
        _showFeedback('探索完成 · 两处室内空间已发现');
      }
    } else if (transition.errorMessage != null) {
      // Keep the error visible briefly, then clear it without requiring a
      // follow-up key-up or interaction.
      transition.releaseInteraction(clearError: false);
      _showFeedback(transition.errorMessage!, isError: true);
    }
    _publishHud();
  }

  void _releaseInteraction() {
    if (!_gameStateReady) return;
    transition.releaseInteraction();
    _interacting = false;
    _publishHud();
  }

  void _showFeedback(String message, {bool isError = false}) {
    _feedbackMessage = message;
    _feedbackIsError = isError;
    _feedbackRemaining = 1.8;
  }

  void _advanceFeedback(double dt) {
    if (_feedbackMessage == null) return;
    _feedbackRemaining -= dt;
    if (_feedbackRemaining > 0) return;
    _clearFeedback();
    _publishHud();
  }

  void _clearFeedback() {
    _feedbackMessage = null;
    _feedbackRemaining = 0;
    if (_feedbackIsError) transition.releaseInteraction();
    _feedbackIsError = false;
  }

  @override
  void onRemove() {
    clearInput();
    _disposed = true;
    hudState.dispose();
    super.onRemove();
  }

  void _publishHud() {
    if (!_gameStateReady || _disposed) return;
    final nearby = transition.nearbyEntrance(player.position);
    final currentScene = scene;
    hudState.value = GameHudState(
      sceneName: _sceneName(transition.currentScene),
      visitedCount: transition.progress.visitedCount,
      complete: transition.progress.complete,
      interactionLabel: nearby == null ? null : _interactionLabel(nearby),
      playerPosition: player.position,
      errorMessage: _feedbackIsError ? _feedbackMessage : null,
      successMessage: !_feedbackIsError ? _feedbackMessage : null,
      scene: currentScene.id,
      sceneModel: currentScene,
    );
  }

  String _sceneName(SceneId id) {
    switch (id) {
      case SceneId.street:
        return '探索街区';
      case SceneId.coffeeShop:
        return '咖啡店 · 室内';
      case SceneId.convenienceStore:
        return '便利店 · 室内';
    }
  }

  String _interactionLabel(Entrance entrance) {
    if (entrance.targetScene == SceneId.street) return '离开室内';
    switch (entrance.targetScene) {
      case SceneId.coffeeShop:
        return '进入咖啡店';
      case SceneId.convenienceStore:
        return '进入便利店';
      case SceneId.street:
        return '返回街区';
    }
  }

  Bounds2 _projectedBounds(SceneModel value) {
    final points = <Point2>[
      projection.worldToScreen(Point2(value.bounds.left, value.bounds.top)),
      projection.worldToScreen(Point2(value.bounds.right, value.bounds.top)),
      projection.worldToScreen(Point2(value.bounds.right, value.bounds.bottom)),
      projection.worldToScreen(Point2(value.bounds.left, value.bounds.bottom)),
    ];
    return Bounds2(
      points.map((point) => point.x).reduce((a, b) => a < b ? a : b),
      points.map((point) => point.y).reduce((a, b) => a < b ? a : b),
      points.map((point) => point.x).reduce((a, b) => a > b ? a : b),
      points.map((point) => point.y).reduce((a, b) => a > b ? a : b),
    );
  }

  String _keyName(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowUp) return 'arrowup';
    if (key == LogicalKeyboardKey.arrowDown) return 'arrowdown';
    if (key == LogicalKeyboardKey.arrowLeft) return 'arrowleft';
    if (key == LogicalKeyboardKey.arrowRight) return 'arrowright';
    if (key == LogicalKeyboardKey.shiftLeft) return 'shiftleft';
    if (key == LogicalKeyboardKey.shiftRight) return 'shiftright';
    if (key == LogicalKeyboardKey.keyW) return 'w';
    if (key == LogicalKeyboardKey.keyA) return 'a';
    if (key == LogicalKeyboardKey.keyS) return 's';
    if (key == LogicalKeyboardKey.keyD) return 'd';
    if (key == LogicalKeyboardKey.keyE) return 'e';
    return key.keyLabel;
  }
}

/// Computes a single camera translation from the smoothed screen-space target.
///
/// Small worlds are centered instead of passing an invalid clamp range.
ui.Offset cameraOffsetForTarget({
  required Point2 cameraTarget,
  required Bounds2 bounds,
  required double viewportWidth,
  required double viewportHeight,
  required Point2 sceneCenter,
  required Point2 viewportCenter,
}) {
  final x = bounds.width <= viewportWidth
      ? viewportCenter.x - sceneCenter.x
      : (viewportCenter.x - cameraTarget.x).clamp(
          viewportWidth - bounds.right,
          -bounds.left,
        );
  final y = bounds.height <= viewportHeight
      ? viewportCenter.y - sceneCenter.y
      : (viewportCenter.y - cameraTarget.y).clamp(
          viewportHeight - bounds.bottom,
          -bounds.top,
        );
  return ui.Offset(x.toDouble(), y.toDouble());
}
