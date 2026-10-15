import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/star_set.dart';
import 'package:starward/data/synthetic_galaxy.dart';

/// Confirms the bundled SG-1 / SG-2 data files parse and carry exactly the
/// stars the in-app generator (`SyntheticGalaxy.all`) produces — same ids, in
/// the same order, with the same positions and colours. The ids are the durable
/// keys behind saved destinations (`star:<id>`), so any drift here silently
/// repoints old saves; this test is the tripwire.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<HygStars> readOne(String file) async {
    final bin = await rootBundle.load('assets/stars/$file.bin');
    final stars = HygStars.fromBinary(bin.buffer.asByteData());
    final raw = await rootBundle.loadString('assets/stars/${file}_named.json');
    // parsed files have an empty const named map — swap in a mutable copy.
    final named = HygStars.namedFromJson(raw);
    return HygStars(
      count: stars.count,
      starId: stars.starId,
      xyz: stars.xyz,
      mag: stars.mag,
      color: stars.color,
      named: named,
      indexById: stars.indexById,
    );
  }

  void expectSameStars(HygStars a, HygStars b, String label) {
    expect(a.count, b.count, reason: '$label star count drifted');
    for (var i = 0; i < a.count; i++) {
      expect(a.starId[i], b.starId[i], reason: '$label starId[$i] drifted');
      expect(a.xyz[i * 3], b.xyz[i * 3], reason: '$label x[$i] drifted');
      expect(a.xyz[i * 3 + 1], b.xyz[i * 3 + 1], reason: '$label y[$i] drifted');
      expect(a.xyz[i * 3 + 2], b.xyz[i * 3 + 2], reason: '$label z[$i] drifted');
      expect(a.mag[i], b.mag[i], reason: '$label mag[$i] drifted');
      expect(a.color[i], b.color[i], reason: '$label color[$i] drifted');
    }
    for (final entry in a.named.entries) {
      expect(b.named[entry.key], isNotNull, reason: '$label lost "${entry.key}"');
    }
  }

  test('sg1.bin matches the in-app generator exactly', () async {
    final fromFile = await readOne('sg1');
    final generated = SyntheticGalaxy.all()[0];
    expectSameStars(fromFile, generated, 'SG-1');
  });

  test('sg2.bin matches the in-app generator exactly', () async {
    final fromFile = await readOne('sg2');
    final generated = SyntheticGalaxy.all()[1];
    expectSameStars(fromFile, generated, 'SG-2');
  });

  test('the parsed files keep the reserved id ranges', () async {
    final sg1 = await readOne('sg1');
    final sg2 = await readOne('sg2');
    expect(sg1.starId.first, greaterThanOrEqualTo(SyntheticGalaxy.idBase));
    expect(sg2.starId.first, greaterThanOrEqualTo(20000000));
    expect(sg1.count + sg2.count, 11200);
    // The named sidecar holds each galaxy's core, and lookups resolve it.
    expect(sg1.named['螺旋星系 SG-1'], isNotNull);
    expect(sg2.named['星系 SG-2'], isNotNull);
    expect(sg1.positionOfId(sg1.named['螺旋星系 SG-1']!.id), isNotNull);
  });

  test('round-trip through HygStars.toBinary is byte-stable', () {
    final generated = SyntheticGalaxy.all()[0];
    final back = HygStars.fromBinary(generated.toBinary());
    final a = Uint8List.sublistView(generated.toBinary());
    final b = Uint8List.sublistView(back.toBinary());
    expect(a, b);
  });

  test('the checked-in assets are current with the build tool', () {
    // Guards against editing the generator parameters without re-running
    // tool/build_synthetic_galaxies.dart: the tool's output must be a
    // byte-identical regeneration of what's committed.
    for (final file in ['sg1', 'sg2']) {
      final bin = File('assets/stars/$file.bin');
      expect(bin.existsSync(), isTrue, reason: '$file.bin missing — run the tool');
      final json = File('assets/stars/${file}_named.json');
      expect(json.existsSync(), isTrue,
          reason: '${file}_named.json missing — run the tool');
      final parsed = HygStars.fromBinary(
          ByteData.sublistView(bin.readAsBytesSync()));
      final namedList = jsonDecode(json.readAsStringSync()) as List<dynamic>;
      expect(namedList.length, 1,
          reason: '$file sidecar holds exactly the galaxy core');
      final core = namedList.first as Map<String, dynamic>;
      expect(core['i'], parsed.starId[0], reason: '$file sidecar id');
      expect((core['n'] as String), isNotEmpty);
    }
  });
}
