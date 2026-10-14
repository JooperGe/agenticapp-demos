import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/models/energy_transaction.dart';
import 'package:starward/data/models/journey.dart';
import 'package:starward/data/models/player_state.dart';

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
        reason: 'the enum is exactly these seven kinds — an eighth needs its '
            'own save migration',
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

  group('PlayerState cruise fields', () {
    PlayerState parked() => PlayerState.deepSpaceStart(
          energy: 300,
          startCoordX: 0,
          startCoordY: 0,
          startX: 1,
          startY: 2,
          startZ: 3,
          createdAt: DateTime(2026),
        );

    test('a fresh player is parked, awake, and would halt on an empty tank', () {
      final p = parked();
      expect(p.driftPowered, isFalse);
      expect(p.engineDormant, isFalse);
      expect(p.cruisePolicy, FuelPolicy.halt);
    });

    test('the three fields survive a save round trip', () {
      final p = parked().copyWith(
        driftPowered: true,
        engineDormant: true,
        cruisePolicy: FuelPolicy.coast,
      );
      final back = PlayerState.fromJson(p.toJson());
      expect(back.driftPowered, isTrue);
      expect(back.engineDormant, isTrue);
      expect(back.cruisePolicy, FuelPolicy.coast);
    });

    test('an old save with none of the keys loads as parked and awake', () {
      // The migration that matters: every save written before this feature has
      // no drift at all, so "not powered, not dormant" is not a guess — it is
      // the only reading that leaves those saves behaving as they always did.
      final json = parked().toJson()
        ..remove('driftPowered')
        ..remove('engineDormant')
        ..remove('cruisePolicy');
      final back = PlayerState.fromJson(json);
      expect(back.driftPowered, isFalse);
      expect(back.engineDormant, isFalse);
      expect(back.cruisePolicy, FuelPolicy.halt);
    });

    test('copyWith leaves the new fields alone unless asked', () {
      final p = parked().copyWith(
        driftPowered: true,
        engineDormant: true,
        cruisePolicy: FuelPolicy.coast,
      );
      final energyOnly = p.copyWith(energyBalance: 42);
      expect(energyOnly.driftPowered, isTrue);
      expect(energyOnly.engineDormant, isTrue);
      expect(energyOnly.cruisePolicy, FuelPolicy.coast);
    });
  });
}
