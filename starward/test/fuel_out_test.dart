import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/models/engine.dart';
import 'package:starward/data/models/journey.dart';
import 'package:starward/data/models/planet.dart';
import 'package:starward/data/storage/storage_backend.dart';
import 'package:starward/state/game_controller.dart';
import 'package:starward/ui/journey/fuel_choice_dialog.dart';

class FakeClock {
  FakeClock(this._now);
  DateTime _now;
  DateTime call() => _now;
  void advance(Duration d) => _now = _now.add(d);
}

Future<GameController> _boot(FakeClock clock, {MemoryStorage? storage}) async {
  final c = GameController(
    repository: GameRepository(storage ?? MemoryStorage()),
    clock: clock.call,
    random: math.Random(3),
  );
  await c.init();
  return c;
}

/// Rewrites the saved balance, so a test can start from a tank it chooses.
///
/// Flying hops down to a target is not deterministic: a refuse launch stops at
/// the first hop it cannot afford, and no sequence of hops lands on exactly
/// zero. Writing the balance is exact.
Future<void> _setEnergy(MemoryStorage storage, int balance) async {
  final raw = await storage.read('starward.save.v2');
  final json = jsonDecode(raw!) as Map<String, dynamic>;
  (json['player'] as Map<String, dynamic>)['energyBalance'] = balance;
  await storage.write('starward.save.v2', jsonEncode(json));
}

/// Boots a controller whose tank holds exactly [balance].
Future<GameController> _bootWithEnergy(FakeClock clock, int balance) async {
  final storage = MemoryStorage();
  await _boot(clock, storage: storage);
  await _setEnergy(storage, balance);
  return _boot(clock, storage: storage);
}

/// The farthest reachable target — the one most likely to be unaffordable.
Planet _farthest(GameController c) => c.planets
    .where((p) => p.id != c.currentPlanetId)
    .reduce((a, b) => c.distanceTo(a) > c.distanceTo(b) ? a : b);

/// The nearest reachable target — cheap enough to fly on a full tank.
Planet _nearest(GameController c) => c.planets
    .where((p) => p.id != c.currentPlanetId)
    .reduce((a, b) => c.distanceTo(a) <= c.distanceTo(b) ? a : b);

/// Docks at the nearest planet, leaves a single drop in the tank, and launches
/// a voyage it cannot afford under [policy]. Returns the controller and target.
///
/// Docking is not decoration: the coast test reads the origin planet's
/// position, and a voyage launched from open space carries `kDeepSpaceId` as
/// its origin, for which `planetById` returns `null`.
Future<(GameController, Planet)> _doomed(
  FakeClock clock,
  FuelPolicy policy,
) async {
  final storage = MemoryStorage();
  final c = await _boot(clock, storage: storage);
  final near = _nearest(c);
  expect(await c.launchJourney(near), LaunchResult.success,
      reason: 'precondition: the nearest planet is affordable from a full tank');
  clock.advance(const Duration(hours: 12));
  c.tick();
  await c.acknowledgeArrival();
  expect(c.currentPlanetId, near.id, reason: 'precondition: docked');

  // One drop of fuel: `cost >= minEnergyCost == 1`, so this is the one balance
  // guaranteed to be strictly below the quote for any destination.
  await _setEnergy(storage, 1);
  final docked = await _boot(clock, storage: storage);
  expect(docked.currentPlanetId, near.id, reason: 'precondition: still docked');

  final far = _farthest(docked);
  expect(docked.energyCostTo(far), greaterThan(docked.energy),
      reason: 'precondition: this hop is out of reach');
  expect(await docked.launchJourney(far, onEmpty: policy),
      LaunchResult.success);
  return (docked, far);
}

void main() {
  group('FuelPolicy on a voyage', () {
    test('round-trips through JSON and defaults to halt', () {
      final j = Journey(
        id: 'j1',
        originPlanetId: 'a',
        destinationPlanetId: 'b',
        departure: DateTime(2026),
        arrival: DateTime(2026, 1, 2),
        energyCost: 100,
        status: JourneyStatus.inProgress,
      );
      expect(j.fuelPolicy, FuelPolicy.halt, reason: 'the safe default');
      expect(j.copyWith(status: JourneyStatus.arrived).fuelPolicy,
          FuelPolicy.halt, reason: 'copyWith must not drop the policy');

      final coast = Journey(
        id: 'j2',
        originPlanetId: 'a',
        destinationPlanetId: 'b',
        departure: DateTime(2026),
        arrival: DateTime(2026, 1, 2),
        energyCost: 100,
        status: JourneyStatus.inProgress,
        fuelPolicy: FuelPolicy.coast,
      );
      expect(Journey.fromJson(coast.toJson()).fuelPolicy, FuelPolicy.coast);
    });

    test('an old save with no fuelPolicy key loads as halt', () {
      final json = Journey(
        id: 'j1',
        originPlanetId: 'a',
        destinationPlanetId: 'b',
        departure: DateTime(2026),
        arrival: DateTime(2026, 1, 2),
        energyCost: 100,
        status: JourneyStatus.inProgress,
      ).toJson()
        ..remove('fuelPolicy');
      expect(Journey.fromJson(json).fuelPolicy, FuelPolicy.halt);
    });
  });

  group('the launch gate follows the policy', () {
    test('refuse is the default and rejects what it cannot afford', () async {
      final clock = FakeClock(DateTime(2026));
      // A single drop of fuel: `cost >= minEnergyCost == 1`, so this is the one
      // balance guaranteed to be strictly below the quote for any destination.
      final c = await _bootWithEnergy(clock, 1);
      final far = _farthest(c);
      expect(c.energyCostTo(far), greaterThan(c.energy),
          reason: 'precondition: this hop is out of reach');

      expect(await c.launchJourney(far), LaunchResult.insufficientEnergy);
      expect(c.activeJourney, isNull);
      expect(c.energy, 1, reason: 'nothing was deducted');
    });

    test('halt and coast only need a drop of fuel', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _bootWithEnergy(clock, 1);
      final far = _farthest(c);
      expect(c.energyCostTo(far), greaterThan(c.energy));

      expect(await c.launchJourney(far, onEmpty: FuelPolicy.halt),
          LaunchResult.success);
      expect(c.activeJourney!.fuelPolicy, FuelPolicy.halt);
    });

    test('an empty tank moves nothing under any policy', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _bootWithEnergy(clock, 0);
      expect(c.energy, 0, reason: 'precondition: the tank is dry');

      final far = _farthest(c);
      expect(await c.launchJourney(far, onEmpty: FuelPolicy.halt),
          LaunchResult.insufficientEnergy);
      expect(await c.launchJourney(far, onEmpty: FuelPolicy.coast),
          LaunchResult.insufficientEnergy);
      expect(await c.launchJourney(far, onEmpty: FuelPolicy.refuse),
          LaunchResult.insufficientEnergy);
    });
  });

  group('the exhaust point is closed-form', () {
    test('progress, time and position all follow from the balance', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _bootWithEnergy(clock, 1);
      final far = _farthest(c);
      final cost = c.energyCostTo(far);
      final balance = c.energy;
      final origin = c.playerPosition3D;
      final departure = clock();

      expect(await c.launchJourney(far, onEmpty: FuelPolicy.halt),
          LaunchResult.success);
      final journey = c.activeJourney!;

      final p = balance / cost;
      expect(c.fuelExhaustProgress, closeTo(p, 1e-12));
      expect(c.fuelExhaustTime(journey),
          departure.add(Duration(
              milliseconds:
                  (journey.totalDuration.inMilliseconds * p).round())));

      // pos_exhaust = origin + (dest - origin) * p
      final expected = origin + (far.pos - origin) * p;
      final actual = origin +
          (far.pos - origin) *
              journey.progressAt(c.fuelExhaustTime(journey));
      // `fuelExhaustTime` rounds to whole milliseconds, so the exhaust point can
      // sit up to half a millisecond of travel away from the exact fraction.
      // That is the whole of the slack, and it scales with the length of the leg.
      final slack =
          c.distanceTo(far) * (0.5 / journey.totalDuration.inMilliseconds) + 1e-9;
      expect((actual - expected).length, lessThan(slack));
    });

    test('a top-up mid-flight pushes the exhaust point past arrival', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _bootWithEnergy(clock, 1);
      final far = _farthest(c);
      final cost = c.energyCostTo(far);
      expect(cost, greaterThan(c.energy));
      await c.launchJourney(far, onEmpty: FuelPolicy.halt);
      expect(c.fuelExhaustProgress, lessThan(1));

      // Enough training to cover the rest of the quote. Priced off the quote
      // rather than a fixed number: the nearby search reaches 960 ly, so a long
      // leg's quote can run into the thousands.
      final session = await c.startCourse('walk');
      await c.completeCourse(session.id, cost);

      expect(c.fuelExhaustProgress, 1.0,
          reason: 'the tank now covers the whole trip');
      expect(c.fuelExhaustTime(c.activeJourney!),
          c.activeJourney!.arrival,
          reason: 'nothing to run out of before the destination');
    });
  });

  group('halt', () {
    test('stops at the exhaust point with an empty tank', () async {
      final clock = FakeClock(DateTime(2026));
      final (c, far) = await _doomed(clock, FuelPolicy.halt);
      final journey = c.activeJourney!;
      final origin = c.planetById(journey.originPlanetId)!.pos;
      final p = c.fuelExhaustProgress!;
      final balance = c.energy;
      final entriesBefore = c.energyLedger.length;

      // One second past the moment the tank runs dry.
      clock.advance(c.fuelExhaustTime(journey).difference(clock()) +
          const Duration(seconds: 1));
      c.tick();

      expect(c.activeJourney, isNull, reason: 'the voyage is over');
      expect(c.inDeepSpace, isTrue);
      expect(c.energy, 0, reason: 'the whole tank is gone');
      expect(c.driftVelocity.length, 0, reason: 'halt parks the ship');
      expect(c.energyLedger.length, entriesBefore + 1);
      expect(c.energyLedger.first.amount, -balance);

      // The exhaust point is `origin + (dest - origin) * p`; `fuelExhaustTime`
      // rounds to whole milliseconds, so the real point can sit up to half a
      // millisecond of travel away — 0.5 / (37.5 * 1000) ly for the standard
      // engine, since the leg length cancels out of `dist * 0.5 / totalMs`.
      final expected = origin + (far.pos - origin) * p;
      expect((c.playerPosition3D - expected).length, lessThan(0.001));
    });

    test('the ship does not creep forward afterwards', () async {
      final clock = FakeClock(DateTime(2026));
      final (c, _) = await _doomed(clock, FuelPolicy.halt);
      clock.advance(c.fuelExhaustTime(c.activeJourney!).difference(clock()) +
          const Duration(seconds: 1));
      c.tick();
      final parked = c.playerPosition3D;
      clock.advance(const Duration(days: 30));
      expect(c.playerPosition3D.x, parked.x);
      expect(c.playerPosition3D.y, parked.y);
      expect(c.playerPosition3D.z, parked.z);
    });
  });

  group('coast', () {
    test('keeps moving at cruise speed and burns nothing more', () async {
      final clock = FakeClock(DateTime(2026));
      final (c, _) = await _doomed(clock, FuelPolicy.coast);
      final journey = c.activeJourney!;

      clock.advance(c.fuelExhaustTime(journey).difference(clock()) +
          const Duration(seconds: 1));
      c.tick();

      expect(c.activeJourney, isNull);
      expect(c.inDeepSpace, isTrue);
      expect(c.energy, 0);
      final v = c.driftVelocity;
      expect(v.length, greaterThan(0));
      // The engine's own cruise speed, not `distance / duration`. The duration
      // is rounded to whole seconds, so a speed recovered from it would differ
      // per route — and the braking quote, a ratio of that speed, with it. The
      // tolerance covers the round trip through `Vec3.length` (a few ulps);
      // the derivation it replaces is off by ~1e-7, so this still has teeth.
      expect(v.length, closeTo(c.ship.engine.cruiseSpeedLyPerSec, 1e-12));

      final entries = c.energyLedger.length;
      final atStart = c.playerPosition3D;
      clock.advance(const Duration(seconds: 100));
      final later = c.playerPosition3D;
      expect((later - atStart).length, closeTo(v.length * 100, 0.01),
          reason: 'constant speed, no acceleration');

      clock.advance(const Duration(days: 3));
      c.tick();
      expect(c.energyLedger.length, entries,
          reason: 'coasting costs nothing to run');
    });

    test('a coasting ship ends up on the shell, never in a void', () async {
      final clock = FakeClock(DateTime(2026));
      final (c, _) = await _doomed(clock, FuelPolicy.coast);
      clock.advance(c.fuelExhaustTime(c.activeJourney!).difference(clock()) +
          const Duration(seconds: 1));
      c.tick();

      // Fly the drift out to (and well past) the boundary. The ship exhausts
      // near the origin planet, well inside the shell, and cruise speed is
      // 1/37.5 ly/s — 60 days covers 138,240 ly, so it is pinned to the shell
      // long before this.
      clock.advance(const Duration(days: 60));
      final r = c.playerPosition3D.length;
      // Mirrors `playerPosition3D`'s own bound: never tighter than the ship's
      // own radius, so a ship that started outside the shell keeps its distance.
      final bound = math.max(c.universe.universeRadius, r);
      expect(r, closeTo(bound, 1.0));
      expect(c.planets, isNotEmpty,
          reason: 'wherever it ends up, there is somewhere to go');
    });
  });

  group('refuse', () {
    test('an affordable voyage is untouched by any of this', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      // `planetsNear` sorts nearest-first, so this is the nearest planet and
      // its quote is well inside `Balance.initialEnergy`.
      final target = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
      await c.launchJourney(target);
      final journey = c.activeJourney!;
      expect(journey.fuelPolicy, FuelPolicy.refuse);
      expect(c.fuelExhaustProgress, 1.0);

      clock.advance(journey.totalDuration + const Duration(seconds: 1));
      c.tick();
      expect(c.currentPlanetId, target.id, reason: 'it simply arrives');
      expect(c.driftVelocity.length, 0);
    });
  });

  group('reachableLyFor', () {
    test('is the plain inverse of energyPerLy', () {
      expect(Engine.standard.reachableLyFor(100), 40.0);
      expect(Engine.standard.reachableLyFor(300), 120.0);
      expect(Engine.standard.reachableLyFor(0), 0.0);
    });
  });

  group('the fuel choice dialog', () {
    /// Pumps a button that opens the dialog, taps it, and settles. Returns the
    /// future the dialog's result arrives on — already pending, because the
    /// sheet is open by the time this returns.
    Future<Future<FuelPolicy?>> open(
      WidgetTester tester, {
      required int energy,
      required int cost,
    }) async {
      final picked = Completer<FuelPolicy?>();
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                picked.complete(await showFuelChoiceDialog(
                  context,
                  energy: energy,
                  cost: cost,
                  braking: 0,
                  distanceLy: 100.0,
                  engine: Engine.standard,
                ));
              },
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      return picked.future;
    }

    testWidgets('spells out what the tank can and cannot reach',
        (tester) async {
      await open(tester, energy: 100, cost: 250);
      expect(find.textContaining('100 EN'), findsOneWidget);
      expect(find.textContaining('40.0 ly'), findsOneWidget);
      expect(find.textContaining('100.0 ly'), findsOneWidget);
      expect(find.text('放弃航行'), findsOneWidget);
      expect(find.text('耗尽后停下'), findsOneWidget);
      expect(find.text('耗尽后滑行'), findsOneWidget);
    });

    testWidgets('returns the policy the player tapped', (tester) async {
      final future = await open(tester, energy: 100, cost: 250);
      await tester.tap(find.text('耗尽后滑行'));
      await tester.pumpAndSettle();
      expect(await future, FuelPolicy.coast);
    });

    testWidgets('an empty tank is only offered a way out', (tester) async {
      final future = await open(tester, energy: 0, cost: 250);
      expect(find.text('耗尽后停下'), findsNothing,
          reason: 'no fuel means no voyage to run out of');
      expect(find.text('耗尽后滑行'), findsNothing);
      expect(find.text('放弃航行'), findsOneWidget);
      await tester.tap(find.text('放弃航行'));
      await tester.pumpAndSettle();
      expect(await future, isNull);
    });
  });
}
