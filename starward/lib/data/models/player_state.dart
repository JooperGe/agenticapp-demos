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

  bool get inDeepSpace => currentPlanetId == null;

  PlayerState copyWith({
    int? energyBalance,
    String? currentPlanetId,
    Set<String>? discoveredPlanetIds,
    Set<String>? exploredPlanetIds,
    String? activeJourneyId,
    bool clearActiveJourney = false,
  }) {
    return PlayerState(
      energyBalance: energyBalance ?? this.energyBalance,
      currentPlanetId: currentPlanetId ?? this.currentPlanetId,
      discoveredPlanetIds: discoveredPlanetIds ?? this.discoveredPlanetIds,
      exploredPlanetIds: exploredPlanetIds ?? this.exploredPlanetIds,
      activeJourneyId:
          clearActiveJourney ? null : (activeJourneyId ?? this.activeJourneyId),
      createdAt: createdAt,
      startCoordX: startCoordX,
      startCoordY: startCoordY,
      startX: startX,
      startY: startY,
      startZ: startZ,
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
      };
}
