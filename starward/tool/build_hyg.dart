// Build-time tool (NOT shipped in the app): converts the full HYG v41 CSV into
// a compact binary the app can load fast and small.
//
// Usage:
//   dart run tool/build_hyg.dart /tmp/hygdata_v41.csv
//
// Output (written to assets/stars/):
//   hyg.bin        — Int32 count, then per star 20 bytes:
//                    f32 x,y,z (light-years, NCP-up), f32 mag, u8 r,g,b, u8 named
//                    Stars are sorted brightest-first so the renderer can draw
//                    the brightest N and stop.
//   hyg_named.json — [{"n":name,"x":,"y":,"z":,"m":mag,"c":argb}] for stars with
//                    a proper name (labels + hero-planet anchoring).
//
// Data: HYG database (Hipparcos/Yale/Gliese), © David Nash / Astronexus,
// CC BY-SA 4.0 — github.com/astronexus/HYG-Database.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const double _pcToLy = 3.2615638;

void main(List<String> args) {
  final input = args.isNotEmpty ? args[0] : '/tmp/hygdata_v41.csv';
  final lines = File(input).readAsLinesSync();
  final header = _splitCsv(lines.first);
  int col(String name) => header.indexOf(name);
  final iId = col('id');
  final iX = col('x'), iY = col('y'), iZ = col('z');
  final iMag = col('mag'), iCi = col('ci'), iProper = col('proper');
  final iDist = col('dist');

  final records = <_Star>[];
  for (var li = 1; li < lines.length; li++) {
    final line = lines[li];
    if (line.isEmpty) continue;
    final f = _splitCsv(line);
    final dist = double.tryParse(f[iDist]) ?? 1e9;
    // HYG uses dist = 100000 for stars with no known parallax — drop them.
    if (dist >= 100000) continue;

    // HYG is equatorial parsecs: X→(RA0,Dec0), Y→(RA6h), Z→NCP.
    // Our engine wants Y = up = NCP, so swap Y/Z and convert to light-years.
    final hx = double.tryParse(f[iX]) ?? 0;
    final hy = double.tryParse(f[iY]) ?? 0;
    final hz = double.tryParse(f[iZ]) ?? 0;
    final x = hx * _pcToLy;
    final y = hz * _pcToLy; // NCP up
    final z = hy * _pcToLy;

    final id = int.tryParse(f[iId]) ?? -1;
    final mag = double.tryParse(f[iMag]) ?? 15.0;
    final ci = double.tryParse(f[iCi]);
    final rgb = _ciToRgb(ci);
    final name = f[iProper].trim();

    records.add(_Star(id, x, y, z, mag, rgb, name));
  }

  // Brightest first so the renderer can cap the draw count by magnitude.
  records.sort((a, b) => a.mag.compareTo(b.mag));

  _writeBin(records);
  _writeNamed(records);

  final named = records.where((r) => r.name.isNotEmpty).length;
  stdout.writeln('HYG build complete: ${records.length} stars '
      '($named named). Brightest: ${records.first.name.isEmpty ? "?" : records.first.name} '
      '(mag ${records.first.mag}).');
}

class _Star {
  _Star(this.id, this.x, this.y, this.z, this.mag, this.rgb, this.name);
  final int id;
  final double x, y, z, mag;
  final List<int> rgb;
  final String name;
}

void _writeBin(List<_Star> records) {
  final count = records.length;
  final bytes = BytesBuilder();
  final head = ByteData(4)..setInt32(0, count, Endian.little);
  bytes.add(head.buffer.asUint8List());
  // 24-byte record: int32 hygId, f32 x,y,z,mag, u8 r,g,b, u8 named-flag.
  final rec = ByteData(24);
  for (final s in records) {
    rec
      ..setInt32(0, s.id, Endian.little)
      ..setFloat32(4, s.x, Endian.little)
      ..setFloat32(8, s.y, Endian.little)
      ..setFloat32(12, s.z, Endian.little)
      ..setFloat32(16, s.mag, Endian.little)
      ..setUint8(20, s.rgb[0])
      ..setUint8(21, s.rgb[1])
      ..setUint8(22, s.rgb[2])
      ..setUint8(23, s.name.isEmpty ? 0 : 1);
    bytes.add(rec.buffer.asUint8List());
  }
  Directory('assets/stars').createSync(recursive: true);
  File('assets/stars/hyg.bin').writeAsBytesSync(bytes.toBytes());
}

void _writeNamed(List<_Star> records) {
  final named = <Map<String, dynamic>>[];
  for (final s in records) {
    if (s.name.isEmpty) continue;
    final argb =
        (0xFF << 24) | (s.rgb[0] << 16) | (s.rgb[1] << 8) | s.rgb[2];
    named.add(<String, dynamic>{
      'i': s.id,
      'n': s.name,
      'x': double.parse(s.x.toStringAsFixed(3)),
      'y': double.parse(s.y.toStringAsFixed(3)),
      'z': double.parse(s.z.toStringAsFixed(3)),
      'm': double.parse(s.mag.toStringAsFixed(2)),
      'c': argb,
    });
  }
  File('assets/stars/hyg_named.json')
      .writeAsStringSync(jsonEncode(named));
}

/// Approximate B-V colour index → RGB. Piecewise but smooth enough to make hot
/// blue and cool red stars read correctly.
List<int> _ciToRgb(double? ci) {
  if (ci == null) return <int>[248, 247, 255];
  final bv = ci.clamp(-0.4, 2.0);
  if (bv < 0.0) return <int>[155, 176, 255];
  if (bv < 0.3) return <int>[202, 216, 255];
  if (bv < 0.6) return <int>[248, 247, 255];
  if (bv < 0.9) return <int>[255, 244, 214];
  if (bv < 1.3) return <int>[255, 210, 161];
  return <int>[255, 176, 125];
}

/// Minimal quote-aware CSV splitter. HYG's numeric columns are never quoted,
/// so this only needs to respect double-quoted text fields.
List<String> _splitCsv(String line) {
  final out = <String>[];
  final sb = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') {
      inQuotes = !inQuotes;
    } else if (c == ',' && !inQuotes) {
      out.add(sb.toString());
      sb.clear();
    } else {
      sb.write(c);
    }
  }
  out.add(sb.toString());
  return out;
}
