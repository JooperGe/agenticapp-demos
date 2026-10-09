import 'package:flutter/material.dart';

import '../../model/geometry.dart';
import '../../model/scene_model.dart';
import '../../projection/iso_projection.dart';
import '../paint_utils.dart';
import '../render_style.dart';

/// Draws the remaining street and interior decoration props: lamps, benches,
/// parked cars, counters, tables and shelves.
class PropRenderer {
  const PropRenderer(this.palette);

  final PropPalette palette;

  /// Interior furniture accent color for the given scene.
  Color interiorAccent(SceneId id) =>
      id == SceneId.coffeeShop ? palette.coffeeAccent : palette.storeAccent;

  void drawLamp(Canvas canvas, IsoProjection projection, Point2 point) {
    final screen = toOffset(projection.worldToScreen(point));
    final paint = Paint()
      ..color = palette.lampPole
      ..strokeWidth = 2;
    canvas.drawLine(screen, screen.translate(0, -30), paint);
    canvas.drawCircle(
      screen.translate(0, -33),
      4,
      Paint()..color = palette.lampLight,
    );
  }

  void drawBench(Canvas canvas, IsoProjection projection, Point2 point) {
    final screen = toOffset(projection.worldToScreen(point));
    final paint = Paint()..color = palette.bench;
    canvas.drawRect(
      Rect.fromCenter(center: screen.translate(0, -5), width: 22, height: 4),
      paint,
    );
    canvas.drawRect(
      Rect.fromCenter(center: screen.translate(0, -12), width: 22, height: 4),
      paint,
    );
    canvas.drawLine(
      screen.translate(-8, -3),
      screen.translate(-8, 5),
      paint..strokeWidth = 3,
    );
    canvas.drawLine(screen.translate(8, -3), screen.translate(8, 5), paint);
  }

  void drawCar(
    Canvas canvas,
    IsoProjection projection,
    Point2 point,
    Color color,
  ) {
    final screen = toOffset(projection.worldToScreen(point));
    canvas.drawOval(
      Rect.fromCenter(center: screen.translate(0, -5), width: 25, height: 12),
      Paint()..color = color,
    );
    canvas.drawRect(
      Rect.fromCenter(center: screen.translate(0, -9), width: 12, height: 7),
      Paint()..color = color.withValues(alpha: .85),
    );
    canvas.drawCircle(
      screen.translate(-8, 1),
      3,
      Paint()..color = palette.carWheel,
    );
    canvas.drawCircle(
      screen.translate(8, 1),
      3,
      Paint()..color = palette.carWheel,
    );
  }

  void drawCounter(
    Canvas canvas,
    IsoProjection projection,
    Point2 point,
    Color color,
  ) {
    final screen = toOffset(projection.worldToScreen(point));
    canvas.drawRect(
      Rect.fromCenter(center: screen.translate(0, -8), width: 45, height: 14),
      Paint()..color = color,
    );
    canvas.drawRect(
      Rect.fromCenter(center: screen.translate(0, -17), width: 47, height: 4),
      Paint()..color = palette.counterTop,
    );
  }

  void drawTable(
    Canvas canvas,
    IsoProjection projection,
    Point2 point,
    Color color,
  ) {
    final screen = toOffset(projection.worldToScreen(point));
    canvas.drawOval(
      Rect.fromCenter(center: screen.translate(0, -7), width: 23, height: 13),
      Paint()..color = color,
    );
    canvas.drawLine(
      screen.translate(0, -4),
      screen.translate(0, 6),
      Paint()
        ..color = palette.tableLeg
        ..strokeWidth = 3,
    );
  }

  void drawShelf(Canvas canvas, IsoProjection projection, Point2 point) {
    final screen = toOffset(projection.worldToScreen(point));
    final paint = Paint()..color = palette.shelf;
    canvas.drawRect(
      Rect.fromCenter(center: screen.translate(0, -15), width: 25, height: 32),
      paint,
    );
    for (var i = 0; i < 3; i++) {
      canvas.drawLine(
        screen.translate(-10, -25 + i * 9),
        screen.translate(10, -25 + i * 9),
        Paint()
          ..color = palette.shelfBoard
          ..strokeWidth = 3,
      );
    }
  }
}
