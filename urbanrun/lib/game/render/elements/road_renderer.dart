import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../model/geometry.dart';
import '../../projection/iso_projection.dart';
import '../ground_textures.dart';
import '../paint_utils.dart';
import '../render_style.dart';

/// Draws the street grid: pavement bands, road surface, lane dashes and
/// zebra crossings. Fixed layout for the 3x3 demo block.
class RoadRenderer {
  const RoadRenderer(this.palette);

  final RoadPalette palette;

  void draw(
    Canvas canvas,
    IsoProjection projection, {
    ui.Image? asphalt,
    ui.Image? pavementTexture,
  }) {
    final pavement = pavementTexture != null
        ? tiledPaint(pavementTexture, 80)
        : (Paint()..color = palette.pavement);
    final road = asphalt != null
        ? tiledPaint(asphalt, 80)
        : (Paint()..color = palette.surface);
    final roadEdge = Paint()..color = palette.laneMarking;
    final paths = <List<Point2>>[
      [
        const Point2(0, 7.1),
        const Point2(24, 7.1),
        const Point2(24, 8.8),
        const Point2(0, 8.8),
      ],
      [
        const Point2(7.1, 0),
        const Point2(8.8, 0),
        const Point2(8.8, 24),
        const Point2(7.1, 24),
      ],
      [
        const Point2(14.2, 0),
        const Point2(15.9, 0),
        const Point2(15.9, 24),
        const Point2(14.2, 24),
      ],
      [
        const Point2(0, 14.2),
        const Point2(24, 14.2),
        const Point2(24, 15.9),
        const Point2(0, 15.9),
      ],
    ];
    for (final path in paths) {
      canvas.drawPath(
        polygon(path.map(projection.worldToScreen).toList()),
        pavement,
      );
    }
    final roads = <List<Point2>>[
      [
        const Point2(0, 7.45),
        const Point2(24, 7.45),
        const Point2(24, 8.45),
        const Point2(0, 8.45),
      ],
      [
        const Point2(7.45, 0),
        const Point2(8.45, 0),
        const Point2(8.45, 24),
        const Point2(7.45, 24),
      ],
      [
        const Point2(14.55, 0),
        const Point2(15.55, 0),
        const Point2(15.55, 24),
        const Point2(14.55, 24),
      ],
      [
        const Point2(0, 14.55),
        const Point2(24, 14.55),
        const Point2(24, 15.55),
        const Point2(0, 15.55),
      ],
    ];
    for (final points in roads) {
      canvas.drawPath(
        polygon(points.map(projection.worldToScreen).toList()),
        road,
      );
    }
    for (var i = 1; i < 24; i += 2) {
      drawWorldLine(
        canvas,
        projection,
        Point2(i.toDouble(), 7.95),
        Point2((i + .7).toDouble(), 7.95),
        roadEdge,
        0.08,
      );
      drawWorldLine(
        canvas,
        projection,
        Point2(7.95, i.toDouble()),
        Point2(7.95, (i + .7).toDouble()),
        roadEdge,
        0.08,
      );
      drawWorldLine(
        canvas,
        projection,
        Point2(15.05, i.toDouble()),
        Point2(15.05, (i + .7).toDouble()),
        roadEdge,
        0.08,
      );
      drawWorldLine(
        canvas,
        projection,
        Point2(i.toDouble(), 15.05),
        Point2((i + .7).toDouble(), 15.05),
        roadEdge,
        0.08,
      );
    }
    _drawCrossing(canvas, projection, const Point2(7.95, 6.8), false);
    _drawCrossing(canvas, projection, const Point2(6.8, 7.95), true);
    _drawCrossing(canvas, projection, const Point2(15.05, 8.8), true);
  }

  void _drawCrossing(
    Canvas canvas,
    IsoProjection projection,
    Point2 center,
    bool horizontal,
  ) {
    final paint = Paint()..color = palette.crossing;
    for (var i = -2; i <= 2; i++) {
      final offset = i * .26;
      final a = horizontal
          ? Point2(center.x + offset, center.y - .4)
          : Point2(center.x - .4, center.y + offset);
      final b = horizontal
          ? Point2(center.x + offset, center.y + .4)
          : Point2(center.x + .4, center.y + offset);
      drawWorldLine(canvas, projection, a, b, paint, .13);
    }
  }
}
