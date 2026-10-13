import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/vec3.dart';
import 'package:starward/data/hyg_catalog.dart';
import 'package:starward/data/synthetic_galaxy.dart';
import 'package:starward/data/universe.dart';
import 'package:starward/ui/galaxy3d/star_field_painter.dart';

/// Distance of every star of [g] from the galaxy's own centroid.
List<double> _radiiAboutCentroid(HygStars g) {
  var cx = 0.0, cy = 0.0, cz = 0.0;
  for (var i = 0; i < g.count; i++) {
    cx += g.xyz[i * 3];
    cy += g.xyz[i * 3 + 1];
    cz += g.xyz[i * 3 + 2];
  }
  cx /= g.count;
  cy /= g.count;
  cz /= g.count;
  final out = <double>[];
  for (var i = 0; i < g.count; i++) {
    final x = g.xyz[i * 3] - cx;
    final y = g.xyz[i * 3 + 1] - cy;
    final z = g.xyz[i * 3 + 2] - cz;
    out.add(math.sqrt(x * x + y * y + z * z));
  }
  return out;
}

/// The added fictional galaxy sits in a different direction from the Milky Way
/// and is fully integrated into the universe (renderable + hosts planets).
void main() {
  test('synthetic galaxy is far, in the +x/-y/+z octant, brightest-first', () {
    final g = SyntheticGalaxy.build();
    expect(g.count, greaterThan(1000));
    // Reserved id range so it never clashes with real HYG ids.
    expect(g.starId[0], greaterThanOrEqualTo(SyntheticGalaxy.idBase));
    // Sorted brightest-first (ascending magnitude).
    expect(g.mag[0], lessThanOrEqualTo(g.mag[g.count - 1]));

    var mx = 0.0, my = 0.0, mz = 0.0;
    for (var i = 0; i < g.count; i++) {
      mx += g.xyz[i * 3];
      my += g.xyz[i * 3 + 1];
      mz += g.xyz[i * 3 + 2];
    }
    final center = Vec3(mx / g.count, my / g.count, mz / g.count);
    // Far away and on the sparse side of the Milky Way (different azimuth).
    expect(center.length, greaterThan(2000));
    expect(center.x > 0 && center.y < 0 && center.z > 0, isTrue);
  });

  test('the galaxy hosts planets and their ids round-trip', () {
    final g = SyntheticGalaxy.build();
    final u = Universe(HygCatalog.curatedFallback(), extraGalaxies: <HygStars>[g]);

    var mx = 0.0, my = 0.0, mz = 0.0;
    for (var i = 0; i < g.count; i++) {
      mx += g.xyz[i * 3];
      my += g.xyz[i * 3 + 1];
      mz += g.xyz[i * 3 + 2];
    }
    final center = Vec3(mx / g.count, my / g.count, mz / g.count);

    final near = u.planetsNear(center, 400, cap: 60);
    expect(near, isNotEmpty, reason: 'galaxy stars should host planets');

    final p = near.first;
    final again = u.planetById(p.id);
    expect(again, isNotNull);
    expect(again!.id, p.id);
    expect(again.pos.x, closeTo(p.pos.x, 1e-6));
  });

  test('multiple galaxies exist in different directions with disjoint ids', () {
    final gs = SyntheticGalaxy.all();
    expect(gs.length, greaterThanOrEqualTo(2));

    // No star-id overlap between galaxies.
    final ids = <int>{};
    for (final g in gs) {
      for (var i = 0; i < g.count; i++) {
        expect(ids.add(g.starId[i]), isTrue, reason: 'duplicate star id');
      }
    }

    Vec3 dir(g) {
      var x = 0.0, y = 0.0, z = 0.0;
      for (var i = 0; i < g.count; i++) {
        x += g.xyz[i * 3];
        y += g.xyz[i * 3 + 1];
        z += g.xyz[i * 3 + 2];
      }
      return Vec3(x / g.count, y / g.count, z / g.count).normalized;
    }

    // Their centres point in clearly different directions (> 60° apart).
    expect(dir(gs[0]).dot(dir(gs[1])), lessThan(0.5));
  });

  test('every galaxy fades toward its rim instead of ending in a hard edge',
      () {
    // Measured against the real catalogue, whose own bounding radius holds
    // 0.9% of its stars in the outer tenth. Sampling uniformly in area — the
    // old `pow(u, 0.5)` — holds *full* density right out to the rim and then
    // stops dead, which is what drew each galaxy as a hard bright circle: 15%
    // of its stars sat in the outer tenth, twice as many as in the middle
    // tenth. A disk that fades has to be on the other side of 1.
    for (final g in SyntheticGalaxy.all()) {
      final radii = _radiiAboutCentroid(g);
      final rim = radii.reduce(math.max);
      var outer = 0, middle = 0;
      for (final d in radii) {
        if (d > 0.9 * rim) outer++;
        if (d > 0.45 * rim && d < 0.55 * rim) middle++;
      }
      expect(outer, lessThan(middle),
          reason: 'the outer tenth of the radius must be emptier than the '
              'middle tenth, or the disk ends in a rim');
      expect(outer / g.count, lessThan(0.06),
          reason: 'a hard rim piles stars against the boundary');
    }
  });

  test('the arms are broad, not wires', () {
    // Built on a plane we chose, so the ring below can name its angle: the
    // normal is +y, which puts the disk in the x/z plane.
    final g = SyntheticGalaxy.build(normal: const Vec3(0, 1, 0), seed: 7);

    var cx = 0.0, cz = 0.0;
    for (var i = 0; i < g.count; i++) {
      cx += g.xyz[i * 3];
      cz += g.xyz[i * 3 + 2];
    }
    cx /= g.count;
    cz /= g.count;

    // A ring 4% of the radius wide at 0.6 R. The old generator scattered every
    // star onto an arm with an angular jitter but *no* radial jitter, so the
    // arm was a near-zero-width curve: this ring came out about a third
    // occupied — two narrow bands with the rest of the circumference empty,
    // which is exactly what read as crisp concentric rings.
    const radius = 520.0;
    final bins = List<int>.filled(36, 0);
    for (var i = 0; i < g.count; i++) {
      final dx = g.xyz[i * 3] - cx;
      final dz = g.xyz[i * 3 + 2] - cz;
      final r = math.sqrt(dx * dx + dz * dz);
      if ((r - 0.6 * radius).abs() >= 0.02 * radius) continue;
      var a = math.atan2(dz, dx);
      if (a < 0) a += 2 * math.pi;
      bins[(a / (2 * math.pi) * 36).floor() % 36]++;
    }
    final occupied = bins.where((b) => b > 0).length;
    expect(occupied, greaterThan(24),
        reason: 'the arms must fill most of a thin ring, not draw two wires');
  });

  test('the draw cap does not truncate a galaxy', () {
    // Both painters draw a galaxy whole, because stars are sorted
    // brightest-first and a galaxy's magnitude rises with radius: the stars a
    // cap drops are the faint outer disk, whose fade is the whole reason the
    // galaxy does not end in a hard edge. See [kGalaxyMaxDraw].
    for (final g in SyntheticGalaxy.all()) {
      expect(g.count, lessThanOrEqualTo(kGalaxyMaxDraw),
          reason: 'raise kGalaxyMaxDraw, or the galaxy renders without its rim');
    }
  });
}
