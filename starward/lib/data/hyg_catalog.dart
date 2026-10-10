import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../core/vec3.dart';
import 'star_catalog.dart';

/// A named real star (for labels and anchoring game planets to real systems).
class HygNamed {
  const HygNamed({
    required this.id,
    required this.name,
    required this.position,
    required this.magnitude,
    required this.color,
  });

  final int id;
  final String name;

  /// Position in light-years, Sun at origin, Y = north celestial pole.
  final Vec3 position;
  final double magnitude;
  final int color;
}

/// The full HYG catalogue loaded into packed typed arrays. Positions are kept
/// in flat [Float32List]s (not Vec3 objects) so the renderer can iterate
/// ~109k stars per frame without allocating.
class HygStars {
  HygStars({
    required this.count,
    required this.starId,
    required this.xyz,
    required this.mag,
    required this.color,
    required this.named,
    required this.indexById,
  });

  final int count;

  /// Stable HYG id per star (durable key for procedural planet generation).
  final Int32List starId;

  /// Length 3*count — x,y,z in light-years, sorted brightest-first.
  final Float32List xyz;

  /// Apparent magnitude per star (brightest first).
  final Float32List mag;

  /// Packed ARGB per star.
  final Int32List color;

  /// Named stars by proper name.
  final Map<String, HygNamed> named;

  /// Stable HYG id → index into the packed arrays.
  final Map<int, int> indexById;

  Vec3 positionOfIndex(int i) => Vec3(xyz[i * 3], xyz[i * 3 + 1], xyz[i * 3 + 2]);

  Vec3? positionOfId(int id) {
    final i = indexById[id];
    return i == null ? null : positionOfIndex(i);
  }

  Vec3? positionOf(String nameFragment) {
    for (final e in named.entries) {
      if (e.key == nameFragment || e.key.contains(nameFragment)) {
        return e.value.position;
      }
    }
    return null;
  }
}

/// Loads the compact HYG binary + named index from assets. Returns null if the
/// asset is missing so callers can fall back to the curated catalogue.
class HygCatalog {
  HygCatalog._();

  static HygStars? _cache;

  static Future<HygStars?> load() async {
    if (_cache != null) return _cache;
    try {
      final data = await rootBundle.load('assets/stars/hyg.bin');
      final bd = data.buffer.asByteData();
      final count = bd.getInt32(0, Endian.little);
      final starId = Int32List(count);
      final xyz = Float32List(count * 3);
      final mag = Float32List(count);
      final color = Int32List(count);
      final indexById = <int, int>{};
      var off = 4;
      for (var i = 0; i < count; i++) {
        final id = bd.getInt32(off, Endian.little);
        starId[i] = id;
        indexById[id] = i;
        xyz[i * 3] = bd.getFloat32(off + 4, Endian.little);
        xyz[i * 3 + 1] = bd.getFloat32(off + 8, Endian.little);
        xyz[i * 3 + 2] = bd.getFloat32(off + 12, Endian.little);
        mag[i] = bd.getFloat32(off + 16, Endian.little);
        final r = bd.getUint8(off + 20);
        final g = bd.getUint8(off + 21);
        final b = bd.getUint8(off + 22);
        color[i] = (0xFF << 24) | (r << 16) | (g << 8) | b;
        off += 24;
      }

      final named = <String, HygNamed>{};
      final rawNamed = await rootBundle.loadString('assets/stars/hyg_named.json');
      final list = jsonDecode(rawNamed) as List<dynamic>;
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        final name = m['n'] as String;
        named[name] = HygNamed(
          id: m['i'] as int,
          name: name,
          position: Vec3(
            (m['x'] as num).toDouble(),
            (m['y'] as num).toDouble(),
            (m['z'] as num).toDouble(),
          ),
          magnitude: (m['m'] as num).toDouble(),
          color: m['c'] as int,
        );
      }

      _cache = HygStars(
        count: count,
        starId: starId,
        xyz: xyz,
        mag: mag,
        color: color,
        named: named,
        indexById: indexById,
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
