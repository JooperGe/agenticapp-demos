import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/storage/storage_backend.dart';
import 'package:starward/state/game_controller.dart';
import 'package:starward/ui/game_scope.dart';
import 'package:starward/ui/shell/home_shell.dart';

/// Smoke test: the whole shell (all four tab pages live inside an IndexedStack)
/// must build without throwing. This catches integration/layout wiring errors
/// that unit tests on the controller can't.
void main() {
  testWidgets('home shell builds all tabs without error', (tester) async {
    final controller = GameController(repository: GameRepository(MemoryStorage()));
    await controller.init();

    await tester.pumpWidget(
      MaterialApp(
        home: GameScope(controller: controller, child: const HomeShell()),
      ),
    );
    // Starfields animate forever, so pump fixed frames rather than settle.
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('星图'), findsWidgets);
    expect(find.text('航行'), findsWidgets);
    expect(find.text('发现'), findsWidgets);
    expect(find.text('训练'), findsWidgets);

    // Switch to each tab to force its subtree through a real layout pass.
    for (final label in <String>['训练', '发现', '航行', '星图']) {
      await tester.tap(find.text(label).last);
      await tester.pump(const Duration(milliseconds: 100));
    }
  });

  testWidgets('the universe overview is reachable and replaces the sensor bar',
      (tester) async {
    final controller =
        GameController(repository: GameRepository(MemoryStorage()));
    await controller.init();

    await tester.pumpWidget(
      MaterialApp(
        home: GameScope(controller: controller, child: const HomeShell()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('星图 · 总览'), findsOneWidget);
    expect(find.text('飞行器传感器范围'), findsOneWidget);

    await tester.tap(find.text('寰宇'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('星图 · 寰宇'), findsOneWidget);
    // The overview painter built without throwing — a smoke test cannot assert
    // what it drew, only that the whole subtree survived a real layout pass.

    await tester.tap(find.text('总览'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('星图 · 总览'), findsOneWidget);
    expect(find.text('飞行器传感器范围'), findsOneWidget);

    // And the third mode still works after a round trip through the overview.
    await tester.tap(find.text('座舱'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('星图 · 座舱视角'), findsOneWidget);
  });
}
