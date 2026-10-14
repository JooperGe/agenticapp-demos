import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/vec3.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/models/drift_report.dart';
import 'package:starward/data/models/energy_transaction.dart';
import 'package:starward/data/models/engine.dart';
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

Future<GameController> _boot(FakeClock clock, {StorageBackend? storage}) async {
  final c = GameController(
    repository: GameRepository(storage ?? MemoryStorage()),
    clock: clock.call,
    random: math.Random(3),
  );
  await c.init();
  return c;
}

/// Writes a drift into the save, so a test can start from a ship already moving.
///
/// [powered] is written too: a hand-built save is the only way to reach a
/// cruising ship without going through `igniteCruise`, which is exactly what
/// makes it a useful fixture for the read-only tests below.
Future<void> _setDrift(
  MemoryStorage storage,
  Vec3 velocity,
  DateTime startedAt, {
  bool powered = false,
}) async {
  final raw = await storage.read('starward.save.v2');
  final json = jsonDecode(raw!) as Map<String, dynamic>;
  final player = json['player'] as Map<String, dynamic>;
  player['driftVelocityX'] = velocity.x;
  player['driftVelocityY'] = velocity.y;
  player['driftVelocityZ'] = velocity.z;
  player['driftStartedAt'] = startedAt.millisecondsSinceEpoch;
  player['driftPowered'] = powered;
  await storage.write('starward.save.v2', jsonEncode(json));
}

/// Rewrites the saved balance, so a test can start from a tank it chooses.
Future<void> _setEnergy(MemoryStorage storage, int balance) async {
  final raw = await storage.read('starward.save.v2');
  final json = jsonDecode(raw!) as Map<String, dynamic>;
  (json['player'] as Map<String, dynamic>)['energyBalance'] = balance;
  await storage.write('starward.save.v2', jsonEncode(json));
}

/// Marks a planet explored in the save, so a reload sees it through `stateOf`.
///
/// Written into `planetStates` — the map `stateOf` reads — rather than the
/// player's `exploredPlanetIds`. `completeExploration` keeps the two in step,
/// but only `planetStates` backs `stateOf`, so this is the lever that makes an
/// explored planet actually invisible to the recommendation rule.
Future<void> _setExplored(MemoryStorage storage, String planetId) async {
  final raw = await storage.read('starward.save.v2');
  final json = jsonDecode(raw!) as Map<String, dynamic>;
  (json['planetStates'] as Map<String, dynamic>)[planetId] = 'explored';
  await storage.write('starward.save.v2', jsonEncode(json));
}

/// The persisted `driftPowered` flag — the only way to observe it once the
/// velocity has been cleared, since `hasMomentum` is false either way then.
Future<bool> _savedPowered(MemoryStorage storage) async {
  final raw = await storage.read('starward.save.v2');
  final json = jsonDecode(raw!) as Map<String, dynamic>;
  return (json['player'] as Map<String, dynamic>)['driftPowered'] as bool;
}

/// Flies to the nearest planet and arrives, so the ship is docked.
Future<GameController> _docked(FakeClock clock, MemoryStorage storage) async {
  final c = await _boot(clock, storage: storage);
  final near = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
  expect(await c.launchJourney(near), LaunchResult.success,
      reason: 'precondition: the nearest planet is affordable from a full tank');
  clock.advance(const Duration(hours: 12));
  c.tick();
  await c.acknowledgeArrival();
  expect(c.currentPlanetId, near.id, reason: 'precondition: docked');
  return _boot(clock, storage: storage);
}

void main() {
  group('Engine cruise pricing', () {
    test('power draw is the engine\'s own speed times its own appetite', () {
      // Derived, never stored: a stored copy could drift out of step with the
      // two fields it comes from, and then a cruise and a voyage would disagree
      // about how fast the same tank drains.
      expect(Engine.standard.powerDrawPerSecond, closeTo(1 / 15, 1e-12));
    });

    test('a cruise and a voyage price the same distance identically', () {
      // The invariant the whole energy model hangs on: burning for exactly as
      // long as a leg takes must cost exactly the leg's quote. If this breaks,
      // "cruise to a place" and "fly to a place" become different prices.
      for (final d in <double>[1, 5, 40, 120, 200]) {
        final seconds = Engine.standard.secondsFor(d);
        expect(Engine.standard.burnForSeconds(seconds.toDouble()),
            Engine.standard.energyCostFor(d),
            reason: '$d ly');
      }
    });

    test('secondsForEnergy is 15 s per EN, with no floor of its own', () {
      // Exact, not approximate: the exhaustion check compares elapsed seconds
      // against this, and a rounding error here moves the halt point a tick.
      // Except at the floor: this has no `minEnergyCost` of its own, so 0 EN
      // reads 0 s where `burnForSeconds(0)` quotes 1 EN.
      expect(Engine.standard.secondsForEnergy(300), 4500.0);
      expect(Engine.standard.secondsForEnergy(200), 3000.0);
      expect(Engine.standard.secondsForEnergy(40), 600.0);
      expect(Engine.standard.secondsForEnergy(0), 0.0);
    });

    test('a turn is priced on the angle, at the delta-v it costs', () {
      // At speed v a turn of theta changes the velocity vector by
      // 2*v*sin(theta/2). Priced through the same per-light-year scale as any
      // other leg: energyCostFor(40 * 2 sin(theta/2)) == round(200 sin(theta/2)).
      const e = Engine.standard;
      double deg(double d) => d * math.pi / 180;
      expect(e.turnCostFor(0), 0);
      expect(e.turnCostFor(deg(5)), 9);
      expect(e.turnCostFor(deg(10)), 17);
      expect(e.turnCostFor(deg(30)), 52);
      expect(e.turnCostFor(deg(60)), 100);
      expect(e.turnCostFor(deg(90)), 141);
      expect(e.turnCostFor(deg(120)), 173);
      expect(e.turnCostFor(deg(180)), 200);
    });

    test('60 degrees is the crossover: past it, stopping is cheaper', () {
      // Not a coincidence — both quotes are built from `brakingDistanceLy`.
      // Under 60 the turn is the cheap way out; over 60 the ship should brake
      // and re-ignite, which is free. The cockpit says so out loud rather than
      // letting the player overpay in silence.
      const e = Engine.standard;
      final braking = e.brakingCostFor(e.cruiseSpeedLyPerSec);
      expect(braking, 100);
      expect(e.turnCostFor(60 * math.pi / 180), braking);
      expect(e.turnCostFor(30 * math.pi / 180), lessThan(braking));
      expect(e.turnCostFor(120 * math.pi / 180), greaterThan(braking));
    });

    test('an engine saved before activation existed pays the standard fee', () {
      final json = Engine.standard.toJson()..remove('activationCost');
      expect(json.containsKey('activationCost'), isFalse,
          reason: 'precondition: this is what an old save looks like');
      expect(Engine.fromJson(json).activationCost, Engine.standard.activationCost);
    });
  });

  group('drift vocabulary', () {
    test('a parked ship has no momentum and is neither coasting nor cruising',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      expect(c.hasMomentum, isFalse);
      expect(c.isCoasting, isFalse);
      expect(c.isCruising, isFalse);
      expect(c.isDormant, isFalse);
    });

    test('an unpowered drift is a coast, and reads exactly as it did before',
        () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      await _boot(clock, storage: storage);
      await _setDrift(storage, const Vec3(1 / 37.5, 0, 0), clock());
      final c = await _boot(clock, storage: storage);

      expect(c.hasMomentum, isTrue);
      expect(c.isCoasting, isTrue);
      expect(c.isCruising, isFalse);

      // The three getters that used to key off `isCoasting` must give the same
      // answers they always did for a save that predates this feature.
      clock.advance(const Duration(seconds: 100));
      expect(c.driftElapsed, const Duration(seconds: 100));
      expect(c.driftDistanceLy, closeTo(100 / 37.5, 1e-9));
      expect(c.driftPath, isNotNull);
      expect(c.brakingCost, 100);
      expect(c.canBrake, isTrue);
    });

    test('a powered drift is a cruise, not a coast', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      await _boot(clock, storage: storage);
      await _setDrift(storage, const Vec3(1 / 37.5, 0, 0), clock(),
          powered: true);
      final c = await _boot(clock, storage: storage);

      expect(c.hasMomentum, isTrue);
      expect(c.isCruising, isTrue);
      expect(c.isCoasting, isFalse);
      // A cruising ship is still moving, so it still has momentum to shed and
      // the same quote to shed it. If this were zero, "cruise out, then launch
      // a voyage" would be a free ferry.
      expect(c.brakingCost, 100);
    });
  });

  group('igniteCruise', () {
    test('lights the engine along the chosen heading and starts the meter',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final before = c.playerPosition3D;

      expect(await c.igniteCruise(const Vec3(1, 0, 0),
          onEmpty: FuelPolicy.coast), LaunchResult.success);

      expect(c.isCruising, isTrue);
      expect(c.isCoasting, isFalse);
      expect(c.driftVelocity.length,
          closeTo(c.ship.engine.cruiseSpeedLyPerSec, 1e-12));
      // The heading is a direction, not a speed: a caller that passes a long
      // vector must still get cruise speed, not a multiple of it.
      expect(c.driftVelocity.y, closeTo(0, 1e-12));
      expect(c.driftVelocity.z, closeTo(0, 1e-12));
      expect(c.player.cruisePolicy, FuelPolicy.coast,
          reason: 'the choice is made at ignition and acted on much later');
      // The anchor is re-pinned to where the ship already is, so lighting the
      // engine does not teleport it back to its last anchor.
      expect((c.playerPosition3D - before).length, lessThan(1e-9));
      expect(c.driftElapsed, Duration.zero);
    });

    test('ignition itself is free — the price is the power it draws', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await c.igniteCruise(const Vec3(0, 0, 1), onEmpty: FuelPolicy.halt);
      expect(c.energy, 300, reason: 'nothing is charged at t=0');
      expect(c.energyLedger, isEmpty);
    });

    test('a normalised heading of any length gives the same cruise', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await c.igniteCruise(const Vec3(0, 0, 7), onEmpty: FuelPolicy.halt);
      expect(c.driftVelocity.length,
          closeTo(c.ship.engine.cruiseSpeedLyPerSec, 1e-12));
      expect(c.driftVelocity.z, closeTo(c.ship.engine.cruiseSpeedLyPerSec, 1e-12));
    });

    test('refuses a zero heading', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      expect(await c.igniteCruise(const Vec3(0, 0, 0), onEmpty: FuelPolicy.halt),
          LaunchResult.noSelection);
      expect(c.hasMomentum, isFalse);
    });

    test('refuses to light an engine that is already moving the ship', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      expect(await c.igniteCruise(const Vec3(0, 0, 1), onEmpty: FuelPolicy.halt),
          LaunchResult.alreadyTraveling);
      expect(c.driftVelocity.x, greaterThan(0),
          reason: 'the original heading is untouched');
    });

    test('refuses while a voyage is in progress', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final target = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
      await c.launchJourney(target);
      expect(await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt),
          LaunchResult.alreadyTraveling);
    });

    test('refuses at a planet — a docked ship is not stranded', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _docked(clock, storage);
      expect(await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt),
          LaunchResult.alreadyHere);
    });

    test('refuses on an empty tank', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      await _boot(clock, storage: storage);
      await _setEnergy(storage, 0);
      final c = await _boot(clock, storage: storage);
      expect(c.energy, 0, reason: 'precondition: the tank is dry');
      expect(await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt),
          LaunchResult.insufficientEnergy);
    });
  });

  group('a cruise drains the tank', () {
    test('the meter runs while the engine is on', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      expect(c.energy, 300);

      // 37.5 s is one light-year, which is 3 EN — the same quote a voyage of
      // that length gets. Nothing about the price is cruise-specific.
      clock.advance(const Duration(seconds: 37, milliseconds: 500));
      expect(c.energy, 297);

      clock.advance(const Duration(seconds: 1462, milliseconds: 500));
      expect(c.energy, 200, reason: '1500 s is 40 ly is 100 EN');
    });

    test('a coast does not drain anything', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      await _boot(clock, storage: storage);
      await _setDrift(storage, const Vec3(1 / 37.5, 0, 0), clock());
      final c = await _boot(clock, storage: storage);

      clock.advance(const Duration(days: 3));
      expect(c.energy, 300, reason: 'an unpowered drift costs nothing to run');
    });

    test('the reserve is what the cruise must keep to buy its own stop', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      expect(c.cruiseReserve, 100);
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      // While cruising the two quotes coincide, which is the point: the reserve
      // *is* the braking cost, held back rather than spent.
      expect(c.cruiseReserve, c.brakingCost);
    });

    test('the remaining-time readout counts down one-for-one with the meter',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      expect(c.cruiseRemaining, Duration.zero, reason: 'not cruising yet');

      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      // 300 EN less the 100 EN reserve is 200 EN, which is 3000 s.
      expect(c.cruiseRemaining, const Duration(seconds: 3000));

      clock.advance(const Duration(seconds: 1500));
      expect(c.cruiseRemaining, const Duration(seconds: 1500));
    });

    test('a tank that is all reserve is not enough to cruise', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      await _boot(clock, storage: storage);
      await _setEnergy(storage, 100);
      final c = await _boot(clock, storage: storage);
      // Every last drop is already spoken for, so there is no cruise to run —
      // and none to start: `igniteCruise` refuses on a spendable budget of zero
      // (Task 10), which is the same rule `_launchGate` applies as `> braking`.
      expect(await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt),
          LaunchResult.insufficientEnergy);
      expect(c.cruiseRemaining, Duration.zero);

      // One EN past the reserve is a real, if tiny, cruise: 1 EN is 15 s.
      await _setEnergy(storage, 101);
      final c2 = await _boot(clock, storage: storage);
      await c2.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      expect(c2.cruiseRemaining, const Duration(seconds: 15));
    });
  });

  group('settling a cruise leg', () {
    test('braking books the leg and the burn, in that order', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      clock.advance(const Duration(seconds: 1500));
      expect(c.energy, 200, reason: '100 EN of cruise is already spent');

      await c.stopShip();

      // Never 200: the leg's 100 EN was spent the moment it was burned, and the
      // brake's 100 EN comes out of what is left.
      expect(c.energy, 100);
      expect(c.hasMomentum, isFalse);
      expect(c.isCruising, isFalse);
      expect(c.energyLedger, hasLength(2));
      expect(c.energyLedger.first.type, EnergyTxType.braking);
      expect(c.energyLedger.first.amount, -100);
      expect(c.energyLedger[1].type, EnergyTxType.cruiseCost);
      expect(c.energyLedger[1].amount, -100);
    });

    test('the burn is booked once, not once per settle', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      clock.advance(const Duration(seconds: 1500));
      // `_anchorHere` settles too, so `stopShip`'s own settle has to be a no-op
      // the second time round — a double booking here would be silent. Exactly
      // two entries and not three: the leg once, the brake once.
      await c.stopShip();
      expect(c.energyLedger, hasLength(2));
      expect(c.energy, 100);
      // A repeat stop is a no-op at the parked guard, so it must not add an
      // entry either.
      await c.stopShip();
      expect(c.energyLedger, hasLength(2));
      expect(c.energy, 100);
    });

    test('launching a voyage mid-cruise settles the leg and charges the brake',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final target = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      clock.advance(const Duration(seconds: 1500));

      // A lenient policy, so the gate turns only on the braking reserve — the
      // point here is the settlement, not the quote.
      expect(await c.launchJourney(target, onEmpty: FuelPolicy.halt),
          LaunchResult.success);
      expect(c.energy, 100,
          reason: 'the leg and the brake are both gone; the voyage has not burned yet');
      expect(c.isCruising, isFalse);
      expect(c.hasMomentum, isFalse, reason: 'the brake parked the ship');
    });

    test('the gate sees the unbooked burn, not the stale balance', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      // The reserve is all that is left, and it is spoken for. 3000 s is 80 ly is
      // 200 EN — the whole spendable budget — so this is the exhaustion point
      // itself, not a point past it. Advancing further would burn the reserve too
      // and leave nothing, which is a state the finished game never reaches:
      // Task 8's `tick` resolves the cruise at exactly this moment.
      clock.advance(const Duration(seconds: 3000));
      expect(c.energy, 100);
      final far = c.planets
          .where((p) => p.id != c.currentPlanetId)
          .reduce((a, b) => c.distanceTo(a) > c.distanceTo(b) ? a : b);
      expect(await c.launchJourney(far, onEmpty: FuelPolicy.halt),
          LaunchResult.insufficientEnergy,
          reason: 'a lenient launch still needs more than the braking reserve');
    });

    test('braking a cruise clears the powered flag in the save', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      await _boot(clock, storage: storage);
      await _setDrift(storage, const Vec3(1 / 37.5, 0, 0), clock(),
          powered: true);
      final c = await _boot(clock, storage: storage);
      expect(c.isCruising, isTrue, reason: 'precondition: under power');

      await c.stopShip();

      // Read from the save rather than from the getters: `_anchorHere` clears
      // the velocity too, so `hasMomentum` is false whether or not the engine was
      // declared off. Only the persisted flag can tell the difference, and a ship
      // left `driftPowered` would be misread as under power the next time it
      // drifts without igniting.
      expect(await _savedPowered(storage), isFalse);
    });

    test('a voyage that runs dry after a cruise is a coast, not a cruise',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      clock.advance(const Duration(seconds: 1500));

      final far = c.planets
          .where((p) => p.id != c.currentPlanetId)
          .reduce((a, b) => c.distanceTo(a) > c.distanceTo(b) ? a : b);
      expect(await c.launchJourney(far, onEmpty: FuelPolicy.coast),
          LaunchResult.success);
      expect(c.energyCostTo(far), greaterThan(c.energy),
          reason: 'precondition: the voyage must run dry, not arrive');

      clock.advance(const Duration(hours: 1));
      c.tick();

      expect(c.hasMomentum, isTrue, reason: 'the coast left the ship moving');
      expect(c.isCoasting, isTrue);
      expect(c.isCruising, isFalse);
    });
  });

  group('correctHeading', () {
    test('a turn can leave a cruising ship unable to brake', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      // 750 s of burn is 20 ly is 50 EN, so the live tank reads 250 — enough to
      // clear the 180° turn's `turnCostFor(π) == 200` under the lenient
      // `energy >= cost` guard.
      clock.advance(const Duration(seconds: 750));
      expect(c.energy, 250, reason: 'precondition');

      expect(await c.correctHeading(const Vec3(-1, 0, 0)), isTrue,
          reason: 'precondition: the turn is affordable');

      // The turn settles the leg's 50 EN *and* books the 200 EN fee, so the raw
      // balance lands on 50 — under the 100 EN `canBrake` needs — while the ship
      // is still under power and not dormant (`_syncDormancy` trips only at
      // `<= 0`). This is the state the cockpit's brake hint must not offer a
      // stop in: `stopShip` settles the burn and then returns without braking
      // when `canBrake` is false, so the hint would offer a stop that does not
      // happen, at a price the tank cannot pay.
      expect(c.energy, 50);
      expect(c.hasMomentum, isTrue);
      expect(c.isCruising, isTrue);
      expect(c.isDormant, isFalse);
      expect(c.brakingCost, 100);
      expect(c.canBrake, isFalse);
    });
  });

  group('running the tank dry mid-cruise', () {
    /// Ignites [c] with a full tank and runs the cruise to its exhaustion point.
    ///
    /// Takes the controller rather than building one. `_boot` makes a fresh
    /// `MemoryStorage` on every call, so two boots are two controllers over two
    /// separate saves — a helper that booted its own would leave the caller
    /// asserting against a ship that never moved.
    Future<void> exhausted(
      GameController c,
      FakeClock clock,
      FuelPolicy policy,
    ) async {
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: policy);
      // 300 EN less the 100 EN reserve is 200 EN, which is exactly 3000 s.
      clock.advance(const Duration(seconds: 3000));
      c.tick();
    }

    test('halt stops the ship exactly at the quoted 80 ly', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final start = c.playerPosition3D;
      await exhausted(c, clock, FuelPolicy.halt);

      expect(c.hasMomentum, isFalse, reason: 'halt parks the ship');
      expect(c.energy, 100, reason: 'the reserve is kept, not burned');
      expect(c.isDormant, isTrue, reason: 'the tank is out of spendable energy');
      // 3000 s at 1/37.5 ly/s. The exhaustion check compares *seconds*, not
      // energy: `burnForSeconds(elapsed) >= 200` first reaches 200 at 2992.5 s
      // and lands 0.2 ly short of this.
      expect((c.playerPosition3D - start).length, closeTo(80.0, 0.01));
    });

    test('coast keeps the ship moving with the engine off', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final start = c.playerPosition3D;
      await exhausted(c, clock, FuelPolicy.coast);

      expect(c.hasMomentum, isTrue);
      expect(c.isCoasting, isTrue, reason: 'out of power, still moving');
      expect(c.isCruising, isFalse);
      expect(c.isDormant, isTrue);
      expect(c.energy, 100);
      expect(c.driftVelocity.length,
          closeTo(c.ship.engine.cruiseSpeedLyPerSec, 1e-12));
      expect((c.playerPosition3D - start).length, closeTo(80.0, 0.01));

      // And it keeps going, for free, from the exhaust point.
      clock.advance(const Duration(seconds: 1500));
      expect(c.energy, 100);
      expect((c.playerPosition3D - start).length, closeTo(120.0, 0.01));
    });

    test('the whole spendable budget is booked, exactly once', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await exhausted(c, clock, FuelPolicy.halt);
      expect(c.energyLedger, hasLength(1));
      expect(c.energyLedger.first.type, EnergyTxType.cruiseCost);
      expect(c.energyLedger.first.amount, -200);
    });

    test('the burn is not charged for the interval after the tank ran dry',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      // Notice a full day late: the ship had no spendable energy for 23 of those
      // hours, so charging for them would invent a burn that never happened.
      clock.advance(const Duration(days: 1));
      c.tick();
      expect(c.energy, 100);
      expect(c.energyLedger.single.amount, -200);
      expect(c.energyLedger.single.createdAt,
          DateTime(2026).add(const Duration(seconds: 3000)),
          reason: 'booked at the exhaust instant, not the day-late notice');
      // And the ship is where it should have stopped, not where a full day of
      // cruise would have taken it.
      expect(c.driftElapsed, Duration.zero, reason: 'halt cleared the drift');
    });

    test('a coast noticed late still anchors at the exhaust point', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final start = c.playerPosition3D;
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.coast);
      clock.advance(const Duration(days: 1));
      c.tick();

      // 80 ly of powered cruise, then the rest of the day coasting: a day is
      // 86400 s, so 83400 s of coast at cruise speed is a further 2224 ly.
      expect(c.energy, 100);
      expect(c.isCoasting, isTrue);
      expect((c.playerPosition3D - start).length, closeTo(80 + 83400 / 37.5, 1.0));
    });

    test('a fuel-out report is queued for the leg that just ended', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await exhausted(c, clock, FuelPolicy.coast);
      final report = c.pendingDriftReport;
      expect(report, isNotNull);
      expect(report!.kind, DriftReportKind.fuelOut);
      expect(report.distanceLy, closeTo(80.0, 0.01));
      expect(report.elapsed, const Duration(seconds: 3000));
      expect((report.toPos - report.fromPos).length, closeTo(80.0, 0.01));
      expect(report.hitBoundary, isFalse);
    });

    test('tick is a no-op for a cruise that still has time on the clock',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      clock.advance(const Duration(seconds: 2999));
      c.tick();
      expect(c.isCruising, isTrue);
      expect(c.isDormant, isFalse);
      expect(c.energyLedger, isEmpty, reason: 'nothing is booked mid-leg');
    });
  });

  group('recommendedDestination', () {
    test('is never the planet the ship is already parked on', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _docked(clock, storage);
      expect(c.currentPlanetId, isNotNull,
          reason: 'precondition: docked, so there is an own planet to exclude');

      // The guard only bites if the ship's own planet would otherwise win. It
      // sits at distance 0, so it wins whenever it is a hero world, or whenever
      // no hero world is in range to outrank it. Assert that, or removing the
      // guard would change nothing and this test would be vacuous.
      final pool = c.planets
          .where((p) => c.stateOf(p.id) != DiscoveryState.explored)
          .toList();
      final featured = pool.where((p) => p.featured).toList();
      final winner = (featured.isNotEmpty ? featured : pool)
          .reduce((a, b) => c.distanceTo(a) <= c.distanceTo(b) ? a : b);
      expect(winner.id, c.currentPlanetId,
          reason: 'precondition: without the guard the ship would recommend the '
              'planet it is parked on');

      expect(c.recommendedDestination!.id, isNot(c.currentPlanetId));
    });

    test('is never a planet that has already been explored', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _boot(clock, storage: storage);
      final rec0 = c.recommendedDestination;
      expect(rec0, isNotNull, reason: 'precondition: something is recommended');
      await _setExplored(storage, rec0!.id);
      final reloaded = await _boot(clock, storage: storage);
      expect(reloaded.stateOf(rec0.id), DiscoveryState.explored,
          reason: 'precondition: the fixture really marked it explored');

      // `rec0` is the planet the rule already chose, so without the guard it
      // would be chosen again — the guard is the only thing that stopped it.
      final rec1 = reloaded.recommendedDestination;
      expect(rec1, isNotNull);
      expect(rec1!.id, isNot(rec0.id));
      expect(reloaded.stateOf(rec1.id), isNot(DiscoveryState.explored));
    });

    test('prefers the nearest hero world over a nearer ordinary one', () async {
      // Force the preference to matter: explore the current recommendation, so
      // the nearest survivor is generally no longer the nearest hero world.
      // A property, not a fixed answer: the universe is generated from a seed,
      // and pinning a planet id would make this test a hostage of the generator
      // rather than of the rule.
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _boot(clock, storage: storage);
      final rec0 = c.recommendedDestination!;
      await _setExplored(storage, rec0.id);
      final reloaded = await _boot(clock, storage: storage);

      final candidates = reloaded.planets
          .where((p) => p.id != reloaded.currentPlanetId)
          .where((p) => reloaded.stateOf(p.id) != DiscoveryState.explored)
          .toList();
      Planet nearest(Iterable<Planet> pool) => pool.reduce(
          (a, b) => reloaded.distanceTo(a) <= reloaded.distanceTo(b) ? a : b);

      final featured = candidates.where((p) => p.featured).toList();
      expect(featured, isNotEmpty,
          reason: 'precondition: a hero world survives to be preferred');
      final nearestFeatured = nearest(featured);
      final nearestOverall = nearest(candidates);
      expect(nearestFeatured.id, isNot(nearestOverall.id),
          reason: 'precondition: the preference must be able to change the '
              'answer, or this test could not tell the two rules apart');

      expect(reloaded.recommendedDestination!.id, nearestFeatured.id,
          reason: 'a hero world wins even when an ordinary world is nearer');
    });
  });

  group('the cockpit request', () {
    test('is set once, idempotent, and cleared by acknowledging', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      expect(c.cockpitRequested, isFalse);

      var notified = 0;
      c.addListener(() => notified++);
      c.requestCockpit();
      expect(c.cockpitRequested, isTrue);
      expect(notified, 1);
      c.requestCockpit();
      expect(notified, 1, reason: 'an already-set request is not news');

      c.acknowledgeCockpitRequest();
      expect(c.cockpitRequested, isFalse);
      expect(notified, 2, reason: 'clearing a live request is news');
      c.acknowledgeCockpitRequest();
      expect(c.cockpitRequested, isFalse, reason: 'idempotent');
      expect(notified, 2, reason: 'an already-clear request is not news either');
    });

    test('is not persisted — it is a hint for one screen transition', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _boot(clock, storage: storage);
      c.requestCockpit();
      final reloaded = await _boot(clock, storage: storage);
      expect(reloaded.cockpitRequested, isFalse);
    });
  });
}
