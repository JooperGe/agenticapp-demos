import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/models/energy_transaction.dart';
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
    random: math.Random(2),
  );
  await c.init();
  return c;
}

/// The closest planet we could launch to — the cheapest hop on offer.
Planet _nearest(GameController c) => c.planets
    .where((p) => p.id != c.currentPlanetId)
    .reduce((a, b) => c.distanceTo(a) <= c.distanceTo(b) ? a : b);

void main() {
  group('energy economy', () {
    test('launch quotes from the engine; the burn settles on arrival', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final before = c.energy;
      final target = _nearest(c);
      final cost = c.energyCostTo(target);
      final total = c.travelDurationTo(target);

      await c.launchJourney(target);
      expect(c.energy, before, reason: 'nothing burns at t=0');
      // Cost scales linearly with distance, floored so a hop is never free —
      // and it comes off the ship's fitted engine, not a global table.
      expect(cost, c.ship.engine.energyCostFor(c.distanceTo(target)));

      clock.advance(total + const Duration(seconds: 1));
      c.tick();
      expect(c.energy, before - cost);
    });

    test('cannot launch without enough energy and balance is untouched',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      // Drain energy by repeatedly completing arrivals + exploring is slow;
      // instead pick a long trip and spend down with resets is awkward, so we
      // assert the guard directly on a long trip after draining via training
      // is not needed — drain by launching+acknowledging short hops.
      var guardHit = false;
      for (var i = 0; i < 50; i++) {
        final target = c.planets.firstWhere(
          (p) => p.id != c.currentPlanetId,
          orElse: () => c.planets.first,
        );
        final before = c.energy;
        final r = await c.launchJourney(target);
        if (r == LaunchResult.insufficientEnergy) {
          expect(c.energy, before); // nothing deducted
          guardHit = true;
          break;
        }
        if (r == LaunchResult.success) {
          clock.advance(const Duration(hours: 1));
          c.tick(); // arrive
          await c.acknowledgeArrival();
        }
      }
      expect(guardHit, isTrue, reason: 'energy should eventually run out');
      expect(c.energy, greaterThanOrEqualTo(0));
    });

    test('energy never goes negative', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      for (var i = 0; i < 100; i++) {
        final target = c.planets.firstWhere(
          (p) => p.id != c.currentPlanetId,
          orElse: () => c.planets.first,
        );
        final r = await c.launchJourney(target);
        if (r == LaunchResult.success) {
          clock.advance(const Duration(hours: 1));
          c.tick();
          await c.acknowledgeArrival();
        }
        expect(c.energy, greaterThanOrEqualTo(0));
      }
    });

    test('every balance change leaves a ledger entry', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final target = _nearest(c);
      final cost = c.energyCostTo(target);
      final total = c.travelDurationTo(target);
      await c.launchJourney(target);
      expect(c.energyLedger, isEmpty, reason: 'booked at the end, not the start');

      clock.advance(total + const Duration(seconds: 1));
      c.tick();
      expect(c.energyLedger.first.amount, -cost);
      expect(c.energyLedger.first.type, EnergyTxType.travelCost);
    });
  });

  group('training rewards claim-once', () {
    test('completing a course grants reward exactly once', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final before = c.energy;

      final session = await c.startCourse('walk');
      final first = await c.completeCourse(session.id, 40);
      expect(first, TrainingClaimResult.success);
      expect(c.energy, before + 40);

      final second = await c.completeCourse(session.id, 40);
      expect(second, TrainingClaimResult.alreadyClaimed);
      expect(c.energy, before + 40); // no double grant
    });
  });
}
