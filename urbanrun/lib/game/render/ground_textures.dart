import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Seamless ground textures (grass / road asphalt / pavement). Any missing
/// texture is null and the renderers fall back to their flat palette color, so
/// the exact road/ground geometry is unchanged.
class GroundTextures {
  GroundTextures._(this.grass, this.road, this.pavement);

  final ui.Image? grass;
  final ui.Image? road;
  final ui.Image? pavement;

  static const String _dir = 'assets/ground/';

  static Future<GroundTextures> load() async {
    return GroundTextures._(
      await _tryLoad('${_dir}grass.png'),
      await _tryLoad('${_dir}road.png'),
      await _tryLoad('${_dir}pavement.png'),
    );
  }

  static Future<ui.Image?> _tryLoad(String key) async {
    try {
      final data = await rootBundle.load(key);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }
}

/// A repeating-image paint for [image], scaled so one tile spans [tilePx]
/// pixels in the current (scene) coordinate space.
Paint tiledPaint(ui.Image image, double tilePx) {
  final k = tilePx / image.width;
  final matrix = Matrix4.identity()..scaleByDouble(k, k, 1, 1);
  return Paint()
    ..shader = ImageShader(
      image,
      TileMode.mirror,
      TileMode.mirror,
      matrix.storage,
    )
    ..filterQuality = FilterQuality.medium;
}
