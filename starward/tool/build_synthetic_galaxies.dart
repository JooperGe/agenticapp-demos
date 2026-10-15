// Build-time tool (NOT shipped in the app): materialises the synthetic
// galaxies (SG-1 / SG-2) into the same asset format as the HYG catalogue, so
// they ship as data files instead of being regenerated from parameters at
// every launch.
//
// The generation code is the app's own `SyntheticGalaxy.build`, run with the
// exact parameters `SyntheticGalaxy.all()` uses — so the written star ids are
// bit-identical to what the in-app generator produced, and every saved
// destination (`star:<id>`) stays valid with no migration.
//
// Usage (from starward/):
//   dart run tool/build_synthetic_galaxies.dart
//
// Output (written to assets/stars/):
//   sg1.bin / sg2.bin        — same 24-byte-record format as hyg.bin
//   sg1_named.json / sg2_named.json — one entry: the galaxy's core "star",
//     which the renderer labels and the lookups treat as the named anchor.
import 'dart:convert';
import 'dart:io';

import 'package:starward/core/vec3.dart';
import 'package:starward/data/star_set.dart';
import 'package:starward/data/synthetic_galaxy.dart';

void main() {
  final galaxies = <String, HygStars>{
    'sg1': SyntheticGalaxy.build(),
    'sg2': SyntheticGalaxy.build(
      center: const Vec3(-0.58, 0.66, -0.48).normalized * 3400,
      normal: const Vec3(0.75, 0.35, 0.55).normalized,
      diskRadius: 620,
      count: 6000,
      seed: 909090,
      idBase: 20000000,
      name: '星系 SG-2',
      coreColor: 0xFFFFC29A,
      reddish: true,
    ),
  };

  for (final MapEntry(key: file, value: galaxy) in galaxies.entries) {
    final named = galaxy.named.values
        .map((n) => <String, dynamic>{
              'i': n.id,
              'n': n.name,
              'x': n.position.x,
              'y': n.position.y,
              'z': n.position.z,
              'm': n.magnitude,
              'c': n.color,
            })
        .toList();

    Directory('assets/stars').createSync(recursive: true);
    File('assets/stars/$file.bin')
        .writeAsBytesSync(galaxy.toBinary().buffer.asUint8List());
    File('assets/stars/${file}_named.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(named));
    stdout.writeln(
        '$file: ${galaxy.count} stars, ids ${galaxy.starId.first}–${galaxy.starId.last}, '
        'core "${named.first['n']}".');
  }
}
