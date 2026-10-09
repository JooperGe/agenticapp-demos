import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

/// Loads illustrated tree sprites (foot-anchored like buildings). Missing
/// assets simply yield an empty set and the renderer falls back to the
/// procedural tree, so the demo still runs without the images.
class TreeSprites {
  TreeSprites._(this.images);

  final List<ui.Image> images;

  static const String _dir = 'assets/trees/cut/';
  static const List<String> _files = <String>[
    'tree-1.png',
    'tree-2.png',
    'tree-3.png',
  ];

  static Future<TreeSprites> load() async {
    final loaded = <ui.Image>[];
    for (final name in _files) {
      try {
        loaded.add(await _loadImage('$_dir$name'));
      } catch (_) {
        // Skip missing variants.
      }
    }
    return TreeSprites._(loaded);
  }

  bool get isEmpty => images.isEmpty;

  /// A sprite for the given slot, cycling through the loaded variants.
  ui.Image? byIndex(int index) =>
      images.isEmpty ? null : images[index % images.length];

  static Future<ui.Image> _loadImage(String key) async {
    final data = await rootBundle.load(key);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}
