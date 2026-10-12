import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/models/journey.dart';
import 'package:starward/data/models/planet.dart';
import 'package:starward/data/storage/storage_backend.dart';
import 'package:starward/state/game_controller.dart';

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
}
