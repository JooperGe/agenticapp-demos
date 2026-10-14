# Starward 自由巡航与座舱改向 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a ship stopped in deep space a way to move again — an ignition with no destination — and give a moving ship a way to change direction without stopping, priced by the angle it turns.

**Architecture:** A cruise is a *powered drift*: the same `(anchor, velocity, startedAt)` triple that already describes a coast, plus one boolean saying whether the engine is driving it. That reuse is what makes the feature cheap — `DriftPath`, `playerPosition3D`, the drift report and the nearby rescan all keep working untouched, and a coast becomes "a drift whose engine is off". The price of a cruise is the engine's own `powerDrawPerSecond`, derived from `energyPerLy × cruiseSpeedLyPerSec` so a cruise and a voyage can never disagree about how fast the tank drains. A turn is a Δv burn — `2v·sin(θ/2)` — priced through the same `energyCostFor` scale as a leg of that length, which is why 60° costs exactly what braking costs, and why that crossover is worth telling the player about out loud.

**Tech Stack:** Flutter / Dart. `flutter_test` with a `FakeClock`, fixed `math.Random` seeds, and `MemoryStorage`. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-14-starward-free-cruise-design.md`

## Global Constraints

- Layer discipline: `lib/core` → `lib/data` → `lib/state` → `lib/ui`. UI never reads storage directly; all rules live on `GameController`.
- Attributes belong to their owning entity. A number describing the engine is a field on `Engine`. `Balance` holds only cross-entity economy. Derived calculations are methods on the entity (`Engine.energyCostFor(ly)`), never top-level functions reading globals.
- Models are immutable: `final` fields, `const` constructors, changes return a new instance via `copyWith`/named methods.
- **Migrate, do not bump `_saveKey`.** The save key stays `starward.save.v2`. New fields fall back to a sensible default when absent.
- TDD: write the failing test first, run it and watch it fail, then implement.
- Tests pin concrete numbers (as `test/ship_test.dart` does for the standard engine) so "the refactor changed nothing" is verifiable rather than asserted.
- `flutter analyze` must report **No issues found** and `flutter test` must be fully green at the end of every task.
- UI copy is Chinese, matching the surrounding screens.

### The reference economy, verbatim

Standard engine (`Engine.standard`): `energyPerLy` 2.5, `cruiseSpeedLyPerSec` 1/37.5 = 0.02666666666666667, `brakingDistanceLy` 40, `minEnergyCost` 1, `minTravelSeconds` 15, **`activationCost` 5**.

`Balance.initialEnergy` 300 EN. Training rewards 40 / 70 / 50 EN. `Balance.explorationReward` 15 EN.

Derived, all verified numerically against Dart's `double.round()` (half away from zero):

| Quantity | Value |
|---|---|
| `powerDrawPerSecond` = `2.5 × (1/37.5)` | 0.06666666666666667 EN/s (= 1/15) |
| `secondsForEnergy(300)` | 4500.0 s **exactly** |
| `secondsForEnergy(200)` | 3000.0 s **exactly** |
| `secondsForEnergy(40)` | 600.0 s **exactly** |
| `burnForSeconds(0)` / `(37.5)` / `(1500)` / `(4500)` / `(5100)` | 1 / 3 / 100 / 300 / 340 EN |
| `energyCostFor(1)` / `(5)` / `(40)` / `(120)` / `(200)` | 3 / 13 / 100 / 300 / 500 EN |
| `brakingCostFor(cruiseSpeed)` | 100 EN |
| `turnCostFor(0°/5°/10°/30°/60°/90°/120°/180°)` | 0 / 9 / 17 / 52 / 100 / 141 / 173 / 200 EN |

### The three invariants, verbatim

1. **A cruise and a voyage price the same distance identically.** `burnForSeconds(secondsFor(D)) == energyCostFor(D)`.
2. **A cruise always leaves enough in the tank to buy its own stop.** `cruiseReserve` = 100 EN is held back for the whole cruise, so the exhaustion point is `balance − 100`.
3. **`driftVelocity` going from non-zero to zero books exactly one `braking` entry** (unchanged from the braking spec), and any change to one of `(startX/Y/Z, driftStartedAt, driftVelocity)` re-pins the other two in the same breath.

---

## Spec Deviations (read this before Task 1)

Four places where the spec and the code disagree, or where the spec is self-inconsistent. Each is resolved here, in favour of the code, with the reason. Do not "fix" these back.

1. **`turnCostFor`'s domain is `[0, π]`, not `[0, 2π]`.** Spec §5.1's table lists 350° and 360°. Those are unreachable: `GameController.turnAngleTo` computes the angle between two unit vectors with `acos(dot)`, which cannot exceed π. The table's 350° row (17 EN) is the 10° row, which is correct physics — a 350° turn *is* a 10° turn the other way — and the 360° row (0 EN) contradicts `minEnergyCost = 1`. So `turnCostFor` is only ever called with `[0, π]`, and 0° → 0 comes from an explicit early return, not from the floor.
2. **`correctHeading` guards on the live `energy`, and checks before settling.** Spec §8.8's sample reads `_player.energyBalance`, which is stale — the current leg's burn is computed by the `energy` getter and not yet booked. Checking the stale number would let a turn eat the braking reserve.
3. **The exhaustion check compares time, not energy.** `burnForSeconds(elapsed) >= budget` fires a tick early because EN is quantised: at `budget = 200` it trips at 2992 s (79.8 ly) instead of 3000 s (80 ly). Compare `elapsed >= engine.secondsForEnergy(budget)` instead — verified exact at 4500.0 / 3000.0 / 600.0 s.
4. **`_reconcileCruise` builds its `DriftReport` before settling.** `_settleCruise` re-pins `driftStartedAt = now`, so a report built afterwards would see a zero-length leg and return null.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `starward/lib/data/models/engine.dart` | Cruise power draw, cruise burn, seconds-per-energy, turn pricing, activation fee | Modify |
| `starward/lib/data/models/energy_transaction.dart` | Three new ledger kinds | Modify |
| `starward/lib/data/models/player_state.dart` | `driftPowered`, `engineDormant`, `cruisePolicy` | Modify |
| `starward/lib/state/game_controller.dart` | All rules: drift vocabulary, ignition, cruise burn, exhaustion, dormancy, activation, turning, the cockpit request | Modify |
| `starward/lib/ui/galaxy3d/camera3d.dart` | `aimCameraAt` — the exact inverse of `Camera3D.forward` | Modify |
| `starward/lib/ui/galaxy3d/cockpit_hud.dart` | Pure HUD geometry: the heading readout, marker projection, off-screen clamping | **Create** |
| `starward/lib/ui/galaxy3d/galaxy_map_3d_page.dart` | Cockpit request handling, aiming, FOV-scaled look sensitivity, HUD overlay, heading bar | Modify |
| `starward/lib/ui/journey/journey_page.dart` | Ignition button, cruise readout, cruise-aware timer and starfield | Modify |
| `starward/lib/ui/journey/fuel_choice_dialog.dart` | The cruise variant of the exhaustion-policy dialog | Modify |
| `starward/lib/ui/galaxy/planet_details_sheet.dart` | New `LaunchResult` case | Modify |
| `starward/lib/ui/shell/home_shell.dart` | Voyage-tab badge covers a cruise | Modify |
| `starward/test/cruise_test.dart` | Engine pricing + cruise behaviour | **Create** |
| `starward/test/cruise_save_test.dart` | Persistence and migration of the three new fields | **Create** |
| `starward/test/heading_test.dart` | Turn pricing and `correctHeading` | **Create** |
| `starward/test/cockpit_hud_test.dart` | Pure HUD geometry | **Create** |
| `starward/test/camera_aim_test.dart` | `aimCameraAt` round-trips `Camera3D.forward` | **Create** |
| `starward/test/dormancy_test.dart` | Dormancy transitions and the activation fee | **Create** |
| `starward/test/cruise_ui_test.dart` | Dock and cockpit widget behaviour | **Create** |

No file is split or moved. `game_controller.dart` (1223 lines), `journey_page.dart` (1455) and `galaxy_map_3d_page.dart` (905) are large, but they are the established homes for rules and for their screens respectively; restructuring them is out of scope. The one new file, `cockpit_hud.dart`, exists because the HUD geometry is a *pure function of a direction and a camera* — testable without pumping a widget — and because `_CockpitPainter` is already at the limit of what one file should hold.

---

## Phase 1 — 词汇 (no behaviour change)

Every task in this phase is provably behaviour-preserving. The phase ships on its own: nothing the player can do changes.

---

### Task 1: The engine learns what a cruise costs

**Files:**
- Modify: `starward/lib/data/models/engine.dart`
- Modify: `starward/test/ship_test.dart:16` (compile fix)
- Modify: `starward/test/drift_report_test.dart:55` (compile fix)
- Modify: `starward/test/flight_panel_test.dart:258` (compile fix)
- Modify: `starward/test/return_to_origin_test.dart:146` (compile fix)
- Test: `starward/test/cruise_test.dart` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `Engine.activationCost` (`int`, required constructor field, 5 on `Engine.standard`); `Engine.powerDrawPerSecond` (`double` getter); `Engine.burnForSeconds(double seconds)` → `int`; `Engine.secondsForEnergy(int energy)` → `double`; `Engine.turnCostFor(double radians)` → `int`.

- [ ] **Step 1: Write the failing test**

Create `starward/test/cruise_test.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/models/engine.dart';

void main() {
  group('Engine cruise pricing', () {
    test('power draw is the engine\'s own speed times its own appetite', () {
      // Derived, never stored: a stored copy could drift out of step with the
      // two fields it comes from, and then a cruise and a voyage would disagree
      // about how fast the same tank drains.
      expect(Engine.standard.powerDrawPerSecond, closeTo(1 / 15, 1e-12));
    });

    test('a cruise and a voyage price the same distance identically', () {
      // The invariant the whole energy model hangs on: burning for exactly as
      // long as a leg takes must cost exactly the leg's quote. If this breaks,
      // "cruise to a place" and "fly to a place" become different prices.
      for (final d in <double>[1, 5, 40, 120, 200]) {
        final seconds = Engine.standard.secondsFor(d);
        expect(Engine.standard.burnForSeconds(seconds.toDouble()),
            Engine.standard.energyCostFor(d),
            reason: '$d ly');
      }
    });

    test('secondsForEnergy inverts the burn exactly', () {
      // Exact, not approximate: the exhaustion check compares elapsed seconds
      // against this, and a rounding error here moves the halt point a tick.
      expect(Engine.standard.secondsForEnergy(300), 4500.0);
      expect(Engine.standard.secondsForEnergy(200), 3000.0);
      expect(Engine.standard.secondsForEnergy(40), 600.0);
      expect(Engine.standard.secondsForEnergy(0), 0.0);
    });

    test('a turn is priced on the angle, at the delta-v it costs', () {
      // At speed v a turn of theta changes the velocity vector by
      // 2*v*sin(theta/2). Priced through the same per-light-year scale as any
      // other leg: energyCostFor(40 * 2 sin(theta/2)) == round(200 sin(theta/2)).
      const e = Engine.standard;
      double deg(double d) => d * math.pi / 180;
      expect(e.turnCostFor(0), 0);
      expect(e.turnCostFor(deg(5)), 9);
      expect(e.turnCostFor(deg(10)), 17);
      expect(e.turnCostFor(deg(30)), 52);
      expect(e.turnCostFor(deg(60)), 100);
      expect(e.turnCostFor(deg(90)), 141);
      expect(e.turnCostFor(deg(120)), 173);
      expect(e.turnCostFor(deg(180)), 200);
    });

    test('60 degrees is the crossover: past it, stopping is cheaper', () {
      // Not a coincidence — both quotes are built from `brakingDistanceLy`.
      // Under 60 the turn is the cheap way out; over 60 the ship should brake
      // and re-ignite, which is free. The cockpit says so out loud rather than
      // letting the player overpay in silence.
      const e = Engine.standard;
      final braking = e.brakingCostFor(e.cruiseSpeedLyPerSec);
      expect(braking, 100);
      expect(e.turnCostFor(60 * math.pi / 180), braking);
      expect(e.turnCostFor(30 * math.pi / 180), lessThan(braking));
      expect(e.turnCostFor(120 * math.pi / 180), greaterThan(braking));
    });

    test('an engine saved before activation existed pays the standard fee', () {
      final json = Engine.standard.toJson()..remove('activationCost');
      expect(json.containsKey('activationCost'), isFalse,
          reason: 'precondition: this is what an old save looks like');
      expect(Engine.fromJson(json).activationCost, Engine.standard.activationCost);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/cruise_test.dart`
Expected: FAIL — `The getter 'powerDrawPerSecond' isn't defined for the type 'Engine'` (and the same for the other three members).

- [ ] **Step 3: Add the activation fee field**

In `starward/lib/data/models/engine.dart`, add to the constructor parameter list (after `required this.minTravelSeconds,`):

```dart
    required this.activationCost,
```

and add the field next to `minTravelSeconds`:

```dart
  /// What it costs to bring the engine back online after the tank ran dry and
  /// it shut itself down. A flat fee, not a function of anything: the point is
  /// that recovery has a price, not that it scales.
  final int activationCost;
```

Set it on the standard engine:

```dart
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
```

- [ ] **Step 4: Add the four derived members**

Still in `starward/lib/data/models/engine.dart`, after `brakingCostFor`:

```dart
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
```

- [ ] **Step 5: Persist the new field with a migration**

In `toJson`, add `'activationCost': activationCost,` to the returned map. In `fromJson`, alongside the existing fallbacks:

```dart
        // Absent in saves written before the activation fee existed. The
        // standard fee is the only sensible reading: an engine that predates the
        // field is a standard engine.
        activationCost:
            (json['activationCost'] as num?)?.toInt() ?? Engine.standard.activationCost,
```

- [ ] **Step 6: Fix the four test construction sites**

`activationCost` is a required field, so these four `Engine(...)` literals no longer compile. Add `activationCost: 5,` to each (after `minTravelSeconds`):

- `starward/test/ship_test.dart:16` — `_thrifty`
- `starward/test/drift_report_test.dart:55` — `_greedy`
- `starward/test/flight_panel_test.dart:258` — `_greedy`
- `starward/test/return_to_origin_test.dart:146` — the inline greedy engine

- [ ] **Step 7: Run the tests and analyze**

Run: `flutter test test/cruise_test.dart test/ship_test.dart test/drift_report_test.dart test/flight_panel_test.dart test/return_to_origin_test.dart`
Expected: PASS, all of them.

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add starward/lib/data/models/engine.dart starward/test/cruise_test.dart \
        starward/test/ship_test.dart starward/test/drift_report_test.dart \
        starward/test/flight_panel_test.dart starward/test/return_to_origin_test.dart
git commit -m "feat(starward): teach the engine what a cruise, a turn and a restart cost

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 2: Three new ledger kinds

**Files:**
- Modify: `starward/lib/data/models/energy_transaction.dart`
- Test: `starward/test/cruise_save_test.dart` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `EnergyTxType.cruiseCost`, `EnergyTxType.turn`, `EnergyTxType.activation`.

- [ ] **Step 1: Write the failing test**

Create `starward/test/cruise_save_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/models/energy_transaction.dart';

void main() {
  group('EnergyTxType', () {
    test('a cruise, a turn and an activation are three separate kinds', () {
      // Not one "misc" bucket: the ledger is the only place a player can see
      // where the tank went, and "I cruised 200 ly" and "I turned 40 degrees"
      // are different answers to "why is it empty".
      expect(EnergyTxType.values, contains(EnergyTxType.cruiseCost));
      expect(EnergyTxType.values, contains(EnergyTxType.turn));
      expect(EnergyTxType.values, contains(EnergyTxType.activation));
      expect(
        <EnergyTxType>{
          EnergyTxType.travelCost,
          EnergyTxType.trainingReward,
          EnergyTxType.explorationReward,
          EnergyTxType.braking,
          EnergyTxType.cruiseCost,
          EnergyTxType.turn,
          EnergyTxType.activation,
        }.length,
        EnergyTxType.values.length,
        reason: 'no two kinds may share a name — the enum name is the save key',
      );
    });

    test('the new kinds survive a save round trip', () {
      for (final t in <EnergyTxType>[
        EnergyTxType.cruiseCost,
        EnergyTxType.turn,
        EnergyTxType.activation,
      ]) {
        expect(energyTxTypeFromName(t.name), t);
      }
    });

    test('an unknown name still falls back to travelCost', () {
      // The `orElse` is what lets an old build read a newer save.
      expect(energyTxTypeFromName('somethingNew'), EnergyTxType.travelCost);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/cruise_save_test.dart`
Expected: FAIL — `The getter 'cruiseCost' isn't defined for the type 'EnergyTxType'`.

- [ ] **Step 3: Add the three members**

In `starward/lib/data/models/energy_transaction.dart`:

```dart
/// What a ledger entry is for.
///
/// The enum *name* is the save key — see [energyTxTypeFromName] — so members may
/// be added but never renamed.
enum EnergyTxType {
  travelCost,
  trainingReward,
  explorationReward,
  braking,

  /// A powered drift's continuous draw. One entry per leg, booked when the leg
  /// ends — on a turn, on a brake, or when the tank runs dry.
  cruiseCost,

  /// A heading correction, priced by the angle turned.
  turn,

  /// The flat fee that brings a dormant engine back online.
  activation,
}
```

- [ ] **Step 4: Run the tests and analyze**

Run: `flutter test test/cruise_save_test.dart`
Expected: PASS.

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add starward/lib/data/models/energy_transaction.dart starward/test/cruise_save_test.dart
git commit -m "feat(starward): give cruises, turns and activations their own ledger kinds

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 3: The player remembers three new things

**Files:**
- Modify: `starward/lib/data/models/player_state.dart`
- Test: `starward/test/cruise_save_test.dart` (append)

**Interfaces:**
- Consumes: `FuelPolicy` from `starward/lib/data/models/journey.dart`.
- Produces: `PlayerState.driftPowered` (`bool`, default false); `PlayerState.engineDormant` (`bool`, default false); `PlayerState.cruisePolicy` (`FuelPolicy`, default `FuelPolicy.halt`); `PlayerState.copyWith` accepts all three.

- [ ] **Step 1: Write the failing test**

Append to `starward/test/cruise_save_test.dart` (and add the imports it needs):

```dart
import 'package:starward/data/models/journey.dart';
import 'package:starward/data/models/player_state.dart';
```

```dart
  group('PlayerState cruise fields', () {
    PlayerState parked() => PlayerState.deepSpaceStart(
          energy: 300,
          startCoordX: 0,
          startCoordY: 0,
          startX: 1,
          startY: 2,
          startZ: 3,
          createdAt: DateTime(2026),
        );

    test('a fresh player is parked, awake, and would halt on an empty tank', () {
      final p = parked();
      expect(p.driftPowered, isFalse);
      expect(p.engineDormant, isFalse);
      expect(p.cruisePolicy, FuelPolicy.halt);
    });

    test('the three fields survive a save round trip', () {
      final p = parked().copyWith(
        driftPowered: true,
        engineDormant: true,
        cruisePolicy: FuelPolicy.coast,
      );
      final back = PlayerState.fromJson(p.toJson());
      expect(back.driftPowered, isTrue);
      expect(back.engineDormant, isTrue);
      expect(back.cruisePolicy, FuelPolicy.coast);
    });

    test('an old save with none of the keys loads as parked and awake', () {
      // The migration that matters: every save written before this feature has
      // no drift at all, so "not powered, not dormant" is not a guess — it is
      // the only reading that leaves those saves behaving as they always did.
      final json = parked().toJson()
        ..remove('driftPowered')
        ..remove('engineDormant')
        ..remove('cruisePolicy');
      final back = PlayerState.fromJson(json);
      expect(back.driftPowered, isFalse);
      expect(back.engineDormant, isFalse);
      expect(back.cruisePolicy, FuelPolicy.halt);
    });

    test('copyWith leaves the new fields alone unless asked', () {
      final p = parked().copyWith(
        driftPowered: true,
        engineDormant: true,
        cruisePolicy: FuelPolicy.coast,
      );
      final energyOnly = p.copyWith(energyBalance: 42);
      expect(energyOnly.driftPowered, isTrue);
      expect(energyOnly.engineDormant, isTrue);
      expect(energyOnly.cruisePolicy, FuelPolicy.coast);
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/cruise_save_test.dart`
Expected: FAIL — `The getter 'driftPowered' isn't defined for the type 'PlayerState'`.

- [ ] **Step 3: Add the fields**

In `starward/lib/data/models/player_state.dart`, add the import:

```dart
import 'journey.dart';
```

(`journey.dart` imports nothing, so this cannot create a cycle.)

Add the three fields next to `driftStartedAt`, and give them defaults in the constructor:

```dart
    this.driftPowered = false,
    this.engineDormant = false,
    this.cruisePolicy = FuelPolicy.halt,
```

```dart
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
```

- [ ] **Step 4: Wire up JSON and `copyWith`**

In `toJson`, add:

```dart
        'driftPowered': driftPowered,
        'engineDormant': engineDormant,
        'cruisePolicy': cruisePolicy.name,
```

In `fromJson`, add:

```dart
        // All three are absent in every save written before free cruise existed.
        // The defaults are the only reading that keeps those saves behaving
        // exactly as they did: not powered, not dormant, halt on empty.
        driftPowered: json['driftPowered'] as bool? ?? false,
        engineDormant: json['engineDormant'] as bool? ?? false,
        cruisePolicy: cruisePolicyFromName(json['cruisePolicy'] as String?),
```

In `journey.dart`, add next to `fuelPolicyFromName`:

```dart
/// Reads a [FuelPolicy] back from a save, falling back to the safe default when
/// the key is absent (an old save) or unrecognised.
FuelPolicy cruisePolicyFromName(String? name) {
  if (name == null) return FuelPolicy.halt;
  return FuelPolicy.values.firstWhere((p) => p.name == name,
      orElse: () => FuelPolicy.halt);
}
```

In `copyWith`, add the three parameters and pass them through:

```dart
    bool? driftPowered,
    bool? engineDormant,
    FuelPolicy? cruisePolicy,
```

```dart
      driftPowered: driftPowered ?? this.driftPowered,
      engineDormant: engineDormant ?? this.engineDormant,
      cruisePolicy: cruisePolicy ?? this.cruisePolicy,
```

- [ ] **Step 5: Run the tests and analyze**

Run: `flutter test test/cruise_save_test.dart test/coast_test.dart test/fuel_out_test.dart`
Expected: PASS. `coast_test.dart` and `fuel_out_test.dart` must be untouched and still green — they hand-edit save JSON, and the new keys default correctly.

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add starward/lib/data/models/player_state.dart starward/lib/data/models/journey.dart starward/test/cruise_save_test.dart
git commit -m "feat(starward): persist whether a drift is powered, dormant, and how it should end

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 4: The controller learns the words

**Files:**
- Modify: `starward/lib/state/game_controller.dart:268-305` (the drift getters), `:919` (`canBrake`)
- Test: `starward/test/cruise_test.dart` (append)

**Interfaces:**
- Consumes: `PlayerState.driftPowered`.
- Produces: `GameController.hasMomentum` (`bool`); `isCoasting` (now `hasMomentum && !driftPowered`); `isCruising` (`bool`); `isDormant` (`bool`). `driftElapsed`, `driftDistanceLy`, `driftPath`, `brakingCost`, `canBrake` all key off `hasMomentum` instead of `isCoasting`.

**Why this is behaviour-preserving:** `driftPowered` is false in every save that exists and in every code path that currently sets a velocity, so `hasMomentum == isCoasting` for all of them. This task adds vocabulary; Task 5 is the first thing that makes the two differ.

- [ ] **Step 1: Write the failing test**

Append to `starward/test/cruise_test.dart` (add the imports it needs):

```dart
import 'dart:convert';

import 'package:starward/data/game_repository.dart';
import 'package:starward/data/models/player_state.dart';
import 'package:starward/data/storage/storage_backend.dart';
import 'package:starward/state/game_controller.dart';

import 'package:starward/core/vec3.dart';
```

```dart
class FakeClock {
  FakeClock(this._now);
  DateTime _now;
  DateTime call() => _now;
  void advance(Duration d) => _now = _now.add(d);
}

Future<GameController> _boot(FakeClock clock, {StorageBackend? storage}) async {
  final c = GameController(
    repository: GameRepository(storage ?? MemoryStorage()),
    clock: clock.call,
    random: math.Random(3),
  );
  await c.init();
  return c;
}

/// Writes a drift into the save, so a test can start from a ship already moving.
///
/// [powered] is written too: a hand-built save is the only way to reach a
/// cruising ship without going through `igniteCruise`, which is exactly what
/// makes it a useful fixture for the read-only tests below.
Future<void> _setDrift(
  MemoryStorage storage,
  Vec3 velocity,
  DateTime startedAt, {
  bool powered = false,
}) async {
  final raw = await storage.read('starward.save.v2');
  final json = jsonDecode(raw!) as Map<String, dynamic>;
  final player = json['player'] as Map<String, dynamic>;
  player['driftVelocityX'] = velocity.x;
  player['driftVelocityY'] = velocity.y;
  player['driftVelocityZ'] = velocity.z;
  player['driftStartedAt'] = startedAt.millisecondsSinceEpoch;
  player['driftPowered'] = powered;
  await storage.write('starward.save.v2', jsonEncode(json));
}
```

```dart
  group('drift vocabulary', () {
    test('a parked ship has no momentum and is neither coasting nor cruising',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      expect(c.hasMomentum, isFalse);
      expect(c.isCoasting, isFalse);
      expect(c.isCruising, isFalse);
      expect(c.isDormant, isFalse);
    });

    test('an unpowered drift is a coast, and reads exactly as it did before',
        () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      await _boot(clock, storage: storage);
      await _setDrift(storage, const Vec3(1 / 37.5, 0, 0), clock());
      final c = await _boot(clock, storage: storage);

      expect(c.hasMomentum, isTrue);
      expect(c.isCoasting, isTrue);
      expect(c.isCruising, isFalse);

      // The three getters that used to key off `isCoasting` must give the same
      // answers they always did for a save that predates this feature.
      clock.advance(const Duration(seconds: 100));
      expect(c.driftElapsed, const Duration(seconds: 100));
      expect(c.driftDistanceLy, closeTo(100 / 37.5, 1e-9));
      expect(c.driftPath, isNotNull);
      expect(c.brakingCost, 100);
      expect(c.canBrake, isTrue);
    });

    test('a powered drift is a cruise, not a coast', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      await _boot(clock, storage: storage);
      await _setDrift(storage, const Vec3(1 / 37.5, 0, 0), clock(),
          powered: true);
      final c = await _boot(clock, storage: storage);

      expect(c.hasMomentum, isTrue);
      expect(c.isCruising, isTrue);
      expect(c.isCoasting, isFalse);
      // A cruising ship is still moving, so it still has momentum to shed and
      // the same quote to shed it. If this were zero, "cruise out, then launch
      // a voyage" would be a free ferry.
      expect(c.brakingCost, 100);
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/cruise_test.dart`
Expected: FAIL — `The getter 'hasMomentum' isn't defined for the type 'GameController'`.

- [ ] **Step 3: Replace the drift getters**

In `starward/lib/state/game_controller.dart`, replace the block from `/// Whether the ship is coasting` (line 268) through the end of `driftPath` (line 305) with:

```dart
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
```

- [ ] **Step 4: Move `canBrake` onto the same footing**

Replace line 919:

```dart
  bool get canBrake => !hasMomentum || _player.energyBalance >= brakingCost;
```

- [ ] **Step 5: Run the whole suite and analyze**

Run: `flutter test`
Expected: PASS, every file. This task changes no behaviour, so a single failure means the refactor was not behaviour-preserving — read it before assuming the test is wrong.

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add starward/lib/state/game_controller.dart starward/test/cruise_test.dart
git commit -m "refactor(starward): name the three drift states instead of one coasting flag

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Phase 2 — 点火与耗电

The ship can now be lit with no destination, burns while it flies, and stops when the tank runs out. Ships on its own: after this phase a stranded player has a way out, through the controller API. The UI for it arrives in Phase 3.

---

### Task 5: Ignition with no destination

**Files:**
- Modify: `starward/lib/state/game_controller.dart` (add after `stopShip`, around line 945)
- Test: `starward/test/cruise_test.dart` (append)

**Interfaces:**
- Consumes: `hasMomentum`, `playerPosition3D`, `PlayerState.driftPowered`/`cruisePolicy`.
- Produces: `Future<LaunchResult> GameController.igniteCruise(Vec3 heading, {required FuelPolicy onEmpty})`; private `void _repinLeg({Vec3? velocity, DateTime? at})`.

- [ ] **Step 1: Write the failing test**

Append to `starward/test/cruise_test.dart`:

```dart
/// Flies to the nearest planet and arrives, so the ship is docked.
Future<GameController> _docked(FakeClock clock, MemoryStorage storage) async {
  final c = await _boot(clock, storage: storage);
  final near = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
  expect(await c.launchJourney(near), LaunchResult.success,
      reason: 'precondition: the nearest planet is affordable from a full tank');
  clock.advance(const Duration(hours: 12));
  c.tick();
  await c.acknowledgeArrival();
  expect(c.currentPlanetId, near.id, reason: 'precondition: docked');
  return _boot(clock, storage: storage);
}
```

```dart
  group('igniteCruise', () {
    test('lights the engine along the chosen heading and starts the meter',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final before = c.playerPosition3D;

      expect(await c.igniteCruise(const Vec3(1, 0, 0),
          onEmpty: FuelPolicy.coast), LaunchResult.success);

      expect(c.isCruising, isTrue);
      expect(c.isCoasting, isFalse);
      expect(c.driftVelocity.length,
          closeTo(c.ship.engine.cruiseSpeedLyPerSec, 1e-12));
      // The heading is a direction, not a speed: a caller that passes a long
      // vector must still get cruise speed, not a multiple of it.
      expect(c.driftVelocity.y, closeTo(0, 1e-12));
      expect(c.driftVelocity.z, closeTo(0, 1e-12));
      expect(c.player.cruisePolicy, FuelPolicy.coast,
          reason: 'the choice is made at ignition and acted on much later');
      // The anchor is re-pinned to where the ship already is, so lighting the
      // engine does not teleport it back to its last anchor.
      expect((c.playerPosition3D - before).length, lessThan(1e-9));
      expect(c.driftElapsed, Duration.zero);
    });

    test('ignition itself is free — the price is the power it draws', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await c.igniteCruise(const Vec3(0, 0, 1), onEmpty: FuelPolicy.halt);
      expect(c.energy, 300, reason: 'nothing is charged at t=0');
      expect(c.energyLedger, isEmpty);
    });

    test('a normalised heading of any length gives the same cruise', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await c.igniteCruise(const Vec3(0, 0, 7), onEmpty: FuelPolicy.halt);
      expect(c.driftVelocity.length,
          closeTo(c.ship.engine.cruiseSpeedLyPerSec, 1e-12));
      expect(c.driftVelocity.z, closeTo(c.ship.engine.cruiseSpeedLyPerSec, 1e-12));
    });

    test('refuses a zero heading', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      expect(await c.igniteCruise(const Vec3(0, 0, 0), onEmpty: FuelPolicy.halt),
          LaunchResult.noSelection);
      expect(c.hasMomentum, isFalse);
    });

    test('refuses to light an engine that is already moving the ship', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      expect(await c.igniteCruise(const Vec3(0, 0, 1), onEmpty: FuelPolicy.halt),
          LaunchResult.alreadyTraveling);
      expect(c.driftVelocity.x, greaterThan(0),
          reason: 'the original heading is untouched');
    });

    test('refuses while a voyage is in progress', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final target = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
      await c.launchJourney(target);
      expect(await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt),
          LaunchResult.alreadyTraveling);
    });

    test('refuses at a planet — a docked ship is not stranded', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _docked(clock, storage);
      expect(await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt),
          LaunchResult.alreadyHere);
    });

    test('refuses on an empty tank', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      await _boot(clock, storage: storage);
      await _setEnergy(storage, 0);
      final c = await _boot(clock, storage: storage);
      expect(c.energy, 0, reason: 'precondition: the tank is dry');
      expect(await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt),
          LaunchResult.insufficientEnergy);
    });
  });
```

Add this helper next to `_setDrift`:

```dart
/// Rewrites the saved balance, so a test can start from a tank it chooses.
Future<void> _setEnergy(MemoryStorage storage, int balance) async {
  final raw = await storage.read('starward.save.v2');
  final json = jsonDecode(raw!) as Map<String, dynamic>;
  (json['player'] as Map<String, dynamic>)['energyBalance'] = balance;
  await storage.write('starward.save.v2', jsonEncode(json));
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/cruise_test.dart`
Expected: FAIL — `The method 'igniteCruise' isn't defined for the type 'GameController'`.

- [ ] **Step 3: Add `_repinLeg`**

In `starward/lib/state/game_controller.dart`, add after `_driftSecondsAt` (line 309):

```dart
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
```

- [ ] **Step 4: Add `igniteCruise`**

Add after `stopShip` (around line 945):

```dart
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
    if (_player.engineDormant) return LaunchResult.engineDormant;
    if (hasMomentum) return LaunchResult.alreadyTraveling;
    if (isTraveling) return LaunchResult.alreadyTraveling;
    if (!_player.inDeepSpace) return LaunchResult.alreadyHere;
    if (_player.energyBalance <= 0) return LaunchResult.insufficientEnergy;

    final pos = playerPosition3D;
    _player = _player.copyWith(
      driftVelocity: direction * _ship.engine.cruiseSpeedLyPerSec,
      driftPowered: true,
      cruisePolicy: onEmpty,
      startX: pos.x,
      startY: pos.y,
      startZ: pos.z,
      driftStartedAt: _now(),
    );
    await _persist();
    notifyListeners();
    return LaunchResult.success;
  }
```

`LaunchResult.engineDormant` does not exist yet — that is Task 10. **For this task, replace that one line with nothing** and add it in Task 10; the dormancy test arrives there too.

- [ ] **Step 5: Run the tests and analyze**

Run: `flutter test test/cruise_test.dart`
Expected: PASS.

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add starward/lib/state/game_controller.dart starward/test/cruise_test.dart
git commit -m "feat(starward): let the engine be lit with no destination

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 6: A cruise drains the tank

**Files:**
- Modify: `starward/lib/state/game_controller.dart:407` (`energy`), and new members after `canBrake`
- Test: `starward/test/cruise_test.dart` (append)

**Interfaces:**
- Consumes: `Engine.burnForSeconds`, `Engine.secondsForEnergy`, `_driftSecondsAt`.
- Produces: `int GameController.cruiseReserve` (getter); `Duration GameController.cruiseRemaining` (getter); private `int _cruiseBurnNow()`.

- [ ] **Step 1: Write the failing test**

Append to `starward/test/cruise_test.dart`:

```dart
  group('a cruise drains the tank', () {
    test('the meter runs while the engine is on', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      expect(c.energy, 300);

      // 37.5 s is one light-year, which is 3 EN — the same quote a voyage of
      // that length gets. Nothing about the price is cruise-specific.
      clock.advance(const Duration(seconds: 37, milliseconds: 500));
      expect(c.energy, 297);

      clock.advance(const Duration(seconds: 1462, milliseconds: 500));
      expect(c.energy, 180, reason: '1500 s is 40 ly is 100 EN');
    });

    test('a coast does not drain anything', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      await _boot(clock, storage: storage);
      await _setDrift(storage, const Vec3(1 / 37.5, 0, 0), clock());
      final c = await _boot(clock, storage: storage);

      clock.advance(const Duration(days: 3));
      expect(c.energy, 300, reason: 'an unpowered drift costs nothing to run');
    });

    test('the reserve is what the cruise must keep to buy its own stop', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      expect(c.cruiseReserve, 100);
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      // While cruising the two quotes coincide, which is the point: the reserve
      // *is* the braking cost, held back rather than spent.
      expect(c.cruiseReserve, c.brakingCost);
    });

    test('the remaining-time readout counts down one-for-one with the meter',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      expect(c.cruiseRemaining, Duration.zero, reason: 'not cruising yet');

      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      // 300 EN less the 100 EN reserve is 200 EN, which is 3000 s.
      expect(c.cruiseRemaining, const Duration(seconds: 3000));

      clock.advance(const Duration(seconds: 1500));
      expect(c.cruiseRemaining, const Duration(seconds: 1500));
    });

    test('the reserve is held back even at the very start', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      await _boot(clock, storage: storage);
      await _setEnergy(storage, 100);
      final c = await _boot(clock, storage: storage);
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      // Every last drop is already spoken for, so there is no cruise to run.
      expect(c.cruiseRemaining, Duration.zero);
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/cruise_test.dart`
Expected: FAIL — `The getter 'cruiseReserve' isn't defined for the type 'GameController'`, and `Expected: <297> Actual: <300>` on the first test.

- [ ] **Step 3: Add `_cruiseBurnNow`, `cruiseReserve` and `cruiseRemaining`**

In `starward/lib/state/game_controller.dart`, add after `canBrake` (line 919):

```dart
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
```

- [ ] **Step 4: Teach `energy` about the cruise**

Replace the `energy` getter (line 407):

```dart
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
```

- [ ] **Step 5: Run the tests and analyze**

Run: `flutter test test/cruise_test.dart`
Expected: PASS.

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add starward/lib/state/game_controller.dart starward/test/cruise_test.dart
git commit -m "feat(starward): charge a cruise for the power it draws, second by second

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 7: The accrued burn is booked when the leg ends

**Files:**
- Modify: `starward/lib/state/game_controller.dart` (`_anchorHere` at :384, `_launchGate` at :1123, `stopShip` at :935, `_applyFuelOut` at :628)
- Test: `starward/test/cruise_test.dart` (append)

**Interfaces:**
- Consumes: `_cruiseBurnNow`, `_repinLeg`, `EnergyTxType.cruiseCost`.
- Produces: private `int _settleCruise()`.

- [ ] **Step 1: Write the failing test**

Append to `starward/test/cruise_test.dart` (add `import 'package:starward/data/models/energy_transaction.dart';`):

```dart
  group('settling a cruise leg', () {
    test('braking books the leg and the burn, in that order', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      clock.advance(const Duration(seconds: 1500));
      expect(c.energy, 200, reason: '100 EN of cruise is already spent');

      await c.stopShip();

      // Never 200: the leg's 100 EN was spent the moment it was burned, and the
      // brake's 100 EN comes out of what is left.
      expect(c.energy, 100);
      expect(c.hasMomentum, isFalse);
      expect(c.isCruising, isFalse);
      expect(c.energyLedger, hasLength(2));
      expect(c.energyLedger.first.type, EnergyTxType.braking);
      expect(c.energyLedger.first.amount, -100);
      expect(c.energyLedger[1].type, EnergyTxType.cruiseCost);
      expect(c.energyLedger[1].amount, -100);
    });

    test('the burn is booked once, not once per settle', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      clock.advance(const Duration(seconds: 1500));
      // `_anchorHere` settles too, so `stopShip`'s own settle must be a no-op
      // the second time round — a double booking here would be silent.
      await c.stopShip();
      final entries = c.energyLedger.length;
      await c.stopShip();
      expect(c.energyLedger, hasLength(entries));
      expect(c.energy, 100);
    });

    test('launching a voyage mid-cruise settles the leg and charges the brake',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final target = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      clock.advance(const Duration(seconds: 1500));

      // A lenient policy, so the gate turns only on the braking reserve — the
      // point here is the settlement, not the quote.
      expect(await c.launchJourney(target, onEmpty: FuelPolicy.halt),
          LaunchResult.success);
      expect(c.energy, 100,
          reason: 'the leg and the brake are both gone; the voyage has not burned yet');
      expect(c.isCruising, isFalse);
      expect(c.hasMomentum, isFalse, reason: 'the brake parked the ship');
    });

    test('the gate sees the unbooked burn, not the stale balance', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      clock.advance(const Duration(seconds: 4500));
      // The reserve is all that is left, and it is spoken for.
      expect(c.energy, 100);
      final far = c.planets
          .where((p) => p.id != c.currentPlanetId)
          .reduce((a, b) => c.distanceTo(a) > c.distanceTo(b) ? a : b);
      expect(await c.launchJourney(far, onEmpty: FuelPolicy.halt),
          LaunchResult.insufficientEnergy,
          reason: 'a lenient launch still needs more than the braking reserve');
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/cruise_test.dart`
Expected: FAIL — `Expected: <100> Actual: <200>` on the first test: the leg's burn is never booked.

- [ ] **Step 3: Add `_settleCruise`**

In `starward/lib/state/game_controller.dart`, add after `_cruiseBurnNow`:

```dart
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
    return burned;
  }
```

- [ ] **Step 4: Settle inside `_anchorHere`**

Replace `_anchorHere` (line 384):

```dart
  /// Brings the ship to rest where it is, billing any momentum it has to shed.
  ///
  /// The cruise settle comes first, and it has to: `brakingCost` is quoted from
  /// the velocity, but what the tank actually holds is the balance *minus* the
  /// leg's accrued burn. Settling after reading the cost would spend the same
  /// energy twice.
  void _anchorHere() {
    _settleCruise();
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
```

- [ ] **Step 5: Make the launch gate ask the live balance**

Replace `_launchGate` (line 1123):

```dart
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
```

- [ ] **Step 6: Settle in `stopShip` before checking the brake**

Replace `stopShip`'s body (lines 935-945):

```dart
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
```

- [ ] **Step 7: Clear the powered flag when fuel runs out**

In `_applyFuelOut`, add `driftPowered: false,` to the `_player.copyWith(...)` at line 628:

```dart
      driftVelocity: journey.fuelPolicy == FuelPolicy.coast
          ? _cruiseVelocityOf(journey)
          : const Vec3(0, 0, 0),
      // An out-of-fuel drift is a coast whatever put the ship there: there is
      // nothing left to power it with.
      driftPowered: false,
```

- [ ] **Step 8: Run the whole suite and analyze**

Run: `flutter test`
Expected: PASS, every file — including `braking_test.dart`, whose "training is the way out of a drift that cannot afford to brake" case now goes through the extra settle (a no-op for a coast).

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 9: Commit**

```bash
git add starward/lib/state/game_controller.dart starward/test/cruise_test.dart
git commit -m "feat(starward): book a cruise leg's burn when the leg ends

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 8: Running the tank dry mid-cruise

**Files:**
- Modify: `starward/lib/state/game_controller.dart` (`tick` at :730, new members after `_settleCruise`)
- Test: `starward/test/cruise_test.dart` (append)

**Interfaces:**
- Consumes: `cruiseReserve`, `Engine.secondsForEnergy`, `_player.cruisePolicy`, `DriftReport`, `DriftReportKind.fuelOut`.
- Produces: private `DateTime? _cruiseExhaustTime()`, `Future<void> _reconcileCruise()`, `DriftReport _cruiseDriftReport(...)`. `tick()` now resolves an exhausted cruise.

- [ ] **Step 1: Write the failing test**

Append to `starward/test/cruise_test.dart` (add `import 'package:starward/data/models/drift_report.dart';`):

```dart
  group('running the tank dry mid-cruise', () {
    /// Ignites with a full tank and runs the cruise to its exhaustion point.
    Future<GameController> exhausted(
      FakeClock clock,
      FuelPolicy policy,
    ) async {
      final c = await _boot(clock);
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: policy);
      // 300 EN less the 100 EN reserve is 200 EN, which is exactly 3000 s.
      clock.advance(const Duration(seconds: 3000));
      c.tick();
      return c;
    }

    test('halt stops the ship exactly at the quoted 80 ly', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final start = c.playerPosition3D;
      final c2 = await exhausted(clock, FuelPolicy.halt);

      expect(identical(c, c2), isTrue, reason: 'precondition: same controller');
      expect(c.hasMomentum, isFalse, reason: 'halt parks the ship');
      expect(c.energy, 100, reason: 'the reserve is kept, not burned');
      expect(c.isDormant, isTrue, reason: 'the tank is out of spendable energy');
      // 3000 s at 1/37.5 ly/s. The exhaustion check compares *seconds*, not
      // energy: `burnForSeconds(elapsed) >= 200` trips at 2992 s and lands 0.2 ly
      // short of this.
      expect((c.playerPosition3D - start).length, closeTo(80.0, 0.01));
    });

    test('coast keeps the ship moving with the engine off', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final start = c.playerPosition3D;
      await exhausted(clock, FuelPolicy.coast);

      expect(c.hasMomentum, isTrue);
      expect(c.isCoasting, isTrue, reason: 'out of power, still moving');
      expect(c.isCruising, isFalse);
      expect(c.isDormant, isTrue);
      expect(c.energy, 100);
      expect(c.driftVelocity.length,
          closeTo(c.ship.engine.cruiseSpeedLyPerSec, 1e-12));
      expect((c.playerPosition3D - start).length, closeTo(80.0, 0.01));

      // And it keeps going, for free, from the exhaust point.
      clock.advance(const Duration(seconds: 1500));
      expect(c.energy, 100);
      expect((c.playerPosition3D - start).length, closeTo(120.0, 0.01));
    });

    test('the whole spendable budget is booked, exactly once', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await exhausted(clock, FuelPolicy.halt);
      expect(c.energyLedger, hasLength(1));
      expect(c.energyLedger.first.type, EnergyTxType.cruiseCost);
      expect(c.energyLedger.first.amount, -200);
    });

    test('the burn is not charged for the interval after the tank ran dry',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      // Notice a full day late: the ship had no spendable energy for 23 of those
      // hours, so charging for them would invent a burn that never happened.
      clock.advance(const Duration(days: 1));
      c.tick();
      expect(c.energy, 100);
      expect(c.energyLedger.single.amount, -200);
      // And the ship is where it should have stopped, not where a full day of
      // cruise would have taken it.
      expect(c.driftElapsed, Duration.zero, reason: 'halt cleared the drift');
    });

    test('a coast noticed late still anchors at the exhaust point', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final start = c.playerPosition3D;
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.coast);
      clock.advance(const Duration(days: 1));
      c.tick();

      // 80 ly of powered cruise, then the rest of the day coasting: a day is
      // 86400 s, so 83400 s of coast at cruise speed is a further 2224 ly.
      expect(c.energy, 100);
      expect(c.isCoasting, isTrue);
      expect((c.playerPosition3D - start).length, closeTo(80 + 83400 / 37.5, 1.0));
    });

    test('a fuel-out report is queued for the leg that just ended', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await exhausted(clock, FuelPolicy.coast);
      final report = c.pendingDriftReport;
      expect(report, isNotNull);
      expect(report!.kind, DriftReportKind.fuelOut);
      expect(report.distanceLy, closeTo(80.0, 0.01));
      expect(report.elapsed, const Duration(seconds: 3000));
      expect((report.toPos - report.fromPos).length, closeTo(80.0, 0.01));
      expect(report.hitBoundary, isFalse);
    });

    test('tick is a no-op for a cruise that still has time on the clock',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      clock.advance(const Duration(seconds: 2999));
      c.tick();
      expect(c.isCruising, isTrue);
      expect(c.isDormant, isFalse);
      expect(c.energyLedger, isEmpty, reason: 'nothing is booked mid-leg');
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/cruise_test.dart`
Expected: FAIL — the ship is still cruising after 3000 s and no `cruiseCost` entry exists.

- [ ] **Step 3: Add the exhaustion time**

In `starward/lib/state/game_controller.dart`, add after `_settleCruise`:

```dart
  /// The instant the current cruise runs out of the energy it is allowed to
  /// spend, or null if it is not cruising / never will.
  ///
  /// Compared on *time*, not on energy: `burnForSeconds` rounds to whole EN, so
  /// testing `burnForSeconds(elapsed) >= budget` fires a tick early — at a
  /// budget of 200 it trips at 2992 s instead of 3000 s, and the halt point
  /// lands 0.2 ly short of the 80 ly the readout promised. Division keeps it
  /// exact: `secondsForEnergy(200)` is 3000.0, while `200 / powerDraw` computed
  /// the other way round is 3000.0000000000005.
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
```

- [ ] **Step 4: Add the report builder**

Add after `_cruiseExhaustTime`:

```dart
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
```

- [ ] **Step 5: Add `_reconcileCruise`**

Add after `_cruiseDriftReport`:

```dart
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
```

- [ ] **Step 6: Teach `tick` about the cruise**

Replace `tick` (line 730):

```dart
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
```

- [ ] **Step 7: Run the whole suite and analyze**

Run: `flutter test`
Expected: PASS, every file. `coast_test.dart` and `fuel_out_test.dart` are the ones to watch: neither has a `driftPowered` key in its hand-edited saves, so both must still load as coasts.

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add starward/lib/state/game_controller.dart starward/test/cruise_test.dart
git commit -m "feat(starward): resolve a cruise that runs its tank dry

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Phase 3 — 休眠、激活与入口

After this phase the player can actually see and use the feature from the voyage screen. Dormancy is the state the whole thing is built to avoid, and activation is the way out of it.

---

### Task 9: Dormancy and the activation fee

**Files:**
- Modify: `starward/lib/state/game_controller.dart` (`_settleBurn` at :1144, `_settleBraking` at :1166, `_settleTank` at :1183, `_settleCruise`, new `_syncDormancy`/`activate`)
- Test: `starward/test/dormancy_test.dart` (create)

**Interfaces:**
- Consumes: `PlayerState.engineDormant`, `Engine.activationCost`, `EnergyTxType.activation`.
- Produces: `bool GameController.isDormant` (already added in Task 4, now backed by real transitions); `Future<bool> GameController.activate()`; private `void _syncDormancy()`.

**Constraint, deliberately not implemented:** `init()` must **not** call `_syncDormancy()`. A save written before dormancy existed, with an empty tank, has to keep behaving as it did — the launch gate refuses on energy, which is a message the player understands, rather than on a shutdown they never saw happen. `test/fuel_out_test.dart:166` ("an empty tank moves nothing under any policy") depends on exactly this, and its hand-edited save has no `engineDormant` key. Do not "tidy this up".

- [ ] **Step 1: Write the failing test**

Create `starward/test/dormancy_test.dart`:

```dart
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/vec3.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/models/energy_transaction.dart';
import 'package:starward/data/models/journey.dart';
import 'package:starward/data/models/planet.dart';
import 'package:starward/data/storage/storage_backend.dart';
import 'package:starward/state/game_controller.dart';

class FakeClock {
  FakeClock(this._now);
  DateTime _now;
  DateTime call() => _now;
  void advance(Duration d) => _now = _now.add(d);
}

Future<GameController> _boot(FakeClock clock, {MemoryStorage? storage}) async {
  final c = GameController(
    repository: GameRepository(storage ?? MemoryStorage()),
    clock: clock.call,
    random: math.Random(3),
  );
  await c.init();
  return c;
}

Future<void> _editPlayer(
  MemoryStorage storage,
  void Function(Map<String, dynamic> player) edit,
) async {
  final raw = await storage.read('starward.save.v2');
  final json = jsonDecode(raw!) as Map<String, dynamic>;
  edit(json['player'] as Map<String, dynamic>);
  await storage.write('starward.save.v2', jsonEncode(json));
}

Future<void> _setEnergy(MemoryStorage storage, int balance) =>
    _editPlayer(storage, (p) => p['energyBalance'] = balance);

Future<void> _setDormant(MemoryStorage storage) =>
    _editPlayer(storage, (p) => p['engineDormant'] = true);

/// Docks at the nearest planet, leaves a single drop in the tank, and launches
/// a voyage it cannot afford, so the ship runs dry en route.
Future<GameController> _doomed(FakeClock clock, FuelPolicy policy) async {
  final storage = MemoryStorage();
  final c = await _boot(clock, storage: storage);
  final near = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
  expect(await c.launchJourney(near), LaunchResult.success,
      reason: 'precondition: the nearest planet is affordable from a full tank');
  clock.advance(const Duration(hours: 12));
  c.tick();
  await c.acknowledgeArrival();
  await _setEnergy(storage, 1);
  final docked = await _boot(clock, storage: storage);
  final far = docked.planets
      .where((p) => p.id != docked.currentPlanetId)
      .reduce((a, b) => docked.distanceTo(a) > docked.distanceTo(b) ? a : b);
  expect(await docked.launchJourney(far, onEmpty: policy), LaunchResult.success);
  return docked;
}

/// Ignites a cruise on a full tank and runs it to exhaustion: dormant, coasting,
/// with the 100 EN braking reserve still in the tank.
Future<GameController> _exhaustedCruise(FakeClock clock) async {
  final c = await _boot(clock);
  await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.coast);
  clock.advance(const Duration(seconds: 3000));
  c.tick();
  expect(c.isDormant, isTrue, reason: 'precondition: the engine shut down');
  expect(c.isCoasting, isTrue, reason: 'precondition: still drifting');
  return c;
}

void main() {
  group('dormancy', () {
    test('a fresh ship is awake', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      expect(c.isDormant, isFalse);
    });

    test('a cruise that runs dry shuts the engine down', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _exhaustedCruise(clock);
      expect(c.energy, 100, reason: 'the reserve survives the shutdown');
      expect(c.isCoasting, isTrue, reason: 'the ship keeps drifting');
    });

    test('a voyage that runs dry shuts the engine down', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _doomed(clock, FuelPolicy.coast);
      expect(c.isDormant, isFalse, reason: 'precondition: still under way');
      clock.advance(c.fuelExhaustTime(c.activeJourney!).difference(clock()) +
          const Duration(seconds: 1));
      c.tick();
      expect(c.energy, 0);
      expect(c.isDormant, isTrue);
      expect(c.isCoasting, isTrue);
    });

    test('loading a dry save does not invent a dormancy', () async {
      // `init()` deliberately does not sync dormancy. A save written before
      // dormancy existed, with an empty tank, has to keep behaving as it did:
      // the gate refuses on energy, not on a shutdown the player never saw.
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      await _boot(clock, storage: storage);
      await _setEnergy(storage, 0);
      final c = await _boot(clock, storage: storage);
      expect(c.energy, 0);
      expect(c.isDormant, isFalse);
      final far = c.planets
          .where((p) => p.id != c.currentPlanetId)
          .reduce((a, b) => c.distanceTo(a) > c.distanceTo(b) ? a : b);
      expect(await c.launchJourney(far, onEmpty: FuelPolicy.halt),
          LaunchResult.insufficientEnergy);
    });

    test('a dormant ship can still brake — dormancy is not paralysis',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _exhaustedCruise(clock);
      expect(c.canBrake, isTrue);
      await c.stopShip();
      expect(c.hasMomentum, isFalse);
      expect(c.energy, 0, reason: 'the reserve bought the stop');
      expect(c.isDormant, isTrue, reason: 'braking does not restart the engine');
    });
  });

  group('activate', () {
    test('pays the flat fee and brings the engine back online', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _exhaustedCruise(clock);
      expect(c.energy, 100);

      expect(await c.activate(), isTrue);
      expect(c.energy, 95);
      expect(c.isDormant, isFalse);
      expect(c.energyLedger.first.type, EnergyTxType.activation);
      expect(c.energyLedger.first.amount, -5);
    });

    test('is a no-op when the engine is already running', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      expect(await c.activate(), isFalse);
      expect(c.energy, 300);
      expect(c.energyLedger, isEmpty);
    });

    test('refuses when the tank cannot cover the fee', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      await _boot(clock, storage: storage);
      await _setEnergy(storage, 3);
      await _setDormant(storage);
      final c = await _boot(clock, storage: storage);
      expect(c.isDormant, isTrue, reason: 'precondition: shut down');
      expect(await c.activate(), isFalse);
      expect(c.energy, 3, reason: 'a refused activation spends nothing');
      expect(c.energyLedger, isEmpty);
    });

    test('training refills the tank but does not restart the engine', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _exhaustedCruise(clock);
      final session = await c.startCourse('walk');
      await c.completeCourse(session.id, 40);
      expect(c.energy, 140);
      expect(c.isDormant, isTrue, reason: 'only activate() clears it');
      expect(
        await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt),
        LaunchResult.engineDormant,
      );
    });

    test('a wake-up survives a reload', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _boot(clock, storage: storage);
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      clock.advance(const Duration(seconds: 3000));
      c.tick();
      await c.activate();
      final reloaded = await _boot(clock, storage: storage);
      expect(reloaded.isDormant, isFalse);
      expect(reloaded.energy, 95);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/dormancy_test.dart`
Expected: FAIL — `isDormant` is always false, so `_exhaustedCruise`'s precondition fails.

- [ ] **Step 3: Add `_syncDormancy`**

In `starward/lib/state/game_controller.dart`, add after `_settleCruise`:

```dart
  /// The single definition of "the tank is dry": the engine shuts down.
  ///
  /// Called at the end of every settlement, so no rule can spend the last drop
  /// without the shutdown following. Deliberately *not* called from `_addEnergy`:
  /// training refills the tank but does not restart the engine — that is what
  /// [activate] is for, and it is the difference between a setback and a free
  /// recovery.
  void _syncDormancy() {
    if (_player.engineDormant) return;
    if (_player.energyBalance > 0) return;
    _player = _player.copyWith(engineDormant: true);
  }
```

- [ ] **Step 4: Call it from all four settlements**

In `_settleBurn`, add `_syncDormancy();` after the ledger entry (i.e. just before `return burned;`).

In `_settleBraking`, add `_syncDormancy();` at the end of the method.

In `_settleTank`, restructure so the sync runs even when there was nothing to drain:

```dart
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
```

In `_settleCruise`, add `_syncDormancy();` after `_repinLeg(at: now);`.

- [ ] **Step 5: Add `activate`**

Add after `_syncDormancy`:

```dart
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
```

- [ ] **Step 6: Run the whole suite and analyze**

Run: `flutter test`
Expected: PASS, every file. Watch `fuel_out_test.dart` and `braking_test.dart` specifically — see the constraint above.

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add starward/lib/state/game_controller.dart starward/test/dormancy_test.dart
git commit -m "feat(starward): shut the engine down when the tank runs dry, and charge to restart it

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 10: Dormancy blocks the things that need a burn

**Files:**
- Modify: `starward/lib/state/game_controller.dart:27` (`LaunchResult`), `:751` (`launchJourney`), `:798` (`launchToStar`), `igniteCruise`
- Modify: `starward/lib/ui/galaxy3d/galaxy_map_3d_page.dart:180` (`_launchMessage`)
- Modify: `starward/lib/ui/galaxy/planet_details_sheet.dart:457` (`_messageFor`)
- Test: `starward/test/dormancy_test.dart` (append)

**Interfaces:**
- Consumes: `isDormant`.
- Produces: `LaunchResult.engineDormant`.

- [ ] **Step 1: Write the failing test**

Append to `starward/test/dormancy_test.dart`:

```dart
  group('a dormant engine cannot burn', () {
    test('a voyage is refused with its own result, not "not enough energy"',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _exhaustedCruise(clock);
      expect(c.energy, 100, reason: 'precondition: it can afford a short hop');

      final near = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
      expect(await c.launchJourney(near, onEmpty: FuelPolicy.halt),
          LaunchResult.engineDormant,
          reason: 'the tank is not the problem — the engine is');
      expect(c.activeJourney, isNull);
      expect(c.energy, 100, reason: 'a refusal spends nothing');
    });

    test('a star launch is refused the same way', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _exhaustedCruise(clock);
      expect(await c.launchToStar(c.stars.starId[0], onEmpty: FuelPolicy.halt),
          LaunchResult.engineDormant);
    });

    test('ignition is refused too', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _exhaustedCruise(clock);
      // Still coasting, so this is `alreadyTraveling` — brake first to reach the
      // state where the dormant check is the one that answers.
      await c.stopShip();
      expect(c.hasMomentum, isFalse);
      expect(c.isDormant, isTrue);
      expect(
        await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt),
        LaunchResult.engineDormant,
      );
    });

    test('activation clears the block', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _exhaustedCruise(clock);
      await c.stopShip();
      await c.activate();
      expect(
        await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt),
        LaunchResult.success,
      );
    });

    test('the launch gate is checked after dormancy, so the message is right',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _exhaustedCruise(clock);
      // Both conditions hold — dormant *and* unable to afford a long hop. The
      // player needs to be told the one they can act on cheaply.
      final far = c.planets
          .where((p) => p.id != c.currentPlanetId)
          .reduce((a, b) => c.distanceTo(a) > c.distanceTo(b) ? a : b);
      expect(c.energyCostTo(far), greaterThan(c.energy));
      expect(await c.launchJourney(far, onEmpty: FuelPolicy.refuse),
          LaunchResult.engineDormant);
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/dormancy_test.dart`
Expected: FAIL — `The getter 'engineDormant' isn't defined for the type 'LaunchResult'`.

- [ ] **Step 3: Add the result**

In `starward/lib/state/game_controller.dart:27`:

```dart
enum LaunchResult {
  success,
  noSelection,
  insufficientEnergy,

  /// The tank has energy in it, but the engine shut down when it last ran dry
  /// and has not been activated since. A separate result from
  /// [insufficientEnergy] because it is a different problem with a different
  /// answer: training will not help, only activation will.
  engineDormant,

  alreadyTraveling,
  alreadyHere,
}
```

- [ ] **Step 4: Gate the three launch paths**

In `launchJourney`, after the `isTraveling` check and before `voyageFuel` is computed:

```dart
    if (_player.engineDormant) return LaunchResult.engineDormant;
```

In `launchToStar`, in the same position (after its `isTraveling` check, before its fuel quote):

```dart
    if (_player.engineDormant) return LaunchResult.engineDormant;
```

In `igniteCruise`, add the guard that Task 5 left out, immediately after the zero-heading check:

```dart
    if (_player.engineDormant) return LaunchResult.engineDormant;
```

Ordering matters: it must come **before** the fuel gate in each method, so a dormant-and-poor player is told about the engine, which 5 EN fixes, rather than about the tank, which needs a training session.

- [ ] **Step 5: Add the two switch cases**

In `starward/lib/ui/galaxy3d/galaxy_map_3d_page.dart`, in `_launchMessage`:

```dart
      case LaunchResult.engineDormant:
        return '引擎处于休眠状态，请先激活（5 EN）';
```

In `starward/lib/ui/galaxy/planet_details_sheet.dart`, in `_messageFor`:

```dart
      case LaunchResult.engineDormant:
        return '引擎处于休眠状态，请先激活（5 EN）';
```

Both switches are exhaustive over `LaunchResult`, so both will fail to compile until these are added.

- [ ] **Step 6: Run the whole suite and analyze**

Run: `flutter test`
Expected: PASS. `fuel_out_test.dart:166` must still get `insufficientEnergy` from all three policies — that save has no `engineDormant` key, so the new guard is skipped.

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add starward/lib/state/game_controller.dart starward/lib/ui/galaxy3d/galaxy_map_3d_page.dart \
        starward/lib/ui/galaxy/planet_details_sheet.dart starward/test/dormancy_test.dart
git commit -m "feat(starward): refuse to launch on a dormant engine, and say so

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 11: The controller learns to recommend and to be asked for the cockpit

**Files:**
- Modify: `starward/lib/state/game_controller.dart` (new members after `canBrake`)
- Modify: `starward/lib/ui/journey/journey_page.dart:291` (delete `_recommendDestination`)
- Test: `starward/test/cruise_test.dart` (append)

**Interfaces:**
- Consumes: `planets`, `stateOf`, `distanceTo`, `currentPlanetId`.
- Produces: `Planet? GameController.recommendedDestination` (getter); `bool GameController.cockpitRequested` (getter); `void GameController.requestCockpit()`; `void GameController.acknowledgeCockpitRequest()`.

- [ ] **Step 1: Write the failing test**

Append to `starward/test/cruise_test.dart` (add `import 'package:starward/data/models/planet.dart';`):

```dart
  group('recommendedDestination', () {
    test('is never where the ship is, nor anywhere already explored', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final rec = c.recommendedDestination;
      expect(rec, isNotNull);
      expect(rec!.id, isNot(c.currentPlanetId));
      expect(c.stateOf(rec.id), isNot(DiscoveryState.explored));
    });

    test('is the nearest hero world, or the nearest world if there is none',
        () async {
      // A property, not a fixed answer: the universe is generated from a seed,
      // and pinning one planet id would make this test a hostage of the
      // generator rather than of the rule.
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final rec = c.recommendedDestination!;
      final candidates = c.planets
          .where((p) => p.id != c.currentPlanetId)
          .where((p) => c.stateOf(p.id) != DiscoveryState.explored)
          .toList();
      expect(candidates, contains(rec));
      final featured = candidates.where((p) => p.featured).toList();
      final pool = featured.isNotEmpty ? featured : candidates;
      final nearest =
          pool.reduce((a, b) => c.distanceTo(a) <= c.distanceTo(b) ? a : b);
      expect(rec.id, nearest.id);
    });
  });

  group('the cockpit request', () {
    test('is set once, idempotent, and cleared by acknowledging', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      expect(c.cockpitRequested, isFalse);

      var notified = 0;
      c.addListener(() => notified++);
      c.requestCockpit();
      expect(c.cockpitRequested, isTrue);
      expect(notified, 1);
      c.requestCockpit();
      expect(notified, 1, reason: 'an already-set request is not news');

      c.acknowledgeCockpitRequest();
      expect(c.cockpitRequested, isFalse);
      c.acknowledgeCockpitRequest();
      expect(c.cockpitRequested, isFalse, reason: 'idempotent');
    });

    test('is not persisted — it is a hint for one screen transition', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _boot(clock, storage: storage);
      c.requestCockpit();
      final reloaded = await _boot(clock, storage: storage);
      expect(reloaded.cockpitRequested, isFalse);
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/cruise_test.dart`
Expected: FAIL — `The getter 'recommendedDestination' isn't defined for the type 'GameController'`.

- [ ] **Step 3: Add the members**

In `starward/lib/state/game_controller.dart`, add after `canBrake`:

```dart
  /// The planet the voyage screen should suggest as the next destination, or
  /// null when there is nothing worth suggesting.
  ///
  /// Nearest not-yet-explored planet, preferring the hand-authored hero worlds
  /// so the suggestion always leads somewhere with real content to discover.
  /// Lifted out of the voyage screen so the recommendation card and the
  /// cockpit's destination marker cannot disagree about where "the nearest
  /// worthwhile place" is.
  Planet? get recommendedDestination {
    Planet? best;
    var bestDistance = double.infinity;
    for (final p in _nearby) {
      if (p.id == _player.currentPlanetId) continue;
      if (stateOf(p.id) == DiscoveryState.explored) continue;
      final distance = distanceTo(p);
      final isBetter = best == null ||
          (p.featured && !best.featured) ||
          (p.featured == best.featured && distance < bestDistance);
      if (isBetter) {
        best = p;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// True when another screen has asked the star map to open in cockpit mode.
  bool get cockpitRequested => _cockpitRequested;

  /// Asks the star map to open in cockpit mode the next time it is shown.
  ///
  /// Deliberately not persisted: it is a navigation hint for one screen
  /// transition, not part of the save. A player who quits mid-request simply
  /// lands on the star map in its default mode, which is a state they can get
  /// out of with one tap.
  void requestCockpit() {
    if (_cockpitRequested) return;
    _cockpitRequested = true;
    notifyListeners();
  }

  /// Marks the cockpit request as served.
  void acknowledgeCockpitRequest() {
    if (!_cockpitRequested) return;
    _cockpitRequested = false;
    notifyListeners();
  }
```

Add the field next to `_pendingDriftReport`:

```dart
  /// A one-shot hint from the voyage screen, never written to the save.
  bool _cockpitRequested = false;
```

- [ ] **Step 4: Point the voyage screen at the controller**

In `starward/lib/ui/journey/journey_page.dart`, replace line 313:

```dart
    final rec = c.recommendedDestination;
```

and delete the whole private `_recommendDestination` method (lines 290-308). Nothing else in the file uses it.

- [ ] **Step 5: Run the tests and analyze**

Run: `flutter test test/cruise_test.dart test/widget_smoke_test.dart`
Expected: PASS.

Run: `flutter analyze`
Expected: `No issues found!` — in particular no "unused element" for the deleted method.

- [ ] **Step 6: Commit**

```bash
git add starward/lib/state/game_controller.dart starward/lib/ui/journey/journey_page.dart \
        starward/test/cruise_test.dart
git commit -m "feat(starward): move the destination recommendation onto the controller

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 12: The voyage screen offers ignition, and reads a cruise

**Files:**
- Modify: `starward/lib/ui/journey/journey_page.dart` (`_sync` at :99, `_buildStandby` at :310, `_DriftDock` at :663, `_CoastDock` at :716)
- Modify: `starward/lib/ui/shell/home_shell.dart:73`
- Test: `starward/test/cruise_ui_test.dart` (create)

**Interfaces:**
- Consumes: `isCruising`, `cruiseRemaining`, `ship.engine.powerDrawPerSecond`, `requestCockpit`, `ShellScope.go`.
- Produces: `_DriftDock({required controller, required onIgnite})`; `_CoastDock({required controller, required cruising, required onBrake, required onChangeCourse, required onSteer})`.

- [ ] **Step 1: Write the failing test**

Create `starward/test/cruise_ui_test.dart`:

```dart
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/vec3.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/models/journey.dart';
import 'package:starward/data/storage/storage_backend.dart';
import 'package:starward/state/game_controller.dart';
import 'package:starward/ui/game_scope.dart';
import 'package:starward/ui/shell/home_shell.dart';

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

/// Pumps the shell and settles, so the voyage tab's standby state is on screen.
Future<void> _pumpVoyage(WidgetTester tester, GameController c) async {
  await tester.pumpWidget(MaterialApp(
    home: GameScope(controller: c, child: const HomeShell()),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('航行'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a stranded ship is offered a way to light the engine',
      (tester) async {
    final clock = FakeClock(DateTime(2026));
    final c = await _boot(clock, MemoryStorage());
    expect(c.inDeepSpace, isTrue);
    expect(c.hasMomentum, isFalse, reason: 'precondition: parked in deep space');

    await _pumpVoyage(tester, c);
    expect(find.text('点火巡航'), findsOneWidget);
    expect(find.text('深空待命'), findsOneWidget);
  });

  testWidgets('tapping it asks the star map for the cockpit and goes there',
      (tester) async {
    final clock = FakeClock(DateTime(2026));
    final c = await _boot(clock, MemoryStorage());
    await _pumpVoyage(tester, c);

    await tester.tap(find.text('点火巡航'));
    await tester.pumpAndSettle();

    expect(c.cockpitRequested, isTrue);
    expect(find.text('星图 · 座舱视角'), findsOneWidget,
        reason: 'the tap both asks and navigates');
  });

  testWidgets('a cruising ship reads as cruising, not as coasting',
      (tester) async {
    final clock = FakeClock(DateTime(2026));
    final storage = MemoryStorage();
    final c = await _boot(clock, storage);
    await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
    clock.advance(const Duration(seconds: 1500));
    await _pumpVoyage(tester, c);

    expect(find.text('巡航中'), findsOneWidget);
    expect(find.text('滑行中'), findsNothing);
    expect(find.text('已巡航'), findsOneWidget);
    expect(find.text('可维持'), findsOneWidget);
    expect(find.text('修正航向'), findsOneWidget,
        reason: 'a cruise steers rather than stops to turn');
    expect(find.text('0.07 EN/s'), findsOneWidget);
  });

  testWidgets('a coast still reads as a coast', (tester) async {
    final clock = FakeClock(DateTime(2026));
    final storage = MemoryStorage();
    final c = await _boot(clock, storage);
    await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.coast);
    clock.advance(const Duration(seconds: 3000));
    c.tick();
    expect(c.isCoasting, isTrue, reason: 'precondition: out of power');
    await _pumpVoyage(tester, c);

    expect(find.text('滑行中'), findsOneWidget);
    expect(find.text('已滑行'), findsOneWidget);
    expect(find.text('可维持'), findsNothing,
        reason: 'a coast has no burn left to run out of');
    expect(find.text('改变航向'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/cruise_ui_test.dart`
Expected: FAIL — `Expected: exactly one matching candidate, Actual: _TextWidgetFinder:<zero widgets with text "点火巡航">`.

- [ ] **Step 3: Wire the timer and the starfield to `hasMomentum`**

In `journey_page.dart`'s `_sync` (line 99), replace the `needsTimer` line:

```dart
    // A drifting ship has no journey to resolve, but its marker still moves, its
    // readout still ticks, and — while cruising — its burn still has to be
    // resolved when it runs out. So the timer runs for both.
    final needsTimer = status == JourneyStatus.inProgress || c.hasMomentum;
```

In `_buildStandby`, replace the `coasting` local and the starfield:

```dart
    final coasting = c.isCoasting;
    final cruising = c.isCruising;
    final drifting = current == null;
```

```dart
        // A drifting ship keeps the star-stream moving; parked stays calm and
        // static. `scrollSpeed` is a static offset, not a rate
        // (`starfield.dart:164`), so the motion has to come from the
        // ever-growing `_phase` — the same mechanism `_buildFlight` uses below.
        // A constant here freezes the field.
        Positioned.fill(
          child: ValueListenableBuilder<double>(
            valueListenable: _phase,
            builder: (context, phase, _) => StarfieldBackground(
              seed: 7,
              starCount: 150,
              scrollSpeed: (coasting || cruising) ? 0.35 * phase : 0.0,
            ),
          ),
        ),
```

- [ ] **Step 4: Add the cruise copy to the standby headline**

Replace the headline `Text` and the paragraph below it:

```dart
                Text(
                  cruising
                      ? '巡航中'
                      : (coasting
                          ? '滑行中'
                          : (drifting ? '漂浮于深空' : '没有进行中的航行')),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: StarColors.offWhite,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  cruising
                      ? '引擎正在驱动飞船以巡航速度前进，每秒消耗能量。'
                          '在星图 · 座舱模式中可以用准星修正航向。'
                      : (coasting
                          ? '燃料已尽，飞船以巡航速度继续滑行。它不会减速，也不会再消耗能量。'
                          : (drifting
                              ? '你的飞船正静静悬停在星海之中，等待你选择第一个目的地。'
                              : '飞船正在 ${current.name} 停泊待命，等待下一段旅程。')),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: StarColors.muted,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
```

- [ ] **Step 5: Route the three dock branches**

Replace the branch block:

```dart
                if (coasting || cruising)
                  _CoastDock(
                    controller: c,
                    cruising: cruising,
                    onBrake: () => _brakeCoast(c),
                    onChangeCourse: () => _brakeAndChangeCourse(c),
                    onSteer: () => _steerFromCockpit(c),
                  )
                else if (drifting)
                  _DriftDock(
                    controller: c,
                    onIgnite: () => _steerFromCockpit(c),
                  )
                else
                  _CurrentDock(planet: current),
```

Add the helper next to `_changeCourse`:

```dart
  /// Sends the player to the star map's cockpit, asking it to open there.
  ///
  /// The cockpit is the one place a heading is chosen: the reticle *is* the
  /// direction, and both igniting and turning are quoted from it. Putting
  /// direction-picking in two screens would mean two answers to "which way".
  void _steerFromCockpit(GameController c) {
    c.requestCockpit();
    ShellScope.go(context, 0);
  }
```

And the `_TopBar` subtitle at line 401:

```dart
          child: _TopBar(
              energy: c.energy,
              subtitle: cruising
                  ? '巡航中'
                  : (coasting ? '滑行中' : (drifting ? '深空待命' : '待命'))),
```

- [ ] **Step 6: Give `_DriftDock` its button**

Replace `_DriftDock`'s constructor and `build`:

```dart
class _DriftDock extends StatelessWidget {
  const _DriftDock({required this.controller, required this.onIgnite});

  final GameController controller;
  final VoidCallback onIgnite;

  @override
  Widget build(BuildContext context) {
    final p = controller.deepSpaceOrigin3D;
    final coord = p == null
        ? '—'
        : 'X ${p.x.toStringAsFixed(1)}  Y ${p.y.toStringAsFixed(1)}  Z ${p.z.toStringAsFixed(1)} ly';
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
                child: const Icon(Icons.my_location_rounded,
                    color: StarColors.cyan, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('当前坐标 · 深空',
                        style: TextStyle(color: StarColors.faint, fontSize: 11)),
                    const SizedBox(height: 3),
                    Text(
                      coord,
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
          _ActionButton(
            label: '点火巡航',
            icon: Icons.rocket_launch_rounded,
            onPressed: onIgnite,
          ),
          const SizedBox(height: 10),
          const Text(
            '自由巡航没有目的地：点火后飞船以巡航速度沿准星方向前进，每秒耗电。'
            '方向在星图 · 座舱模式中用准星选定。',
            style: TextStyle(color: StarColors.faint, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 7: Teach `_CoastDock` about cruising**

Replace `_CoastDock`'s constructor and field list:

```dart
class _CoastDock extends StatelessWidget {
  const _CoastDock({
    required this.controller,
    required this.cruising,
    required this.onBrake,
    required this.onChangeCourse,
    required this.onSteer,
  });

  final GameController controller;

  /// True while the engine is driving the drift. Same readout, different labels
  /// and a different second button: a cruise changes course, a coast changes it
  /// by stopping first.
  final bool cruising;

  final VoidCallback onBrake;
  final VoidCallback onChangeCourse;
  final VoidCallback onSteer;
```

In `build`, replace the header text, the stat rows and the button row:

```dart
                    Text(cruising ? '巡航中 · 巡航速度' : '滑行中 · 巡航速度',
                        style:
                            TextStyle(color: StarColors.faint, fontSize: 11)),
```

```dart
          _CoastStat(
              label: cruising ? '已巡航' : '已滑行', value: duration),
          _CoastStat(
              label: cruising ? '本段距离' : '累计距离',
              value: '${controller.driftDistanceLy.toStringAsFixed(1)} ly'),
          _CoastStat(
              label: '途经恒星系',
              value: '${controller.passedSystemsSoFar.count}'),
          _CoastStat(
              label: '当前坐标',
              value:
                  'X ${p.x.toStringAsFixed(1)}  Y ${p.y.toStringAsFixed(1)}  Z ${p.z.toStringAsFixed(1)}'),
          if (cruising) ...<Widget>[
            _CoastStat(
              label: '耗电',
              value:
                  '${controller.ship.engine.powerDrawPerSecond.toStringAsFixed(2)} EN/s',
            ),
            _CoastStat(
              label: '可维持',
              value: _formatDriftDuration(controller.cruiseRemaining),
            ),
          ],
          _CoastStat(
            label: '制动需要',
            value: '$braking EN（现有 ${controller.energy} EN）',
            valueColor: canBrake ? null : StarColors.danger,
          ),
```

```dart
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
                  label: cruising ? '修正航向' : '改变航向',
                  icon: Icons.alt_route_rounded,
                  filled: false,
                  // Steering a cruise does not stop it — that is the entire
                  // point of the feature — so this is deliberately not gated on
                  // `canBrake`, which is about a burn the ship is not making.
                  onPressed:
                      cruising ? onSteer : (canBrake ? onChangeCourse : null),
                ),
              ),
            ],
          ),
```

- [ ] **Step 8: Extend the tab badge**

In `starward/lib/ui/shell/home_shell.dart`, replace lines 70-74:

```dart
    // A drifting ship has no active journey, but it is still moving — coasting
    // or under power — and the player still has something waiting on the voyage
    // tab. So the badge has to cover all three, or switching to training hides
    // the drift entirely.
    final hasJourney =
        controller.activeJourney != null || controller.hasMomentum;
```

- [ ] **Step 9: Run the tests and analyze**

Run: `flutter test test/cruise_ui_test.dart test/widget_smoke_test.dart`
Expected: PASS. If the cockpit assertion in the second test fails, Task 14 has not been done yet — check that `'星图 · 座舱视角'` is the label `_SideControls` shows in cockpit mode (`galaxy_map_3d_page.dart`), and if the mode change is not wired until Task 14, mark that one assertion `skip` with a comment pointing at Task 14 and re-enable it there.

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 10: Commit**

```bash
git add starward/lib/ui/journey/journey_page.dart starward/lib/ui/shell/home_shell.dart \
        starward/test/cruise_ui_test.dart
git commit -m "feat(starward): offer ignition from the voyage screen and read a live cruise

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Phase 4 — 座舱改向

The cockpit is where a heading is chosen. The reticle at the centre of the screen *is* `camera.forward`; the heading bar quotes `camera.forward`; ignition flies along `camera.forward`. Everything in this phase exists to keep those three in agreement.

---

### Task 13: Turning a moving ship

**Files:**
- Modify: `starward/lib/state/game_controller.dart` (new members after `igniteCruise`)
- Test: `starward/test/heading_test.dart` (create)

**Interfaces:**
- Consumes: `Engine.turnCostFor`, `EnergyTxType.turn`, `_settleCruise`, `_repinLeg`, `isDormant`, `hasMomentum`.
- Produces: `double GameController.turnAngleTo(Vec3)`; `int GameController.turnCostTo(Vec3)`; `Future<bool> GameController.correctHeading(Vec3)`.

- [ ] **Step 1: Write the failing test**

Create `starward/test/heading_test.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/vec3.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/models/energy_transaction.dart';
import 'package:starward/data/models/engine.dart';
import 'package:starward/data/models/journey.dart';
import 'package:starward/data/storage/storage_backend.dart';
import 'package:starward/state/game_controller.dart';

class FakeClock {
  FakeClock(this._now);
  DateTime _now;
  DateTime call() => _now;
  void advance(Duration d) => _now = _now.add(d);
}

Future<GameController> _boot(FakeClock clock) async {
  final c = GameController(
    repository: GameRepository(MemoryStorage()),
    clock: clock.call,
    random: math.Random(3),
  );
  await c.init();
  return c;
}

/// Ignites east and burns for [seconds], so the ship is mid-cruise with a
/// settled, known energy balance.
///
/// `FuelPolicy.coast` throughout: the policy is only consulted when the tank
/// runs dry, and a cruise test that reaches that point wants the ship still
/// drifting so it has a course left to correct.
Future<GameController> _cruising(FakeClock clock, int seconds) async {
  final c = await _boot(clock);
  await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.coast);
  clock.advance(Duration(seconds: seconds));
  return c;
}

void main() {
  group('the turn price', () {
    test('is zero for the heading the ship is already on', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _cruising(clock, 1500);
      expect(c.turnAngleTo(const Vec3(1, 0, 0)), closeTo(0, 1e-9));
      expect(c.turnCostTo(const Vec3(1, 0, 0)), 0);
    });

    test('is the pinned price for the pinned angles', () async {
      // `turnCostFor` is `energyCostFor(brakingDistanceLy · Δv / cruiseSpeed)`
      // where `Δv = 2 · v · sin(θ/2)`. With the standard engine
      // (2.5 EN/ly, v = 1/37.5, braking 40 ly) that gives exactly these:
      final clock = FakeClock(DateTime(2026));
      final c = await _cruising(clock, 1500);
      final cases = <double, int>{
        5: 9,
        10: 17,
        30: 52,
        60: 100,
        90: 141,
        120: 173,
        180: 200,
      };
      cases.forEach((degrees, cost) {
        // A heading rotated `degrees` off +X in the XY plane.
        final rad = degrees * math.pi / 180;
        final heading = Vec3(math.cos(rad), math.sin(rad), 0);
        expect(c.turnAngleTo(heading), closeTo(rad, 1e-9),
            reason: '$degrees° off the bow');
        expect(c.turnCostTo(heading), cost, reason: '$degrees°');
      });
    });

    test('a hairpin is twice the price of a full stop', () async {
      // Not a bug and not fixable by pricing — it is the Δv the turn really
      // costs. The UI's job is to say so; see Task 16's brake hint.
      final clock = FakeClock(DateTime(2026));
      final c = await _cruising(clock, 1500);
      expect(c.turnCostTo(const Vec3(-1, 0, 0)), 200);
      expect(c.brakingCost, 100);
    });

    test('the crossover is at 60°, where turning costs the same as stopping',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _cruising(clock, 1500);
      final engine = c.ship.engine;
      final braking = engine.brakingCostFor(engine.cruiseSpeedLyPerSec);
      expect(engine.turnCostFor(59.9 * math.pi / 180), lessThan(braking));
      expect(engine.turnCostFor(60 * math.pi / 180), braking);
      expect(engine.turnCostFor(60.1 * math.pi / 180), greaterThan(braking));
    });

    test('is zero when the ship is not moving — there is no course to be off',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      expect(c.turnAngleTo(const Vec3(0, 0, 1)), 0);
      expect(c.turnCostTo(const Vec3(0, 0, 1)), 0);
    });
  });

  group('correctHeading', () {
    test('bills the burn and the turn, in that order, and re-aims the ship',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _cruising(clock, 1500);
      expect(c.energy, 200, reason: '300 − 1500 s of burn (100 EN)');

      expect(await c.correctHeading(const Vec3(0, 0, 1)), isTrue);

      // 200 − 141 (a 90° turn) = 59.
      expect(c.energy, 59);
      // Newest first: the turn, then the burn that preceded it.
      expect(c.energyLedger.first.type, EnergyTxType.turn);
      expect(c.energyLedger.first.amount, -141);
      expect(c.energyLedger[1].type, EnergyTxType.cruiseCost);
      expect(c.energyLedger[1].amount, -100);

      // The ship now moves along the new heading at the same speed.
      final v = c.driftVelocity;
      expect(v.x, closeTo(0, 1e-9));
      expect(v.z, closeTo(Engine.standard.cruiseSpeedLyPerSec, 1e-12));
    });

    test('does not teleport the ship — the anchor is re-pinned at the turn',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _cruising(clock, 1500);
      // 1500 s at 1/37.5 ly/s = 40 ly east.
      expect(c.playerPosition3D.x, closeTo(40, 1e-6));
      expect(c.playerPosition3D.z, closeTo(0, 1e-9));

      await c.correctHeading(const Vec3(0, 0, 1));
      expect(c.playerPosition3D.x, closeTo(40, 1e-6),
          reason: 'the turn happens where the ship is, not where it started');
      expect(c.playerPosition3D.z, closeTo(0, 1e-9));

      clock.advance(const Duration(seconds: 375)); // 10 ly
      expect(c.playerPosition3D.x, closeTo(40, 1e-6));
      expect(c.playerPosition3D.z, closeTo(10, 1e-6));
    });

    test('a zero-angle correction is free but still settles the burn',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _cruising(clock, 1500);
      expect(await c.correctHeading(const Vec3(1, 0, 0)), isTrue);
      expect(c.energy, 200, reason: 'nothing turned, but the burn is now booked');
      expect(c.energyLedger.length, 1);
      expect(c.energyLedger.first.type, EnergyTxType.cruiseCost);
    });

    test('refuses when the live balance cannot cover the turn', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _cruising(clock, 2400); // 300 − 160 = 140 EN left
      expect(c.energy, 140);
      expect(c.turnCostTo(const Vec3(-1, 0, 0)), 200);

      expect(await c.correctHeading(const Vec3(-1, 0, 0)), isFalse);
      expect(c.energy, 140, reason: 'a refusal spends nothing');
      expect(c.energyLedger, isEmpty, reason: 'and books nothing');
      expect(c.driftVelocity.x, closeTo(1 / 37.5, 1e-12),
          reason: 'the ship is still on the old heading');
    });

    test('refuses while the engine is dormant', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _cruising(clock, 1500);
      // Run it dry: budget = 300 − 100 reserve = 200 EN = 3000 s.
      clock.advance(const Duration(seconds: 1500));
      c.tick();
      expect(c.isDormant, isTrue, reason: 'precondition: shut down');
      expect(c.isCoasting, isTrue);
      expect(c.energy, 100);

      expect(await c.correctHeading(const Vec3(0, 0, 1)), isFalse);
      expect(c.energy, 100);
    });

    test('refuses when the ship is parked', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      expect(await c.correctHeading(const Vec3(0, 0, 1)), isFalse);
    });

    test('turning a coast re-lights the engine, and it burns again from there',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _cruising(clock, 3000);
      c.tick();
      expect(c.isCoasting, isTrue, reason: 'precondition: out of power');
      expect(c.energy, 100, reason: 'the braking reserve is still aboard');

      expect(await c.activate(), isTrue);
      expect(c.energy, 95);

      // 30° off the bow is 52 EN, which 95 EN covers. A 90° turn (141 EN) would
      // be *refused* — after activation the ship holds only the 100 EN reserve,
      // which is the trap 已知取舍 #2 describes. Worth knowing before writing a
      // test that expects a big turn here to succeed.
      final heading = Vec3(math.cos(math.pi / 6), math.sin(math.pi / 6), 0);
      expect(c.turnCostTo(heading), 52);
      expect(await c.correctHeading(heading), isTrue);
      expect(c.energy, 43);
      expect(c.isCruising, isTrue, reason: 'the engine is driving again');
      expect(c.energyLedger.first.type, EnergyTxType.turn);
      expect(c.energyLedger.first.amount, -52);
    });

    test('a correction survives a reload', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = GameController(
        repository: GameRepository(storage),
        clock: clock.call,
        random: math.Random(3),
      );
      await c.init();
      await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
      clock.advance(const Duration(seconds: 1500));
      await c.correctHeading(const Vec3(0, 0, 1));

      final reloaded = GameController(
        repository: GameRepository(storage),
        clock: clock.call,
        random: math.Random(3),
      );
      await reloaded.init();
      expect(reloaded.energy, 59);
      expect(reloaded.driftVelocity.z, closeTo(1 / 37.5, 1e-12));
      expect(reloaded.isCruising, isTrue,
          reason: 'a powered drift survives the reload as a powered drift');
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/heading_test.dart`
Expected: FAIL — `The method 'turnAngleTo' isn't defined for the type 'GameController'`.

- [ ] **Step 3: Add the three members**

In `starward/lib/state/game_controller.dart`, add after `igniteCruise`:

```dart
  /// The angle between the ship's current course and [heading], in radians.
  ///
  /// Zero when the ship is not moving: a parked ship has no course to be off,
  /// which is what makes `turnCostTo` read 0 rather than quoting a turn that
  /// would in fact be an ignition.
  double turnAngleTo(Vec3 heading) {
    if (!hasMomentum) return 0;
    final to = heading.normalized;
    if (to.length <= 0) return 0;
    final from = _player.driftVelocity.normalized;
    return math.acos(from.dot(to).clamp(-1.0, 1.0));
  }

  /// What it would cost to swing the ship onto [heading] without stopping.
  int turnCostTo(Vec3 heading) =>
      _ship.engine.turnCostFor(turnAngleTo(heading));

  /// Swings the ship onto [heading] without stopping, for a fee priced by the
  /// angle turned. Returns false when the manoeuvre is not available: no course
  /// to correct, a dormant engine, or a tank that cannot cover the fee.
  ///
  /// The fee is charged *after* the burn is settled, and the guard reads the
  /// live [energy] — which already has the burn subtracted. Checking against
  /// `_player.energyBalance` instead would quote the player a budget they spent
  /// an hour ago.
  Future<bool> correctHeading(Vec3 heading) async {
    if (!hasMomentum) return false;
    if (isDormant) return false;
    final direction = heading.normalized;
    if (direction.length <= 0) return false;

    final cost = _ship.engine.turnCostFor(turnAngleTo(direction));
    if (energy < cost) return false;

    _settleCruise();
    _player = _player.copyWith(
      energyBalance: _player.energyBalance - cost,
      // Same speed, new direction — a turn is a rotation of the velocity, not a
      // re-launch. The engine is now running, so the burn resumes.
      driftVelocity: direction * _player.driftVelocity.length,
      driftPowered: true,
    );
    if (cost > 0) {
      _energyLedger.add(EnergyTransaction(
        id: _newId('en'),
        type: EnergyTxType.turn,
        amount: -cost,
        createdAt: _now(),
      ));
    }
    // Required even though `_settleCruise` just re-pinned: it returns early
    // when the ship is *coasting*, leaving the anchor at the original ignition.
    // Rotating the velocity under a stale anchor would teleport the ship to
    // where it would be if it had always flown the new heading.
    _repinLeg(at: _now());
    await _persist();
    notifyListeners();
    return true;
  }
```

- [ ] **Step 4: Run the test and analyze**

Run: `flutter test test/heading_test.dart`
Expected: PASS, all ten.

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add starward/lib/state/game_controller.dart starward/test/heading_test.dart
git commit -m "feat(starward): let a moving ship change course for the price of the turn

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 14: The cockpit can be asked for, and can be aimed exactly

**Files:**
- Modify: `starward/lib/ui/galaxy3d/camera3d.dart` (new `aimCameraAt` after `placeCameraForRoute`)
- Modify: `starward/lib/ui/galaxy3d/galaxy_map_3d_page.dart` (`_aimCockpitAtOrigin` at :298, `_recenter` at :305, `_onScaleUpdate` at :113, `_setMode` at :283, `_SideControls` at :494, `build` at :417)
- Test: `starward/test/camera_aim_test.dart` (create)

**Interfaces:**
- Consumes: `Camera3D.forward`, `Camera3D.clampPitch`, `GameController.cockpitRequested`, `acknowledgeCockpitRequest`.
- Produces: `void aimCameraAt(Camera3D camera, Vec3 direction)` (top-level, in `camera3d.dart`); `_GalaxyMap3DPageState._maybeEnterRequestedCockpit(Size2 vp)`.

- [ ] **Step 1: Write the failing test**

Create `starward/test/camera_aim_test.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/vec3.dart';
import 'package:starward/ui/galaxy3d/camera3d.dart';

void main() {
  group('aimCameraAt', () {
    test('is the exact inverse of Camera3D.forward', () {
      // The reticle is drawn at the centre of the screen, the heading bar quotes
      // `forward`, and ignition flies along `forward`. If aiming and reading are
      // not exact inverses, those three disagree about where the ship points.
      final directions = <Vec3>[
        const Vec3(1, 0, 0),
        const Vec3(-1, 0, 0),
        const Vec3(0, 0, 1),
        const Vec3(0, 0, -1),
        const Vec3(0.3, 0.5, -0.8),
        const Vec3(-0.2, -0.7, 0.4),
        const Vec3(1, 0.001, 1),
      ];
      for (final d in directions) {
        final camera = Camera3D();
        aimCameraAt(camera, d);
        final want = d.normalized;
        final got = camera.forward.normalized;
        expect(got.x, closeTo(want.x, 1e-9), reason: '$d');
        expect(got.y, closeTo(want.y, 1e-9), reason: '$d');
        expect(got.z, closeTo(want.z, 1e-9), reason: '$d');
      }
    });

    test('clamps a straight-up aim rather than flipping over the pole', () {
      final camera = Camera3D();
      aimCameraAt(camera, const Vec3(0, 1, 0));
      expect(camera.pitch, lessThan(math.pi / 2));
      expect(camera.forward.y, greaterThan(0.99),
          reason: 'clamped, but still pointing essentially straight up');
    });

    test('leaves the eye and the mode alone', () {
      final camera = Camera3D()
        ..mode = CameraMode.cockpit
        ..eyeOverride = const Vec3(5, 6, 7);
      aimCameraAt(camera, const Vec3(0, 0, 1));
      expect(camera.mode, CameraMode.cockpit);
      expect(camera.eyeOverride, const Vec3(5, 6, 7));
    });

    test('a zero vector is ignored rather than producing NaN', () {
      final camera = Camera3D()..yaw = 1.2;
      aimCameraAt(camera, const Vec3(0, 0, 0));
      expect(camera.yaw, 1.2, reason: 'unchanged');
      expect(camera.forward.length, closeTo(1, 1e-9));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/camera_aim_test.dart`
Expected: FAIL — `Undefined name 'aimCameraAt'`.

- [ ] **Step 3: Add `aimCameraAt`**

In `starward/lib/ui/galaxy3d/camera3d.dart`, add after `placeCameraForRoute`:

```dart
/// Points [camera] along [direction], exactly.
///
/// The exact inverse of [Camera3D.forward]: `yaw = atan2(x, z)`,
/// `pitch = asin(y)`. That exactness is the point — the cockpit's reticle is
/// drawn at the centre of the screen, the heading bar quotes `forward`, and
/// ignition flies along `forward`, so an approximate aim would make the three
/// disagree about where the ship is pointing.
///
/// Pitch is still clamped, so aiming at a pole stops just short of it rather
/// than flipping the camera over. A zero [direction] is ignored: there is no
/// heading in it, and normalising would produce NaN.
void aimCameraAt(Camera3D camera, Vec3 direction) {
  final d = direction.normalized;
  if (d.length <= 0) return;
  camera.yaw = math.atan2(d.x, d.z);
  camera.pitch = math.asin(d.y.clamp(-1.0, 1.0));
  camera.clampPitch();
}
```

- [ ] **Step 4: Replace the page's aim helper**

In `galaxy_map_3d_page.dart`, replace `_aimCockpitAtOrigin` (lines 298-303):

```dart
  /// Points the cockpit at the galactic centre. A decorative default, not an
  /// exact aim: the `* 0.6` flattens the tilt so the view lands on the
  /// starfield rather than on the empty middle of the shell. Deliberately
  /// different from `aimCameraAt`, which is the exact form the reticle needs.
  void _aimCockpitAtOrigin() {
    final dir = (const Vec3(0, 0, 0) - _shipPos).normalized;
    _camera.yaw = math.atan2(dir.x, dir.z);
    _camera.pitch = math.asin(dir.y.clamp(-1.0, 1.0)) * 0.6;
    _camera.clampPitch();
  }
```

- [ ] **Step 5: Make the recenter button do something in cockpit mode**

In `_SideControls`, make the fourth button mode-dependent:

```dart
              _RoundButton(
                icon: Icons.my_location_rounded,
                // `placeCamera` only sets `eyeOverride` in cockpit mode, so
                // "居中" there would re-place the eye exactly where it already
                // is — a button that visibly does nothing. Re-aiming at the
                // galactic centre is the useful version of "put me back on a
                // known reference", so the button changes meaning with the mode.
                label: mode == CameraMode.cockpit ? '对准银心' : '居中',
                onTap: onRecenter,
              ),
```

And in `build`, pass the mode-appropriate callback:

```dart
                  _SideControls(
                    mode: _camera.mode,
                    onSelect: (m) => _setMode(m, vp),
                    onRecenter: () => _recenter(vp),
                  ),
```

`_recenter` becomes:

```dart
  void _recenter(Size2 vp) {
    setState(() {
      if (_camera.mode == CameraMode.cockpit) {
        // The eye is pinned to the ship in this mode, so there is nothing to
        // re-place. What the button means here is "point me somewhere known".
        _aimCockpitAtOrigin();
        return;
      }
      placeCamera(
        _camera,
        mode: _camera.mode,
        shipPosition: _shipPos,
        overviewDistance: _overviewDefaultDistance(vp),
      );
    });
  }
```

- [ ] **Step 6: Scale look sensitivity with the field of view**

In `_onScaleUpdate` (line 117), replace the constant:

```dart
      // Drag-to-look is a *screen* gesture, so it has to be scaled by how much
      // of the world a screen pixel covers. At the default 60° FOV the factor
      // is 1 and the feel is unchanged; zoomed in to 30° the same drag turns
      // half as far, which keeps a star that was under the finger under the
      // finger. Only the cockpit changes FOV (`_initCamera` sets 60 and the
      // pinch clamp is 30–95), so the other two modes always get `k = 0.006`.
      final k = 0.006 * (_camera.fovDegrees / 60);
```

- [ ] **Step 7: Honour a cockpit request**

Add the field and the handler:

```dart
  /// Guards the post-frame callback that serves a `requestCockpit()`, so a
  /// rebuild loop cannot queue more than one.
  bool _cockpitRequestScheduled = false;

  /// Enters cockpit mode when the voyage screen has asked for it.
  ///
  /// Called from inside the `LayoutBuilder`, which is the only place `vp`
  /// exists — `_setMode` needs it for the overview distance. The actual work is
  /// deferred to a post-frame callback because it calls `setState` *and*
  /// `acknowledgeCockpitRequest`, which notifies listeners; doing either during
  /// a build is an error.
  void _maybeEnterRequestedCockpit(Size2 vp) {
    if (!_c.cockpitRequested) return;
    if (_camera.mode == CameraMode.cockpit) {
      _c.acknowledgeCockpitRequest();
      return;
    }
    if (_cockpitRequestScheduled) return;
    _cockpitRequestScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cockpitRequestScheduled = false;
      if (!mounted) return;
      _setMode(CameraMode.cockpit, vp);
      _c.acknowledgeCockpitRequest();
    });
  }
```

Call it from inside the `LayoutBuilder`, immediately after `final vp = Size2(...)`:

```dart
              final vp = Size2(size.width, size.height);
              _maybeEnterRequestedCockpit(vp);
```

- [ ] **Step 8: Run the tests and analyze**

Run: `flutter test test/camera_aim_test.dart test/cruise_ui_test.dart`
Expected: PASS. `cruise_ui_test.dart`'s "tapping it asks the star map for the cockpit" now passes for real — remove any `skip` you added in Task 12 Step 9.

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 9: Commit**

```bash
git add starward/lib/ui/galaxy3d/camera3d.dart starward/lib/ui/galaxy3d/galaxy_map_3d_page.dart \
        starward/test/camera_aim_test.dart
git commit -m "feat(starward): open the star map in the cockpit on request, and aim it exactly

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 15: The cockpit HUD's pure parts

**Files:**
- Create: `starward/lib/ui/galaxy3d/cockpit_hud.dart`
- Test: `starward/test/cockpit_hud_test.dart` (create)

**Interfaces:**
- Consumes: `Camera3D.project`, `Camera3D.eye`, `Projected.visible`, `focalFor`, `Size2`, `Vec3`.
- Produces: `({String bearing, String elevation}) headingLabel(Vec3)`; `Offset? hudMarkerPoint({required Camera3D camera, required Vec3 world, required Size2 viewport})`; `class HudMarker`; `class CockpitHudPainter`.

- [ ] **Step 1: Write the failing test**

Create `starward/test/cockpit_hud_test.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/vec3.dart';
import 'package:starward/ui/galaxy3d/camera3d.dart';
import 'package:starward/ui/galaxy3d/cockpit_hud.dart';

/// A camera at the origin looking down +Z, with a 60° field of view.
Camera3D _lookingForward() => Camera3D()
  ..mode = CameraMode.cockpit
  ..eyeOverride = const Vec3(0, 0, 0)
  ..yaw = 0
  ..pitch = 0
  ..fovDegrees = 60;

const Size2 _vp = Size2(400, 800);

void main() {
  group('headingLabel', () {
    test('reads a bearing from +Z toward +X, the same convention as forward',
        () {
      // `Camera3D.forward` is `(cos(p)sin(y), sin(p), cos(p)cos(y))`, so
      // `yaw == atan2(x, z)`. The readout has to use the same convention or a
      // ship aimed at a star reads a bearing the star map would not give it.
      expect(headingLabel(const Vec3(0, 0, 1)).bearing, '0°');
      expect(headingLabel(const Vec3(1, 0, 0)).bearing, '90°');
      expect(headingLabel(const Vec3(0, 0, -1)).bearing, '180°');
      expect(headingLabel(const Vec3(-1, 0, 0)).bearing, '270°');
    });

    test('reads elevation above and below the galactic plane', () {
      expect(headingLabel(const Vec3(0, 0, 1)).elevation, '+0°');
      expect(headingLabel(const Vec3(0, 1, 0)).elevation, '+90°');
      expect(headingLabel(const Vec3(0, -1, 0)).elevation, '−90°');
      // 45° up, and the same 45° below reads with a minus sign, not a second
      // "down" scale.
      expect(headingLabel(const Vec3(0, 1, 1)).elevation, '+45°');
      expect(headingLabel(const Vec3(0, -1, 1)).elevation, '−45°');
    });

    test('does not care how long the vector is', () {
      expect(headingLabel(const Vec3(0, 0, 7)).bearing, '0°');
      expect(headingLabel(const Vec3(0, 7, 0)).elevation, '+90°');
    });

    test('a zero vector reads as no heading rather than as NaN', () {
      expect(headingLabel(const Vec3(0, 0, 0)).bearing, '—');
      expect(headingLabel(const Vec3(0, 0, 0)).elevation, '—');
    });
  });

  group('hudMarkerPoint', () {
    test('puts a point dead ahead in the centre of the screen', () {
      final at = hudMarkerPoint(
          camera: _lookingForward(), world: const Vec3(0, 0, 100), viewport: _vp);
      expect(at, isNotNull);
      expect(at!.dx, closeTo(200, 1e-6));
      expect(at.dy, closeTo(400, 1e-6));
    });

    test('puts a point off to the right of centre, and one above it above', () {
      final right = hudMarkerPoint(
          camera: _lookingForward(), world: const Vec3(10, 0, 100), viewport: _vp);
      final up = hudMarkerPoint(
          camera: _lookingForward(), world: const Vec3(0, 10, 100), viewport: _vp);
      expect(right!.dx, greaterThan(200));
      expect(right.dy, closeTo(400, 1e-6));
      // Screen y grows downward, so "above the camera" is a smaller y.
      expect(up!.dy, lessThan(400));
      expect(up.dx, closeTo(200, 1e-6));
    });

    test('projects through the real perspective divide, not a flat scale', () {
      // At 60° FOV over an 800 px tall viewport, `focal = 400 / tan(30°)`.
      // A point 10 units right at 100 units deep is `focal * 0.1` px right of
      // centre: `400 / tan(30°) * 0.1 = 69.282...`.
      final at = hudMarkerPoint(
          camera: _lookingForward(), world: const Vec3(10, 0, 100), viewport: _vp);
      expect(at!.dx, closeTo(200 + 69.2820323, 1e-4));
    });

    test('drops anything level with or behind the camera', () {
      final camera = _lookingForward();
      // Behind: a marker there would otherwise be mirrored to the wrong side of
      // the screen, which reads as a marker for something in front.
      expect(
          hudMarkerPoint(
              camera: camera, world: const Vec3(0, 0, -100), viewport: _vp),
          isNull);
      // At the eye itself.
      expect(hudMarkerPoint(camera: camera, world: const Vec3(0, 0, 0), viewport: _vp),
          isNull);
      // Exactly on the camera plane, level with the eye's own right vector:
      // the perspective divide has no answer for it, so it is dropped rather
      // than drawn at infinity.
      expect(
          hudMarkerPoint(
              camera: camera, world: const Vec3(50, 0, 0), viewport: _vp),
          isNull);
    });

    test('follows the camera when it turns', () {
      final camera = _lookingForward()..yaw = math.pi / 2; // now looking +X
      final at = hudMarkerPoint(
          camera: camera, world: const Vec3(100, 0, 0), viewport: _vp);
      expect(at!.dx, closeTo(200, 1e-6), reason: 'now dead ahead');
      expect(at.dy, closeTo(400, 1e-6));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/cockpit_hud_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:starward/ui/galaxy3d/cockpit_hud.dart'`.

- [ ] **Step 3: Write the file**

Create `starward/lib/ui/galaxy3d/cockpit_hud.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/vec3.dart';
import 'camera3d.dart';

/// The heading as a compass-style readout: a bearing in the galactic plane and
/// an elevation above it.
///
/// Bearing is measured from +Z toward +X, which is the convention
/// [Camera3D.forward] already uses (`yaw == atan2(x, z)`). Using the same one
/// matters: a ship aimed at a star has to read the bearing the star map would
/// give that star, or the readout is decoration.
///
/// Elevation is signed — `+45°` up, `−45°` down — rather than a second scale
/// measured from a pole, so "which way is up" is never ambiguous. The minus is
/// U+2212, not a hyphen: it lines up with the digits at this size.
({String bearing, String elevation}) headingLabel(Vec3 heading) {
  final d = heading.normalized;
  if (d.length <= 0) return (bearing: '—', elevation: '—');
  var bearing = math.atan2(d.x, d.z) * 180 / math.pi;
  if (bearing < 0) bearing += 360;
  final elevation = math.asin(d.y.clamp(-1.0, 1.0)) * 180 / math.pi;
  final sign = elevation < 0 ? '−' : '+';
  return (
    bearing: '${bearing.toStringAsFixed(0)}°',
    elevation: '$sign${elevation.abs().toStringAsFixed(0)}°',
  );
}

/// Where [world] lands on screen, in logical pixels, or null when it is not in
/// front of the camera.
///
/// Thin wrapper over [Camera3D.project] so the HUD and the scene painter cannot
/// disagree about the projection — there is one convention in this codebase and
/// it lives in `camera3d.dart`. The null case is the whole reason this exists:
/// a point behind the eye would otherwise be mirrored to the wrong side of the
/// screen and read as a marker for something in front.
Offset? hudMarkerPoint({
  required Camera3D camera,
  required Vec3 world,
  required Size2 viewport,
}) {
  final p = camera.project(world, viewport);
  return p.visible ? p.screen : null;
}

/// One thing worth pointing at from the cockpit.
class HudMarker {
  const HudMarker({
    required this.world,
    required this.label,
    required this.color,
  });

  final Vec3 world;
  final String label;
  final Color color;
}

/// Draws a ring and a label for each marker, clamped to the viewport edge when
/// the marker is outside the field of view.
///
/// The clamping is the point. Without it, a destination further away than the
/// ship's sensor range — or simply off to one side — draws nothing at all,
/// which is exactly the defect the free-cruise feature exists to fix. A clamped
/// marker still answers "which way", which is the question the player is asking.
class CockpitHudPainter extends CustomPainter {
  const CockpitHudPainter({required this.camera, required this.markers});

  final Camera3D camera;
  final List<HudMarker> markers;

  @override
  void paint(Canvas canvas, Size size) {
    final vp = Size2(size.width, size.height);
    for (final m in markers) {
      final at = hudMarkerPoint(camera: camera, world: m.world, viewport: vp);
      if (at == null) continue;

      // Keep clear of the frame (`_CockpitPainter` insets its window by 14 and
      // its struts by 48 / 40) and of the heading bar at the bottom.
      final clamped = Offset(
        at.dx.clamp(26.0, size.width - 26.0),
        at.dy.clamp(74.0, size.height - 132.0),
      );
      final offScreen = clamped != at;

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = offScreen ? 1.2 : 1.8
        ..color = m.color.withValues(alpha: offScreen ? 0.45 : 0.85);

      if (offScreen) {
        // A chevron pointing the way, so an off-screen marker reads as a
        // direction rather than as a target sitting at the edge.
        final dir = at - clamped;
        final len = dir.distance;
        if (len > 1e-6) {
          final u = dir / len;
          final tip = clamped + u * 11;
          final left = clamped + Vec3(-u.y, u.x, 0) * 7;
          final right = clamped + Vec3(u.y, -u.x, 0) * 7;
          canvas.drawPath(
            Path()
              ..moveTo(tip.dx, tip.dy)
              ..lineTo(left.dx, left.dy)
              ..lineTo(right.dx, right.dy)
              ..close(),
            paint,
          );
        }
      } else {
        canvas.drawCircle(clamped, 9, paint);
        canvas.drawCircle(clamped, 2, Paint()..color = m.color);
      }

      final text = TextPainter(
        text: TextSpan(
          text: m.label,
          style: TextStyle(
            color: m.color.withValues(alpha: offScreen ? 0.5 : 0.85),
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, clamped + const Offset(14, -6));
    }
  }

  // Always true. `Vec3` has no `==`, and `markers` is rebuilt from live scene
  // positions on every frame, so any equality check here would compare
  // identities and report "unchanged" for a camera that has moved.
  @override
  bool shouldRepaint(CockpitHudPainter oldDelegate) => true;
}
```

- [ ] **Step 4: Run the test and analyze**

Run: `flutter test test/cockpit_hud_test.dart`
Expected: PASS. If `headingLabel(const Vec3(0, 1, 0)).bearing` is asserted anywhere, note that `atan2(0, 0)` is `0` in Dart, so it reads `0°` — the elevation is what disambiguates it.

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add starward/lib/ui/galaxy3d/cockpit_hud.dart starward/test/cockpit_hud_test.dart
git commit -m "feat(starward): add the cockpit HUD's heading readout and marker projection

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 16: The cockpit's heading bar, and the markers it draws

**Files:**
- Modify: `starward/lib/ui/galaxy3d/galaxy_map_3d_page.dart` (`build` at :417, new `_HeadingBar`, new `_hudMarkers`, new `_igniteFromCockpit`/`_correctFromCockpit`/`_brakeFromCockpit`)
- Test: `starward/test/cruise_ui_test.dart` (append)

**Interfaces:**
- Consumes: `CockpitHudPainter`, `HudMarker`, `headingLabel`, `igniteCruise`, `correctHeading`, `turnCostTo`, `brakingCost`, `activate`, `isDormant`, `hasMomentum`, `recommendedDestination`, `_launchMessage`, `_worldScale`.
- Produces: `_HeadingBar({required controller, required camera, required onActivate, required onIgnite, required onCorrect, required onBrake})`.

- [ ] **Step 1: Write the failing test**

Append to `starward/test/cruise_ui_test.dart`:

```dart
  /// The cockpit's heading bar, scoped by key.
  ///
  /// `HomeShell` mounts all four pages in an `IndexedStack`, so the voyage tab's
  /// dock is in the tree at the same time as this bar — and both have a button
  /// labelled 修正航向. An unscoped `find.text` would match both and the test
  /// would pass or fail for the wrong reason.
  final cockpit = find.byKey(const Key('cockpit-heading-bar'));

  /// Text inside the heading bar only.
  Finder inCockpit(String text) =>
      find.descendant(of: cockpit, matching: find.text(text));

  Future<void> _enterCockpit(WidgetTester tester) async {
    await tester.tap(find.text('座舱'));
    await tester.pumpAndSettle();
  }

  Future<void> _pumpStarMap(WidgetTester tester, GameController c) async {
    await tester.pumpWidget(MaterialApp(
      home: GameScope(controller: c, child: const HomeShell()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('星图'));
    await tester.pumpAndSettle();
  }

  testWidgets('the cockpit reads the heading the reticle is pointing at',
      (tester) async {
    final clock = FakeClock(DateTime(2026));
    final c = await _boot(clock, MemoryStorage());
    await _pumpStarMap(tester, c);
    await _enterCockpit(tester);

    expect(cockpit, findsOneWidget);
    // Entering the cockpit aims at the galactic centre, so the readout is
    // whatever that bearing is — the point is that it is a real reading and not
    // a placeholder.
    expect(inCockpit('准星航向'), findsOneWidget);
    expect(inCockpit('—'), findsNothing);
    expect(find.text('对准银心'), findsOneWidget,
        reason: 'the recenter button changes meaning in this mode');
  });

  testWidgets('a parked ship is offered ignition from the cockpit',
      (tester) async {
    final clock = FakeClock(DateTime(2026));
    final c = await _boot(clock, MemoryStorage());
    await _pumpStarMap(tester, c);
    await _enterCockpit(tester);

    expect(inCockpit('点火巡航'), findsOneWidget);
    expect(inCockpit('修正航向'), findsNothing);

    await tester.tap(inCockpit('点火巡航'));
    await tester.pumpAndSettle();
    expect(c.isCruising, isTrue);
    expect(c.hasMomentum, isTrue);
  });

  testWidgets('a cruising ship is quoted the turn and can take it',
      (tester) async {
    final clock = FakeClock(DateTime(2026));
    final c = await _boot(clock, MemoryStorage());
    await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.halt);
    clock.advance(const Duration(seconds: 1500));
    await _pumpStarMap(tester, c);
    await _enterCockpit(tester);

    // Aimed at the origin from (40, 0, 0): a 180° turn, 200 EN — more than the
    // 100 EN a stop costs, so the brake hint must be showing.
    expect(inCockpit('修正航向'), findsOneWidget);
    expect(find.descendant(of: cockpit, matching: find.text('200 EN')),
        findsOneWidget);
    expect(inCockpit('制动停下只需 100 EN'), findsOneWidget);

    await tester.tap(inCockpit('修正航向'));
    await tester.pumpAndSettle();
    expect(c.energy, 0, reason: '300 − 100 burned − 200 turned');
    expect(c.driftVelocity.x, lessThan(0),
        reason: 'now flying the other way');
  });

  testWidgets('a dormant engine is offered activation, not ignition',
      (tester) async {
    final clock = FakeClock(DateTime(2026));
    final c = await _boot(clock, MemoryStorage());
    await c.igniteCruise(const Vec3(1, 0, 0), onEmpty: FuelPolicy.coast);
    clock.advance(const Duration(seconds: 3000));
    c.tick();
    expect(c.isDormant, isTrue, reason: 'precondition');

    await _pumpStarMap(tester, c);
    await _enterCockpit(tester);

    expect(inCockpit('激活引擎'), findsOneWidget);
    expect(inCockpit('修正航向'), findsNothing);

    await tester.tap(inCockpit('激活引擎'));
    await tester.pumpAndSettle();
    expect(c.isDormant, isFalse);
    expect(c.energy, 95);
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/cruise_ui_test.dart`
Expected: FAIL — `zero widgets with text "准星航向"`.

- [ ] **Step 3: Add the page's three cockpit actions**

In `_GalaxyMap3DPageState`, add after `_launchMessage`:

```dart
  /// Lights the engine along whatever the reticle is on.
  ///
  /// `FuelPolicy.coast` rather than `halt`: a free cruise that runs out of power
  /// keeps drifting, which is what the player asked for by choosing a
  /// destination-less cruise. Stopping dead in the dark is a surprise, not a
  /// default.
  Future<void> _igniteFromCockpit() async {
    final result =
        await _c.igniteCruise(_camera.forward, onEmpty: FuelPolicy.coast);
    if (!mounted) return;
    if (result != LaunchResult.success) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_launchMessage(result))));
    }
  }

  Future<void> _correctFromCockpit() async {
    final heading = _camera.forward;
    final cost = _c.turnCostTo(heading);
    final ok = await _c.correctHeading(heading);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? '航向已修正（$cost EN）' : '能量不足，无法修正航向'),
    ));
  }

  Future<void> _brakeFromCockpit() async {
    await _c.stopShip();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已制动停下')));
  }

  /// What the cockpit points at: the recommended destination — always, even
  /// when it is far outside sensor range, which is precisely the case the star
  /// map could not show — plus the galactic centre as a fixed reference.
  List<HudMarker> _hudMarkers(Galaxy3DScene scene) {
    final out = <HudMarker>[];
    final rec = _c.recommendedDestination;
    if (rec != null && scene.planetPositions.containsKey(rec.id)) {
      out.add(HudMarker(
        world: scene.positionOf(rec.id),
        label: rec.name,
        color: StarColors.gold,
      ));
    }
    out.add(const HudMarker(
      world: Vec3(0, 0, 0),
      label: '银心',
      color: StarColors.cyan,
    ));
    return out;
  }
```

Add the import: `import 'cockpit_hud.dart';`.

- [ ] **Step 4: Draw the markers and swap the bottom panel in cockpit mode**

In `build`, replace the `_CockpitOverlay` block (lines 415-420):

```dart
                  // Cockpit framing — a through-the-viewport feel in first
                  // person. Non-interactive so gestures pass through.
                  if (_camera.mode == CameraMode.cockpit) ...<Widget>[
                    const Positioned.fill(
                      child: IgnorePointer(child: _CockpitOverlay()),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: CockpitHudPainter(
                            camera: _camera,
                            markers: _hudMarkers(scene),
                          ),
                        ),
                      ),
                    ),
                  ],
```

Replace the `else` branch (lines 437-442):

```dart
                  else if (_camera.mode == CameraMode.cockpit)
                    _HeadingBar(
                      controller: _c,
                      camera: _camera,
                      onActivate: () => _c.activate(),
                      onIgnite: _igniteFromCockpit,
                      onCorrect: _correctFromCockpit,
                      onBrake: _brakeFromCockpit,
                    )
                  else
                    _BottomControls(
                      sensorRange: _sensorRange,
                      mode: _camera.mode,
                      onSensorChanged: (v) => setState(() => _sensorRange = v),
                    ),
```

- [ ] **Step 5: Write `_HeadingBar`**

Add at the end of `galaxy_map_3d_page.dart`:

```dart
/// The cockpit's bottom panel: where the reticle is pointing, what it would
/// cost to go there, and the one button that does it.
///
/// Replaces the sensor slider in this mode — a sensor range is a property of
/// the star map's detail level, and the cockpit's question is "which way",
/// which the marker overlay answers better.
class _HeadingBar extends StatelessWidget {
  const _HeadingBar({
    required this.controller,
    required this.camera,
    required this.onActivate,
    required this.onIgnite,
    required this.onCorrect,
    required this.onBrake,
  });

  final GameController controller;
  final Camera3D camera;
  final VoidCallback onActivate;
  final VoidCallback onIgnite;
  final VoidCallback onCorrect;
  final VoidCallback onBrake;

  @override
  Widget build(BuildContext context) {
    final heading = camera.forward;
    final label = headingLabel(heading);
    final dormant = controller.isDormant;
    final moving = controller.hasMomentum;
    final turnCost = controller.turnCostTo(heading);
    final braking = controller.brakingCost;
    // A turn past 60° costs more than stopping and re-lighting the engine, and
    // that is the real Δv, not a pricing mistake — but a player who does not
    // know it is being offered the expensive option first. So say the cheap one
    // out loud, and make it tappable.
    final turningIsDearer = moving && !dormant && turnCost > braking;

    return SafeArea(
      // Keyed because `HomeShell` mounts all four pages in an `IndexedStack`,
      // so an unscoped `find.text` in a widget test matches this bar *and* the
      // voyage tab's dock behind it. Every cockpit assertion in
      // `cruise_ui_test.dart` scopes to this key.
      key: const Key('cockpit-heading-bar'),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: StarPanel(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.gps_fixed_rounded,
                        color: StarColors.cyan, size: 16),
                    const SizedBox(width: 8),
                    const Text('准星航向',
                        style: TextStyle(
                            color: StarColors.offWhite,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('${label.bearing}  ${label.elevation}',
                        style: const TextStyle(
                            color: StarColors.gold,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 10),
                if (dormant)
                  _HudButton(
                    label: '激活引擎',
                    detail: '${controller.ship.engine.activationCost} EN',
                    icon: Icons.power_settings_new_rounded,
                    onPressed: onActivate,
                  )
                else if (!moving)
                  _HudButton(
                    label: '点火巡航',
                    detail: '沿准星方向',
                    icon: Icons.rocket_launch_rounded,
                    onPressed: onIgnite,
                  )
                else
                  _HudButton(
                    label: '修正航向',
                    detail: '$turnCost EN',
                    icon: Icons.alt_route_rounded,
                    onPressed: onCorrect,
                  ),
                if (turningIsDearer) ...<Widget>[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: onBrake,
                    behavior: HitTestBehavior.opaque,
                    child: Text('制动停下只需 $braking EN',
                        style: const TextStyle(
                            color: StarColors.cyan,
                            fontSize: 11,
                            decoration: TextDecoration.underline)),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  switch ((dormant, moving)) {
                    (true, _) => '引擎已休眠，飞船仍在滑行。激活后才能再次点火或改向。',
                    (false, false) => '拖动环视 · 准星所指即点火方向 · 双指调整视场',
                    (false, true) => '拖动环视 · 修正航向不减速，按转角收费 · 双指调整视场',
                  },
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: StarColors.faint, fontSize: 10.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A full-width labelled button for the cockpit panel.
class _HudButton extends StatelessWidget {
  const _HudButton({
    required this.label,
    required this.detail,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final String detail;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: panelDecoration(radius: 12, color: StarColors.panelLight),
        child: Row(
          children: <Widget>[
            Icon(icon, color: StarColors.cyan, size: 18),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(
                    color: StarColors.offWhite,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(detail,
                style: const TextStyle(
                    color: StarColors.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Run the whole suite and analyze**

Run: `flutter test`
Expected: PASS, every file.

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Run the app and check it by hand**

Run: `flutter run`

Walk this path, in order — it is the whole feature end to end:
1. Voyage tab → 「点火巡航」 → lands on the star map in cockpit mode.
2. Drag to aim. The 准星航向 bearing changes; the gold marker labelled with a planet name stays clamped to the edge when you look away from it.
3. Tap 「点火巡航」. The ship starts moving; the voyage tab's dock now reads 巡航中, with 耗电 0.07 EN/s and a 可维持 countdown.
4. Return to the star map, cockpit, aim somewhere else, tap 「修正航向」. The energy drops by the quoted amount.
5. Aim 180° away. 「修正航向」 quotes 200 EN and 「制动停下只需 100 EN」 appears under it.
6. Cruise until 可维持 reaches zero. The dock flips to 滑行中, the engine reads 休眠, and the cockpit offers 「激活引擎 5 EN」.
7. Tap it. 95 EN, engine awake, and the ship can ignite again.

- [ ] **Step 8: Commit**

```bash
git add starward/lib/ui/galaxy3d/galaxy_map_3d_page.dart starward/test/cruise_ui_test.dart
git commit -m "feat(starward): give the cockpit a heading bar and off-screen destination markers

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Self-Review

Run against `docs/superpowers/specs/2026-10-14-starward-free-cruise-design.md` after the last task was written.

**Spec coverage.** Every numbered requirement in the spec maps to a task: §3 (states and transitions) → T4/T9; §4 (free cruise) → T5/T6/T8; §5.1 (turn pricing) → T1/T13; §5.2 (the 60° crossover and its UI mitigation) → T13's crossover test and T16's brake hint; §5.3 (the cockpit HUD) → T15/T16; §6 (dormancy) → T9/T10; §7 (activation, and the §7.1 dialog wording) → T9; §8 (controller API) → T5–T13; §9 (readouts) → T12; §10 (test matrix) → the per-task test files, with `test/dormancy_test.dart` added beyond the spec's list because dormancy turned out to be its own concern; §11 (staging) → the four phases.

**Placeholder scan.** No "TBD", no "handle edge cases", no "similar to Task N". Every code step carries the code. Every test step carries the assertions. Two spots name a decision rather than a value and are deliberate: Task 12 Step 9's conditional `skip` (resolved in Task 14) and Task 16 Step 7's manual walkthrough (a human check, not a machine one).

**Type consistency.** Checked the names that cross task boundaries: `activationCost` (T1 → T9/T10/T16); `powerDrawPerSecond`/`burnForSeconds`/`secondsForEnergy`/`turnCostFor` (T1 → T6/T8/T13); `EnergyTxType.cruiseCost`/`turn`/`activation` (T2 → T6/T9/T13); `PlayerState.driftPowered`/`engineDormant`/`cruisePolicy` (T3 → T5/T7/T9); `hasMomentum`/`isCoasting`/`isCruising`/`isDormant`/`brakingCost`/`canBrake` (T4 → T7/T9/T12/T13/T16); `_repinLeg` (T5 → T7/T13); `_settleCruise` (T7 → T8/T13); `_syncDormancy` (T9 → T7's four call sites, added in the same task); `LaunchResult.engineDormant` (T10 → the two switches); `recommendedDestination`/`cockpitRequested`/`requestCockpit`/`acknowledgeCockpitRequest` (T11 → T12/T14/T16); `aimCameraAt` (T14); `headingLabel`/`hudMarkerPoint`/`HudMarker`/`CockpitHudPainter` (T15 → T16).

Three ordering constraints that a fresh executor could get wrong, all called out where they bite: `_settleCruise` before `_anchorHere`'s `brakingCost` read (T7), `_repinLeg` after `correctHeading`'s velocity change (T13), and the `engineDormant` guard before the fuel gate in all three launch paths (T10).

## 已知取舍

1. **Ignition is free, so a turn past 60° is dearer than stopping and re-igniting.** 200 EN against 100 + 0. The user rejected charging for ignition, and the spec documents the crossover in §5.2 rather than hiding it. The mitigation is the tappable brake hint (T16), which tells the truth instead of steering around it. If the economy later wants a fix, the honest one is a `turnCostFor` discount above 60° — not a hidden ignition fee.

2. **A turn made on the last of the tank is a trap.** Activation costs 5 EN, a turn costs at least 9; a player who spends down to the 100 EN reserve and then turns can end up dormant again on the next tick, having bought a heading and nothing else. The model is self-consistent — the engine really cannot be sustained — and the HUD shows both the turn price and the 可维持 countdown, so the trap is visible before it is entered. Left as-is; the alternative (refusing a turn the ship cannot sustain) takes a decision away from the player.

3. **The drift report after an exhaustion is written from the exhaustion point, not from `now`.** A player who returns a day later gets a report covering the 80 ly they actually flew, not 23 hours of imagined burn. This is spec test 14's pinned number and it is the difference between a log and a lie.

4. **`init()` deliberately does not sync dormancy.** Documented in T9 with the reason. It is what keeps `fuel_out_test.dart:166` green, and more importantly it is what keeps a pre-dormancy save behaving the way its owner last saw it.

5. **The cockpit's markers are not interactive.** They say which way; they do not open anything. Tapping a marker to set a destination is a different feature (it would need a real destination-picking flow, not a free cruise) and is out of scope.

6. **`CockpitHudPainter.shouldRepaint` always returns true.** Cheaper than teaching `Vec3` an `==`, and the marker list is rebuilt from live scene positions every frame anyway.

## 与 spec 的偏差汇总

Four deviations, all documented in place at the top of the plan; repeated here so an executor who reads only the closing section still sees them.

| # | Spec says | Plan does | Why |
|---|---|---|---|
| 1 | §5.1 tabulates 0°–360° | `turnCostFor`'s domain is `[0, π]`; the 350°/360° rows are unreachable | `acos(dot)` cannot exceed π. And 360°→0 contradicts `minEnergyCost = 1`: `sin(2π) ≈ -2.45e-16` is negative, so the formula would floor to 1, not 0. 0° is handled by an explicit early return. |
| 2 | §8.4 guards `correctHeading` on the energy balance | It guards on the live `energy` getter, before settling | `_player.energyBalance` is the balance at the last settlement. A ship that has cruised for an hour has spent energy the raw field does not know about. |
| 3 | §8.5 checks exhaustion by comparing burned energy to the budget | It compares time, via `secondsForEnergy` | EN is quantised, so `burnForSeconds(elapsed) >= budget` fires at 2992.5 s instead of 3000 s. The division form is exact: `secondsForEnergy(300) == 4500.0`, `(200) == 3000.0`, `(40) == 600.0`. |
| 4 | §8.6 builds the drift report after settling | `_reconcileCruise` builds it before settling | Settling re-pins the leg, which zeroes the elapsed time the report needs. The report describes the leg that just ended; it has to be read while that leg is still the current one. |

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-10-14-starward-free-cruise.md`.** Two execution options:

**1. Subagent-Driven (recommended)** — a fresh subagent per task, with review between tasks. Sixteen tasks across four phases, each with its own test cycle, is exactly the shape this suits: the phases have hard boundaries (Phase 1 changes no behaviour, Phase 2 adds no UI, Phase 3 adds the entry points, Phase 4 adds the cockpit), so a reviewer can reject one task without blocking its neighbour.

**2. Inline Execution** — execute the tasks in this session, with checkpoints for review. Better if you want to watch the numbers land as they go, since this plan pins a lot of them.

Which approach?




