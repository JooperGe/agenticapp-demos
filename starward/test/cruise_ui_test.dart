import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/vec3.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/models/journey.dart';
import 'package:starward/data/storage/storage_backend.dart';
import 'package:starward/state/game_controller.dart';
import 'package:starward/ui/galaxy3d/cockpit_hud.dart';
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

/// Enters the star map's cockpit mode from the 座舱 side control.
///
/// One bounded pump is enough: `_setMode` `setState`s synchronously in the tap
/// handler, unlike the post-frame cockpit-request path the regression test above
/// pumps twice for.
Future<void> _enterCockpit(WidgetTester tester) async {
  await tester.tap(find.text('座舱'));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Pumps the shell and lands on the star map tab — `IndexedStack` child 0, and
/// the default — so the cockpit is on stage.
///
/// Bounded pumps, never `pumpAndSettle`: the starfield runs a repeating
/// animation controller, so the tree never settles.
Future<void> _pumpStarMap(WidgetTester tester, GameController c) async {
  await tester.pumpWidget(MaterialApp(
    home: GameScope(controller: c, child: const HomeShell()),
  ));
  await tester.pump();
  await tester.tap(find.text('星图'));
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

    // The label is a `switch (mode)` in this page's `_TopBar`, so it reads
    // '星图 · 座舱视角' only in cockpit mode. It lives on the star map, which is
    // IndexedStack child 0, and the default finder skips non-selected
    // IndexedStack children — so finding it pins *both* halves of the tap: the
    // tab switch (the page is onstage) and the mode change (the request was
    // consumed). Neither half can pass on the other's work.
    expect(find.text('星图 · 座舱视角'), findsOneWidget);
  });

  testWidgets('a cockpit request served while already in the cockpit does not '
      'throw', (tester) async {
    final clock = FakeClock(DateTime(2026));
    final c = await _boot(clock, MemoryStorage());
    await tester.pumpWidget(MaterialApp(
      home: GameScope(controller: c, child: const HomeShell()),
    ));
    await tester.pump();

    // Precondition: the star map (IndexedStack child 0, the default tab) is
    // already in cockpit mode before the request arrives. 座舱 is the side
    // control that enters it.
    await tester.tap(find.text('座舱'));
    await tester.pump();
    expect(find.text('星图 · 座舱视角'), findsOneWidget,
        reason: 'precondition: the star map is in cockpit mode');

    // Switch to 航行 and ask for the cockpit again. The star map is still in
    // cockpit mode, so this takes `_maybeEnterRequestedCockpit`'s
    // already-in-cockpit branch. That branch must not acknowledge the request
    // synchronously from inside the LayoutBuilder: `acknowledgeCockpitRequest`
    // notifies listeners, which marks the star map's AnimatedBuilder — an
    // ancestor of the LayoutBuilder, and live even on another tab — dirty
    // during build.
    await tester.tap(find.text('航行'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('点火巡航'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull,
        reason: 'acknowledging inside the LayoutBuilder throws '
            'setState()/markNeedsBuild() called during build');
    expect(find.text('星图 · 座舱视角'), findsOneWidget,
        reason: 'the request is served without leaving cockpit mode');
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

  /// The cockpit's heading bar, scoped by key.
  ///
  /// `HomeShell` mounts all four pages in an `IndexedStack`, so the voyage tab's
  /// dock is in the tree at the same time as this bar — and while cruising both
  /// show a button labelled 修正航向. Default finders skip offstage children, and
  /// an `IndexedStack` only visits its selected one, so an unscoped `find.text`
  /// still finds one; the scoping is defensive, so that a later change to the
  /// finder (or to the shell) cannot quietly start matching the dock's button.
  final cockpit = find.byKey(const Key('cockpit-heading-bar'));

  /// Text inside the heading bar only.
  Finder inCockpit(String text) =>
      find.descendant(of: cockpit, matching: find.text(text));

  testWidgets('the cockpit reads the heading the reticle is pointing at',
      (tester) async {
    final clock = FakeClock(DateTime(2026));
    final c = await _boot(clock, MemoryStorage());
    await _pumpStarMap(tester, c);
    await _enterCockpit(tester);

    expect(cockpit, findsOneWidget);
    // Entering the cockpit aims at the galactic centre, so the readout is
    // whatever that bearing is — the point is that it is a real reading and not
    // a placeholder. A placeholder renders the whole readout as '—  —', so this
    // scopes an em-dash search to the bar's subtree: the readout is the only
    // `Text` in the bar whose data can contain one (the elevation sign is
    // U+2212, a different character), so this fails if the label ever falls
    // back to the placeholder.
    expect(inCockpit('准星航向'), findsOneWidget);
    expect(find.descendant(of: cockpit, matching: find.textContaining('—')),
        findsNothing);
    expect(find.text('对准银心'), findsOneWidget,
        reason: 'the recenter button changes meaning in this mode');

    // The marker layer is on the cockpit, carrying the galactic centre as its
    // fixed reference. (Task 15's `cockpit_hud_test.dart` covers where each
    // marker lands; this pins that the layer is mounted at all.)
    final hudPainters = tester.widgetList<CustomPaint>(find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is CockpitHudPainter));
    expect(hudPainters, hasLength(1),
        reason: 'the cockpit mounts exactly one marker layer');
    final markers =
        (hudPainters.single.painter! as CockpitHudPainter).markers;
    expect(markers.map((m) => m.label), contains('银心'),
        reason: 'the galactic centre is the cockpit\'s fixed reference');
  });

  testWidgets('a parked ship is offered ignition from the cockpit',
      (tester) async {
    final clock = FakeClock(DateTime(2026));
    final c = await _boot(clock, MemoryStorage());
    await _pumpStarMap(tester, c);
    await _enterCockpit(tester);

    expect(inCockpit('点火巡航'), findsOneWidget);
    expect(inCockpit('修正航向'), findsNothing);

    await tester.tap(inCockpit('点火巡航'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.isCruising, isTrue);
    expect(c.hasMomentum, isTrue);
  });

  testWidgets('a cruising ship is quoted the turn and can take it',
      (tester) async {
    final clock = FakeClock(DateTime(2026));
    final c = await _boot(clock, MemoryStorage());
    await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
    clock.advance(const Duration(seconds: 1500));
    await _pumpStarMap(tester, c);
    await _enterCockpit(tester);

    // The ship drifted 40 ly out along +X from a spawn within 0.9 ly of Sol, so
    // aiming back at the galactic centre is an ≈ 180° turn from the current
    // heading — not exactly 180° — which rounds to 200 EN. That is more than the
    // 100 EN a stop costs, so the brake hint must be showing.
    expect(inCockpit('修正航向'), findsOneWidget);
    expect(find.descendant(of: cockpit, matching: find.text('200 EN')),
        findsOneWidget);
    expect(inCockpit('制动停下只需 100 EN'), findsOneWidget);

    await tester.tap(inCockpit('修正航向'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.energy, 0, reason: '300 − 100 burned − 200 turned');
    expect(c.driftVelocity.x, lessThan(0),
        reason: 'now flying the other way');
  });

  testWidgets('a dormant engine is offered activation, not ignition',
      (tester) async {
    final clock = FakeClock(DateTime(2026));
    final c = await _boot(clock, MemoryStorage());
    await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.coast);
    clock.advance(const Duration(seconds: 3000));
    c.tick();
    expect(c.isDormant, isTrue, reason: 'precondition');
    // Running dry queues a fuel-out report. Left queued, the voyage page —
    // built as an `IndexedStack` child — pushes its modal sheet, whose barrier
    // covers the tab bar: `_pumpStarMap`'s tap on 星图 lands on the barrier
    // instead of the nav item (harmless here, the star map is already the
    // default tab) and Flutter logs a hit-test warning. Dismissing the report
    // first keeps the test off that tap timing; the coast test above does the
    // same.
    await c.acknowledgeDriftReport();

    await _pumpStarMap(tester, c);
    await _enterCockpit(tester);

    expect(inCockpit('激活引擎'), findsOneWidget);
    expect(inCockpit('修正航向'), findsNothing);

    await tester.tap(inCockpit('激活引擎'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.isDormant, isFalse);
    expect(c.energy, 95);
  });
}
