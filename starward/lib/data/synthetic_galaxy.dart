import 'dart:math' as math;
import 'dart:typed_data';

import '../core/vec3.dart';
import 'hyg_catalog.dart';

/// Fictional galaxies added to the universe so the zoomed-out view isn't
/// one-sided (the real HYG stars cluster along the Milky Way plane). Each one
/// sits in a *different* direction, so they read as separate islands of stars
/// scattered around the far sky.
///
/// Reuses [HygStars] so the renderer, planet generator and lookups treat them
/// exactly like the real catalogue. Their stars get ids in reserved,
/// non-overlapping ranges so they never clash with real HYG ids or each other.
class SyntheticGalaxy {
  SyntheticGalaxy._();

  /// Reserved id base of the first galaxy — real HYG ids are < ~120000, and
  /// each galaxy gets its own million-wide block, so nothing ever clashes.
  static const int idBase = 10000000;

  /// Every fictional galaxy in the universe. Add an entry to drop in another.
  static List<HygStars> all() => <HygStars>[
        // SG-1: cool blue spiral toward the sparse (+x, -y, +z) octant.
        build(),
        // SG-2: warm/reddish spiral on the opposite, also-sparse side.
        build(
          center: const Vec3(-0.58, 0.66, -0.48).normalized * 3400,
          normal: const Vec3(0.75, 0.35, 0.55).normalized,
          diskRadius: 620,
          count: 6000,
          seed: 909090,
          idBase: 20000000,
          name: '星系 SG-2',
          coreColor: 0xFFFFC29A,
          reddish: true,
        ),
      ];

  /// Builds one galaxy. Defaults describe SG-1; pass overrides for others.
  static HygStars build({
    Vec3? center,
    Vec3? normal,
    double diskRadius = 520,
    double thickness = 42,
    int count = 5200,
    int seed = 424242,
    int idBase = SyntheticGalaxy.idBase,
    String name = '螺旋星系 SG-1',
    int coreColor = 0xFFBFD4FF,
    bool reddish = false,
  }) {
    final rng = math.Random(seed);

    // Default: ~2600 ly toward the (+x, -y, +z) octant the real catalogue
    // leaves sparse — a different azimuth from the Milky Way.
    final c = center ?? (const Vec3(0.6, -0.72, 0.55).normalized * 2600);

    // Disk orientation (normal), tilted differently from the galactic plane.
    final w = (normal ?? const Vec3(0.2, 0.9, -0.3)).normalized;
    var u = w.cross(const Vec3(0, 0, 1));
    if (u.length < 1e-3) u = w.cross(const Vec3(1, 0, 0));
    u = u.normalized;
    final v = w.cross(u).normalized;

    const arms = 2;
    const windings = 2.4;

    // Radial scale length of the exponential disk. Stars are sampled from a
    // density ∝ r·e^(-r/h), so by 0.65 R the disk is down to e^(-3.3) ≈ 4% of
    // its central value and it fades out well before [diskRadius]. The old
    // sampling was uniform *in area* (`pow(u, 0.5)`), which held full density
    // right up to the rim and then stopped dead — every galaxy ended in a hard
    // bright circle with 15% of its stars in the outer tenth of the radius,
    // against 0.9% for the real catalogue.
    final scaleLength = diskRadius / 5;

    // Where the disk's stars go. A little under two thirds ride an arm; the
    // rest fill the space between them, so the arms read as a density wave
    // rather than as a drawing. The scatter is applied *across* the arm as
    // well as along it: an angular jitter on its own leaves the arm a
    // near-zero-width curve, and a curve is what drew the crisp rings.
    const armFraction = 0.62;
    const armAngularSpread = 0.45; // radians, 1σ
    const armRadialSpread = 0.045; // fraction of diskRadius, 1σ

    // A soft core rather than a knot: the old bulge packed 22% of the stars
    // into 18% of the radius, eight times the disk's own surface density.
    const bulgeFraction = 0.14;
    const bulgeRadius = 0.22; // fraction of diskRadius

    // The disk's vertical scatter. `thickness` keeps its historical meaning of
    // roughly the 3σ extent, so the standard deviation is a third of it.
    final scaleHeight = thickness / 3;

    // Magnitudes. The real catalogue's median star is ~8.4 mag and its fifth
    // percentile ~6.1; a galaxy spanning 2.2–7.6 outshone the entire sky and
    // rendered as a glaring ring.
    const bulgeMagnitude = 3.2;
    const diskMagnitude = 5.0;
    const diskMagnitudeSpan = 3.6;

    final xs = <double>[];
    final ys = <double>[];
    final zs = <double>[];
    final mags = <double>[];
    final cols = <int>[];

    for (var i = 0; i < count; i++) {
      final bulge = rng.nextDouble() < bulgeFraction;
      double inPlaneX, inPlaneY, offW, mag;
      int color;
      if (bulge) {
        final r =
            diskRadius * bulgeRadius * math.pow(rng.nextDouble(), 0.6).toDouble();
        final a = rng.nextDouble() * math.pi * 2;
        inPlaneX = r * math.cos(a);
        inPlaneY = r * math.sin(a);
        offW = _gauss(rng, scaleHeight * 1.4);
        mag = bulgeMagnitude + rng.nextDouble() * 2.6;
        color = _warm(rng);
      } else {
        // Exponential disk, sampled as the sum of two exponentials: that sum
        // is distributed exactly as r·e^(-r/h). Resampling past the rim keeps
        // the galaxy inside the radius it advertises, and costs ~4% of draws.
        double rad;
        do {
          rad = -scaleLength *
              (math.log(1 - rng.nextDouble()) +
                  math.log(1 - rng.nextDouble()));
        } while (rad > diskRadius);

        final arm = rng.nextInt(arms);
        final onArm = rng.nextDouble() < armFraction;
        final jitter = _gauss(rng, 1);
        final a = onArm
            ? rad / diskRadius * windings * math.pi * 2 +
                arm * (math.pi * 2 / arms) +
                jitter * armAngularSpread
            : rng.nextDouble() * math.pi * 2;
        // Across the arm as well as along it — this is what gives the arms a
        // width instead of leaving them wires.
        final r = onArm
            ? (rad + _gauss(rng, 1) * diskRadius * armRadialSpread)
                .clamp(0.0, diskRadius)
            : rad;
        inPlaneX = r * math.cos(a);
        inPlaneY = r * math.sin(a);
        offW = _gauss(rng, scaleHeight);
        mag = diskMagnitude +
            rad / diskRadius * diskMagnitudeSpan +
            rng.nextDouble() * 1.2;
        // SG-1 arms are blue; a "reddish" galaxy skews its arms warm/pink. The
        // stars between the arms are older and warm in either galaxy.
        color = onArm && jitter.abs() < 0.8
            ? (reddish ? _pink(rng) : _blue(rng))
            : _warm(rng);
      }
      final pos = c + u * inPlaneX + v * inPlaneY + w * offW;
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

    final named = <String, HygNamed>{
      name: HygNamed(
        id: starId[0],
        name: name,
        position: c,
        magnitude: 1.2,
        color: coreColor,
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

  /// Gaussian noise with standard deviation [sd], from the sum of three
  /// uniforms: cheap, and bounded at ±1.5·sd so no star flies off the disk.
  static double _gauss(math.Random rng, double sd) =>
      (rng.nextDouble() + rng.nextDouble() + rng.nextDouble() - 1.5) / 1.5 * sd;

  static int _blue(math.Random rng) {
    const pool = <int>[0xFFBFD4FF, 0xFFD6E4FF, 0xFFA9C4FF, 0xFFEAF0FF];
    return pool[rng.nextInt(pool.length)];
  }

  static int _pink(math.Random rng) {
    const pool = <int>[0xFFFFB3C1, 0xFFFFC2A0, 0xFFF2A0B5, 0xFFFFD0C0];
    return pool[rng.nextInt(pool.length)];
  }

  static int _warm(math.Random rng) {
    const pool = <int>[0xFFFFD9A0, 0xFFFFC87A, 0xFFF2C879, 0xFFFFE6B5];
    return pool[rng.nextInt(pool.length)];
  }
}
