import 'dart:convert';
import 'dart:typed_data';

import '../core/vec3.dart';

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

/// A star catalogue loaded into packed typed arrays. Positions are kept
/// in flat [Float32List]s (not Vec3 objects) so the renderer can iterate
/// ~109k stars per frame without allocating.
///
/// Pure Dart — no Flutter imports — so build-time tools can build one with
/// exactly the same code path the app uses to parse one.
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

  /// Parses the compact catalogue binary (as written by the build tools):
  /// little-endian Int32 count, then per star a 24-byte record —
  /// Int32 id, f32 x/y/z (light-years), f32 mag, u8 r/g/b, u8 named-flag.
  static HygStars fromBinary(ByteData bd) {
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
    return HygStars(
      count: count,
      starId: starId,
      xyz: xyz,
      mag: mag,
      color: color,
      named: const <String, HygNamed>{},
      indexById: indexById,
    );
  }

  /// Parses the named-star JSON sidecar: [{"n":name,"i":id,"x":,"y":,"z":,"m":mag,"c":argb}].
  static Map<String, HygNamed> namedFromJson(String raw) {
    final named = <String, HygNamed>{};
    final list = jsonDecode(raw) as List<dynamic>;
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
    return named;
  }

  /// Serialises the packed arrays to the compact catalogue binary. The inverse
  /// of [fromBinary]; used by the build tools so app and tool share one format.
  ByteData toBinary() {
    final bytes = BytesBuilder();
    final head = ByteData(4)..setInt32(0, count, Endian.little);
    bytes.add(head.buffer.asUint8List());
    final rec = ByteData(24);
    for (var i = 0; i < count; i++) {
      final c = color[i];
      rec
        ..setInt32(0, starId[i], Endian.little)
        ..setFloat32(4, xyz[i * 3], Endian.little)
        ..setFloat32(8, xyz[i * 3 + 1], Endian.little)
        ..setFloat32(12, xyz[i * 3 + 2], Endian.little)
        ..setFloat32(16, mag[i], Endian.little)
        ..setUint8(20, (c >> 16) & 0xFF)
        ..setUint8(21, (c >> 8) & 0xFF)
        ..setUint8(22, c & 0xFF)
        ..setUint8(23, 0);
      bytes.add(rec.buffer.asUint8List());
    }
    return ByteData.sublistView(bytes.toBytes());
  }
}
