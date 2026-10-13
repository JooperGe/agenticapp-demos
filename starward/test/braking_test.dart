import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/models/engine.dart';

void main() {
  group('Engine braking', () {
    test('a full cruise burn costs what flying the braking distance costs', () {
      const e = Engine.standard;
      expect(e.travelSecondsPerLy, 37.5, reason: 'the pinned reference engine');
      expect(e.cruiseSpeedLyPerSec, closeTo(0.0266667, 1e-7));
      expect(e.brakingDistanceLy, 40);
      expect(e.energyCostFor(40), 100, reason: 'the quote this all rests on');
      expect(e.brakingCostFor(e.cruiseSpeedLyPerSec), 100);
    });

    test('half a cruise speed costs half as much', () {
      const e = Engine.standard;
      expect(e.brakingCostFor(e.cruiseSpeedLyPerSec / 2), 50);
    });

    test('a ship at rest is quoted nothing, not the minEnergyCost floor', () {
      const e = Engine.standard;
      expect(e.minEnergyCost, 1,
          reason: 'the floor this guard exists to dodge');
      expect(e.brakingCostFor(0), 0);
      expect(e.brakingCostFor(-0.5), 0);
    });

    test('braking distance survives a JSON round trip', () {
      final back = Engine.fromJson(Engine.standard.toJson());
      expect(back.brakingDistanceLy, 40);
      expect(back.brakingCostFor(back.cruiseSpeedLyPerSec), 100);
    });

    test('an engine saved before braking existed falls back to the standard',
        () {
      final json = Engine.standard.toJson()..remove('brakingDistanceLy');
      expect(json.containsKey('brakingDistanceLy'), isFalse,
          reason: 'precondition: this is what an old save looks like');

      final back = Engine.fromJson(json);
      expect(back.brakingDistanceLy, Engine.standard.brakingDistanceLy);
      expect(back.brakingCostFor(back.cruiseSpeedLyPerSec), 100);
    });
  });
}
