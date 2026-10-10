import 'dart:math' as math;

import '../core/vec3.dart';

/// A real star placed by its true position. Coordinates are the standard
/// equatorial-to-Cartesian conversion with the Sun at the origin, so the
/// backdrop genuinely matches our stellar neighbourhood rather than being
/// decorative noise.
class CatalogStar {
  const CatalogStar({
    required this.name,
    required this.position,
    required this.distanceLy,
    required this.magnitude,
    required this.color,
    this.isSun = false,
  });

  final String name;

  /// Position in light-years, Sun at origin.
  final Vec3 position;
  final double distanceLy;

  /// Apparent visual magnitude (smaller = brighter).
  final double magnitude;
  final int color;
  final bool isSun;
}

/// Equatorial (RA hours, Dec degrees, distance ly) → Cartesian ly.
Vec3 _equatorialToCartesian(double raHours, double decDeg, double distLy) {
  final ra = raHours * 15 * math.pi / 180; // 1h = 15°
  final dec = decDeg * math.pi / 180;
  final cosDec = math.cos(dec);
  return Vec3(
    distLy * cosDec * math.cos(ra),
    distLy * math.sin(dec), // galactic "up" = celestial north here
    distLy * cosDec * math.sin(ra),
  );
}

class _Raw {
  const _Raw(this.name, this.ra, this.dec, this.dist, this.mag, this.color);
  final String name;
  final double ra;
  final double dec;
  final double dist;
  final double mag;
  final int color;
}

/// Curated catalogue of real stars within ~37 ly (plus the Sun). Values are
/// approximate published RA/Dec/distance/magnitude — enough to make the sky
/// recognisable (Sirius, Alpha Centauri, Vega, Altair, Arcturus…). Distant
/// landmark stars can be appended later without touching the pipeline.
const List<_Raw> _rawCatalog = <_Raw>[
  _Raw('太阳 Sol', 0, 0, 0.0, -26.7, 0xFFFFE9B0),
  _Raw('比邻星 Proxima Cen', 14.496, -62.68, 4.24, 11.1, 0xFFFF9966),
  _Raw('南门二 A Alpha Cen A', 14.66, -60.83, 4.37, -0.01, 0xFFFFF2C8),
  _Raw('南门二 B Alpha Cen B', 14.66, -60.84, 4.37, 1.33, 0xFFFFC87A),
  _Raw('巴纳德星 Barnard', 17.963, 4.69, 5.96, 9.5, 0xFFFF8A5C),
  _Raw('沃夫359 Wolf 359', 10.94, 7.01, 7.86, 13.5, 0xFFFF7A4A),
  _Raw('拉兰德21185', 11.06, 35.97, 8.31, 7.5, 0xFFFF9A66),
  _Raw('天狼星 Sirius', 6.752, -16.72, 8.60, -1.46, 0xFFB8D4FF),
  _Raw('鲁坦726-8', 1.656, -17.95, 8.73, 12.0, 0xFFFF8050),
  _Raw('罗斯154 Ross 154', 18.83, -23.84, 9.69, 10.4, 0xFFFF8A5C),
  _Raw('罗斯248 Ross 248', 23.69, 44.18, 10.3, 12.3, 0xFFFF8050),
  _Raw('天苑四 Epsilon Eri', 3.548, -9.46, 10.50, 3.73, 0xFFFFC27A),
  _Raw('拉卡伊9352', 23.09, -35.85, 10.70, 7.34, 0xFFFF9A66),
  _Raw('罗斯128 Ross 128', 11.80, 0.80, 11.0, 11.1, 0xFFFF8050),
  _Raw('南河三 Procyon', 7.655, 5.22, 11.46, 0.34, 0xFFF2F0E0),
  _Raw('天津增廿九 61 Cyg A', 21.07, 38.75, 11.40, 5.2, 0xFFFFB070),
  _Raw('天仓五 Tau Ceti', 1.734, -15.94, 11.90, 3.5, 0xFFFFE6A0),
  _Raw('印第安人 Epsilon Ind', 22.03, -56.79, 11.90, 4.7, 0xFFFFC27A),
  _Raw('卡普坦星 Kapteyn', 5.19, -45.0, 12.8, 8.9, 0xFFFF9A66),
  _Raw('克鲁格60 Kruger 60', 22.47, 57.70, 13.1, 9.8, 0xFFFF8A5C),
  _Raw('沃夫1061 Wolf 1061', 16.50, -12.66, 14.0, 10.1, 0xFFFF8A5C),
  _Raw('格利泽1 Gliese 1', 0.05, -37.36, 14.2, 8.5, 0xFFFFA870),
  _Raw('天鹰座牛郎星 Altair', 19.846, 8.87, 16.70, 0.77, 0xFFEAF0FF),
  _Raw('天苑增三 40 Eri', 4.25, -7.65, 16.3, 4.43, 0xFFFFD28A),
  _Raw('侯 70 Oph', 18.09, 2.5, 16.6, 4.0, 0xFFFFC27A),
  _Raw('天棓增一 Sigma Dra', 19.53, 69.66, 18.8, 4.7, 0xFFFFE6A0),
  _Raw('王良三 Eta Cas', 0.82, 57.82, 19.4, 3.44, 0xFFFFF0CF),
  _Raw('织女星 Vega', 18.615, 38.78, 25.0, 0.03, 0xFFC8DBFF),
  _Raw('北落师门 Fomalhaut', 22.96, -29.62, 25.1, 1.16, 0xFFDCE6FF),
  _Raw('北河三 Pollux', 7.755, 28.03, 33.8, 1.14, 0xFFFFCC8A),
  _Raw('大角星 Arcturus', 14.26, 19.18, 36.7, -0.05, 0xFFFFB766),
  _Raw('五帝座一 Denebola', 11.82, 14.57, 36.0, 2.14, 0xFFEAF0FF),
];

class StarCatalog {
  StarCatalog._();

  static List<CatalogStar> build() {
    return <CatalogStar>[
      for (final r in _rawCatalog)
        CatalogStar(
          name: r.name,
          position: _equatorialToCartesian(r.ra, r.dec, r.dist),
          distanceLy: r.dist,
          magnitude: r.mag,
          color: r.color,
          isSun: r.dist == 0,
        ),
    ];
  }

  /// Looks up a real star's position by name fragment — used to anchor the
  /// game's hero planets to real systems.
  static Vec3 positionOf(String nameFragment) {
    final r = _rawCatalog.firstWhere(
      (e) => e.name.contains(nameFragment),
      orElse: () => _rawCatalog.first,
    );
    return _equatorialToCartesian(r.ra, r.dec, r.dist);
  }
}
