import '../model/geometry.dart';

/// Converts ground-plane world coordinates to and from an isometric screen.
class IsoProjection {
  const IsoProjection({this.tileWidth = 64, this.tileHeight = 32})
    : assert(tileWidth > 0),
      assert(tileHeight > 0);

  final double tileWidth;
  final double tileHeight;

  Point2 worldToScreen(Point2 point) {
    final sx = (point.x - point.y) * tileWidth / 2;
    final sy = (point.x + point.y) * tileHeight / 2;
    return Point2(sx, sy);
  }

  Point2 screenToWorld(Point2 point) {
    final x = point.x / tileWidth + point.y / tileHeight;
    final y = point.y / tileHeight - point.x / tileWidth;
    return Point2(x, y);
  }
}
