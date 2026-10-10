import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/balance.dart';
import 'package:starward/data/game_repository.dart';
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

Future<GameController> _boot(FakeClock clock, {MemoryStorage? storage}) async {
  final controller = GameController(
    repository: GameRepository(storage ?? MemoryStorage()),
    clock: clock.call,
    random: math.Random(1),
  );
  await controller.init();
  return controller;
}

Planet _firstReachable(GameController c, TravelTier tier) {
  return c.planets.firstWhere(
    (p) => p.id != c.currentPlanetId && c.tierTo(p) == tier,
  );
}

void main() {
  group('journey progress is derived from timestamps', () {
    test('progress and remaining track the clock', () async {
      final clock = FakeClock(DateTime(2026, 1, 1, 12));
      final c = await _boot(clock);
      final target = _firstReachable(c, TravelTier.short);

      final result = await c.launchJourney(target);
      expect(result, LaunchResult.success);

      final journey = c.activeJourney!;
      expect(journey.progressAt(clock()), 0.0);

      final half = journey.totalDuration ~/ 2;
      clock.advance(half);
      expect(journey.progressAt(clock()), closeTo(0.5, 0.02));
      expect(journey.remainingAt(clock()).inSeconds,
          closeTo((journey.totalDuration - half).inSeconds, 1));
    });

    test('progress clamps to 1 and remaining never goes negative', () async {
      final clock = FakeClock(DateTime(2026, 1, 1, 12));
      final c = await _boot(clock);
      final target = _firstReachable(c, TravelTier.short);
      await c.launchJourney(target);
      final journey = c.activeJourney!;

      clock.advance(const Duration(days: 1));
      expect(journey.progressAt(clock()), 1.0);
      expect(journey.remainingAt(clock()), Duration.zero);
    });
  });

  group('arrival reconciliation survives restart', () {
    test('a journey finished while away is arrived on relaunch', () async {
      final storage = MemoryStorage();
      final clock = FakeClock(DateTime(2026, 1, 1, 12));
      final c1 = await _boot(clock, storage: storage);
      final target = _firstReachable(c1, TravelTier.short);
      await c1.launchJourney(target);
      expect(c1.isTraveling, isTrue);

      // Simulate the app being closed, time passing, then relaunching.
      clock.advance(const Duration(hours: 2));
      final c2 = await _boot(clock, storage: storage);

      expect(c2.activeJourney, isNotNull);
      expect(c2.activeJourney!.status, JourneyStatus.arrived);
      expect(c2.currentPlanet!.id, target.id);
      expect(c2.stateOf(target.id), DiscoveryState.discovered);
      expect(c2.isTraveling, isFalse);
    });
  });

  group('single active journey', () {
    test('cannot launch a second journey while in progress', () async {
      final clock = FakeClock(DateTime(2026, 1, 1, 12));
      final c = await _boot(clock);
      final a = _firstReachable(c, TravelTier.short);
      await c.launchJourney(a);
      final energyAfterFirst = c.energy;

      final b = c.planets.firstWhere((p) => p.id != a.id && p.id != c.currentPlanetId);
      final result = await c.launchJourney(b);
      expect(result, LaunchResult.alreadyTraveling);
      // No extra energy was deducted by the rejected launch.
      expect(c.energy, energyAfterFirst);
    });
  });
}
