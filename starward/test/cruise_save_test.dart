import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/models/energy_transaction.dart';

void main() {
  group('EnergyTxType', () {
    test('a cruise, a turn and an activation are three separate kinds', () {
      // Not one "misc" bucket: the ledger is the only place a player can see
      // where the tank went, and "I cruised 200 ly" and "I turned 40 degrees"
      // are different answers to "why is it empty".
      expect(EnergyTxType.values, contains(EnergyTxType.cruiseCost));
      expect(EnergyTxType.values, contains(EnergyTxType.turn));
      expect(EnergyTxType.values, contains(EnergyTxType.activation));
      expect(
        <EnergyTxType>{
          EnergyTxType.travelCost,
          EnergyTxType.trainingReward,
          EnergyTxType.explorationReward,
          EnergyTxType.braking,
          EnergyTxType.cruiseCost,
          EnergyTxType.turn,
          EnergyTxType.activation,
        }.length,
        EnergyTxType.values.length,
        reason: 'no two kinds may share a name — the enum name is the save key',
      );
    });

    test('the new kinds survive a save round trip', () {
      for (final t in <EnergyTxType>[
        EnergyTxType.cruiseCost,
        EnergyTxType.turn,
        EnergyTxType.activation,
      ]) {
        expect(energyTxTypeFromName(t.name), t);
      }
    });

    test('an unknown name still falls back to travelCost', () {
      // The `orElse` is what lets an old build read a newer save.
      expect(energyTxTypeFromName('somethingNew'), EnergyTxType.travelCost);
    });
  });
}
