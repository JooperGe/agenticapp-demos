/// Status of a journey.
///
/// [inProgress] — the ship is travelling. [arrived] — the ship has reached the
/// destination but the player has not yet explored it. [completed] — the
/// destination has been explored and the journey archived.
enum JourneyStatus { inProgress, arrived, completed }

JourneyStatus journeyStatusFromName(String name) =>
    JourneyStatus.values.firstWhere((s) => s.name == name,
        orElse: () => JourneyStatus.inProgress);

/// What happens when a voyage's fuel runs out before it reaches its
/// destination.
///
/// Chosen at launch rather than globally, because it is a decision about *this*
/// trip: the same ship may want to limp home on one voyage and gamble on
/// another.
enum FuelPolicy {
  /// Refuse to depart without enough energy for the whole trip.
  refuse,

  /// Burn out and stop, parked where the tank emptied.
  halt,

  /// Burn out and keep coasting at cruise speed.
  coast,
}

FuelPolicy fuelPolicyFromName(String name) => FuelPolicy.values
    .firstWhere((p) => p.name == name, orElse: () => FuelPolicy.halt);

/// A single voyage between two planets.
///
/// Progress is derived entirely from the departure/arrival timestamps, never
/// from a running timer — so travel continues while the app is backgrounded or
/// killed, and resumes correctly on relaunch.
class Journey {
  const Journey({
    required this.id,
    required this.originPlanetId,
    required this.destinationPlanetId,
    required this.departure,
    required this.arrival,
    required this.energyCost,
    required this.status,
    this.fuelPolicy = FuelPolicy.halt,
  });

  final String id;
  final String originPlanetId;
  final String destinationPlanetId;
  final DateTime departure;
  final DateTime arrival;
  final int energyCost;
  final JourneyStatus status;

  /// What to do if the tank runs dry en route. Defaults to [FuelPolicy.halt] so
  /// saves written before this existed — whose voyages were paid for in full
  /// and therefore can never exhaust — load without a special case.
  final FuelPolicy fuelPolicy;

  Duration get totalDuration => arrival.difference(departure);

  /// Travel progress in [0, 1] at [now], derived purely from timestamps.
  double progressAt(DateTime now) {
    final total = arrival.difference(departure).inMilliseconds;
    if (total <= 0) return 1;
    final elapsed = now.difference(departure).inMilliseconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  /// Remaining travel time at [now], never negative.
  Duration remainingAt(DateTime now) {
    final remaining = arrival.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Energy burned by [now], in EN — proportional to the distance covered.
  ///
  /// This is the whole of "real-time consumption": nothing is deducted at
  /// launch, the burn is re-derived from the timestamps every time it is asked
  /// for, so it survives the app being backgrounded or killed exactly like
  /// [progressAt] does. `progressAt` is clamped to [0, 1], so the result is
  /// always within `[0, energyCost]`.
  int burnedAt(DateTime now) => (energyCost * progressAt(now)).round();

  /// Whether the ship has physically reached the destination by [now],
  /// regardless of whether [status] has been reconciled yet.
  bool hasArrivedBy(DateTime now) => !now.isBefore(arrival);

  Journey copyWith({JourneyStatus? status, FuelPolicy? fuelPolicy}) => Journey(
        id: id,
        originPlanetId: originPlanetId,
        destinationPlanetId: destinationPlanetId,
        departure: departure,
        arrival: arrival,
        energyCost: energyCost,
        status: status ?? this.status,
        fuelPolicy: fuelPolicy ?? this.fuelPolicy,
      );

  factory Journey.fromJson(Map<String, dynamic> json) => Journey(
        id: json['id'] as String,
        originPlanetId: json['originPlanetId'] as String,
        destinationPlanetId: json['destinationPlanetId'] as String,
        departure:
            DateTime.fromMillisecondsSinceEpoch(json['departure'] as int),
        arrival: DateTime.fromMillisecondsSinceEpoch(json['arrival'] as int),
        energyCost: json['energyCost'] as int,
        status: journeyStatusFromName(json['status'] as String),
        fuelPolicy: json['fuelPolicy'] == null
            ? FuelPolicy.halt
            : fuelPolicyFromName(json['fuelPolicy'] as String),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'originPlanetId': originPlanetId,
        'destinationPlanetId': destinationPlanetId,
        'departure': departure.millisecondsSinceEpoch,
        'arrival': arrival.millisecondsSinceEpoch,
        'energyCost': energyCost,
        'status': status.name,
        'fuelPolicy': fuelPolicy.name,
      };
}
