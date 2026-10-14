import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/vec3.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/models/energy_transaction.dart';
import 'package:starward/data/models/journey.dart';
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

Future<void> _editPlayer(
  MemoryStorage storage,
  void Function(Map<String, dynamic> player) edit,
) async {
  final raw = await storage.read('starward.save.v2');
  final json = jsonDecode(raw!) as Map<String, dynamic>;
  edit(json['player'] as Map<String, dynamic>);
  await storage.write('starward.save.v2', jsonEncode(json));
}

Future<void> _setEnergy(MemoryStorage storage, int balance) =>
    _editPlayer(storage, (p) => p['energyBalance'] = balance);

Future<void> _setDormant(MemoryStorage storage) =>
    _editPlayer(storage, (p) => p['engineDormant'] = true);

/// Docks at the nearest planet, leaves a single drop in the tank, and launches
/// a voyage it cannot afford, so the ship runs dry en route.
Future<GameController> _doomed(FakeClock clock, FuelPolicy policy) async {
  final storage = MemoryStorage();
  final c = await _boot(clock, storage: storage);
  final near = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
  expect(await c.launchJourney(near), LaunchResult.success,
      reason: 'precondition: the nearest planet is affordable from a full tank');
  clock.advance(const Duration(hours: 12));
  c.tick();
  await c.acknowledgeArrival();
  await _setEnergy(storage, 1);
  final docked = await _boot(clock, storage: storage);
  final far = docked.planets
      .where((p) => p.id != docked.currentPlanetId)
      .reduce((a, b) => docked.distanceTo(a) > docked.distanceTo(b) ? a : b);
  expect(await docked.launchJourney(far, onEmpty: policy), LaunchResult.success);
  return docked;
}

/// Ignites a cruise on a full tank and runs it to exhaustion: dormant, coasting,
/// with the 100 EN braking reserve still in the tank.
Future<GameController> _exhaustedCruise(FakeClock clock) async {
  final c = await _boot(clock);
  await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.coast);
  clock.advance(const Duration(seconds: 3000));
  c.tick();
  expect(c.isDormant, isTrue, reason: 'precondition: the engine shut down');
  expect(c.isCoasting, isTrue, reason: 'precondition: still drifting');
  return c;
}

void main() {
  group('dormancy', () {
    test('a fresh ship is awake', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      expect(c.isDormant, isFalse);
    });

    test('a cruise that runs dry shuts the engine down', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _exhaustedCruise(clock);
      expect(c.energy, 100, reason: 'the reserve survives the shutdown');
      expect(c.isCoasting, isTrue, reason: 'the ship keeps drifting');
    });

    test('a voyage that runs dry shuts the engine down', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _doomed(clock, FuelPolicy.coast);
      expect(c.isDormant, isFalse, reason: 'precondition: still under way');
      clock.advance(c.fuelExhaustTime(c.activeJourney!).difference(clock()) +
          const Duration(seconds: 1));
      c.tick();
      expect(c.energy, 0);
      expect(c.isDormant, isTrue);
      expect(c.isCoasting, isTrue);
    });

    test('a voyage resolving against an already-empty tank still shuts down',
        () async {
      // The input is hand-built: `_setEnergy(storage, 0)` edits a dry
      // tank into the save while a voyage is under way, so that the reload's
      // `_settleTank` sees `drained == 0` and takes the branch that only syncs
      // dormancy. Resolution is left to `init()` rather than a `tick()` because
      // reopening the save is what the `init()` constraint protects. The
      // `_doomed` test above cannot reach `drained == 0`: its tank still holds
      // the 1 EN it launched with.
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _boot(clock, storage: storage);
      final near = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
      expect(await c.launchJourney(near), LaunchResult.success);
      clock.advance(const Duration(hours: 12));
      c.tick();
      await c.acknowledgeArrival();
      final docked = await _boot(clock, storage: storage);
      final far = docked.planets
          .where((p) => p.id != docked.currentPlanetId)
          .reduce((a, b) => docked.distanceTo(a) > docked.distanceTo(b) ? a : b);
      expect(await docked.launchJourney(far, onEmpty: FuelPolicy.coast),
          LaunchResult.success);
      await _setEnergy(storage, 0);
      // Precondition, read straight off the hand-edited save: the voyage is
      // still under way and the tank is empty, so the reload's `_settleTank`
      // sees `drained == 0` and takes the branch that only syncs dormancy.
      final saved = jsonDecode((await storage.read('starward.save.v2'))!);
      final raw = saved as Map<String, dynamic>;
      expect((raw['player'] as Map<String, dynamic>)['energyBalance'], 0);
      expect(raw['activeJourney'], isNotNull);

      final resumed = await _boot(clock, storage: storage);
      expect(resumed.activeJourney, isNull, reason: 'the voyage resolved');
      expect(resumed.energy, 0);
      expect(resumed.isDormant, isTrue);
    });

    test('loading a dry save does not invent a dormancy', () async {
      // `init()` deliberately does not sync dormancy. A save written before
      // dormancy existed, with an empty tank, has to keep behaving as it did:
      // the gate refuses on energy, not on a shutdown the player never saw.
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      await _boot(clock, storage: storage);
      await _setEnergy(storage, 0);
      final c = await _boot(clock, storage: storage);
      expect(c.energy, 0);
      expect(c.isDormant, isFalse);
      final far = c.planets
          .where((p) => p.id != c.currentPlanetId)
          .reduce((a, b) => c.distanceTo(a) > c.distanceTo(b) ? a : b);
      expect(await c.launchJourney(far, onEmpty: FuelPolicy.halt),
          LaunchResult.insufficientEnergy);
    });

    test('a dormant ship can still brake — dormancy is not paralysis',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _exhaustedCruise(clock);
      expect(c.canBrake, isTrue);
      await c.stopShip();
      expect(c.hasMomentum, isFalse);
      expect(c.energy, 0, reason: 'the reserve bought the stop');
      expect(c.isDormant, isTrue, reason: 'braking does not restart the engine');
    });
  });

  group('activate', () {
    test('pays the flat fee and brings the engine back online', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _exhaustedCruise(clock);
      expect(c.energy, 100);

      expect(await c.activate(), isTrue);
      expect(c.energy, 95);
      expect(c.isDormant, isFalse);
      expect(c.energyLedger.first.type, EnergyTxType.activation);
      expect(c.energyLedger.first.amount, -5);
    });

    test('is a no-op when the engine is already running', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      expect(await c.activate(), isFalse);
      expect(c.energy, 300);
      expect(c.energyLedger, isEmpty);
    });

    test('refuses when the tank cannot cover the fee', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      await _boot(clock, storage: storage);
      await _setEnergy(storage, 3);
      await _setDormant(storage);
      final c = await _boot(clock, storage: storage);
      expect(c.isDormant, isTrue, reason: 'precondition: shut down');
      expect(await c.activate(), isFalse);
      expect(c.energy, 3, reason: 'a refused activation spends nothing');
      expect(c.energyLedger, isEmpty);
    });

    test('training refills the tank but does not restart the engine', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _exhaustedCruise(clock);
      final session = await c.startCourse('walk');
      await c.completeCourse(session.id, 40);
      expect(c.energy, 140);
      expect(c.isDormant, isTrue, reason: 'only activate() clears it');
      // That a dormant engine then *refuses* to ignite is Task 10's assertion,
      // not this one's: it needs `LaunchResult.engineDormant`, which Task 10
      // introduces. Asserting it here would make this file fail to compile and
      // this task's own Step 6 unsatisfiable.
    });

    test('a wake-up survives a reload', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _boot(clock, storage: storage);
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      clock.advance(const Duration(seconds: 3000));
      c.tick();
      await c.activate();
      final reloaded = await _boot(clock, storage: storage);
      expect(reloaded.isDormant, isFalse);
      expect(reloaded.energy, 95);
    });
  });

  group('a dormant engine cannot burn', () {
    test('a voyage is refused with its own result, not "not enough energy"',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _exhaustedCruise(clock);
      // The tank has to clear the launch gate on its own, or the refusal would
      // not be attributable to dormancy: a coasting ship's `brakingCost` is the
      // 100 EN brake, so 100 EN sits exactly on the gate's `available <= braking`
      // boundary and would be refused on energy. Training 40 EN lifts the tank to
      // 140, strictly past it.
      expect(c.isDormant, isTrue, reason: 'precondition: the engine is down');
      expect(c.isCoasting, isTrue, reason: 'precondition: still drifting');
      final session = await c.startCourse('walk');
      await c.completeCourse(session.id, 40);
      expect(c.energy, 140, reason: 'precondition: the tank is refuelled');
      expect(c.energy, greaterThan(c.brakingCost));

      final near = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
      expect(await c.launchJourney(near, onEmpty: FuelPolicy.halt),
          LaunchResult.engineDormant,
          reason: 'the tank clears the gate, so only the engine can refuse');
      expect(c.activeJourney, isNull);
      expect(c.energy, 140, reason: 'a refusal spends nothing');
    });

    test('a star launch is refused the same way', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _exhaustedCruise(clock);
      expect(await c.launchToStar(c.stars.starId[0], onEmpty: FuelPolicy.halt),
          LaunchResult.engineDormant);
    });

    test('ignition is refused too', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _exhaustedCruise(clock);
      // Phase 1: still coasting. `igniteCruise` checks dormancy *before*
      // `hasMomentum`, so a moving dormant ship is answered `engineDormant`; if
      // the two guards were swapped, `hasMomentum` would answer
      // `alreadyTraveling` instead, which is what pins the order.
      expect(c.hasMomentum, isTrue, reason: 'precondition: still drifting');
      expect(c.isDormant, isTrue, reason: 'precondition: the engine is down');
      expect(
        await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt),
        LaunchResult.engineDormant,
      );

      // Phase 2: parked, and the brake has spent the whole 100 EN reserve, so
      // the tank is empty. The dormancy guard sits *before* the energy gate, so
      // the answer is still `engineDormant` — the energy gate would have said
      // `insufficientEnergy`.
      await c.stopShip();
      expect(c.hasMomentum, isFalse);
      expect(c.energy, 0, reason: 'the reserve bought the stop');
      expect(
        await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt),
        LaunchResult.engineDormant,
      );
    });

    test('activation clears the block', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _exhaustedCruise(clock);
      await c.stopShip();
      // Braking spends the *entire* reserve — `cruiseReserve` is defined as
      // `brakingCostFor(cruiseSpeed)`, which is the same 100 EN the brake
      // quotes — so the tank is empty at this point and `activate()` cannot
      // afford its own 5 EN fee. Training is the cheapest way back to a tank
      // that can, and it doubles as proof that refuelling does not wake the
      // engine on its own.
      expect(c.energy, 0, reason: 'the reserve bought the stop');
      final session = await c.startCourse('walk');
      await c.completeCourse(session.id, 40);
      expect(c.energy, 40);
      expect(c.isDormant, isTrue, reason: 'training does not restart it');
      expect(await c.activate(), isTrue);
      expect(c.energy, 35);
      // Awake is not the same as ready to fly. 35 EN is less than the 100 EN
      // reserve, so a cruise would have no seconds of burn to buy — and would
      // exhaust on its first tick, handing the player a fuel-out report for a
      // leg of 0 ly. The refusal is about energy, not about dormancy, which the
      // activation above already cleared.
      expect(
        await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt),
        LaunchResult.insufficientEnergy,
      );
      // One more course clears the reserve, and the block really is gone.
      final second = await c.startCourse('walk');
      await c.completeCourse(second.id, 80);
      expect(c.energy, 115);
      expect(
        await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt),
        LaunchResult.success,
      );
    });

    test('the launch gate is checked after dormancy, so the message is right',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _exhaustedCruise(clock);
      // Both conditions hold — dormant *and* unable to afford a long hop. The
      // player needs to be told the one they can act on cheaply.
      final far = c.planets
          .where((p) => p.id != c.currentPlanetId)
          .reduce((a, b) => c.distanceTo(a) > c.distanceTo(b) ? a : b);
      expect(c.energyCostTo(far), greaterThan(c.energy));
      expect(await c.launchJourney(far, onEmpty: FuelPolicy.refuse),
          LaunchResult.engineDormant);
    });
  });
}
