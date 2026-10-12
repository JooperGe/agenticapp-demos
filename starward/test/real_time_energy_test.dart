import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/models/energy_transaction.dart';
import 'package:starward/data/models/journey.dart';
import 'package:starward/data/models/planet.dart';
import 'package:starward/data/storage/storage_backend.dart';
import 'package:starward/state/game_controller.dart';

/// A voyage that departs 12:00 and arrives 12:10, quoting 100 EN.
Journey _tenMinuteVoyage() => Journey(
      id: 'jny-1',
      originPlanetId: 'a',
      destinationPlanetId: 'b',
      departure: DateTime(2026, 1, 1, 12),
      arrival: DateTime(2026, 1, 1, 12, 10),
      energyCost: 100,
      status: JourneyStatus.inProgress,
    );

DateTime _at(int minute) => DateTime(2026, 1, 1, 12, minute);

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
  group('Journey.burnedAt', () {
    test('burns in proportion to distance covered', () {
      final j = _tenMinuteVoyage();
      expect(j.burnedAt(_at(0)), 0);
      expect(j.burnedAt(_at(2)), 20);
      expect(j.burnedAt(_at(5)), 50);
      expect(j.burnedAt(_at(10)), 100);
    });

    test('never over-burns past arrival', () {
      final j = _tenMinuteVoyage();
      // A voyage reconciled an hour late must not bill more than it quoted.
      expect(j.burnedAt(_at(70)), 100);
    });

    test('never burns before departure', () {
      final j = _tenMinuteVoyage();
      expect(j.burnedAt(DateTime(2026, 1, 1, 11, 30)), 0);
    });
  });

  group('real-time energy', () {
    test('launch burns nothing; the burn accrues with progress', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final before = c.energy;
      final target = _nearest(c);
      final cost = c.energyCostTo(target);
      final total = c.travelDurationTo(target);

      await c.launchJourney(target);

      // Not a drop has burned at t=0.
      expect(c.energy, before);
      expect(c.energyLedger, isEmpty, reason: 'nothing is booked at launch');

      // Halfway: exactly half the quoted cost is gone.
      clock.advance(Duration(milliseconds: total.inMilliseconds ~/ 2));
      expect(c.energy, before - (cost * 0.5).round());

      // Arrival settles the whole quote.
      clock.advance(total);
      c.tick();
      expect(c.energy, before - cost);
      expect(c.energyLedger.single.amount, -cost);
      expect(c.energyLedger.single.type, EnergyTxType.travelCost);
    });

    test('an in-flight reading survives a kill and restart', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c1 = await _boot(clock, storage: storage);
      final target = _nearest(c1);
      final cost = c1.energyCostTo(target);
      final total = c1.travelDurationTo(target);
      final balance = c1.energy;
      await c1.launchJourney(target);

      clock.advance(Duration(milliseconds: total.inMilliseconds ~/ 4));
      final live = c1.energy;
      expect(live, closeTo(balance - cost * 0.25, 1),
          reason: 'a quarter of the way is a quarter of the fuel');

      // "Kill the process": a brand-new controller reads the same save.
      final c2 = await _boot(clock, storage: storage);
      expect(c2.energy, live,
          reason: 'the reading follows the clock, not the process uptime');
      expect(c2.activeJourney!.energyCost, cost, reason: 'the quote is stable');
      expect(c2.energyLedger, isEmpty,
          reason: 'nothing is booked until the voyage ends');
    });

    test('a top-up mid-voyage lands in the live reading', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final target = _nearest(c);
      final cost = c.energyCostTo(target);
      final total = c.travelDurationTo(target);
      final balance = c.energy;
      await c.launchJourney(target);

      clock.advance(Duration(milliseconds: total.inMilliseconds ~/ 2));
      final halfway = c.energy;
      expect(halfway, closeTo(balance - cost * 0.5, 1));

      // Training has no position or energy precondition, so a course can be
      // finished mid-flight. The reward goes straight onto the balance — which
      // is what makes a doomed voyage rescuable. Task 8 pins that consequence;
      // here we only pin that the live reading moves.
      final session = await c.startCourse('walk');
      await c.completeCourse(session.id, 40);
      expect(c.energy, halfway + 40,
          reason: 'a top-up lands straight in the live reading');

      clock.advance(total);
      c.tick();
      expect(c.currentPlanetId, target.id, reason: 'the trip still completes');
      expect(c.energy, balance + 40 - cost,
          reason: 'arrival books exactly the quote, top-up included');
    });

    test('aborting books only what was actually burned', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final before = c.energy;
      final target = _nearest(c);
      final cost = c.energyCostTo(target);
      final total = c.travelDurationTo(target);
      await c.launchJourney(target);

      clock.advance(Duration(milliseconds: total.inMilliseconds ~/ 4));
      await c.abortJourney();

      final burned = (cost * 0.25).round();
      expect(c.energy, before - burned, reason: 'unburned fuel never left');
      expect(c.energyLedger.single.amount, -burned);
      expect(c.inDeepSpace, isTrue);
    });

    test('turning back settles the outbound leg before quoting the return',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final before = c.energy;
      final target = _nearest(c);
      final cost = c.energyCostTo(target);
      final total = c.travelDurationTo(target);
      await c.launchJourney(target);

      clock.advance(Duration(milliseconds: total.inMilliseconds ~/ 2));
      await c.returnToOrigin();

      final burned = (cost * 0.5).round();
      final back = c.activeJourney!;
      // Exactly two ledger entries are possible at this point: the settled
      // outbound burn, and the return leg's own quote (settled on arrival).
      expect(c.energy, before - burned, reason: 'only the outbound leg burned');
      expect(c.energyLedger.map((t) => t.amount).toList(), <int>[-burned]);
      expect(back.energyCost, greaterThan(0));

      clock.advance(back.totalDuration + const Duration(seconds: 1));
      c.tick();
      expect(c.energy, before - burned - back.energyCost);
      expect(c.energyLedger.length, 2);
    });
  });

  group('v2 save migration', () {
    test('a pre-energy-model save gets its up-front deduction back', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _boot(clock, storage: storage);
      final target = _nearest(c);
      final cost = c.energyCostTo(target);
      final total = c.travelDurationTo(target);
      await c.launchJourney(target);
      clock.advance(Duration(milliseconds: total.inMilliseconds ~/ 2));
      final live = c.energy;
      final balanceBefore = c.player.energyBalance;

      // Rewrite the save the way v2 wrote it: the whole quote already
      // deducted, and no energyModel marker.
      final raw = await storage.read('starward.save.v2');
      final json = jsonDecode(raw!) as Map<String, dynamic>;
      final player = json['player'] as Map<String, dynamic>;
      player['energyBalance'] = (player['energyBalance'] as int) - cost;
      json.remove('energyModel');
      await storage.write('starward.save.v2', jsonEncode(json));

      // Loading migrates it: the deduction comes back, so the live reading is
      // exactly what it was before the round trip.
      final c2 = await _boot(clock, storage: storage);
      expect(c2.energy, live);
      expect(c2.player.energyBalance, balanceBefore,
          reason: 'the migration hands back exactly the quote v2 had taken');
    });

    test('a save with no voyage in flight is left alone', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _boot(clock, storage: storage);
      final before = c.energy;

      final raw = await storage.read('starward.save.v2');
      final json = jsonDecode(raw!) as Map<String, dynamic>;
      json.remove('energyModel');
      await storage.write('starward.save.v2', jsonEncode(json));

      final c2 = await _boot(clock, storage: storage);
      expect(c2.energy, before);
    });

    test('the marker survives a round trip', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      await _boot(clock, storage: storage);
      final raw = await storage.read('starward.save.v2');
      final json = jsonDecode(raw!) as Map<String, dynamic>;
      expect(json['energyModel'], 2);
    });
  });
}
