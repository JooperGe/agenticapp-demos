import 'package:flutter/material.dart';

import '../../model/geometry.dart';
import '../../projection/iso_projection.dart';
import '../paint_utils.dart';
import '../render_style.dart';

/// Draws a stylized tree: two overlapping canopy blobs over a trunk.
class TreeRenderer {
  const TreeRenderer(this.palette);

  final TreePalette palette;

  void draw(Canvas canvas, IsoProjection projection, Point2 point) {
    final screen = projection.worldToScreen(point);
    canvas.drawCircle(
      toOffset(screen + const Point2(0, -22)),
      12,
      Paint()..color = palette.canopyPrimary,
    );
    canvas.drawCircle(
      toOffset(screen + const Point2(-8, -17)),
      8,
      Paint()..color = palette.canopySecondary,
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: toOffset(screen + const Point2(0, -6)),
        width: 4,
        height: 13,
      ),
      Paint()..color = palette.trunk,
    );
  }
}
