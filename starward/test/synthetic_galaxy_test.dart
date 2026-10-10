import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/vec3.dart';
import 'package:starward/data/hyg_catalog.dart';
import 'package:starward/data/synthetic_galaxy.dart';
import 'package:starward/data/universe.dart';

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
}
