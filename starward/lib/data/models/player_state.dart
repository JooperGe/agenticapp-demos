import '../../core/vec3.dart';
import 'journey.dart';

/// The player's mutable progress. Immutable value object — the controller
/// replaces it wholesale via [copyWith] so state transitions are explicit and
/// easy to reason about.
class PlayerState {
  const PlayerState({
    required this.energyBalance,
    required this.currentPlanetId,
    required this.discoveredPlanetIds,
    required this.exploredPlanetIds,
    required this.activeJourneyId,
    required this.createdAt,
    required this.startCoordX,
    required this.startCoordY,
    required this.startX,
    required this.startY,
    required this.startZ,
    required this.driftVelocity,
    required this.driftStartedAt,
    this.driftPowered = false,
    this.engineDormant = false,
    this.cruisePolicy = FuelPolicy.halt,
  });

  final int energyBalance;

  /// The planet the ship is currently at, or null when drifting in deep space
  /// (true for a brand-new save until the first arrival).
  final String? currentPlanetId;

  final Set<String> discoveredPlanetIds;
  final Set<String> exploredPlanetIds;
  final String? activeJourneyId;
  final DateTime createdAt;

  /// Deep-space start — the randomised position a new player wakes up at.
  /// [startCoordX/Y] are the 2D gameplay coordinates used for travel distance /
  /// energy while drifting; [startX/Y/Z] are the 3D light-year coordinates used
  /// to place the ship and camera in the galaxy view. Only meaningful while
  /// [currentPlanetId] is null.
  final double startCoordX;
  final double startCoordY;
  final double startX;
  final double startY;
  final double startZ;

  /// Deep-space drift. The ship's position while [currentPlanetId] is null is
  /// `startX/Y/Z` advanced by this velocity since [driftStartedAt] — see
  /// `GameController.playerPosition3D`.
  ///
  /// Zero velocity (the default for every save written before coasting
  /// existed) means the ship is parked: it sits at the anchor forever, which is
  /// exactly the static deep-space hover the game had before.
  final Vec3 driftVelocity;

  /// When [driftVelocity] started being applied. Only meaningful while
  /// [driftVelocity] is non-zero; the epoch default keeps a parked ship's
  /// arithmetic well away from any "you have been drifting for 56 years" bug.
  final DateTime driftStartedAt;

  /// True when the engine is driving the drift: the ship is cruising under power
  /// and the tank is draining. False on a coast, which is the same motion with
  /// the engine off.
  final bool driftPowered;

  /// True when the tank hit zero and the engine shut itself down. The ship still
  /// hovers or coasts — what stops is everything that needs a burn: igniting,
  /// turning, and launching a voyage.
  final bool engineDormant;

  /// What the player chose should happen when a *cruise* runs the tank dry.
  ///
  /// A cruise has no destination, so unlike a voyage's policy this cannot live
  /// on a `Journey` — it has to survive on the player, because the choice is
  /// made at ignition and acted on arbitrarily later.
  final FuelPolicy cruisePolicy;

  bool get inDeepSpace => currentPlanetId == null;

  PlayerState copyWith({
    int? energyBalance,
    String? currentPlanetId,
    Set<String>? discoveredPlanetIds,
    Set<String>? exploredPlanetIds,
    String? activeJourneyId,
    bool clearActiveJourney = false,
    double? startX,
    double? startY,
    double? startZ,
    bool toDeepSpace = false,
    Vec3? driftVelocity,
    DateTime? driftStartedAt,
    bool? driftPowered,
    bool? engineDormant,
    FuelPolicy? cruisePolicy,
  }) {
    return PlayerState(
      energyBalance: energyBalance ?? this.energyBalance,
      currentPlanetId:
          toDeepSpace ? null : (currentPlanetId ?? this.currentPlanetId),
      discoveredPlanetIds: discoveredPlanetIds ?? this.discoveredPlanetIds,
      exploredPlanetIds: exploredPlanetIds ?? this.exploredPlanetIds,
      activeJourneyId:
          clearActiveJourney ? null : (activeJourneyId ?? this.activeJourneyId),
      createdAt: createdAt,
      startCoordX: startCoordX,
      startCoordY: startCoordY,
      startX: startX ?? this.startX,
      startY: startY ?? this.startY,
      startZ: startZ ?? this.startZ,
      driftVelocity: driftVelocity ?? this.driftVelocity,
      driftStartedAt: driftStartedAt ?? this.driftStartedAt,
      driftPowered: driftPowered ?? this.driftPowered,
      engineDormant: engineDormant ?? this.engineDormant,
      cruisePolicy: cruisePolicy ?? this.cruisePolicy,
    );
  }

  /// A fresh save drifting in deep space at a randomised coordinate.
  factory PlayerState.deepSpaceStart({
    required int energy,
    required double startCoordX,
    required double startCoordY,
    required double startX,
    required double startY,
    required double startZ,
    required DateTime createdAt,
  }) {
    return PlayerState(
      energyBalance: energy,
      currentPlanetId: null, // drifting — not on any planet yet
      discoveredPlanetIds: <String>{},
      exploredPlanetIds: <String>{},
      activeJourneyId: null,
      createdAt: createdAt,
      startCoordX: startCoordX,
      startCoordY: startCoordY,
      startX: startX,
      startY: startY,
      startZ: startZ,
      driftVelocity: const Vec3(0, 0, 0),
      driftStartedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  factory PlayerState.fromJson(Map<String, dynamic> json) => PlayerState(
        energyBalance: json['energyBalance'] as int,
        currentPlanetId: json['currentPlanetId'] as String?,
        discoveredPlanetIds:
            (json['discoveredPlanetIds'] as List<dynamic>).cast<String>().toSet(),
        exploredPlanetIds:
            (json['exploredPlanetIds'] as List<dynamic>).cast<String>().toSet(),
        activeJourneyId: json['activeJourneyId'] as String?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        startCoordX: (json['startCoordX'] as num?)?.toDouble() ?? 0,
        startCoordY: (json['startCoordY'] as num?)?.toDouble() ?? 0,
        startX: (json['startX'] as num?)?.toDouble() ?? 0,
        startY: (json['startY'] as num?)?.toDouble() ?? 0,
        startZ: (json['startZ'] as num?)?.toDouble() ?? 0,
        driftVelocity: Vec3(
          (json['driftVelocityX'] as num?)?.toDouble() ?? 0,
          (json['driftVelocityY'] as num?)?.toDouble() ?? 0,
          (json['driftVelocityZ'] as num?)?.toDouble() ?? 0,
        ),
        driftStartedAt: DateTime.fromMillisecondsSinceEpoch(
            (json['driftStartedAt'] as int?) ?? 0),
        // All three are absent in every save written before free cruise existed.
        // The defaults are the only reading that keeps those saves behaving
        // exactly as they did: not powered, not dormant, halt on empty.
        driftPowered: json['driftPowered'] as bool? ?? false,
        engineDormant: json['engineDormant'] as bool? ?? false,
        cruisePolicy: cruisePolicyFromName(json['cruisePolicy'] as String?),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'energyBalance': energyBalance,
        'currentPlanetId': currentPlanetId,
        'discoveredPlanetIds': discoveredPlanetIds.toList(),
        'exploredPlanetIds': exploredPlanetIds.toList(),
        'activeJourneyId': activeJourneyId,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'startCoordX': startCoordX,
        'startCoordY': startCoordY,
        'startX': startX,
        'startY': startY,
        'startZ': startZ,
        'driftVelocityX': driftVelocity.x,
        'driftVelocityY': driftVelocity.y,
        'driftVelocityZ': driftVelocity.z,
        'driftStartedAt': driftStartedAt.millisecondsSinceEpoch,
        'driftPowered': driftPowered,
        'engineDormant': engineDormant,
        'cruisePolicy': cruisePolicy.name,
      };
}
