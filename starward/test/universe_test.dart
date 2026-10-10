import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/hyg_catalog.dart';
import 'package:starward/data/universe.dart';

/// Universe generation is deterministic and keyed to real stars. Uses the
/// curated fallback catalogue so no asset bundle is needed.
void main() {
  final stars = HygCatalog.curatedFallback();

  test('planet generation is deterministic per star', () {
    final u1 = Universe(stars);
    final u2 = Universe(stars);
    for (var i = 0; i < stars.count; i++) {
      final a = u1.planetsForStarIndex(i);
      final b = u2.planetsForStarIndex(i);
      expect(a.length, b.length);
      for (var k = 0; k < a.length; k++) {
        expect(a[k].id, b[k].id);
        expect(a[k].type, b[k].type);
        expect(a[k].pos.x, b[k].pos.x);
      }
    }
  });

  test('a planet round-trips through its stable id', () {
    final u = Universe(stars);
    // Find any star that hosts a procedural planet.
    for (var i = 0; i < stars.count; i++) {
      final planets = u.planetsForStarIndex(i);
      if (planets.isEmpty) continue;
      final p = planets.last; // last is procedural (hero, if any, is first)
      final again = u.planetById(p.id);
      expect(again, isNotNull);
      expect(again!.id, p.id);
      expect(again.name, p.name);
      expect(again.pos.x, closeTo(p.pos.x, 1e-6));
      expect(again.pointsOfInterest.length, p.pointsOfInterest.length);
      return;
    }
    fail('no procedural planet found in the curated universe');
  });

  test('randomSpawn lands near a star that has planets', () {
    final u = Universe(stars);
    final rng = math.Random(7);
    for (var trial = 0; trial < 20; trial++) {
      final spawn = u.randomSpawn(rng);
      final near = u.planetsNear(spawn, 60, cap: 50);
      expect(near, isNotEmpty, reason: 'spawn should have planets nearby');
    }
  });

  test('density follows the stars: planet count scales with star count', () {
    final u = Universe(stars);
    var total = 0;
    for (var i = 0; i < stars.count; i++) {
      total += u.planetsForStarIndex(i).length;
    }
    // Average ~0.6 procedural planets per star, plus a few heroes.
    expect(total, greaterThan(0));
    expect(total, lessThan(stars.count * 4));
  });
}
