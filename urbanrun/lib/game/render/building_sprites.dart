import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

/// Loads the illustrated building sprites and maps each street building to one.
///
/// Sprites are keyed by the street obstacle's top-left tile (`left,top`). A
/// missing asset simply yields `null`, and [BuildingRenderer] falls back to its
/// procedural drawing — so the demo never fails to start on a bad asset.
class BuildingSprites {
  BuildingSprites._(this._byKey);

  final Map<String, ui.Image> _byKey;

  static const String _dir = 'assets/buildings/cut/';

  /// Street obstacle (left,top) -> sprite file name.
  static const Map<String, String> _streetAssets = <String, String>{
    '2,2': 'building-coffee-shop.png',
    '9,2': 'building-store.png',
    '16,2': 'building-office-a.png',
    '2,9': 'building-residential-a.png',
    '16,9': 'building-residential-b.png',
    '2,16': 'building-corner-shop-a.png',
    '9,16': 'building-office-b.png',
    '16,16': 'building-corner-shop-b.png',
  };

  static Future<BuildingSprites> load() async {
    final map = <String, ui.Image>{};
    for (final entry in _streetAssets.entries) {
      try {
        map[entry.key] = await _loadImage('$_dir${entry.value}');
      } catch (_) {
        // Leave unmapped; the renderer draws the procedural fallback.
      }
    }
    return BuildingSprites._(map);
  }

  /// The sprite for a street obstacle at ([left], [top]) tiles, or null.
  ui.Image? forStreetObstacle(double left, double top) =>
      _byKey['${left.toInt()},${top.toInt()}'];

  static Future<ui.Image> _loadImage(String key) async {
    final data = await rootBundle.load(key);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}
