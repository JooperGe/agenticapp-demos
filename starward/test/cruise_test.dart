import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/models/engine.dart';

void main() {
  group('Engine cruise pricing', () {
    test('power draw is the engine\'s own speed times its own appetite', () {
      // Derived, never stored: a stored copy could drift out of step with the
      // two fields it comes from, and then a cruise and a voyage would disagree
      // about how fast the same tank drains.
      expect(Engine.standard.powerDrawPerSecond, closeTo(1 / 15, 1e-12));
    });

    test('a cruise and a voyage price the same distance identically', () {
      // The invariant the whole energy model hangs on: burning for exactly as
      // long as a leg takes must cost exactly the leg's quote. If this breaks,
      // "cruise to a place" and "fly to a place" become different prices.
      for (final d in <double>[1, 5, 40, 120, 200]) {
        final seconds = Engine.standard.secondsFor(d);
        expect(Engine.standard.burnForSeconds(seconds.toDouble()),
            Engine.standard.energyCostFor(d),
            reason: '$d ly');
      }
    });

    test('secondsForEnergy inverts the burn exactly', () {
      // Exact, not approximate: the exhaustion check compares elapsed seconds
      // against this, and a rounding error here moves the halt point a tick.
      expect(Engine.standard.secondsForEnergy(300), 4500.0);
      expect(Engine.standard.secondsForEnergy(200), 3000.0);
      expect(Engine.standard.secondsForEnergy(40), 600.0);
      expect(Engine.standard.secondsForEnergy(0), 0.0);
    });

    test('a turn is priced on the angle, at the delta-v it costs', () {
      // At speed v a turn of theta changes the velocity vector by
      // 2*v*sin(theta/2). Priced through the same per-light-year scale as any
      // other leg: energyCostFor(40 * 2 sin(theta/2)) == round(200 sin(theta/2)).
      const e = Engine.standard;
      double deg(double d) => d * math.pi / 180;
      expect(e.turnCostFor(0), 0);
      expect(e.turnCostFor(deg(5)), 9);
      expect(e.turnCostFor(deg(10)), 17);
      expect(e.turnCostFor(deg(30)), 52);
      expect(e.turnCostFor(deg(60)), 100);
      expect(e.turnCostFor(deg(90)), 141);
      expect(e.turnCostFor(deg(120)), 173);
      expect(e.turnCostFor(deg(180)), 200);
    });

    test('60 degrees is the crossover: past it, stopping is cheaper', () {
      // Not a coincidence — both quotes are built from `brakingDistanceLy`.
      // Under 60 the turn is the cheap way out; over 60 the ship should brake
      // and re-ignite, which is free. The cockpit says so out loud rather than
      // letting the player overpay in silence.
      const e = Engine.standard;
      final braking = e.brakingCostFor(e.cruiseSpeedLyPerSec);
      expect(braking, 100);
      expect(e.turnCostFor(60 * math.pi / 180), braking);
      expect(e.turnCostFor(30 * math.pi / 180), lessThan(braking));
      expect(e.turnCostFor(120 * math.pi / 180), greaterThan(braking));
    });

    test('an engine saved before activation existed pays the standard fee', () {
      final json = Engine.standard.toJson()..remove('activationCost');
      expect(json.containsKey('activationCost'), isFalse,
          reason: 'precondition: this is what an old save looks like');
      expect(Engine.fromJson(json).activationCost, Engine.standard.activationCost);
    });
  });
}
