import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/models/journey.dart';

/// A voyage that departs 12:00 and arrives 12:10, quoting 100 EN.
Journey _tenMinuteVoyage() => Journey(
      id: 'jny-1',
      originPlanetId: 'a',
      destinationPlanetId: 'b',
      departure: DateTime(2026, 1, 1, 12),
      arrival: DateTime(2026, 1, 1, 12, 10),
      energyCost: 100,
      status: JourneyStatus.inProgress,
    );

DateTime _at(int minute) => DateTime(2026, 1, 1, 12, minute);

void main() {
  group('Journey.burnedAt', () {
    test('burns in proportion to distance covered', () {
      final j = _tenMinuteVoyage();
      expect(j.burnedAt(_at(0)), 0);
      expect(j.burnedAt(_at(2)), 20);
      expect(j.burnedAt(_at(5)), 50);
      expect(j.burnedAt(_at(10)), 100);
    });

    test('never over-burns past arrival', () {
      final j = _tenMinuteVoyage();
      // A voyage reconciled an hour late must not bill more than it quoted.
      expect(j.burnedAt(_at(70)), 100);
    });

    test('never burns before departure', () {
      final j = _tenMinuteVoyage();
      expect(j.burnedAt(DateTime(2026, 1, 1, 11, 30)), 0);
    });
  });
}
