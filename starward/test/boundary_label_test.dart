import 'package:flutter_test/flutter_test.dart';
import 'package:starward/ui/galaxy3d/galaxy_map_3d_page.dart';

/// `boundaryLabel` formats the ship's distance from the universe boundary for
/// the overview readout. It was pulled out of the private `_OverviewReadout`
/// widget precisely so the 「壳外」 branch can be pinned here with concrete
/// numbers.
///
/// The radius used below is a **sample**, not the production value — the
/// formatter is pure arithmetic and these tests care about which branch it
/// takes. That distinction matters more than it used to: since the shell became
/// the catalogue's bounding radius (2026-10-13), no star-spawned ship can sit
/// outside it, so 「壳外」 is now reachable only when the catalogue is empty
/// (radius 0) or if that invariant is ever broken — which is exactly why the
/// branch stays.
void main() {
  test('inside the shell reads as the remaining distance', () {
    // 3066 − 1000 = 2066 ly to the boundary.
    expect(boundaryLabel(3066, 1000), '2066 ly');
  });

  test('exactly on the boundary reads as zero, not as 「壳外」', () {
    // toEdge == 0 takes the non-negative branch: a ship on the surface is not
    // outside it. Sub-1 ly keeps two decimals, hence "0.00".
    expect(boundaryLabel(3066, 3066), '0.00 ly');
  });

  test('outside the shell reads as 「壳外 X ly」', () {
    // 3400 is 334 ly beyond a 3066 radius.
    expect(boundaryLabel(3066, 3400), '壳外 334 ly');
  });

  test('a sub-light-year margin keeps two decimals', () {
    expect(boundaryLabel(3066, 3065.4), '0.60 ly');
  });
}
