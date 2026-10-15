import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'star_catalog.dart';
import 'star_set.dart';

export 'star_set.dart' show HygNamed, HygStars;

/// Loads the compact HYG binary + named index from assets. Returns null if the
/// asset is missing so callers can fall back to the curated catalogue.
///
/// The [HygStars] container itself lives in `star_set.dart` (pure Dart) so the
/// build tools share the exact parse/build code with the app.
class HygCatalog {
  HygCatalog._();

  static HygStars? _cache;

  static Future<HygStars?> load() async {
    if (_cache != null) return _cache;
    try {
      final data = await rootBundle.load('assets/stars/hyg.bin');
      final parsed = HygStars.fromBinary(data.buffer.asByteData());
      // The parsed binary's named map is const-empty; rebuild the record with
      // the parsed sidecar merged in.
      final named = HygStars.namedFromJson(
          await rootBundle.loadString('assets/stars/hyg_named.json'));
      _cache = HygStars(
        count: parsed.count,
        starId: parsed.starId,
        xyz: parsed.xyz,
        mag: parsed.mag,
        color: parsed.color,
        named: named,
        indexById: parsed.indexById,
      );
      return _cache;
    } catch (_) {
      return null; // asset absent → caller uses curated fallback
    }
  }

  /// A tiny in-memory catalogue built from the curated star list, used only
  /// when the HYG asset can't be loaded so the universe still works offline.
  static HygStars curatedFallback() {
    final cat = StarCatalog.build();
    final count = cat.length;
    final starId = Int32List(count);
    final xyz = Float32List(count * 3);
    final mag = Float32List(count);
    final color = Int32List(count);
    final named = <String, HygNamed>{};
    final indexById = <int, int>{};
    for (var i = 0; i < count; i++) {
      final s = cat[i];
      final id = i + 1;
      starId[i] = id;
      indexById[id] = i;
      xyz[i * 3] = s.position.x;
      xyz[i * 3 + 1] = s.position.y;
      xyz[i * 3 + 2] = s.position.z;
      mag[i] = s.magnitude;
      color[i] = s.color;
      // Index by the English token too so hero anchoring can still match.
      for (final token in s.name.split(' ')) {
        named.putIfAbsent(
          token,
          () => HygNamed(
            id: id,
            name: s.name,
            position: s.position,
            magnitude: s.magnitude,
            color: s.color,
          ),
        );
      }
    }
    return HygStars(
      count: count,
      starId: starId,
      xyz: xyz,
      mag: mag,
      color: color,
      named: named,
      indexById: indexById,
    );
  }
}
