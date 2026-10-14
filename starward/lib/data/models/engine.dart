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
    required this.cruiseSpeedLyPerSec,
    required this.brakingDistanceLy,
    required this.minEnergyCost,
    required this.minTravelSeconds,
    required this.activationCost,
  });

  final String id;
  final String name;

  /// Energy burned per light-year. Cost scales linearly with distance — no
  /// tiers — so a short hop is quick and cheap while a long haul is neither.
  final double energyPerLy;

  /// The speed a voyage settles at, in ly/s.
  ///
  /// Speed rather than pace (seconds per light-year) because speed is what the
  /// rest of the game reasons about: a drift continues at it, and the braking
  /// quote is a ratio of it. Storing one of the two and deriving the other —
  /// rather than recovering speed from `distance / duration` at each use — is
  /// what keeps the braking quote exactly constant. A duration is rounded to
  /// whole seconds, so a speed recovered from it would differ from route to
  /// route and drag the quote along with it.
  final double cruiseSpeedLyPerSec;

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

  /// What it costs to bring the engine back online after the tank ran dry and
  /// it shut itself down. A flat fee, not a function of anything: the point is
  /// that recovery has a price, not that it scales.
  final int activationCost;

  /// Energy required to travel [distanceLy] light-years.
  int energyCostFor(double distanceLy) =>
      math.max(minEnergyCost, (distanceLy * energyPerLy).round());

  /// Flight time for [distanceLy] light-years.
  int secondsFor(double distanceLy) =>
      math.max(minTravelSeconds, (distanceLy / cruiseSpeedLyPerSec).round());

  /// How far [energy] will carry this engine, in light-years.
  ///
  /// The plain inverse of [energyPerLy]. This is the number the fuel-out dialog
  /// quotes back to the player ("you have 100 EN, that is 40.0 ly of the
  /// 100.0 ly trip"), so it lives on the engine rather than being recomputed
  /// wherever it is displayed.
  double reachableLyFor(int energy) => energy / energyPerLy;

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

  /// Energy the engine spends per second of powered cruise.
  ///
  /// The ship's life support and electrical systems run off the same tank, so a
  /// cruise burns continuously rather than only at ignition. Derived from the
  /// two fields above so a cruise and a voyage can never disagree about how
  /// fast the tank drains.
  double get powerDrawPerSecond => energyPerLy * cruiseSpeedLyPerSec;

  /// Energy burned by [seconds] of powered cruise.
  ///
  /// Deliberately shaped like [energyCostFor] — including its `minEnergyCost`
  /// floor — because it *is* that quote: `seconds * cruiseSpeed` is the distance
  /// covered, so the two can never drift apart.
  int burnForSeconds(double seconds) =>
      energyCostFor(seconds * cruiseSpeedLyPerSec);

  /// How many seconds [energy] buys.
  ///
  /// The inverse of [burnForSeconds] on the quantised scale, and the form the
  /// exhaustion check has to use: comparing `burnForSeconds(elapsed) >= budget`
  /// fires a tick early, because EN is rounded to whole units. Division keeps it
  /// exact — `secondsForEnergy(200)` is 3000.0, not 3000.0000000000005.
  double secondsForEnergy(int energy) => energy / powerDrawPerSecond;

  /// Energy to swing the heading by [radians] while under way.
  ///
  /// Physically this is a Δv burn: at speed `v`, turning by θ changes the
  /// velocity vector by `2 v sin(θ/2)`. Priced through [energyCostFor] so a turn
  /// is quoted on the same scale as the distance it costs, which is what makes
  /// 60° cost exactly what braking costs.
  int turnCostFor(double radians) {
    if (radians <= 0) return 0;
    final deltaV = 2 * cruiseSpeedLyPerSec * math.sin(radians / 2);
    return energyCostFor(brakingDistanceLy * deltaV / cruiseSpeedLyPerSec);
  }

  /// The engine every new ship is fitted with.
  ///
  /// These are the numbers the game has always used, so a standard ship flies
  /// exactly as it did before engines became a modelled thing.
  static const Engine standard = Engine(
    id: 'engine.standard',
    name: '标准聚变引擎',
    energyPerLy: 2.5,
    cruiseSpeedLyPerSec: 1 / 37.5,
    brakingDistanceLy: 40,
    minEnergyCost: 1,
    minTravelSeconds: 15,
    activationCost: 5,
  );

  factory Engine.fromJson(Map<String, dynamic> json) => Engine(
        id: json['id'] as String,
        name: json['name'] as String,
        energyPerLy: (json['energyPerLy'] as num).toDouble(),
        // Saves written before speed became a field carry `travelSecondsPerLy`
        // instead. Read the old key rather than bumping `_saveKey` and costing
        // the player their game.
        cruiseSpeedLyPerSec: (json['cruiseSpeedLyPerSec'] as num?)?.toDouble() ??
            1 / (json['travelSecondsPerLy'] as num).toDouble(),
        // Saves written after the engine refactor carry a `ship.engine` object
        // with no `brakingDistanceLy`; reading it with `as double` would throw
        // and cost the player their game. Fall back rather than bump the key.
        brakingDistanceLy: (json['brakingDistanceLy'] as num?)?.toDouble() ??
            Engine.standard.brakingDistanceLy,
        minEnergyCost: json['minEnergyCost'] as int,
        minTravelSeconds: json['minTravelSeconds'] as int,
        // Absent in saves written before the activation fee existed. The
        // standard fee is the only sensible reading: an engine that predates the
        // field is a standard engine.
        activationCost:
            (json['activationCost'] as num?)?.toInt() ?? Engine.standard.activationCost,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'energyPerLy': energyPerLy,
        'cruiseSpeedLyPerSec': cruiseSpeedLyPerSec,
        'brakingDistanceLy': brakingDistanceLy,
        'minEnergyCost': minEnergyCost,
        'minTravelSeconds': minTravelSeconds,
        'activationCost': activationCost,
      };
}
