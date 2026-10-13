import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/vec3.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/hyg_catalog.dart';
import 'package:starward/data/models/player_state.dart';
import 'package:starward/data/storage/storage_backend.dart';
import 'package:starward/data/synthetic_galaxy.dart';
import 'package:starward/data/universe.dart';
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

/// Rewrites the saved drift so the ship is coasting from a known anchor.
Future<void> _setDrift(
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

  group('Universe.universeRadius', () {
    // The real catalogue is a bundled asset; loading it needs the binding.
    setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

    test('pins the catalogue bounding radius', () async {
      final hyg = await HygCatalog.load();
      expect(hyg, isNotNull);
      final u = Universe(hyg!, extraGalaxies: SyntheticGalaxy.all());
      // The farthest star in HYG + SG-1 + SG-2, measured 2026-10-13.
      // If this drifts, the star catalogue or the galaxy generator changed —
      // and the shell is no longer the sphere the overview draws.
      expect(u.universeRadius, closeTo(3948.5, 30));
    });

    test('the shell holds every star in the catalogue', () async {
      final hyg = await HygCatalog.load();
      final u = Universe(hyg!, extraGalaxies: SyntheticGalaxy.all());
      final r = u.universeRadius;

      // The contract the universe-overview camera draws: the glass sphere is
      // the catalogue's bounding sphere, so nothing — SG-2 included — hangs
      // outside it. This replaced "the shell is somewhere with stars to reach"
      // on 2026-10-13; the trade that was accepted is written up on
      // `universeRadius`. Both halves are needed: containment alone would pass
      // if the radius were simply made enormous.
      var farthest = 0.0;
      void scan(List<double> xyz, int count) {
        for (var i = 0; i < count; i++) {
          final x = xyz[i * 3], y = xyz[i * 3 + 1], z = xyz[i * 3 + 2];
          final d = math.sqrt(x * x + y * y + z * z);
          if (d > farthest) farthest = d;
        }
      }

      scan(u.stars.xyz, u.stars.count);
      for (final g in u.extraGalaxies) {
        scan(g.xyz, g.count);
      }
      expect(farthest, lessThanOrEqualTo(r),
          reason: 'no star may sit outside the drawn shell');
      expect(r, closeTo(farthest, 0.001),
          reason: 'the shell is tight — it touches the farthest star');
    });

    test('nearestPlanets finds somewhere to go from the middle of nowhere',
        () async {
      final hyg = await HygCatalog.load();
      final u = Universe(hyg!, extraGalaxies: SyntheticGalaxy.all());
      final nowhere = Vec3(50000, 0, 0);
      final found = u.nearestPlanets(nowhere);
      expect(found, isNotEmpty,
          reason: 'a ship stranded outside the shell must still have a target');
      expect(found.length, greaterThanOrEqualTo(10));
      // Pinned against the real catalogue: the star nearest to (50000,0,0) sits
      // at (3187.739, 119.741, -220.695), 46812.935 ly away — but it hosts no
      // planets (`planetCountForStar(116717) == 0`), so the nearest planet
      // orbits the nearest planet-hosting star, SW-115954 at
      // (3000.653, -22.332, -340.268), 47000.584 ly away. A generated planet
      // orbits within 2.6 ly of its star (`_spherePoint(rng, 0.6, 2.6)`),
      // landing 47002.796 ly from the probe. So a nearest-first full-catalogue
      // scan must land in this window. If the fallback only looked at the shell
      // or the curated list, it would miss.
      expect((found.first.pos - nowhere).length, closeTo(47002.8, 5));
      expect(found.first.pos.length, closeTo(3017.7, 5),
          reason: 'the nearest planet orbits a star near the outer shell');
    });
  });

  group('_rebuildNearby under drift', () {
    test('the nearby set is left alone until the ship has moved 20 ly',
        () async {
      final start = DateTime(2026, 1, 1);
      final clock = FakeClock(start);
      final storage = MemoryStorage();
      await _boot(clock, storage: storage);
      // 1 ly/s heading +X, anchored at the Solar-System spawn.
      await _setDrift(storage, const Vec3(1, 0, 0), start);
      final c = await _boot(clock, storage: storage);

      final before = c.planets;
      clock.advance(const Duration(seconds: 10)); // 10 ly — under the threshold
      c.tick();
      expect(identical(c.planets, before), isTrue,
          reason: 'a 10 ly nudge must not trigger a 120k-star rescan');

      clock.advance(const Duration(seconds: 15)); // 25 ly — over it
      c.tick();
      expect(identical(c.planets, before), isFalse);
    });

    test('a ship stranded far outside the shell still has destinations',
        () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      await _boot(clock, storage: storage);
      // 50,000 ly out: nothing within the 960 ly the radius search reaches.
      final raw = await storage.read('starward.save.v2');
      final json = jsonDecode(raw!) as Map<String, dynamic>;
      final player = json['player'] as Map<String, dynamic>;
      player['startX'] = 50000.0;
      player['startY'] = 0.0;
      player['startZ'] = 0.0;
      await storage.write('starward.save.v2', jsonEncode(json));

      final c = await _boot(clock, storage: storage);
      expect(c.planets, isNotEmpty,
          reason: 'no soft-lock: there is always somewhere to fly');
      // And they are the genuinely nearest ones, ~46,000 ly away.
      expect(c.planets.first.pos.length, lessThan(50000));
    });
  });

  group('the coasting readout', () {
    test('measures from the moment the tank emptied', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _boot(clock, storage: storage);
      expect(c.isCoasting, isFalse);
      expect(c.driftElapsed, Duration.zero);
      expect(c.driftDistanceLy, 0);

      await _setDrift(storage, const Vec3(1, 0, 0), clock());
      final c2 = await _boot(clock, storage: storage);
      expect(c2.isCoasting, isTrue);
      expect(c2.driftElapsed, Duration.zero);

      clock.advance(const Duration(hours: 1));
      expect(c2.driftElapsed, const Duration(hours: 1));
      expect(c2.driftDistanceLy, closeTo(3600, 1e-9),
          reason: '1 ly/s for an hour');
    });
  });
}
