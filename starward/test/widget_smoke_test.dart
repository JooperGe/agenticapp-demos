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
}
