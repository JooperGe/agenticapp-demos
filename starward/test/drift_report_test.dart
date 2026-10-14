import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/drift.dart';
import 'package:starward/core/vec3.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/models/drift_report.dart';
import 'package:starward/data/models/engine.dart';
import 'package:starward/data/models/journey.dart';
import 'package:starward/data/storage/storage_backend.dart';
import 'package:starward/state/game_controller.dart';
import 'package:starward/ui/journey/drift_report_sheet.dart';

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
  cruiseSpeedLyPerSec: 1 / 37.5,
  brakingDistanceLy: 40,
  minEnergyCost: 1,
  minTravelSeconds: 15,
  activationCost: 5,
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

    test('a halt reports the powered leg and stops the ship', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _boot(clock, storage);
      await c.installEngine(_greedy);
      final target = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
      expect(await c.launchJourney(target, onEmpty: FuelPolicy.halt),
          LaunchResult.success);
      final journey = c.activeJourney!;
      final exhaustAt = c.fuelExhaustTime(journey);

      clock.advance(exhaustAt.difference(clock()) + const Duration(seconds: 1));
      c.tick();

      // A halt is not silence: the powered leg is exactly the news the player
      // needs, so the same fuel-out report fires as for a coast.
      expect(c.isCoasting, isFalse);
      expect(c.driftVelocity.length, 0, reason: 'the ship really stopped');
      final r = c.pendingDriftReport!;
      expect(r.kind, DriftReportKind.fuelOut);
      expect(r.from, journey.departure);
      expect(r.to, exhaustAt);
      expect(r.elapsed, exhaustAt.difference(journey.departure));

      // The parked ship is never told it drifted. Unread, the fuel-out window
      // is restored as-is; once read, a later boot has nothing to rebuild,
      // because a zero-velocity ship cannot produce a drift report.
      clock.advance(const Duration(days: 3));
      final c2 = await _boot(clock, storage);
      expect(c2.pendingDriftReport!.kind, DriftReportKind.fuelOut);
      expect(c2.pendingDriftReport!.from, r.from);
      expect(c2.pendingDriftReport!.to, r.to);

      await c2.acknowledgeDriftReport();
      clock.advance(const Duration(days: 3));
      final c3 = await _boot(clock, storage);
      expect(c3.pendingDriftReport, isNull);
    });
  });

  group('arrival never queues a report', () {
    test('arriving at a star leaves nothing pending', () async {
      final storage = MemoryStorage();
      final clock = FakeClock(DateTime(2026, 1, 1, 12));
      final c1 = await _boot(clock, storage);
      // The nearest planetless star — the cheapest star hop, so the full tank
      // can afford it. Star destinations are journey ids of the form
      // 'star:<hygId>', the same encoding `launchToStar` writes.
      int? star;
      var best = double.infinity;
      for (var i = 0; i < c1.stars.count; i++) {
        final id = c1.stars.starId[i];
        if (c1.universe.planetsAtStar(id).isNotEmpty) continue;
        final d = c1.distanceToStar(id);
        if (d < best) {
          best = d;
          star = id;
        }
      }
      expect(star, isNotNull, reason: 'expected some planetless star');
      expect(await c1.launchToStar(star!), LaunchResult.success);

      // Closed for the whole voyage: the arrival is reconciled on the next
      // boot, which is the one place a stale drift velocity could survive
      // alongside a fresh drift window and fake a report.
      clock.advance(const Duration(hours: 2));
      final c2 = await _boot(clock, storage);
      expect(c2.activeJourney!.status, JourneyStatus.arrived);
      expect(GameController.isStarDestination(c2.activeJourney!.destinationPlanetId),
          isTrue);
      expect(c2.pendingDriftReport, isNull);
    });

    test('arriving at a deep-space coordinate leaves nothing pending',
        () async {
      final storage = MemoryStorage();
      final clock = FakeClock(DateTime(2026, 1, 1, 12));
      final c1 = await _boot(clock, storage);
      // Launch out from the initial deep-space anchor, then turn straight back:
      // a return to open space targets a bare coordinate, not a planet or star.
      final target = c1.planets
          .where((p) => p.id != c1.currentPlanetId)
          .reduce((a, b) => c1.distanceTo(a) <= c1.distanceTo(b) ? a : b);
      expect(await c1.launchJourney(target), LaunchResult.success);
      // A round trip costs about twice the outbound quote; top up so the
      // return leg is affordable from a full-ish tank.
      final session = await c1.startCourse('walk');
      await c1.completeCourse(session.id, c1.energyCostTo(target));
      expect(await c1.returnToOrigin(), LaunchResult.success);
      expect(GameController.isCoordDestination(
              c1.activeJourney!.destinationPlanetId), isTrue);

      clock.advance(const Duration(days: 1));
      final c2 = await _boot(clock, storage);
      expect(c2.activeJourney!.status, JourneyStatus.arrived);
      expect(GameController.isCoordDestination(
              c2.activeJourney!.destinationPlanetId), isTrue);
      expect(c2.pendingDriftReport, isNull);
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

  group('the report sheet', () {
    Future<void> open(WidgetTester tester, DriftReport report) async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock, MemoryStorage());
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showDriftReportSheet(
                context,
                controller: c,
                report: report,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('a fuel-out report says how far it got', (tester) async {
      await open(
        tester,
        DriftReport(
          kind: DriftReportKind.fuelOut,
          from: DateTime(2026, 3, 1, 9),
          to: DateTime(2026, 3, 1, 11, 30),
          elapsed: const Duration(hours: 2, minutes: 30),
          distanceLy: 12.5,
          fromPos: const Vec3(0, 0, 0),
          toPos: const Vec3(12.5, 0, 0),
          passedCount: 0,
          nearest: const <PassedSystem>[],
          hitBoundary: false,
        ),
      );
      expect(find.text('燃料耗尽'), findsOneWidget);
      expect(find.textContaining('12.5 ly'), findsOneWidget);
      expect(find.textContaining('2 小时 30 分'), findsOneWidget);
      // An empty stretch of space is a legitimate outcome, and the copy has to
      // say so rather than showing an empty list.
      expect(find.textContaining('空旷的星际空间'), findsOneWidget);
    });

    testWidgets('a drift report names what it went past', (tester) async {
      await open(
        tester,
        DriftReport(
          kind: DriftReportKind.drift,
          from: DateTime(2026, 3, 1),
          to: DateTime(2026, 3, 3),
          elapsed: const Duration(days: 2),
          distanceLy: 4608,
          fromPos: const Vec3(0, 0, 0),
          toPos: const Vec3(4608, 0, 0),
          passedCount: 137,
          nearest: const <PassedSystem>[
            PassedSystem(hygId: 1001, distanceLy: 0.4, seconds: 10),
            PassedSystem(hygId: 1000, distanceLy: 3.1, seconds: 50),
          ],
          hitBoundary: true,
        ),
      );
      expect(find.text('滑行播报'), findsOneWidget);
      expect(find.textContaining('4608.0 ly'), findsOneWidget);
      expect(find.textContaining('2 天 0 小时'), findsOneWidget);
      expect(find.textContaining('途经 137 个恒星系'), findsOneWidget);
      expect(find.textContaining('0.4 ly'), findsOneWidget);
      expect(find.textContaining('3.1 ly'), findsOneWidget);
      expect(find.textContaining('贴着宇宙边界'), findsOneWidget);
    });

    testWidgets('dismissing it does not throw', (tester) async {
      await open(
        tester,
        DriftReport(
          kind: DriftReportKind.drift,
          from: DateTime(2026, 3, 1),
          to: DateTime(2026, 3, 1, 1),
          elapsed: const Duration(hours: 1),
          distanceLy: 100,
          fromPos: const Vec3(0, 0, 0),
          toPos: const Vec3(100, 0, 0),
          passedCount: 0,
          nearest: const <PassedSystem>[],
          hitBoundary: false,
        ),
      );
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(find.text('知道了'), findsNothing);
    });
  });
}
