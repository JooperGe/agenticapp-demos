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

Future<GameController> _boot(FakeClock clock) async {
  final c = GameController(
    repository: GameRepository(MemoryStorage()),
    clock: clock.call,
    random: math.Random(3),
  );
  await c.init();
  return c;
}

/// Ignites east and burns for [seconds], so the ship is mid-cruise with a
/// settled, known energy balance.
///
/// `FuelPolicy.coast` throughout: the policy is only consulted when the tank
/// runs dry, and a cruise test that reaches that point wants the ship still
/// drifting so it has a course left to correct.
Future<GameController> _cruising(FakeClock clock, int seconds) async {
  final c = await _boot(clock);
  await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.coast);
  clock.advance(Duration(seconds: seconds));
  return c;
}

void main() {
  group('the turn price', () {
    test('is zero for the heading the ship is already on', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _cruising(clock, 1500);
      expect(c.turnAngleTo(const Vec3(1, 0, 0)), closeTo(0, 1e-9));
      expect(c.turnCostTo(const Vec3(1, 0, 0)), 0);
    });

    test('is the pinned price for the pinned angles', () async {
      // `turnCostFor` is `energyCostFor(brakingDistanceLy · Δv / cruiseSpeed)`
      // where `Δv = 2 · v · sin(θ/2)`. With the standard engine
      // (2.5 EN/ly, v = 1/37.5, braking 40 ly) that gives exactly these:
      final clock = FakeClock(DateTime(2026));
      final c = await _cruising(clock, 1500);
      final cases = <double, int>{
        5: 9,
        10: 17,
        30: 52,
        60: 100,
        90: 141,
        120: 173,
        180: 200,
      };
      cases.forEach((degrees, cost) {
        // A heading rotated `degrees` off +X in the XY plane.
        final rad = degrees * math.pi / 180;
        final heading = Vec3(math.cos(rad), math.sin(rad), 0);
        expect(c.turnAngleTo(heading), closeTo(rad, 1e-9),
            reason: '$degrees° off the bow');
        expect(c.turnCostTo(heading), cost, reason: '$degrees°');
      });
    });

    test('a hairpin is twice the price of a full stop', () async {
      // Not a bug and not fixable by pricing — it is the Δv the turn really
      // costs. The UI's job is to say so; see Task 16's brake hint.
      final clock = FakeClock(DateTime(2026));
      final c = await _cruising(clock, 1500);
      expect(c.turnCostTo(const Vec3(-1, 0, 0)), 200);
      expect(c.brakingCost, 100);
    });

    test('the crossover is at 60°, where turning costs the same as stopping',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _cruising(clock, 1500);
      final engine = c.ship.engine;
      final braking = engine.brakingCostFor(engine.cruiseSpeedLyPerSec);
      // Not 59.9/60.1: `turnCostFor` is quoted through `energyCostFor`, which
      // rounds to whole EN, and 0.1° of turn is worth about 0.15 EN — both of
      // those read 100 and the assertions would be `100 < 100` and
      // `100 > 100`. Half a degree is the tightest step the EN grid can
      // express here: 59.5° is 99.24 EN, 60.5° is 100.75 EN.
      expect(engine.turnCostFor(59.5 * math.pi / 180), lessThan(braking));
      expect(engine.turnCostFor(60 * math.pi / 180), braking);
      expect(engine.turnCostFor(60.5 * math.pi / 180), greaterThan(braking));
    });

    test('is zero when the ship is not moving — there is no course to be off',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      expect(c.turnAngleTo(const Vec3(0, 0, 1)), 0);
      expect(c.turnCostTo(const Vec3(0, 0, 1)), 0);
    });
  });

  group('correctHeading', () {
    test('bills the burn and the turn, in that order, and re-aims the ship',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _cruising(clock, 1500);
      expect(c.energy, 200, reason: '300 − 1500 s of burn (100 EN)');

      expect(await c.correctHeading(const Vec3(0, 0, 1)), isTrue);

      // 200 − 141 (a 90° turn) = 59.
      expect(c.energy, 59);
      // Newest first: the turn, then the burn that preceded it.
      expect(c.energyLedger.first.type, EnergyTxType.turn);
      expect(c.energyLedger.first.amount, -141);
      expect(c.energyLedger[1].type, EnergyTxType.cruiseCost);
      expect(c.energyLedger[1].amount, -100);

      // The ship now moves along the new heading at the same speed.
      final v = c.driftVelocity;
      expect(v.x, closeTo(0, 1e-9));
      expect(v.z, closeTo(Engine.standard.cruiseSpeedLyPerSec, 1e-12));
    });

    test('does not teleport the ship — the anchor is re-pinned at the turn',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      // The generated system decides where the ship wakes up, so the claims
      // below are displacements from that spawn rather than absolute
      // coordinates — the same way `cruise_test.dart` measures a leg.
      final start = c.playerPosition3D;
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.coast);
      clock.advance(const Duration(seconds: 1500));
      // 1500 s at 1/37.5 ly/s = 40 ly east.
      expect(c.playerPosition3D.x, closeTo(start.x + 40, 1e-6));
      expect(c.playerPosition3D.z, closeTo(start.z, 1e-9));

      await c.correctHeading(const Vec3(0, 0, 1));
      expect(c.playerPosition3D.x, closeTo(start.x + 40, 1e-6),
          reason: 'the turn happens where the ship is, not where it started');
      expect(c.playerPosition3D.z, closeTo(start.z, 1e-9));

      clock.advance(const Duration(seconds: 375)); // 10 ly
      expect(c.playerPosition3D.x, closeTo(start.x + 40, 1e-6),
          reason: 'the velocity was rotated, not added to — x has stopped');
      expect(c.playerPosition3D.z, closeTo(start.z + 10, 1e-6));
    });

    test('a zero-angle correction is free but still settles the burn',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _cruising(clock, 1500);
      expect(await c.correctHeading(const Vec3(1, 0, 0)), isTrue);
      expect(c.energy, 200, reason: 'nothing turned, but the burn is now booked');
      expect(c.energyLedger.length, 1);
      expect(c.energyLedger.first.type, EnergyTxType.cruiseCost);
    });

    test('refuses when the live balance cannot cover the turn', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _cruising(clock, 2400); // 300 − 160 = 140 EN left
      expect(c.energy, 140);
      expect(c.turnCostTo(const Vec3(-1, 0, 0)), 200);

      expect(await c.correctHeading(const Vec3(-1, 0, 0)), isFalse);
      expect(c.energy, 140, reason: 'a refusal spends nothing');
      expect(c.energyLedger, isEmpty, reason: 'and books nothing');
      expect(c.driftVelocity.x, closeTo(1 / 37.5, 1e-12),
          reason: 'the ship is still on the old heading');
    });

    test('refuses while the engine is dormant', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _cruising(clock, 1500);
      // Run it dry: budget = 300 − 100 reserve = 200 EN = 3000 s.
      clock.advance(const Duration(seconds: 1500));
      c.tick();
      expect(c.isDormant, isTrue, reason: 'precondition: shut down');
      expect(c.isCoasting, isTrue);
      expect(c.energy, 100);

      expect(await c.correctHeading(const Vec3(0, 0, 1)), isFalse);
      expect(c.energy, 100);
    });

    test('refuses when the ship is parked', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      expect(await c.correctHeading(const Vec3(0, 0, 1)), isFalse);
    });

    test('turning a coast re-lights the engine, and it burns again from there',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _cruising(clock, 3000);
      c.tick();
      expect(c.isCoasting, isTrue, reason: 'precondition: out of power');
      expect(c.energy, 100, reason: 'the braking reserve is still aboard');

      expect(await c.activate(), isTrue);
      expect(c.energy, 95);

      // 30° off the bow is 52 EN, which 95 EN covers. A 90° turn (141 EN) would
      // be *refused* — after activation the ship holds only the 100 EN reserve,
      // which is the trap 已知取舍 #2 describes. Worth knowing before writing a
      // test that expects a big turn here to succeed.
      final heading = Vec3(math.cos(math.pi / 6), math.sin(math.pi / 6), 0);
      expect(c.turnCostTo(heading), 52);
      expect(await c.correctHeading(heading), isTrue);
      expect(c.energy, 43);
      expect(c.isCruising, isTrue, reason: 'the engine is driving again');
      expect(c.energyLedger.first.type, EnergyTxType.turn);
      expect(c.energyLedger.first.amount, -52);
    });

    test('a turn that spends the last drop shuts the engine down', () async {
      // The guard is `energy < cost`, so `energy == cost` goes through — this is
      // the exact boundary it permits, and the one place a turn can leave the
      // tank at zero. `_settleCruise` ran before the deduction and saw 200, so
      // the shutdown has to come from `correctHeading` itself.
      final clock = FakeClock(DateTime(2026));
      final c = await _cruising(clock, 1500);
      expect(c.energy, 200, reason: 'exactly enough for a hairpin');
      expect(await c.correctHeading(const Vec3(-1, 0, 0)), isTrue);
      expect(c.energy, 0);
      expect(c.isDormant, isTrue,
          reason: 'the turn spent the last drop, so the shutdown follows');
    });

    test('a correction survives a reload', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = GameController(
        repository: GameRepository(storage),
        clock: clock.call,
        random: math.Random(3),
      );
      await c.init();
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      clock.advance(const Duration(seconds: 1500));
      await c.correctHeading(const Vec3(0, 0, 1));

      final reloaded = GameController(
        repository: GameRepository(storage),
        clock: clock.call,
        random: math.Random(3),
      );
      await reloaded.init();
      expect(reloaded.energy, 59);
      expect(reloaded.driftVelocity.z, closeTo(1 / 37.5, 1e-12));
      expect(reloaded.isCruising, isTrue,
          reason: 'a powered drift survives the reload as a powered drift');
    });
  });
}
