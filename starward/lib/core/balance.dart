import 'dart:math' as math;

/// Central game-balance configuration.
///
/// Every tunable number lives here so balancing never means hunting through
/// UI code. These are MVP test values, not final economy numbers.
class Balance {
  Balance._();

  /// Starting energy for a fresh save.
  static const int initialEnergy = 300;

  /// Travel cost and pacing scale linearly with distance (light-years) — no
  /// tiers — so a short hop is quick and cheap while a long haul is neither.
  static const double energyPerLy = 2.5;
  static const double travelSecondsPerLy = 37.5;

  /// Floors so even a jump to a close neighbour still takes a beat and costs a
  /// little, and never resolves to 0 s / 0 EN.
  static const int minEnergyCost = 1;
  static const int minTravelSeconds = 15;

  /// A small bonus granted the first time a planet is fully explored.
  static const int explorationReward = 15;
}

/// Energy required to travel [distanceLy] light-years (linear in distance).
int energyCostForDistance(double distanceLy) => math.max(
    Balance.minEnergyCost, (distanceLy * Balance.energyPerLy).round());

/// Flight time for [distanceLy] light-years (linear in distance).
int travelSecondsForDistance(double distanceLy) => math.max(
    Balance.minTravelSeconds,
    (distanceLy * Balance.travelSecondsPerLy).round());
