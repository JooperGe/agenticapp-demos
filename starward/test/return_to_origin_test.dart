import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/models/engine.dart';
import 'package:starward/data/models/journey.dart';
import 'package:starward/data/models/planet.dart';
import 'package:starward/data/storage/storage_backend.dart';
import 'package:starward/state/game_controller.dart';

/// A hand-advanced clock so tests control the passage of time without waiting.
class FakeClock {
  FakeClock(this._now);
  DateTime _now;
  DateTime call() => _now;
  void advance(Duration d) => _now = _now.add(d);
}

Future<GameController> _boot(FakeClock clock, {int seed = 3}) async {
  final c = GameController(
    repository: GameRepository(MemoryStorage()),
    clock: clock.call,
    random: math.Random(seed),
  );
  await c.init();
  return c;
}

/// Launches somewhere and waits out the trip, so the ship is docked at a planet
/// (the scenario in which 返航 has a planet to come back to).
Future<Planet> _dockAtPlanet(GameController c, FakeClock clock) async {
  final target = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
  await c.launchJourney(target);
  clock.advance(const Duration(hours: 2));
  c.tick();
  return c.currentPlanet!;
}

Planet _farthestPlanet(GameController c, String excludeId) => c.planets
    .where((p) => p.id != excludeId)
    .reduce((a, b) => c.distanceTo(a) > c.distanceTo(b) ? a : b);

void main() {
  group('返航 shortly after departure', () {
    test('plots a real return voyage instead of dumping the ship in deep space',
        () async {
      final clock = FakeClock(DateTime(2026, 1, 1, 12));
      final c = await _boot(clock);
      final origin = await _dockAtPlanet(c, clock);

      await c.launchJourney(_farthestPlanet(c, origin.id));
      // The reported repro: turn back well inside the first 19 s of flight.
      clock.advance(const Duration(seconds: 5));

      final res = await c.returnToOrigin();
      expect(res, LaunchResult.success);

      final back = c.activeJourney;
      expect(back, isNotNull,
          reason: '返航 must plot a return voyage — not stop and drift');
      expect(back!.status, JourneyStatus.inProgress);
      expect(back.destinationPlanetId, origin.id);

      // …and the return voyage actually docks back at the origin planet.
      clock.advance(back.totalDuration + const Duration(seconds: 1));
      c.tick();
      expect(c.currentPlanetId, origin.id);
      expect(c.inDeepSpace, isFalse);
    });

    test('a deep-space origin returns to the exact departure point', () async {
      final clock = FakeClock(DateTime(2026, 1, 1, 12));
      final c = await _boot(clock);
      final departure = c.deepSpaceOrigin3D!;

      await c.launchJourney(
          c.planets.firstWhere((p) => p.id != c.currentPlanetId));
      clock.advance(const Duration(seconds: 5));

      final res = await c.returnToOrigin();
      expect(res, LaunchResult.success);
      final back = c.activeJourney!;
      expect(GameController.isCoordDestination(back.destinationPlanetId), isTrue,
          reason: 'open space is not a planet — it returns to a coordinate');

      clock.advance(back.totalDuration + const Duration(seconds: 1));
      c.tick();
      final parked = c.deepSpaceOrigin3D!;
      expect(parked.x, closeTo(departure.x, 0.001),
          reason: 'must land back on the departure point, not short of it');
      expect(parked.y, closeTo(departure.y, 0.001));
      expect(parked.z, closeTo(departure.z, 0.001));
    });

    test('a return voyage is never zero-length', () async {
      final clock = FakeClock(DateTime(2026, 1, 1, 12));
      final c = await _boot(clock);
      final origin = await _dockAtPlanet(c, clock);

      await c.launchJourney(_farthestPlanet(c, origin.id));
      clock.advance(const Duration(seconds: 5));
      await c.returnToOrigin();

      final back = c.activeJourney!;
      expect(back.totalDuration.inSeconds,
          greaterThanOrEqualTo(c.ship.engine.minTravelSeconds));
      expect(back.energyCost,
          greaterThanOrEqualTo(c.ship.engine.minEnergyCost));
    });
  });

  group('停止 mid-flight is unchanged', () {
    test('still parks the ship in deep space at the point reached', () async {
      final clock = FakeClock(DateTime(2026, 1, 1, 12));
      final c = await _boot(clock);
      final origin = await _dockAtPlanet(c, clock);
      await c.launchJourney(_farthestPlanet(c, origin.id));
      final outbound = c.activeJourney!;

      clock.advance(outbound.totalDuration ~/ 2);
      await c.abortJourney();

      expect(c.activeJourney, isNull);
      expect(c.inDeepSpace, isTrue);
      // Halfway along, so genuinely off the origin — not a disguised 返航.
      final parked = c.deepSpaceOrigin3D!;
      final originPos = c.planetById(origin.id)!.pos;
      expect((parked - originPos).length, greaterThan(1));
    });
  });

  group('返航付不起时', () {
    test('does not book the outbound burn, and never books it twice', () async {
      final clock = FakeClock(DateTime(2026, 1, 1, 12));
      final c = await _boot(clock);
      final origin = await _dockAtPlanet(c, clock);

      final target = _farthestPlanet(c, origin.id);
      expect(await c.launchJourney(target), LaunchResult.success);
      final voyage = c.activeJourney!;
      final outbound = voyage.energyCost;

      clock.advance(voyage.totalDuration ~/ 2);

      // A greedy refit prices the way home far beyond the remaining balance.
      await c.installEngine(const Engine(
        id: 'test.greedy',
        name: '测试引擎',
        energyPerLy: 1000,
        travelSecondsPerLy: 37.5,
        brakingDistanceLy: 40,
        minEnergyCost: 1,
        minTravelSeconds: 15,
      ));

      expect(await c.returnToOrigin(), LaunchResult.insufficientEnergy);

      // The refusal must leave the voyage exactly as it was.
      expect(c.activeJourney!.id, voyage.id, reason: 'still the outbound voyage');
      expect(c.activeJourney!.status, JourneyStatus.inProgress);
      expect(
        c.energyLedger.where((t) => t.relatedObjectId == voyage.id),
        isEmpty,
        reason: 'a refused return must not settle the outbound leg',
      );

      // …and flying it out books that leg once, not twice.
      clock.advance(voyage.totalDuration);
      c.tick();
      expect(c.currentPlanetId, target.id);
      final booked = c.energyLedger
          .where((t) => t.relatedObjectId == voyage.id)
          .toList();
      expect(booked.length, 1, reason: 'booked exactly once');
      expect(booked.single.amount, -outbound);
    });
  });
}
