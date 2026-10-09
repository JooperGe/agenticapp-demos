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
Path polygon(List<Point2> points) => Path()
  ..moveTo(points.first.x, points.first.y)
  ..addPolygon(
    points.skip(1).map((point) => Offset(point.x, point.y)).toList(),
    true,
  );

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
