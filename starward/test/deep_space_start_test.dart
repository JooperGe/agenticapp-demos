import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/storage/storage_backend.dart';
import 'package:starward/data/universe.dart';
import 'package:starward/state/game_controller.dart';

class FakeClock {
  FakeClock(this._now);
  DateTime _now;
  DateTime call() => _now;
  void advance(Duration d) => _now = _now.add(d);
}

Future<GameController> _boot(
  FakeClock clock, {
  MemoryStorage? storage,
  int seed = 1,
}) async {
  final c = GameController(
    repository: GameRepository(storage ?? MemoryStorage()),
    clock: clock.call,
    random: math.Random(seed),
  );
  await c.init();
  return c;
}

void main() {
  test('a fresh save starts drifting in deep space, not on a planet', () async {
    final c = await _boot(FakeClock(DateTime(2026)));
    expect(c.inDeepSpace, isTrue);
    expect(c.currentPlanet, isNull);
    expect(c.currentPlanetId, isNull);
    expect(c.deepSpaceOrigin3D, isNotNull);
    // Nothing is discovered yet — the player hasn't reached anywhere.
    expect(c.discoveredCount, 0);
  });

  test('different installs start at different random coordinates', () async {
    final a = await _boot(FakeClock(DateTime(2026)), seed: 11);
    final b = await _boot(FakeClock(DateTime(2026)), seed: 999);
    final pa = a.deepSpaceOrigin3D!;
    final pb = b.deepSpaceOrigin3D!;
    final differs = pa.x != pb.x || pa.y != pb.y || pa.z != pb.z;
    expect(differs, isTrue);
  });

  test('the random start is stable across a restart', () async {
    final storage = MemoryStorage();
    final c1 = await _boot(FakeClock(DateTime(2026)), storage: storage, seed: 5);
    final before = c1.deepSpaceOrigin3D!;
    final c2 = await _boot(FakeClock(DateTime(2026)), storage: storage, seed: 7);
    final after = c2.deepSpaceOrigin3D!;
    // Seed differs, but the persisted save wins → same coordinate.
    expect(after.x, before.x);
    expect(after.y, before.y);
    expect(after.z, before.z);
  });

  test('arriving at the first planet leaves deep space', () async {
    final clock = FakeClock(DateTime(2026));
    final c = await _boot(clock, seed: 3);
    final target = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
    await c.launchJourney(target);
    clock.advance(const Duration(hours: 2));
    c.tick();
    expect(c.inDeepSpace, isFalse);
    expect(c.currentPlanet, isNotNull);
    expect(c.currentPlanet!.id, target.id);
  });

  test('the solar-system spawn strategy lands inside the Solar System', () async {
    final c = GameController(
      repository: GameRepository(MemoryStorage()),
      clock: FakeClock(DateTime(2026)).call,
      random: math.Random(4),
      spawn: SpawnStrategies.solarSystem,
    );
    await c.init();
    final p = c.deepSpaceOrigin3D!;
    // Within ~1 ly of the Sun (origin) — i.e. within the Solar System scale.
    final distFromSun = p.length;
    expect(distFromSun, lessThan(1.5));
  });

  test('the random-galaxy strategy can land in a far galaxy, always playable',
      () async {
    var sawFar = false;
    for (var seed = 0; seed < 16; seed++) {
      final c = GameController(
        repository: GameRepository(MemoryStorage()),
        clock: FakeClock(DateTime(2026)).call,
        random: math.Random(seed),
        spawn: SpawnStrategies.randomGalaxy,
      );
      await c.init();
      final d = c.deepSpaceOrigin3D!.length;
      if (d > 2000) sawFar = true; // landed in SG-1/SG-2, not the Milky Way
      // Wherever it lands, there must be somewhere to go nearby.
      expect(c.planets, isNotEmpty, reason: 'spawn should have planets nearby');
    }
    expect(sawFar, isTrue, reason: 'some spawns should be in an extra galaxy');
  });
}
