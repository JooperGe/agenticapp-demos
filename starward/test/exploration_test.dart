import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/balance.dart';
import 'package:starward/data/game_repository.dart';
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
  );
  await c.init();
  return c;
}

/// Travels to and arrives at [target] so it can be explored.
Future<void> _travelTo(GameController c, FakeClock clock, Planet target) async {
  await c.launchJourney(target);
  clock.advance(const Duration(hours: 2));
  c.tick();
}

void main() {
  group('exploration state is persistent and de-duplicated', () {
    test('recording the same POI twice does not duplicate the log', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final planet = c.planets.firstWhere((p) => p.pointsOfInterest.isNotEmpty);
      await _travelTo(c, clock, planet);

      final poi = planet.pointsOfInterest.first;
      await c.recordDiscovery(planet, poi);
      await c.recordDiscovery(planet, poi);

      expect(c.discoveriesFor(planet.id).length, 1);
      expect(c.foundPoiIds(planet.id), contains(poi.id));
    });

    test('completing exploration marks explored and grants reward once',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final planet = c.planets.firstWhere((p) => p.pointsOfInterest.isNotEmpty);
      await _travelTo(c, clock, planet);
      final energyBefore = c.energy;

      final first = await c.completeExploration(planet);
      expect(first, isTrue);
      expect(c.stateOf(planet.id), DiscoveryState.explored);
      expect(c.energy, energyBefore + Balance.explorationReward);
      // The arrival journey is cleared, freeing the ship.
      expect(c.activeJourney, isNull);

      final second = await c.completeExploration(planet);
      expect(second, isFalse);
      expect(c.energy, energyBefore + Balance.explorationReward); // once only
    });

    test('explored state survives a restart', () async {
      final storage = MemoryStorage();
      final clock = FakeClock(DateTime(2026));
      final c1 = await _boot(clock, storage: storage);
      final planet =
          c1.planets.firstWhere((p) => p.pointsOfInterest.isNotEmpty);
      await _travelTo(c1, clock, planet);
      await c1.recordDiscovery(planet, planet.pointsOfInterest.first);
      await c1.completeExploration(planet);

      final c2 = await _boot(clock, storage: storage);
      expect(c2.stateOf(planet.id), DiscoveryState.explored);
      expect(c2.discoveriesFor(planet.id), isNotEmpty);
    });
  });
}
