import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/balance.dart';
import '../core/drift.dart';
import '../core/vec3.dart';
import '../data/game_repository.dart';
import '../data/hyg_catalog.dart';
import '../data/models/discovery_record.dart';
import '../data/models/drift_report.dart';
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

  /// The position the nearby set was last built at, so a drifting ship can
  /// skip the scan when it has barely moved.
  Vec3? _nearbyScanPos;

  /// How far the ship must travel before the nearby set is rebuilt. A coasting
  /// ship covers 2304 ly/day, so rescanning every frame would walk 120k stars
  /// sixty times a second for a list that hardly changed.
  static const double _nearbyRescanLy = 20;

  late PlayerState _player;

  /// The vessel the player flies. Voyage cost and duration are read off
  /// [_ship]'s engine, never from a global table — see [installEngine].
  late Ship _ship;

  Journey? _activeJourney;

  /// A report the player has not seen yet. Persisted, so being killed between
  /// the drift happening and the sheet being opened does not lose it.
  DriftReport? _pendingDriftReport;

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
    // A drift that ran while the game was closed is the one thing the player
    // could not have watched happen. Recompute it once. A voyage that ran out
    // of fuel while away has already queued its own report, and that news wins:
    // there is one report slot by design (the save holds a single
    // `pendingDriftReport`), so this `??=` deliberately leaves the fuel-out
    // report in place and does not auto-queue the drift window. That is
    // intended — "your voyage was cut short, you got this far" is both more
    // urgent and more specific than "you also coasted" — and the drift summary
    // stays reachable: the coasting screen shows the running totals live and
    // its 查看播报 button yields the report on demand.
    _pendingDriftReport ??= buildDriftReport();
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
    // A queued fuel-out report is history: the powered leg is over, and
    // `buildDriftReport` can only ever produce the `drift` kind, so this
    // window cannot be recomputed after the fact — it has to survive the
    // restart. A queued drift report is a window that kept growing while the
    // game was closed, and rebuilding it covers a superset of the same span
    // (same `driftStartedAt`, later `now`), so it is deliberately left null
    // for `init()` to recompute — design §6.3's offline window is
    // `[driftStartedAt, now]`.
    _pendingDriftReport = save.pendingDriftReport?.kind == DriftReportKind.fuelOut
        ? save.pendingDriftReport
        : null;
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
      pendingDriftReport: _pendingDriftReport,
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

  /// The ship's current drift velocity in ly/s. Zero whenever the ship is
  /// parked — which is every state the game had before coasting existed.
  Vec3 get driftVelocity => _player.driftVelocity;

  /// The ship's current 3D position in light-years.
  ///
  /// Docked at a planet it is that planet's position. Adrift it is the
  /// deep-space anchor advanced by any drift — and because a parked ship has
  /// zero velocity, this returns the anchor untouched, which is what every
  /// deep-space state did before coasting existed.
  Vec3 get playerPosition3D {
    final planet = currentPlanet;
    if (planet != null) return planet.pos;
    final start = Vec3(_player.startX, _player.startY, _player.startZ);
    return driftPositionAt(
      start: start,
      velocity: _player.driftVelocity,
      elapsedSeconds:
          _now().difference(_player.driftStartedAt).inMilliseconds / 1000,
      // Never tighter than the ship's own radius: a player who spawned outside
      // the shell keeps their distance instead of being snapped inward.
      bound: math.max(_universe.universeRadius, start.length),
    );
  }

  /// Whether the ship is moving through deep space at all — under power or not.
  ///
  /// This, not [isCoasting], is the question every movement rule actually asks:
  /// a cruising ship has just as much momentum to shed as a coasting one, and
  /// quoting it a zero braking cost would make "cruise out, then launch a
  /// voyage" a free ferry.
  bool get hasMomentum => _player.driftVelocity.length > 0;

  /// Whether the ship is drifting with the engine off. Zero velocity means
  /// parked in deep space, which is a different state: a parked ship has nowhere
  /// to be and nothing to report.
  bool get isCoasting => hasMomentum && !_player.driftPowered;

  /// Whether the ship is drifting *under power*, burning the tank as it goes.
  bool get isCruising => hasMomentum && _player.driftPowered;

  /// Whether the engine has shut down for want of energy. Only [activate] clears
  /// it — training refills the tank but does not restart the engine.
  bool get isDormant => _player.engineDormant;

  /// What it costs to bring the ship out of its current motion, in EN.
  ///
  /// Zero for a ship at rest — docked, parked in deep space, or on a voyage.
  /// Only a ship with momentum has any to shed.
  int get brakingCost => hasMomentum
      ? _ship.engine.brakingCostFor(_player.driftVelocity.length)
      : 0;

  /// How long the current drift has been running, or zero when parked.
  Duration get driftElapsed => hasMomentum
      ? _now().difference(_player.driftStartedAt)
      : Duration.zero;

  /// How far the current drift has carried the ship, in light-years.
  double get driftDistanceLy => hasMomentum
      ? _player.driftVelocity.length * driftElapsed.inMilliseconds / 1000
      : 0;

  /// The path the current drift follows, or null when the ship is parked.
  ///
  /// `bound` is `max(universeRadius, |start|)`: the shell is the catalogue's
  /// bounding radius, so `|start| > bound` cannot happen for a star-spawned
  /// ship — but the max keeps the definition honest if it ever does, instead of
  /// teleporting the ship inward.
  DriftPath? get driftPath {
    if (!hasMomentum) return null;
    final start = Vec3(_player.startX, _player.startY, _player.startZ);
    return DriftPath(
      start: start,
      velocity: _player.driftVelocity,
      bound: math.max(_universe.universeRadius, start.length),
    );
  }

  /// Seconds of drift at [at], counted from the moment the tank emptied.
  double _driftSecondsAt(DateTime at) =>
      at.difference(_player.driftStartedAt).inMilliseconds / 1000;

  /// Re-pins the drift leg to the ship's current position and the current
  /// instant, optionally replacing the velocity.
  ///
  /// `(startX/Y/Z, driftStartedAt, driftVelocity)` are one fact — a line through
  /// space — and changing any one of them invalidates the other two. This is the
  /// single place that repairs them together, so no rule can move one without
  /// the others. The position is read *before* the anchor is overwritten; that
  /// ordering is the whole trick.
  void _repinLeg({Vec3? velocity, DateTime? at}) {
    final pos = playerPosition3D;
    _player = _player.copyWith(
      startX: pos.x,
      startY: pos.y,
      startZ: pos.z,
      driftStartedAt: at ?? _now(),
      driftVelocity: velocity ?? _player.driftVelocity,
    );
  }

  /// What the current drift has passed so far, for the coasting readout.
  ///
  /// A full catalogue scan — read it once per tick, never per frame.
  PassedSystems get passedSystemsSoFar {
    final path = driftPath;
    if (path == null) return PassedSystems.none;
    return _universe.passedSystemsAlong(
      path: path,
      upToSeconds: _driftSecondsAt(_now()),
    );
  }

  /// The report for the current drift, covering everything since it began.
  ///
  /// Null when parked: a ship that is not moving has nothing to report, and
  /// `driftStartedAt` defaults to the epoch — without the parked guard every
  /// new player would be told they had been drifting for fifty-six years. Null
  /// too for a window that has not opened yet — a drift that has not begun has
  /// nothing to report either, and without that guard every launch while
  /// coasting would queue a report of zero length.
  DriftReport? buildDriftReport() {
    final path = driftPath;
    if (path == null) return null;
    final now = _now();
    if (!now.isAfter(_player.driftStartedAt)) return null;
    final to = _driftSecondsAt(now);
    final passed =
        _universe.passedSystemsAlong(path: path, upToSeconds: to);
    return DriftReport(
      kind: DriftReportKind.drift,
      from: _player.driftStartedAt,
      to: now,
      elapsed: now.difference(_player.driftStartedAt),
      distanceLy: path.travelledBetween(0, to),
      fromPos: path.positionAt(0),
      toPos: path.positionAt(to),
      passedCount: passed.count,
      nearest: passed.nearest,
      hitBoundary: to > path.hitSeconds,
    );
  }

  DriftReport? get pendingDriftReport => _pendingDriftReport;

  /// Queues a report for the drift so far — the coasting screen's "播报" button.
  Future<void> requestDriftReport() async {
    if (_pendingDriftReport != null) return;
    final report = buildDriftReport();
    if (report == null) return;
    _pendingDriftReport = report;
    await _persist();
    notifyListeners();
  }

  /// Marks the queued report as read.
  Future<void> acknowledgeDriftReport() async {
    if (_pendingDriftReport == null) return;
    _pendingDriftReport = null;
    await _persist();
    notifyListeners();
  }

  /// Brings the ship to rest where it is, billing any momentum it has to shed.
  ///
  /// Every launch must do this: [_originPosOf] reads the anchor, so a coasting
  /// ship that launched without re-anchoring would plot its route from a stale
  /// coordinate and arrive somewhere it never was.
  ///
  /// This is also the one place a drift is billed. Putting the charge here
  /// rather than on the "stop" button is what keeps the exits honest: the star
  /// map is a way out of a drift, and if it were free the player would learn to
  /// route around the paid button sitting next to it.
  ///
  /// The cruise settle comes first, and it has to: the `copyWith` below clears
  /// `driftVelocity`, and once it is zero `isCruising` is false and the leg's
  /// accrued burn can never be booked at all. It is *not* about `brakingCost` —
  /// that is a pure function of the velocity the settle preserves, so reading it
  /// is free and order-independent.
  void _anchorHere() {
    _settleCruise();
    // Read the price before the velocity is cleared below — braking is quoted
    // off the speed the ship is actually carrying.
    final braking = brakingCost;
    final pos = playerPosition3D;
    _player = _player.copyWith(
      startX: pos.x,
      startY: pos.y,
      startZ: pos.z,
      driftVelocity: const Vec3(0, 0, 0),
      driftPowered: false,
    );
    if (braking > 0) _settleBraking(braking);
  }

  /// The live balance: what the player can spend right now.
  ///
  /// Both a voyage and a cruise accrue their cost in real time and book it only
  /// when the leg ends, so this subtracts the accrued-but-unbooked part. Without
  /// the cruise branch a powered drift would look free until it stopped, and
  /// every quote made mid-cruise would be against money already spent.
  int get energy {
    final j = _activeJourney;
    if (j != null && j.status == JourneyStatus.inProgress) {
      final left = _player.energyBalance - j.burnedAt(_now());
      return left < 0 ? 0 : left;
    }
    final left = _player.energyBalance - _cruiseBurnNow();
    return left < 0 ? 0 : left;
  }

  /// Display name for a location id (planet name, star name, or "深空").
  String locationLabel(String? planetId) {
    if (planetId == null || planetId == kDeepSpaceId) return '深空';
    if (_isStarDest(planetId)) return _universe.starLabel(_starIdFromDest(planetId));
    return _universe.planetById(planetId)?.name ?? '深空';
  }

  /// The display name for a star system, for report copy.
  String starLabelFor(int hygId) => _universe.starLabel(hygId);

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

  /// Energy this ship would burn to reach [target] — the voyage's own fuel plus
  /// whatever it costs to shed a drift first.
  ///
  /// This is the quote the player sees, so it is what the launch dialogs and
  /// the "开始航行 · N EN" button read. It is deliberately *not* what
  /// `Journey.energyCost` stores: that drives the burn curve and must stay
  /// fuel-only. Parked, docked, or under power, [brakingCost] is 0 and this is
  /// exactly the voyage quote it has always been.
  int energyCostTo(Planet target) =>
      _ship.engine.energyCostFor(distanceTo(target)) + brakingCost;

  /// How long this ship would take to reach [target].
  Duration travelDurationTo(Planet target) =>
      Duration(seconds: _ship.engine.secondsFor(distanceTo(target)));

  /// The fraction of voyage [j]'s route the ship can currently afford, capped
  /// at 1. Below 1 the tank runs dry partway; at 1 the destination is reachable.
  ///
  /// Read off the balance *at the moment of asking*, which is what lets a
  /// course finished mid-flight raise it and pull a doomed trip back onto the
  /// board (see spec §3.4).
  double fuelExhaustProgressFor(Journey j) {
    final p = _player.energyBalance / j.energyCost;
    if (p >= 1) return 1;
    return p <= 0 ? 0 : p;
  }

  /// [fuelExhaustProgressFor] for the voyage in progress, or null when parked.
  double? get fuelExhaustProgress {
    final j = _activeJourney;
    if (j == null || j.status != JourneyStatus.inProgress) return null;
    return fuelExhaustProgressFor(j);
  }

  /// When voyage [j] runs out of fuel — never later than its arrival.
  DateTime fuelExhaustTime(Journey j) {
    final p = fuelExhaustProgressFor(j);
    return j.departure.add(
        Duration(milliseconds: (j.totalDuration.inMilliseconds * p).round()));
  }

  List<DiscoveryRecord> discoveriesFor(String planetId) =>
      _discoveries.where((d) => d.planetId == planetId).toList();

  /// Which point-of-interest ids on [planetId] have already been found.
  Set<String> foundPoiIds(String planetId) =>
      discoveriesFor(planetId).map((d) => d.id).toSet();

  /// Rebuilds the near-player working set, expanding the search radius if the
  /// immediate neighbourhood is sparse (e.g. far from the Sun) so there is
  /// always somewhere to travel.
  void _rebuildNearby() {
    final pos = playerPosition3D;
    var radius = _nearbyRadiusLy;
    var found = _universe.planetsNear(pos, radius, cap: 90);
    var tries = 0;
    while (found.length < 10 && tries < 4) {
      radius *= 2;
      found = _universe.planetsNear(pos, radius, cap: 90);
      tries++;
    }
    // Even 960 ly can come up empty — a ship that drifted or spawned far
    // outside the shell has nothing within reach. Fall back to the nearest
    // stars anywhere in the catalogue, which makes an empty `planets` set
    // practically unreachable and leaves the player somewhere to fly.
    if (found.length < 10) {
      found = _universe.nearestPlanets(pos, cap: 90);
    }
    // Make sure an in-flight destination is always resolvable in the set.
    final destId = _activeJourney?.destinationPlanetId;
    if (destId != null && !found.any((p) => p.id == destId)) {
      final dest = _universe.planetById(destId);
      if (dest != null) found = <Planet>[dest, ...found];
    }
    _nearby = List<Planet>.unmodifiable(found);
    _nearbyScanPos = pos;
  }

  /// Rebuilds the nearby set only if the ship has drifted far enough to matter.
  /// A no-op for a parked ship, and for a docked one.
  void _maybeRescanNearby() {
    if (_player.driftVelocity.length == 0) return;
    final last = _nearbyScanPos;
    if (last != null && (playerPosition3D - last).length < _nearbyRescanLy) {
      return;
    }
    _rebuildNearby();
  }

  // --- Journey rules -------------------------------------------------------

  /// Whether voyage [j] resolves by [now] — it either arrives, or its tank runs
  /// dry first, whichever comes sooner.
  bool _voyageResolvesBy(Journey j, DateTime now) =>
      _exhaustedBy(j, now) || j.hasArrivedBy(now);

  /// Whether voyage [j] has burned its last drop by [now].
  ///
  /// A voyage that can afford the whole trip never exhausts, so a mid-flight
  /// top-up genuinely pulls a doomed trip back onto the board rather than
  /// merely postponing the reckoning.
  bool _exhaustedBy(Journey j, DateTime now) {
    if (j.fuelPolicy == FuelPolicy.refuse) return false;
    if (fuelExhaustProgressFor(j) >= 1) return false;
    return !now.isBefore(fuelExhaustTime(j));
  }

  void _reconcileJourney() {
    final journey = _activeJourney;
    if (journey == null) return;
    if (journey.status != JourneyStatus.inProgress) return;
    final now = _now();
    // Fuel can run out before the destination on an under-funded voyage.
    // Resolve that first: `hasArrivedBy` is still false at the exhaust point,
    // so a halting ship would otherwise keep "flying" on an empty tank.
    if (_exhaustedBy(journey, now)) {
      _applyFuelOut(journey, now);
      return;
    }
    if (journey.hasArrivedBy(now)) {
      _applyArrival(journey);
    }
  }

  /// Resolves a voyage whose tank ran dry: bills the whole tank, then either
  /// parks the ship where it stopped ([FuelPolicy.halt]) or sets it coasting
  /// ([FuelPolicy.coast]). The voyage ends either way — what differs is the
  /// velocity the ship is left with.
  void _applyFuelOut(Journey journey, DateTime now) {
    final exhaustAt = fuelExhaustTime(journey);
    final pos = _positionAlong(journey, exhaustAt);
    // Report the powered leg: that is the part that just happened, and the part
    // the player wants named. A powered leg is a straight line at constant
    // speed — the same velocity `_cruiseVelocityOf` already derives — with the
    // shell far enough out that it can never be reached.
    //
    // Built before the anchor below is moved to the exhaust point: both
    // `_originPosOf` and `_cruiseVelocityOf` read the anchor, so on a
    // deep-space origin they would otherwise report the leg as starting where
    // it ended.
    final legSeconds =
        exhaustAt.difference(journey.departure).inMilliseconds / 1000;
    final legFrom = _originPosOf(journey);
    final legTo = _destPosOf(journey) ?? legFrom;
    final leg = DriftPath(
      start: legFrom,
      velocity: _cruiseVelocityOf(journey),
      bound: 1e12,
    );
    final passed = _universe.passedSystemsAlong(
      path: leg,
      upToSeconds: legSeconds,
    );
    _pendingDriftReport = DriftReport(
      kind: DriftReportKind.fuelOut,
      from: journey.departure,
      to: exhaustAt,
      elapsed: exhaustAt.difference(journey.departure),
      // Capped at the route length, because `_positionAlong` clamps there: a
      // tank that empties while the ship waits out a rounded-up arrival time
      // must not report a leg longer than the voyage it is part of.
      distanceLy: math.min(
        leg.travelledBetween(0, legSeconds),
        (legTo - legFrom).length,
      ),
      fromPos: leg.positionAt(0),
      toPos: pos,
      passedCount: passed.count,
      nearest: passed.nearest,
      hitBoundary: false,
    );
    _settleTank(journey, now);
    _activeJourney = null;
    _player = _player.copyWith(
      toDeepSpace: true,
      startX: pos.x,
      startY: pos.y,
      startZ: pos.z,
      clearActiveJourney: true,
      driftVelocity: journey.fuelPolicy == FuelPolicy.coast
          ? _cruiseVelocityOf(journey)
          : const Vec3(0, 0, 0),
      // An out-of-fuel drift is a coast whatever put the ship there: there is
      // nothing left to power it with.
      driftPowered: false,
      // The drift began when the tank emptied, not when the game noticed. A
      // player who was away for the whole coast gets the distance they missed.
      driftStartedAt: exhaustAt,
    );
    _rebuildNearby();
  }

  /// Cruise velocity along a voyage's route, in ly/s. Constant — a coasting
  /// ship neither accelerates nor slows down.
  ///
  /// The magnitude is the engine's own cruise speed rather than
  /// `distance / duration`: the duration is rounded to whole seconds, so
  /// recovering the speed from it would quote a marginally different drift —
  /// and with it a marginally different braking cost — for every route length.
  Vec3 _cruiseVelocityOf(Journey j) {
    final from = _originPosOf(j);
    final to = _destPosOf(j) ?? from;
    final delta = to - from;
    final length = delta.length;
    if (length <= 0) return const Vec3(0, 0, 0);
    return delta * (_ship.engine.cruiseSpeedLyPerSec / length);
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
    final journey = _activeJourney;
    if (journey != null &&
        journey.status == JourneyStatus.inProgress &&
        _voyageResolvesBy(journey, _now())) {
      _reconcileJourney();
      _persist();
      notifyListeners();
      return;
    }
    // A cruise resolves by the clock too, not by a timer — same reason as a
    // voyage: the answer has to be the same whether the app was open for it or
    // killed through it. Checked on the instant rather than through a flag, so a
    // tick that arrives early is simply a tick that does nothing.
    final exhaustAt = _cruiseExhaustTime();
    if (exhaustAt != null && !_now().isBefore(exhaustAt)) {
      _reconcileCruise();
      return;
    }
    // Still travelling, cruising or coasting: repaint without persisting. A
    // drifting ship may also have crossed into a new neighbourhood.
    _maybeRescanNearby();
    notifyListeners();
  }

  /// Validates and starts a journey to [target].
  ///
  /// The voyage's own fuel is checked up front but not deducted — it accrues in
  /// real time and is booked when the voyage ends (see [_settleBurn]). The
  /// braking burn is different: it is charged at departure, by [_anchorHere].
  Future<LaunchResult> launchJourney(
    Planet target, {
    FuelPolicy onEmpty = FuelPolicy.refuse,
  }) async {
    if (target.id == _player.currentPlanetId) return LaunchResult.alreadyHere;
    if (isTraveling) return LaunchResult.alreadyTraveling;
    // The voyage's fuel only — deliberately not `energyCostTo`, which also
    // carries the braking burn and would leak it into the burn curve below.
    final voyageFuel = _ship.engine.energyCostFor(distanceTo(target));
    final braking = brakingCost;
    final gate = _launchGate(voyageFuel, braking, onEmpty);
    if (gate != null) return gate;

    _anchorHere();
    final departure = _now();
    final arrival = departure.add(travelDurationTo(target));
    final journey = Journey(
      id: _newId('jny'),
      // A new player departs from open space (sentinel) until the first arrival.
      originPlanetId: _player.currentPlanetId ?? kDeepSpaceId,
      destinationPlanetId: target.id,
      departure: departure,
      arrival: arrival,
      energyCost: voyageFuel,
      status: JourneyStatus.inProgress,
      fuelPolicy: onEmpty,
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

  /// Energy this ship would burn to reach a star's arrival point — voyage fuel
  /// plus the braking burn, matching [energyCostTo].
  int energyCostToStar(int hygId) =>
      _ship.engine.energyCostFor(distanceToStar(hygId)) + brakingCost;

  /// Launches a journey to a *star* (used for stars with no planets — you drift
  /// in beside it). Mirrors [launchJourney] but the destination is a star.
  Future<LaunchResult> launchToStar(
    int hygId, {
    FuelPolicy onEmpty = FuelPolicy.refuse,
  }) async {
    final target = _universe.starArrivalPoint(hygId);
    if (target == null) return LaunchResult.noSelection;
    if (isTraveling) return LaunchResult.alreadyTraveling;
    final dist = (playerPosition3D - target).length;
    if (dist < 0.5) return LaunchResult.alreadyHere;
    final voyageFuel = _ship.engine.energyCostFor(dist);
    final braking = brakingCost;
    final gate = _launchGate(voyageFuel, braking, onEmpty);
    if (gate != null) return gate;

    _anchorHere();
    final departure = _now();
    final arrival =
        departure.add(Duration(seconds: _ship.engine.secondsFor(dist)));
    final journey = Journey(
      id: _newId('jny'),
      originPlanetId: _player.currentPlanetId ?? kDeepSpaceId,
      destinationPlanetId: _starDestId(hygId),
      departure: departure,
      arrival: arrival,
      energyCost: voyageFuel,
      status: JourneyStatus.inProgress,
      fuelPolicy: onEmpty,
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

  /// The ship's current 3D position partway along [j] at [now], flying at the
  /// engine's cruise speed. Derived from the clock, so there is no stored
  /// position to drift out of sync.
  ///
  /// Flown at the engine's speed rather than interpolated by `progressAt`,
  /// because `totalDuration` is rounded to whole seconds: a position taken from
  /// it would imply a marginally different speed than the ship actually has —
  /// and the fuel-out report, which measures the leg with the engine's speed,
  /// would then disagree with the position it reports. Clamped at the
  /// destination so a ship that reaches it before the booked arrival time waits
  /// there instead of overshooting.
  Vec3 _positionAlong(Journey j, DateTime now) {
    final from = _originPosOf(j);
    final to = _destPosOf(j) ?? from;
    final delta = to - from;
    final length = delta.length;
    if (length <= 0) return from;
    final elapsed = now.difference(j.departure).inMilliseconds / 1000;
    final travelled = _ship.engine.cruiseSpeedLyPerSec * math.max(0, elapsed);
    return from + delta * (math.min(travelled, length) / length);
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

  /// Whether the ship can currently be brought out of its motion.
  ///
  /// False only for a ship with momentum that cannot afford the braking burn — the
  /// UI uses this to disable the brake rather than letting the tap do nothing.
  bool get canBrake => !hasMomentum || _player.energyBalance >= brakingCost;

  /// Energy the current cruise leg has burned but not yet booked.
  ///
  /// Zero for anything that is not a powered drift — including a cruise leg that
  /// has just been re-pinned, where the honest answer is "nothing yet" rather
  /// than `burnForSeconds(0)`, which is `minEnergyCost` and would book a phantom
  /// light-year every time the ship stopped.
  int _cruiseBurnNow() {
    if (!isCruising) return 0;
    final seconds = _driftSecondsAt(_now());
    if (seconds <= 0) return 0;
    return _ship.engine.burnForSeconds(seconds);
  }

  /// Books the energy the current cruise leg has burned and re-pins the leg to
  /// now, so the next leg is measured from here.
  ///
  /// Idempotent: re-pinning sets `driftStartedAt` to now, which makes the very
  /// next `_cruiseBurnNow()` zero. That is what lets `stopShip` settle before
  /// checking the brake *and* `_anchorHere` settle on its own — two call sites,
  /// one booking.
  int _settleCruise() {
    if (!isCruising) return 0;
    final burned = _cruiseBurnNow();
    final now = _now();
    if (burned > 0) {
      _player = _player.copyWith(
        energyBalance: math.max(0, _player.energyBalance - burned),
      );
      _energyLedger.add(EnergyTransaction(
        id: _newId('en'),
        type: EnergyTxType.cruiseCost,
        amount: -burned,
        createdAt: now,
      ));
    }
    _repinLeg(at: now);
    _syncDormancy();
    return burned;
  }

  /// The instant the current cruise runs out of the energy it is allowed to
  /// spend, or null when the ship is not cruising.
  ///
  /// The `budget <= 0` branch returns "now", so a cruise with nothing spendable
  /// resolves on the next tick rather than dividing by nothing. It is
  /// defence-in-depth: ignition is meant to be gated on a spendable budget
  /// (`energy <= cruiseReserve` → `insufficientEnergy`), and once it is, a
  /// cruising ship always has budget to spend and the branch is unreachable from
  /// the public API. Today `igniteCruise` only rejects `energy <= 0`, so a ship
  /// can still be lit with `0 < energy <= cruiseReserve`.
  ///
  /// Compared on *time*, not on energy: `burnForSeconds` rounds to whole EN, so
  /// testing `burnForSeconds(elapsed) >= budget` fires a tick early — at a
  /// budget of 200 it first reaches 200 at 2992.5 s, and the halt point lands
  /// 0.2 ly short of the 80 ly the readout promised. Division keeps it exact:
  /// `secondsForEnergy(200)` is 3000.0.
  DateTime? _cruiseExhaustTime() {
    if (!isCruising) return null;
    final budget = _player.energyBalance - cruiseReserve;
    if (budget <= 0) return _player.driftStartedAt;
    final seconds = _ship.engine.secondsForEnergy(budget);
    return _player.driftStartedAt.add(
      Duration(
          microseconds:
              (seconds * Duration.microsecondsPerSecond).round()),
    );
  }

  /// The report for the leg of a cruise that just ran the tank dry.
  ///
  /// A cruise has no destination, so there is no route to report against — the
  /// leg between the last turn (or ignition) and the exhaust point is the whole
  /// of what happened. `bound` is huge for the same reason `_applyFuelOut` uses
  /// `1e12`: the leg is a straight line that cannot reach the shell in the time
  /// it has.
  DriftReport _cruiseDriftReport(DateTime exhaustAt, Vec3 fromPos, Vec3 toPos) {
    final start = Vec3(_player.startX, _player.startY, _player.startZ);
    final leg = DriftPath(
      start: start,
      velocity: _player.driftVelocity,
      bound: 1e12,
    );
    final seconds =
        exhaustAt.difference(_player.driftStartedAt).inMilliseconds / 1000;
    final passed = _universe.passedSystemsAlong(path: leg, upToSeconds: seconds);
    return DriftReport(
      kind: DriftReportKind.fuelOut,
      from: _player.driftStartedAt,
      to: exhaustAt,
      elapsed: exhaustAt.difference(_player.driftStartedAt),
      distanceLy: leg.travelledBetween(0, seconds),
      fromPos: fromPos,
      toPos: toPos,
      passedCount: passed.count,
      nearest: passed.nearest,
      hitBoundary: false,
    );
  }

  /// Closes out a cruise whose tank has run dry, at the moment it ran dry.
  ///
  /// Like [_reconcileJourney] this is a pure function of the clock: it can run a
  /// second late, a day late, or after the app was killed, and still place the
  /// ship, the ledger and the report where they belong. It leaves the ship
  /// *dormant* with the braking reserve intact — a cruise always keeps enough to
  /// buy its own stop, which is the whole reason the reserve exists.
  Future<void> _reconcileCruise() async {
    final exhaustAt = _cruiseExhaustTime();
    if (exhaustAt == null) return;
    if (_now().isBefore(exhaustAt)) return;
    final path = driftPath!;
    final exhaustSeconds = _driftSecondsAt(exhaustAt);
    final fromPos = path.positionAt(0);
    final exhaustPos = path.positionAt(exhaustSeconds);
    // Built before the anchor moves: the report reads the same anchor the path
    // was built from, so doing this afterwards would report a zero-length leg.
    _pendingDriftReport = _cruiseDriftReport(exhaustAt, fromPos, exhaustPos);

    // Bill the leg up to the moment the tank ran dry — never up to `now`, which
    // can be a day later. The ship had no spendable energy for the whole of that
    // interval, so charging for it would invent a burn that never happened.
    final burned = _player.energyBalance - cruiseReserve;
    if (burned > 0) {
      _player = _player.copyWith(energyBalance: _player.energyBalance - burned);
      _energyLedger.add(EnergyTransaction(
        id: _newId('en'),
        type: EnergyTxType.cruiseCost,
        amount: -burned,
        createdAt: exhaustAt,
      ));
    }

    // `halt` spends the momentum instead of the energy; `coast` keeps it and
    // drifts on with the engine off. Either way the engine is done.
    final halt = _player.cruisePolicy == FuelPolicy.halt;
    _player = _player.copyWith(
      startX: exhaustPos.x,
      startY: exhaustPos.y,
      startZ: exhaustPos.z,
      driftStartedAt: exhaustAt,
      driftVelocity: halt ? const Vec3(0, 0, 0) : _player.driftVelocity,
      driftPowered: false,
      engineDormant: true,
    );
    _rebuildNearby();
    await _persist();
    notifyListeners();
  }

  /// Shuts the engine down when a settlement has left the tank empty.
  ///
  /// Called at the end of every settlement that moves energy, so no rule can
  /// spend the last drop without the shutdown following. A settlement with
  /// nothing to book returns before reaching the sync — `_settleBurn` and
  /// `_settleCruise` both do — which is harmless: a settlement that moves no
  /// energy cannot create a new dormancy. Deliberately *not* called from
  /// `_addEnergy`: training refills the tank but does not restart the engine —
  /// that is what [activate] is for, and it is the difference between a setback
  /// and a free recovery.
  ///
  /// Not the only way to become dormant, despite the name: a cruise that runs
  /// dry stops on its *spendable budget* (`balance - cruiseReserve`) and keeps
  /// its braking reserve, so `_reconcileCruise` sets the flag itself with 100 EN
  /// still in the tank — this predicate would read that tank as full and leave
  /// the engine running. Do not "unify" the two: routing `_reconcileCruise`
  /// through here would fail to set the flag, leaving every exhausted cruise's
  /// engine running.
  void _syncDormancy() {
    if (_player.engineDormant) return;
    if (_player.energyBalance > 0) return;
    _player = _player.copyWith(engineDormant: true);
  }

  /// Pays the activation fee and brings a dormant engine back online.
  ///
  /// Returns false when there is nothing to do — the engine is already running,
  /// or the tank cannot cover the fee. Deliberately does *not* call
  /// `_syncDormancy`: a player who spends their last 5 EN waking the engine ends
  /// up awake with nothing, which is a worse position than dormant with nothing
  /// but is exactly what they asked for. Re-dormanting them would be the game
  /// quietly taking the decision back.
  Future<bool> activate() async {
    if (!isDormant) return false;
    final cost = _ship.engine.activationCost;
    if (_player.energyBalance < cost) return false;
    _player = _player.copyWith(
      energyBalance: _player.energyBalance - cost,
      engineDormant: false,
    );
    _energyLedger.add(EnergyTransaction(
      id: _newId('en'),
      type: EnergyTxType.activation,
      amount: -cost,
      createdAt: _now(),
    ));
    await _persist();
    notifyListeners();
    return true;
  }

  /// Energy a cruise must keep in the tank so it can always buy its own stop.
  ///
  /// State-independent on purpose: it is a property of the engine and the speed
  /// a cruise runs at, not of where the ship happens to be, so the exhaustion
  /// rule and the readout cannot disagree about it.
  int get cruiseReserve =>
      _ship.engine.brakingCostFor(_ship.engine.cruiseSpeedLyPerSec);

  /// How long the tank can keep driving the current cruise, counting the reserve
  /// it has to hold back. Zero when parked, coasting, or already at the reserve.
  Duration get cruiseRemaining {
    if (!isCruising) return Duration.zero;
    final budget = energy - cruiseReserve;
    if (budget <= 0) return Duration.zero;
    return Duration(
      microseconds: (_ship.engine.secondsForEnergy(budget) *
              Duration.microsecondsPerSecond)
          .round(),
    );
  }

  /// Brings the ship to rest where it is, whatever is moving it.
  ///
  /// One entry point for the whole idea, so the UI does not have to know which
  /// kind of motion the ship is in. A voyage in progress is billed for the fuel
  /// it has burned and the ship parks at the point it had reached — see
  /// [abortJourney]. A coasting ship must first shed its cruise velocity: that
  /// braking burn is billed, and the ship then parks at the point the drift had
  /// carried it to. A parked ship is left alone.
  ///
  /// Deliberately does *not* rebuild the nearby set. While coasting that set is
  /// refreshed only every [_nearbyRescanLy] ly, so braking can leave it that far
  /// out of date — harmless, because quotes are recomputed from
  /// [playerPosition3D] rather than read off the set. [abortJourney] does
  /// rebuild, because that one moves the ship to a point it never scanned from.
  Future<void> stopShip() async {
    final journey = _activeJourney;
    if (journey != null && journey.status == JourneyStatus.inProgress) {
      return abortJourney();
    }
    if (!hasMomentum) return;
    // The leg's burn is owed before the brake can be quoted or afforded, and it
    // is spent whether or not the brake goes ahead — so this runs before the
    // gate, and the state is persisted either way.
    _settleCruise();
    if (!canBrake) {
      await _persist();
      notifyListeners();
      return;
    }
    _anchorHere();
    await _persist();
    notifyListeners();
  }

  /// Lights the engine with no destination: the ship accelerates to cruise speed
  /// along [heading] and starts burning the tank every second.
  ///
  /// Ignition itself is free — the price of a cruise is the power it draws, and
  /// charging twice for the same departure would make free cruise a worse deal
  /// than a voyage to nowhere. [onEmpty] is *required* rather than defaulted
  /// because a cruise has no arrival to fall back on: what happens when the tank
  /// runs dry has to be decided before it does, and it is persisted on the
  /// player because that moment can be hours later, or after a restart.
  Future<LaunchResult> igniteCruise(
    Vec3 heading, {
    required FuelPolicy onEmpty,
  }) async {
    final direction = heading.normalized;
    if (direction.length <= 0) return LaunchResult.noSelection;
    if (hasMomentum) return LaunchResult.alreadyTraveling;
    if (isTraveling) return LaunchResult.alreadyTraveling;
    if (!_player.inDeepSpace) return LaunchResult.alreadyHere;
    if (_player.energyBalance <= 0) return LaunchResult.insufficientEnergy;

    _repinLeg(velocity: direction * _ship.engine.cruiseSpeedLyPerSec);
    _player = _player.copyWith(driftPowered: true, cruisePolicy: onEmpty);
    await _persist();
    notifyListeners();
    return LaunchResult.success;
  }

  /// Turns the ship around mid-flight: launches a fresh journey from the point
  /// reached so far back to where the active journey departed from. The return
  /// quote is checked against the post-burn balance before the outbound leg is
  /// settled (fuel burns both ways); the return leg then burns like any other
  /// voyage and settles on arrival. Returns the launch outcome so the UI can
  /// report e.g. insufficient energy.
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
    final dist = (originPos - currentPos).length;
    final cost = _ship.engine.energyCostFor(dist);
    // The return quote is checked against the balance the player actually has
    // left, i.e. after the outbound burn — but check it *before* settling.
    // Settling and then bailing out would leave this voyage still in flight,
    // and its arrival would book the same fuel a second time.
    if (_player.energyBalance - journey.burnedAt(now) < cost) {
      return LaunchResult.insufficientEnergy;
    }
    _settleBurn(journey, now);

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
      driftVelocity: const Vec3(0, 0, 0),
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
    // The voyage that brought us here is complete. Safe to clear without a
    // settle: the destination guard can only match an already-settled `arrived`
    // voyage, so a widened guard would have to settle first.
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

  /// Whether a voyage can be committed under [policy]. Null means yes.
  ///
  /// [FuelPolicy.refuse] demands the whole quote up front — the rule the game
  /// has always had. [FuelPolicy.halt] and [FuelPolicy.coast] only need a drop
  /// of fuel, because the ship is explicitly allowed to run dry en route.
  ///
  /// [braking] is passed separately from [voyageFuel] because the two are not
  /// the same kind of money: the voyage's fuel accrues over the route, while
  /// the braking burn is charged at departure. Under the lenient policies the
  /// drop of fuel the voyage needs is what is *left after* braking, so the bar
  /// is `> braking` rather than `> 0`.
  LaunchResult? _launchGate(int voyageFuel, int braking, FuelPolicy policy) {
    // The *live* balance, not `_player.energyBalance`: a cruise's accrued burn
    // is real money that has not reached the ledger yet, and a gate reading the
    // raw field would let a player launch on energy they no longer have. The two
    // are identical in every other state, because a voyage in progress returns
    // from `launchJourney` long before this.
    final available = energy;
    if (policy == FuelPolicy.refuse) {
      return available < voyageFuel + braking
          ? LaunchResult.insufficientEnergy
          : null;
    }
    return available <= braking ? LaunchResult.insufficientEnergy : null;
  }

  /// Books the fuel voyage [j] has burned up to [now], once, and returns it.
  ///
  /// Nothing is deducted at launch, so this is where a voyage's cost actually
  /// reaches the ledger. The invariant is *exactly one settle per voyage-ending
  /// path*: `burnedAt(now)` reads only `energyCost` and `progressAt(now)`, never
  /// `status`, so settling before or after the status flip books the same
  /// amount — it is the single call site, not the ordering, that prevents
  /// double-booking. By convention each path still calls it *before* the
  /// journey is cleared, which keeps the ledger entry attributable to a journey
  /// that still exists.
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
    _syncDormancy();
    return burned;
  }

  /// Bills the burn that brings a coasting ship to rest.
  ///
  /// Unlike a voyage's fuel, this is charged at the moment it is committed:
  /// there is no curve to spread it over, and the gate has already established
  /// that the balance covers it. The `braking > 0` guard at the call site is
  /// what keeps a parked ship's anchor from writing a zero-amount entry.
  void _settleBraking(int amount) {
    _player = _player.copyWith(
      energyBalance: math.max(0, _player.energyBalance - amount),
    );
    _energyLedger.add(EnergyTransaction(
      id: _newId('en'),
      type: EnergyTxType.braking,
      amount: -amount,
      createdAt: _now(),
    ));
    _syncDormancy();
  }

  /// Bills the entire tank.
  ///
  /// Used when fuel runs out, where "what is left" and "what burned" are the
  /// same number by definition — so this is exact, unlike re-deriving the burn
  /// from a rounded progress fraction.
  void _settleTank(Journey journey, DateTime now) {
    final drained = _player.energyBalance;
    if (drained > 0) {
      _player = _player.copyWith(energyBalance: 0);
      _energyLedger.add(EnergyTransaction(
        id: _newId('en'),
        type: EnergyTxType.travelCost,
        amount: -drained,
        createdAt: now,
        relatedObjectId: journey.id,
      ));
    }
    // Runs even when the tank was already empty: this is the moment the ship is
    // known to be out of power, and the only moment that knows it.
    _syncDormancy();
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
    _pendingDriftReport = null;
    _discoveries.clear();
    _energyLedger.clear();
    _trainingSessions.clear();
    _planetStates.clear();
    _startFresh();
    await _persist();
    notifyListeners();
  }
}
