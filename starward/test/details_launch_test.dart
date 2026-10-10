import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/balance.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/models/planet.dart';
import 'package:starward/data/storage/storage_backend.dart';
import 'package:starward/state/game_controller.dart';
import 'package:starward/ui/galaxy/planet_details_sheet.dart';
import 'package:starward/ui/game_scope.dart';
import 'package:starward/ui/shell/shell_scope.dart';

/// Verifies the details-sheet launch flow and, crucially, that the re-provided
/// [ShellScope] (sheets are pushed above the shell) is reachable so the tab
/// switch after launch works instead of tripping an assert.
void main() {
  testWidgets('launching from the details sheet travels and switches tab',
      (tester) async {
    final controller = GameController(
      repository: GameRepository(MemoryStorage()),
      random: math.Random(2),
    );
    await controller.init();

    final target = controller.planets.firstWhere((p) =>
        p.id != controller.currentPlanetId &&
        controller.stateOf(p.id) == DiscoveryState.undiscovered &&
        controller.tierTo(p) == TravelTier.short);

    int? switchedTo;
    await tester.pumpWidget(
      MaterialApp(
        home: ShellScope(
          goToTab: (i) => switchedTo = i,
          child: GameScope(
            controller: controller,
            child: Scaffold(
              body: PlanetDetailsSheet(planetId: target.id),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('开始航行'), findsOneWidget);
    await tester.ensureVisible(find.textContaining('开始航行'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('开始航行'));
    await tester.pump();
    await tester.pump();

    expect(controller.isTraveling, isTrue);
    expect(controller.activeJourney!.destinationPlanetId, target.id);
    expect(switchedTo, 1); // jumped to the 航行 tab
  });
}
