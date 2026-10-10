import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/balance.dart';
import '../core/vec3.dart';
import '../data/game_repository.dart';
import '../data/hyg_catalog.dart';
import '../data/models/discovery_record.dart';
import '../data/models/energy_transaction.dart';
import '../data/models/journey.dart';
import '../data/models/planet.dart';
import '../data/models/player_state.dart';
import '../data/models/training_session.dart';
import '../data/universe.dart';

/// Sentinel origin id for a journey that departs from open space (the player's
/// randomised starting drift) rather than from a planet.
const String kDeepSpaceId = 'deep-space';

/// Outcome of a launch attempt, surfaced to the UI for feedback.
enum LaunchResult {
  success,
  noSelection,
  insufficientEnergy,
  alreadyTraveling,
  alreadyHere,
}

/// Outcome of claiming a training reward.
enum TrainingClaimResult { success, notCompleted, alreadyClaimed, notFound }

/// Owns all game state and the rules that mutate it. UI observes this via
/// [ChangeNotifier]; every mutation persists through [GameRepository] and then
/// notifies. No widget mutates data directly.
class GameController extends ChangeNotifier {
  GameController({
    required GameRepository repository,
    DateTime Function()? clock,
    math.Random? random,
    SpawnStrategy? spawn,
  })  // Named params can't be private initializing formals, so assign here.
      // ignore: prefer_initializing_formals
      : _repository = repository,
        _now = clock ?? DateTime.now,
        _random = random ?? math.Random(),
        _spawn = spawn ?? SpawnStrategies.of(kDefaultSpawnMode);

  final GameRepository _repository;
  final DateTime Function() _now;
  final math.Random _random;
  final math.Random _idRng = math.Random();

  /// Where new players first land. Swappable (see [SpawnMode]) without touching
  /// the rest of the controller.
  final SpawnStrategy _spawn;

  late Universe _universe;

  /// Planets currently near the player — the dynamic working set rendered on
  /// the map and offered as destinations. The full universe is never
  /// materialised; this is regenerated when the player moves.
  List<Planet> _nearby = <Planet>[];

  /// How far around the player we surface procedural planets (light-years).
  static const double _nearbyRadiusLy = 60;

  late PlayerState _player;
  Journey? _activeJourney;
  final List<DiscoveryRecord> _discoveries = <DiscoveryRecord>[];
  final List<EnergyTransaction> _energyLedger = <EnergyTransaction>[];
  final List<TrainingSession> _trainingSessions = <TrainingSession>[];
  final Map<String, DiscoveryState> _planetStates = <String, DiscoveryState>{};

  bool _ready = false;

  // --- Lifecycle -----------------------------------------------------------

  Future<void> init() async {
    // Build the universe first — spawn and planet lookups depend on it.
    final hyg = await HygCatalog.load() ?? HygCatalog.curatedFallback();
    _universe = Universe(hyg);

    final save = await _repository.load();
    if (save == null) {
      _startFresh();
      // Lock in the randomised start immediately, so closing the app before
      // doing anything doesn't re-roll the player's position on next launch.
      await _persist();
    } else {
      _restore(save);
    }
    _reconcileJourney();
    _rebuildNearby();
    _ready = true;
    notifyListeners();
  }

  void _startFresh() {
    // New players wake up adrift at a coordinate chosen by the active spawn
    // strategy (random-universe by default, or confined to the Solar System),
    // inside the ship — not on a planet.
    final spawn = _spawn(_universe, _random);
    _player = PlayerState.deepSpaceStart(
      energy: Balance.initialEnergy,
      startCoordX: 0,
      startCoordY: 0,
      startX: spawn.x,
      startY: spawn.y,
      startZ: spawn.z,
      createdAt: _now(),
    );
  }

  void _restore(GameSave save) {
    _player = save.player;
    _activeJourney = save.activeJourney;
    _discoveries
      ..clear()
      ..addAll(save.discoveries);
    _energyLedger
      ..clear()
      ..addAll(save.energyLedger);
    _trainingSessions
      ..clear()
      ..addAll(save.trainingSessions);
    _planetStates
      ..clear()
      ..addAll(save.planetStates.map(
        (k, v) => MapEntry(
          k,
          DiscoveryState.values.firstWhere((s) => s.name == v,
              orElse: () => DiscoveryState.undiscovered),
        ),
      ));
  }

  Future<void> _persist() async {
    await _repository.save(GameSave(
      player: _player,
      activeJourney: _activeJourney,
      discoveries: _discoveries,
      energyLedger: _energyLedger,
      trainingSessions: _trainingSessions,
      planetStates:
          _planetStates.map((k, v) => MapEntry(k, v.name)),
    ));
  }

  // --- Read API ------------------------------------------------------------

  bool get isReady => _ready;

  /// Planets near the player (the working set shown on the map / offered as
  /// destinations). Regenerated from the universe when the player moves.
  List<Planet> get planets => _nearby;

  Universe get universe => _universe;
  HygStars get stars => _universe.stars;

  PlayerState get player => _player;
  int get energy => _player.energyBalance;
  Journey? get activeJourney => _activeJourney;
  List<DiscoveryRecord> get discoveries =>
      List<DiscoveryRecord>.unmodifiable(_discoveries.reversed);
  List<EnergyTransaction> get energyLedger =>
      List<EnergyTransaction>.unmodifiable(_energyLedger.reversed);
  List<TrainingSession> get trainingSessions =>
      List<TrainingSession>.unmodifiable(_trainingSessions);

  DateTime get now => _now();

  Planet? planetById(String id) => _universe.planetById(id);

  /// The planet the ship is at, or null when drifting in deep space.
  Planet? get currentPlanet {
    final id = _player.currentPlanetId;
    return id == null ? null : _universe.planetById(id);
  }

  String? get currentPlanetId => _player.currentPlanetId;
  bool get inDeepSpace => _player.inDeepSpace;

  /// The ship's 3D position in light-years while drifting in deep space.
  Vec3? get deepSpaceOrigin3D => inDeepSpace
      ? Vec3(_player.startX, _player.startY, _player.startZ)
      : null;

  /// The ship's current 3D position in light-years (planet or deep-space drift).
  Vec3 get playerPosition3D =>
      currentPlanet?.pos ??
      Vec3(_player.startX, _player.startY, _player.startZ);

  /// Display name for a location id (planet name, or "深空" for the drift).
  String locationLabel(String? planetId) {
    if (planetId == null || planetId == kDeepSpaceId) return '深空';
    return _universe.planetById(planetId)?.name ?? '深空';
  }

  DiscoveryState stateOf(String planetId) =>
      _planetStates[planetId] ?? DiscoveryState.undiscovered;

  int get discoveredCount =>
      _planetStates.values.where((s) => s != DiscoveryState.undiscovered).length;
  int get exploredCount => _player.exploredPlanetIds.length;

  /// A journey is only *blocking* (prevents a new launch) while in progress.
  bool get isTraveling =>
      _activeJourney?.status == JourneyStatus.inProgress;

  /// Distance from the ship's current location to [target], in light-years.
  double distanceTo(Planet target) =>
      (playerPosition3D - target.pos).length;

  /// Fixed length of a journey, honouring a deep-space origin, in light-years.
  double journeyDistance(Journey j) {
    final to = _universe.planetById(j.destinationPlanetId);
    if (to == null) return 0;
    final Vec3 from = j.originPlanetId == kDeepSpaceId
        ? Vec3(_player.startX, _player.startY, _player.startZ)
        : (_universe.planetById(j.originPlanetId)?.pos ?? playerPosition3D);
    return (to.pos - from).length;
  }

  TravelTier tierTo(Planet target) => tierForDistance(distanceTo(target));
  int energyCostTo(Planet target) => energyCostForTier(tierTo(target));
  Duration travelDurationTo(Planet target) =>
      Duration(seconds: travelSecondsForTier(tierTo(target)));

  List<DiscoveryRecord> discoveriesFor(String planetId) =>
      _discoveries.where((d) => d.planetId == planetId).toList();

  /// Which point-of-interest ids on [planetId] have already been found.
  Set<String> foundPoiIds(String planetId) =>
      discoveriesFor(planetId).map((d) => d.id).toSet();

  /// Rebuilds the near-player working set, expanding the search radius if the
  /// immediate neighbourhood is sparse (e.g. far from the Sun) so there is
  /// always somewhere to travel.
  void _rebuildNearby() {
    var radius = _nearbyRadiusLy;
    var found = _universe.planetsNear(playerPosition3D, radius, cap: 90);
    var tries = 0;
    while (found.length < 10 && tries < 4) {
      radius *= 2;
      found = _universe.planetsNear(playerPosition3D, radius, cap: 90);
      tries++;
    }
    // Make sure an in-flight destination is always resolvable in the set.
    final destId = _activeJourney?.destinationPlanetId;
    if (destId != null && !found.any((p) => p.id == destId)) {
      final dest = _universe.planetById(destId);
      if (dest != null) found = <Planet>[dest, ...found];
    }
    _nearby = List<Planet>.unmodifiable(found);
  }

  // --- Journey rules -------------------------------------------------------

  /// Flips an in-progress journey to [JourneyStatus.arrived] once its arrival
  /// timestamp has passed, applying arrival effects exactly once. Safe to call
  /// repeatedly (on launch, on resume, on tick).
  void _reconcileJourney() {
    final journey = _activeJourney;
    if (journey == null) return;
    if (journey.status == JourneyStatus.inProgress &&
        journey.hasArrivedBy(_now())) {
      _applyArrival(journey);
    }
  }

  void _applyArrival(Journey journey) {
    _activeJourney = journey.copyWith(status: JourneyStatus.arrived);
    _player = _player.copyWith(
      currentPlanetId: journey.destinationPlanetId,
    );
    // Reaching a planet discovers it (if not already explored).
    if (stateOf(journey.destinationPlanetId) == DiscoveryState.undiscovered) {
      _planetStates[journey.destinationPlanetId] = DiscoveryState.discovered;
      _player = _player.copyWith(
        discoveredPlanetIds: <String>{
          ..._player.discoveredPlanetIds,
          journey.destinationPlanetId,
        },
      );
    }
    // The ship has moved — refresh the planets around the new location.
    _rebuildNearby();
  }

  /// Call periodically (e.g. once per second from a visible journey view) to
  /// surface the arrival transition without any always-on timer.
  void tick() {
    if (_activeJourney?.status == JourneyStatus.inProgress &&
        _activeJourney!.hasArrivedBy(_now())) {
      _reconcileJourney();
      _persist();
      notifyListeners();
    } else {
      // Still travelling — repaint progress without persisting.
      notifyListeners();
    }
  }

  /// Validates and starts a journey to [target]. Atomic: energy is only
  /// deducted when all guards pass, preventing double charges and negatives.
  Future<LaunchResult> launchJourney(Planet target) async {
    if (target.id == _player.currentPlanetId) return LaunchResult.alreadyHere;
    if (isTraveling) return LaunchResult.alreadyTraveling;
    final cost = energyCostTo(target);
    if (_player.energyBalance < cost) return LaunchResult.insufficientEnergy;

    final departure = _now();
    final arrival = departure.add(travelDurationTo(target));
    final journey = Journey(
      id: _newId('jny'),
      // A new player departs from open space (sentinel) until the first arrival.
      originPlanetId: _player.currentPlanetId ?? kDeepSpaceId,
      destinationPlanetId: target.id,
      departure: departure,
      arrival: arrival,
      energyCost: cost,
      status: JourneyStatus.inProgress,
    );
    _activeJourney = journey;
    _spendEnergy(cost, EnergyTxType.travelCost, journey.id);
    await _persist();
    notifyListeners();
    return LaunchResult.success;
  }

  /// Dismisses an arrived journey without exploring, freeing the ship to
  /// travel again. Idempotent.
  Future<void> acknowledgeArrival() async {
    final journey = _activeJourney;
    if (journey == null || journey.status == JourneyStatus.inProgress) return;
    _activeJourney = null;
    _player = _player.copyWith(clearActiveJourney: true);
    await _persist();
    notifyListeners();
  }

  // --- Exploration ---------------------------------------------------------

  /// Records a single point-of-interest discovery. No-op if already found so
  /// the log never gains duplicates when a scene is re-entered.
  Future<void> recordDiscovery(Planet planet, PointOfInterest poi) async {
    if (foundPoiIds(planet.id).contains(poi.id)) return;
    _discoveries.add(DiscoveryRecord(
      id: poi.id, // stable id → natural de-duplication
      planetId: planet.id,
      discoveryType: poi.discoveryType,
      title: poi.discoveryTitle,
      description: poi.discoveryDescription,
      discoveredAt: _now(),
      seedColor: planet.seedColor,
    ));
    await _persist();
    notifyListeners();
  }

  /// Marks a planet explored and grants the one-time exploration reward.
  /// Returns true the first time it completes a planet.
  Future<bool> completeExploration(Planet planet) async {
    final firstTime = stateOf(planet.id) != DiscoveryState.explored;
    _planetStates[planet.id] = DiscoveryState.explored;
    _player = _player.copyWith(
      exploredPlanetIds: <String>{
        ..._player.exploredPlanetIds,
        planet.id,
      },
    );
    if (firstTime) {
      _addEnergy(
          Balance.explorationReward, EnergyTxType.explorationReward, planet.id);
    }
    // The voyage that brought us here is now complete.
    if (_activeJourney?.destinationPlanetId == planet.id) {
      _activeJourney = null;
      _player = _player.copyWith(clearActiveJourney: true);
    }
    await _persist();
    notifyListeners();
    return firstTime;
  }

  // --- Training ------------------------------------------------------------

  Future<TrainingSession> startCourse(String courseId) async {
    final session = TrainingSession(
      id: _newId('trn'),
      courseId: courseId,
      startedAt: _now(),
      status: TrainingStatus.inProgress,
      rewardClaimed: false,
    );
    _trainingSessions.add(session);
    await _persist();
    notifyListeners();
    return session;
  }

  /// Completes a session and grants [reward] exactly once. The guard prevents
  /// double claims even if the UI calls this twice.
  Future<TrainingClaimResult> completeCourse(
      String sessionId, int reward) async {
    final idx = _trainingSessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return TrainingClaimResult.notFound;
    final s = _trainingSessions[idx];
    if (s.rewardClaimed) return TrainingClaimResult.alreadyClaimed;

    _trainingSessions[idx] = TrainingSession(
      id: s.id,
      courseId: s.courseId,
      startedAt: s.startedAt,
      completedAt: _now(),
      status: TrainingStatus.completed,
      rewardClaimed: true,
    );
    _addEnergy(reward, EnergyTxType.trainingReward, s.courseId);
    await _persist();
    notifyListeners();
    return TrainingClaimResult.success;
  }

  // --- Energy helpers ------------------------------------------------------

  void _spendEnergy(int cost, EnergyTxType type, String relatedId) {
    final newBalance = math.max(0, _player.energyBalance - cost);
    _player = _player.copyWith(energyBalance: newBalance);
    _energyLedger.add(EnergyTransaction(
      id: _newId('en'),
      type: type,
      amount: -cost,
      createdAt: _now(),
      relatedObjectId: relatedId,
    ));
  }

  void _addEnergy(int amount, EnergyTxType type, String relatedId) {
    _player = _player.copyWith(energyBalance: _player.energyBalance + amount);
    _energyLedger.add(EnergyTransaction(
      id: _newId('en'),
      type: type,
      amount: amount,
      createdAt: _now(),
      relatedObjectId: relatedId,
    ));
  }

  String _newId(String prefix) =>
      '$prefix-${_now().microsecondsSinceEpoch}-${_idRng.nextInt(1 << 20)}';

  /// Wipes the save and restarts — handy for testing the first-run flow.
  Future<void> resetSave() async {
    await _repository.clear();
    _activeJourney = null;
    _discoveries.clear();
    _energyLedger.clear();
    _trainingSessions.clear();
    _planetStates.clear();
    _startFresh();
    await _persist();
    notifyListeners();
  }
}
