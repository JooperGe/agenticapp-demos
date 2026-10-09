import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

import '../model/scene_model.dart';

/// Loads the illustrated interior room images, keyed by interior [SceneId].
///
/// A missing asset yields null and the renderer falls back to the procedural
/// interior, so the demo still runs if an image fails to load.
class InteriorSprites {
  InteriorSprites._(this._byScene);

  final Map<SceneId, ui.Image> _byScene;

  static const String _dir = 'assets/buildings/interior-cut/';

  static const Map<SceneId, String> _assets = <SceneId, String>{
    SceneId.coffeeShop: 'interior-coffee-shop.png',
    SceneId.convenienceStore: 'interior-store.png',
    SceneId.officeA: 'interior-office-a.png',
    SceneId.officeB: 'interior-office-b.png',
    SceneId.residentialA: 'interior-residential-a.png',
    SceneId.residentialB: 'interior-residential-b.png',
    SceneId.cornerShopA: 'interior-corner-shop-a.png',
    SceneId.cornerShopB: 'interior-corner-shop-b.png',
  };

  static Future<InteriorSprites> load() async {
    final map = <SceneId, ui.Image>{};
    for (final entry in _assets.entries) {
      try {
        map[entry.key] = await _loadImage('$_dir${entry.value}');
      } catch (_) {
        // Leave unmapped; renderer draws the procedural interior fallback.
      }
    }
    return InteriorSprites._(map);
  }

  ui.Image? forScene(SceneId id) => _byScene[id];

  static Future<ui.Image> _loadImage(String key) async {
    final data = await rootBundle.load(key);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}
