import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/models/discovery_record.dart';
import 'package:starward/data/models/energy_transaction.dart';
import 'package:starward/data/models/engine.dart';
import 'package:starward/data/models/planet.dart';
import 'package:starward/data/models/player_state.dart';
import 'package:starward/data/models/ship.dart';
import 'package:starward/data/models/training_session.dart';
import 'package:starward/data/storage/storage_backend.dart';
import 'package:starward/state/game_controller.dart';

/// A refit that trades speed for efficiency: cheaper per light-year, slower.
const Engine _thrifty = Engine(
  id: 'engine.thrifty',
  name: '节能引擎',
  energyPerLy: 1.5,
  cruiseSpeedLyPerSec: 1 / 50,
  brakingDistanceLy: 40,
  minEnergyCost: 1,
  minTravelSeconds: 15,
  activationCost: 5,
);

class FakeClock {
  FakeClock(this._now);
  DateTime _now;
  DateTime call() => _now;
  void advance(Duration d) => _now = _now.add(d);
}

Future<GameController> _boot(FakeClock clock, {StorageBackend? storage}) async {
  final c = GameController(
    repository: GameRepository(storage ?? MemoryStorage()),
    clock: clock.call,
    random: math.Random(2),
  );
  await c.init();
  return c;
}

/// The closest planet we could launch to — the cheapest hop on offer.
Planet _nearest(GameController c) => c.planets
    .where((p) => p.id != c.currentPlanetId)
    .reduce((a, b) => c.distanceTo(a) <= c.distanceTo(b) ? a : b);

GameSave _saveWith(Ship ship) => GameSave(
      player: PlayerState.deepSpaceStart(
        energy: 300,
        startCoordX: 0,
        startCoordY: 0,
        startX: 1,
        startY: 2,
        startZ: 3,
        createdAt: DateTime(2026),
      ),
      ship: ship,
      activeJourney: null,
      discoveries: const <DiscoveryRecord>[],
      energyLedger: const <EnergyTransaction>[],
      trainingSessions: const <TrainingSession>[],
      planetStates: const <String, String>{},
      pendingDriftReport: null,
    );

void main() {
  group('Engine', () {
    test('the standard engine reproduces the historical global constants', () {
      const e = Engine.standard;
      // These were `max(1, (ly * 2.5).round())` and
      // `max(15, (ly * 37.5).round())` when they lived in Balance. Pinned so
      // the migration is provably behaviour-preserving.
      expect(e.energyCostFor(10), 25);
      expect(e.secondsFor(10), 375);
      expect(e.energyCostFor(2), 5);
      expect(e.secondsFor(2), 75);
    });

    test('floors keep a zero-distance hop from being free or instant', () {
      expect(Engine.standard.energyCostFor(0), Engine.standard.minEnergyCost);
      expect(Engine.standard.secondsFor(0), Engine.standard.minTravelSeconds);
    });

    test('a refit trades energy against speed', () {
      // Same 10 ly, different engine: cheaper but slower.
      expect(_thrifty.energyCostFor(10), 15);
      expect(_thrifty.secondsFor(10), 500);
      expect(_thrifty.energyCostFor(10),
          lessThan(Engine.standard.energyCostFor(10)));
      expect(_thrifty.secondsFor(10), greaterThan(Engine.standard.secondsFor(10)));
    });

    test('an engine saved before speed became a field migrates to a speed', () {
      final json = Engine.standard.toJson()
        ..remove('cruiseSpeedLyPerSec')
        ..['travelSecondsPerLy'] = 50.0;
      expect(json.containsKey('cruiseSpeedLyPerSec'), isFalse,
          reason: 'precondition: this is what an old save looks like');

      final back = Engine.fromJson(json);
      // The old key was a pace; the field is a speed. Inverting it recovers
      // the engine exactly, so an old save flies as it always did.
      expect(back.cruiseSpeedLyPerSec, 1 / 50);
      expect(back.secondsFor(10), 500, reason: 'the old pace, recovered exactly');
    });
  });

  group('Ship', () {
    test('withEngine refits the engine and leaves the hull alone', () {
      final refit = Ship.standard.withEngine(_thrifty);
      expect(refit.id, Ship.standard.id);
      expect(refit.name, Ship.standard.name);
      expect(refit.engine.id, 'engine.thrifty');
      // The original is untouched — a refit is a new value, not a mutation.
      expect(Ship.standard.engine.id, Engine.standard.id);
    });
  });

  group('save', () {
    test('the ship survives a save/load round trip', () {
      final restored =
          GameSave.fromJson(_saveWith(Ship.standard.withEngine(_thrifty)).toJson());
      expect(restored.ship.id, Ship.standard.id);
      expect(restored.ship.engine.id, 'engine.thrifty');
      expect(restored.ship.engine.name, '节能引擎');
      expect(restored.ship.engine.energyPerLy, 1.5);
      expect(restored.ship.engine.minTravelSeconds, 15);
    });

    test('a save written before ships existed migrates to the standard ship',
        () {
      final json = _saveWith(Ship.standard).toJson()..remove('ship');
      final restored = GameSave.fromJson(json);
      expect(restored.ship.id, Ship.standard.id);
      expect(restored.ship.engine.energyPerLy, Engine.standard.energyPerLy);
      expect(restored.ship.engine.cruiseSpeedLyPerSec,
          Engine.standard.cruiseSpeedLyPerSec);
    });
  });

  group('controller charges through the ship', () {
    test('launch cost comes from the fitted engine, not a global constant',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final target = _nearest(c);
      expect(c.energyCostTo(target),
          c.ship.engine.energyCostFor(c.distanceTo(target)));
      expect(c.travelDurationTo(target).inSeconds,
          c.ship.engine.secondsFor(c.distanceTo(target)));
    });

    test('refitting changes cost and duration for the same hop', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final target = _nearest(c);
      final costBefore = c.energyCostTo(target);
      final timeBefore = c.travelDurationTo(target);

      await c.installEngine(_thrifty);

      expect(c.energyCostTo(target), lessThan(costBefore));
      expect(c.travelDurationTo(target), greaterThan(timeBefore));
    });

    test('the voyage bills the refitted cost, settled on arrival', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await c.installEngine(_thrifty);
      final target = _nearest(c);
      final before = c.energy;
      final cost = c.energyCostTo(target);
      final total = c.travelDurationTo(target);

      await c.launchJourney(target);
      expect(c.energy, before, reason: 'nothing burns at t=0');

      clock.advance(total + const Duration(seconds: 1));
      c.tick();
      expect(c.energy, before - cost);
      expect(c.energyLedger.first.amount, -cost);
    });

    test('a refit survives a reload', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _boot(clock, storage: storage);
      await c.installEngine(_thrifty);

      final reloaded = await _boot(clock, storage: storage);
      expect(reloaded.ship.engine.id, 'engine.thrifty');
      expect(reloaded.ship.engine.energyPerLy, 1.5);
    });
  });
}
