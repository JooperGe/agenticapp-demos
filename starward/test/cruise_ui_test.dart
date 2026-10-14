import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/vec3.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/models/journey.dart';
import 'package:starward/data/storage/storage_backend.dart';
import 'package:starward/state/game_controller.dart';
import 'package:starward/ui/game_scope.dart';
import 'package:starward/ui/shell/home_shell.dart';

class FakeClock {
  FakeClock(this._now);
  DateTime _now;
  DateTime call() => _now;
  void advance(Duration d) => _now = _now.add(d);
}

Future<GameController> _boot(FakeClock clock, MemoryStorage storage) async {
  final c = GameController(
    repository: GameRepository(storage),
    clock: clock.call,
    random: math.Random(3),
  );
  await c.init();
  return c;
}

/// Pumps the shell and lands on the voyage tab, so its standby state is on
/// screen.
///
/// Bounded pumps, never `pumpAndSettle`: the starfield runs a repeating
/// animation controller, so the tree never settles — the same reason
/// `braking_test.dart` pumps fixed frames.
Future<void> _pumpVoyage(WidgetTester tester, GameController c) async {
  await tester.pumpWidget(MaterialApp(
    home: GameScope(controller: c, child: const HomeShell()),
  ));
  await tester.pump();
  await tester.tap(find.text('航行'));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('a stranded ship is offered a way to light the engine',
      (tester) async {
    final clock = FakeClock(DateTime(2026));
    final c = await _boot(clock, MemoryStorage());
    expect(c.inDeepSpace, isTrue);
    expect(c.hasMomentum, isFalse, reason: 'precondition: parked in deep space');

    await _pumpVoyage(tester, c);
    expect(find.text('点火巡航'), findsOneWidget);
    expect(find.text('深空待命'), findsOneWidget);
  });

  testWidgets('tapping it asks the star map for the cockpit', (tester) async {
    final clock = FakeClock(DateTime(2026));
    final c = await _boot(clock, MemoryStorage());
    await _pumpVoyage(tester, c);

    await tester.tap(find.text('点火巡航'));
    // The tap raises the request synchronously, and the star map — already in
    // the tree as IndexedStack child 0 — consumes it in the very next frame.
    // So the request has to be read *before* pumping: one pump later it has
    // been acknowledged and this line would read false.
    expect(c.cockpitRequested, isTrue);

    await tester.pump(const Duration(milliseconds: 100));
    // A second bounded pump. `_maybeEnterRequestedCockpit` defers `_setMode` to
    // a post-frame callback, and that `setState` only renders on the *next*
    // frame, so the frame above still shows the old label. Never
    // `pumpAndSettle`: the starfield runs a repeating animation controller
    // (`starfield.dart:97`), so no starfield screen ever settles.
    await tester.pump(const Duration(milliseconds: 100));

    // The label is a `switch (mode)` in galaxy_map_3d_page.dart:478-483, so it
    // reads '星图 · 座舱视角' only in cockpit mode. It lives on the star map, which
    // is IndexedStack child 0, and the default finder skips non-selected
    // IndexedStack children — so finding it pins *both* halves of the tap:
    // the tab switch (the page is onstage) and the mode change (the request was
    // consumed). Neither half can pass on the other's work.
    expect(find.text('星图 · 座舱视角'), findsOneWidget);
  });

  testWidgets('a cruising ship reads as cruising, not as coasting',
      (tester) async {
    final clock = FakeClock(DateTime(2026));
    final storage = MemoryStorage();
    final c = await _boot(clock, storage);
    await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
    clock.advance(const Duration(seconds: 1500));
    await _pumpVoyage(tester, c);

    // Two surfaces name the state: the standby headline and the _TopBar
    // subtitle. Both have to agree, so the count is the assertion.
    expect(find.text('巡航中'), findsNWidgets(2));
    expect(find.text('滑行中'), findsNothing);
    expect(find.text('已巡航'), findsOneWidget);
    expect(find.text('可维持'), findsOneWidget);
    expect(find.text('修正航向'), findsOneWidget,
        reason: 'a cruise steers rather than stops to turn');
    expect(find.text('0.07 EN/s'), findsOneWidget);
  });

  testWidgets('a coast still reads as a coast', (tester) async {
    final clock = FakeClock(DateTime(2026));
    final storage = MemoryStorage();
    final c = await _boot(clock, storage);
    await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.coast);
    clock.advance(const Duration(seconds: 3000));
    c.tick();
    expect(c.isCoasting, isTrue, reason: 'precondition: out of power');
    // Running dry queues a fuel-out report, and its sheet is modal: left
    // queued, its barrier covers the tab bar and the voyage tab is never
    // reached. Dismiss it here — the report is a separate surface with its own
    // tests, and this test is about the coast dock behind it.
    await c.acknowledgeDriftReport();
    await _pumpVoyage(tester, c);

    // The headline and the _TopBar subtitle both name the state.
    expect(find.text('滑行中'), findsNWidgets(2));
    expect(find.text('已滑行'), findsOneWidget);
    expect(find.text('可维持'), findsNothing,
        reason: 'a coast has no burn left to run out of');
    expect(find.text('改变航向'), findsOneWidget);
  });

  testWidgets('the ticker resolves a cruise that runs dry while on screen',
      (tester) async {
    final clock = FakeClock(DateTime(2026));
    final c = await _boot(clock, MemoryStorage());
    await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.coast);
    await _pumpVoyage(tester, c);
    expect(find.text('巡航中'), findsNWidgets(2));

    // 200 EN of spendable budget at 1/15 EN/s is 3000 s; past it the tank is
    // down to the 100 EN braking reserve and the cruise has to resolve.
    clock.advance(const Duration(seconds: 3100));
    // Let the voyage screen's one-second ticker call tick(), which is what
    // resolves the burn. Nothing else in the app calls it.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));

    expect(c.isCoasting, isTrue,
        reason: "only this screen's ticker calls tick(), which resolves the "
            'burn — without it the ship cruises on forever');
    expect(find.text('滑行中'), findsNWidgets(2));
    expect(find.text('巡航中'), findsNothing);
  });

  testWidgets('the voyage tab badge lights for a cruising ship', (tester) async {
    final clock = FakeClock(DateTime(2026));
    final c = await _boot(clock, MemoryStorage());
    await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
    await _pumpVoyage(tester, c);

    expect(find.byKey(const Key('voyage-tab-badge')), findsOneWidget,
        reason: 'a cruise is motion the voyage tab has to advertise');
  });

  testWidgets('the voyage tab badge stays dark for a parked ship',
      (tester) async {
    final clock = FakeClock(DateTime(2026));
    final c = await _boot(clock, MemoryStorage());
    await _pumpVoyage(tester, c);

    expect(find.byKey(const Key('voyage-tab-badge')), findsNothing);
  });

  testWidgets('braking a cruise is confirmed as a cruise, not a coast',
      (tester) async {
    final clock = FakeClock(DateTime(2026));
    final c = await _boot(clock, MemoryStorage());
    await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
    clock.advance(const Duration(seconds: 1500));
    await _pumpVoyage(tester, c);

    await tester.tap(find.text('制动停下'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('停止巡航'), findsOneWidget);
    expect(find.textContaining('本次巡航'), findsOneWidget);
    expect(find.text('停止滑行'), findsNothing);
  });
}
