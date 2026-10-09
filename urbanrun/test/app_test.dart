import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:urbanrun/app.dart';
import 'package:urbanrun/game/hud/urbanrun_hud.dart';
import 'package:urbanrun/game/model/geometry.dart';
import 'package:urbanrun/game/model/scene_model.dart';
import 'package:urbanrun/game/model/world_model.dart';
import 'package:urbanrun/game/render/city_renderer.dart';
import 'package:urbanrun/game/urbanrun_game.dart';

void main() {
  testWidgets('mounts the Urbanrun game host and title', (tester) async {
    await tester.pumpWidget(const UrbanrunApp());

    expect(
      find.byWidgetPredicate((widget) => widget is GameWidget),
      findsOneWidget,
    );
    expect(find.text('URBANRUN'), findsOneWidget);
  });

  test(
    'GameHudState starts at the street with no visited or nearby building',
    () {
      final game = UrbanrunGame();
      final state = game.hudState.value;

      expect(state.sceneName, '探索街区');
      expect(state.visitedCount, 0);
      expect(state.complete, isFalse);
      expect(state.interactionLabel, isNull);
      expect(state.errorMessage, isNull);
    },
  );

  testWidgets('HUD shows initial exploration progress', (tester) async {
    final state = ValueNotifier<GameHudState>(GameHudState.street());
    await tester.pumpWidget(
      MaterialApp(
        home: UrbanrunHud(state: state, onInteract: () {}),
      ),
    );

    expect(find.text('探索街区 0/8'), findsOneWidget);
  });

  testWidgets('HUD shows completed exploration progress', (tester) async {
    final state = ValueNotifier<GameHudState>(
      GameHudState(
        sceneName: '探索街区',
        visitedCount: 8,
        total: 8,
        complete: true,
        interactionLabel: null,
        playerPosition: const Point2(12, 12),
        errorMessage: null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: UrbanrunHud(state: state, onInteract: () {}),
      ),
    );

    expect(find.text('探索街区 8/8'), findsOneWidget);
    expect(find.text('区域已探索'), findsOneWidget);
  });

  testWidgets('HUD only exposes interaction control for a target', (
    tester,
  ) async {
    var calls = 0;
    final state = ValueNotifier<GameHudState>(GameHudState.street());
    await tester.pumpWidget(
      MaterialApp(
        home: UrbanrunHud(state: state, onInteract: () => calls++),
      ),
    );
    expect(find.textContaining('E'), findsNothing);

    state.value = GameHudState(
      sceneName: '探索街区',
      visitedCount: 0,
      complete: false,
      interactionLabel: '进入咖啡店',
      playerPosition: const Point2(6.75, 4),
      errorMessage: null,
    );
    await tester.pump();
    expect(find.text('E'), findsOneWidget);
    await tester.tap(find.text('E'));
    expect(calls, 1);
  });

  test('requestInteraction is one-shot and does not leave E held', () async {
    final game = UrbanrunGame();
    await game.onLoad();

    game.requestInteraction();
    expect(game.input.consumeInteraction(), isFalse);
    expect(game.input.screenDirection, const Point2(0, 0));
  });

  test(
    'requestInteraction can enter and exit again without a sticky lock',
    () async {
      final game = UrbanrunGame();
      await game.onLoad();

      game.player.position = const Point2(6.75, 4);
      game.requestInteraction();
      expect(game.scene.id, SceneId.coffeeShop);

      game.player.position = const Point2(1, 6);
      game.requestInteraction();
      expect(game.scene.id, SceneId.street);
      expect(game.input.consumeInteraction(), isFalse);
    },
  );

  test('keyboard and pointer interaction share the same one-shot path', () async {
    final game = UrbanrunGame();
    await game.onLoad();
    game.player.position = const Point2(6.75, 4);

    game.onKeyDown(LogicalKeyboardKey.keyE);
    game.update(0);
    expect(game.scene.id, SceneId.coffeeShop);
    game.onKeyUp(LogicalKeyboardKey.keyE);

    game.player.position = const Point2(1, 6);
    game.requestInteraction();
    expect(game.scene.id, SceneId.street);
    expect(game.hudState.value.errorMessage, isNull);
  });

  test('clearInput releases the interaction state before the next interaction', () async {
    final game = UrbanrunGame();
    await game.onLoad();
    game.player.position = const Point2(6.75, 4);

    game.onKeyDown(LogicalKeyboardKey.keyE);
    game.update(0);
    game.clearInput();

    game.player.position = const Point2(1, 6);
    game.resumeInput();
    game.requestInteraction();
    expect(game.scene.id, SceneId.street);
    expect(game.hudState.value.errorMessage, isNull);
  });

  test('completion feedback is edge-triggered and expires', () async {
    final game = UrbanrunGame();
    await game.onLoad();

    // Street entrance positions for all eight enterable buildings.
    const entrances = <Point2>[
      Point2(6.75, 4), // coffee shop
      Point2(11, 6.75), // convenience store
      Point2(15.25, 4), // office A
      Point2(6.75, 11), // residential A
      Point2(15.25, 11), // residential B
      Point2(6.75, 18), // corner shop A
      Point2(11, 15.25), // office B
      Point2(15.25, 18), // corner shop B
    ];
    const interiorExit = Point2(1, 6);

    for (var i = 0; i < entrances.length; i++) {
      game.player.position = entrances[i];
      game.requestInteraction();
      expect(game.scene.id, isNot(SceneId.street));
      if (i < entrances.length - 1) {
        game.player.position = interiorExit;
        game.requestInteraction();
        expect(game.scene.id, SceneId.street);
      }
    }

    expect(game.hudState.value.complete, isTrue);
    expect(game.hudState.value.visitedCount, 8);
    expect(game.hudState.value.successMessage, '探索完成 · 已发现全部 8 处室内空间');
    game.update(2);
    expect(game.hudState.value.successMessage, isNull);

    game.requestInteraction();
    expect(game.hudState.value.complete, isTrue);
    expect(game.hudState.value.successMessage, isNull);
  });

  test('failed interaction error feedback expires without another input', () async {
    const world = WorldModel(
      scenes: <SceneId, SceneModel>{
        SceneId.street: SceneModel(
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
              targetSpawn: Point2(2, 2),
              returnPosition: Point2(2, 2),
            ),
          ],
        ),
      },
    );
    final game = UrbanrunGame(world: world);
    await game.onLoad();
    game.player.position = const Point2(2, 2);

    game.requestInteraction();
    expect(game.hudState.value.errorMessage, contains('missing'));
    game.update(2);
    expect(game.hudState.value.errorMessage, isNull);
  });

  test(
    'camera offset follows one target and centers worlds smaller than viewport',
    () {
      final offset = cameraOffsetForTarget(
        cameraTarget: const Point2(60, 40),
        bounds: const Bounds2(0, 0, 200, 100),
        viewportWidth: 100,
        viewportHeight: 100,
        sceneCenter: const Point2(100, 50),
        viewportCenter: const Point2(50, 50),
      );
      expect(offset.dx, -10);
      expect(offset.dy, 0);

      final centered = cameraOffsetForTarget(
        cameraTarget: const Point2(999, 999),
        bounds: const Bounds2(10, 20, 20, 30),
        viewportWidth: 100,
        viewportHeight: 100,
        sceneCenter: const Point2(15, 25),
        viewportCenter: const Point2(50, 50),
      );
      expect(centered.dx, 35);
      expect(centered.dy, 25);
    },
  );

  test('render depth comes from explicit ground-foot coordinates', () {
    const obstacle = Obstacle(Bounds2(2, 3, 6, 9));

    expect(obstacle.groundFoot, const Point2(6, 9));
    expect(groundDepth(obstacle.groundFoot), 15);
    expect(groundDepth(const Point2(1, 8)), 9);
  });

  test('player and city items are sorted together by ground depth', () {
    final calls = <String>[];
    final sorted = sortCityRenderItems(<CityRenderItem>[
      CityRenderItem(
        groundFoot: const Point2(6, 6),
        paint: () => calls.add('city-after'),
      ),
      CityRenderItem(
        groundFoot: const Point2(4, 4),
        paint: () => calls.add('city-before'),
      ),
      CityRenderItem(
        groundFoot: const Point2(5, 5),
        paint: () => calls.add('player'),
      ),
    ]);
    for (final item in sorted) {
      item.paint();
    }

    expect(calls, <String>['city-before', 'player', 'city-after']);
  });
}
