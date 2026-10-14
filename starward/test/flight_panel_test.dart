import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/models/engine.dart';
import 'package:starward/data/models/journey.dart'; // FuelPolicy 在这里
import 'package:starward/data/storage/storage_backend.dart';
import 'package:starward/state/game_controller.dart';
import 'package:starward/ui/game_scope.dart';
import 'package:starward/ui/shell/home_shell.dart';
import 'package:starward/ui/widgets/common.dart';
import 'package:starward/ui/widgets/starfield.dart';

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

  testWidgets('a doomed voyage warns on the flight panel', (tester) async {
    final clock = _FakeClock(DateTime(2026));
    final c = await _bootAt(clock);
    await c.installEngine(_greedy);

    // The greedy engine prices the nearest planet beyond a full tank, so the
    // voyage is doomed the moment it departs — p_exhaust < 1. The precondition
    // is asserted relationally rather than against a distance pin because a
    // widget test loads the real HYG catalogue (nearest planet 1.608 ly out,
    // quote 1608), not the curated fallback a plain test sees (2.5983 ly, 2598).
    final target = c.planets
        .where((p) => p.id != c.currentPlanetId)
        .reduce((a, b) => c.distanceTo(a) < c.distanceTo(b) ? a : b);
    final cost = c.energyCostTo(target);
    expect(cost, greaterThan(c.energy));
    expect(c.energy, 300);

    await c.launchJourney(target, onEmpty: FuelPolicy.coast);
    final journey = c.activeJourney!;

    await tester.pumpWidget(
      MaterialApp(home: GameScope(controller: c, child: const HomeShell())),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('航行').last);
    await tester.pump(const Duration(milliseconds: 100));

    // The warning counts down to the moment the tank runs dry, not the ETA.
    expect(find.textContaining('燃料将于'), findsOneWidget);
    expect(
      find.textContaining(
          StarLabels.duration(c.fuelExhaustTime(journey).difference(clock()))),
      findsOneWidget,
    );

    // And the bar carries a marker at p_exhaust.
    expect(find.byKey(const ValueKey('fuel-marker')), findsOneWidget);
  });

  testWidgets('an affordable voyage shows no warning', (tester) async {
    final clock = _FakeClock(DateTime(2026));
    final c = await _bootAt(clock);
    // Same target, standard engine: the nearest hop is a few EN out of 300, so
    // the voyage is never doomed. Relational for the same catalogue reason.
    final target = c.planets
        .where((p) => p.id != c.currentPlanetId)
        .reduce((a, b) => c.distanceTo(a) < c.distanceTo(b) ? a : b);
    expect(c.energyCostTo(target), lessThan(c.energy));

    await c.launchJourney(target);
    await tester.pumpWidget(
      MaterialApp(home: GameScope(controller: c, child: const HomeShell())),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('航行').last);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('燃料将于'), findsNothing);
    expect(find.byKey(const ValueKey('fuel-marker')), findsNothing);
  });

  testWidgets('the coasting starfield streams', (tester) async {
    // Boot a doomed coast exactly as the neighbouring test does, then let the
    // tank run dry so the ship ends up coasting on the standby screen.
    final clock = _FakeClock(DateTime(2026));
    final c = await _bootAt(clock);
    await c.installEngine(_greedy);

    final target = c.planets
        .where((p) => p.id != c.currentPlanetId)
        .reduce((a, b) => c.distanceTo(a) < c.distanceTo(b) ? a : b);
    await c.launchJourney(target, onEmpty: FuelPolicy.coast);
    final journey = c.activeJourney!;

    clock.advance(journey.totalDuration);
    c.tick();
    expect(c.isCoasting, isTrue, reason: 'the tank ran dry and it coasts on');
    expect(c.activeJourney, isNull, reason: 'coasting is not a voyage');
    // Running dry queues a fuel-out report, which the journey page now shows as
    // a modal sheet. Its barrier would cover the tab bar, so clear it: this test
    // is about the starfield, and the sheet has its own coverage.
    await c.acknowledgeDriftReport();

    await tester.pumpWidget(
      MaterialApp(home: GameScope(controller: c, child: const HomeShell())),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('航行').last);
    await tester.pump();

    final first = tester
        .widget<StarfieldBackground>(find.byType(StarfieldBackground))
        .scrollSpeed;
    await tester.pump(const Duration(seconds: 2));
    final second = tester
        .widget<StarfieldBackground>(find.byType(StarfieldBackground))
        .scrollSpeed;
    expect(second, greaterThan(first),
        reason: 'the star-stream must keep moving while coasting');
  });

  testWidgets('a queued drift report auto-shows when the journey view mounts',
      (tester) async {
    // Boot a doomed coast exactly as `the coasting starfield streams` does, then
    // let the tank run dry: that queues a fuel-out report. Unlike that test we
    // leave the report queued — this is its complement, and the report must
    // surface on its own. The journey page is always mounted inside the shell's
    // IndexedStack, so the sheet opens as soon as the shell is pumped; there is
    // no tab to tap, because the sheet's barrier would cover the tab bar.
    final clock = _FakeClock(DateTime(2026));
    final c = await _bootAt(clock);
    await c.installEngine(_greedy);

    final target = c.planets
        .where((p) => p.id != c.currentPlanetId)
        .reduce((a, b) => c.distanceTo(a) < c.distanceTo(b) ? a : b);
    await c.launchJourney(target, onEmpty: FuelPolicy.coast);
    final journey = c.activeJourney!;

    clock.advance(journey.totalDuration);
    c.tick();
    expect(c.pendingDriftReport, isNotNull,
        reason: 'running dry queues a report, left unacknowledged here');

    await tester.pumpWidget(
      MaterialApp(home: GameScope(controller: c, child: const HomeShell())),
    );
    await tester.pump(const Duration(milliseconds: 100));
    // The sheet opens from a post-frame callback: give it a frame to fire and
    // its entrance animation a moment to run.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('燃料耗尽'), findsOneWidget,
        reason: 'the queued report auto-shows as the drift report sheet');
    expect(find.text('知道了'), findsOneWidget);
  });

  testWidgets('the coasting readout shows the live drift totals',
      (tester) async {
    // Spec §6.2 (在线播报) requires the coasting page to show the running totals
    // live, and §6.3's row 3 (在线滚动播报) is implemented by this readout.
    // Acknowledge the fuel-out sheet so its barrier does not cover the dock,
    // then assert the real strings the dock renders.
    final clock = _FakeClock(DateTime(2026));
    final c = await _bootAt(clock);
    await c.installEngine(_greedy);

    final target = c.planets
        .where((p) => p.id != c.currentPlanetId)
        .reduce((a, b) => c.distanceTo(a) < c.distanceTo(b) ? a : b);
    await c.launchJourney(target, onEmpty: FuelPolicy.coast);
    final journey = c.activeJourney!;

    clock.advance(journey.totalDuration);
    c.tick();
    expect(c.isCoasting, isTrue, reason: 'the tank ran dry and it coasts on');
    await c.acknowledgeDriftReport();

    await tester.pumpWidget(
      MaterialApp(home: GameScope(controller: c, child: const HomeShell())),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('航行').last);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('途经恒星系'), findsOneWidget,
        reason: 'the coasting dock shows how many systems the drift passed');
    expect(find.text('查看播报'), findsOneWidget,
        reason: 'the dock offers the on-demand drift report');
  });
}

class _FakeClock {
  _FakeClock(this._now);
  DateTime _now;
  DateTime call() => _now;
  void advance(Duration d) => _now = _now.add(d);
}

/// A thousand energy per light-year makes any real hop unaffordable, which is
/// the cheapest way to reach a doomed voyage without draining the tank first.
const _greedy = Engine(
  id: 'test.greedy',
  name: '测试引擎',
  energyPerLy: 1000,
  cruiseSpeedLyPerSec: 1 / 37.5,
  brakingDistanceLy: 40,
  minEnergyCost: 1,
  minTravelSeconds: 15,
  activationCost: 5,
);

Future<GameController> _bootAt(_FakeClock clock) async {
  final c = GameController(
    repository: GameRepository(MemoryStorage()),
    clock: clock.call,
    random: math.Random(3),
  );
  await c.init();
  return c;
}
