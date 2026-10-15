import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/hyg_catalog.dart';
import 'package:starward/ui/galaxy3d/camera3d.dart';
import 'package:starward/ui/galaxy3d/star_field_painter.dart';

/// The magnitude → pixel ramp decides how much light each star contributes, and
/// therefore which colour a field reads as. It used to be two inline
/// expressions in the hot loop, tuned for the real catalogue but applied to
/// every field alike.
///
/// These tests hold the two styles apart. `catalogue` must reproduce the old
/// inline numbers *exactly* — the Milky Way is not part of this change — while
/// `galaxy` must **compress** the ramp's dynamic range rather than merely
/// brighten it, because a galaxy whose brightest star carries ten times the
/// light of its faintest reads as a single colour.
void main() {
  // The expressions this style replaced, written out as literals:
  //   alpha  = ((6.6 - m) / 8 + 0.12).clamp(0.05, 1.0)
  //   radius = (0.5 + (3.0 - m) * 0.33).clamp(0.5, 2.6)
  const catalogue = StarFieldStyle.catalogue;
  const galaxy = StarFieldStyle.galaxy;

  // A galaxy's stars span the bulge at m = 3.2 to the outer disk at m = 9.8.
  const brightest = 3.2;
  const faintest = 9.8;

  group('StarFieldStyle.catalogue reproduces the ramp it replaced', () {
    test('alpha pivots at 0.12 at m = 6.6 and saturates at 1.0', () {
      expect(catalogue.alphaFor(6.6), 0.12);
      expect(catalogue.alphaFor(-2.0), 1.0);
    });

    test('alpha floors at 0.05 past m = 7.16', () {
      expect(catalogue.alphaFor(7.16), 0.05);
      expect(catalogue.alphaFor(9.8), 0.05);
      expect(catalogue.alphaFor(14.0), 0.05);
    });

    test('radius floors at 0.5 for anything fainter than m = 3.0', () {
      expect(catalogue.radiusFor(3.0), 0.5);
      expect(catalogue.radiusFor(9.8), 0.5);
    });

    test('radius grows for bright stars and ceilings at 2.6', () {
      expect(catalogue.radiusFor(0.0), closeTo(1.49, 1e-12));
      expect(catalogue.radiusFor(-4.94), 2.6);
    });

    test('bloom still only fires below m = 1.4', () {
      expect(catalogue.bloomBelow, 1.4);
    });
  });

  group('StarFieldStyle.galaxy lifts the disk off the floor', () {
    test('a faint disk star is no longer pinned to the alpha floor', () {
      expect(catalogue.alphaFor(faintest), 0.05);
      expect(galaxy.alphaFor(faintest),
          greaterThan(catalogue.alphaFor(faintest) * 2));
    });

    test('the dynamic range is compressed, not merely shifted up', () {
      double spread(StarFieldStyle s) =>
          s.alphaFor(brightest) / s.alphaFor(faintest);
      // 0.545 / 0.05 today. Merely adding a constant would keep this ratio,
      // and the bright warm bulge would go on outvoting the blue arms.
      expect(spread(catalogue), closeTo(10.9, 0.1));
      expect(spread(galaxy), lessThan(spread(catalogue) / 3));
    });

    test('galaxy stars are no longer sub-pixel', () {
      expect(catalogue.radiusFor(faintest), 0.5);
      expect(galaxy.radiusFor(faintest), greaterThanOrEqualTo(0.6));
    });
  });

  group('drawStarField applies the style it is handed', () {
    // A single-magnitude field inside the camera's frame. With the catalogue
    // ramp every one of these stars sits on the 0.05 alpha floor at 0.5px;
    // with the galaxy ramp they are brighter and larger, so they must light up
    // strictly more pixels. If the count comes out equal, the parameter was
    // accepted and ignored.
    final field = _uniformField(count: 200, magnitude: 8.0);
    final camera = Camera3D(
      target: const Vec3(0, 0, 0),
      yaw: 0.6,
      pitch: 0.35,
      distance: 2000,
      mode: CameraMode.overview,
    );

    Future<int> litPixels(StarFieldStyle style) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 800, 600));
      drawStarField(
        canvas,
        size: const Size(800, 600),
        field: field,
        camera: camera,
        worldScale: 12,
        maxDraw: 8000,
        distanceScaled: false,
        style: style,
      );
      final image = recorder.endRecording().toImageSync(800, 600);
      final data =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final bytes = data.buffer.asUint8List();
      var n = 0;
      for (var i = 3; i < bytes.length; i += 4) {
        if (bytes[i] > 0) n++;
      }
      image.dispose();
      return n;
    }

    test('the galaxy style lights up more pixels than the catalogue style',
        () async {
      final dim = await litPixels(StarFieldStyle.catalogue);
      final lifted = await litPixels(StarFieldStyle.galaxy);
      expect(dim, greaterThan(0), reason: 'the field must paint at all');
      expect(lifted, greaterThan(dim));
    });
  });
}

/// [count] stars of one magnitude, scattered through a 120 ly box at the
/// origin — small enough that the whole field stays inside an 800×600 frame.
HygStars _uniformField({required int count, required double magnitude}) {
  final rng = math.Random(11);
  final xyz = Float32List(count * 3);
  final ids = Int32List(count);
  final mag = Float32List(count);
  final color = Int32List(count);
  for (var i = 0; i < count; i++) {
    xyz[i * 3] = (rng.nextDouble() - 0.5) * 120;
    xyz[i * 3 + 1] = (rng.nextDouble() - 0.5) * 120;
    xyz[i * 3 + 2] = (rng.nextDouble() - 0.5) * 120;
    ids[i] = 1000 + i;
    mag[i] = magnitude;
    color[i] = 0xFFBFD4FF;
  }
  return HygStars(
    count: count,
    starId: ids,
    xyz: xyz,
    mag: mag,
    color: color,
    named: const <String, HygNamed>{},
    indexById: <int, int>{for (var i = 0; i < count; i++) 1000 + i: i},
  );
}
