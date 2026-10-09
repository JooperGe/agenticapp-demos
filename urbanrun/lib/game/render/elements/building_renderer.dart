import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../model/geometry.dart';
import '../../model/scene_model.dart';
import '../../projection/iso_projection.dart';
import '../paint_utils.dart';
import '../render_style.dart';

/// Draws a single building/obstacle. When an illustrated [sprite] is supplied
/// it is blitted anchored to the footprint's front corner; otherwise the
/// building falls back to a procedural extruded isometric box.
class BuildingRenderer {
  const BuildingRenderer(this.palette, {this.spriteScale = 1.0});

  final BuildingPalette palette;

  /// Multiplier applied to the footprint diamond width when sizing a sprite.
  /// Tunes how far the illustrated building overhangs its collision box.
  final double spriteScale;

  void draw(
    Canvas canvas,
    SceneModel scene,
    Obstacle obstacle,
    IsoProjection projection, {
    ui.Image? sprite,
  }) {
    final b = obstacle.bounds;
    if (sprite != null) {
      _drawSprite(canvas, b, sprite, projection);
      return;
    }
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

  void _drawSprite(
    Canvas canvas,
    Bounds2 b,
    ui.Image sprite,
    IsoProjection projection,
  ) {
    // Front/ground corner of the footprint diamond; the sprite's bottom-center
    // anchor sits here so illustrated buildings line up with the collision box
    // and sort by the same ground foot the procedural path uses.
    final foot = projection.worldToScreen(Point2(b.right, b.bottom));
    final diamondWidth = (b.width + b.height) * projection.tileWidth / 2;
    final destWidth = diamondWidth * spriteScale;
    final scale = destWidth / sprite.width;
    final destHeight = sprite.height * scale;
    final dst = Rect.fromLTWH(
      foot.x - destWidth / 2,
      foot.y - destHeight,
      destWidth,
      destHeight,
    );
    final src = Rect.fromLTWH(
      0,
      0,
      sprite.width.toDouble(),
      sprite.height.toDouble(),
    );
    canvas.drawImageRect(
      sprite,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
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
