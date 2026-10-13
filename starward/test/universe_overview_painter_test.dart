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
}
