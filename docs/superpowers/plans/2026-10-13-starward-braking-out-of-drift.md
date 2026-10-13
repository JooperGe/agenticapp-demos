# Starward 滑行制动 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a coasting ship a real way out — a braking burn that costs energy, billed at the one choke point every exit already passes through, plus the UI actions to trigger it.

**Architecture:** The braking price is a property of the *engine* (`brakingDistanceLy`), not a global constant, and the charge is booked inside `GameController._anchorHere()` — the single existing call site both launch paths funnel through. That placement is what makes "launch from the star map" stop being a free escape, without writing the charge twice. `Journey.energyCost` stays fuel-only so the burn curve (`burnedAt` = `round(energyCost × progress)`) is untouched; the braking burn is a separate, up-front ledger entry.

**Tech Stack:** Flutter / Dart. `flutter_test` with a `FakeClock`, fixed `math.Random` seed, and `MemoryStorage`. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-13-starward-braking-out-of-drift-design.md`

## Global Constraints

- Layer discipline: `lib/core` → `lib/data` → `lib/state` → `lib/ui`. UI never reads storage directly; all rules live on `GameController`.
- Attributes belong to their owning entity. A number describing the engine is a field on `Engine`. `Balance` holds only cross-entity economy. Derived calculations are methods on the entity (`Engine.energyCostFor(ly)`), never top-level functions reading globals.
- Models are immutable: `final` fields, `const` constructors, changes return a new instance via `copyWith`/named methods.
- **Migrate, do not bump `_saveKey`.** The save key stays `starward.save.v2`. New fields fall back to a sensible default when absent.
- TDD: write the failing test first, run it and watch it fail, then implement.
- Tests pin concrete numbers (as `test/ship_test.dart` does for the standard engine) so "the refactor changed nothing" is verifiable rather than asserted.
- `flutter analyze` must report **No issues found** and `flutter test` must be fully green at the end of every task.
- The reference economy, verbatim from spec §4: `Balance.initialEnergy` 300 EN; training rewards 40 / 70 / 50 EN; `Balance.explorationReward` 15 EN; standard engine `energyPerLy` 2.5, `travelSecondsPerLy` 37.5, `minEnergyCost` 1, `minTravelSeconds` 15; cruise speed 1 / 37.5 = 0.0266667 ly/s.
- The one pricing decision, verbatim: **`Engine.standard.brakingDistanceLy = 40` → `energyCostFor(40)` = 100 EN.**
- The one invariant, verbatim: **`driftVelocity` going from non-zero to zero books exactly one `braking` entry.**
- UI copy is Chinese, matching the surrounding screens.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `starward/lib/data/models/engine.dart` | Engine braking capability and its quote | Modify |
| `starward/lib/data/models/energy_transaction.dart` | Ledger entry kinds | Modify |
| `starward/lib/state/game_controller.dart` | All rules: braking price, the charge, the gate, `stopShip` | Modify |
| `starward/lib/ui/journey/journey_page.dart` | Coasting panel actions and confirmations | Modify |
| `starward/lib/ui/journey/fuel_choice_dialog.dart` | Under-funded launch dialog | Modify |
| `starward/lib/ui/galaxy/planet_details_sheet.dart` | Launch button and its insufficiency hint | Modify |
| `starward/lib/ui/galaxy3d/galaxy_map_3d_page.dart` | Star-launch path's dialog call and empty-tank guard | Modify |
| `starward/lib/ui/shell/home_shell.dart` | Voyage tab badge | Modify |
| `starward/test/braking_test.dart` | Everything the spec's §9.1 demands | **Create** |

No file is split or moved. `game_controller.dart` and `journey_page.dart` are large, but they are already the established homes for rules and for this screen respectively; restructuring them is out of scope for this change.

---

## Phase 1 — 制动地基

Ships on its own. Player-visible change: launching from the star map while coasting now costs extra.

---

### Task 1: The engine learns to brake

**Files:**
- Modify: `starward/lib/data/models/engine.dart`
- Test: `starward/test/braking_test.dart` (create)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `Engine.brakingDistanceLy` — `double`, the distance the engine needs to shed one cruise speed's worth of velocity.
  - `Engine.cruiseSpeedLyPerSec` — `double` getter, `1 / travelSecondsPerLy`.
  - `Engine.brakingCostFor(double speedLyPerSec)` → `int`, EN to shed that speed. Returns `0` for `speedLyPerSec <= 0`.

- [ ] **Step 1: Write the failing test**

Create `starward/test/braking_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/models/engine.dart';

void main() {
  group('Engine braking', () {
    test('a full cruise burn costs what flying the braking distance costs', () {
      const e = Engine.standard;
      expect(e.travelSecondsPerLy, 37.5, reason: 'the pinned reference engine');
      expect(e.cruiseSpeedLyPerSec, closeTo(0.0266667, 1e-7));
      expect(e.brakingDistanceLy, 40);
      expect(e.energyCostFor(40), 100, reason: 'the quote this all rests on');
      expect(e.brakingCostFor(e.cruiseSpeedLyPerSec), 100);
    });

    test('half a cruise speed costs half as much', () {
      const e = Engine.standard;
      expect(e.brakingCostFor(e.cruiseSpeedLyPerSec / 2), 50);
    });

    test('a ship at rest is quoted nothing, not the minEnergyCost floor', () {
      const e = Engine.standard;
      expect(e.minEnergyCost, 1,
          reason: 'the floor this guard exists to dodge');
      expect(e.brakingCostFor(0), 0);
      expect(e.brakingCostFor(-0.5), 0);
    });

    test('braking distance survives a JSON round trip', () {
      final back = Engine.fromJson(Engine.standard.toJson());
      expect(back.brakingDistanceLy, 40);
      expect(back.brakingCostFor(back.cruiseSpeedLyPerSec), 100);
    });

    test('an engine saved before braking existed falls back to the standard',
        () {
      final json = Engine.standard.toJson()..remove('brakingDistanceLy');
      expect(json.containsKey('brakingDistanceLy'), isFalse,
          reason: 'precondition: this is what an old save looks like');

      final back = Engine.fromJson(json);
      expect(back.brakingDistanceLy, Engine.standard.brakingDistanceLy);
      expect(back.brakingCostFor(back.cruiseSpeedLyPerSec), 100);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd starward && flutter test test/braking_test.dart`
Expected: FAIL — compile error, `The getter 'cruiseSpeedLyPerSec' isn't defined for the type 'Engine'`.

- [ ] **Step 3: Write the minimal implementation**

In `starward/lib/data/models/engine.dart`, add the field to the constructor and the field list. Place `brakingDistanceLy` after `travelSecondsPerLy`:

```dart
  const Engine({
    required this.id,
    required this.name,
    required this.energyPerLy,
    required this.travelSecondsPerLy,
    required this.brakingDistanceLy,
    required this.minEnergyCost,
    required this.minTravelSeconds,
  });
```

```dart
  /// Seconds of flight per light-year.
  final double travelSecondsPerLy;

  /// Distance the engine needs to shed one cruise speed's worth of velocity.
  /// Braking from a full cruise burn costs what flying this far costs.
  ///
  /// A distance rather than a flat EN price, because "how much does this engine
  /// need to cancel its own speed" is a property of the engine — a refit that
  /// brakes harder should not have to also edit a global cost table.
  final double brakingDistanceLy;
```

Add the two derived members after `reachableLyFor`:

```dart
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
```

Add the value to `Engine.standard`:

```dart
  static const Engine standard = Engine(
    id: 'engine.standard',
    name: '标准聚变引擎',
    energyPerLy: 2.5,
    travelSecondsPerLy: 37.5,
    brakingDistanceLy: 40,
    minEnergyCost: 1,
    minTravelSeconds: 15,
  );
```

Add the migration fallback to `fromJson` and the key to `toJson`:

```dart
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
```

- [ ] **Step 3b: Add the field to the four test engines that build `Engine(...)` literally**

`brakingDistanceLy` is required, so these stop compiling until they name it. Use `40` — the same value as the standard engine. These engines vary *fuel economy* (`_greedy` at 1000 EN/ly, `_thrifty` at 1.5 EN/ly), not braking, and none of the tests that use them coast, so the value is behaviourally inert; anything else would invent game balance the spec did not ask for.

`starward/test/flight_panel_test.dart:258` and `starward/test/drift_report_test.dart:55` (both `_greedy`) — add one line after `travelSecondsPerLy`:

```dart
const _greedy = Engine(
  id: 'test.greedy',
  name: '测试引擎',
  energyPerLy: 1000,
  travelSecondsPerLy: 37.5,
  brakingDistanceLy: 40,
  minEnergyCost: 1,
  minTravelSeconds: 15,
);
```

`starward/test/ship_test.dart:16` (`_thrifty`) — same insertion:

```dart
const Engine _thrifty = Engine(
  id: 'engine.thrifty',
  name: '节能引擎',
  energyPerLy: 1.5,
  travelSecondsPerLy: 50,
  brakingDistanceLy: 40,
  minEnergyCost: 1,
  minTravelSeconds: 15,
);
```

`starward/test/return_to_origin_test.dart:146` (inline) — same insertion:

```dart
      await c.installEngine(const Engine(
        id: 'test.greedy',
        name: '测试引擎',
        energyPerLy: 1000,
        travelSecondsPerLy: 37.5,
        brakingDistanceLy: 40,
        minEnergyCost: 1,
        minTravelSeconds: 15,
      ));
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd starward && flutter test test/braking_test.dart`
Expected: PASS — 5 tests.

Then confirm nothing else broke, because `Engine` gained a required constructor parameter. `Engine.standard` is the only construction site in `lib/`; the four test constructions handled in Step 3b are the only others in the repo:

Run: `cd starward && flutter analyze && flutter test`
Expected: `No issues found!` and all tests green.

- [ ] **Step 5: Commit**

```bash
cd starward
git add lib/data/models/engine.dart test/braking_test.dart \
        test/flight_panel_test.dart test/drift_report_test.dart \
        test/ship_test.dart test/return_to_origin_test.dart
git commit -m "feat(starward): give the engine a braking distance and a quote for it

A coasting ship has momentum and nothing in the model prices shedding it.
The braking price belongs on the engine, not in Balance: \"how far this
engine needs to travel to cancel its own cruise speed\" is a property of
the engine, so a future refit is one field, not a global-table edit.

Zero speed is quoted 0, not minEnergyCost's 1 — energyCostFor floors, and
without the guard a parked ship would be charged 1 EN to not move.

Old saves carry ship.engine with no brakingDistanceLy; fromJson falls back
to the standard rather than throwing, per the migrate-don't-bump rule."
```

---

### Task 2: The braking burn, billed at the anchor

**Files:**
- Modify: `starward/lib/data/models/energy_transaction.dart`
- Modify: `starward/lib/state/game_controller.dart`
- Test: `starward/test/braking_test.dart`

**Interfaces:**
- Consumes: `Engine.brakingCostFor` (Task 1), `Engine.cruiseSpeedLyPerSec` (Task 1).
- Produces:
  - `EnergyTxType.braking` — new enum member.
  - `GameController.brakingCost` → `int`, EN to bring the ship out of its current motion. `0` unless coasting.
  - `GameController._settleBraking(int amount)` → `void`, private.
  - `GameController._launchGate(int voyageFuel, int braking, FuelPolicy policy)` → `LaunchResult?`. **Signature changed** from `(int cost, FuelPolicy policy)`.
  - `GameController.isCoasting` already exists and is unchanged.

- [ ] **Step 1: Write the failing tests**

Append to `starward/test/braking_test.dart`. First replace the import block at the top of the file with:

```dart
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/vec3.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/models/energy_transaction.dart';
import 'package:starward/data/models/engine.dart';
import 'package:starward/data/storage/storage_backend.dart';
import 'package:starward/state/game_controller.dart';
```

Then add these helpers above `void main()`:

```dart
class FakeClock {
  FakeClock(this._now);
  DateTime _now;
  DateTime call() => _now;
  void advance(Duration d) => _now = _now.add(d);
}

Future<GameController> _boot(FakeClock clock, MemoryStorage storage) async {
  final c = GameController(
    repository: GameRepository(storage),
    clock: clock.call,
    random: math.Random(3),
  );
  await c.init();
  return c;
}

/// Rewrites the saved balance so the ship starts with exactly [balance] EN.
Future<void> _setEnergy(MemoryStorage storage, int balance) async {
  final raw = await storage.read('starward.save.v2');
  final json = jsonDecode(raw!) as Map<String, dynamic>;
  (json['player'] as Map<String, dynamic>)['energyBalance'] = balance;
  await storage.write('starward.save.v2', jsonEncode(json));
}

/// Rewrites the saved drift so the ship is coasting from its anchor.
Future<void> _setDrift(
  MemoryStorage storage,
  Vec3 velocity,
  DateTime startedAt,
) async {
  final raw = await storage.read('starward.save.v2');
  final json = jsonDecode(raw!) as Map<String, dynamic>;
  final player = json['player'] as Map<String, dynamic>;
  player['driftVelocityX'] = velocity.x;
  player['driftVelocityY'] = velocity.y;
  player['driftVelocityZ'] = velocity.z;
  player['driftStartedAt'] = startedAt.millisecondsSinceEpoch;
  await storage.write('starward.save.v2', jsonEncode(json));
}

/// A controller whose ship is coasting at the standard engine's own cruise
/// speed — so the braking quote is exactly the reference 100 EN — carrying
/// [energy] EN.
Future<GameController> _coasting(
  FakeClock clock,
  MemoryStorage storage, {
  int energy = 300,
}) async {
  await _boot(clock, storage);
  await _setEnergy(storage, energy);
  await _setDrift(
    storage,
    const Vec3(1 / 37.5, 0, 0),
    clock(),
  );
  final c = await _boot(clock, storage);
  expect(c.isCoasting, isTrue, reason: 'precondition: the ship is drifting');
  return c;
}
```

Then add these groups inside `void main()`:

```dart
  group('GameController.brakingCost', () {
    test('is zero for a ship that is not coasting', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock, MemoryStorage());
      expect(c.brakingCost, 0);
    });

    test('is the engine quote while coasting', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _coasting(clock, MemoryStorage());
      expect(c.brakingCost, 100);
    });
  });

  group('the braking burn', () {
    test('a launch from a drift books it once, on top of the voyage fuel',
        () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _coasting(clock, storage, energy: 100000);
      final target = c.planets.first;
      final voyageFuel = c.ship.engine.energyCostFor(c.distanceTo(target));
      expect(voyageFuel, greaterThan(0), reason: 'precondition');

      expect(await c.launchJourney(target), LaunchResult.success);

      final braking =
          c.energyLedger.where((t) => t.type == EnergyTxType.braking).toList();
      expect(braking.length, 1);
      expect(braking.single.amount, -100);
      expect(c.isCoasting, isFalse);
      // Only the braking burn has been deducted: voyage fuel accrues with
      // progress, and at t=0 no progress has been made.
      expect(c.energy, 100000 - 100);
    });

    test('keeps the braking burn out of the voyage quote', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _coasting(clock, storage, energy: 100000);
      final target = c.planets.first;
      final voyageFuel = c.ship.engine.energyCostFor(c.distanceTo(target));

      await c.launchJourney(target);

      expect(c.activeJourney!.energyCost, voyageFuel,
          reason: 'burnedAt = round(energyCost * progress); folding 100 EN of '
              'braking in here would spread it over the whole route and move '
              'the fuel-out point');
    });

    test('a parked ship books nothing when it launches', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock, MemoryStorage());
      expect(c.brakingCost, 0, reason: 'precondition');

      await c.launchJourney(c.planets.first);

      expect(
        c.energyLedger.where((t) => t.type == EnergyTxType.braking),
        isEmpty,
        reason: 'the braking > 0 guard keeps a zero-amount entry out of the '
            'ledger',
      );
    });
  });

  group('the launch gate with a drift to shed', () {
    test('a balance below the braking cost cannot leave at all', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _coasting(clock, MemoryStorage(), energy: 50);
      expect(c.brakingCost, 100, reason: 'precondition');

      expect(await c.launchJourney(c.planets.first),
          LaunchResult.insufficientEnergy);

      expect(c.energy, 50, reason: 'nothing was charged');
      expect(c.isCoasting, isTrue, reason: 'the ship is still drifting');
      expect(c.energyLedger, isEmpty);
    });

    test('exactly the braking cost is still not enough to leave', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _coasting(clock, MemoryStorage(), energy: 100);

      expect(await c.launchJourney(c.planets.first, onEmpty: FuelPolicy.halt),
          LaunchResult.insufficientEnergy);
      expect(c.isCoasting, isTrue);
    });

    test('one EN past the braking cost is enough to run dry en route',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _coasting(clock, MemoryStorage(), energy: 101);

      expect(await c.launchJourney(c.planets.first, onEmpty: FuelPolicy.halt),
          LaunchResult.success);
      expect(c.energy, 1,
          reason: 'the braking burn came off the top, leaving the drop the '
              'halt policy asks for');
    });

    test('an under-funded refuse launch still demands the whole quote',
        () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _coasting(clock, storage, energy: 300);
      final target = c.planets.first;
      final voyageFuel = c.ship.engine.energyCostFor(c.distanceTo(target));
      // One EN short of voyage fuel + braking.
      await _setEnergy(storage, voyageFuel + 100 - 1);
      final c2 = await _boot(clock, storage);

      expect(await c2.launchJourney(target), LaunchResult.insufficientEnergy);
      expect(c2.isCoasting, isTrue);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd starward && flutter test test/braking_test.dart`
Expected: FAIL — compile errors, `The getter 'brakingCost' isn't defined for the type 'GameController'`.

- [ ] **Step 3: Add the ledger type**

In `starward/lib/data/models/energy_transaction.dart`, change the enum:

```dart
/// Kinds of energy ledger entries.
enum EnergyTxType { travelCost, trainingReward, explorationReward, braking }
```

`energyTxTypeFromName` needs no change: it already has `orElse: () => EnergyTxType.travelCost`, so a save holding only the three old names still loads. Appending a member does not rename any existing one.

- [ ] **Step 4: Add `brakingCost` to the controller**

In `starward/lib/state/game_controller.dart`, add immediately after `isCoasting` (currently around `:272`):

```dart
  /// What it costs to bring the ship out of its current motion, in EN.
  ///
  /// Zero for a ship at rest — docked, parked in deep space, or under power.
  /// Only a coasting ship has momentum to shed.
  int get brakingCost => isCoasting
      ? _ship.engine.brakingCostFor(_player.driftVelocity.length)
      : 0;
```

- [ ] **Step 5: Charge it inside `_anchorHere`**

Replace `_anchorHere` (currently around `:371`) with:

```dart
  /// Pins the deep-space anchor to where the ship actually is right now, and
  /// stops any drift — the engine is taking over the motion.
  ///
  /// Every launch must do this: [_originPosOf] reads the anchor, so a coasting
  /// ship that launched without re-anchoring would plot its route from a stale
  /// coordinate and arrive somewhere it never was.
  ///
  /// This is also the one place a drift is billed. Putting the charge here
  /// rather than on the "stop" button is what keeps the exits honest: the star
  /// map is a way out of a drift, and if it were free the player would learn to
  /// route around the paid button sitting next to it.
  void _anchorHere() {
    // Read the price before the velocity is cleared — braking is quoted off the
    // speed the ship is actually carrying.
    final braking = brakingCost;
    final pos = playerPosition3D;
    _player = _player.copyWith(
      startX: pos.x,
      startY: pos.y,
      startZ: pos.z,
      driftVelocity: const Vec3(0, 0, 0),
    );
    if (braking > 0) _settleBraking(braking);
  }
```

Add `_settleBraking` directly after `_settleBurn` (currently around `:1045`):

```dart
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
  }
```

- [ ] **Step 6: Split the gate and the two launch quotes**

Replace `_launchGate` (currently around `:1026`) with:

```dart
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
    if (policy == FuelPolicy.refuse) {
      return _player.energyBalance < voyageFuel + braking
          ? LaunchResult.insufficientEnergy
          : null;
    }
    return _player.energyBalance <= braking
        ? LaunchResult.insufficientEnergy
        : null;
  }
```

In `launchJourney` (currently around `:710`), replace the body from the doc comment down to the `Journey(...)` construction:

```dart
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
```

In `launchToStar` (currently around `:752`), replace only the gate lines:

```dart
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
```

- [ ] **Step 7: Correct the now-stale `energy` doc comment**

The `energy` getter (currently around `:388`) claims "Nothing is deducted at launch". That is still true of voyage fuel and no longer true of braking. Amend the last paragraph:

```dart
  /// The player's energy right now, in EN.
  ///
  /// While a voyage is in progress this is the fuel still aboard: the balance
  /// minus what the engine has burned so far. Voyage fuel is not deducted at
  /// launch, so this getter is the only place the burn is applied — which is
  /// what makes the reading tick down in real time and still be correct after
  /// the app is killed and restarted. A braking burn is the exception: it is a
  /// departure-time charge and is already out of `energyBalance` by the time
  /// any of this runs.
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `cd starward && flutter test test/braking_test.dart`
Expected: PASS — 14 tests.

- [ ] **Step 9: Run the full suite**

Run: `cd starward && flutter analyze && flutter test`
Expected: `No issues found!` and all tests green.

The spec's §9.2 already verified that **no existing test launches while `isCoasting == true`**, so nothing should break. If something does, it is a real regression — do not edit the test to accommodate it without first explaining why the old assertion was wrong.

- [ ] **Step 10: Commit**

```bash
cd starward
git add lib/data/models/energy_transaction.dart lib/state/game_controller.dart test/braking_test.dart
git commit -m "feat(starward): bill the braking burn when a drift ends

A coasting ship could already be freed by launching from the star map —
_anchorHere cleared the velocity on the way past. That made the exit free
and unnamed. Charge it there instead, at the one choke point both launch
paths already funnel through, so every exit costs the same and no path can
be routed around.

Journey.energyCost stays fuel-only. burnedAt = round(energyCost *
progress) spreads a cost over the route, so folding 100 EN of braking in
would move the fuel-out point. Braking is a departure-time charge with its
own ledger type.

_launchGate now takes the two sums separately: under halt/coast the drop of
fuel the voyage needs is what is left after braking, so the bar is
'balance > braking', not 'balance > 0'."
```

---

### Task 3: The player-facing quote includes the braking burn

**Files:**
- Modify: `starward/lib/state/game_controller.dart`
- Test: `starward/test/braking_test.dart`

**Interfaces:**
- Consumes: `GameController.brakingCost` (Task 2).
- Produces: `GameController.energyCostTo(Planet)` → `int` and `GameController.energyCostToStar(int hygId)` → `int`, both now **totals** — voyage fuel plus braking. Signatures unchanged; semantics changed.

- [ ] **Step 1: Write the failing tests**

Add to `starward/test/braking_test.dart` inside `void main()`:

```dart
  group('energyCostTo is the total the player will pay', () {
    test('adds the braking burn while coasting', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _coasting(clock, MemoryStorage());
      final target = c.planets.first;
      final voyageFuel = c.ship.engine.energyCostFor(c.distanceTo(target));

      expect(c.energyCostTo(target), voyageFuel + 100);
    });

    test('adds the braking burn to the star quote while coasting', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _coasting(clock, MemoryStorage());
      // `stars.starId` is the HYG id array; `distanceToStar` keys off it.
      final hygId = c.stars.starId[0];
      final voyageFuel = c.ship.engine.energyCostFor(c.distanceToStar(hygId));

      expect(c.energyCostToStar(hygId), voyageFuel + 100);
    });

    test('is the plain voyage quote for a parked ship', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock, MemoryStorage());
      final target = c.planets.first;

      expect(c.brakingCost, 0, reason: 'precondition');
      expect(c.energyCostTo(target),
          c.ship.engine.energyCostFor(c.distanceTo(target)));
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd starward && flutter test test/braking_test.dart`
Expected: FAIL on the two coasting cases — the quote comes back 100 EN short.

- [ ] **Step 3: Implement**

In `starward/lib/state/game_controller.dart`, replace `energyCostTo` (currently around `:439`):

```dart
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
```

And replace `energyCostToStar` (currently around `:747`):

```dart
  /// Energy this ship would burn to reach a star's arrival point — voyage fuel
  /// plus the braking burn, matching [energyCostTo].
  int energyCostToStar(int hygId) =>
      _ship.engine.energyCostFor(distanceToStar(hygId)) + brakingCost;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd starward && flutter test test/braking_test.dart`
Expected: PASS — 17 tests.

- [ ] **Step 5: Run the full suite**

Run: `cd starward && flutter analyze && flutter test`
Expected: green. `energy_test.dart` and `real_time_energy_test.dart` lean on `energyCostTo` to predict burn, but none of their cases coast, so `brakingCost == 0` and their numbers are unchanged. If any does fail, that is a genuine finding — investigate before touching the assertion.

- [ ] **Step 6: Commit**

```bash
cd starward
git add lib/state/game_controller.dart test/braking_test.dart
git commit -m "feat(starward): quote the braking burn in the player-facing total

energyCostTo and energyCostToStar now include braking, so the seven UI
call sites that read them (star system sheet, planet details sheet, star
map, journey page) report the real total without being touched one by one.
Parked ships see brakingCost == 0 and therefore byte-identical quotes."
```

---

## Phase 2 — 滑行出口

Player-visible change: the coasting panel finally has actions.

---

### Task 4: `stopShip` — one name for "bring the ship to rest"

**Files:**
- Modify: `starward/lib/state/game_controller.dart`
- Test: `starward/test/braking_test.dart`

**Interfaces:**
- Consumes: `GameController.brakingCost`, `_anchorHere()` (Task 2), `GameController.abortJourney()` (existing).
- Produces:
  - `GameController.canBrake` → `bool`. `false` only for a coasting ship that cannot afford the braking burn.
  - `GameController.stopShip()` → `Future<void>`. Idempotent; a no-op when parked or when the tank cannot pay.

- [ ] **Step 1: Write the failing tests**

Add to `starward/test/braking_test.dart` inside `void main()`:

```dart
  group('stopShip', () {
    test('parks a coasting ship where the drift had carried it', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _coasting(clock, MemoryStorage());
      clock.advance(const Duration(hours: 1));
      final before = c.playerPosition3D;
      expect(before.length, greaterThan(0),
          reason: 'precondition: the drift has moved the ship off its anchor');

      await c.stopShip();

      expect(c.isCoasting, isFalse);
      expect(c.driftVelocity.length, 0);
      expect(c.inDeepSpace, isTrue);
      final parked = c.playerPosition3D;
      expect(parked.x, closeTo(before.x, 1e-9));
      expect(parked.y, closeTo(before.y, 1e-9));
      expect(parked.z, closeTo(before.z, 1e-9));

      clock.advance(const Duration(days: 10));
      expect(c.playerPosition3D.x, closeTo(parked.x, 1e-9),
          reason: 'a stopped ship stays stopped');
    });

    test('bills the braking burn exactly once, however often it is called',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _coasting(clock, MemoryStorage());
      expect(c.energy, 300, reason: 'precondition');

      await c.stopShip();
      await c.stopShip();

      final braking =
          c.energyLedger.where((t) => t.type == EnergyTxType.braking).toList();
      expect(braking.length, 1);
      expect(braking.single.amount, -100);
      expect(c.energy, 200);
    });

    test('does nothing when the tank cannot pay for the braking', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _coasting(clock, MemoryStorage(), energy: 50);
      expect(c.canBrake, isFalse, reason: 'precondition');

      await c.stopShip();

      expect(c.isCoasting, isTrue, reason: 'the ship keeps drifting');
      expect(c.energy, 50);
      expect(c.energyLedger, isEmpty);
    });

    test('does nothing for a parked ship', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock, MemoryStorage());
      expect(c.canBrake, isTrue, reason: 'a ship at rest is always stoppable');

      await c.stopShip();

      expect(c.isCoasting, isFalse);
      expect(c.energyLedger, isEmpty);
    });

    test('delegates to abortJourney while a voyage is in progress', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock, MemoryStorage());
      final target = c.planets.first;
      await c.launchJourney(target);
      final journey = c.activeJourney!;
      clock.advance(journey.totalDuration ~/ 2);
      final burned = journey.burnedAt(clock());
      expect(burned, greaterThan(0), reason: 'precondition');

      await c.stopShip();

      expect(c.activeJourney, isNull);
      expect(c.isCoasting, isFalse);
      expect(c.energyLedger.length, 1);
      expect(c.energyLedger.single.type, EnergyTxType.travelCost);
      expect(c.energyLedger.single.amount, -burned);
      expect(c.energy, 300 - burned);
    });

    test('training is the way out of a drift that cannot afford to brake',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _coasting(clock, MemoryStorage(), energy: 0);
      await c.stopShip();
      expect(c.isCoasting, isTrue, reason: 'no energy, no braking');
      expect(c.canBrake, isFalse);

      // Training has no precondition, which is exactly why it is the escape
      // hatch here: a stranded player must always have something to do.
      // Real course ids and rewards, from `lib/ui/training/courses.dart`:
      // cardio is 70 EN, walk is 40 EN.
      final first = await c.startCourse('cardio');
      await c.completeCourse(first.id, 70);
      final second = await c.startCourse('walk');
      await c.completeCourse(second.id, 40);
      expect(c.energy, 110);
      expect(c.canBrake, isTrue);

      await c.stopShip();

      expect(c.isCoasting, isFalse);
      expect(c.energy, 10, reason: '110 EN earned, 100 EN spent braking');
    });

    test('a braked ship reloads parked, with its ledger intact', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _coasting(clock, storage);
      clock.advance(const Duration(hours: 1));
      await c.stopShip();
      final parked = c.playerPosition3D;

      final reloaded = await _boot(clock, storage);

      expect(reloaded.isCoasting, isFalse);
      expect(reloaded.driftVelocity.length, 0);
      expect(reloaded.energy, 200);
      expect(reloaded.playerPosition3D.x, closeTo(parked.x, 1e-9));
      expect(reloaded.playerPosition3D.y, closeTo(parked.y, 1e-9));
      expect(reloaded.playerPosition3D.z, closeTo(parked.z, 1e-9));
      expect(
        reloaded.energyLedger
            .where((t) => t.type == EnergyTxType.braking)
            .length,
        1,
        reason: 'the new enum member has to survive energyTxTypeFromName',
      );
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd starward && flutter test test/braking_test.dart`
Expected: FAIL — `The method 'stopShip' isn't defined for the type 'GameController'`.

- [ ] **Step 3: Implement**

In `starward/lib/state/game_controller.dart`, add directly after `abortJourney` (currently around `:834`):

```dart
  /// Whether the ship can currently be brought out of its motion.
  ///
  /// False only for a coasting ship that cannot afford the braking burn — the
  /// UI uses this to disable the brake rather than letting the tap do nothing.
  bool get canBrake => !isCoasting || _player.energyBalance >= brakingCost;

  /// Brings the ship to rest where it is, whatever is moving it.
  ///
  /// One entry point for the whole idea, so the UI does not have to know which
  /// kind of motion the ship is in. A voyage in progress is billed for the fuel
  /// it has burned and the ship parks at the point it had reached — see
  /// [abortJourney]. A coasting ship must first shed its cruise velocity: that
  /// braking burn is billed, and the ship then parks at the point the drift had
  /// carried it to. A parked ship is left alone.
  ///
  /// Deliberately does *not* rebuild the nearby set: braking freezes the ship
  /// where it already is, so the set is still correct. [abortJourney] does
  /// rebuild, because that one does move the ship.
  Future<void> stopShip() async {
    final journey = _activeJourney;
    if (journey != null && journey.status == JourneyStatus.inProgress) {
      return abortJourney();
    }
    if (!isCoasting) return;
    if (!canBrake) return;
    _anchorHere();
    await _persist();
    notifyListeners();
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd starward && flutter test test/braking_test.dart`
Expected: PASS — 24 tests.

- [ ] **Step 5: Run the full suite**

Run: `cd starward && flutter analyze && flutter test`
Expected: green. `stopShip` is additive; nothing existing calls it yet.

- [ ] **Step 6: Commit**

```bash
cd starward
git add lib/state/game_controller.dart test/braking_test.dart
git commit -m "feat(starward): add stopShip, one name for bringing the ship to rest

Stopping was two controller methods with different preconditions
(abortJourney for a voyage, _anchorHere for a drift) and the drift half had
no public entry at all. stopShip dispatches on the ship's motion so the UI
can offer one action, and canBrake lets it disable the button rather than
letting the tap silently do nothing.

It does not rebuild the nearby set: braking freezes the ship, so the set is
still right."
```

---

### Task 5: The coasting panel gets its actions

**Files:**
- Modify: `starward/lib/ui/journey/journey_page.dart`
- Test: `starward/test/braking_test.dart`

**Interfaces:**
- Consumes: `GameController.stopShip()`, `GameController.canBrake`, `GameController.brakingCost` (Task 4); `GameController.driftElapsed`, `GameController.driftDistanceLy`, `GameController.passedSystemsSoFar` (existing); `ShellScope.go(context, index)` (existing).
- Produces: nothing consumed by later tasks. `_CoastDock`'s constructor gains `onBrake` and `onChangeCourse`; `_CoastStat` gains an optional `valueColor`; `_ActionButton` gains a disabled visual.

- [ ] **Step 1: Write the failing test**

Add to `starward/test/braking_test.dart`. First add these imports to the top of the file:

```dart
import 'package:flutter/material.dart';
import 'package:starward/ui/game_scope.dart';
import 'package:starward/ui/shell/home_shell.dart';
```

Then add this group inside `void main()`:

```dart
  group('the coasting panel', () {
    testWidgets('offers a brake and a course change, and braking stops the ship',
        (tester) async {
      final clock = FakeClock(DateTime(2026));
      final c = await _coasting(clock, MemoryStorage());
      clock.advance(const Duration(hours: 1));

      await tester.pumpWidget(
        MaterialApp(home: GameScope(controller: c, child: const HomeShell())),
      );
      // Never pumpAndSettle here: the coasting panel runs a one-second ticker
      // that schedules a frame every tick, so settling never happens.
      await tester.pump();
      await tester.tap(find.text('航行'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('制动停下'), findsOneWidget);
      expect(find.text('改变航向'), findsOneWidget);
      expect(find.text('查看播报'), findsOneWidget);
      expect(find.textContaining('100 EN'), findsWidgets,
          reason: 'the braking readout is on the panel');

      await tester.tap(find.text('制动停下'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('停止滑行'), findsOneWidget,
          reason: 'braking is confirmed before it is charged');

      await tester.tap(find.text('制动'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(c.isCoasting, isFalse);
      expect(c.energyLedger.single.amount, -100);
      expect(c.energy, 200);
    });

    testWidgets('disables both buttons when the braking burn is unaffordable',
        (tester) async {
      final clock = FakeClock(DateTime(2026));
      final c = await _coasting(clock, MemoryStorage(), energy: 50);

      await tester.pumpWidget(
        MaterialApp(home: GameScope(controller: c, child: const HomeShell())),
      );
      await tester.pump();
      await tester.tap(find.text('航行'));
      await tester.pump(const Duration(milliseconds: 100));

      final brake = tester.widget<InkWell>(find.ancestor(
        of: find.text('制动停下'),
        matching: find.byType(InkWell),
      ));
      expect(brake.onTap, isNull);
      expect(find.text('前往训练补充能量'), findsOneWidget);
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd starward && flutter test test/braking_test.dart`
Expected: FAIL — `Expected: exactly one matching candidate, Actual: _TextWidgetFinder:<Found 0 widgets with text "制动停下">`.

- [ ] **Step 3: Give `_ActionButton` a disabled look**

`_ActionButton` (currently around `:1097`) currently ignores `onPressed == null` visually, so a disabled button is indistinguishable from an enabled one. Replace its `build`:

```dart
  @override
  Widget build(BuildContext context) {
    // A dead button must look dead. Every existing call site passes an
    // onPressed, so this only affects the ones that opt into disabling.
    final disabled = onPressed == null;
    final fg = disabled
        ? StarColors.faint
        : (filled ? StarColors.abyss : color);
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: disabled
            ? StarColors.panelLight
            : (filled ? color : Colors.transparent),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: filled || disabled
                  ? null
                  : Border.all(color: color.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, color: fg, size: 19),
                const SizedBox(width: 9),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
```

- [ ] **Step 4: Let `_CoastStat` carry a colour**

Replace `_CoastStat` (currently around `:747`):

```dart
class _CoastStat extends StatelessWidget {
  const _CoastStat({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;

  /// Overrides the reading's colour — used to flag a braking burn the tank
  /// cannot cover.
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Text(label,
              style: const TextStyle(color: StarColors.faint, fontSize: 11)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                color: valueColor ?? StarColors.offWhite,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Rewrite `_CoastDock`**

Replace `_CoastDock` (currently around `:655`) with:

```dart
/// Shown in the standby state while the ship is coasting: where it is, how
/// fast it is going, how far it has come since the tank emptied, and — the
/// part that used to be missing — how to make it stop.
class _CoastDock extends StatelessWidget {
  const _CoastDock({
    required this.controller,
    required this.onBrake,
    required this.onChangeCourse,
  });

  final GameController controller;
  final VoidCallback onBrake;
  final VoidCallback onChangeCourse;

  @override
  Widget build(BuildContext context) {
    final p = controller.playerPosition3D;
    final v = controller.driftVelocity;
    final elapsed = controller.driftElapsed;
    final hours = elapsed.inHours;
    final duration = hours >= 24
        ? '${(hours / 24).toStringAsFixed(1)} 天'
        : (hours >= 1
            ? '$hours 小时'
            : '${elapsed.inMinutes} 分钟');
    final braking = controller.brakingCost;
    final canBrake = controller.canBrake;
    return StarPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: StarColors.panelLight,
                ),
                child: const Icon(Icons.explore_rounded,
                    color: StarColors.cyan, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('滑行中 · 巡航速度',
                        style:
                            TextStyle(color: StarColors.faint, fontSize: 11)),
                    const SizedBox(height: 3),
                    Text(
                      '${v.length.toStringAsFixed(4)} ly/s',
                      style: const TextStyle(
                        color: StarColors.offWhite,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _CoastStat(label: '已滑行', value: duration),
          _CoastStat(
              label: '累计距离',
              value: '${controller.driftDistanceLy.toStringAsFixed(1)} ly'),
          _CoastStat(
              label: '途经恒星系',
              value: '${controller.passedSystemsSoFar.count}'),
          _CoastStat(
              label: '当前坐标',
              value:
                  'X ${p.x.toStringAsFixed(1)}  Y ${p.y.toStringAsFixed(1)}  Z ${p.z.toStringAsFixed(1)}'),
          _CoastStat(
            label: '制动需要',
            value: '$braking EN（现有 ${controller.energy} EN）',
            valueColor: canBrake ? null : StarColors.danger,
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: _ActionButton(
                  label: '制动停下',
                  icon: Icons.anchor_rounded,
                  color: StarColors.danger,
                  onPressed: canBrake ? onBrake : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  label: '改变航向',
                  icon: Icons.alt_route_rounded,
                  filled: false,
                  onPressed: canBrake ? onChangeCourse : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ActionButton(
            label: '查看播报',
            icon: Icons.article_rounded,
            filled: false,
            onPressed: controller.requestDriftReport,
          ),
          if (!canBrake) ...<Widget>[
            const SizedBox(height: 10),
            _ActionButton(
              label: '前往训练补充能量',
              icon: Icons.favorite_rounded,
              color: StarColors.flora,
              filled: false,
              onPressed: () => ShellScope.go(context, 3),
            ),
          ],
        ],
      ),
    );
  }
}
```

`_ActionButton` is full-width by design (`width: double.infinity`), which is why the two side-by-side buttons each sit in an `Expanded`.

- [ ] **Step 6: Add the two confirm dialogs**

In `_JourneyPageState`, add after `_changeCourse` (currently around `:186`):

```dart
  /// One line of drift totals, read *before* the brake clears them.
  ///
  /// Braking nulls `driftPath`, so `buildDriftReport()` returns null and these
  /// numbers are gone for good the moment the ship stops. Reciting them in the
  /// confirmation is the whole mitigation — there is deliberately no queued
  /// summary report.
  String _driftSummary(GameController c) {
    final elapsed = c.driftElapsed;
    final hours = elapsed.inHours;
    final duration = hours >= 24
        ? '${(hours / 24).toStringAsFixed(1)} 天'
        : (hours >= 1 ? '$hours 小时' : '${elapsed.inMinutes} 分钟');
    return '$duration · ${c.driftDistanceLy.toStringAsFixed(1)} ly · '
        '途经 ${c.passedSystemsSoFar.count} 个恒星系';
  }

  Future<void> _brakeCoast(GameController c) async {
    // Read the summary first: after the brake it no longer exists.
    final summary = _driftSummary(c);
    final braking = c.brakingCost;
    final ok = await _confirm(
      title: '停止滑行',
      message: '飞船将制动停下，漂浮于深空。\n\n'
          '本次滑行 $summary\n'
          '制动消耗 $braking EN，制动后剩余 ${c.energy - braking} EN。',
      confirmLabel: '制动',
      danger: true,
    );
    if (ok != true) return;
    await c.stopShip();
  }

  Future<void> _brakeAndChangeCourse(GameController c) async {
    final summary = _driftSummary(c);
    final braking = c.brakingCost;
    final ok = await _confirm(
      title: '制动并改变航向',
      message: '飞船将制动停下，然后回到星图重新选择目的地。\n\n'
          '本次滑行 $summary\n'
          '制动消耗 $braking EN，制动后剩余 ${c.energy - braking} EN。',
      confirmLabel: '制动并去星图',
    );
    if (ok != true) return;
    await c.stopShip();
    if (!mounted) return;
    ShellScope.go(context, 0);
  }
```

Note the dialog titles are deliberately distinct from the button labels (`停止滑行` vs `制动停下`, `制动并改变航向` vs `改变航向`) so a widget test can tell the button from the dialog it opens.

- [ ] **Step 7: Wire the callbacks in `_buildStandby`**

In `_buildStandby`, the `coasting` branch currently constructs `_CoastDock(controller: c)`. Change it to:

```dart
            _CoastDock(
              controller: c,
              onBrake: () => _brakeCoast(c),
              onChangeCourse: () => _brakeAndChangeCourse(c),
            ),
```

- [ ] **Step 8: Route the in-flight buttons through `stopShip`**

Replace `_abortFlight` and `_changeCourse` (currently around `:164` and `:175`) so both go through the single action name:

```dart
  Future<void> _abortFlight(GameController c) async {
    final ok = await _confirm(
      title: '停止航行',
      message: '飞船将在当前位置停下，漂浮于深空。已消耗的能量不会退还。',
      confirmLabel: '停止',
      danger: true,
    );
    if (ok != true) return;
    await c.stopShip();
  }

  Future<void> _changeCourse(GameController c) async {
    final ok = await _confirm(
      title: '改变航向',
      message: '将中止当前航行并回到星图重新选择目的地。已消耗的能量不会退还。',
      confirmLabel: '去星图',
    );
    if (ok != true) return;
    await c.stopShip();
    if (!mounted) return;
    ShellScope.go(context, 0);
  }
```

While a voyage is in progress `stopShip()` delegates straight to `abortJourney()`, so behaviour is identical; the UI just stops naming a controller method the player has never heard of.

- [ ] **Step 9: Run the tests to verify they pass**

Run: `cd starward && flutter test test/braking_test.dart`
Expected: PASS — 26 tests.

- [ ] **Step 10: Run the full suite**

Run: `cd starward && flutter analyze && flutter test`
Expected: green. `flight_panel_test.dart` exercises the in-flight buttons, which now route through `stopShip` — the delegation makes this a no-op change, but confirm rather than assume.

- [ ] **Step 11: Commit**

```bash
cd starward
git add lib/ui/journey/journey_page.dart test/braking_test.dart
git commit -m "feat(starward): give the coasting panel a way out

The panel showed the drift's statistics and one button, and that button
only opened a report — the player could watch the ship drift with nothing
to do about it. Add 制动停下 and 改变航向, both confirmed first.

改变航向 is deliberately not a free path: it brakes and then switches tab,
so the two buttons differ in destination, not in price.

The confirmation recites the drift's totals because braking nulls
driftPath and buildDriftReport() with it — this is the last moment those
numbers exist, and copying them into the dialog is why stopping needs no
report pipeline of its own.

_ActionButton now looks disabled when it is, and the in-flight stop and
change-course buttons go through stopShip() so the UI has one action name."
```

---

## Phase 3 — 报价与可见性

Independent of Phase 2. Player-visible change: an under-funded player can tell *which* line item they are short of, and can see the ship is still drifting from another tab.

---

### Task 6: The fuel dialog knows about the braking burn

**Files:**
- Modify: `starward/lib/ui/journey/fuel_choice_dialog.dart`
- Modify: `starward/lib/ui/galaxy/planet_details_sheet.dart` (call site only)
- Modify: `starward/lib/ui/galaxy3d/galaxy_map_3d_page.dart` (call site and empty-tank guard)
- Test: `starward/test/braking_test.dart`

**Interfaces:**
- Consumes: `GameController.brakingCost` (Task 2), `GameController.energyCostTo`/`energyCostToStar` as totals (Task 3).
- Produces: `showFuelChoiceDialog(BuildContext, {required int energy, required int cost, required int braking, required double distanceLy, required Engine engine})` → `Future<FuelPolicy?>`. **Signature changed** — `braking` is a new required parameter.

- [ ] **Step 1: Write the failing test**

Add to `starward/test/braking_test.dart`. Add this import:

```dart
import 'package:starward/ui/journey/fuel_choice_dialog.dart';
```

And this group:

```dart
  group('the fuel choice dialog with a braking burn', () {
    Future<void> open(
      WidgetTester tester, {
      required int energy,
      required int braking,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFuelChoiceDialog(
                context,
                // A 100 ly voyage: 250 EN of fuel.
                energy: energy,
                cost: 250 + braking,
                braking: braking,
                distanceLy: 100,
                engine: Engine.standard,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('reports the braking burn separately from the voyage fuel',
        (tester) async {
      await open(tester, energy: 150, braking: 100);

      expect(find.textContaining('其中 100 EN 要先用于制动'), findsOneWidget);
      expect(find.textContaining('制动后剩 50 EN'), findsOneWidget);
      expect(find.textContaining('可以飞 20.0 ly'), findsOneWidget,
          reason: 'reachableLyFor(150 - 100) = 50 / 2.5');
      expect(find.text('耗尽后滑行'), findsOneWidget,
          reason: '50 EN is still a drop of fuel, so running dry is on offer');
    });

    testWidgets('offers no running-dry choice when the braking eats it all',
        (tester) async {
      await open(tester, energy: 100, braking: 100);

      expect(find.text('耗尽后滑行'), findsNothing);
      expect(find.text('耗尽后停下'), findsNothing);
    });

    testWidgets('says nothing about braking for a ship that is not coasting',
        (tester) async {
      await open(tester, energy: 150, braking: 0);

      expect(find.textContaining('制动'), findsNothing);
      expect(find.textContaining('可以飞 60.0 ly'), findsOneWidget,
          reason: 'reachableLyFor(150) = 60.0 ly');
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd starward && flutter test test/braking_test.dart`
Expected: FAIL — `No named parameter with the name 'braking'`.

- [ ] **Step 3: Implement the dialog change**

In `starward/lib/ui/journey/fuel_choice_dialog.dart`, add `required int braking` to the signature and replace the reach calculation and the two gated strings:

```dart
Future<FuelPolicy?> showFuelChoiceDialog(
  BuildContext context, {
  required int energy,
  required int cost,
  required int braking,
  required double distanceLy,
  required Engine engine,
}) {
  // The braking burn comes off the top, so what matters for the voyage is what
  // is left after it — not the whole balance.
  final reach = engine.reachableLyFor(energy - braking);
```

and, in the copy, branch on whether there is a braking burn to mention:

```dart
              braking > 0
                  ? '你只有 $energy EN，其中 $braking EN 要先用于制动。'
                      '制动后剩 ${energy - braking} EN，'
                      '可以飞 ${reach.toStringAsFixed(1)} ly，'
                      '全程 ${distanceLy.toStringAsFixed(1)} ly。'
                  : '你只有 $energy EN，可以飞 ${reach.toStringAsFixed(1)} ly，'
                      '全程 ${distanceLy.toStringAsFixed(1)} ly。',
```

and change the gate on the halt/coast choices from `energy > 0` to:

```dart
            // The drop of fuel those policies need is the drop left *after*
            // braking — with the tank at or below the braking cost there is
            // nothing to decide.
            if (energy > braking) ...<Widget>[
```

- [ ] **Step 4: Update all three call sites**

In `starward/lib/ui/galaxy/planet_details_sheet.dart`, in `_launchWithChoice` (currently around `:423`), add the parameter:

```dart
    final policy = await showFuelChoiceDialog(
      context,
      energy: controller.energy,
      cost: controller.energyCostTo(planet),
      braking: controller.brakingCost,
      distanceLy: controller.distanceTo(planet),
      engine: controller.ship.engine,
    );
```

In `starward/lib/ui/galaxy3d/galaxy_map_3d_page.dart`, in `_launchToStar` (currently around `:198`), change the empty-tank guard and add the parameter:

```dart
    if (_c.energy < cost) {
      // Below the braking cost there is nothing the dialog could offer — not
      // even running dry, since the ship cannot leave the drift at all.
      if (_c.energy <= _c.brakingCost) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_c.brakingCost > 0
                ? '能量不足，连制动都不够，先去做一组训练吧'
                : '能量不足，先去做一组训练吧'),
          ),
        );
        return;
      }
      policy = await showFuelChoiceDialog(
        context,
        energy: _c.energy,
        cost: cost,
        braking: _c.brakingCost,
        distanceLy: _c.distanceToStar(hygId),
        engine: _c.ship.engine,
      );
      if (policy == null || !mounted) return;
    }
```

There is a **third** call site the two above do not cover: `starward/test/fuel_out_test.dart:381`, inside that file's local `open()` helper. `braking` being required stops the file compiling until it is named. Pass `0` rather than adding a parameter to the helper — that keeps the whole group byte-identical, because `reachableLyFor(energy - 0)` is `reachableLyFor(energy)`, `energy > 0` is `energy > braking`, and the copy takes the `braking > 0 ? … : …` else-branch, which is the original string. Task 6's tests in `braking_test.dart` are what cover the non-zero case, so an unused helper parameter would be YAGNI.

```dart
                picked.complete(await showFuelChoiceDialog(
                  context,
                  energy: energy,
                  cost: cost,
                  braking: 0,
                  distanceLy: 100.0,
                  engine: Engine.standard,
                ));
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd starward && flutter test test/braking_test.dart`
Expected: PASS — 29 tests.

- [ ] **Step 6: Run the full suite**

Run: `cd starward && flutter analyze && flutter test`
Expected: green. The dialog's signature changed, so `flutter analyze` is what catches any call site missed here.

- [ ] **Step 7: Commit**

```bash
cd starward
git add lib/ui/journey/fuel_choice_dialog.dart lib/ui/galaxy/planet_details_sheet.dart lib/ui/galaxy3d/galaxy_map_3d_page.dart test/braking_test.dart test/fuel_out_test.dart
git commit -m "feat(starward): show the braking burn as its own line in the fuel dialog

The dialog computed how far the tank would carry with reachableLyFor(energy)
and offered the run-dry choices whenever energy > 0. Both are wrong once a
coasting ship owes a braking burn: the reachable distance is what is left
after braking, and the bar for running dry is a drop left after it too.

The star map's empty-tank guard moves from 'energy <= 0' to
'energy <= brakingCost' for the same reason — below that the dialog has
nothing to offer."
```

---

### Task 7: The details sheet says which line item is short

**Files:**
- Modify: `starward/lib/ui/galaxy/planet_details_sheet.dart`
- Test: `starward/test/braking_test.dart`

**Interfaces:**
- Consumes: `GameController.brakingCost` (Task 2), `GameController.energyCostTo` as a total (Task 3).
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Write the failing test**

Add to `starward/test/braking_test.dart`. Add these imports:

```dart
import 'package:starward/ui/galaxy/planet_details_sheet.dart';
import 'package:starward/ui/shell/shell_scope.dart';
```

And this group:

```dart
  group('the details sheet with a drift to shed', () {
    Future<void> showSheet(WidgetTester tester, GameController c) async {
      final target = c.planets.first;
      await tester.pumpWidget(
        MaterialApp(
          home: ShellScope(
            goToTab: (_) {},
            child: GameScope(
              controller: c,
              child: Scaffold(body: PlanetDetailsSheet(planetId: target.id)),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('names the braking burn when the tank cannot cover it',
        (tester) async {
      final clock = FakeClock(DateTime(2026));
      // 50 EN: short of the 100 EN braking burn, whatever the voyage costs.
      final c = await _coasting(clock, MemoryStorage(), energy: 50);

      await showSheet(tester, c);

      expect(find.textContaining('先制动需要 100 EN'), findsOneWidget);
      expect(find.textContaining('能量不足'), findsOneWidget);
    });

    testWidgets('says nothing about braking for a parked ship', (tester) async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock, MemoryStorage());

      await showSheet(tester, c);

      expect(find.textContaining('先制动需要'), findsNothing);
    });
  });
```

`c.planets.first` reaches the launch branch: the ship is in deep space so `atPlanet` is false (branch 2 is skipped) and no voyage is running so `travelingHere` is false (branches 1 and 3 are skipped). With 50 EN against a `cost` of at least `1 + 100`, `canAfford` is always false, so the insufficiency branch is the one under test.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd starward && flutter test test/braking_test.dart`
Expected: FAIL — `Found 0 widgets with text containing "先制动需要 100 EN"`.

- [ ] **Step 3: Implement**

In `starward/lib/ui/galaxy/planet_details_sheet.dart`, in the launch section (currently around `:357`), read the braking cost and add the hint line:

```dart
    // 4) Launch a new voyage.
    final cost = controller.energyCostTo(planet);
    final braking = controller.brakingCost;
    final canAfford = controller.energy >= cost;
    if (!canAfford) {
      // Under the halt/coast policies the voyage only needs a drop of fuel —
      // but it has to be a drop left *after* the braking burn.
      final hasFuel = controller.energy > braking;
      return Column(
        children: <Widget>[
          _Button(
            label: '能量不足（需 $cost EN · 现有 ${controller.energy} EN）',
            icon: Icons.bolt_rounded,
          ),
          // A coasting ship owes a braking burn before it can go anywhere, so
          // "the place is close, why am I short?" needs an answer on screen.
          if (braking > 0) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              '其中先制动需要 $braking EN',
              textAlign: TextAlign.center,
              style: const TextStyle(color: StarColors.faint, fontSize: 11),
            ),
          ],
          const SizedBox(height: 10),
          _Button(
            label: '选择如何出发',
            icon: Icons.rocket_launch_rounded,
            color: StarColors.cyan,
            onPressed: hasFuel
                ? () => _launchWithChoice(context, controller, planet)
                : null,
          ),
          const SizedBox(height: 10),
          _Button(
            label: '前往训练补充能量',
            icon: Icons.favorite_rounded,
            color: StarColors.flora,
            filled: false,
            onPressed: () {
              ShellScope.go(context, 3);
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    }
```

The rest of the method (the `开始航行 · $cost EN` branch) is unchanged — `cost` already includes braking, so its label is correct as written.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd starward && flutter test test/braking_test.dart`
Expected: PASS — 31 tests.

- [ ] **Step 5: Run the full suite**

Run: `cd starward && flutter analyze && flutter test`
Expected: green. `details_launch_test.dart` covers the affordable path, which this task does not touch.

- [ ] **Step 6: Commit**

```bash
cd starward
git add lib/ui/galaxy/planet_details_sheet.dart test/braking_test.dart
git commit -m "feat(starward): explain the braking burn on the details sheet

'能量不足' on a destination a few light-years away is baffling when most of
the shortfall is the braking burn the ship owes before it can leave at all.
Name that line item.

The '选择如何出发' button's gate moves from 'energy > 0' to 'energy >
braking' for the same reason as the dialog it opens."
```

---

### Task 8: The voyage tab badge lights up while coasting

**Files:**
- Modify: `starward/lib/ui/shell/home_shell.dart`
- Test: `starward/test/braking_test.dart`

**Interfaces:**
- Consumes: `GameController.isCoasting` (existing).
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Write the failing test**

Add to `starward/test/braking_test.dart` and add the theme import:

```dart
import 'package:starward/core/theme.dart';
```

Add this group:

```dart
  group('the voyage tab badge', () {
    /// The badge is a small gold dot in the nav bar; there is no text to find.
    Finder badgeDot() => find.byWidgetPredicate((w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration! as BoxDecoration).color == StarColors.gold);

    testWidgets('lights up for a coasting ship, not just a live voyage',
        (tester) async {
      final clock = FakeClock(DateTime(2026));
      final c = await _coasting(clock, MemoryStorage());
      expect(c.activeJourney, isNull, reason: 'precondition: no voyage running');

      await tester.pumpWidget(
        MaterialApp(home: GameScope(controller: c, child: const HomeShell())),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(badgeDot(), findsOneWidget,
          reason: 'switching to the training tab must not hide that the ship '
              'is still drifting');
    });

    testWidgets('stays dark for a parked ship', (tester) async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock, MemoryStorage());

      await tester.pumpWidget(
        MaterialApp(home: GameScope(controller: c, child: const HomeShell())),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(badgeDot(), findsNothing);
    });
  });
```

`_NavItem` renders the badge as an 8×8 `Container` with a circular gold `BoxDecoration` (`home_shell.dart:151-158`), and `StarColors.gold` appears nowhere else in that file — so the predicate is exact, and the second test is what proves it empirically.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd starward && flutter test test/braking_test.dart`
Expected: FAIL on the first case — `Expected: exactly one matching candidate, Actual: Found 0 widgets`.

- [ ] **Step 3: Implement**

In `starward/lib/ui/shell/home_shell.dart`, change the badge condition (currently `:71`):

```dart
    // A coasting ship has no active journey, but it is still moving and the
    // player still has something waiting on the voyage tab — so the badge has
    // to cover both, or switching to training hides the drift entirely.
    final hasJourney =
        controller.activeJourney != null || controller.isCoasting;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd starward && flutter test test/braking_test.dart`
Expected: PASS — 33 tests.

- [ ] **Step 5: Run the full suite and analyze**

Run: `cd starward && flutter analyze && flutter test`
Expected: `No issues found!` and every test in the project green.

- [ ] **Step 6: Commit**

```bash
cd starward
git add lib/ui/shell/home_shell.dart test/braking_test.dart
git commit -m "feat(starward): light the voyage badge while the ship is coasting

The badge keyed off activeJourney alone, so a coasting ship had no active
journey and the badge went dark — switching to the training tab left no
signal anywhere that the ship was still drifting. Training is exactly what
a stranded player goes to do, which is when the signal matters most."
```

---

## Done

After Task 8, run the full gate one last time:

```bash
cd starward && flutter analyze && flutter test
```

Then verify against the spec's §9.1 list — all eleven items should be covered by `test/braking_test.dart`:

| Spec item | Covered by |
|---|---|
| 1. `brakingCostFor` pinned numbers | Task 1 |
| 2. Braking parks the ship and bills 100 EN | Task 4 |
| 3. Braking bills once | Task 4 |
| 4. Launching from a drift also bills, and keeps `Journey.energyCost` fuel-only | Task 2 |
| 5. The gate: 50 EN cannot stop or launch | Tasks 2, 4 |
| 6. Zero-impact regression (parked / docked / under power) | Tasks 2, 3, 4, 7 |
| 7. The one-`braking`-entry-per-drift invariant | Tasks 2, 4 |
| 8. 0 EN is not a soft-lock — training still works | Task 4 |
| 9. Hull-hugging drift does not change the price | Task 4 (position assertions hold the velocity constant) |
| 10. Save round trip after braking | Task 4 |
| 11. Engine JSON migration | Task 1 |
