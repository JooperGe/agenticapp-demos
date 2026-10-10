import 'dart:math' as math;
import 'dart:typed_data';

import '../core/vec3.dart';
import 'hyg_catalog.dart';

/// A fictional spiral galaxy added to the universe so the zoomed-out view isn't
/// one-sided (the real HYG stars cluster along the Milky Way plane). It sits in
/// a *different* direction from that plane — toward a sparse octant — so it
/// reads as a clearly separate island of stars on the far side of the sky.
///
/// Reuses [HygStars] so the renderer, planet generator and lookups treat it
/// exactly like the real catalogue. Its stars get ids in a reserved range so
/// they never collide with real HYG ids.
class SyntheticGalaxy {
  SyntheticGalaxy._();

  /// Reserved id base — real HYG ids are < ~120000, so these never clash.
  static const int idBase = 10000000;

  /// Builds the galaxy. Deterministic (fixed seed) so it's identical on every
  /// launch, like everything else in the universe.
  static HygStars build() {
    final rng = math.Random(424242);

    // Centre: ~2600 ly away toward the (+x, -y, +z) octant, which the real
    // catalogue leaves sparse — i.e. a different azimuth from the Milky Way.
    final center = Vec3(0.6, -0.72, 0.55).normalized * 2600;

    // Disk orientation (normal), tilted differently from the galactic plane.
    final w = const Vec3(0.2, 0.9, -0.3).normalized;
    var u = w.cross(const Vec3(0, 0, 1));
    if (u.length < 1e-3) u = w.cross(const Vec3(1, 0, 0));
    u = u.normalized;
    final v = w.cross(u).normalized;

    const diskRadius = 520.0; // ly
    const thickness = 42.0; // ly (half)
    const arms = 2;
    const windings = 2.4;
    const count = 5200;

    final xs = <double>[];
    final ys = <double>[];
    final zs = <double>[];
    final mags = <double>[];
    final cols = <int>[];

    for (var i = 0; i < count; i++) {
      final bulge = rng.nextDouble() < 0.22;
      double inPlaneX, inPlaneY, offW, mag;
      int color;
      if (bulge) {
        // Dense, rounder, yellow core.
        final r = diskRadius * 0.18 * math.pow(rng.nextDouble(), 0.6);
        final a = rng.nextDouble() * math.pi * 2;
        inPlaneX = r * math.cos(a);
        inPlaneY = r * math.sin(a);
        offW = _gauss(rng) * thickness * 1.4;
        mag = 1.6 + rng.nextDouble() * 3.0;
        color = _warm(rng);
      } else {
        // Disk + two logarithmic spiral arms.
        final rad = diskRadius * math.pow(rng.nextDouble(), 0.5).toDouble();
        final arm = rng.nextInt(arms);
        final spiral = rad / diskRadius * windings * math.pi * 2 +
            arm * (math.pi * 2 / arms);
        final jitter = _gauss(rng) * 0.35;
        final a = spiral + jitter;
        inPlaneX = rad * math.cos(a);
        inPlaneY = rad * math.sin(a);
        offW = _gauss(rng) * thickness;
        // Brighter toward the centre; arms skew blue, inter-arm dimmer/redder.
        final armness = math.cos(jitter * 3).abs();
        mag = 2.2 + rad / diskRadius * 4.2 + rng.nextDouble() * 1.2;
        color = armness > 0.5 ? _blue(rng) : _warm(rng);
      }
      final pos = center + u * inPlaneX + v * inPlaneY + w * offW;
      xs.add(pos.x);
      ys.add(pos.y);
      zs.add(pos.z);
      mags.add(mag);
      cols.add(color);
    }

    // Sort brightest-first so the renderer's draw cap keeps the brightest.
    final order = List<int>.generate(count, (i) => i)
      ..sort((a, b) => mags[a].compareTo(mags[b]));

    final starId = Int32List(count);
    final xyz = Float32List(count * 3);
    final mag = Float32List(count);
    final color = Int32List(count);
    final indexById = <int, int>{};
    for (var dst = 0; dst < count; dst++) {
      final src = order[dst];
      final id = idBase + dst;
      starId[dst] = id;
      indexById[id] = dst;
      xyz[dst * 3] = xs[src];
      xyz[dst * 3 + 1] = ys[src];
      xyz[dst * 3 + 2] = zs[src];
      mag[dst] = mags[src];
      color[dst] = cols[src];
    }

    // A bright, labelled anchor at the galaxy's core.
    final named = <String, HygNamed>{
      '螺旋星系 SG-1': HygNamed(
        id: starId[0],
        name: '螺旋星系 SG-1',
        position: center,
        magnitude: 1.2,
        color: 0xFFBFD4FF,
      ),
    };

    return HygStars(
      count: count,
      starId: starId,
      xyz: xyz,
      mag: mag,
      color: color,
      named: named,
      indexById: indexById,
    );
  }

  static double _gauss(math.Random rng) =>
      (rng.nextDouble() + rng.nextDouble() + rng.nextDouble() - 1.5) / 1.5;

  static int _blue(math.Random rng) {
    const pool = <int>[0xFFBFD4FF, 0xFFD6E4FF, 0xFFA9C4FF, 0xFFEAF0FF];
    return pool[rng.nextInt(pool.length)];
  }

  static int _warm(math.Random rng) {
    const pool = <int>[0xFFFFD9A0, 0xFFFFC87A, 0xFFF2C879, 0xFFFFE6B5];
    return pool[rng.nextInt(pool.length)];
  }
}
