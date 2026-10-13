import 'dart:math' as math;

/// The ship's power source — the part that decides how much energy a voyage
/// burns and how long it takes.
///
/// Both numbers live here rather than in a global balance table because they
/// are properties *of the engine*: swapping the engine is how a voyage gets
/// cheaper or faster, and a refit should not have to reach into unrelated game
/// state to change them. A faster engine burning more energy per light-year
/// (or vice versa) is therefore expressible as data, not as a code change.
class Engine {
  const Engine({
    required this.id,
    required this.name,
    required this.energyPerLy,
    required this.travelSecondsPerLy,
    required this.brakingDistanceLy,
    required this.minEnergyCost,
    required this.minTravelSeconds,
  });

  final String id;
  final String name;

  /// Energy burned per light-year. Cost scales linearly with distance — no
  /// tiers — so a short hop is quick and cheap while a long haul is neither.
  final double energyPerLy;

  /// Seconds of flight per light-year.
  final double travelSecondsPerLy;

  /// Distance the engine needs to shed one cruise speed's worth of velocity.
  /// Braking from a full cruise burn costs what flying this far costs.
  ///
  /// A distance rather than a flat EN price, because "how much does this engine
  /// need to cancel its own speed" is a property of the engine — a refit that
  /// brakes harder should not have to also edit a global cost table.
  final double brakingDistanceLy;

  /// Floors so even a jump to a close neighbour still takes a beat and costs a
  /// little, and never resolves to 0 EN / 0 s.
  final int minEnergyCost;
  final int minTravelSeconds;

  /// Energy required to travel [distanceLy] light-years.
  int energyCostFor(double distanceLy) =>
      math.max(minEnergyCost, (distanceLy * energyPerLy).round());

  /// Flight time for [distanceLy] light-years.
  int secondsFor(double distanceLy) =>
      math.max(minTravelSeconds, (distanceLy * travelSecondsPerLy).round());

  /// How far [energy] will carry this engine, in light-years.
  ///
  /// The plain inverse of [energyPerLy]. This is the number the fuel-out dialog
  /// quotes back to the player ("you have 100 EN, that is 40.0 ly of the
  /// 100.0 ly trip"), so it lives on the engine rather than being recomputed
  /// wherever it is displayed.
  double reachableLyFor(int energy) => energy / energyPerLy;

  /// The speed a voyage settles at, in ly/s.
  double get cruiseSpeedLyPerSec => 1 / travelSecondsPerLy;

  /// Energy to shed [speedLyPerSec], in EN.
  ///
  /// Written as a ratio of the cruise speed rather than as a flat price so that
  /// a partly-spent drift is automatically cheaper, and so the rule still holds
  /// if a future engine's drift speed stops being constant.
  ///
  /// Zero for a ship already at rest — [energyCostFor] floors at
  /// [minEnergyCost], so without this guard a stationary ship would be quoted
  /// 1 EN to not move.
  int brakingCostFor(double speedLyPerSec) {
    if (speedLyPerSec <= 0) return 0;
    return energyCostFor(brakingDistanceLy * speedLyPerSec / cruiseSpeedLyPerSec);
  }

  /// The engine every new ship is fitted with.
  ///
  /// These are the numbers the game has always used, so a standard ship flies
  /// exactly as it did before engines became a modelled thing.
  static const Engine standard = Engine(
    id: 'engine.standard',
    name: '标准聚变引擎',
    energyPerLy: 2.5,
    travelSecondsPerLy: 37.5,
    brakingDistanceLy: 40,
    minEnergyCost: 1,
    minTravelSeconds: 15,
  );

  factory Engine.fromJson(Map<String, dynamic> json) => Engine(
        id: json['id'] as String,
        name: json['name'] as String,
        energyPerLy: (json['energyPerLy'] as num).toDouble(),
        travelSecondsPerLy: (json['travelSecondsPerLy'] as num).toDouble(),
        // Saves written after the engine refactor carry a `ship.engine` object
        // with no `brakingDistanceLy`; reading it with `as double` would throw
        // and cost the player their game. Fall back rather than bump the key.
        brakingDistanceLy: (json['brakingDistanceLy'] as num?)?.toDouble() ??
            Engine.standard.brakingDistanceLy,
        minEnergyCost: json['minEnergyCost'] as int,
        minTravelSeconds: json['minTravelSeconds'] as int,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'energyPerLy': energyPerLy,
        'travelSecondsPerLy': travelSecondsPerLy,
        'brakingDistanceLy': brakingDistanceLy,
        'minEnergyCost': minEnergyCost,
        'minTravelSeconds': minTravelSeconds,
      };
}
