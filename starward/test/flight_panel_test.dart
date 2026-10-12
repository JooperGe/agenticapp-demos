import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/storage/storage_backend.dart';
import 'package:starward/state/game_controller.dart';
import 'package:starward/ui/game_scope.dart';
import 'package:starward/ui/shell/home_shell.dart';
import 'package:starward/ui/widgets/common.dart';

/// End-to-end cover for the reported bug: turning back seconds after departure
/// must show a return voyage in flight — not the standby screen reading
/// "漂浮于深空" — and that voyage must name its real (short) distance.
void main() {
  test('short distances keep two decimals instead of rounding to "0 ly"', () {
    expect(StarLabels.distance(0.027), '0.03 ly');
    expect(StarLabels.distance(0.5), '0.50 ly');
    expect(StarLabels.distance(1.4), '1 ly');
    expect(StarLabels.distance(33.77), '34 ly');
  });

  testWidgets('turning back 5 s into a voyage shows the return flight, not 深空',
      (tester) async {
    final clock = _FakeClock(DateTime(2026, 1, 1, 12));
    final controller = GameController(
      repository: GameRepository(MemoryStorage()),
      clock: clock.call,
      random: math.Random(3),
    );
    await controller.init();

    // Dock at a planet first, so 返航 has a planet to come home to.
    final first =
        controller.planets.firstWhere((p) => p.id != controller.currentPlanetId);
    await controller.launchJourney(first);
    clock.advance(const Duration(hours: 2));
    controller.tick();
    final origin = controller.currentPlanet!;

    // Then a long hop, turned around 5 s in.
    final far = controller.planets
        .where((p) => p.id != origin.id)
        .reduce((a, b) =>
            controller.distanceTo(a) > controller.distanceTo(b) ? a : b);
    await controller.launchJourney(far);
    clock.advance(const Duration(seconds: 5));
    await controller.returnToOrigin();

    final back = controller.activeJourney!;
    expect(back.destinationPlanetId, origin.id);
    expect(controller.journeyDistance(back), lessThan(1),
        reason: 'a 5 s old return leg is a very short hop');


    await tester.pumpWidget(
      MaterialApp(
        home: GameScope(controller: controller, child: const HomeShell()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    // Starfields animate forever, so pump fixed frames rather than settle.
    await tester.tap(find.text('航行').last);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('漂浮于深空'), findsNothing,
        reason: 'the bug: 返航 dropped the ship into deep space');
    expect(find.textContaining('航程 0.'), findsOneWidget,
        reason: 'the return voyage shows its real sub-light-year distance');
    expect(find.textContaining('航程 0 ly'), findsNothing);
  });
}

class _FakeClock {
  _FakeClock(this._now);
  DateTime _now;
  DateTime call() => _now;
  void advance(Duration d) => _now = _now.add(d);
}
