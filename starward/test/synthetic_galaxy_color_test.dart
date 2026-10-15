import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/hyg_catalog.dart';
import 'package:starward/data/synthetic_galaxy.dart';
import 'package:starward/ui/galaxy3d/star_field_painter.dart';

/// Colour behaviour of the two fictional galaxies.
///
/// These are the regression metrics for "SG-1 and SG-2 render as a single
/// colour". Everything is weighted by the renderer's own
/// [StarFieldStyle.galaxy] ramp, so the numbers describe what gets *drawn*
/// rather than what is stored.
void main() {
  final galaxies = SyntheticGalaxy.all();

  /// Packed ARGB stored in an `Int32List` is sign-extended — `0xFFBFD4FF` comes
  /// back as -4205313 — so a positive hex literal never matches it.
  int unsigned(int packed) => packed & 0xFFFFFFFF;
  bool inPool(int packed, List<int> pool) => pool.contains(unsigned(packed));

  double light(double mag) {
    final a = StarFieldStyle.galaxy.alphaFor(mag);
    final r = StarFieldStyle.galaxy.radiusFor(mag);
    return a * r * r;
  }

  /// Light-weighted hue concentration: the length of the mean unit vector over
  /// the light's hues, so 1.0 means every photon carries the same hue and 0.0
  /// means they cancel out. `1 - R` is the "is this more than one colour"
  /// number. A mean RGB would not do — a blue/warm mix averages toward grey,
  /// which reads as *less* colour the better the mix.
  double hueVariety(HygStars g) {
    var vx = 0.0, vy = 0.0, total = 0.0;
    for (var i = 0; i < g.count; i++) {
      final w = light(g.mag[i]);
      final hue =
          HSVColor.fromColor(Color(unsigned(g.color[i]))).hue * math.pi / 180.0;
      vx += w * math.cos(hue);
      vy += w * math.sin(hue);
      total += w;
    }
    return 1 - math.sqrt(vx * vx + vy * vy) / total;
  }

  /// Share of the drawn light carried by the young (arm) family — the arms and
  /// the star-forming knots — against the old (bulge + inter-arm) family.
  double youngLightShare(HygStars g) {
    var young = 0.0, total = 0.0;
    for (var i = 0; i < g.count; i++) {
      final w = light(g.mag[i]);
      total += w;
      final c = g.color[i];
      if (!inPool(c, SyntheticGalaxy.warmPool)) young += w;
    }
    return young / total;
  }

  /// Mean distance from each sampled member to its nearest same-family
  /// neighbour. The stride keeps the O(n²) pass cheap by capping the sample at
  /// ~600 points; it lengthens both families' distances alike, so the ratio
  /// between them still separates "clumped" from "spread along an arm".
  double meanNearestNeighbour(HygStars g, List<int> idx) {
    final stride = idx.length <= 600 ? 1 : (idx.length / 600).ceil();
    final pts = Float64List((idx.length / stride).ceil() * 3);
    var n = 0;
    for (var k = 0; k < idx.length; k += stride) {
      final i = idx[k];
      pts[n * 3] = g.xyz[i * 3];
      pts[n * 3 + 1] = g.xyz[i * 3 + 1];
      pts[n * 3 + 2] = g.xyz[i * 3 + 2];
      n++;
    }
    var total = 0.0;
    for (var a = 0; a < n; a++) {
      var best = double.infinity;
      for (var b = 0; b < n; b++) {
        if (a == b) continue;
        final dx = pts[a * 3] - pts[b * 3];
        final dy = pts[a * 3 + 1] - pts[b * 3 + 1];
        final dz = pts[a * 3 + 2] - pts[b * 3 + 2];
        final d2 = dx * dx + dy * dy + dz * dz;
        if (d2 < best) best = d2;
      }
      total += math.sqrt(best);
    }
    return total / n;
  }

  List<int> indicesWhere(HygStars g, bool Function(int) test) {
    final out = <int>[];
    for (var i = 0; i < g.count; i++) {
      if (test(g.color[i])) out.add(i);
    }
    return out;
  }

  group('star-forming knots', () {
    test('the knot palette is used, and only for a minority of the disk', () {
      for (final g in galaxies) {
        final knots =
            indicesWhere(g, (c) => inPool(c, SyntheticGalaxy.knotPool));
        expect(knots, isNotEmpty,
            reason: 'the knot pool must actually be drawn somewhere');
        expect(knots.length / g.count, lessThan(0.2),
            reason: 'knots are star-forming regions, not the whole disk');
      }
    });

    test('knot stars are clumped, not sprinkled through the disk', () {
      for (final g in galaxies) {
        final knots =
            indicesWhere(g, (c) => inPool(c, SyntheticGalaxy.knotPool));
        expect(knots, isNotEmpty,
            reason: 'with no knots this test would pass on an empty sample');

        // A size-matched random sample of the same galaxy — what the knot pool
        // would look like if it were handed out by chance rather than to the
        // knots. Its spacing is the "sprinkled" baseline, so the ratio between
        // the two is what separates a real clump from a scatter. Note this
        // cannot ask for a large margin: membership is geometric, so a knot's
        // internal spacing is the arm ridge's own density and no tighter. What
        // the threshold catches is a knot pool applied to the wrong stars.
        final rng = math.Random(7);
        final scattered = <int>[
          for (var k = 0; k < knots.length; k++) rng.nextInt(g.count),
        ];
        final knotNN = meanNearestNeighbour(g, knots);
        final baseNN = meanNearestNeighbour(g, scattered);
        expect(knotNN, lessThan(baseNN * 0.6),
            reason: 'knot stars must sit closer together than a random draw of '
                'the same size (knot $knotNN vs scattered $baseNN)');
      }
    });

    test('knots stay well inside the disk, so the rim still fades', () {
      for (final g in galaxies) {
        final knots =
            indicesWhere(g, (c) => inPool(c, SyntheticGalaxy.knotPool));
        expect(knots, isNotEmpty,
            reason: 'with no knots this test would pass vacuously');
        // Radii about the galaxy's own centroid, as the rim-fade test measures.
        var cx = 0.0, cy = 0.0, cz = 0.0;
        for (var i = 0; i < g.count; i++) {
          cx += g.xyz[i * 3];
          cy += g.xyz[i * 3 + 1];
          cz += g.xyz[i * 3 + 2];
        }
        cx /= g.count;
        cy /= g.count;
        cz /= g.count;
        var rim = 0.0;
        for (var i = 0; i < g.count; i++) {
          final dx = g.xyz[i * 3] - cx;
          final dy = g.xyz[i * 3 + 1] - cy;
          final dz = g.xyz[i * 3 + 2] - cz;
          final d = math.sqrt(dx * dx + dy * dy + dz * dz);
          if (d > rim) rim = d;
        }
        for (final i in knots) {
          final dx = g.xyz[i * 3] - cx;
          final dy = g.xyz[i * 3 + 1] - cy;
          final dz = g.xyz[i * 3 + 2] - cz;
          expect(math.sqrt(dx * dx + dy * dy + dz * dz), lessThan(0.85 * rim));
        }
      }
    });
  });

  group('the knots moved no star', () {
    // The save-safety guard, and the reason ⑤ is colour-only. A saved
    // destination is `star:<hygId>` or `p1-<hygId>-<k>`, where the id is
    // `idBase + dst` and `dst` is the star's rank in the brightest-first sort.
    // Anything that changes a magnitude, or the number of draws the main stream
    // consumes, shifts that ranking and silently repoints every save naming a
    // star past the first change. `coast_test.dart`'s universeRadius ±30 cannot
    // see that: the star set is identical, only the ids move.
    //
    // Measured *before* the knots were added, and required to stay
    // bit-identical — that equality is the whole proof, so these are pinned to
    // full precision rather than to a loose tolerance. The index-weighted sums
    // are the renumbering guard proper: a permutation barely moves the plain
    // sums but shifts these by thousands.
    //
    // Order: idBase, Σx, Σy, Σz, Σ(i+1)x, Σ(i+1)y, Σ(i+1)z, mag[0],
    // mag[last], xyz[0..2] of the brightest star.
    const expected = <String, List<double>>{
      '螺旋星系 SG-1': <double>[
        10000000,
        7448026.01574707, -8953027.348510742, 6846215.888427734,
        19340798718.139282, -23271269719.928223, 17816134537.130554,
        3.208378314971924, 9.571829795837402,
        1425.8907470703125, -1718.6943359375, 1334.861083984375,
      ],
      '星系 SG-2': <double>[
        20000000,
        -11827410.213012695, 13457104.87109375, -9773106.85925293,
        -35506892321.21887, 40377724990.761475, -29298562279.92737,
        3.202848196029663, 9.716059684753418,
        -1914.704833984375, 2226.520751953125, -1694.420166015625,
      ],
    };

    for (final g in galaxies) {
      final name = g.named.keys.first;
      final last = g.count - 1;
      final e = expected[name]!;

      test('$name: positions and magnitudes are unmoved', () {
        var sx = 0.0, sy = 0.0, sz = 0.0;
        var wx = 0.0, wy = 0.0, wz = 0.0;
        for (var i = 0; i < g.count; i++) {
          final x = g.xyz[i * 3], y = g.xyz[i * 3 + 1], z = g.xyz[i * 3 + 2];
          sx += x;
          sy += y;
          sz += z;
          wx += (i + 1) * x;
          wy += (i + 1) * y;
          wz += (i + 1) * z;
        }
        expect(sx, closeTo(e[1], 1.0));
        expect(sy, closeTo(e[2], 1.0));
        expect(sz, closeTo(e[3], 1.0));
        expect(wx, closeTo(e[4], 100.0));
        expect(wy, closeTo(e[5], 100.0));
        expect(wz, closeTo(e[6], 100.0));
        expect(g.mag[0], closeTo(e[7], 1e-6));
        expect(g.mag[last], closeTo(e[8], 1e-6));
      });

      test('$name: the ids a save names still point at the same stars', () {
        // The brightest star is the one `named` publishes, so it is the id most
        // likely to be in a save; the faintest is the far end of the ranking.
        expect(g.starId[0], e[0]);
        expect(g.starId[last], e[0] + last);
        expect(g.xyz[0], closeTo(e[9], 1e-3));
        expect(g.xyz[1], closeTo(e[10], 1e-3));
        expect(g.xyz[2], closeTo(e[11], 1e-3));
      });
    }
  });

  group('the light is more than one hue', () {
    test('the arms are no longer outvoted by the warm bulge', () {
      // Share of the drawn light carried by the young family (arms + knots).
      // SG-1 measured 40.4% under the old ramp and 49.6% now. The bulge is 14%
      // of the stars but 1.8–2.8 mag brighter, so under the old ramp it took
      // most of the light and the blue arms went unseen even though 53% of the
      // stars are blue. This is the metric that says the balance moved.
      for (final g in galaxies) {
        expect(youngLightShare(g), greaterThan(0.45));
      }
    });

    test('SG-2 is not a single warm band any more', () {
      // 0.063 before the knots, 0.233 after. SG-2's arms are pink (hue ≈ 350°)
      // and its field is warm (≈ 40°), so every colour it had sat inside a 50°
      // band — the most literal form of the reported problem. The knots are the
      // only thing that can fix it: no magnitude ramp can, because the palette
      // bounds which hues exist at all. The threshold sits at 2.4× the old
      // value, well out of reach of any ramp.
      final sg2 = galaxies.last;
      expect(hueVariety(sg2), greaterThan(0.15));
    });

    test('SG-1 keeps a real spread of hue', () {
      // 0.806 on the old ramp, 0.951 from the ramp alone, 0.975 with the knots.
      expect(hueVariety(galaxies.first), greaterThan(0.85));
    });
  });
}
