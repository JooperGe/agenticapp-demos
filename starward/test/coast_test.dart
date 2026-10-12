import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/vec3.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/models/player_state.dart';
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

void main() {
  group('PlayerState drift fields', () {
    test('default to a parked ship and survive a JSON round trip', () {
      final s = PlayerState.deepSpaceStart(
        energy: 300,
        startCoordX: 0,
        startCoordY: 0,
        startX: 1,
        startY: 2,
        startZ: 3,
        createdAt: DateTime(2026),
      );
      expect(s.driftVelocity.length, 0);
      expect(s.driftStartedAt.millisecondsSinceEpoch, 0);

      final moved = s.copyWith(
        driftVelocity: const Vec3(0, 0.5, 0),
        driftStartedAt: DateTime(2026, 5, 1),
      );
      final back = PlayerState.fromJson(moved.toJson());
      expect(back.driftVelocity.y, 0.5);
      expect(back.driftStartedAt, DateTime(2026, 5, 1));
    });

    test('an old save with no drift keys loads as parked', () {
      final json = PlayerState.deepSpaceStart(
        energy: 300,
        startCoordX: 0,
        startCoordY: 0,
        startX: 1,
        startY: 2,
        startZ: 3,
        createdAt: DateTime(2026),
      ).toJson()
        ..remove('driftVelocityX')
        ..remove('driftVelocityY')
        ..remove('driftVelocityZ')
        ..remove('driftStartedAt');
      final back = PlayerState.fromJson(json);
      expect(back.driftVelocity.length, 0);
      expect(back.driftStartedAt.millisecondsSinceEpoch, 0);
    });
  });

  group('a parked ship does not move', () {
    test('position is stable no matter how much time passes', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final before = c.playerPosition3D;
      clock.advance(const Duration(days: 400));
      final after = c.playerPosition3D;
      expect(after.x, before.x);
      expect(after.y, before.y);
      expect(after.z, before.z);
    });

    test('aborting still parks the ship at the point it reached', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final target = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
      await c.launchJourney(target);
      final journey = c.activeJourney!;
      clock.advance(journey.totalDuration ~/ 2);
      await c.abortJourney();

      expect(c.inDeepSpace, isTrue);
      expect(c.driftVelocity.length, 0,
          reason: 'aborting stops the ship; it does not start a drift');
      final parked = c.playerPosition3D;
      clock.advance(const Duration(days: 10));
      expect(c.playerPosition3D.x, parked.x);
      expect(c.playerPosition3D.y, parked.y);
      expect(c.playerPosition3D.z, parked.z);
    });

    test('launching re-anchors the deep-space origin to where the ship is',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final target = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
      await c.launchJourney(target);
      final journey = c.activeJourney!;
      clock.advance(journey.totalDuration ~/ 2);
      await c.abortJourney();
      final parked = c.playerPosition3D;

      // Fly again from the parked spot, then abort again: the new anchor must
      // be the second parking spot, not the first.
      await c.launchJourney(c.planets.firstWhere((p) => p.id != target.id));
      final second = c.activeJourney!;
      clock.advance(second.totalDuration ~/ 4);
      await c.abortJourney();
      final secondPark = c.playerPosition3D;
      expect((secondPark - parked).length, greaterThan(0.001),
          reason: 'the second abort parks somewhere new');
      expect(c.deepSpaceOrigin3D!.x, closeTo(secondPark.x, 0.001));
    });
  });
}
