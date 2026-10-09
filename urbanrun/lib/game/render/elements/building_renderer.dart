import 'package:flutter/material.dart';

import '../../model/geometry.dart';
import '../../model/scene_model.dart';
import '../../projection/iso_projection.dart';
import '../paint_utils.dart';
import '../render_style.dart';

/// Draws a single building/obstacle as an extruded isometric box with light
/// and shadow walls, plus street signage labels.
class BuildingRenderer {
  const BuildingRenderer(this.palette);

  final BuildingPalette palette;

  void draw(
    Canvas canvas,
    SceneModel scene,
    Obstacle obstacle,
    IsoProjection projection,
  ) {
    final b = obstacle.bounds;
    final base = rectCorners(b, projection);
    final height = scene.id == SceneId.street ? 1.8 : .35;
    final roof = base
        .map(
          (point) => Point2(point.x, point.y - height * projection.tileHeight),
        )
        .toList();
    final roofPaint = Paint()
      ..color = scene.id == SceneId.street
          ? _buildingColor(b)
          : palette.interiorRoof;
    final wallLight = Paint()
      ..color = scene.id == SceneId.street
          ? palette.streetWallLight
          : palette.interiorWallLight;
    final wallShadow = Paint()
      ..color = scene.id == SceneId.street
          ? palette.streetWallShadow
          : palette.interiorWallShadow;
    canvas.drawPath(
      polygon(<Point2>[base[0], base[1], roof[1], roof[0]]),
      wallLight,
    );
    canvas.drawPath(
      polygon(<Point2>[base[1], base[2], roof[2], roof[1]]),
      wallShadow,
    );
    canvas.drawPath(polygon(roof), roofPaint);
    if (scene.id == SceneId.street && b.left == 2 && b.top == 2) {
      _drawLabel(
        canvas,
        projection.worldToScreen(const Point2(4, 2)),
        'COFFEE SHOP',
      );
    }
    if (scene.id == SceneId.street && b.left == 9 && b.top == 2) {
      _drawLabel(
        canvas,
        projection.worldToScreen(const Point2(11, 2)),
        'MARKET',
      );
    }
  }

  Color _buildingColor(Bounds2 bounds) {
    if (bounds.left == 2 && bounds.top == 2) return palette.coffeeRoof;
    if (bounds.left == 9 && bounds.top == 2) return palette.marketRoof;
    if (bounds.left == 16 && bounds.top == 2) return palette.thirdRoof;
    return palette.defaultRoof;
  }

  void _drawLabel(Canvas canvas, Point2 point, String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: palette.label,
          fontSize: 8,
          fontWeight: FontWeight.w700,
          letterSpacing: .8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(point.x - painter.width / 2, point.y - 38));
  }
}
