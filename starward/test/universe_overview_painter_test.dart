import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/hyg_catalog.dart';
import 'package:starward/ui/galaxy3d/camera3d.dart';
import 'package:starward/ui/galaxy3d/galaxy3d_scene.dart';
import 'package:starward/ui/galaxy3d/universe_overview_painter.dart';

/// The overview painter is orchestration, so its correctness is mostly visual
/// and checked by running the app. What *is* testable is that it survives every
/// camera position the page can put it in — including deep inside the sphere,
/// where the shell must silently stop drawing instead of producing a garbage
/// silhouette — and that it paints something.
void main() {
  const double ws = 12;
  const double rWorld = 36792;
  const double rLy = 3066;

  final scene = Galaxy3DScene(
    planets: const <ScenePlanet>[],
    planetPositions: const <String, Vec3>{},
    worldScale: ws,
    hyg: HygCatalog.curatedFallback(),
  );

  ui.Image paintAt(Camera3D camera) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 800, 600));
    UniverseOverviewPainter(
      scene: scene,
      camera: camera,
      shipPosition: const Vec3(100, 0, 0),
      universeRadiusLy: rLy,
      journey: null,
      journeyProgress: 0,
      repaint: const AlwaysStoppedAnimation<double>(0),
    ).paint(canvas, const Size(800, 600));
    return recorder.endRecording().toImageSync(800, 600);
  }

  /// Counts the pixels with alpha > 0 in [image]. `ui.Picture` exposes no
  /// draw-call count, so rasterising to an image and scanning the alpha channel
  /// is the only way to tell "the painter drew something" from "it drew
  /// nothing" — which is exactly what the inside/outside shell distinction
  /// needs.
  Future<int> opaquePixels(ui.Image image) async {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final bytes = data.buffer.asUint8List();
    var n = 0;
    for (var i = 3; i < bytes.length; i += 4) {
      if (bytes[i] > 0) n++;
    }
    image.dispose();
    return n;
  }

  Camera3D cameraAt(double distance) => Camera3D(
        target: const Vec3(0, 0, 0),
        yaw: 0.6,
        pitch: 0.35,
        distance: distance,
        mode: CameraMode.overview,
      );

  test('paints from outside the sphere without throwing', () {
    final image = paintAt(cameraAt(2.3 * rWorld));
    expect(image.width, 800);
    expect(image.height, 600);
    image.dispose();
  });

  test('paints from inside the sphere without throwing', () {
    // The "focus route" framing puts the camera deep inside; the shell must
    // fade out rather than project a nonsense silhouette.
    final image = paintAt(cameraAt(880));
    expect(image.width, 800);
    image.dispose();
  });

  test('paints at the exact framing distance without throwing', () {
    final image = paintAt(cameraAt(2 * rWorld));
    expect(image.width, 800);
    image.dispose();
  });

  // Spec §10 test 4: inside the sphere (d < R) the shell must draw nothing.
  // `ui.Picture` exposes no draw-call count, so the discriminator is real
  // pixels: the same scene rendered outside the shell (d = 2.3·R, shellFade == 1,
  // shell drawn) versus inside it (d = 880, the route-focus distance — a real
  // camera position, not a contrived one — where shellFade == 0 and the shell
  // is skipped). The shell's fill washes the whole projected disc, so the
  // outside render lights up far more pixels.
  //
  // Measured: outside = 199696 px, inside = 11895 px (ratio ≈ 16.8×). The 5×
  // bound sits far below that and far above 1×.
  //
  // What this establishes is the *coarse* contrast "shell drawn outside vs not
  // drawn at all", not that nothing leaks inside: forcing shellFade to return 1
  // still passes, because inside the sphere `limbRadius` is infinite so the fill
  // and limb paths early-return and the leaked lattice strokes (~7k px of faint
  // lines) stay under the 5× bound. The exact "inside draws nothing" claim is
  // pinned by `test/universe_shell_test.dart`, which asserts zero opaque pixels
  // for the same inside case.
  test('draws the shell outside the sphere and not inside it', () async {
    final outside = await opaquePixels(paintAt(cameraAt(2.3 * rWorld)));
    final inside = await opaquePixels(paintAt(cameraAt(880)));
    expect(inside, greaterThan(0)); // the star field alone still paints
    expect(outside, greaterThan(inside * 5));
  });
}
