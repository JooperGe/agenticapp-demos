import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/vec3.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/models/energy_transaction.dart';
import 'package:starward/data/models/engine.dart';
import 'package:starward/data/models/journey.dart';
import 'package:starward/data/storage/storage_backend.dart';
import 'package:starward/state/game_controller.dart';

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

/// Rewrites the saved balance so the ship starts with exactly [balance] EN.
Future<void> _setEnergy(MemoryStorage storage, int balance) async {
  final raw = await storage.read('starward.save.v2');
  final json = jsonDecode(raw!) as Map<String, dynamic>;
  (json['player'] as Map<String, dynamic>)['energyBalance'] = balance;
  await storage.write('starward.save.v2', jsonEncode(json));
}

/// Rewrites the saved drift so the ship is coasting from its anchor.
Future<void> _setDrift(
  MemoryStorage storage,
  Vec3 velocity,
  DateTime startedAt,
) async {
  final raw = await storage.read('starward.save.v2');
  final json = jsonDecode(raw!) as Map<String, dynamic>;
  final player = json['player'] as Map<String, dynamic>;
  player['driftVelocityX'] = velocity.x;
  player['driftVelocityY'] = velocity.y;
  player['driftVelocityZ'] = velocity.z;
  player['driftStartedAt'] = startedAt.millisecondsSinceEpoch;
  await storage.write('starward.save.v2', jsonEncode(json));
}

/// A controller whose ship is coasting at the standard engine's own cruise
/// speed — so the braking quote is exactly the reference 100 EN — carrying
/// [energy] EN.
Future<GameController> _coasting(
  FakeClock clock,
  MemoryStorage storage, {
  int energy = 300,
}) async {
  await _boot(clock, storage);
  await _setEnergy(storage, energy);
  await _setDrift(
    storage,
    const Vec3(1 / 37.5, 0, 0),
    clock(),
  );
  final c = await _boot(clock, storage);
  expect(c.isCoasting, isTrue, reason: 'precondition: the ship is drifting');
  return c;
}

void main() {
  group('Engine braking', () {
    test('a full cruise burn costs what flying the braking distance costs', () {
      const e = Engine.standard;
      expect(e.travelSecondsPerLy, 37.5, reason: 'the pinned reference engine');
      expect(e.cruiseSpeedLyPerSec, closeTo(0.0266667, 1e-7));
      expect(e.brakingDistanceLy, 40);
      expect(e.energyCostFor(40), 100, reason: 'the quote this all rests on');
      expect(e.brakingCostFor(e.cruiseSpeedLyPerSec), 100);
    });

    test('half a cruise speed costs half as much', () {
      const e = Engine.standard;
      expect(e.brakingCostFor(e.cruiseSpeedLyPerSec / 2), 50);
    });

    test('a ship at rest is quoted nothing, not the minEnergyCost floor', () {
      const e = Engine.standard;
      expect(e.minEnergyCost, 1,
          reason: 'the floor this guard exists to dodge');
      expect(e.brakingCostFor(0), 0);
      expect(e.brakingCostFor(-0.5), 0);
    });

    test('braking distance survives a JSON round trip', () {
      final back = Engine.fromJson(Engine.standard.toJson());
      expect(back.brakingDistanceLy, 40);
      expect(back.brakingCostFor(back.cruiseSpeedLyPerSec), 100);
    });

    test('an engine saved before braking existed falls back to the standard',
        () {
      final json = Engine.standard.toJson()..remove('brakingDistanceLy');
      expect(json.containsKey('brakingDistanceLy'), isFalse,
          reason: 'precondition: this is what an old save looks like');

      final back = Engine.fromJson(json);
      expect(back.brakingDistanceLy, Engine.standard.brakingDistanceLy);
      expect(back.brakingCostFor(back.cruiseSpeedLyPerSec), 100);
    });
  });

  group('GameController.brakingCost', () {
    test('is zero for a ship that is not coasting', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock, MemoryStorage());
      expect(c.brakingCost, 0);
    });

    test('is the engine quote while coasting', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _coasting(clock, MemoryStorage());
      expect(c.brakingCost, 100);
    });
  });

  group('the braking burn', () {
    test('a launch from a drift books it once, on top of the voyage fuel',
        () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _coasting(clock, storage, energy: 100000);
      final target = c.planets.first;
      final voyageFuel = c.ship.engine.energyCostFor(c.distanceTo(target));
      expect(voyageFuel, greaterThan(0), reason: 'precondition');

      expect(await c.launchJourney(target), LaunchResult.success);

      final braking =
          c.energyLedger.where((t) => t.type == EnergyTxType.braking).toList();
      expect(braking.length, 1);
      expect(braking.single.amount, -100);
      expect(c.isCoasting, isFalse);
      // Only the braking burn has been deducted: voyage fuel accrues with
      // progress, and at t=0 no progress has been made.
      expect(c.energy, 100000 - 100);
    });

    test('keeps the braking burn out of the voyage quote', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _coasting(clock, storage, energy: 100000);
      final target = c.planets.first;
      final voyageFuel = c.ship.engine.energyCostFor(c.distanceTo(target));

      await c.launchJourney(target);

      expect(c.activeJourney!.energyCost, voyageFuel,
          reason: 'burnedAt = round(energyCost * progress); folding 100 EN of '
              'braking in here would spread it over the whole route and move '
              'the fuel-out point');
    });

    test('a parked ship books nothing when it launches', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock, MemoryStorage());
      expect(c.brakingCost, 0, reason: 'precondition');

      await c.launchJourney(c.planets.first);

      expect(
        c.energyLedger.where((t) => t.type == EnergyTxType.braking),
        isEmpty,
        reason: 'the braking > 0 guard keeps a zero-amount entry out of the '
            'ledger',
      );
    });
  });

  group('the launch gate with a drift to shed', () {
    test('a balance below the braking cost cannot leave at all', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _coasting(clock, MemoryStorage(), energy: 50);
      expect(c.brakingCost, 100, reason: 'precondition');

      expect(await c.launchJourney(c.planets.first),
          LaunchResult.insufficientEnergy);

      expect(c.energy, 50, reason: 'nothing was charged');
      expect(c.isCoasting, isTrue, reason: 'the ship is still drifting');
      expect(c.energyLedger, isEmpty);
    });

    test('exactly the braking cost is still not enough to leave', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _coasting(clock, MemoryStorage(), energy: 100);

      expect(await c.launchJourney(c.planets.first, onEmpty: FuelPolicy.halt),
          LaunchResult.insufficientEnergy);
      expect(c.isCoasting, isTrue);
    });

    test('one EN past the braking cost is enough to run dry en route',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _coasting(clock, MemoryStorage(), energy: 101);

      expect(await c.launchJourney(c.planets.first, onEmpty: FuelPolicy.halt),
          LaunchResult.success);
      expect(c.energy, 1,
          reason: 'the braking burn came off the top, leaving the drop the '
              'halt policy asks for');
    });

    test('an under-funded refuse launch still demands the whole quote',
        () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _coasting(clock, storage, energy: 300);
      final target = c.planets.first;
      final voyageFuel = c.ship.engine.energyCostFor(c.distanceTo(target));
      // One EN short of voyage fuel + braking.
      await _setEnergy(storage, voyageFuel + 100 - 1);
      final c2 = await _boot(clock, storage);

      expect(await c2.launchJourney(target), LaunchResult.insufficientEnergy);
      expect(c2.isCoasting, isTrue);
    });
  });
}
