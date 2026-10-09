import 'package:flutter/material.dart';

import '../../model/geometry.dart';
import '../../model/scene_model.dart';
import '../../projection/iso_projection.dart';
import '../paint_utils.dart';
import '../render_style.dart';

/// Draws the block's ground plate, interior floor and the park flowerbed.
///
/// Road markings live in [RoadRenderer]; this module only owns the terrain the
/// block sits on, so either can be re-skinned independently.
class BlockRenderer {
  const BlockRenderer(this.palette);

  final BlockPalette palette;

  void drawGroundBase(
    Canvas canvas,
    SceneModel scene,
    IsoProjection projection,
  ) {
    final ground = Paint()
      ..color = scene.id == SceneId.street
          ? palette.streetGround
          : palette.interiorGround;
    canvas.drawPath(polygon(rectCorners(scene.bounds, projection)), ground);
  }

  void drawInteriorFloor(
    Canvas canvas,
    SceneModel scene,
    IsoProjection projection,
  ) {
    final bounds = scene.bounds;
    final floor = Paint()..color = palette.interiorFloor;
    final inset = Bounds2(
      bounds.left + .35,
      bounds.top + .35,
      bounds.right - .35,
      bounds.bottom - .35,
    );
    canvas.drawPath(polygon(rectCorners(inset, projection)), floor);
  }

  void drawFlowerbed(Canvas canvas, IsoProjection projection) {
    const bed = Bounds2(9.3, 9.5, 13.3, 12.6);
    canvas.drawPath(
      polygon(rectCorners(bed, projection)),
      Paint()..color = palette.flowerbed,
    );
    final flower = Paint()..color = palette.flowerPrimary;
    for (final point in <Point2>[
      const Point2(10, 10),
      const Point2(11.2, 11.2),
      const Point2(12.2, 10.2),
      const Point2(11, 12),
    ]) {
      canvas.drawCircle(toOffset(projection.worldToScreen(point)), 3, flower);
      canvas.drawCircle(
        toOffset(projection.worldToScreen(point + const Point2(.2, .1))),
        2,
        Paint()..color = palette.flowerAccent,
      );
    }
  }
}
