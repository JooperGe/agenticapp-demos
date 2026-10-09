import 'package:flutter_test/flutter_test.dart';
import 'package:urbanrun/game/model/geometry.dart';
import 'package:urbanrun/game/projection/iso_projection.dart';

void main() {
  test('projection round trips ground coordinates', () {
    final projection = IsoProjection();
    final input = Point2(3.25, -1.5);
    final actual = projection.screenToWorld(projection.worldToScreen(input));
    expect(actual.x, closeTo(input.x, 1e-9));
    expect(actual.y, closeTo(input.y, 1e-9));
  });
}
