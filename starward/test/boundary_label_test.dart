import 'package:flutter_test/flutter_test.dart';
import 'package:starward/ui/galaxy3d/galaxy_map_3d_page.dart';

/// `boundaryLabel` formats the ship's distance from the universe boundary for
/// the overview readout. It was pulled out of the private `_OverviewReadout`
/// widget precisely so the 「壳外」 branch — legal but not the default, so the
/// widget test never reaches it — can be pinned here with concrete numbers.
void main() {
  test('inside the shell reads as the remaining distance', () {
    // R = 3066 ly, ship 1000 ly from the centre → 2066 ly to the boundary.
    expect(boundaryLabel(3066, 1000), '2066 ly');
  });

  test('exactly on the boundary reads as zero, not as 「壳外」', () {
    // toEdge == 0 takes the non-negative branch: a ship on the surface is not
    // outside it. Sub-1 ly keeps two decimals, hence "0.00".
    expect(boundaryLabel(3066, 3066), '0.00 ly');
  });

  test('outside the shell reads as 「壳外 X ly」', () {
    // SG-2 sits at 3400 ly, beyond R = 3066 → 334 ly outside the boundary.
    expect(boundaryLabel(3066, 3400), '壳外 334 ly');
  });

  test('a sub-light-year margin keeps two decimals', () {
    expect(boundaryLabel(3066, 3065.4), '0.60 ly');
  });
}
