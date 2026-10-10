import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/hyg_catalog.dart';

/// Confirms the full HYG binary asset loads and parses correctly through the
/// runtime loader (not just the build tool).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('HYG catalogue loads with the full star count and named index', () async {
    final hyg = await HygCatalog.load();
    expect(hyg, isNotNull);
    // ~109k stars after dropping unknown-distance entries.
    expect(hyg!.count, greaterThan(100000));
    expect(hyg.xyz.length, hyg.count * 3);
    expect(hyg.mag.length, hyg.count);

    // Brightest-first ordering → the Sun (mag -26.7) is first.
    expect(hyg.mag[0], lessThan(-20));

    // Named index resolves real landmark stars used for hero anchoring.
    expect(hyg.named.containsKey('Sol'), isTrue);
    expect(hyg.positionOf('Sirius'), isNotNull);
    expect(hyg.positionOf('Vega'), isNotNull);
  });
}
