import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/vec3.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/models/drift_report.dart';
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
    random: math.Random(5),
  );
  await c.init();
  return c;
}

/// Rewrites the saved drift so the ship is coasting from a known anchor, then
/// reboots. Going through the save rather than a setter also proves the drift
/// fields round-trip through JSON.
Future<GameController> _drifting(
  FakeClock clock,
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
  return _boot(clock, storage);
}

/// A greedy engine makes even a short hop unaffordable on a full tank — a
/// cheaper route to a doomed voyage than draining 300 EN a hop at a time.
const _greedy = Engine(
  id: 'test.greedy',
  name: '测试引擎',
  energyPerLy: 1000,
  travelSecondsPerLy: 37.5,
  minEnergyCost: 1,
  minTravelSeconds: 15,
);

void main() {
  group('a parked ship is never reported on', () {
    test('a brand new player', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _boot(clock, storage);
      // Without this guard `driftStartedAt` defaults to the epoch and every new
      // player would be told they had been drifting for fifty-six years.
      expect(c.pendingDriftReport, isNull);
    });

    test('a player who comes back much later without moving', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      await _boot(clock, storage);
      clock.advance(const Duration(days: 30));
      final c2 = await _boot(clock, storage);
      expect(c2.pendingDriftReport, isNull);
    });

    test('after aborting a voyage', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _boot(clock, storage);
      final target = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
      await c.launchJourney(target);
      clock.advance(const Duration(minutes: 1));
      await c.abortJourney();
      expect(c.inDeepSpace, isTrue);
      expect(c.isCoasting, isFalse);
      clock.advance(const Duration(days: 7));
      final c2 = await _boot(clock, storage);
      expect(c2.pendingDriftReport, isNull);
    });
  });

  group('the offline drift report', () {
    test('measures the window the player could not watch', () async {
      final start = DateTime(2026, 3, 1, 9);
      final clock = FakeClock(start);
      final storage = MemoryStorage();
      await _boot(clock, storage);
      final c = await _drifting(clock, storage, const Vec3(1, 0, 0), start);
      expect(c.pendingDriftReport, isNull,
          reason: 'no time has passed yet');

      clock.advance(const Duration(minutes: 10));
      final c2 = await _boot(clock, storage);
      final r = c2.pendingDriftReport!;

      expect(r.kind, DriftReportKind.drift);
      expect(r.from, start);
      expect(r.to, clock());
      expect(r.elapsed, const Duration(minutes: 10));
      expect(r.distanceLy, closeTo(600, 1e-6));
      expect(r.fromPos.x, closeTo(c2.playerPosition3D.x - 600, 1e-6));
      expect(r.toPos.x, closeTo(c2.playerPosition3D.x, 1e-6));
      expect(r.hitBoundary, isFalse, reason: '600 ly, well inside the shell');
    });

    test('a drift that reached the shell says so', () async {
      final start = DateTime(2026, 3, 1);
      final clock = FakeClock(start);
      final storage = MemoryStorage();
      await _boot(clock, storage);
      // Anchored just inside the shell, heading straight out at 1 ly/s.
      final raw = await storage.read('starward.save.v2');
      final json = jsonDecode(raw!) as Map<String, dynamic>;
      final player = json['player'] as Map<String, dynamic>;
      player['startX'] = 3000.0;
      player['startY'] = 0.0;
      player['startZ'] = 0.0;
      player['driftVelocityX'] = 1.0;
      player['driftVelocityY'] = 0.0;
      player['driftVelocityZ'] = 0.0;
      player['driftStartedAt'] = start.millisecondsSinceEpoch;
      await storage.write('starward.save.v2', jsonEncode(json));

      clock.advance(const Duration(days: 1));
      final c = await _boot(clock, storage);
      final r = c.pendingDriftReport!;
      expect(r.hitBoundary, isTrue);
      expect(r.toPos.length, closeTo(c.universe.universeRadius, 1.0));
      // Purely radial: it stops at the point where it met the shell rather
      // than sliding, so it travelled exactly the gap it had left.
      expect(r.distanceLy, closeTo(c.universe.universeRadius - 3000, 1.0));
    });

    test('a reboot recomputes the window for the still-running drift', () async {
      final start = DateTime(2026, 3, 1);
      final clock = FakeClock(start);
      final storage = MemoryStorage();
      await _boot(clock, storage);
      await _drifting(clock, storage, const Vec3(1, 0, 0), start);
      clock.advance(const Duration(minutes: 5));
      final c = await _boot(clock, storage);
      expect(c.pendingDriftReport, isNotNull);
      final firstElapsed = c.pendingDriftReport!.elapsed;

      // Acknowledging dismisses the auto-shown sheet; it does not claim the
      // drift is over, so the next boot reports the longer window afresh.
      await c.acknowledgeDriftReport();
      expect(c.pendingDriftReport, isNull);

      clock.advance(const Duration(minutes: 5));
      final c2 = await _boot(clock, storage);
      expect(c2.pendingDriftReport, isNotNull,
          reason: 'a reboot recomputes the whole drift window');
      expect(c2.pendingDriftReport!.elapsed, greaterThan(firstElapsed),
          reason: 'the window grows with the drift, so this is a new report');
    });

    test('it survives a kill before the player ever read it', () async {
      final start = DateTime(2026, 3, 1);
      final clock = FakeClock(start);
      final storage = MemoryStorage();
      await _boot(clock, storage);
      await _drifting(clock, storage, const Vec3(1, 0, 0), start);
      clock.advance(const Duration(minutes: 30));

      // Booted once (which queued the report) but the app was killed before the
      // sheet was opened.
      final c = await _boot(clock, storage);
      expect(c.pendingDriftReport, isNotNull);
      final c2 = await _boot(clock, storage);
      expect(c2.pendingDriftReport, isNotNull,
          reason: 'the window is recomputed on the next boot and is not lost');
      expect(c2.pendingDriftReport!.elapsed, const Duration(minutes: 30));
    });

    test('the coasting screen can ask for one on demand', () async {
      final start = DateTime(2026, 3, 1);
      final clock = FakeClock(start);
      final storage = MemoryStorage();
      await _boot(clock, storage);
      await _drifting(clock, storage, const Vec3(1, 0, 0), start);
      clock.advance(const Duration(hours: 1));
      final c = await _boot(clock, storage);
      await c.acknowledgeDriftReport();
      expect(c.pendingDriftReport, isNull);

      clock.advance(const Duration(hours: 4));
      await c.requestDriftReport();
      expect(c.pendingDriftReport!.elapsed, const Duration(hours: 5),
          reason: 'the whole drift so far, not just since the last report');
    });
  });

  group('the fuel-out report', () {
    test('covers the powered leg, not the drift that follows', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _boot(clock, storage);
      await c.installEngine(_greedy);

      final target = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
      final origin = c.playerPosition3D;
      final distanceLy = c.distanceTo(target);
      final cost = c.energyCostTo(target);
      final balance = c.energy;
      expect(balance, 300);
      expect(cost, greaterThan(balance), reason: 'precondition: unaffordable');

      expect(await c.launchJourney(target, onEmpty: FuelPolicy.coast),
          LaunchResult.success);
      final journey = c.activeJourney!;
      final exhaustAt = c.fuelExhaustTime(journey);
      expect(c.fuelExhaustProgress, closeTo(balance / cost, 1e-12));

      clock.advance(exhaustAt.difference(clock()) + const Duration(seconds: 1));
      c.tick();
      expect(c.isCoasting, isTrue);

      final r = c.pendingDriftReport!;
      expect(r.kind, DriftReportKind.fuelOut);
      expect(r.from, journey.departure);
      expect(r.to, exhaustAt);
      expect(r.elapsed, exhaustAt.difference(journey.departure));
      expect(r.fromPos.x, closeTo(origin.x, 1e-6));
      // The window ends at the exhaust point, not at the ship's current
      // position: a second of coasting has passed by now, so a window that ran
      // on into the drift would report the current position instead.
      expect(r.toPos.x, isNot(closeTo(c.playerPosition3D.x, 1e-6)));
      expect(r.distanceLy, closeTo((r.toPos - r.fromPos).length, 1e-6),
          reason: 'the powered leg is a straight line');
      expect(r.distanceLy, closeTo(distanceLy * balance / cost, 0.01));
      expect(r.hitBoundary, isFalse);
    });

    test('a mid-flight top-up means there is nothing to report', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _boot(clock, storage);
      await c.installEngine(_greedy);
      final target = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
      final cost = c.energyCostTo(target);
      await c.launchJourney(target, onEmpty: FuelPolicy.coast);
      final journey = c.activeJourney!;

      // Enough training to cover the rest of the quote. Priced off the quote
      // rather than a fixed number: the greedy engine bills this leg in the
      // thousands, so a constant would leave the tank short.
      final session = await c.startCourse('walk');
      await c.completeCourse(session.id, cost);
      expect(c.fuelExhaustProgress, 1.0);

      clock.advance(journey.totalDuration + const Duration(seconds: 1));
      c.tick();
      expect(c.currentPlanetId, target.id, reason: 'it simply arrives');
      expect(c.pendingDriftReport, isNull);
    });
  });

  group('a queued report survives a restart', () {
    test('a fuel-out report is restored, not rebuilt', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _boot(clock, storage);
      await c.installEngine(_greedy);
      final target = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
      expect(await c.launchJourney(target, onEmpty: FuelPolicy.coast),
          LaunchResult.success);
      final journey = c.activeJourney!;

      clock.advance(c.fuelExhaustTime(journey).difference(clock()) +
          const Duration(seconds: 1));
      c.tick();
      final queued = c.pendingDriftReport!;
      expect(queued.kind, DriftReportKind.fuelOut);

      // Killed before the sheet was opened. The powered leg is history:
      // `buildDriftReport` only ever produces the `drift` kind, so this window
      // cannot be recomputed after the fact — it has to survive the restart.
      final c2 = await _boot(clock, storage);
      final r = c2.pendingDriftReport!;
      expect(r.kind, DriftReportKind.fuelOut);
      expect(r.from, queued.from);
      expect(r.to, queued.to);
      expect(r.distanceLy, queued.distanceLy);
    });

    test('a drift report is recomputed, not restored stale', () async {
      final start = DateTime(2026, 3, 1);
      final clock = FakeClock(start);
      final storage = MemoryStorage();
      await _boot(clock, storage);
      await _drifting(clock, storage, const Vec3(1, 0, 0), start);
      clock.advance(const Duration(minutes: 5));
      final c = await _boot(clock, storage);

      // Get a drift report onto disk: init() only builds one in memory, so
      // acknowledge the auto-queued one and ask again — requestDriftReport()
      // is what persists.
      await c.acknowledgeDriftReport();
      await c.requestDriftReport();
      final persisted = c.pendingDriftReport!;
      expect(persisted.kind, DriftReportKind.drift);

      clock.advance(const Duration(hours: 3));
      final c2 = await _boot(clock, storage);
      expect(c2.pendingDriftReport!.kind, DriftReportKind.drift);
      expect(c2.pendingDriftReport!.to, clock(),
          reason: 'the window is rebuilt for the later boot, not restored');
      expect(c2.pendingDriftReport!.elapsed, greaterThan(persisted.elapsed));
    });
  });
}
