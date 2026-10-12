import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/balance.dart';
import '../core/vec3.dart';
import '../data/game_repository.dart';
import '../data/hyg_catalog.dart';
import '../data/models/discovery_record.dart';
import '../data/models/energy_transaction.dart';
import '../data/models/engine.dart';
import '../data/models/journey.dart';
import '../data/models/planet.dart';
import '../data/models/player_state.dart';
import '../data/models/ship.dart';
import '../data/models/training_session.dart';
import '../data/synthetic_galaxy.dart';
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

  /// The vessel the player flies. Voyage cost and duration are read off
  /// [_ship]'s engine, never from a global table — see [installEngine].
  late Ship _ship;

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
    _universe = Universe(hyg, extraGalaxies: SyntheticGalaxy.all());

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
    _ship = Ship.standard;
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
    _ship = save.ship;
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
      ship: _ship,
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

  /// The vessel the player flies. Its engine is the single source of truth for
  /// voyage cost and duration.
  Ship get ship => _ship;

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

  /// The player's energy right now, in EN.
  ///
  /// While a voyage is in progress this is the fuel still aboard: the balance
  /// minus what the engine has burned so far. Nothing is deducted at launch, so
  /// this getter is the only place the burn is applied — which is what makes
  /// the reading tick down in real time and still be correct after the app is
  /// killed and restarted.
  int get energy {
    final j = _activeJourney;
    if (j == null || j.status != JourneyStatus.inProgress) {
      return _player.energyBalance;
    }
    final left = _player.energyBalance - j.burnedAt(_now());
    return left < 0 ? 0 : left;
  }

  /// Display name for a location id (planet name, star name, or "深空").
  String locationLabel(String? planetId) {
    if (planetId == null || planetId == kDeepSpaceId) return '深空';
    if (_isStarDest(planetId)) return _universe.starLabel(_starIdFromDest(planetId));
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
    final Vec3? toPos = _isStarDest(j.destinationPlanetId)
        ? _universe.starArrivalPoint(_starIdFromDest(j.destinationPlanetId))
        : _isCoordDest(j.destinationPlanetId)
            ? _coordFromDest(j.destinationPlanetId)
            : _universe.planetById(j.destinationPlanetId)?.pos;
    if (toPos == null) return 0;
    final Vec3 from = j.originPlanetId == kDeepSpaceId
        ? Vec3(_player.startX, _player.startY, _player.startZ)
        : (_universe.planetById(j.originPlanetId)?.pos ?? playerPosition3D);
    return (toPos - from).length;
  }

  /// Energy this ship would burn to reach [target]. Read off the fitted
  /// engine, so a refit changes the quote immediately.
  int energyCostTo(Planet target) =>
      _ship.engine.energyCostFor(distanceTo(target));

  /// How long this ship would take to reach [target].
  Duration travelDurationTo(Planet target) =>
      Duration(seconds: _ship.engine.secondsFor(distanceTo(target)));

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
    // The voyage ends here, so the whole quote lands now.
    _settleBurn(journey, _now());
    final dest = journey.destinationPlanetId;
    // Travelling to a star (not a planet): arrive drifting beside it.
    if (_isStarDest(dest)) {
      final target = _universe.starArrivalPoint(_starIdFromDest(dest));
      _activeJourney = journey.copyWith(status: JourneyStatus.arrived);
      if (target != null) {
        _player = _player.copyWith(
          toDeepSpace: true,
          startX: target.x,
          startY: target.y,
          startZ: target.z,
        );
      }
      _rebuildNearby();
      return;
    }

    // Returning to a free point in deep space: arrive drifting there.
    if (_isCoordDest(dest)) {
      final target = _coordFromDest(dest);
      _activeJourney = journey.copyWith(status: JourneyStatus.arrived);
      _player = _player.copyWith(
        toDeepSpace: true,
        startX: target.x,
        startY: target.y,
        startZ: target.z,
      );
      _rebuildNearby();
      return;
    }

    _activeJourney = journey.copyWith(status: JourneyStatus.arrived);
    _player = _player.copyWith(currentPlanetId: dest);
    // Reaching a planet discovers it (if not already explored).
    if (stateOf(dest) == DiscoveryState.undiscovered) {
      _planetStates[dest] = DiscoveryState.discovered;
      _player = _player.copyWith(
        discoveredPlanetIds: <String>{..._player.discoveredPlanetIds, dest},
      );
    }
    // The ship has moved — refresh the planets around the new location.
    _rebuildNearby();
  }

  // Star destinations are encoded as 'star:<hygId>' in a journey.
  static String _starDestId(int hygId) => 'star:$hygId';
  static bool _isStarDest(String id) => id.startsWith('star:');
  static int _starIdFromDest(String id) => int.parse(id.substring(5));

  /// Whether a journey destination id refers to a star rather than a planet.
  static bool isStarDestination(String id) => _isStarDest(id);

  // Deep-space waypoints — used when turning back to an origin that was open
  // space (not a planet or star) — are encoded as 'coord:<x>,<y>,<z>'.
  static String _coordDestId(Vec3 p) => 'coord:${p.x},${p.y},${p.z}';
  static bool _isCoordDest(String id) => id.startsWith('coord:');
  static Vec3 _coordFromDest(String id) {
    final parts = id.substring(6).split(',');
    return Vec3(
        double.parse(parts[0]), double.parse(parts[1]), double.parse(parts[2]));
  }

  /// Whether a journey destination id refers to a free deep-space coordinate.
  static bool isCoordDestination(String id) => _isCoordDest(id);

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

  /// Validates and starts a journey to [target]. Energy is checked up front but
  /// not deducted — the burn accrues in real time and is booked when the voyage
  /// ends (see [_settleBurn]).
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
    await _persist();
    notifyListeners();
    return LaunchResult.success;
  }

  /// Distance (ly) from the ship to a star's arrival point.
  double distanceToStar(int hygId) {
    final target = _universe.starArrivalPoint(hygId);
    if (target == null) return double.infinity;
    return (playerPosition3D - target).length;
  }

  int energyCostToStar(int hygId) =>
      _ship.engine.energyCostFor(distanceToStar(hygId));

  /// Launches a journey to a *star* (used for stars with no planets — you drift
  /// in beside it). Mirrors [launchJourney] but the destination is a star.
  Future<LaunchResult> launchToStar(int hygId) async {
    final target = _universe.starArrivalPoint(hygId);
    if (target == null) return LaunchResult.noSelection;
    if (isTraveling) return LaunchResult.alreadyTraveling;
    final dist = (playerPosition3D - target).length;
    if (dist < 0.5) return LaunchResult.alreadyHere;
    final cost = _ship.engine.energyCostFor(dist);
    if (_player.energyBalance < cost) return LaunchResult.insufficientEnergy;

    final departure = _now();
    final arrival =
        departure.add(Duration(seconds: _ship.engine.secondsFor(dist)));
    final journey = Journey(
      id: _newId('jny'),
      originPlanetId: _player.currentPlanetId ?? kDeepSpaceId,
      destinationPlanetId: _starDestId(hygId),
      departure: departure,
      arrival: arrival,
      energyCost: cost,
      status: JourneyStatus.inProgress,
    );
    _activeJourney = journey;
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

  // --- Mid-flight controls -------------------------------------------------

  /// The 3D position a journey departed from (planet, star, or deep-space drift).
  Vec3 _originPosOf(Journey j) {
    final id = j.originPlanetId;
    if (id == kDeepSpaceId) {
      return Vec3(_player.startX, _player.startY, _player.startZ);
    }
    if (_isStarDest(id)) {
      return _universe.starArrivalPoint(_starIdFromDest(id)) ?? playerPosition3D;
    }
    if (_isCoordDest(id)) return _coordFromDest(id);
    return _universe.planetById(id)?.pos ?? playerPosition3D;
  }

  /// The 3D position a journey is heading toward.
  Vec3? _destPosOf(Journey j) {
    final id = j.destinationPlanetId;
    if (_isStarDest(id)) {
      return _universe.starArrivalPoint(_starIdFromDest(id));
    }
    if (_isCoordDest(id)) return _coordFromDest(id);
    return _universe.planetById(id)?.pos;
  }

  /// The ship's current 3D position partway along [j] at [now], by linear
  /// interpolation between origin and destination. Matches the timestamp-driven
  /// progress model, so there is no stored position to drift out of sync.
  Vec3 _positionAlong(Journey j, DateTime now) {
    final from = _originPosOf(j);
    final to = _destPosOf(j) ?? from;
    return from + (to - from) * j.progressAt(now);
  }

  /// Aborts an in-progress journey, leaving the ship drifting at the point it
  /// had reached along the route. Only the fuel burned to get this far is
  /// billed — the unburned remainder never left the tank. No-op if not
  /// travelling.
  Future<void> abortJourney() async {
    final journey = _activeJourney;
    if (journey == null || journey.status != JourneyStatus.inProgress) return;
    final now = _now();
    final pos = _positionAlong(journey, now);
    // Only the fuel actually burned is billed — the rest never left the tank,
    // so there is no refund to write.
    _settleBurn(journey, now);
    _activeJourney = null;
    _player = _player.copyWith(
      toDeepSpace: true,
      startX: pos.x,
      startY: pos.y,
      startZ: pos.z,
      clearActiveJourney: true,
    );
    _rebuildNearby();
    await _persist();
    notifyListeners();
  }

  /// Turns the ship around mid-flight: launches a fresh journey from the point
  /// reached so far back to where the active journey departed from. The outbound
  /// leg's burn is settled before the return leg is quoted (fuel burns both
  /// ways); the return leg then burns like any other voyage and settles on
  /// arrival. Returns the launch outcome so the UI can report e.g. insufficient
  /// energy.
  ///
  /// This is unconditional — turning back one second after departure still plots
  /// a return voyage rather than stopping the ship where it is. The distance
  /// floors on [Engine] already keep a near-zero return leg from resolving to a
  /// zero-length trip, and stopping short of the origin would strand the player
  /// in open space when they asked to go home (use [abortJourney] for that).
  Future<LaunchResult> returnToOrigin() async {
    final journey = _activeJourney;
    if (journey == null || journey.status != JourneyStatus.inProgress) {
      return LaunchResult.noSelection;
    }
    final now = _now();
    final currentPos = _positionAlong(journey, now);
    final originPos = _originPosOf(journey);
    // Settle the outbound leg first: the return quote has to be checked against
    // the balance the player actually has left.
    _settleBurn(journey, now);
    final dist = (originPos - currentPos).length;
    final cost = _ship.engine.energyCostFor(dist);
    if (_player.energyBalance < cost) return LaunchResult.insufficientEnergy;

    // Where we return *to*: dock at the origin planet/star, or a free deep-space
    // coordinate if the journey launched from open space.
    final destId = journey.originPlanetId == kDeepSpaceId
        ? _coordDestId(originPos)
        : journey.originPlanetId;

    // The ship now drifts at the point it had reached — origin of the return.
    _player = _player.copyWith(
      toDeepSpace: true,
      startX: currentPos.x,
      startY: currentPos.y,
      startZ: currentPos.z,
    );
    final arrival =
        now.add(Duration(seconds: _ship.engine.secondsFor(dist)));
    final ret = Journey(
      id: _newId('jny'),
      originPlanetId: kDeepSpaceId,
      destinationPlanetId: destId,
      departure: now,
      arrival: arrival,
      energyCost: cost,
      status: JourneyStatus.inProgress,
    );
    _activeJourney = ret;
    _rebuildNearby();
    await _persist();
    notifyListeners();
    return LaunchResult.success;
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

  // --- Ship ----------------------------------------------------------------

  /// Fits a different [engine] to the ship and persists the refit.
  ///
  /// This is the seam that makes the engine a real, separately-changeable part:
  /// a refit is this one call, and every subsequent voyage quote, launch, and
  /// return leg picks up the new numbers because they all read [_ship]. It is
  /// a no-op when [engine] is already fitted.
  Future<void> installEngine(Engine engine) async {
    if (_ship.engine.id == engine.id) return;
    _ship = _ship.withEngine(engine);
    await _persist();
    notifyListeners();
  }

  // --- Energy helpers ------------------------------------------------------

  /// Books the fuel voyage [j] has burned up to [now], once, and returns it.
  ///
  /// Nothing is deducted at launch, so this is where a voyage's cost actually
  /// reaches the ledger. Every path that ends a voyage calls it *before* the
  /// journey is cleared or its status flips — that ordering is what keeps it
  /// from booking twice.
  int _settleBurn(Journey j, DateTime now) {
    final burned = j.burnedAt(now);
    if (burned <= 0) return 0;
    _player = _player.copyWith(
      energyBalance: math.max(0, _player.energyBalance - burned),
    );
    _energyLedger.add(EnergyTransaction(
      id: _newId('en'),
      type: EnergyTxType.travelCost,
      amount: -burned,
      createdAt: now,
      relatedObjectId: j.id,
    ));
    return burned;
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
