import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../model/geometry.dart';
import '../model/scene_model.dart';
import '../projection/iso_projection.dart';
import 'building_sprites.dart';
import 'elements/block_renderer.dart';
import 'elements/building_renderer.dart';
import 'elements/prop_renderer.dart';
import 'elements/road_renderer.dart';
import 'elements/tree_renderer.dart';
import 'interior_sprites.dart';
import 'paint_utils.dart';
import 'render_style.dart';

/// Composites the neighborhood from independent element renderers.
///
/// This class owns only scene composition and painter's-depth ordering; the
/// look of each element lives in its own module ([RoadRenderer],
/// [BuildingRenderer], [TreeRenderer], [BlockRenderer], [PropRenderer]) and is
/// swapped by passing a different [RenderStyle].
class CityRenderer {
  CityRenderer({this.style = RenderStyle.classic})
    : _block = BlockRenderer(style.block),
      _road = RoadRenderer(style.road),
      _building = BuildingRenderer(style.building),
      _tree = TreeRenderer(style.tree),
      _prop = PropRenderer(style.prop);

  final RenderStyle style;
  final BlockRenderer _block;
  final RoadRenderer _road;
  final BuildingRenderer _building;
  final TreeRenderer _tree;
  final PropRenderer _prop;

  /// Illustrated building sprites; assigned after async asset load. When null
  /// (or missing a given building) the procedural box is drawn instead.
  BuildingSprites? sprites;

  /// Illustrated interior room images, keyed by interior scene. When present
  /// for the current scene the room is drawn from the image instead of the
  /// procedural floor + furniture.
  InteriorSprites? interiors;

  /// Interior image sizing/placement tunables (fraction of the scene's floor
  /// diamond width, and where the scene centre lands in the image).
  static const double _interiorScale = 1.5;
  static const double _interiorAnchorY = 0.62;

  void render(
    Canvas canvas,
    SceneModel scene,
    IsoProjection projection, {
    Iterable<CityRenderItem> additionalItems = const <CityRenderItem>[],
  }) {
    final ui.Image? room = scene.id == SceneId.street
        ? null
        : interiors?.forScene(scene.id);
    if (room != null) {
      _drawInteriorImage(canvas, scene, projection, room);
      final items = sortCityRenderItems(additionalItems);
      for (final item in items) {
        item.paint();
      }
      _drawEntrances(canvas, scene, projection);
      return;
    }

    _drawGround(canvas, scene, projection);
    final items = <CityRenderItem>[];
    for (final obstacle in scene.obstacles) {
      final ui.Image? sprite = scene.id == SceneId.street
          ? sprites?.forStreetObstacle(
              obstacle.bounds.left,
              obstacle.bounds.top,
            )
          : null;
      items.add(
        CityRenderItem(
          groundFoot: obstacleGroundFoot(obstacle),
          paint: () =>
              _building.draw(canvas, scene, obstacle, projection, sprite: sprite),
        ),
      );
    }
    if (scene.id == SceneId.street) {
      items.addAll(_streetProps(canvas, projection));
    } else {
      items.addAll(_interiorProps(canvas, scene, projection));
    }
    items.addAll(additionalItems);
    final sortedItems = sortCityRenderItems(items);
    for (final item in sortedItems) {
      item.paint();
    }
    _drawEntrances(canvas, scene, projection);
  }

  void _drawInteriorImage(
    Canvas canvas,
    SceneModel scene,
    IsoProjection projection,
    ui.Image room,
  ) {
    final b = scene.bounds;
    final center = projection.worldToScreen(
      Point2((b.left + b.right) / 2, (b.top + b.bottom) / 2),
    );
    final floorWidth = (b.width + b.height) * projection.tileWidth / 2;
    final destWidth = floorWidth * _interiorScale;
    final destScale = destWidth / room.width;
    final destHeight = room.height * destScale;
    final dst = Rect.fromLTWH(
      center.x - destWidth / 2,
      center.y - destHeight * _interiorAnchorY,
      destWidth,
      destHeight,
    );
    canvas.drawImageRect(
      room,
      Rect.fromLTWH(0, 0, room.width.toDouble(), room.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  void _drawGround(Canvas canvas, SceneModel scene, IsoProjection projection) {
    _block.drawGroundBase(canvas, scene, projection);
    if (scene.id != SceneId.street) {
      _block.drawInteriorFloor(canvas, scene, projection);
      return;
    }
    _road.draw(canvas, projection);
    _block.drawFlowerbed(canvas, projection);
  }

  List<CityRenderItem> _streetProps(Canvas canvas, IsoProjection projection) =>
      <CityRenderItem>[
        CityRenderItem(
          groundFoot: const Point2(7.2, 6.2),
          paint: () => _tree.draw(canvas, projection, const Point2(7.2, 6.2)),
        ),
        CityRenderItem(
          groundFoot: const Point2(15.8, 8.9),
          paint: () => _tree.draw(canvas, projection, const Point2(15.8, 8.9)),
        ),
        CityRenderItem(
          groundFoot: const Point2(8.2, 15.9),
          paint: () => _tree.draw(canvas, projection, const Point2(8.2, 15.9)),
        ),
        CityRenderItem(
          groundFoot: const Point2(15.7, 15.9),
          paint: () => _tree.draw(canvas, projection, const Point2(15.7, 15.9)),
        ),
        CityRenderItem(
          groundFoot: const Point2(8.9, 7.1),
          paint: () =>
              _prop.drawLamp(canvas, projection, const Point2(8.9, 7.1)),
        ),
        CityRenderItem(
          groundFoot: const Point2(15.9, 14.1),
          paint: () =>
              _prop.drawLamp(canvas, projection, const Point2(15.9, 14.1)),
        ),
        CityRenderItem(
          groundFoot: const Point2(12.2, 13.3),
          paint: () =>
              _prop.drawBench(canvas, projection, const Point2(12.2, 13.3)),
        ),
        CityRenderItem(
          groundFoot: const Point2(17.2, 8.0),
          paint: () => _prop.drawCar(
            canvas,
            projection,
            const Point2(17.2, 8.0),
            const Color(0xFFE5A56B),
          ),
        ),
        CityRenderItem(
          groundFoot: const Point2(5.2, 15.0),
          paint: () => _prop.drawCar(
            canvas,
            projection,
            const Point2(5.2, 15.0),
            const Color(0xFF9BB6D0),
          ),
        ),
      ];

  List<CityRenderItem> _interiorProps(
    Canvas canvas,
    SceneModel scene,
    IsoProjection projection,
  ) {
    final accent = _prop.interiorAccent(scene.id);
    return <CityRenderItem>[
      CityRenderItem(
        groundFoot: const Point2(5.4, 1.5),
        paint: () => _prop.drawCounter(
          canvas,
          projection,
          const Point2(5.4, 1.5),
          accent,
        ),
      ),
      CityRenderItem(
        groundFoot: const Point2(3.2, 3.9),
        paint: () =>
            _prop.drawTable(canvas, projection, const Point2(3.2, 3.9), accent),
      ),
      CityRenderItem(
        groundFoot: const Point2(6.9, 4.1),
        paint: () =>
            _prop.drawTable(canvas, projection, const Point2(6.9, 4.1), accent),
      ),
      if (scene.id == SceneId.convenienceStore ||
          scene.id == SceneId.cornerShopA ||
          scene.id == SceneId.cornerShopB)
        CityRenderItem(
          groundFoot: const Point2(8.0, 2.0),
          paint: () =>
              _prop.drawShelf(canvas, projection, const Point2(8.0, 2.0)),
        ),
    ];
  }

  void _drawEntrances(
    Canvas canvas,
    SceneModel scene,
    IsoProjection projection,
  ) {
    final markerPaint = Paint()..color = style.marker.entrance;
    for (final entrance in scene.entrances) {
      final screen = projection.worldToScreen(entrance.position);
      final path = Path()
        ..moveTo(screen.x, screen.y - 12)
        ..lineTo(screen.x + 9, screen.y - 3)
        ..lineTo(screen.x, screen.y + 6)
        ..lineTo(screen.x - 9, screen.y - 3)
        ..close();
      canvas.drawPath(path, markerPaint);
      canvas.drawCircle(
        toOffset(screen),
        3,
        Paint()..color = style.marker.entranceCore,
      );
    }
  }
}

class CityRenderItem {
  const CityRenderItem({required this.groundFoot, required this.paint});

  final Point2 groundFoot;
  double get depth => groundDepth(groundFoot);
  final VoidCallback paint;
}

/// Returns the isometric painter's depth for an object's ground contact point.
double groundDepth(Point2 groundFoot) => groundFoot.x + groundFoot.y;

List<CityRenderItem> sortCityRenderItems(Iterable<CityRenderItem> items) {
  final sorted = items.toList()..sort((a, b) => a.depth.compareTo(b.depth));
  return sorted;
}

/// The visible ground contact corner for a rectangular obstacle/building.
Point2 obstacleGroundFoot(Obstacle obstacle) =>
    Point2(obstacle.bounds.right, obstacle.bounds.bottom);
