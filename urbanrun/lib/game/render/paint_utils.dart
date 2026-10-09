import 'package:flutter/material.dart';

import '../model/geometry.dart';
import '../model/scene_model.dart';
import '../projection/iso_projection.dart';

/// Shared isometric drawing helpers used by every element renderer.
///
/// These keep projection + path construction identical across modules so a
/// re-skinned element lines up pixel-for-pixel with the rest of the scene.

/// The four screen-space corners of a world-space rectangle, clockwise from
/// top-left.
List<Point2> rectCorners(Bounds2 bounds, IsoProjection projection) => <Point2>[
  projection.worldToScreen(Point2(bounds.left, bounds.top)),
  projection.worldToScreen(Point2(bounds.right, bounds.top)),
  projection.worldToScreen(Point2(bounds.right, bounds.bottom)),
  projection.worldToScreen(Point2(bounds.left, bounds.bottom)),
];

/// A closed polygon path through the given screen-space points.
///
/// Note: `moveTo` + `addPolygon` would start a *separate* sub-path from the
/// second point, dropping the first vertex (filling only the triangle of the
/// remaining points). We build the contour explicitly so every vertex is
/// included — important for the large ground quad, not just thin road bands.
Path polygon(List<Point2> points) {
  final path = Path()..moveTo(points.first.x, points.first.y);
  for (final point in points.skip(1)) {
    path.lineTo(point.x, point.y);
  }
  return path..close();
}

/// Draws a line between two world-space points, scaling [width] (expressed in
/// tiles) by the projection tile height.
void drawWorldLine(
  Canvas canvas,
  IsoProjection projection,
  Point2 a,
  Point2 b,
  Paint paint,
  double width,
) {
  final linePaint = Paint.from(paint)
    ..strokeWidth = width * projection.tileHeight;
  canvas.drawLine(
    toOffset(projection.worldToScreen(a)),
    toOffset(projection.worldToScreen(b)),
    linePaint,
  );
}

Offset toOffset(Point2 point) => Offset(point.x, point.y);
