/// Central game-balance configuration.
///
/// Every tunable number lives here so balancing never means hunting through
/// UI code. These are MVP test values, not final economy numbers.
class Balance {
  Balance._();

  /// Starting energy for a fresh save.
  static const int initialEnergy = 300;

  /// Energy cost per travel tier.
  static const int shortTripCost = 20;
  static const int midTripCost = 50;
  static const int longTripCost = 100;

  /// A small bonus granted the first time a planet is fully explored.
  static const int explorationReward = 15;

  /// Test-mode travel durations (seconds). Deliberately short so a new player
  /// reaches a destination within minutes — NOT the final live pacing.
  static const int shortTripSeconds = 90; // ~1.5 min
  static const int midTripSeconds = 420; // 7 min
  static const int longTripSeconds = 1500; // 25 min

  /// Distance thresholds (in light-years) that map a journey to a tier. Short
  /// hops stay within a star system / immediate neighbours; long hauls cross
  /// to farther systems.
  static const double midTripDistance = 12;
  static const double longTripDistance = 40;
}

/// The three travel tiers derived from map distance.
enum TravelTier { short, mid, long }

TravelTier tierForDistance(double distance) {
  if (distance >= Balance.longTripDistance) return TravelTier.long;
  if (distance >= Balance.midTripDistance) return TravelTier.mid;
  return TravelTier.short;
}

int energyCostForTier(TravelTier tier) {
  switch (tier) {
    case TravelTier.short:
      return Balance.shortTripCost;
    case TravelTier.mid:
      return Balance.midTripCost;
    case TravelTier.long:
      return Balance.longTripCost;
  }
}

int travelSecondsForTier(TravelTier tier) {
  switch (tier) {
    case TravelTier.short:
      return Balance.shortTripSeconds;
    case TravelTier.mid:
      return Balance.midTripSeconds;
    case TravelTier.long:
      return Balance.longTripSeconds;
  }
}
