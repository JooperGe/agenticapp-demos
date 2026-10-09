import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

/// Loads the illustrated player character. Prefers a numbered walk cycle
/// (`player-1.png` … `player-8.png`); falls back to a single `player.png`.
/// When no asset loads the list is empty and [PlayerRenderer] draws the
/// procedural figure.
class CharacterSprite {
  CharacterSprite._(this.frames);

  /// Walk-cycle frames in order (same view/scale, only limbs differ).
  final List<ui.Image> frames;

  bool get isEmpty => frames.isEmpty;

  static const String _dir = 'assets/character/cut/';

  static Future<CharacterSprite> load() async {
    final frames = <ui.Image>[];
    for (var i = 1; i <= 8; i++) {
      try {
        frames.add(await _loadImage('${_dir}player-$i.png'));
      } catch (_) {
        // Skip missing/gap frames; load whichever numbered frames exist.
        continue;
      }
    }
    if (frames.isEmpty) {
      try {
        frames.add(await _loadImage('${_dir}player.png'));
      } catch (_) {
        // No character art available.
      }
    }
    return CharacterSprite._(frames);
  }

  static Future<ui.Image> _loadImage(String key) async {
    final data = await rootBundle.load(key);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}
