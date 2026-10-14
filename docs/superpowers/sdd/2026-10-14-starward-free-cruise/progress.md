# SDD ledger — plan: docs/superpowers/plans/2026-10-14-starward-free-cruise.md

Spec: docs/superpowers/specs/2026-10-14-starward-free-cruise-design.md (reachable, committed 66c423b)
Repo: /Users/jooper/Documents/samples/todoapp  Branch: main (human consented explicitly, 2026-10-14)
Plan committed: 64a20ca, amended fddbc63 (T15 unused-import fix)
BASE for Task 1: fddbc63

## Pre-flight conflict scan

Run 2026-10-14 before dispatching Task 1.

### A. Per-task self-consistency (tests specified vs code specified; files created vs files later touched)

| Task | Self-consistent? | Finding |
|---|---|---|
| 1 Engine pricing | yes | The 4 compile-fix sites it names (`ship_test.dart:16`, `drift_report_test.dart:55`, `flight_panel_test.dart:258`, `return_to_origin_test.dart:146`) are **exactly** the 4 non-`Engine.standard` `Engine(...)` constructions in the repo — verified by grep, no site missed. |
| 2 Ledger kinds | yes | — |
| 3 PlayerState fields | yes | — |
| 4 Controller vocabulary | yes, doc gap | `Produces` lists `isDormant`, whose body reads `_player.engineDormant`, but `Consumes` names only `driftPowered`. `engineDormant` is produced by Task 3, which precedes it. Documentation gap only; no ordering risk. |
| 5 Ignition | yes | The brief contains `if (_player.engineDormant) return LaunchResult.engineDormant;` — a forward reference to Task 10's enum member — **and immediately says to omit that one line for now.** Self-aware, not a defect. |
| 6 Cruise burn | yes | — |
| 7 Settling | yes | — |
| 8 Exhaustion | yes | `_reconcileCruise` deliberately does **not** call `_settleCruise` (it sets `driftPowered: false` directly). Verified against Task 7's brief. |
| 9 Dormancy | yes | — |
| 10 LaunchResult gate | yes | — |
| 11 Recommend + cockpit request | yes | — |
| 12 Voyage docks | yes, cross-task test dep | One widget assertion needs Task 14's wiring. Step 9 says so and prescribes a `skip` + re-enable. See C.1. |
| 13 Turning | yes | Three bugs in its own test code were found and fixed during authoring (see "Plan edits made during the scan"). |
| 14 Cockpit request + aim | yes | — |
| 15 HUD pure parts | **no → fixed** | Unused `theme.dart` import. See "Plan edits made during the scan". |
| 16 Heading bar + markers | yes | The `Key('cockpit-heading-bar')` exists only so tests can scope past the `IndexedStack`; justified inline. |

### B. Cross-task rows (every pair sharing a file or an interface)

| Producer → Consumer | Contract | Finding |
|---|---|---|
| 1 → 13 | `Engine.turnCostFor(double)` → `turnCostTo` | clean |
| 1 → 6, 8 | `burnForSeconds` / `secondsForEnergy` | clean |
| 1 → 9 | `Engine.activationCost` → `activate()` | clean |
| 2 → 6, 9, 13 | `EnergyTxType.cruiseCost` / `turn` / `activation` | clean |
| 3 → 4 | `PlayerState.driftPowered`, `engineDormant` | clean (doc gap per A.4) |
| 3 → 5, 7 | `driftPowered`, `cruisePolicy` | clean |
| 5 → 7 | `_repinLeg` → `_anchorHere` | clean |
| 5 → 13 | `_repinLeg` → `correctHeading` | clean; T13's brief carries the "required even though `_settleCruise` re-pinned" note |
| 6 → 7 | `_cruiseBurnNow` → `_settleCruise` | clean |
| 6 → 8 | `cruiseReserve` → `_cruiseExhaustTime` | clean |
| 7 → 8 | `_settleCruise` | clean — T8 does not call it (A.8) |
| 7 → 13 | `_settleCruise` → `correctHeading` | clean |
| 9 → 7 | `_syncDormancy` added to `_settleCruise` (created in 7) | clean, ordered |
| 9 → 10 | `isDormant` → the 3 launch gates | clean |
| 11 → 12, 14, 16 | `requestCockpit` / `cockpitRequested` / `recommendedDestination` | clean |
| 12 ↔ 14 | T12's cockpit widget assertion needs T14's `_maybeEnterRequestedCockpit` | **known, documented** — see C.1 |
| 12 ↔ 16 | Both render a button labelled 修正航向 (`_CoastDock` vs `_HeadingBar`) | **hazard, mitigated** — see C.2 |
| 13 → 16 | `turnCostTo` / `correctHeading` → `_HeadingBar` | clean |
| 14 → 16 | **Both edit `build` in `galaxy_map_3d_page.dart`** | clean — T14 edits the `final vp = …` line, T16 edits the `_CockpitOverlay` block (415-420) and the bottom-panel branch (437-442). Disjoint regions, sequential order. |
| 15 → 16 | `CockpitHudPainter` / `HudMarker` / `headingLabel` | clean |

### C. Plan-mandated things the review rubric may treat as defects

1. **T12 Step 9's conditional `skip`.** A skipped widget assertion is normally a review finding. It is a documented cross-task dependency here, resolved by T14. Ruling below.
2. **T12 ↔ T16 share a button label.** `HomeShell` mounts all four pages in an `IndexedStack`, so the voyage tab's `_CoastDock` and the cockpit's `_HeadingBar` are in the tree at once and both can render 修正航向. T16 keys the bar and scopes its finders through `find.descendant`; T12's voyage assertions are safe because the star map is never in cockpit mode during them. Both reviewers get this context.
3. **T15's `shouldRepaint => true`.** Justified inline (`Vec3` has no `==`; the marker list is rebuilt per frame). Not pre-judged for the reviewer — if it is raised, it will be adjudicated on its merits.

### D. Rulings from the scan

- Ruling: fix T15's unused `theme.dart` import in the plan before execution rather than letting the implementer hit a failing `flutter analyze` on the step that asserts `No issues found!` — the plan's own Step 4 makes the defect self-evident, so this is a transcription error, not a design question. Cost if wrong: none; the import was never referenced.
- Ruling: T12's `skip` stands as written. The alternative (moving T14 before T12) would put cockpit aiming before the voyage screen has any way to reach the cockpit, and T12's other 3 widget tests are independent of it. Cost if wrong: one assertion is dark for one task, re-enabled and verified in T14.
- Ruling: T12↔T16's shared label needs no plan change. T16's key + scoped finders already handle it; the scan records it so both reviewers know the hazard is understood rather than missed. Cost if wrong: a widget test passes for the wrong reason — mitigated because T16's finders are scoped by key.

### Plan edits made during the scan

1. T15 `Consumes:` — dropped `StarColors`; the HUD painter takes every colour from `HudMarker.color` and never reads the palette.
2. T15 `cockpit_hud.dart` — dropped `import '../../core/theme.dart';`. It was unused, which `flutter analyze` reports as `unused_import`; the task's own Step 4 asserts `No issues found!` and could not have passed.

## Progress

### Task 1: The engine learns what a cruise costs

- BASE fddbc63. Dispatched to implementer agent `ac35f4e2bcdd19c54` (sonnet — foundation task: 5 files, a save migration, and the interface every later task consumes).
- Brief: `task-1-brief.md`. Report: `task-1-report.md`.
- Pre-dispatch numeric verification (controller, python3 double arithmetic): all 15 values in the brief's tables reproduce exactly — `powerDrawPerSecond` 0.06666666666666667; `secondsForEnergy(300/200/40/0)` 4500.0/3000.0/600.0/0.0 **exact equality**; `turnCostFor(0/5/10/30/60/90/120/180)` 9/17/52/100/141/173/200. `turnCostFor(0)` is 0 only via the brief's `radians <= 0` early return (the raw formula floors at `minEnergyCost` = 1), so that guard is load-bearing and is called out in the dispatch.
- Also verified `dart:math as math` is already imported in `engine.dart:1`, so the new `turnCostFor` needs no import change.
- Pre-generated briefs for Tasks 2-16 alongside.
- **Reported DONE.** Commit `ae5ed4a` "feat(starward): teach the engine what a cruise, a turn and a restart cost". 6/6 cruise tests, full suite **220/220** (baseline was 214; +6). `flutter analyze` clean. Review package `review-fddbc63..ae5ed4a.diff`; task reviewer dispatched.
- Ruling: accept the implementer's decision **not** to run `dart format` on the changed files. The repo predates the installed Dart 3.13 tall-style formatter, so `dart format --set-exit-if-changed` flags untouched files too — independently reproduced on `player_state.dart` and `discovery_record.dart`, both unmodified and both flagged. Reformatting would bury a 6-line semantic change in a whole-file rewrite. Cost if wrong: the new code is formatted in the older style, consistent with every neighbouring file; a future repo-wide format pass fixes it in one commit.
- **Review verdict: ✅ Spec compliant, quality Approved.** No Critical, no Important. Reviewer independently recomputed all 15 pinned values with IEEE-754 semantics and confirmed the four-`Engine(...)`-sites claim by grep, so the analyze-clean claim is well-supported. Task 1 complete.
- Parked (Minor, non-load-bearing) — reviewer findings, with rulings:
  - Minor: `engine.dart:110`'s guard is `radians <= 0`, so a *negative* angle would be priced 0 — a free left turn — while a positive one is priced. Ruling: **no fix now.** The plan's deviation §1 already pins `turnCostFor`'s domain to `[0, π]`, and the only producer is Task 13's `turnAngleTo`, which returns `math.acos(dot)` ∈ `[0, π]` and therefore can never be negative. `<= 0` catches exactly the 0 case the brief requires. **Carry-forward: the Task 13 dispatch must state that `turnAngleTo`'s non-negativity is what makes this guard safe, and that a signed angle must not be passed.** Cost if wrong: a future signed-angle consumer silently gets free turns.
  - Minor: `engine.dart:101` — `secondsForEnergy` has no `energy < 0` guard. Ruling: **no fix.** Not requested, and its only caller (Task 8's `_cruiseExhaustTime`) passes a non-negative budget. Cost if wrong: a negative duration in an unreachable branch.

- Ruling: **serialize the per-task loop** — do not dispatch Task 2's implementer until Task 1's review verdict lands, even though Task 2 is independent (`Consumes: nothing`, disjoint files). If Task 1's review requires a fix to `engine.dart`, that fix commit lands after Task 2's commit and the scoped re-review's `BASE..HEAD` range would swallow Task 2's unrelated diff. Cost if wrong: a few minutes of pipeline idle per task, against a review package that misrepresents what it covers.
- Task 2 pre-dispatch verification (ready to go, not yet dispatched): `energy_transaction.dart:2` has exactly the four members `travelCost, trainingReward, explorationReward, braking`, so 4+3 = 7 matches the brief's pinned set length at its line 37-38 — the test's "no two kinds may share a name" assertion will hold. `energyTxTypeFromName` already exists (`:4-6`) with `orElse: () => EnergyTxType.travelCost`, so the brief's third test is a guard on existing behaviour, not new code. The brief's Step 3 block replaces lines 1-2 only; `energyTxTypeFromName` and the `EnergyTransaction` class below are untouched.

### Task 2: Three new ledger kinds

- BASE ae5ed4a. Dispatched to implementer agent `ac09d52985038249a` (haiku — pure transcription: one enum, complete code in the brief, 1 source file + 1 test file).
- Brief: `task-2-brief.md`. Report: `task-2-report.md`.
- Edit observed landing on disk correctly mid-flight: the enum and its doc comment were replaced, `energyTxTypeFromName` and `EnergyTransaction` left byte-for-byte untouched, exactly as the dispatch scoped it.
- **Review verdict: ✅ Spec compliant, quality Approved.** No Critical, no Important. Reviewer confirmed the four save-key members survived verbatim and that `energyTxTypeFromName` + `EnergyTransaction` appear only as context lines. Task 2 complete.
- Reviewer's named-risk check (worth keeping): it grepped every `EnergyTxType` reference in `lib`/`test` and found **no exhaustive `switch` over the enum anywhere**, so adding members cannot break a switch — the reason "analyze clean / 223 passing" is credible rather than lucky.
- Parked (Minor, plan-mandated) — `cruise_save_test.dart:78`'s `reason` string says "no two kinds may share a name", but Dart already forbids duplicate enum member names, so the set-dedup mechanism that wording describes can never fire. The assertion's real job is pinning "exactly seven members exist", which it does correctly (a fourth member would make `values.length` 8 against a 7-element literal). Ruling: **no change** — it is the brief's own text, and the guard is sound; only its stated rationale is loose. Cost if wrong: a future reader misreads what the assertion protects.


### Task 3: The player remembers three new things

- BASE 9d1bca9. Dispatched to implementer agent `a610009232f59897b` (haiku — complete code in the brief, 3 files but all transcription).
- Brief: `task-3-brief.md`. Report: `task-3-report.md`.
- **Reported DONE.** Commit `dae36db` "feat(starward): persist whether a drift is powered, dormant, and how it should end". Full suite **227/227** (223 + 4). `flutter analyze` clean. Review package `review-9d1bca9..dae36db.diff` — verified to contain exactly the 3 task files and no docs, so the uncommitted plan fix stayed out of the range as intended. Task reviewer dispatched.
- The implementer noticed the modified plan file in the working tree, correctly identified it as not its own work, left it out of the commit, and reported it as a concern. Exactly the right behaviour — recorded because it is the evidence that the held-back plan-fix commit was safe to defer.
- `journey.dart` has **no imports whatsoever**, so `player_state.dart` importing it cannot create a cycle. The brief asserts this; it holds.
- `FuelPolicy` is exactly `refuse, halt, coast` — `FuelPolicy.halt` exists as the brief's default. `fuelPolicyFromName` exists at `journey.dart:29`.
- `coast_test.dart` and `fuel_out_test.dart` both exist and both hand-edit save JSON (`coast_test.dart:80-84` removes `driftVelocity*`/`driftStartedAt`; `fuel_out_test.dart:134-135` removes `fuelPolicy`), so the brief's Step 5 regression check is meaningful rather than decorative.
- **No `PlayerState(` construction site exists outside `player_state.dart`.** Adding three optional-with-default constructor params therefore cannot break any existing file's compile — the only compile risk in Task 3 is its own new test group.
- Ruling: the brief's new `cruisePolicyFromName(String?)` in `journey.dart` **duplicates** `fuelPolicyFromName`'s `orElse: () => FuelPolicy.halt` fallback; it could instead delegate as `name == null ? FuelPolicy.halt : fuelPolicyFromName(name)`. **Keep the brief's version as written.** Behaviour is identical, both fallbacks are pinned by tests, and deviating from an explicit plan code block buys a reviewer "differs from the brief" finding for the sake of two lines. Recorded so that if the task reviewer raises the duplication, it is adjudicated against this ruling rather than re-litigated. Cost if wrong: two lines of duplicated fallback that must move together if the default ever changes.

### Plan fixes made during execution (Task 4 prep)

Two defects found in Task 4's brief while pre-reading it for dispatch, plus a third handled in the dispatch. Both plan defects fixed in the plan itself, because the brief is generated from the plan — the artifact must be correct, not just the dispatch text.

1. **A test fixture that could never have passed.** Task 4's `_setDrift` helper wrote `player['driftStartedAt'] = startedAt.toIso8601String()` — a **String**. But `PlayerState.fromJson` reads that key with `(json['driftStartedAt'] as int?)`, so all three of Task 4's new tests would have thrown a `TypeError` inside `init()` instead of showing the intended `hasMomentum isn't defined` RED. The helper was clearly adapted from `coast_test.dart:44`, which writes `startedAt.millisecondsSinceEpoch` (an int); the unit was lost in the copy. Fixed the plan to match `coast_test.dart`. Scanned the whole plan: `toIso8601String` occurred **exactly once**, so the defect is isolated to Task 4. Cost had it shipped: one wasted dispatch, plus a real risk the implementer "fixed" it by loosening `PlayerState.fromJson` to accept strings — a genuine save-format regression.
2. **A doc comment this task would have falsified.** The replacement `brakingCost` block's comment read "Zero for a ship at rest — docked, parked in deep space, or **under power**." Pre-feature, "under power" meant *on a voyage* (such a ship has zero `driftVelocity`, so the quote really is 0). Post-feature the same phrase reads as *cruising* — which the very next line and Task 4's own third test both contradict, since a cruising ship is quoted 100 EN. Changed to "or on a voyage", preserving the original meaning unambiguously.
3. **A third, related stale comment, handled in the dispatch rather than the plan.** `game_controller.dart:917-918`'s `canBrake` comment says "False only for a **coasting** ship that cannot afford the braking burn". The plan's Step 4 quotes only the getter line, so the comment would survive the task still saying "coasting" — yet after Step 4 a *cruising* ship with insufficient energy also gets `canBrake == false`. The Task 4 dispatch instructs the implementer to amend that phrase to "a ship with momentum".

- Ruling: fix defect 1 in the plan rather than let the implementer hit it. It is a transcription slip (a unit dropped when copying a fixture), not a design question, and the plan's own Step 5 asserts a fully green suite — the task could not have passed as written. Cost if wrong: none; the corrected line matches the sibling fixture that has always worked.
- Ruling: fix defect 2 in the plan and defect 3 in the dispatch, each bounded to a single phrase, rather than leaving stale comments for the reviewer to find. Cost if wrong: two comment phrases differ from the plan's original wording; no code is touched and both changes only remove a contradiction the task itself introduces.
- Ruling: **hold the plan-fix commit until Task 3's commit lands.** Task 3 was mid-flight; committing the plan now would race its index, and committing it *before* Task 3's commit would drag it into Task 3's `BASE..HEAD` review range. Plan: let Task 3 commit, generate Task 3's review package from `9d1bca9..<T3>`, then commit the plan fix and use it as Task 4's BASE. The dirty working tree meanwhile is harmless — every task's `git add` list is explicit, so nothing sweeps the plan file. Cost if wrong: a docs commit lands a few minutes later than it could have.

- **Plan fix committed as `a1c1819`** once Task 3's commit and review package were in place, keeping Task 3's range clean. Tree clean afterwards.
- **Task 3 review verdict: ✅ Spec compliant, quality Approved.** All three fields confirmed present in all five touchpoints (constructor, fields, `copyWith` params + pass-through, `toJson`, `fromJson`). Reviewer's named-risk checks: absent-key tolerance is real (`as bool? ?? false`, nullable policy reader), and it read `player_state.dart` for an `operator ==`/`hashCode` that adding fields could silently desync — there is none, so no equality bug. Task 3 complete.
- Parked (Minor) — two, neither load-bearing:
  - `journey.dart:30-34` — `cruisePolicyFromName` re-states `fuelPolicyFromName`'s `halt` fallback instead of delegating. **Plan-mandated** per the earlier ruling; reviewer reported it Minor as instructed. Ruling: **no change**, as already ruled. Cost if wrong: two fallbacks must move together.
  - `cruise_save_test.dart:232-287` — the group covers the null-key path but never calls `cruisePolicyFromName` with an unrecognised non-null value, so its `orElse` line is dead in tests (unlike `fuelPolicyFromName`, pinned by the `'somethingNew'` case at `:226-229`). Ruling: **park, no fix round.** The `orElse` is one line of standard enum-reader boilerplate whose behaviour is identical to the sibling function that *is* pinned; a whole fix round to add one assertion is not worth it, and no later task's correctness depends on it. Cost if wrong: a future edit to that fallback is unguarded by a test.

### Task 4: The controller learns the words

- BASE a1c1819. Dispatched to implementer agent `afdf8ddb9efffe4fa` (haiku — complete code in the brief; a block replacement plus a test append).
- Brief: `task-4-brief.md`. Report: `task-4-report.md`. Diff: `review-a1c1819..84d33bf.diff`.
- **Commit `84d33bf`** — `refactor(starward): name the three drift states instead of one coasting flag`. 230/230 (227 baseline + 3 new), analyze clean.
- Status DONE_WITH_CONCERNS. The one concern: the brief's Step 1 import block lists `player_state.dart`, which nothing in the test references, so `flutter analyze` flags it `unused_import` — directly contradicting the brief's own Step 5 and the binding "analyze must be clean" constraint. The implementer dropped that single line and flagged it rather than either shipping a red analyze or silently deviating.
- Ruling: **the implementer's call is upheld.** The brief frames the block as "the imports it needs", and an unused import is by definition not needed; keeping it would make the brief self-contradictory and violate a Global Constraint. This is the **fourth** plan defect this session and the **second** in Task 4's brief alone — a reminder that a brief is only as compiled as its source. Cost if wrong: one import must be re-added if a later edit of this file starts using `PlayerState` (it does not today; `_setDrift` writes raw JSON).
- **Review verdict: ✅ Spec compliant, quality Approved.** No Critical, no Important. The reviewer verified the behaviour-preservation claim independently and found it *stronger* than the brief asserted: because `hasMomentum` is defined with the literal expression the old `isCoasting` used, all five moved getters plus `canBrake` are byte-identical for **every** state, not merely the `driftPowered == false` ones. It also confirmed by grep that the only assignment of a non-zero `driftVelocity` in `lib` is `_applyFuelOut`'s coast path (`:649-651`, which does not set `driftPowered`), that the other two assignments clear it to zero (`:408`, `:1005`), and that **`driftPowered` is never set to `true` anywhere in `lib`** — the only writers are `copyWith`/`fromJson` defaults. So no existing path distinguishes the two predicates. Task 4 complete.
- Parked (Minor) — four, none load-bearing:
  - `game_controller.dart:932` — the `canBrake` doc comment was edited ("a coasting ship" → "a ship with momentum") although the brief specified only the getter line. **This was my own bounded instruction in the dispatch**, and the change is what makes the comment truthful now that `canBrake` keys off `hasMomentum`. Ruling: **no change, and not a deviation** — it was authorized in advance.
  - `cruise_test.dart:128-148` — the "reads exactly as it did before" test cannot fail against an implementation that leaves `driftElapsed`/`driftDistanceLy`/`driftPath` on the old `isCoasting`, because its fixture is unpowered and the two predicates coincide there. Three of the five moved getters therefore have no test distinguishing them. **Inherited verbatim from the brief**, and the implementation is correct. Ruling: **park, no fix round.** The distinguishing case is exactly what Task 5's `igniteCruise` tests introduce (a powered drift), and Task 5 asserts on `isCruising`/`isCoasting` for it; a fix round here would spend a dispatch to re-test a predicate Task 5 exercises within the hour. Cost if wrong: a future edit could move one getter back to `isCoasting` and only Task 5's tests would notice.
  - `cruise_test.dart:140` — comment says "The three getters that used to key off `isCoasting`" where four did. Comment-only, and the assertion block below it covers all four plus `canBrake`. Ruling: **park.** Cost if wrong: a miscount in a comment.
  - `game_controller.dart:955` — `stopShip()` still guards on `isCoasting`, so once a powered cruise exists it would return early for a cruising ship even though `canBrake` is true. Ruling: **no action; already owned by the plan.** Verified rather than assumed: the plan names `stopShip` at `:935` among the methods Task 7 modifies (plan line 1219) and Task 7 Step 6 ("Settle in `stopShip` before checking the brake", plan line 1386-1391) replaces its body. Recorded here so the seam is not lost if Task 7's brief is ever regenerated from a stale plan. Cost if wrong: Task 7's review must confirm the guard actually moved.

### Task 5: Ignition with no destination

- BASE `84d33bf`. Brief: `task-5-brief.md` (already staged). Report: `task-5-report.md`.

### Task 5 prep (verified, not yet dispatched)

- **`LaunchResult` is exactly `success, noSelection, insufficientEnergy, alreadyTraveling, alreadyHere`** — confirmed by reading the enum. So `engineDormant` genuinely does not exist yet, and the brief's Step 4 note ("replace that one line with nothing, Task 10 adds it") is correct rather than a stale instruction.
- All other members Task 5's tests use exist: `isTraveling` (`game_controller.dart:434`), `player` (`:211`), `energyLedger` (`:220`), `energy` (`:407`).
- Ruling: **keep `igniteCruise`'s inlined re-pin as the brief writes it** (it sets `startX/Y/Z` + `driftStartedAt` in the same `copyWith` as `driftVelocity`/`driftPowered`/`cruisePolicy`), rather than routing it through the `_repinLeg` added in the same task. Reasoning, so a reviewer finding is adjudicated against this rather than re-litigated: the inline form is a *single atomic* state transition for the whole ignition, whereas `_repinLeg` would force either two `copyWith` calls (two intermediate `PlayerState`s) or a widened signature. There is no correctness risk in the duplication because for a parked ship `playerPosition3D == Vec3(startX, startY, startZ)` exactly — `igniteCruise` has already returned unless `!hasMomentum`, and `DriftPath` with `_speed == 0` returns `start + zero·t == start` — so `_repinLeg`'s position read would assign the identical value. `_repinLeg` earns its keep in Tasks 7 and 13, where re-pinning *is* the operation. Cost if wrong: four duplicated assignment lines that must move together if the anchor triple's shape changes.
- Ruling: **pre-authorize one bounded fixture fix in Task 5's dispatch.** Its `_docked` helper selects a target with `c.planets.firstWhere((p) => p.id != c.currentPlanetId)` — the *first* planet, not the nearest — while its own `reason` string says "the nearest planet is affordable from a full tank". That reason string is **verbatim `fuel_out_test.dart:76`**, which is `_doomed`'s precondition line, and `_doomed` reaches its target through `_nearest(c)` (`:58-60`). So `_docked` was adapted from a working helper and lost `_nearest` in the copy — the same class of slip as the `toIso8601String` unit, and the third instance this session of a fixture defect the plan carries silently.
  - **Where the failure lands, derived so the implementer's decision is crisp rather than a guess:** a fresh save has `currentPlanetId: null` (`player_state.dart:133`), so `firstWhere` returns `planets[0]`, the first planet of the lowest-index star inside the nearby rescan. `c.planets` is `_nearby` (`game_controller.dart:206`), *not* the whole catalogue, so that planet is within the rescan's final radius. `_nearbyRadiusLy = 60` (`:71`), doubled up to 4 times while fewer than 10 planets are found (`:526-530`) — so the radius is 60, 120, 240, 480 or 960. `energyCostFor(ly) = max(1, round(2.5·ly))` (`engine.dart:60-61`) against a full tank of `Balance.initialEnergy = 300` covers exactly `ly ≤ 120`. Therefore the precondition holds iff the rescan stayed at 60 or 120 ly, and breaks only if it doubled to 240+, i.e. only if the spawn landed where fewer than 10 planets lie within 60 ly. The default spawn is deliberately placed within 1.5–3 ly of a planet-hosting star (`universe.dart:381-389`, and its own doc comment promises "somewhere to go nearby"), which makes the tight radius overwhelmingly likely — but `spawnInRandomGalaxy` (`:373-377`) may pick a synthetic extra galaxy whose density I have not verified, so at the time of writing this was a genuine coin-flip rather than a certainty.
  - **Resolved: the pre-authorization should not fire.** `kDefaultSpawnMode = SpawnMode.solarSystem` (`universe.dart:541`), and `_boot` passes no `spawn` override (`game_controller.dart:52`), so the ship wakes 0.2–0.9 ly from Sol (`universe.dart:397-400`) — not in a random galaxy, which removes the density doubt above. `planetsNear` returns only planets whose star lies inside the radius (`:243-260`), so `planets[0]` is inside the rescan radius, and the rescan only leaves 60 ly if fewer than 10 planets lie within 60 ly of Sol — not a realistic outcome in real HYG data for the solar neighbourhood. At 60 ly `planets[0]` costs at most `round(2.5·60) = 150` EN against 300. The residual risk is the one thing I did not verify — the actual planet count within 60 ly of Sol for this catalogue — and the authorization below covers exactly that. Cost if wrong: one failed precondition assertion, self-correcting through the authorization.
  - Authorization: if and only if that `LaunchResult.success` precondition fails, swap `_docked`'s `firstWhere` for the `_nearest` idiom copied from `fuel_out_test.dart:58-60`. Nothing else in Task 5 changes; `_nearest` is not needed by any other test in the brief. Cost if wrong: none — the fallback is only taken if the test is actually red, and `_nearest` is a strictly stronger guarantee of the property the reason string claims.


### Task 6 prep (verified, not yet dispatched)

- **Plan defect found and fixed before dispatch — the fifth this session.** Task 6's first test pins `expect(c.energy, 180, reason: '1500 s is 40 ly is 100 EN')` after advancing the clock 37.5 s and then a further 1462.5 s. The advance totals **1500 s**, and the reason string agrees: 1500 s × (1/37.5 ly/s) = 40 ly, × 2.5 EN/ly = 100 EN, and 300 − 100 = **200**. The expectation `180` is the outlier — it is the value for **1800 s** (48 ly, 120 EN). Verified numerically rather than by eye, including Dart's half-away-from-zero `round()`: 37.5 s → 297 (matches the test), 1500 s → 200, 1800 s → 180.
  - **Fix applied to the plan:** the expectation, not the advance. `expect(c.energy, 180)` → `expect(c.energy, 200)`, leaving the advance (1462.5 s) and the reason string untouched, so all three elements now agree. Changing the advance instead would have kept 180 but falsified the reason string's "1500 s". Brief regenerated; `task-6-brief.md:29` carries the corrected value. Cost if wrong: none — the corrected number is the one the specified `energy` getter actually produces.
  - This is the second defect in as many tasks, and both were a *pinned number that contradicts its own stated rationale*. Worth watching for in Tasks 7-16: the plan's reason strings are a second, independent statement of intent, so a mismatch between a value and its `reason` is a cheap way to catch these.
- Rest of Task 6's numbers verified by hand against the real source, all consistent:
  - `cruiseReserve` = `brakingCostFor(cruiseSpeedLyPerSec)` = `energyCostFor(40 · (1/37.5)/(1/37.5))` = `energyCostFor(40)` = 100 ✓ matches the pinned `expect(c.cruiseReserve, 100)` and, after ignition, `cruiseReserve == brakingCost` (Task 4's `brakingCost` reads the same speed, so both are 100) ✓.
  - `cruiseRemaining` after ignition: budget = 300 − 100 = 200, `secondsForEnergy(200)` = 200 / (2.5 · 1/37.5) = **3000.0** ✓; after 1500 s, budget = 100 → **1500.0** ✓.
  - The dry-reserve test: a tank of 100 passes `igniteCruise`'s `energyBalance <= 0` guard (100 > 0), then budget = 100 − 100 = 0 → `Duration.zero` ✓.
  - The `seconds <= 0` guard in `_cruiseBurnNow` is load-bearing, not defensive: at 0 s the raw formula gives `burnForSeconds(0)` = `energyCostFor(0)` = `minEnergyCost` = **1**, so without the guard every cruise would book a phantom 1 EN the instant it started, and the pinned `expect(c.energy, 300)` right after ignition would fail.
  - `_driftSecondsAt` (`game_controller.dart:323-324`) confirmed to be plain seconds since `driftStartedAt`, and `energy` (`:422-429`) confirmed to return `_player.energyBalance` unmodified when no voyage is in progress — so a cruise's accrual is the only subtraction in the test's path.
- Note for the dispatch: Task 6's brief says to replace `energy` at "line 407" and to add members "after `canBrake` (line 919)". **Both line numbers are stale** — Task 4 inserted ~35 lines above them, and the live positions are `energy` at **:422** and `canBrake` at **:934**. The brief quotes the full old body of `energy` and names `canBrake` explicitly, so the implementer can find both by name; the dispatch will say so rather than let it hunt for a stale line number.

- **Commit `ff9d0a3`** — `feat(starward): let the engine be lit with no destination`. 17/17 in `cruise_test.dart`, 238/238 full suite, analyze clean.
- Status DONE_WITH_CONCERNS, with one deliberate deviation. **My Task 5 prep ruling on this was wrong and is reversed.** I had ruled to keep `igniteCruise`'s inlined anchor repair "as the brief writes it" and pre-emptively argued a reviewer should not flag the duplication, reasoning that the inline form is a single atomic `copyWith`. I optimised for atomicity and missed the binding constraint I was violating: the brief's Step 3 adds `_repinLeg` and its Step 4 never calls it, so the helper is unreferenced, and an unreferenced private method is `unused_element` — `flutter analyze` cannot report "No issues found". The brief contradicted its own Step 5. The implementer found this, wired `igniteCruise` through `_repinLeg`, and reported it rather than silently choosing.
  - I verified the fix myself rather than taking the report's word. `game_controller.dart:1001-1002` is `_repinLeg(velocity: ...)` followed by `_player = _player.copyWith(driftPowered: true, cruisePolicy: onEmpty)`. The ordering is correct: `_repinLeg` is called while the ship is still parked, so its `playerPosition3D` read returns the old anchor (`DriftPath` with `_speed == 0` returns `start`, per `drift.dart:85`), and only then is the velocity written. Calling it the other way round — velocity first — would make the helper read a point along the *new* course from the *old* anchor and teleport the ship; Task 5's own `(c.playerPosition3D - before).length < 1e-9` assertion is what would catch that, and it passes. Both `_persist()` and `notifyListeners()` come after the second write, so no observer can see the intermediate `PlayerState`.
  - Ruling: **deviation upheld, and it is the better code.** Cost if wrong: none identified; the helper is now referenced, the ship does not teleport, and the two-step write is unobservable.
- **Plan fixed to match.** Task 5's Step 4 block now routes through `_repinLeg` and carries a comment recording both constraints — the read-before-overwrite ordering *and* the `unused_element` reason it is not collapsed back into one `copyWith`. Without this the plan would re-teach the defect to anyone regenerating the brief. Cost if wrong: none; the block now matches the shipped, tested code.
- **Review verdict: ✅ Spec compliant, quality Approved.** No Critical, no Important. Diff is purely additive (158 insertions, 0 deletions).
- The reviewer settled deviation #3 empirically rather than by argument: it reproduced `unused_element` under this repo's exact lint config (`include: package:flutter_lints/flutter.yaml`) on a private method that uses both its parameters but is never referenced, and confirmed the analyzer emits `warning - The declaration '_repinLeg' isn't referenced`, which `flutter analyze` counts as an issue. **So the brief as literally written could not satisfy its own Step 5.** It also confirmed the code's `_repinLeg` body uses both params, so no `unused_element_parameter` fires. My ruling was wrong; the implementer's override was right.
- It verified the ordering claim independently and found the two-step write unobservable: both `copyWith` calls are synchronous with no `await`, no `notifyListeners()` and no `_persist()` between them, and Dart is single-threaded, so the intermediate `PlayerState` cannot be seen; `_now()` is invoked the same number of times as in the inline version; the resulting `_player` is field-for-field identical.
- **A verification I would have got wrong:** it established that the "no teleport" assertion (`cruise_test.dart:212`) is *not* vacuous despite looking it — a parked ship's anchor already equals its position, so the position component of the re-pin is a no-op there. But an implementation that skipped the re-pin entirely would leave `driftStartedAt` at the epoch, making post-ignition `playerPosition3D` equal `anchor + v·(now − epoch)`, a huge displacement that fails the assertion. The companion `driftElapsed == Duration.zero` pins the same fact. It also confirmed normalisation is real: an unnormalised implementation would return 7× cruise speed for the `Vec3(0,0,7)` heading and fail both assertions.
- Guard-order sweep found no reachable wrong result, including the `isTraveling`-before-`inDeepSpace` ordering for both deep-space-origin and planet-origin voyages (both refuse, so the order is harmless). Task 5 complete.
- Parked (Minor) — one, plus one informational:
  - `game_controller.dart:994-995` — the zero-heading guard `direction.length <= 0` lets a NaN heading through, since `NaN <= 0` is false; `igniteCruise(const Vec3(double.nan, 0, 0), ...)` would return `success` and store a NaN velocity, poisoning `driftPath`/`brakingCost`/`playerPosition3D`. Ruling: **park, no fix.** Not reachable — headings originate from UI gestures, and the guard is verbatim from the brief. Cost if wrong: a NaN could only enter via a caller that does not exist.
  - Informational: the omitted `engineDormant` guard is currently unreachable because nothing in `lib/` ever sets `engineDormant` to `true` — only reads, defaults and persists it. Confirms Task 10 is the right place for both the guard and its test.
- The reviewer also correctly triaged the plan file's uncommitted edit as not its own work and belonging to Task 6. It was mine; committed as `3c226f0` (see below), which is Task 6's BASE.
- BASE `3c226f0`. Dispatched to implementer agent `a164796901f71848f` (haiku — complete code in the brief). Report: `task-6-report.md`.
- Dispatch carried three resolutions: the brief's line numbers are stale (`energy` is at **:422**, not 407; `canBrake` at **:934**, not 919 — both findable by name); the `seconds <= 0` guard in `_cruiseBurnNow` is load-bearing and must not be "simplified" (without it `burnForSeconds(0)` = `energyCostFor(0)` = `minEnergyCost` = 1, booking a phantom 1 EN at ignition and failing the pinned `expect(c.energy, 300)`); and no `dart format`.
- Also told the implementer it should need **no new imports** (`journey.dart` came in with Task 5), and to report rather than silently add one — the last two briefs each carried a broken import list.
- **Commit `f5fbdcb`** — `feat(starward): charge a cruise for the power it draws, second by second`. 22/22 in `cruise_test.dart`, 243/243 full, analyze clean. Status **DONE**, no concerns. 106 insertions / 11 deletions across only the two intended files.
- **Review verdict: ✅ Spec compliant, quality Approved.** No Critical, no Important. The reviewer compared the diff against the brief's code blocks character by character and confirmed all three new members and the rewritten `energy` are verbatim, doc comments included. It reproduced `243/243` and a clean analyze.
- Independently confirmed the `seconds <= 0` guard is load-bearing rather than defensive: `burnForSeconds(0)` = `energyCostFor(0)` = `math.max(minEnergyCost, 0)` = **1**, and `_repinLeg` sets `driftStartedAt = _now()` at ignition, so `_driftSecondsAt(_now())` is exactly 0 — without the guard the pinned `expect(c.energy, 300)` would read **299**. Guard present and correctly ordered at `:960-962`.
- Confirmed the voyage branch of `energy` is unchanged apart from the inverted guard, and that the cruise branch is genuinely unreachable during a voyage: `igniteCruise` refuses on `isTraveling`, and every launch path calls `_anchorHere`, which zeroes `driftVelocity`.
- Confirmed `cruiseReserve` (`:971-972`) reads only `_ship.engine` and never `_player` or motion, and that `cruiseRemaining`'s rounding is exact for every reachable state — `budget` is always an `int`, and `budget / (1/37.5) * 1e6` lands within float epsilon of an exact microsecond count that `.round()` recovers.
- Confirmed the coast test is non-vacuous: `_setDrift(..., powered: false)` yields `isCoasting == true`, and if `_cruiseBurnNow` keyed off `hasMomentum` the 3-day burn would clamp `energy` to 0 instead of the asserted 300. Task 6 complete.
- Parked (Minor) — one, plus one informational that validates Task 7's shape:
  - `game_controller.dart:957-958` — the doc comment says the missing guard "would book a phantom light-year every time the ship **stopped**", but the phantom charge actually occurs at **ignition**, the one call site of `_repinLeg` where `driftStartedAt` is reset and `seconds == 0`. Documentation-only, inherited verbatim from the brief, no failure scenario. Ruling: **park.** Cost if wrong: a reader mislocates which call site the guard protects.
  - Informational, explicitly deferred by the reviewer to Task 7 and not a Task 6 defect: mid-cruise the new live `energy` disagrees with three readers that still use the raw `_player.energyBalance` — `canBrake` (`:951`), `_launchGate` (`:1218`, `:1222`) and `brakingCost` (`:292-294`) — and `driftPowered` is set at `:1034` but never cleared, so a voyage that fuel-outs under `FuelPolicy.coast` after an earlier cruise would be misclassified as `isCruising` and drain falsely. **Both are closed by Task 7's Steps 4-7** (settle-in-anchor, live-balance launch gate, `driftPowered: false` in both `_anchorHere` and `_applyFuelOut`), which is why Task 7's pre-verification checked exactly those call sites. Recorded so the gap is on the books; no change made here, since it is out of Task 6's scope and Task 7 is the task that books the burn.
  - Note for Task 7's review, so it is adjudicated rather than rediscovered: `canBrake` is **not** changed by Task 7 and does not need to be. Its question is "can I afford to brake", and the reserve exists precisely so the answer is always yes — the live balance can never fall below `cruiseReserve == brakingCost`. In `stopShip`'s path the settle runs first anyway, so `canBrake` reads the settled balance. Cost if wrong: a UI affordance could appear enabled while the live balance reads lower.

### Task 7 prep (verified, not yet dispatched)

- **Plan defect found and fixed before dispatch — the sixth this session, and the third pinned number that contradicts its own stated rationale.** Task 7's fourth test ("the gate sees the unbooked burn, not the stale balance") ignited a cruise, advanced **4500 s**, then asserted `expect(c.energy, 100)` with the comment "The reserve is all that is left, and it is spoken for". 4500 s is 120 ly is **300 EN** — the entire tank — so the live balance is `max(0, 300 − 300)` = **0**, not 100. Verified numerically (4500 s → 120.00000000000001 ly → burn 300 → energy 0; 3000 s → 80 ly → burn 200 → energy 100).
  - **Fix applied to the plan: the advance, not the expectation.** `Duration(seconds: 4500)` → `Duration(seconds: 3000)`. Deciding this needed Task 8, so I read it: Task 8's `exhausted` helper advances exactly **3000 s** and documents "300 EN less the 100 EN reserve is 200 EN, which is exactly 3000 s", with the cruise burning down to the reserve and never below. So 3000 s *is* the exhaustion point, and at it the reserve is all that is left — precisely what Task 7's comment claims. Changing the expectation to 0 instead would have pinned a state the finished game cannot reach, since Task 8's `tick()` resolves the cruise at exactly that moment. Cost if wrong: none; the corrected advance is the one that makes the test's own comment true.
  - Note the trap this avoided: at 3000 s the burn (200 EN) exactly equals the spendable budget, so the scenario is correct whether or not a future task clamps the burn at the reserve. The test does not depend on Task 8 existing.
- Rest of Task 7 verified by hand against the real source:
  - `energyLedger` is `List.unmodifiable(_energyLedger.reversed)` (`game_controller.dart:220-221`), so it is **newest-first** — which is why test 1's `energyLedger.first.type == braking` (added last) and `[1].type == cruiseCost` are correct rather than inverted.
  - Test 1's arithmetic: 1500 s → 40 ly → 100 EN, so `energy` = 200 before the stop ✓; `stopShip` settles the leg (balance 200, ledger `cruiseCost −100`), then `_anchorHere` settles again as a no-op (the `_repinLeg(at: now)` reset `driftStartedAt`, making the next `_cruiseBurnNow()` zero) and charges `brakingCost` = 100 via `_settleBraking` → balance **100** ✓.
  - Test 3's path through `launchJourney` (`:783-814`) checks out: `braking` is read at `:792` *while still cruising* (100), the gate runs at `:793` before `_anchorHere()` at `:796`, and `_anchorHere` then books the settle and the brake, leaving 100 ✓. Lenient gate at that moment: `available` 200 `<= braking` 100 is false, so it proceeds ✓.
  - Test 4 after the fix: gate sees `available` = 100 against `braking` = 100 → `100 <= 100` → `insufficientEnergy` ✓. The test still distinguishes the live balance from the raw one, since the raw `energyBalance` of 300 would have let the launch through.
  - `_settleBraking(int)` (`:1259-1268`) confirmed to both deduct from `energyBalance` and append a `braking` ledger entry ✓. `_cruiseVelocityOf`, `_newId` and `_applyFuelOut` all exist ✓.
  - The current `_anchorHere` (`:418-430`) does **not** set `driftPowered: false`; Task 7's Step 4 adds it, which is what makes `isCruising` false after a brake (test 3 asserts this) ✓.
- **All four of Task 7's file:line references are stale**, and the dispatch will say so: `_anchorHere` is at **:418** not :384, `_launchGate` at **:1216** not :1123, `_applyFuelOut` at **:615** not :628, and `stopShip` has moved too. The brief quotes each method's full body, so all four are findable by name — but the numbers must not be trusted. This is the same drift that Task 6 hit, and it will keep worsening as tasks insert code.
- BASE `7c703ee`. Dispatched to implementer agent `abc4c51e4eee22081` (sonnet — four existing methods edited plus one added, integration-shaped). Report: `task-7-report.md`.
- Dispatch carried five resolutions: (1) all four stale line numbers, find by name; (2) `_settleCruise`'s idempotency via `_repinLeg`'s `driftStartedAt` reset is the load-bearing design point, not an accident — the two settle calls in `stopShip`+`_anchorHere` must both stay; (3) `_anchorHere` gaining `driftPowered: false` is required for `isCruising` to go false after a brake; (4) `canBrake` must **not** be changed — its question is affordability of the brake, which the reserve guarantees, and in `stopShip` the settle has already run; (5) no `dart format`.
- Also told it the `energy_transaction.dart` import is genuinely needed (verified `grep -c` → 0 in `cruise_test.dart`) but to report rather than silently add any *other* import, since the last two briefs each carried a broken import list.
- And that `_cruiseBurnNow()` deliberately does not clamp at the reserve — the floor is Task 8's job — so it must not "fix" that.
- **Commit `4303f84`** — `feat(starward): book a cruise leg's burn when the leg ends`. 247/247 full suite (incl. `braking_test.dart`), `cruise_test.dart` green, analyze clean. Status **DONE**. 129 insertions / 18 deletions across the two intended files.
- Implementer flagged one concern, which I verified myself before review: Step 4's code block carried its own doc comment, so `_anchorHere`'s **existing three-paragraph doc comment was replaced wholesale** rather than merged. The old comment carried two rationales the new one does not: (a) every launch must re-anchor because `_originPosOf` reads the anchor, so a coasting ship that launched without re-anchoring would plot its route from a stale coordinate; (b) this is the one place a drift is billed, and *why* the charge lives here rather than on the stop button — "if it were free the player would learn to route around the paid button sitting next to it". I confirmed (a) partly survives at `:780` ("The braking burn is different: it is charged at departure, by [_anchorHere]"), but (b) is gone. Handed to the reviewer to adjudicate rather than pre-empting, since it is a quality finding on a "copy verbatim" instruction.
- Review package `review-7c703ee..4303f84.diff` (1 commit, 14036 bytes) → dispatched to reviewer agent `acb293574aa8228db` (sonnet).
- The review prompt also asks for independent verdicts on five specific things: the settle ordering in `_anchorHere`; `_settleCruise`'s idempotency across every path; whether `_launchGate` asking the live `energy` changed any **non-cruise** outcome; the two `driftPowered: false` sites closing Task 6's misclassification gap; and the doc-comment loss above. It also carries the explicit note that `canBrake` was deliberately **not** changed and must not be flagged as a defect — with an invitation to tell me if that reasoning is wrong.

### Task 8 prep (verified; **plan defect found and fixed**, not yet dispatched)

- **Seventh plan defect, and the first structural rather than numeric one.** Task 8's first two tests asserted against a controller that was never ignited. The helper
  `Future<GameController> exhausted(FakeClock clock, FuelPolicy policy)` **boots its own controller** (`final c = await _boot(clock);`), and `_boot` constructs a fresh `MemoryStorage()` on every call when no `storage` is passed — so `final c = await _boot(clock);` in the test body and the `c` inside `exhausted` are **two different `GameController`s over two separate saves**. Consequence: test 1's `expect(identical(c, c2), isTrue, reason: 'precondition: same controller')` asserts a falsehood by construction, and every later assertion in tests 1 and 2 reads the untouched parked ship — `energy` would be 300 not 100, `isDormant` false not true, and `(c.playerPosition3D - start).length` 0 not 80. Tests 3, 4, 5, 6 and 7 are unaffected: they use the returned controller or ignite inline. Verified by reading `_boot` in `cruise_test.dart:20-27` — not inferred.
  - **Fix applied to the plan: `exhausted` now takes the controller** (`Future<void> exhausted(GameController c, FakeClock clock, FuelPolicy policy)`) and all four call sites pass it. Chosen over the alternative (leaving the helper to boot its own and having tests 1-2 obtain `start` from a separate boot, relying on `math.Random(3)` making both spawns identical) because it removes the falsehood at its root instead of working around it, drops the need for the `identical` precondition guard entirely — that guard existed only because the author was unsure — and stops the tests depending on spawn determinism. Cost if wrong: none identified; the four call sites are now uniform and each test asserts against the ship it actually moved.
  - **Same edit fixed a wrong number in a shipped comment.** The plan's Step 3 doc comment for `_cruiseExhaustTime` says the naive check "trips at 2992 s". Computed exactly: `burnForSeconds(s) = energyCostFor(s * 1/37.5) = max(1, round(s/15))`, so `>= 200` first holds at **2992.5 s** (`round(199.5) = 200` under Dart's half-away-from-zero), which at whole seconds is 2993. The plan's own next clause — "lands 0.2 ly short" — is *exactly* right for 2992.5 (7.5 s / 37.5 = 0.2 ly) and only approximate for 2993 (0.1867 ly), which shows the author computed the crossing correctly and then truncated it. Changed to "first reaches 200 at 2992.5 s" so the sentence is true and the 0.2 ly is exact. Cost if wrong: none; the comment is not load-bearing, but it ships into `game_controller.dart` and the plan's standard is that numbers in it are true.
- Rest of Task 8 verified against the real source:
  - `secondsForEnergy(200)` is **exactly 3000.0** — `200 / (2.5 * (1/37.5))` = `200 / 0.06666666666666667` = 3000.0 ✓, and `(3000.0 * 1e6).round()` = 3000000000 µs, so `exhaustAt` lands exactly on ignition + 3000 s. The "3000.0000000000005" the comment contrasts against is the reciprocal-multiply form (`1/0.06666666666666667 = 15.000000000000002`, `200 * that` = 3000.0000000000005) — so the comment's claim is about a real alternative implementation, not a strawman.
  - Every dependency exists: `travelledBetween(from, to)` (`drift.dart:181`), `passedSystemsAlong({path, upToSeconds})` (`universe.dart:277`), `_pendingDriftReport`/`pendingDriftReport` (`:92`, `:387`), `_driftSecondsAt` (`:323`), `_rebuildNearby` (`:533`), `_maybeRescanNearby` (`:562`), `_voyageResolvesBy` (`:575`), `_applyFuelOut` (`:610`), and `DriftReport` carries all ten fields `_cruiseDriftReport` passes ✓. `DriftReportKind.fuelOut` exists ✓.
  - The plan's claim that `_applyFuelOut` uses `bound: 1e12` for the same reason is true (`:628`) ✓, so `_cruiseDriftReport`'s huge bound is consistent with the established pattern rather than a new liberty.
  - Current `tick()` (`:760-774`) matches the shape Step 6 replaces — journey branch first with its `_persist()`, then `_maybeRescanNearby()` + `notifyListeners()` — so the insertion is additive ✓.
  - All seven tests' arithmetic re-derived by hand and each holds once the fixture is fixed, including the two that differ only by *when* the tick arrives: at 3000 s (exact exhaustion) and at 86400 s (a day late, where billing `now` instead of `exhaustAt` would invent 23 hours of burn that never happened).
  - Note for the dispatch: `_reconcileCruise` is `async` and `tick()` calls it **without `await`** (it cannot — `tick()` is `void`), but every state mutation (`_pendingDriftReport`, `_player`, `_energyLedger.add`, `_rebuildNearby`) runs synchronously before its first `await`, so all seven tests' synchronous reads see settled state. Same pattern as the existing journey branch. Not a defect, but the implementer should not "fix" it into an awaited call.
  - Task 8's file:line refs are stale again: `tick` is at **:760**, not :730.

### Task 9 prep (verified; **two plan defects found and fixed**, not yet dispatched)

- **Eighth plan defect — Critical, cross-task: Task 9's own Step 6 was unsatisfiable.** Task 9's last test asserted `expect(await c.igniteCruise(...), LaunchResult.engineDormant)`, but **`LaunchResult` currently has exactly five values and no `engineDormant`** (verified at `game_controller.dart:27-33`), and the plan deliberately defers that enum value to Task 10 — Task 5's block at plan line 1030 says so in as many words: "`LaunchResult.engineDormant` does not exist yet — that is Task 10. **For this task, replace that one line with nothing** and add it in Task 10". So Task 9's `dormancy_test.dart` would not compile, and Step 6's "whole suite green + `No issues found!`" could not be met by any implementation of Task 9's own steps.
  - **The assertion was wrong twice over**, which is what settled the fix rather than merely moving code. The ship at that point is *coasting* (from `_exhaustedCruise`, policy coast), and `igniteCruise` refuses on `if (hasMomentum) return LaunchResult.alreadyTraveling;` (`:1060`) — so even after Task 10 adds the enum and the guard, that call answers `alreadyTraveling` unless the ship is braked first. Task 10's own test 'ignition is refused too' gets this right and brakes first; Task 9's did not.
  - **Fix applied to the plan: the assertion is removed from Task 9, not the enum added to it.** Adding `LaunchResult.engineDormant` in Task 9 was the alternative and is worse: Task 10's Step 2 explicitly pins its expected failure as "`The getter 'engineDormant' isn't defined for the type 'LaunchResult'`", so moving the enum earlier would break Task 10's own TDD step. Task 9 keeps the half it owns — training refills the tank to 140 but `isDormant` stays true, because only `activate()` clears it — and a comment now records that the ignition half is Task 10's. Cost if wrong: none; the assertion is duplicated, in stronger form, in Task 10's 'ignition is refused too'.
- **Ninth plan defect — Task 10's test comment contradicted Task 5's mandated guard placement.** Task 10's 'ignition is refused too' said "Still coasting, so this is `alreadyTraveling` — brake first to reach the state where the dormant check is the one that answers". But Task 5's block puts the dormancy guard at plan line 1008, **directly after the zero-heading check and before `hasMomentum` at 1009**, and Task 10's Step 4 repeats that placement ("immediately after the zero-heading check"). With the guard first, a dormant *coasting* ship answers `engineDormant`, not `alreadyTraveling` — so the comment misstated the shipped code.
  - The test itself passes either way (it brakes first), so this is documentation-only. **Fix applied: the comment now states the real ordering**, and explains that parking is what makes the dormancy guard the only possible author of the refusal — motion is removed as an alternative explanation. Cost if wrong: a reader would believe `hasMomentum` is checked first and could "fix" the order to match, silently changing which message a coasting-but-dormant player sees.
- Rest of Task 9 verified against the real source:
  - All four settlement methods exist and are reachable: `_settleBurn` (`:1273`), `_settleBraking` (`:1295`), `_settleTank` (`:1312`), `_settleCruise` (`:971`). **All four of Task 9's cited line numbers are stale again** (`:1144`, `:1166`, `:1183`) — find by name. Note `_settleCruise` returns `int`, not `void`.
  - `EnergyTxType.activation` exists (Task 2) ✓, `Engine.activationCost` = 5 ✓, `PlayerState.engineDormant` ✓.
  - `energyCostTo` (`:490`), `fuelExhaustTime` (`:517`), `startCourse` (`:1183`), `completeCourse` (`:1199`), `launchToStar` (`:828`) all exist ✓.
  - `_doomed`'s reason string — "the nearest planet is affordable from a full tank" — is **accurate**, which is worth stating because the same shape was a defect in Task 5's `_docked`. `planetsNear` sorts ascending by distance (`universe.dart:259-260`), so `planets.first` genuinely is the nearest, and the ship spawns in the solar system (`kDefaultSpawnMode`) so it is within ~1 ly of Sol where the 60 ly scan finds well over ten planets. The 12-hour advance before arrival is ample: a ≤60 ly hop at 1/37.5 ly/s is ≤2250 s.
  - `_doomed` is only ever called with `FuelPolicy.coast`, and the coast gate is lenient (`available <= braking` is `1 <= 0`, false), so launching the *farthest* planet on 1 EN is legitimately `success` ✓ — the voyage then exhausts after ~15 s and `_settleTank` drains the last 1 EN to 0, which is what trips `_syncDormancy`.
  - The dormancy `Constraint` block (init must not sync) is consistent with `fuel_out_test.dart`'s hand-edited save having no `engineDormant` key ✓.

### Task 10 prep (verified; **one plan defect found and fixed**, not yet dispatched)

- **Tenth plan defect — Task 10's 'activation clears the block' could not pass.** It was `_exhaustedCruise` → `stopShip()` → `activate()` → expect `igniteCruise` to be `success`. But `cruiseReserve` is *defined* as `brakingCostFor(cruiseSpeed)` (`:995-996`), i.e. the reserve is exactly the braking cost — 100 EN — so braking spends the whole reserve and leaves **0**. `activate()` then hits `if (_player.energyBalance < cost) return false` and refuses; the engine stays dormant; `igniteCruise` answers `engineDormant`, not `success`. Task 9's own test 'a dormant ship can still brake' pins the same arithmetic (`expect(c.energy, 0, reason: 'the reserve bought the stop')`), so the two tasks disagreed about the post-brake tank.
  - **Fix applied: top the tank up with a training session before activating.** After the brake the test now asserts `c.energy == 0`, trains 40 (`startCourse('walk')` + `completeCourse(id, 40)`, the same API and the same +40 Task 9's training test uses), asserts `40` and `isDormant` still true, then `activate()` → `35`, then ignition → `success`. The top-up also buys a second assertion for free: training does not wake the engine, which is `_syncDormancy`'s documented deliberate omission from `_addEnergy`. Cost if wrong: none; every intermediate number is now pinned, and the ignition half still proves activation is what cleared the block.
- Rest of Task 10 verified:
  - `isTraveling` is `_activeJourney?.status == JourneyStatus.inProgress` (`:461-462`) — so a **coasting** ship is not traveling, which is what lets test 1 reach the dormancy guard rather than stopping at `alreadyTraveling` ✓. Worth stating explicitly because it is the one place the two `alreadyTraveling` guards (`hasMomentum` in `igniteCruise`, `isTraveling` in the launch paths) could have been confused.
  - Tests 1, 3 and 5 re-derived: test 1 gets `engineDormant` with `activeJourney` null and 100 EN unspent ✓; test 3 is parked-and-dormant so the dormancy guard is the sole author ✓; test 5 has `energyCostTo(far) >= 150 > c.energy == 100` while coasting (no cruise burn, since `driftPowered` is false) and still gets `engineDormant`, proving the guard precedes the fuel gate ✓.
  - Task 10's file:line refs are stale as usual (`LaunchResult` is at **:27** which happens to still be right; `launchJourney` and `launchToStar` have moved).
  - Task 10 is the task that adds `LaunchResult.engineDormant` and the two exhaustive UI switches, so it is also where Task 9's removed assertion lands.
- **Review verdict: ✅ Spec compliant, quality Sound.** No Critical, no Important. The reviewer reproduced `247/247` and a clean analyze, and ran five mutation experiments on a throwaway copy in `/tmp` (repo untouched) to settle its claims empirically rather than by argument. It confirmed every briefed element is present verbatim with the brief's names, values and ordering, and that `braking_test.dart`'s "training is the way out of a drift that cannot afford to brake" case really is a no-op for a coast — `_settleCruise` returns 0 at its `isCruising` guard before doing any work, traced rather than assumed.
- **The reviewer's best finding: `_anchorHere`'s new doc comment named the wrong hazard, and it proved it.** The comment (verbatim from the brief) said the settle must precede the `brakingCost` read because "settling after reading the cost would spend the same energy twice". That is false — `brakingCost` is a pure function of `driftVelocity.length`, and `_settleCruise` calls `_repinLeg(at: now)` with no velocity argument, so it preserves the velocity and the cost is identical read either way; reading a getter spends nothing. *Reproduced:* swapping the two statements left all of `cruise_test.dart` + `braking_test.dart` green. The real constraint is that the settle must precede the `copyWith` that **clears the velocity** — once `driftVelocity` is zero, `isCruising` is false and the burn can never be booked. *Reproduced:* moving `_settleCruise()` after the `copyWith` fails "launching a voyage mid-cruise" with `Expected: <100> Actual: <200>`, and only that test. So the ordering is load-bearing but the brief explained it wrongly. I would not have caught this by reading: the comment is plausible, and only the mutation shows the stated reason is not what holds the order in place.
- It also **reproduced** the `driftPowered` coverage gap: deleting either clear leaves all 247 tests green, and deleting both makes a coast fuel-out following an earlier cruise read `isCruising == true`. So the fix Task 7 exists to make was unpinned.
- Verdict on the other three adjudications: `_launchGate`'s live `energy` is neither weaker nor stronger for a non-cruise launch (*reproduced*: reverting to the raw balance changes exactly one cruise test and no non-cruise outcome, because `energy` reduces to the balance whenever not cruising and the in-progress branch is unreachable behind `isTraveling`); idempotency holds on every path (*reproduced*: breaking the re-pin fails tests 1 and 2 with `Actual: <0>`); and it **agreed** with leaving `canBrake` on the raw balance, on the grounds that the one state where the two could diverge — live `energy` below the reserve — is exactly the state Task 8 makes unreachable.
- It confirmed the implementer's flag by diffing `git show 7c703ee:…` against the current body line by line: only the doc comment and one inline comment changed, plus the two added lines. No executable statement was silently dropped.
- **Fix round 1 dispatched to implementer `abc4c51e4eee22081`** (resumed, same agent — round 1 of 5), carrying four changes: (1) correct `_anchorHere`'s doc comment to name the velocity-clear hazard and drop the false "spend the same energy twice" claim; (2) fold back the two rationales the brief's block displaced, condensed — the reviewer grepped `lib/` and confirmed the `_originPosOf`/re-anchor reasoning survives nowhere as prose, and the "route around the paid button" rationale survives only as a bare fact at `:780`; (3) fix `cruise_test.dart:366-378`, whose `expect(c.energyLedger, hasLength(entries))` compares the ledger's length to itself because the second `stopShip` returns at the parked guard — a vacuous assertion, which is the one thing the review rubric treats as a defect outright; (4) add a save-reading test that pins `_anchorHere`'s clear, plus the reviewer's end-to-end coast-after-cruise probe, with explicit permission to delete the latter if its affordability precondition does not hold on this seed — and an instruction not to weaken it into something that passes for the wrong reason.
- The dispatch also told it **not** to "fix" two things it might otherwise tidy: `canBrake` stays on the raw balance, and `_applyFuelOut`'s `driftPowered: false` stays even though it is defence-in-depth and no test can fail if it goes (`_anchorHere` clears the flag on every path into a voyage, so it is insurance rather than the load-bearing clear).
- Parked (Minor) — one: `game_controller.dart:960` + `:102` — idempotency rests on `_driftSecondsAt` truncating via `inMilliseconds`, so two `_now()` calls in the same millisecond give `seconds == 0`. Under the production wall clock, ≥1 ms between `stopShip`'s settle and `_anchorHere`'s would make `burnForSeconds` floor to `minEnergyCost` and charge a phantom 1 EN. Ruling: **park, no fix.** There is no `await` between the two calls, so the interval is sub-millisecond in practice, and the frozen `FakeClock` cannot exercise it either way. Cost if wrong: a 1 EN phantom charge in a state the game does not reach.

### Task 7 fix round 1 — implementer reported DONE

- Commit `548e673` — `fix(starward): correct _anchorHere's rationale and pin the powered flag`. 249 tests green (+2), `flutter analyze` clean.
- Implementer's own report: all four changes made; it **kept** the end-to-end coast-after-cruise probe (its "runs dry, not arrive" precondition held on this seed) and ran a mutation check confirming the save-reading test pins `_anchorHere`'s flag alone while the end-to-end test fails only when *both* `driftPowered: false` lines are gone. That is the division of labour the dispatch asked for, so the pairing is deliberate rather than redundant.
- **Scoped re-review dispatched** to a fresh reviewer (agent `a5e6df55a313c10d9`, `sonnet` — a small fix diff takes a cheap-to-mid tier), against `review-fix-7-0813980..548e673.diff`. The diff was cut from `0813980` and not `4303f84`: my three intervening plan-fix commits (`750e2f3`, `696e47d`, `0813980`) sit inside the wider range and would have put plan prose in front of a reviewer whose scope is the fix. The dispatch carries the four findings verbatim, the Global Constraints block, and one specific doubt to settle: the implementer's claim that the new probe's precondition holds, which a test that passes either way would make false.

### Tasks 11-16 pre-verification (scan complete; **one plan defect found and fixed**)

Ran the targeted scan for the defect classes that have recurred eleven times now — a pinned number contradicting its own reason string, a test asserting against a controller a helper never returned, an assertion depending on a symbol another task introduces — over every cross-task symbol Tasks 11-16 use.

- **Eleventh plan defect — Task 13's 60° crossover test could not pass, for a reason the plan itself had already documented two tasks earlier.** It asserted `turnCostFor(59.9°) < braking`, `turnCostFor(60°) == braking`, `turnCostFor(60.1°) > braking`. But `turnCostFor` quotes through `energyCostFor`, which **rounds to whole EN** (`engine.dart:61`), and 0.1° of turn is worth about 0.15 EN. Computed exactly against the standard engine: 59.9° → 99.85 EN → **100**, 60° → 100, 60.1° → 100.16 EN → **100**. So two of the three assertions were `100 < 100` and `100 > 100`, and the test's own name — "the crossover is at 60°" — was the one thing it could not demonstrate.
  - **Fix applied: 59.5° and 60.5°**, the tightest pair the EN grid can express, with a comment recording why 0.1° is not enough. Measured: 59.5° → 99.23 EN → 99, 60.5° → 100.75 EN → 101. Both sit ~0.25 EN clear of the `.5` rounding boundary, and the function is pure with fixed engine constants, so there is no seed or timing sensitivity to widen for. Cost if wrong: none — the assertions are now true, and they still say what the test's name says.
  - Worth naming as a pattern rather than an incident: `burnForSeconds`'s doc comment (`engine.dart:107-110`) warns in as many words that "comparing `burnForSeconds(elapsed) >= budget` fires a tick early, because EN is rounded to whole units", and Task 8's defect was that exact trap. The author knew the quantisation was there and still wrote a test on a 0.1° margin. Same root cause, third instance.
- **Task 13's remaining eight tests re-derived by hand and all consistent.** 300 EN less 1500 s of burn (40 ly × 2.5) = 200, less a 90° turn (141) = 59 ✓; the reload pins 59 ✓; the refusal case at 2400 s holds 140 EN against a 200 EN hairpin ✓; the dormant and parked refusals both return before any settle, so `energy` is unchanged and the ledger stays empty ✓; and the coast re-light case runs 95 → 43 on a 52 EN 30° turn ✓.
- **The carry-forward note on Task 13 is confirmed, not merely inherited.** `turnAngleTo` ends in `math.acos(from.dot(to).clamp(-1.0, 1.0))` (`plan:3169`), whose range is [0, π], so it can never hand `turnCostFor` a negative — which is what makes that function's `radians <= 0` guard safe. `Vec3.normalized` returns `const Vec3(0, 0, 0)` for a zero vector (`vec3.dart:22-25`) rather than NaN, so the `to.length <= 0` guard below it is reachable and the NaN case the guard exists for cannot arrive by that path. Both matter because `clamp` on a NaN returns NaN, and a NaN angle would slip past `radians <= 0` — the guard is only sound because nothing upstream can produce one.
- **The phantom-1-EN concern I had about `correctHeading` is resolved, and was never real.** `correctHeading` sets `energyBalance - cost` and then `_repinLeg(at: _now())`, so `_cruiseBurnNow()` is read at zero elapsed seconds — and `burnForSeconds` floors at `minEnergyCost` (1 EN), which would have made `c.energy` read 42 where Task 13's test pins 43. Checked the shipped code rather than the plan: `_cruiseBurnNow` guards `if (seconds <= 0) return 0;` (`game_controller.dart:969-974`) **before** calling `burnForSeconds`. Task 6 already closed this, and the guard is load-bearing — without it, every settle-at-now would charge a phantom EN and Task 13's `expect(c.energy, 43)` would fail.
- **Task 14's zero-vector test is consistent with the implementation it specifies.** `aimCameraAt` normalises first and returns on `d.length <= 0` (`plan:3336-3337`), so `camera.yaw` stays 1.2 and no NaN reaches `atan2`; the same test's `camera.forward.length` ≈ 1 assertion holds because the early return leaves a camera that was already valid. The separate `_aimCockpitAtOrigin` is *deliberately* not `aimCameraAt` — its `* 0.6` flattening is documented as decorative — so the two are not a duplicated-logic defect despite looking like one.
- **Task 15's `headingLabel` polar case is documented rather than latent.** The plan's Step-5 note (`plan:3760`) pre-empts the trap: `atan2(0, 0)` is `0` in Dart, so `headingLabel(const Vec3(0, 1, 0)).bearing` reads `0°` and only the elevation disambiguates it. Checked that no test asserts a bearing for a pole — the polar case asserts elevation alone (`plan:3526`) ✓.
- **Task 16's consume list is satisfied by earlier tasks.** `_launchMessage` is not created by this plan at all — it is pre-existing and Task 10 only modifies it (`galaxy_map_3d_page.dart:180`), so Task 16 extending the switch over `LaunchResult` is editing a method that already exists. `_worldScale` is pre-existing in the same page. `aimCameraAt` is absent from Task 16's consume list and absent from its code, correctly: the aim happens on cockpit entry (Task 14), not in the HUD painter.

### Process defect caught: the staged briefs were stale, and three were about to be dispatched

- **Twelfth plan defect — Task 8's `2992` survived in a second location.** The fix I made earlier corrected the *test* comment ("first reaches 200 at 2992.5 s"); the *implementation* doc comment for `_cruiseExhaustTime` still said the naive check "trips at 2992 s instead of 3000 s, and the halt point lands 0.2 ly short of the 80 ly". Those two halves refute each other — 0.2 ly is 7.5 s at 1/37.5 ly/s, so the halt point is 2992.5 s, and 2992 s lands 0.1867 ly short. Fixed in the plan (`b19cd86`) and in the re-extracted brief. Cost if wrong: none, and the corrected sentence is now self-checking, since a reader who doubts 2992.5 can re-derive it from the 0.2 ly in the same clause.
- **The real catch: every brief for Tasks 8-16 was extracted at 11:49, before any of my plan fixes.** `task-8-brief.md` still carried the broken `exhausted(FakeClock, FuelPolicy)` helper and the `c2`/`identical` assertion (seventh defect); `task-9-brief.md` still carried the `LaunchResult.engineDormant` assertion that will not compile (eighth); `task-10-brief.md` still carried the activation test with no energy to pay with (tenth); `task-13-brief.md` still carried the 0.1° margin (eleventh). Dispatching any of them would have fed an implementer the exact defect the plan fix existed to remove, and — because the implementer is told the brief is its requirements — it would have implemented the defect faithfully and then been reviewed against a brief that mandates it.
  - **Ruling: re-extract the brief for a task immediately before dispatching it, never earlier.** The plan is the source of truth and it moves; a staged brief is a snapshot of a document under active repair. All of Tasks 8-16 have now been re-extracted from the corrected plan and verified to carry each fix — Task 8's helper signature and the absence of `identical`, Task 9's removed assertion plus its "that is Task 10's assertion" comment, Task 10's training top-up with `expect(c.energy, 35)`, Task 13's 59.5°/60.5°. Cost if wrong: a stale brief reaches an implementer, which is the failure this ruling exists to prevent; the check is one `grep` per fix and takes seconds.
  - The three earlier briefs that *were* re-extracted at dispatch time (`task-6` at 12:07, `task-7` at 12:17) were re-extracted for this same reason, which is why Tasks 6 and 7 went smoothly.

### Tasks 11 and 12 pre-verification (structural; clean)

Checked the claims a brief can get wrong without its own text contradicting itself — the class that produced Task 5's `unused_element` blocker.

- **Task 11's `recommendedDestination` is a genuine move, not a rewrite, and the test's oracle matches the implementation's comparator.** `planets` returns `_nearby` verbatim (`game_controller.dart:206`), so the test's `candidates` is drawn from the same list, in the same order, that the implementation iterates. That matters because the test re-derives "nearest" with `reduce((a, b) => distanceTo(a) <= distanceTo(b) ? a : b)` while the implementation uses a three-clause `isBetter` with a strict `<`. They agree: the implementation prefers featured over non-featured and then strictly-closer, and `<=` in the reduce keeps the earlier element on a tie — the same element the strict `<` keeps. Had `planets` returned the full catalogue rather than the sensor subset, the test could have named a featured planet the implementation never saw. It does not.
  - `Planet.featured` ✓ (`planet.dart:114`), `distanceTo(Planet)` ✓ (`:477`), `currentPlanetId` ✓ (`:235`), `DiscoveryState.explored` ✓.
  - `_recommendDestination` is referenced exactly twice in `journey_page.dart` — the definition at `:291` and the call at `:314` — so the brief's "nothing else in the file uses it" is true and the deletion will not orphan a call site.
  - **Stale line number, cosmetic:** the brief says "replace line 313"; the call is at **:314**. Covered by the standing instruction to find members by name rather than by the brief's line numbers. Not worth a plan edit.
- **Task 12's `home_shell.dart` edit lands exactly on its stated range and the comment is rewritten, not left stale.** `sed` confirms lines 70-74 are the four-line comment plus `final hasJourney = controller.activeJourney != null || controller.isCoasting;`, and the replacement widens it to `hasMomentum` with a comment that now says "coasting or under power" — so the edit does not leave a comment describing a two-state world next to three-state code, which is the defect shape the reviewer caught in Task 7.
  - `cruiseRemaining` is produced by Task 6 (`plan:1059`) and already exists in the source (`:1012`) ✓ — checked because it appears in Task 12's consume list but in none of the plan's type-consistency cross-references, which is where a missing producer would hide.
  - Step 9 pre-empts the one real cross-task hazard: the cockpit-label assertion depends on Task 14's wiring, and the plan already rules on it — `skip` with a comment pointing at Task 14, re-enabled there. That is a better ruling than I would have improvised, so it stands.

### Task 7: complete ✅ (`548e673`)

Re-review verdict: **All four findings addressed, no new Critical/Important breakage.** The reviewer worked from the diff file, the brief, the report and a `/tmp` copy — never touching this checkout.

- **All four verdicts ADDRESSED, each with file:line.** (1) `game_controller.dart:418-422` now names the velocity-clear hazard and explicitly disclaims the false one. (2) Both rationales are back and the reviewer verified each against the code rather than the prose: `_originPosOf` does read the anchor for a deep-space origin (`:888-891`), and `_settleBraking` really is called only from `_anchorHere` (`:436`) — so the "route around the paid button" argument is accurate, because the stop button and both star-map launch paths all funnel through it (`:1052`, `:806`, `:854`). (3) The self-comparing assertion is gone; the test now proves a repeat `stopShip()` is a no-op at the parked guard. (4) `_savedPowered` plus both tests are present.
- **The reviewer reproduced the mutation experiment rather than accepting the report's version of it**, and got the same three results: removing `_anchorHere`'s clear fails the save test alone (27/28); removing `_applyFuelOut`'s clear fails nothing; removing both fails the save test *and* the end-to-end test. That is the division of labour the dispatch asked for, and it confirms `_applyFuelOut`'s clear is genuinely unpinnable alone — which is why it is parked as defence-in-depth rather than treated as a coverage gap.
- **It settled the one doubt I asked it to, and reported the limit honestly.** It ran a focused probe on the copy: on this seed `far = p1-30-0` at 60.67 ly, `voyageFuel = 152`, live balance 100, so the coast-policy launch is affordable and the precondition holds; after the hour advance the voyage resolves fuel-out before arrival, giving `hasMomentum` true, `isCoasting` true, `isCruising` false, energy 0. So the test is a real "runs dry, not arrive" case. It also stated the limitation rather than overclaiming: that test passes with *either* clear present, so it pins the invariant and not either individual line — and it would have passed with fix round 1 absent, since round 1 changed no behaviour on that path. Correct, and worth having on the record: the save test is the one that pins `_anchorHere` specifically.
- Fix diff is a doc comment plus tests; `_anchorHere`'s body is byte-identical apart from an added inline comment. `flutter analyze` clean on the copy; 249 tests green.
- **Task 7 is done. `tick()`'s cruise branch is Task 8's, and `_settleCruise` now has two call sites that must stay idempotent.**

### Thirteenth plan defect — an invented counterexample, quoted from shipped source

- `secondsForEnergy`'s doc comment (`engine.dart:107-110`) claimed division stays exact where "`200 / powerDraw` computed the other way round is 3000.0000000000005". **It is not, in Dart or in Python.** Computed and confirmed with `dart run`: `200 / (2.5 · (1/37.5))` = `3000.0`, `200 · 37.5 / 2.5` = `3000.0`, `(200 / 2.5) · 37.5` = `3000.0`, `200 / 2.5 / (1/37.5)` = `3000.0`. There is no arrangement of these constants that produces the quoted value.
  - **Fix applied to both copies (`bb223db`)** — the shipped comment and Task 8's quotation of it in `_cruiseExhaustTime`. The claim the sentence exists to make is true and is now the one it makes: the first instant `burnForSeconds` reaches 200 is 2992.5 s (`round(t/15) >= 200` ⟺ `t >= 2992.5`), so comparing on quantised energy halts 7.5 s and 0.2 ly early. Cost if wrong: none; the corrected contrast is derivable from the two numbers in the sentence.
  - **Why this one was worth chasing rather than waving through:** the number was *inherited*. It had sat in `engine.dart` since before this plan, and Task 8's author copied it forward. A false number that has survived one review is exactly the kind that survives all of them, and it was about to be shipped a second time in a comment a fresh implementer would read as authoritative. Verified with a real `dart run` rather than by argument, because a floating-point claim is not something to settle by reasoning about it.
  - Third instance of the same root cause as defects eleven and twelve: a number written once and then trusted. The pattern is now clear enough to name — **every number in a comment must be re-derivable from the other numbers in its own sentence.** `2992.5` passes that test against its `0.2 ly`; `2992` fails it; `3000.0000000000005` had nothing to be checked against at all, which is why it lasted.
- **Task 8 dispatched** to implementer `ad12fe5631091ac6a` (`sonnet`) from BASE `bb223db`, with its brief re-extracted after this fix. The dispatch carries the Global Constraints, the interfaces from Tasks 1-7 that the brief cannot know (the `_cruiseBurnNow` zero-guard's load-bearing status, `_settleCruise`'s `int` return and idempotency, `_anchorHere`'s clear, the four state getters, `_applyFuelOut`'s separateness), the stale line numbers by name (`tick` at `:772`, not `:730`; `_settleCruise` ending at `:1001`), four ambiguities ruled on in advance — most importantly that **`tick()` must stay synchronous and must not await `_reconcileCruise()`**, which reads like an oversight in the brief and is not — and the standing ruling against running `dart format`.

### Fourteenth plan defect — Task 15 put world +X on the wrong side of the screen

- Two of Task 15's `hudMarkerPoint` tests assumed that for a camera looking +Z, a point at world `+X` appears **right** of centre. It appears **left**. `Camera3D.project` builds `right = f.cross(Vec3.up)` (`camera3d.dart:106`), and for `f = (0,0,1)` that cross product is `(−1,0,0)` — so `camX = rel · right` is negated for a +X point.
  - **Reproduced through the real code, not by algebra.** Wrote a throwaway `test/zz_probe_test.dart`, ran only that file, deleted it. Output: `world +X,0,100 -> dx=130.7179676972449 dy=400.0` and `world 0,+Y,100 -> dx=200.0 dy=330.7179676972449`, against a viewport of `Size2(400, 800)` and a centre of `(200, 400)`. So `expect(right!.dx, greaterThan(200))` was `130.72 > 200` and `expect(at!.dx, closeTo(200 + 69.2820323, 1e-4))` was `130.72 ≈ 269.28`. Both false. The `+Y` half of the same test was right — `330.72 < 400`, since screen y grows downward — which is what made the failure look like a sign typo rather than a wrong model.
  - **Fix applied (`fe857e6`): the two tests now use `Vec3(−10, 0, 100)` for screen-right, and the convention is written down in the test** — the cross product, the two measured projections, and the note that nothing else pins the sign. `galaxy3d_projection_test.dart:40-46` asserts only `(p.screen.dx − 400).abs() > 1`, deliberately leaving the sign unstated, so before this fix no test in the repo said which side +X lands on. The HUD's markers and the scene painter both depend on it now, so it belongs in a test.
  - **The ruling, and its cost:** I fixed the *test* to match `project` rather than changing `project`. `project` is shipped code that the orbit view, the overview and the scene painter all share, and its existing tests pass; this plan's Task 15 exists to draw markers through the same projection, so it must match reality rather than assert its own. Cost if wrong: if the game is *meant* to render +X on the right, then `project` carries a latent mirroring bug and my fix encodes it into a test instead of exposing it. It would still be testing the real code path, and correcting `project` is a separate change that would have to face the existing projection tests — not this plan's business.
  - Checked the rest of the plan for the same assumption: the only other `.dx`/`.dy` uses are the painter's clamp and path arithmetic (`plan:3716-3740`), which make no sign claim, and the "follows the camera when it turns" test, which I verified passes — with `yaw = π/2` the forward is `(1,0,0)` and the `+X` point really is dead ahead, so that test's `closeTo(200)` is right.
- **Task 15's `headingLabel` strings all verified by running the real formula** for all nine cases: `0°`/`90°`/`180°`/`270°` bearings, `+0°`/`+90°`/`−90°`/`+45°`/`−45°` elevations, and `—` for the zero vector. The `(0,1,1)` case computes `44.99999999999999`, which `toStringAsFixed(0)` renders as `45` — worth having measured, because that value sits one ULP below the integer and a switch to truncation would silently print `44°`.

### Fifteenth plan defect — a turn that spends the last drop left the engine awake

- **Found by tracing Task 16's dormant-state precondition back through Task 13**, not by reading either task's text alone. `_syncDormancy`'s doc comment (`plan:1995`) states the contract outright — "Called at the end of every settlement, so no rule can spend the last drop without the shutdown following" — and it is called from `_settleBurn`, `_settleBraking`, `_settleTank` and `_settleCruise`. `correctHeading` breaks it: it calls `_settleCruise()` and *then* deducts the turn cost, so the sync ran while the tank still held the fee.
  - **The boundary it breaks on is the one its own guard permits.** `correctHeading`'s guard is `energy < cost`, so `energy == cost` proceeds and leaves `energyBalance` at 0 with `engineDormant` false. The ship then reads as cruising on an empty tank until some later `tick()` happens to resolve it — which for a player who closes the app is never. That is precisely the defect this whole feature exists to remove, reintroduced through a side door.
  - **Fixed in the plan (`dcfa3bc`):** `_syncDormancy();` added after `_repinLeg(at: _now());` and before `await _persist();`, with a comment naming why `_settleCruise`'s own sync cannot cover it. A test pins the boundary — `energy == 200`, a hairpin `correctHeading(Vec3(-1,0,0))`, then `energy == 0` and `isDormant` true.
  - Safe for Task 13's other thirteen tests: every one of them either ends with energy > 0 or returns before the deduction.
- **The concern I raised and withdrew, for the record.** I first suspected Task 16's `isDormant` precondition depended on a state Task 13 never produces. Reading Task 16's tests (`plan:3889-3908`) showed the dormant test reaches dormancy through `_reconcileCruise` — a coast cruise, 3000 s, `tick()` — not through a turn. So that specific dependency was always sound and needed no ruling. The turn path was still a genuine gap and is now closed; the two are independent findings that happened to surface together.
- **Stale test count, same commit.** Task 13's Step 4 said "Expected: PASS, all ten." The group holds 5 tests in 'the turn price' and 9 in `correctHeading` — fourteen, and thirteen before my added test, so the count was already wrong when the plan was written. Corrected to "all fourteen."
- **Task 13's brief re-extracted** after this commit (`task-13-brief.md`, 372 lines); all three edits grep-verified present at `:233`, `:347`, `:357`. This is the standing ruling applied — never dispatch a brief extracted before the last plan edit.
- **Task 8 review in flight** (agent `af4b9766acde35a89`, `opus`) against `review-fe857e6..ec5d384.diff`, with four named risks: double-booking between `_settleCruise` and `_reconcileCruise`; whether `_cruiseDriftReport` is built before the anchor moves; `_cruiseExhaustTime`'s `budget <= 0` branch returning `driftStartedAt`; and `tick()`'s new cruise branch returning before `_maybeRescanNearby()` while staying synchronous without awaiting `_reconcileCruise()`.

### Sixteenth plan defect — `_syncDormancy` claimed to be the only way to be dormant

- Task 9's brief introduces `_syncDormancy` with "**The single definition of 'the tank is dry'**: the engine shuts down." Task 8 shipped a second one: `_reconcileCruise` sets `engineDormant: true` inline (`game_controller.dart:1105`) with **100 EN still in the tank** — and it has to, because a cruise exhaustion stops on the *spendable budget* (`balance − cruiseReserve`) rather than on the balance. `_syncDormancy`'s predicate is `energyBalance > 0 → return`, so it would read that tank as full and leave the engine running.
  - **Why this is worth an edit rather than a shrug:** the comment does not merely overstate. It invites the exact refactor that breaks the feature — "unify the two definitions" — and a reader who takes it at its word deletes Task 8's line, silently un-dormanting every exhausted cruise and failing four of Task 8's tests. The invariant the sentence wants to express is real, it is just narrower than the sentence says.
  - **Fixed in the plan (this commit):** the comment now states its own scope ("Shuts the engine down when a settlement has left the tank empty"), keeps the `_addEnergy` note, and adds the counter-case by name with an explicit "do not unify" — the same shape as Task 7's fix, which named the velocity-clear hazard instead of leaving it implicit.
  - **Checked the rest of the interaction before ruling.** `_settleCruise` calling `_syncDormancy()` *is* load-bearing: it deducts with `math.max(0, …)` (`:998`), so a burn larger than the balance drives it to exactly 0 and the sync fires. And it does not disturb Task 8's paths: `stopShip` on an exhausted coast runs `_settleCruise` (early-returns, not cruising) then brakes the reserve to 0, where `_settleBraking`'s sync early-returns because the flag is already set. Task 9's own test asserts exactly that (`isDormant` stays true after the stop).
  - **Also verified while here:** Task 9's `_doomed` helper's `onEmpty: coast/halt` launch on 1 EN really is allowed — `_launchGate` (`:1370`) only requires `available > braking` for a non-refuse policy, and a ship at rest has `brakingCost == 0`, so `1 <= 0` is false and the gate returns null. The precondition the helper asserts holds.
- **Task 9's brief re-extracted** after this commit (326 lines) and the new wording grep-verified. **Standing note for its dispatch:** the brief's line numbers are stale again (`_settleBurn` is at `:1395`, not `:1144`; `_settleBraking` `:1417`; `_settleTank` `:1434`; `_settleCruise` `:992`) — find every anchor by name. And "add after `_settleCruise`" now means after Task 8's cruise cluster (`_settleCruise` … `_reconcileCruise` ends `:1110`); inserting between `_settleCruise` and `_cruiseExhaustTime` would split that cluster, so the dispatch will say to place it after `_reconcileCruise`.

### Task 8 review verdict: Spec ✅ / quality Approved, no Critical, no Important

Four named risks all came back clean, and the reviewer showed its work on each rather than accepting the report's version: no double-booking (`_settleCruise` re-pins so the next `_cruiseBurnNow()` is 0, and `_reconcileCruise` sets `driftPowered: false` so `_settleCruise` is a permanent no-op after it runs); the report is built at `:1079`, before the anchor moves at `:1098`; the `burned > 0` guard is what stops a negative ledger entry in the `budget <= 0` case; and `_rebuildNearby()` is the right call rather than `_maybeRescanNearby()`'s threshold skip. Five minors, adjudicated one by one below.

### Ruling: exhaustion keeps the braking reserve (plan deviation 5)

The reviewer's minor #2 — the `budget <= 0` branch is reachable and queues a zero-length report — sent me back to the spec, and the spec and the plan turned out to disagree about something larger than that branch.

- **The disagreement.** Spec §4.2 ends *both* policies at 0 EN: `halt` by paying the reserve out as a `braking` entry (its §11 item 14 pins `cruiseCost −200` **and** `braking −100`), `coast` by burning the whole tank — 120 ly, not 80. Task 8 as shipped ends both at 80 ly with **100 EN still in the tank** and books no `braking` entry at all. So `halt` gets a free stop, and both policies leave the player 100 EN richer than the spec says.
  - **Why it went unnoticed:** the plan's own "Spec Deviations" section audits exactly this kind of divergence and lists four — the reserve disposition is not among them. So it was not a decision; it was written into Task 8's tests as an assumption and reviewed as one.
- **Ruled: keep the plan's model, and record it.** The reserve exists to guarantee a way out — that is invariant 2, and it is the entire point of the feature, whose defect is a ship with no way to restart. Spending it leaves a coasting player at 0 EN whose only escape is to go and train, which is §4.3's own stated fear ("把出口挂在收费门后面") reintroduced through the back door. Both models were coherent; this one is coherent *with the reason the feature exists*.
  - **Cost if wrong:** the player who runs dry is one reserve richer than intended, and `halt`'s automatic stop is free where the spec charges 100. Recorded in the plan as deviation 5, with invariant 3's named exception (the automatic halt is not a purchase) so the next reader does not "unify" it back.
  - Also recorded as **deviation 6**: `activate` uses `< cost` where spec §4.3 wants strict `>`. Both reach the same end state — spend 5 then train, or train then spend 5 — so the strictness only picks which of two adjacent states the player occupies for one training session. Not worth refusing a request the player just made.

### Ruling: ignition needs a spendable budget, not a positive balance

- **The hole.** `igniteCruise` refused only on `energyBalance <= 0`. With a 100 EN reserve held back, `_cruiseExhaustTime` reads `balance - reserve`, so igniting at 1–99 EN returns "already dry" and the first tick reconciles: a zero-length leg, a `fuelOut` report for 0 ly, and under `coast` a **free perpetual drift** — the exhaustion bills `balance - reserve`, which is negative, so the `burned > 0` guard books nothing and the ship keeps cruise velocity forever.
  - **Reachable straight from an activation**, which is what makes it more than theoretical: a halt-exhaustion leaves 100 EN, activating leaves 95, and 95 EN is a budget of −5. Wake, ignite, re-exhaust, dormant again — a 5 EN loop that buys nothing, one tap away from the state Task 9 creates. The reviewer saw the branch; the loop needed the reserve model to see.
- **Ruled: gate on `energy <= cruiseReserve` → `insufficientEnergy`.** It is the spec's own rule — §4.2 says the cruise's reserve rule "与 `_launchGate` 的 `> braking` 是同一条" — and `_launchGate` already refuses a lenient launch at `available <= braking` (`:1382`), so this makes two paths agree instead of one. It also makes `budget <= 0` genuine defence-in-depth rather than a player-reachable branch.
  - **Landed in Task 10, not Task 6**, because Task 10 owns ignition gating (it already adds the dormancy guard to `igniteCruise`) and because it is the task whose own test encoded the broken flow.
  - **It invalidates one shipped test**, and the failure mode is worth naming: Task 6's `'the reserve is held back even at the very start'` boots with exactly 100 EN and asserts only `cruiseRemaining == Duration.zero` — which a *refused* ignition also satisfies. It would have stayed green while testing nothing. The plan now replaces it with a test that pins both sides of the boundary (100 EN refused; 101 EN is a 15 s cruise).
  - **Cost if wrong:** a player holding ≤ 100 EN can no longer cruise at all until they earn more, where before they could waste 5 EN discovering it. A cruise with a spendable budget of zero has nothing to sell them, so the refusal is the honest message.

### Rulings on the reviewer's remaining minors

- **Restart resolution (minor #1) — closed by Task 12, no code change.** The reviewer is right that `init()` reconciles journeys only and that `_reconcileCruise` has exactly one caller (`tick`, `:788`). But `home_shell.dart:35` is an `IndexedStack`, so `journey_page` builds at startup and its `_sync` runs; Task 12 widens `needsTimer` from `isCoasting` to `hasMomentum`, which is true for a cruise, so the 1 Hz timer starts and the first `tick()` reconciles — within a second of launch, from the pure function of the clock the doc comment promises. An `init()` reconcile would be the same answer one frame earlier at the cost of an await before first paint. **Cost if wrong:** if the voyage page is ever moved off the `IndexedStack` (a `PageView`, say), a cruise would sit unreconciled until something else called `tick()` — the reviewer's over-billing consequence, which the `math.max(0, …)` clamp already bounds.
- **Zero-length report (minor #2) — subsumed** by the budget gate above. The branch stays as defence.
- **Loose doc comment (minor #4) — fixing** in Task 8's fix round 1, alongside minor #3.
- **Ledger timestamp (minor #3) — fixing** in Task 8's fix round 1. The "billed at the exhaust instant, not `now`" intent is the load-bearing part of `_reconcileCruise` and was pinned by nothing; a regression to `createdAt: _now()` would have passed every assertion in the file.
- **The transient plan edit (minor #5)** was mine — the plan fixes committed as `a4cd4ca`, `b19cd86`, `bb223db`, `fe857e6` while the implementer ran. It correctly identified an external writer and correctly excluded it from its commit.

### Task 8 fix round 1 dispatched

Resumed implementer `ad12fe5631091ac6a` from BASE `ab8381a` for minors #3 and #4: pin the ledger timestamp to the exhaust instant (with the mutation experiment — flip `createdAt` to `_now()`, watch it fail, flip it back), and reword `_cruiseExhaustTime`'s null contract to match the code. The dispatch carries the standing no-`dart format` ruling and the note that the budget gate is Task 10's, not to be added early.

### Task 8 fix round 1: complete (`e480a4a`)

Both minors closed. 256 tests pass, `flutter analyze` clean.

- **The mutation experiment was run, not asserted**, and its output is the proof the finding wanted: with `createdAt: exhaustAt` flipped to `createdAt: _now()`, the new assertion fails with `Expected: 2026-01-01 00:50:00.000` (ignition + 3000 s — the exhaust instant) against `Actual: 2026-01-02 00:00:00.000` (the day-late notice). Reverted, green on the real code. So the assertion really does distinguish the two instants, which is exactly what was missing.
- **The implementer corrected my dispatch, and was right to.** I described the `budget <= 0` branch as "not a path a player reaches"; it pointed out that is only true *after* Task 10's gate — today `igniteCruise` rejects only `energyBalance <= 0`, so a ship lit with `0 < energy <= cruiseReserve` reaches that branch immediately. It wrote the comment to state both: defence-in-depth, unreachable from the public API *once* ignition is gated on a spendable budget, and an explicit note about the current guard. That is a better comment than the one I asked for, and I am keeping it rather than trimming it. Worth recording because the dispatch was wrong in the direction of assuming a future task's behaviour was already in place — the same mistake the plan's deviation list exists to prevent.
- Scoped re-review dispatched (`a4260626203499d54`, `sonnet`) against `review-ab8381a..e480a4a.diff`, with the arithmetic to check written out in the dispatch so the reviewer re-derives the exhaust instant from `_cruiseExhaustTime` and `_reconcileCruise` rather than trusting the test's own comment.

### Task 8 fix round 1 re-review: both findings ADDRESSED

Scoped re-review (`a4260626203499d54`, `sonnet`) verified both verdicts against the code *and* by running the test.

- **Finding 1 (test coverage) — ADDRESSED.** It re-derived the exhaust instant from the code rather than the comment: `powerDrawPerSecond = 2.5 × (1/37.5) = 1/15`; `cruiseReserve = energyCostFor(40) = 100`; the `_boot` tank is `Balance.initialEnergy = 300` so the budget is 200 EN; `secondsForEnergy(200)` is exactly `3000.0` in IEEE double (it checked the float representation, which is the part that could have made the assertion brittle); `driftStartedAt` is `DateTime(2026)` and `igniteCruise` adds no ledger entry, so `energyLedger.single` is the cruise row; `_reconcileCruise` books `createdAt: exhaustAt` = ignition + 3000 s, the asserted value. It also confirmed the assertion *distinguishes* the two instants — a day ≠ 3000 s, so a regression to `_now()` fails — and ran the test to green.
- **Finding 2 (comment accuracy) — ADDRESSED.** The null contract now matches the single null path (`if (!isCruising) return null;`). It independently confirmed the reachability claim against `igniteCruise` (`:1193` rejects only `energyBalance <= 0`), so the `budget <= 0` branch really is reachable today, exactly as the comment says, and read the forward-looking half as correctly conditional.
- **One nit, explicitly not a downgrade:** the new paragraph says the `budget <= 0` branch returns "now", but `:1030` returns `_player.driftStartedAt` — equal to now only at ignition. The operative claim in the same sentence ("resolves on the next tick rather than dividing by nothing") holds either way, since `driftStartedAt <= now` makes `_now().isBefore(exhaustAt)` false. Loose phrasing, not a false statement about behaviour. **Not fixing:** the sentence is about *why the branch is safe*, and the safety argument is exact; rewording for precision about which instant is returned would be a second fix round on a comment for a branch that Task 10's gate is about to make unreachable. **Cost if wrong:** a reader momentarily believes the returned instant is always `now`; the branch cannot be reached from the public API after Task 10, and its return value is only ever used as an "already elapsed" sentinel.
- **Nothing else moved:** `git show --stat e480a4a` is exactly two files, 12 insertions / 1 deletion, one doc comment and one `expect` — no behavioural change, no file outside the two named, and no reformatting of untouched code (the standing formatter ruling was respected). No new Critical or Important breakage.

**Task 8: complete (`ec5d384`, fix round `e480a4a`).** Next: Task 9.

### Task 9 dispatched; Tasks 10–16 pre-verified while it runs

Task 9's brief re-extracted immediately before dispatch (md5 unchanged from the copy extracted after `b09b737`, so it is current). Implementer dispatched on `sonnet` from BASE `e480a4a` with: the stale line numbers named (`_settleBurn` :1403, `_settleBraking` :1425, `_settleTank` :1442, `_settleCruise` :992 correct, `_addEnergy` :1455); the ruling that "after `_settleCruise`" now means **after Task 8's cruise cluster** (`_reconcileCruise` ends ~:1127), because inserting between `_settleCruise` and `_cruiseExhaustTime` would split it; that `_reconcileCruise` keeps setting `engineDormant` inline (deviation 5); that `_settleCruise`'s `_syncDormancy()` is a deliberate no-op; that `_applyFuelOut` → `_settleTank` is the path that makes the voyage fuel-out test pass; that `activate`'s `< cost` is deliberate (deviation 6); and **not** to add Task 10's budget gate or `LaunchResult.engineDormant` early.

Local verification done during the wait, so later dispatches start from checked facts rather than re-derivation:

- **Task 10's ordering requirement is satisfiable as written.** `igniteCruise` (`:1188-1193`) guards in the order `noSelection` → `hasMomentum` → `isTraveling` → `inDeepSpace` → energy, so "immediately after the zero-heading check" puts the dormancy guard **before** `hasMomentum` — which is exactly what Task 10's `'ignition is refused too'` test comment claims. Its `stopShip()` call before the assertion is belt-and-braces, not load-bearing.
- **Task 10's `fuel_out_test.dart:166` claim holds.** Neither `test/fuel_out_test.dart` nor `test/braking_test.dart` writes an `engineDormant` key into its hand-edited save, so `PlayerState.fromJson`'s `?? false` fallback applies and the new guard is skipped — those tests keep getting `insufficientEnergy` from the energy gate.
- **Tasks 11–16 consume only symbols that exist.** Checked each `Consumes:` line: `planets`, `stateOf` (`:465`), `distanceTo`, `currentPlanetId`; `ShellScope.go` (`shell_scope.dart:15`); `Camera3D.forward` (`:83`), `.eye` (`:89`), `.clampPitch` (`:97`), `.project` (`:103`), `Projected.visible` (`:25`), `focalFor` (`:135`), `Size2` (`:127`); `brakingCost` (`:292`); `_worldScale` (`galaxy_map_3d_page.dart:36`, a static const on `_GalaxyMap3DPageState` — Task 16's `_HeadingBar` must live in that library or be handed it). No task in the plan consumes a symbol no earlier task produces.
- Task 10's plan text re-read end to end after this session's edits and is internally coherent: the enum, the three guards, the budget gate, the Task 6 test replacement, the two exhaustive switch cases, and the commit list all agree. Its `Files:` line numbers are stale (`launchJourney` is `:802`, not `:751`) — to be re-anchored by name in the dispatch, as usual.

### Task 9 implemented (`7a07000`)

DONE on the first dispatch. 10/10 in `dormancy_test.dart`, 266/266 full suite, `flutter analyze` → `No issues found!`. `fuel_out_test.dart` and `braking_test.dart` pass **unmodified** — no pre-existing test encoded behaviour this task changes, which is the outcome the `init()` constraint was there to protect. Diff is exactly the two intended files (72 lines in the controller, 194 in the new test).

One deviation, and it is correct: the brief's verbatim test file imports `package:starward/data/models/planet.dart` but never names `Planet` — the `_doomed` helper's `near` is inferred from `c.planets.firstWhere(...)` — so as written `flutter analyze` reports `unused_import` and the brief's own required `No issues found!` is unreachable. The implementer removed that one line; every test body is byte-for-byte the brief's. Verified independently: `Planet` and `Journey` and `DriftReport` all appear zero times in the committed file, but `journey.dart` must stay — `FuelPolicy` is defined there (`journey.dart:18`) and is used five times.

**Nineteenth plan defect** — of the same family as the eighteenth and nineteenth: the plan specifies a file whose own content cannot satisfy the plan's own Global Constraint. Here a mandated import contradicts the mandated `No issues found!`. Fixed in the artifact (the line is gone from the committed test) but **not** in the plan text; noted so the final review does not read the plan's Step 1 as the source of truth for that file. **Cost if wrong:** none — the plan's test bodies are otherwise identical to what shipped, so a reader diffing the two sees one line.

### Task 9 review verdict

**Spec ✅ / Quality: Approved with findings.** No Critical, no Important. Four Minors.

All eight of the risks I named in the dispatch came back checked with evidence rather than accepted from the report:

- **`_reconcileCruise` still sets the flag itself** (`:1114`) and is not routed through `_syncDormancy`; nothing unified the two.
- **`init()` untouched** (`:103-132`). It reaches `_syncDormancy` only transitively via `_reconcileJourney → _applyFuelOut → _settleTank`, and only for an in-progress exhausted voyage — the intended new behaviour. A dry save with no voyage stays awake.
- **`_settleTank`'s sync really is outside the drain block** (`:1494-1506`); the old `if (drained <= 0) return;` is gone. Verified by reading the code, not the test.
- **`activate` keeps the strict `<`** (`:1152`); `activationCost` stays on `Engine` (`engine.dart:57`, standard `5` at `:138`); no new `Balance` constant; `_saveKey` still `starward.save.v2`.
- **The unused-import deviation is justified**, confirmed by diffing the brief's Step-1 block against the committed file (exactly one line differs) and by grep (no bare `Planet` identifier). A second cosmetic deviation — the two methods placed after `_reconcileCruise` rather than directly after `_settleCruise` — is not a defect; Dart method order is irrelevant and it keeps the cruise cluster together.
- **Every decrement path enumerated** (`grep 'energyBalance:'` → exactly six sites plus `_addEnergy`): four call the sync, `_reconcileCruise` sets the flag itself, `activate` deliberately does not, `_addEnergy` only adds. `EnergyTxType.turn` / `Engine.turnCostFor` exist but are unused in `lib/state`, so there is **no un-synced turn-spend path** — which also means Task 13 will be the first task to create one, and its dispatch must carry that.
- **The flag survives `_applyFuelOut`'s subsequent `copyWith`** (`:667-682` does not pass `engineDormant`).
- **Mutation sensitivity of each new test** was enumerated, one per test.

### Rulings on the reviewer's four minors

- **Minor #1 — the `drained <= 0` branch of `_settleTank` is never exercised. FIXING.** `_doomed` writes `energyBalance = 1` and a voyage deducts nothing until it settles, so that test drives `drained == 1`. A mutation restoring `if (drained <= 0) return;` ahead of the sync at `:1506` leaves the whole suite green — so the restructure the brief calls out with its own comment ("Runs even when the tank was already empty: this is the moment the ship is known to be out of power, and the only moment that knows it") has **no regression guard**. That is the recurring defect class again: a comment claiming a behaviour that nothing pins. The reviewer rates it Minor because the branch is unreachable through the public API, and it is right that the gate at `:1438` (`energy > braking`) and `returnToOrigin`'s `_settleBurn` (`:1279`, gated to leave `>= cost >= 1`) both keep a real voyage from settling at zero — but "unreachable through the public API" is exactly what a hand-edited save is for, and this file already edits saves to reach states the API refuses. The scenario is a **pre-dormancy save with a dry tank and a voyage in progress**, which is the migration shape the whole `init()` constraint exists to protect. The fix round must write the test *and* mutation-verify it (restore the early return, watch it fail, restore).
- **Minor #2 — "silently un-dormants every exhausted cruise" is the wrong failure. FIXING.** `_syncDormancy` only ever sets the flag (`:1135-1139`); the accurate failure, already stated correctly in the preceding sentence, is that it would *fail to set* it. The word matters because the comment exists solely to prevent one specific future refactor: a reader parsing "un-dormants" goes looking for a `copyWith(engineDormant: false)` that is not there, concludes the warning is stale, and makes the edit. One-word fix, load-bearing comment.
- **Minor #3 — "Called at the end of every settlement" is stricter than the code. FIXING.** `_settleBurn` (`:1453`) and `_settleCruise` (`:993`) early-return before the sync when there is nothing to book. The reviewer supplies the reason it is harmless — a settlement that moves no energy cannot create a new dormancy — and that reason belongs *in* the comment, since it is the justification for why the early returns are safe. Same defect family as the sixteenth plan defect, in the same method's comment.
- **Minor #4 — `_boot`/`_setEnergy`/`_setDormant` duplicate `test/fuel_out_test.dart:22-42`. PARKED, no action.** Flutter tests in this repo each carry their own boot helpers; sharing them across files would need a test-support library the project does not have, and introducing one is out of scope for this plan. **Cost if wrong:** the three helpers drift between files; they are nine lines and the duplication is visible.

### Task 9 fix round 1 dispatched; Task 12's claim re-verified

Fix round 1 resumed the Task 9 implementer from BASE `7a07000` with the three Minors to close: (1) add a test for `_settleTank`'s `drained <= 0` branch — reached by hand-editing a dry tank into a save with a voyage already in progress, which is the pre-dormancy migration shape — with **mutation verification as the acceptance criterion** (restore `if (drained <= 0) return;`, watch it fail, restore, watch it pass; report rather than keep the test if it cannot be made to fail); (2) fix the "un-dormants" wording, which names a failure `_syncDormancy` cannot cause since it only ever sets the flag; (3) qualify "the end of every settlement" and add the reason the two early returns are safe. Minor #4 (duplicated test helpers) parked with a ruling.

Local verification while the fix round runs:

- **Task 8's minor #1 (restart resolution) really is closed by Task 12, and the mechanism is confirmed rather than assumed.** `home_shell.dart:35` is an `IndexedStack` whose `children` are `const <Widget>[...]` including `JourneyPage()` at `:39` — `IndexedStack` builds every child, so `JourneyPage.build` runs at startup. `journey_page.dart:131` calls `_sync(c)` from inside `build` (not from `initState`), and `:103` is `final needsTimer = status == JourneyStatus.inProgress || c.isCoasting;`. Task 12 widens the second disjunct to `c.hasMomentum`, which is true for a cruise, so the 1 Hz `Timer.periodic` at `:105-106` starts at startup and the first `tick()` reconciles. An `init()` reconcile would be the same answer one frame earlier, at the cost of an await before first paint. **Cost if wrong:** if `JourneyPage` ever leaves the `IndexedStack` (a `PageView`, say), a cruise would sit unreconciled until something else called `tick()`.
- **Task 10's two switch cases are genuinely load-bearing.** Both `_messageFor` (`planet_details_sheet.dart:457`) and `_launchMessage` (`galaxy_map_3d_page.dart:180`) switch over all five current `LaunchResult` values with no `default:`, so adding `engineDormant` breaks compilation until both are updated — as Step 6 claims.
- **Task 10's `launchToStar` placement needs one clarification its plan text does not give.** `launchToStar` (`:849`) guards `noSelection` → `alreadyTraveling` (`:855`) → `dist < 0.5` → `alreadyHere` → fuel quote. The plan says "after its `isTraveling` check, before its fuel quote", which spans the proximity check. Put it **immediately after `isTraveling`, before `dist < 0.5`**, so the dormancy answer cannot be pre-empted by the ship happening to sit near the target star — that is what makes `'a star launch is refused the same way'` deterministic, since it launches at `c.stars.starId[0]` from wherever the exhausted cruise left the ship. Both orderings are defensible semantics; determinism decides it. Task 10's dispatch must carry this.

### Task 11 pre-scan: two suspicions raised, both checked and both clean

I read Task 11's plan text in full while the Task 9 fix round ran, and chased two things that looked like the plan's recurring defect class. Both turned out to be fine, and the checks are recorded so no later reviewer re-derives them:

- **Suspicion: the test's candidate set and the getter's iteration set are different domains.** Step 1's test derives its expected answer from `c.planets`, while Step 3's `recommendedDestination` iterates the private `_nearby`. If those differed, the test's `nearest` could be a planet the getter never considers — a test whose expectation is computed over a different population than the code under test, which is how a green-but-wrong test gets written. **Clean: `planets` is literally `_nearby`** (`game_controller.dart:206`, `List<Planet> get planets => _nearby;`). Same list, so the two agree by construction.
- **Suspicion: `expect(rec, isNotNull)` is hostage to the generated universe.** `_nearby` is a *radius-limited* working set (`_nearbyRadiusLy = 60`), not every planet, so the recommendation can legitimately be null — and if the boot-time universe had no unexplored non-current planet in range, the test would be flaky rather than wrong. **Clean: `_rebuildNearby` (`:545`) cannot leave the set short.** It doubles the radius up to four times while `found.length < 10`, then falls back to `_universe.nearestPlanets(pos, cap: 90)` if even 960 ly comes up empty, so `planets` is never empty. The getter's `Planet?` return is honest but the non-null case is what every boot produces.
- **The deleted method leaves no unused import.** `_recommendDestination` is the *only* user of `DiscoveryState` in `journey_page.dart` (`:296`), which is what made this worth checking — the nineteenth plan defect was exactly an unused import making a mandated `No issues found!` unreachable, and Step 5 anticipates an unused *method* but not an unused *import*. **Clean:** `DiscoveryState` lives in `planet.dart` (`:15`), and `journey_page.dart:7` imports that file for `Planet`, which is used in a dozen other places. The import stays load-bearing.
- **Line numbers in Step 4 are off by one, both of them.** The method to delete is `:288-309` (doc comment at `:289-290`, body `:291-309`), not "290-308"; the call site to replace is `:314`, not "313". Both found by name in the dispatch, as usual.

### Task 9 fix round 1 re-review: all three ADDRESSED

Scoped re-review (`a0d3289e53a9b20f0`, `sonnet`) returned ADDRESSED for all three, and **ran the mutation itself** rather than trusting the report: inserting `if (drained <= 0) return;` ahead of the sync fails exactly one test, at `dormancy_test.dart:138`, then restored via `git checkout` and confirmed `git status` clean and 267/267. It also traced the path from `init()` → `_reconcileJourney` (`:117`) → `fuelExhaustProgressFor == 0` → `fuelExhaustTime == departure` (`:515-533`) → `_exhaustedBy` (`:595-599`) → `_applyFuelOut` (`:622`) → `_settleTank` (`:665`) with `drained == 0` (`:1497`), reaching `_syncDormancy()` (`:1510`). `_reconcileCruise` is the only other dormancy route and is called only from `tick()`, which `init()` never calls. It confirmed the `game_controller.dart` half of `7d000f6` is **comment-only** by filtering the diff to non-comment lines.

### Ruling: the new test's scenario is synthetic, and its comment says otherwise

The re-review raised one thing it was not asked about, and it is right: **the state the new test constructs is not reachable in normal play.** `_launchGate` (`:1430-1443`) requires `available > braking` for `halt`/`coast` — leaving at least 1 EN — and `available >= voyageFuel + braking` for `refuse`; nothing decrements the balance mid-voyage; and every settlement that can drive it to 0 also ends the voyage, which I verified directly: `_applyFuelOut` (`:665-683`) calls `_settleTank` and then sets `_activeJourney = null` with `clearActiveJourney: true`, so `inProgress` and a zero tank cannot co-exist in a saved state. `returnToOrigin`'s `_settleBurn` is gated to leave `>= cost >= 1`. So the only producer of the state is `_setEnergy(storage, 0)`.

The test's comment (`dormancy_test.dart:106-107`) says the hand-edited save is "the shape a save written before dormancy existed has", and the re-review shows that is overstated — `_launchGate` and `_applyFuelOut`/`_settleTank` all predate `7a07000`, so pre-dormancy saves were subject to the same invariant. A false historical claim is exactly the class this plan keeps producing.

**Ruled: keep the test, correct the comment.** The test is worth keeping on its own merits — the mutation proves it pins a real branch, and the branch is real code that runs on this input — so the fix is to the *rationale*, not the test. The comment must say the state is deliberately constructed because play cannot produce it, rather than claiming play does. **Cost if wrong:** a reader who believes dry in-progress saves are a real migration shape may later add handling for a case that cannot occur, or argue from the comment that the branch is load-bearing when it is defensive.

Also folded into the same round: **finding 3's replacement sentence is loose for `_settleCruise`.** It says a settlement with nothing to book returns before the sync and names `_settleCruise` among them, but that method skips on `!isCruising` — not on nothing to book — and a *cruising* leg with `burned == 0` does reach the sync. The substantive claim (those two are the only methods that skip it, and the skip is harmless) is correct and verified: the sync has exactly four call sites (`:1008`, `:1468`, `:1488`, `:1510`), `_settleBurn` early-returns at `:1457`, `_settleCruise` at `:993`, and `_settleBraking`/`_settleTank` always sync.

Fix round 2 dispatched for the two comment corrections only — no code, no test behaviour.

### Task 9 fix round 2 (`013d8cf`); a twentieth finding parked to Task 13

Fix round 2 landed both comment corrections; 267/267 green, `flutter analyze` clean, comment-only. Re-review of `7d000f6..013d8cf` dispatched to check the specific risk of a comment over-correcting into a *new* false claim.

While waiting, I read Task 13's plan text (the next task to spend energy) and found one thing the round-2 correction left standing.

**Twentieth finding — "no rule can spend the last drop without the shutdown following" is falsified by `activate`.** The clause is in the shipped `_syncDormancy` doc comment (`game_controller.dart:1123-1124`) and repeated verbatim in Task 13's plan text (`:3305`), where it is the stated justification for the extra sync call after a turn. But `activate` **is** a rule that spends the last drop and deliberately stays awake: `activate`'s own doc comment says "Deliberately does *not* call `_syncDormancy`: a player who spends their last 5 EN waking the engine ends up awake with nothing... Re-dormanting them would be the game quietly taking the decision back." A tank of exactly 5 EN activated is that case. So the universal claim has a documented counterexample two methods away.

Round 2 qualified the *first* half of the sentence ("every settlement **that moves energy**") and left the inference intact, so the two halves no longer match: a scoped premise, an unscoped conclusion.

**Ruled: fix it in Task 13's dispatch, not in a third round now.** Task 13 is the task that writes this phrase into a second comment and that adds the call making it meaningful, so the correction belongs in its brief and costs one instruction instead of a dispatch-plus-review cycle. Task 13's dispatch must say: scope the clause to *settlements* — no **settlement** can spend the last drop without the shutdown following — and name `activate` as the one deliberate exception, pointing at its own comment for why. **Cost if wrong:** the phrase survives as a false universal; a reader who notices `activate` contradicts it may distrust the rest of the contract, which is the sentence that stops a future rule from spending the last drop unsynced.

Also re-verified while reading Task 13: the `_syncDormancy();` call and its reasoning are present at plan `:3309`, with the accurate note that `_settleCruise` cannot honour the contract there because it runs *before* the turn's deduction. And Task 12's anchors are where its plan text says — `_sync` `:99`, `_buildStandby` `:310`, `_DriftDock` `:663`, `_CoastDock` `:716`, and `home_shell.dart:73` is the `hasJourney` line the badge reads.

### Task 9 fix round 2 re-review: correction 2 ADDRESSED, correction 1 PARTIALLY — and the false claim was mine

Correction 2 is clean and the reviewer verified each clause against code: `_settleBurn` early-returns at `:1457` (`burned <= 0`), `_settleCruise` at `:993` (`!isCruising`), only those two skip, `_settleBraking`/`_settleTank` always sync, and the new wording correctly implies a *cruising* leg with `burned == 0` still syncs because `_syncDormancy()` at `:1008` sits outside the `if (burned > 0)` block. The test body is byte-identical to `7d000f6` (diff of comment-stripped lines is empty), the mutation still fails it at `:142`, the whole diff is comment lines, and the tree was restored clean.

**Correction 1 is PARTIALLY ADDRESSED, and the defect is in the wording I dispatched.** I told the implementer to write that the state is "deliberately constructed because play cannot produce it" and that the branch is "defensive". The reviewer disproved the second half and found a flat contradiction with shipped code:

- **"the only settlement that syncs dormancy without booking anything" — false.** `_settleCruise` calls `_syncDormancy()` at `:1008` *unconditionally* once `isCruising`, outside the `if (burned > 0)` block, so a cruising leg with `burned == 0` also syncs with no ledger entry. That path is real, not theoretical: `stopShip` (`:1216`) settles, then `_anchorHere()` (`:1224`) settles again with `burned == 0` after the repin — which `_settleCruise`'s own doc comment at `:988-990` calls out as "two call sites, one booking". So the test comment contradicted a sibling doc comment in shipped code. `_settleTank` is not unique.
- **"nothing decrements the balance mid-voyage" / "play cannot produce it" — false, and the reviewer proved it end-to-end.** `activate()` (`:1153-1170`) deducts the fee and has **no `isTraveling` guard**; `launchJourney` has **no dormancy guard** (that is Task 10's job); and `_syncDormancy` no-ops when already dormant (`:1140`), so dormancy survives a launch. Its probe: a dormant ship holding exactly the 5 EN fee launches a voyage (`LaunchResult.success`), then `activate()` returns true, and the persisted save reads `energyBalance=0` with `activeJourney.status == inProgress`. The reachability of the dormant-5 pre-state is arithmetic rather than impossibility — dormant balances are 0 or 100 plus sums of the 15/40/50/70 rewards, all multiples of 5, and an arriving voyage subtracts an integer cost. So the state the test hand-builds is **reachable through the public API today**, and Task 10's dormancy guard on `launchJourney` is what closes the route.
- It also noted the "defensive" framing is in tension with `_settleTank`'s own doc at `:1508-1509`, which calls this "the only moment that knows it" — i.e. the codebase describes the branch as load-bearing, not defensive.

**This is my second instance of the same mistake**, and worth naming: I asserted a reachability fact about a future task's guard as though it were already in place. The Task 8 fix round produced the first instance (I told that implementer the `budget <= 0` branch was unreachable, and it correctly replied that this only holds *after* Task 10's gate). The pattern is specific and repeatable — **when a task's correctness depends on a guard a later task will add, describe the code as it stands, not as the plan intends it to be** — and it belongs in the final review's notes, because both times it was a subagent that caught it.

**Ruled: fix round 3, and the comment loses its reachability theory entirely.** The durable facts are the ones worth keeping — `_doomed` cannot reach `drained == 0` because its tank still holds the 1 EN it launched with, and resolution is left to `init()` rather than a `tick()` because reopening the save is what the `init()` constraint protects. A sentence about *reachability* is the wrong thing to write here at all: it is about to change (Task 10 closes the `activate`-mid-voyage route), so any version of it becomes stale one task later, and the version I asked for was already false. The comment should say what the test does and why it must hand-build the input, and should not characterise the branch as either defensive or load-bearing — the codebase's own `_settleTank` doc already gives it its meaning. **Cost if wrong:** the test loses a sentence explaining why the input is hand-built; the mutation-proven assertion is what carries the guarantee, and it is untouched.

### Task 9 fix round 3 (`4d0faee`); a process defect of mine

Comment-only, one file (7 insertions / 10 deletions in `dormancy_test.dart`), 267/267 green, `flutter analyze` clean. The reachability theory is gone with no substitute; the two confirmed-true statements survived; the test body, hand-edit and assertions are untouched.

**Process defect (mine, second of its kind this task): I omitted the `Co-Authored-By: Claude Code <noreply@anthropic.com>` trailer from the round-3 commit message, and the implementer correctly kept it anyway** — matching the harness attribution rule and the two prior commits in the same task. Recording it because the failure mode is silent: every earlier dispatch in this plan carried the trailer verbatim, so a missing one produces a commit that looks fine in `git log --oneline` and only differs in `git log` body. From here on the trailer goes in every dispatch's commit block, including fix rounds, without being assumed.

Scoped re-review of `013d8cf..4d0faee` dispatched with a deliberately narrow brief: produce a **claim-by-claim truth table** for every declarative sentence in the committed comment, because the previous two rounds each fixed one false claim and introduced another. It is also asked to check for a *paraphrase* of any removed claim and for a comment that is now true but too thin for a reader.

### Task 9 fix round 3 re-review: uniqueness and defensiveness gone, reachability back as a modal

The reviewer produced the requested claim-by-claim truth table for `dormancy_test.dart:106-112`. Nine claims: **C2–C9 TRUE** (with evidence at `game_controller.dart:117`, `:601-616`, `:609-610`, `:665`, `:1497-1510`, `:292-294`, and the test's own `:39-40`, `:56`, `:125-127`, `:136`); **C1 FALSE**.

- **The uniqueness claim is gone.** "the branch that only syncs dormancy" (`:108`) scopes to `_settleTank`'s own `drained == 0` branch, not to settlements generally — the reviewer checked that it does not smuggle uniqueness back, and it does not.
- **"defensive" is gone**, as is any "harmless"/"defence-in-depth" framing.
- **Both "must survive" statements are present and byte-for-byte identical** to `013d8cf`.
- **The test body is unchanged**: diffing against `013d8cf` with comment-only lines stripped yields no differences. The hand-edit (`:127`), precondition checks (`:131-134`) and assertions (`:136-139`) are byte-identical. The diff is comment-only (filtering `^[+-][[:space:]]*//` leaves zero changed lines). 11/11 and `flutter analyze` clean.
- **The comment is not too thin** — it still says why the input is hand-built, why resolution goes through a reload rather than a `tick()`, and why `_doomed` is not a substitute.

**C1 — "The input has to be hand-built" (`:106`) is the same false claim in a softened modal.** "Has to be" asserts that the state cannot be produced except by hand, which is exactly "play cannot produce it" — the claim the previous round removed, and which the mechanism disproves: `launchJourney` has no dormancy guard (`:802-833`; only `alreadyHere`/`alreadyTraveling` at `:806-807` and the gate at `:812`), `activate()` has no `isTraveling` guard (`:1153-1170`), `_syncDormancy` no-ops when already dormant (`:1140`), and a dormant *parked* ship has `brakingCost == 0` (`:292-294`) so the gate at `:1442` passes at 5 EN. So a dormant ship holding exactly the fee can launch and then activate, persisting `inProgress` with a zero tank. The reviewer caught it by checking for a *paraphrase* of the removed claim rather than its wording — which is the check I asked for, and it earned its keep.

**Ruled: park C1 and carry it into Task 10's dispatch, rather than spend a fourth round on it.** The correction is one word — "has to be hand-built" → "is hand-built" — and **Task 10 appends to this exact file** (`starward/test/dormancy_test.dart`), so its implementer will have the file open and its reviewer will see the line in the diff with an explicit instruction to verify it. That is the skill's prescribed route for a parked finding in an area a later task touches, and it gets the change independently reviewed at no extra dispatch. The finding is not load-bearing for behaviour: the assertion is mutation-proven (restoring `if (drained <= 0) return;` fails it at `:142`), so a false modal in its comment cannot make the suite lie. **Cost if wrong:** the modal survives one more task; the reader harm is that "has to be" implies an unreachable state, which may argue someone into treating the branch as dead code — the opposite of what `_settleTank`'s own doc (`:1508-1509`, "the only moment that knows it") says.

### Task 9: complete (`7a07000`, fix rounds `7d000f6`, `013d8cf`, `4d0faee`)

Three fix rounds, all comment-and-test only; no behavioural change in any of them. 267 tests, `flutter analyze` clean. **One finding carried forward into Task 10** (C1 above). Two lessons recorded for the final review:

1. **Do not describe a later task's guard as though it were already in place.** I did this twice in this task — asserting the `budget <= 0` branch and then the hand-built state were unreachable, both times because Task 10's gates do not exist yet. Both times a subagent caught it, and the second time my wrong wording had already been written into a shipped comment. When a task's correctness depends on a guard a later task adds, describe the code as it stands.
2. **Every dispatch's commit block carries the `Co-Authored-By: Claude Code <noreply@anthropic.com>` trailer, fix rounds included.** I omitted it once; the implementer added it back.

### Task 10 dispatched (BASE `4d0faee`, brief re-extracted, 238 lines)

Implementer on `sonnet`, report to `task-10-report.md`. Brief re-extracted immediately before dispatch and verified to carry this session's plan edits: the budget gate `if (energy <= cruiseReserve) return LaunchResult.insufficientEnergy;` at brief `:167`, `Step 5: Update the Task 6 test the budget gate changes` at `:172`, `'a tank that is all reserve is not enough to cruise'` at `:177`, Steps 6/7/8 at `:200`/`:218`/`:226`.

The dispatch carried ten items beyond the brief text, recorded here so a post-compaction resume does not have to reconstruct them:

1. **Stale line numbers — find every anchor by name.** Plan says `launchJourney` at `:751`; it is `:802`. `launchToStar` `:849` (plan: `:798`), `LaunchResult` enum `:27` (correct), `igniteCruise` `:1184`, `_launchGate` `:1430`.
2. **`igniteCruise`'s guard order is `noSelection` → `hasMomentum` → `isTraveling` → `inDeepSpace` → energy**, so "immediately after the zero-heading check" puts the dormancy guard *before* `hasMomentum` — which is what the brief's `'ignition is refused too'` test comment claims, and required for that test to mean what it says.
3. **`launchToStar` placement clarification the plan text does not give:** the dormancy guard goes **immediately after `isTraveling`, before the `dist < 0.5` → `alreadyHere` check**, so the answer cannot be pre-empted by the ship happening to sit near the target star. Without this the `'a star launch is refused the same way'` test is proximity-dependent.
4. **The budget gate's `energy` is the getter and must stay so** — it is the live spendable balance; at that point it equals `_player.energyBalance` anyway because `isTraveling` already returned. Told the implementer not to "fix" it.
5. **The gap the three guards close is currently reachable** (see C1): a dormant *parked* ship has `brakingCost == 0`, so `_launchGate` passes at 5 EN, and `activate()` has no `isTraveling` guard.
6. **Reuse Task 9's helpers in `dormancy_test.dart`** (`FakeClock`, `_boot`, `_editPlayer`, `_setEnergy`, `_setDormant`, `_doomed`, `_exhaustedCruise`); do not redefine. Do not re-add the unused `planet.dart` import the Task 9 brief carried.
7. **Step 5 replaces an existing test** in `cruise_test.dart` (`'the reserve is held back even at the very start'`), which would keep passing after the gate.
8. **Both UI switches are exhaustive with no `default:`** — verified at `planet_details_sheet.dart:457` and `galaxy_map_3d_page.dart:180`.
9. **C1, carried from Task 9:** `dormancy_test.dart:106` "The input **has to be** hand-built" → drop the necessity modal. Explicitly told to leave the rest of that comment alone (its other statements were verified true).
10. Standing no-`dart format` ruling; `No issues found!` required; trailer in the commit block.

### Task 10 implemented (`9e7cab4`), review dispatched — do NOT re-dispatch this task

Report DONE, no concerns. One commit, 5 files, +126/−5: `game_controller.dart` (+20), `planet_details_sheet.dart` (+2), `galaxy_map_3d_page.dart` (+2), `cruise_test.dart` (+15), `dormancy_test.dart` (+92). Implementer reports **272 passed / 0 failed** and `No issues found!`, and that `fuel_out_test.dart:166` still returns `insufficientEnergy` under all three policies as predicted (that hand-edited save has no `engineDormant` key, so `fromJson` falls back to `false`). It watched the test fail first with `Member not found: 'engineDormant'` before implementing.

Review package: `review-4d0faee..9e7cab4.diff` (16320 bytes). Task reviewer dispatched on `sonnet` with a claim-by-claim truth-table instruction (the check that caught the Task 9 residue), the six placement/semantics claims I made in the dispatch marked "tell me if I was wrong", and an explicit note that this task's own guards may have retroactively made the C1 reachability claim true — so it must not report it as a stale finding.

### Task 10 review: spec COMPLIANT, behaviour sound, three false claims shipped

Verdict 1 spec compliance: COMPLIANT — every brief step done, nothing extra; the only edit outside the brief's file list was the dispatch-ordered C1 change. Verdict 2 quality: no blocking finding; the guards, their ordering and the gate are correct and mutation-verified; no reachable path starts a burn while dormant; `stopShip`/braking still works while dormant as Task 9 pinned. 272 passed / 0 failed, `No issues found!`, tree clean (probe copy removed).

**All seven of my dispatch claims verified correct, including the one I was least sure of:** item 6 — the C1 modal is gone with no surviving paraphrase, and Task 10's `launchJourney` guard makes the removed necessity claim retroactively true, which the reviewer correctly did *not* re-add. My `launchToStar` placement (item 3) and the `energy`-getter choice (item 4) were both confirmed right.

**Four findings, all comment/test-string only — no behavioural defect.** I re-derived each against the code before ruling:

- **F1 (should-fix) `dormancy_test.dart:238`,`:243` — both `reason:`s false.** The fixture is *coasting* at exactly 100 EN, so `brakingCost` is 100 and `_launchGate` (`:1460`) refuses on `available <= braking` → `100 <= 100`. Probe: removing only the guard yields `insufficientEnergy`, not `success`. So "it can afford a short hop" and "the tank is not the problem" are both false. **Ruled: fix the fixture, not the wording** — train 40 EN first, which makes the tank genuinely clear the gate and leaves the test a real isolation of dormancy. Task 9's `:206-217` already proves that path works from `_exhaustedCruise` and pins `energy == 140` exactly. Cost if wrong: one test gets three lines longer and its mutation failure mode changes from `insufficientEnergy` to `success` — strictly a stronger test.
- **F2 (should-fix) `game_controller.dart:1029-1030` — stale `_cruiseExhaustTime` doc that contradicts itself.** "Today `igniteCruise` only rejects `energy <= 0`" is falsified by this task's own gate at `:1263`, and it now contradicts the preceding sentence, which says the gate "is meant to be" in place. **Ruled: delete the sentence; require the implementer not to substitute an unverified reachability claim.** `igniteCruise` refusing `energy <= cruiseReserve` is checkable by inspection; "the branch is unreachable" additionally depends on nothing else driving a live cruise's budget to zero. This is the mirror image of the defect I committed twice — a comment describing the *pre*-guard world that nothing updated when the guard landed.
- **F3 (should-fix) `game_controller.dart:32` — `engineDormant`'s doc opens "The tank has energy in it", which is false.** A voyage that runs dry settles to 0 EN and goes dormant (pinned at `dormancy_test.dart:99-100`; `_settleTank` drains to zero before `_syncDormancy()`). Dormancy says nothing about the tank. **Ruled: the brief's text is wrong here** — this one came from the brief, not the implementer, so the ruling is against the plan. Drop the tank clause; keep the distinguishing fact that only activation helps.
- **F4 (should-fix) `dormancy_test.dart:255-270` — the ordering claim is asserted in a comment but pinned by nothing.** The comment says dormancy precedes `hasMomentum`, then the test parks the ship with `stopShip()`, removing exactly the condition that distinguishes the orderings. Verified against the landed code: `:1251` dormancy precedes `:1252` `hasMomentum`, which returns `alreadyTraveling`. **Ruled: rewrite the test in two phases** — coasting+dormant → `engineDormant` (pins dormancy before `hasMomentum`), then `stopShip()` to 0 EN → `engineDormant` again (pins dormancy before the energy gate at `:1263`). Drop the "Task 5's block" provenance, which points at plan structure a reader cannot see.
- **F5 (minor) parked with a ruling: nothing pins the `launchToStar` ordering** (dormancy before `dist < 0.5` → `alreadyHere`). Pinning it needs a fixture that parks the ship within 0.5 ly of a star — more machinery than the ordering is worth. The placement stands on determinism: it keeps `'a star launch is refused the same way'` independent of where the exhausted drift ends. **Cost if wrong:** a future reorder of `launchToStar`'s guards would not be caught by a test; it would be caught only by the star test turning proximity-dependent, which is a subtle failure.

Fix round 1 dispatched to the same implementer (comment-and-test only), with acceptance criteria naming the exact wrong-reason failure each changed test must exhibit under a temporarily removed guard.

### Task 10 fix round 1 (`66aee27`); the fourth subagent correction of me

Report DONE, no disagreements with the four rulings. Comment-and-test only — 2 files, +35/−18, **272 passed / 0 failed**, `No issues found!`, no rule touched. F1: trains 40 EN so the tank genuinely clears the gate, asserts `energy == 140` and `greaterThan(c.brakingCost)`, and mutation-verifies that removing the `launchJourney` guard now fails with `success` rather than `insufficientEnergy`. F2/F3: stale and false sentences deleted, no substitute reachability claim. F4: two-phase, mutation-verified against the `igniteCruise` guard (`alreadyTraveling` in phase 1). F5 parked as ruled. Guards confirmed restored at `:815`, `:864`, `:1248`.

**My error, corrected by the implementer (third subagent correction on this plan, and the second of the same kind):** my dispatch said to mutate the guard "at `:1251`" to check F1 — but `:1251` is `igniteCruise`'s guard, which F1's `launchJourney` path never reaches. The implementer mutated `launchJourney`'s guard (`:815`) for F1 and `igniteCruise`'s for F4, separately, and said so. **Lesson for the final review:** I cite line numbers from a mental model that the implementer has since changed; the two earlier instances were stale plan line numbers, this one was a line number *I* had just read. Cite anchors by name in acceptance criteria, or re-read immediately before writing the number.

Scoped re-review of `9e7cab4..66aee27` dispatched (package 7352 bytes) with the paraphrase check that earned its keep in Task 9, a truth table for the rewritten comments only, an instruction to re-derive the new fixture's numbers independently, and a check that the three guards are intact and correctly ordered after the probe mutations.

### Task 10 fix round 1 re-review: all four ADDRESSED, no new findings

F1–F4 all ADDRESSED with `file:line` evidence; **no new findings**; paraphrase check clean (the reviewer grepped the removed phrases and their variants across `lib/` and `test/` and found no re-statement — the check that caught the Task 9 residue); **truth table 10/10 TRUE** for every declarative sentence the fix wrote or rewrote; the parked `launchToStar` ordering correctly left unpinned.

The re-reviewer independently reproduced all three mutation claims on an out-of-repo copy: removing `launchJourney`'s guard → F1's test fails with `success`; removing `igniteCruise`'s guard → phase 1 fails with `alreadyTraveling`; **moving the guard after the energy gate → an isolated phase-2 test fails with `insufficientEnergy`** (this third probe is the strongest evidence in the task — it shows F4's phase 2 really does pin dormancy before the energy gate, not merely that it passes). Guards intact at `launchJourney:815`, `launchToStar:864`, `igniteCruise:1248`; the source diff is comment-only. 272 passed / 0 failed, `No issues found!`, tree clean.

### Task 10: complete (`9e7cab4`, fix round `66aee27`)

One fix round, comment-and-test only; no behavioural change in it. 272 tests (up from 267), `flutter analyze` clean. **No findings carried forward into Task 11.** The C1 finding carried in from Task 9 is closed: the modal is gone, no paraphrase survives, and Task 10's `launchJourney` guard has made the removed necessity claim retroactively true — which the implementer correctly did *not* re-add. F5 (the `launchToStar` ordering pin) is parked here permanently.

**Lessons recorded for the final review, from this task:**

1. **A comment written to describe the pre-guard world is a landmine for the task that lands the guard.** F2 is the mirror image of the defect I committed twice in Task 9: Task 8's `_cruiseExhaustTime` doc forward-referenced Task 10's gate ("ignition is meant to be gated…") and then described the current behaviour ("Today `igniteCruise` only rejects `energy <= 0`"), so landing the gate made the same paragraph contradict itself. A forward reference must not be paired with a present-tense description of the thing it forward-references.
2. **Cite anchors by name in acceptance criteria, or re-read the file immediately before writing the number.** My F1 instruction said to mutate the guard "at `:1251`" — `igniteCruise`'s — but F1's path is `launchJourney`'s at `:815`. Second instance of this kind; the implementer caught it again.

### Task 11 dispatched (BASE `66aee27`, brief re-extracted, 174 lines)

Implementer on `sonnet`, report to `task-11-report.md`. Task 11 lifts `journey_page.dart`'s private `_recommendDestination` onto `GameController` as a public getter and adds the one-shot cockpit request flag. The dispatch carried eight corrections, all verified against the code at `66aee27` — **the brief's Step 4 line numbers are wrong in both halves**, which is the third task in a row whose plan line numbers were stale:

1. **Step 4 anchors.** Real block in `journey_page.dart`: doc `:289-290`, declaration `:291`, closing brace `:307`, call site `:314`. The brief says "delete lines 290-308" (one line of the method would survive and one line of the doc would not) and "replace line 313". Instructed to delete the doc with the method, since the new getter carries an equivalent doc and a second copy of the rationale left in the UI layer is what this task exists to remove.
2. **The brief says "append to `cruise_test.dart`", but the new groups must go inside `main()`** — the file is 604 lines and `:604` closes `main()`. Appending after it would not compile.
3. **`cruise_test.dart`'s helper is `_boot(FakeClock, {StorageBackend? storage})`** (`:21`), not `{MemoryStorage?}`. The brief's calls compile unchanged; told the implementer not to "fix" the signature.
4. **`planet.dart` is not imported in `cruise_test.dart`** today, so the brief's "add the import" is required, not a duplicate (needed for `DiscoveryState`).
5. **`Planet.featured` exists** (`planet.dart:114`, default `false` at `:86`) — verified, nothing to add.
6. **Run the whole suite**, not the two files Step 5 names.
7. **The lift is faithful and must stay so:** `c.planets` → `_nearby` (same list object — `planets` is `=> _nearby`), plus three receiver renames and `double` → `var`. No rule change.
8. **Ruling on a forward reference in the new getter's doc.** The brief's doc ends "…so the recommendation card and the cockpit's destination marker cannot disagree". **No cockpit destination marker exists** — grep found only `CameraMode.cockpit` framing/vignette, no marker. Ruled the brief's sentence wrong: keep the purpose (one rule every surface reads), do not name a consumer that is not there yet. This is the lesson-1 shape from Task 10 applied pre-emptively rather than caught in review. Cost if wrong: the doc loses a concrete example a later task can restore in one line.

Verified for the eventual reviewer so it need not re-derive: the brief's property test agrees with the getter on **both** tie-breaks — the getter keeps the first candidate on equal distance (`distance < bestDistance`, strict) and so does the test's `reduce` (`<=` picks `a`), and both prefer the featured set before distance. `_rebuildNearby` guarantees at least ten planets, so `expect(rec, isNotNull)` is safe. Deleting the method leaves `planet.dart` imported for `Planet` (`journey_page.dart:149`, `:625`, `:870`, `:933`, `:961`) — `DiscoveryState` was used only at `:296`, so no unused import results.

### Task 11 implemented (`3fd626f`), review dispatched — do NOT re-dispatch this task

Report DONE. 3 files, +114/−20: `game_controller.dart` (+51), `journey_page.dart` (−20 net), `cruise_test.dart` (+62). **276 passed / 0 failed** (up from 272; `cruise_test.dart` 35→39, all four new tests run), `No issues found!`. TDD trace captured (failed to compile first). Implementer agreed with dispatch item 8 — no cockpit destination marker exists today — and rephrased the getter doc accordingly; all other corrections checked out.

**Two implementer concerns, both carried to the reviewer for independent verification rather than accepted:**

1. **`recommendedDestination` reads the `_nearby` working set, which while drifting is rescanned only every 20 ly (`_nearbyRescanLy`), so a coasting ship can be offered a suggestion from a slightly stale set.** The implementer says this is unchanged from the old UI method, so the lift is behaviour-preserving. I asked the reviewer to verify that claim rather than take it — if the old method read a fresher set, the lift is not behaviour-preserving and that is a finding. Either way it is worth a line in the final review for the future cockpit consumer (Task 13), which will read the same set.
2. **"The three new controller members have no callers outside tests yet."** This looks partly wrong: Step 4 points `journey_page.dart`'s call site at `c.recommendedDestination`, so the getter *should* have a production caller, while the `cockpitRequested`/`requestCockpit`/`acknowledgeCockpitRequest` trio correctly has none until Task 12/13. Asked the reviewer to check and report what it finds — a claimed-but-absent caller would be the same defect class as the rest of this plan.

Review package: `review-66aee27..3fd626f.diff` (10380 bytes). Task reviewer dispatched on `sonnet` with the claim-by-claim truth-table instruction, an instruction to diff the old UI method against the new getter to confirm the selection rule is character-for-character the same logic, a request to verify the notification counts in the `requestCockpit` idempotence test against the committed code, and a request to verify that `_cockpitRequested` genuinely *cannot* reach the save rather than merely being absent from it on this one path.

### Task 11 review: both verdicts ACCEPT, five findings — all test-and-comment

**Spec compliance ACCEPT** — exactly the three files, members after `canBrake` (`game_controller.dart:992`), field next to `_pendingDriftReport` (`:102`), `_recommendDestination` deleted, call site reads `c.recommendedDestination` (`journey_page.dart:295`), save key still `starward.save.v2`, new groups inside `main()` (`cruise_test.dart:604-665`), no later-task work leaked in. **Code quality ACCEPT with findings, no blocking.** All seven of my dispatch corrections verified correct, including the lift being character-for-character identical (only the three receiver renames plus `var bestDistance`) and the deletion being exactly doc+method. 276 green, analyze clean, probes restored.

**Both implementer concerns independently checked, and the implementer was right on both:** `_nearby` staleness is unchanged (the old UI method read `c.planets`, which is `=> _nearby` at `game_controller.dart:216` — the same object), and `recommendedDestination` *does* have a production caller at `journey_page.dart:295`.

**Five findings, none of them a behavioural defect; three are defects in tests the brief prescribed verbatim, so the brief is at fault rather than the implementer.** I ruled the brief wrong on all five:

- **F1 (should-fix) `cruise_test.dart:610-616` — the test pins neither guard it names.** A fresh boot is in deep space, so `currentPlanetId` is null and `rec.id` is a `String`, making `isNot(c.currentPlanetId)` trivially true; nothing is explored at boot, making the `DiscoveryState` assertion trivially true. Probes: removing **either** guard still passes. **Ruled: rebuild both halves on real fixtures** — `_docked` (`cruise_test.dart:70`) for the own-planet guard, with a precondition asserting the ship's own planet really is in the candidate set; and a save edit marking the current recommendation explored for the explored guard. Both shapes are fixture-independent (no planet id pinned), which matters because the universe comes from a generator.
- **F2 (should-fix) `cruise_test.dart:618-628` — the hero-world preference is not pinned.** Replacing `isBetter` with pure-nearest still passes, because at boot the nearest candidate happens to be featured, so the two rules agree and the fixture cannot separate them. **Ruled: use the explored set as the lever to force the rules apart** — mark the current recommendation explored, assert the separation precondition loudly (a featured candidate still exists, and nearest-featured ≠ nearest-overall), then assert the recommendation is the nearest *featured* one. This is the one finding whose fix might not be constructible for this seed; I told the implementer **not** to weaken the assertion to make it pass, but to report it for a ruling. A conditional assertion that may assert nothing would be worse than no test.
- **F3 (minor) `cruise_test.dart:649-652` — acknowledge idempotence unpinned.** Removing `acknowledgeCockpitRequest`'s early-return still passes, since the test only reads `cockpitRequested`, false either way. Request-side idempotence *is* pinned. Fix: assert the second acknowledge adds no notification, using the counter already in that test.
- **F4 (minor) `game_controller.dart:101` — the field doc names a producer that does not exist** ("from the voyage screen"; nothing in `lib/` calls `requestCockpit()` until Task 12). Same defect class as dispatch item 8, ruled the same way: state what the flag is, let Task 12 name the producer when it lands.
- **F5 (minor) `game_controller.dart:988` — "always leads somewhere with real content" overstates** the conditional hero preference. Pre-existing lifted text, fixed while the file is open.

Fix round 1 dispatched to the same implementer, test-and-comment only, with mutation verification required for F1 and F2 — that is the whole point of the round, since the defect was assertions that nothing could falsify.

### Task 11 fix round 1 (`65c7d37`); my inference error, corrected for the fourth time

Report DONE. 2 files, +86/−22; `game_controller.dart` six comment lines, `cruise_test.dart` the rest. **277 passed / 0 failed** (up from 276; the `recommendedDestination` group went 2→3 tests), `No issues found!`, no formatter, all probes restored (`grep MUTATION` clean). All five findings addressed. **F2's separation precondition held** for seed 3, so the hero assertion is unconditional and nothing was weakened: after exploring `haven`, nearest-featured = `ashen-reach` (9.72 ly) against nearest-overall = `p1-2-0` (an ordinary world, 3.22 ly). Four mutation probes reproduced by the implementer: own-planet guard removed → fails; explored guard removed → fails; preference → pure-nearest → fails (`ashen-reach` expected, `p1-2-0` actual); acknowledge early-return removed → fails (notified 3, expected 2).

**My error, and a new shape of it.** My dispatch told the implementer that `player['exploredPlanetIds']` backs `stateOf` and that a save edit could mark a planet explored "exactly like `_setEnergy`". **That is wrong.** `stateOf` reads `_planetStates` (`game_controller.dart:475`), which is persisted as the **top-level `planetStates` map** (`game_repository.dart:40`, `:59`, `:101-102`); `completeExploration` writes both `planetStates` and `exploredPlanetIds`, but only `planetStates` backs `stateOf`. The implementer wrote `_setExplored` against `planetStates` and said so. I confirmed the storage fact afterwards.

**Lesson for the final review — the third distinct shape of my own error on this plan, and the one most likely to recur:** I verified `stateOf`'s *read* path and `exploredPlanetIds`' *persistence* path **separately**, then asserted they were connected without ever checking the link. Two true facts joined by an unchecked inference is indistinguishable, in a dispatch, from one verified fact. When a dispatch tells an implementer that writing X will cause Y, the link between X and Y is the thing to check, not X and Y.

Scoped re-review of `3fd626f..65c7d37` dispatched (package 11453 bytes) with an instruction to reproduce the two F1 guards and the F2 preference probes itself, to check that no rewritten assertion is *newly* vacuous (a null `currentPlanetId`, an empty explored set, an empty featured set, an assertion on a value the fixture never varies), to confirm no planet id is pinned, and to verify the `_setExplored` helper writes the field that actually drives `stateOf` — since if it wrote the other one, the tests would pass for the wrong reason and F1/F2 would still be unpinned.

### Task 11 fix round 1 re-review: all five ADDRESSED, correction confirmed, one minor parked

All five ADDRESSED with `file:line` evidence. **The implementer's correction is confirmed correct:** `stateOf` reads `_planetStates` (`game_controller.dart:476-477`), persisted as the top-level `planetStates` map (`game_repository.dart:40`, `:59`, `:101-104`), not `exploredPlanetIds`; `_setExplored` (`cruise_test.dart:68-73`) writes `planetStates`, the field that actually drives `stateOf` — **had it written `exploredPlanetIds`, probe B would have survived**, which is precisely the failure mode my wrong dispatch would have produced. `exploredPlanetIds` is read only by `exploredCount` (`:481`) and written by `completeExploration` (`:1410`); no test reads it and nothing was disturbed.

**All four mutation probes reproduced independently by the re-reviewer**, matching the report exactly: own-planet guard removed → fails at `:641`; explored guard removed → fails at `:659`; preference → pure-nearest → fails at `:692` (`ashen-reach` / `p1-2-0`); acknowledge early-return removed → fails at `:716` (`<2>` / `<3>`). Probes A and C fail at the final guard/preference assertion rather than at a precondition, so the preconditions are load-bearing rather than decorative. No planet id pinned; F2's separation precondition is a bare `expect`, not `if`-guarded. Production diff is **comment-only** — 6 changed lines, all `///` docs. Claim-by-claim truth table: no false claim in any rewritten comment, test name, or `reason:`. 277 green, analyze clean, probes restored, tree clean.

- **New minor, parked with a ruling: `cruise_test.dart:660` is entailed by `:659` plus the fixture, so it cannot independently fail.** Ruled: park, do not fix. It is a *redundant* assertion, not a *vacuous* one — `:659` genuinely pins the explored guard, so the test pins what its name claims; `:660` merely restates a consequence and cannot produce a false pass or a false failure. A second fix round plus a re-review for one redundant line costs more than the line. **Cost if wrong:** the suite carries one assertion that never independently fails, which a future reader may mistake for independent coverage.

### Task 11: complete (`3fd626f`, fix round `65c7d37`)

One fix round, test-and-comment only; no behavioural change in it. 277 tests (up from 276), `flutter analyze` clean. **No findings carried forward into Task 12** beyond the parked minor above. Two observations to carry to the final review rather than to a later task:

1. **`recommendedDestination` reads the `_nearby` working set, which while drifting is rescanned only every 20 ly (`_nearbyRescanLy`), so a coasting ship can be offered a suggestion from a slightly stale set.** Verified unchanged from the UI method it was lifted from — behaviour-preserving — so it is not a regression, but the cockpit consumer (Task 12/13) reads the same set and the staleness becomes more visible when a marker is drawn from it.
2. **The hero-world preference is now pinned, but only because the explored set could be used to force the two rules apart.** The construction is sound; it is worth noting that its separation precondition depends on the generated universe (it held for seed 3). If the generator's seed or the hero-world set ever changes, that precondition assertion fails loudly rather than silently weakening — which is the intended behaviour, and worth a line in the final review.

---

## Task 12 — dispatched

**BASE `65c7d37`.** Brief re-extracted immediately before dispatch via `scripts/task-brief` to `task-12-brief.md` (450 lines) and read in full. Scope: the voyage screen offers ignition and reads a live cruise — `journey_page.dart` (`_sync`, `_buildStandby`, `_DriftDock`, `_CoastDock`), `home_shell.dart` `hasJourney`, new `test/cruise_ui_test.dart`. Ten steps. Produces `_DriftDock({controller, onIgnite})` and `_CoastDock({controller, cruising, onBrake, onChangeCourse, onSteer})`. Dispatch carried seven corrections; four of them are brief defects I verified against the code at `65c7d37` before dispatching.

**Correction 1 — the brief's test file cannot pass `flutter analyze`: `import 'dart:convert';` is unused.** Nothing in the test does a save edit, so the analyzer reports `unused_import` and the mandated `No issues found!` is unreachable. This is the same shape as Task 9's unused-import defect. Told the implementer to delete that one line.

**Correction 2 — `_pumpVoyage`'s `pumpAndSettle()` cannot settle once the ship has momentum, and this repo already says so.** `test/braking_test.dart:460-461`, verbatim: *"Never pumpAndSettle here: the coasting panel runs a one-second ticker that schedules a frame every tick, so settling never happens."* That test then does `pump()` → tap → `pump(100ms)`. Tests 3 and 4 both put the ship in motion, so `_sync`'s widened `needsTimer` starts that ticker. The brief's helper would hang to timeout on exactly the two tests that matter. **The brief's own Step 3 is what makes the brief's own Step 1 helper wrong** — the defect is internal to the brief, not inherited.

**Correction 3 — `find.text('滑行中')` and `find.text('巡航中')` each match TWO widgets, so the brief's `findsOneWidget` assertions fail.** The standby headline (`journey_page.dart:323-326`) and the `_TopBar` subtitle (`:382`, rendered as `Text(subtitle)` at `:588-592`) both name the state. Consequence the brief does not anticipate: **test 4 fails against the unmodified code**, and its failure is a two-match count, not the `zero widgets with text "点火巡航"` that Step 2 predicts — so a naive implementer would chase the wrong failure. Ruled `findsNWidgets(2)` with a comment naming both surfaces, rather than `findsWidgets`, because the requirement being pinned is that the two surfaces *agree* and `findsWidgets` would pass even if one disagreed.

**Correction 4 — Step 9's `skip` escape hatch is a defect, and I ruled against it.** The brief anticipates `find.text('星图 · 座舱视角')` failing because Task 14 has not landed the consumption yet, and instructs marking that one assertion `skip`. **A skipped assertion asserts nothing** — it converts a real gap into a green run, which is the failure mode this plan's reviews exist to catch. Ruled instead: drop the assertion from test 2, keep `expect(c.cockpitRequested, isTrue)` (what Task 12 actually delivers), narrow test 2's name so it no longer claims navigation it does not assert, and carry the cockpit-label assertion to Task 14's dispatch, where it becomes true and where it transitively pins the navigation as well.

**Ruling recorded — test 2 cannot assert the navigation directly.** The obvious substitute, asserting the star map's own mode label (`'星图 · 寰宇'` for overview), **proves nothing**: `home_shell.dart:35` is an `IndexedStack`, which builds every tab, so the star map's texts are findable whether or not it is the selected tab. The assertion would pass before the tap. This is why the brief reached for the cockpit label in the first place — the cockpit label only appears if the star map actually entered cockpit mode, so it pins the request *and* the navigation in one string. It just cannot do so until Task 14. **Cost if wrong:** Task 12 ships with its navigation pinned only by `cockpitRequested`, and a `ShellScope.go(context, 0)` that went to the wrong index would not be caught until Task 14 — which is one task later and where the assertion is already scheduled.

**Correction 5 — the brief's line numbers are stale by ~19 lines** (Task 11 deleted a method they were measured before). Verified at `65c7d37`: `_sync` `:99` ✓, `needsTimer` `:103` ✓, `_buildStandby` `:291` (brief: 310), `coasting` local `:293`, starfield `:299-312`, headline `:323-326`, `_TopBar` subtitle `:382` (brief: 401), `_DriftDock` `:644` (brief: 663), `_CoastDock` `:697` (brief: 716); `home_shell.dart` `hasJourney` `:73` with comment `:70-72` ✓, tab labels `星图` `:89` (index 0), `航行` `:95`. Told the implementer to find every anchor by name — the standing lesson from Task 10's fix round.

**Correction 6 — every symbol the brief's new code references was verified to exist**, so the implementer need not re-derive: `inDeepSpace` `:247`, `deepSpaceOrigin3D` `:250`, `isCruising` `:293`, `driftDistanceLy` `:313`, `passedSystemsSoFar` `:359`, `cruiseRemaining` `:1241`; `_ActionButton({label, icon, onPressed, color, filled})` `:1166`, `_CoastStat({label, value, valueColor})` `:816`, `StarPanel` `common.dart:91`, `StarColors.danger` `theme.dart:24`, `StarColors.panelLight` `:33`. **The brief's `starfield.dart:164` claim is TRUE** — `final scroll = scrollSpeed * (0.3 + s.layer);` is added to `y` and never multiplied by time, so `scrollSpeed` is a static offset and the motion must come from the growing `_phase`. Kept as written.

**Correction 7 — `tester.tap(find.text('航行'))` may be ambiguous.** The tab label is `home_shell.dart:95` and `_TopBar` also renders a `'航行'` title (`journey_page.dart:579`). `braking_test.dart:464` taps that exact finder successfully, while `widget_smoke_test.dart:26` uses `findsWidgets` for `'航行'`, which suggests more than one match can be present. Told the implementer to follow whichever the existing tests prove works and to narrow the finder rather than work around it if ambiguous.

Dispatch also carried: the no-subagents contract, the no-`dart format` standing ruling (the repo predates the installed Dart 3.13 tall-style formatter), the `Co-Authored-By: Claude Code <noreply@anthropic.com>` trailer, "run the **whole** suite — not just the two files Step 9 names", the report path `task-12-report.md` with the return-only contract, and the standing warning about this plan's recurring defect class (two dozen instances so far, two of them this task's corrections 3 and 4).

### Task 13 pre-flight (done while Task 12's implementer runs; anchors re-verified at `65c7d37`)

Brief extracted to `task-13-brief.md` (372 lines) and read in full. Scope: turning a moving ship — three new controller members (`turnAngleTo`, `turnCostTo`, `correctHeading`) plus `test/heading_test.dart`. It touches only `game_controller.dart` and a new test file, so **Task 12 cannot invalidate its anchors** (Task 12 is UI-only: `journey_page.dart`, `home_shell.dart`, `cruise_ui_test.dart`).

**Verified correct, so no later reviewer need re-derive them:**

- **The test count claim "all fourteen" is right** — 5 tests in `the turn price`, 9 in `correctHeading`.
- **All seven pinned turn prices are exact.** `Engine.turnCostFor` (`engine.dart:120-124`) is `energyCostFor(brakingDistanceLy · 2·v·sin(θ/2) / v)` = `energyCostFor(80·sin(θ/2))` (the speed cancels), and `energyCostFor` (`:60-61`) is `max(minEnergyCost, (distanceLy · energyPerLy).round())` — **`.round()`, not `.ceil()`**, floor 1. With `energyPerLy` 2.5: 5°→8.724→**9**, 10°→17.431→**17**, 30°→51.764→**52**, 60°→100→**100**, 90°→141.421→**141**, 120°→173.205→**173**, 180°→200→**200**. Every one matches the brief. (`.ceil()` would have broken 10° and 90°, so the brief's numbers implicitly pin the rounding mode — worth knowing if a future engine edit changes it.)
- **The crossover-at-60° test is sound, including its comment's reasoning.** `turnCostFor(59.5°)` = 99.24 → 99 < 100; `60°` = 100 exactly; `60.5°` = 100.76 → 101 > 100. The comment's "0.1° of turn is worth about 0.15 EN" is correct — `d(cost)/dθ = 100·cos(θ/2)` per radian = 86.6 EN/rad = 1.51 EN/deg at 60°, so 0.1° ≈ 0.151 EN — and the "both of those read 100" claim holds (59.9° → 99.86 → 100; 60.1° → 100.15 → 100). The two illustrative decimals are off by ≤0.02 EN from my hand computation, which is within my own error, not a defect.
- **`turnCostFor(0) == 0` holds** because of an explicit `if (radians <= 0) return 0;` guard at `engine.dart:121` — necessary, since `energyCostFor` floors at `minEnergyCost` 1 and would otherwise quote 1 EN to not turn. This is what makes tests 1 and 5's zero-cost assertions true.
- **The brief's `_energyLedger.add(...)` is correct and test 1's "Newest first" comment is accurate.** The list is stored oldest-first (`:106`) with every writer using `add`, and the public getter reverses it: `List.unmodifiable(_energyLedger.reversed)` (`:231-232`). So after `_settleCruise` appends `cruiseCost(−100)` and `correctHeading` appends `turn(−141)`, the getter yields `[turn(−141), cruiseCost(−100)]` — `first` is the turn, `[1]` is the burn, exactly as test 1 asserts. Had the getter not reversed, this test would have failed for a reason the brief never mentions.
- **Test 7's `isCruising` assertion at 43 EN survives, and the reason matters.** `_syncDormancy` (`:1198-1202`) is `if (energyBalance > 0) return;` — **dormant iff the balance is ≤ 0, not below the 100 EN cruise reserve.** So 43 EN is not dormant, `driftPowered` stays true and the ship still reads as cruising. (The reserve is a *cruise budget* concept: `_cruiseExhaustTime` uses `balance − cruiseReserve` and `_reconcileCruise` sets the dormancy flag itself with 100 EN still aboard, which `_syncDormancy`'s own doc at `:1190-1197` explains and warns not to unify.) Also: `activate()` sets `engineDormant: false` but **not** `driftPowered`, so it is `correctHeading`'s own `driftPowered: true` that makes test 7's `isCruising` true — the assertion is placed after the turn, so it holds.
- **Test 7's fixture arithmetic is right:** `activate()` charges `activationCost` 5 (95 EN left), the 30° turn is 52 EN, 95 − 52 = **43**. `_settleCruise` returns early here (the ship is coasting after exhaustion), so it books no second burn, and the ledger's newest entry is the turn.
- **Test 6's boundary is inclusive and the brief's fixture lands exactly on it:** budget 200 EN = `secondsForEnergy(200)` = 3000.0 s, and `_cruising(1500)` + `advance(1500)` = 3000 s. `engine.dart:107-111` documents that division keeps this exact precisely so the check does not fire a tick early.
- **The refusal test books nothing** because the `energy < cost` guard precedes `_settleCruise()`, and `_cruising(2400)` books nothing either (`igniteCruise` is free by the user's decision, and the advance never ticks). So `expect(c.energyLedger, isEmpty)` holds.
- **The zero-angle test's `length 1` holds** because the turn entry is guarded by `if (cost > 0)` in the brief's own code.
- **Test 2's geometry is right:** 1500 s at 1/37.5 ly/s = 40 ly east; 375 s = 10 ly along the new +Z heading; x stays 40 because `_repinLeg` moves the anchor to the turn point. The ship's balance after the 90° turn (59 EN) is below the reserve but above zero, so it is neither dormant nor stopped, and the test reads position without ticking — no interaction with the reserve.
- **No unused imports in the brief's test file** (unlike Task 12's) — all eight are used.
- **Every consumed symbol exists:** `Engine.turnCostFor` `engine.dart:120`, `EnergyTxType.turn` `energy_transaction.dart:16` (doc: "A heading correction, priced by the angle turned"), `EnergyTxType.cruiseCost` `:13` (whose doc already names "on a turn" as a booking point), `_repinLeg` `:345`, `isDormant` `:297`, `hasMomentum` `:285`, `brakingCost` `:303`, `driftVelocity` `:256`, `playerPosition3D` `:264`, `activate` `:1212`, `_persist` `:197`. `import 'dart:math' as math;` is already at `:1` for `math.acos`.
- **Anchor correction:** the brief says "add after `igniteCruise`" — `igniteCruise` is at **`:1295`**, not the `:1245` my earlier note carried. Find it by name.

**The one confirmed defect — this is the twentieth finding on this plan, and the one I flagged for this dispatch.**

- **The brief's Step 3 comment overstates `_syncDormancy`'s contract.** It reads: *"`_syncDormancy`'s contract is that no rule can spend the last drop without the shutdown following."* **That is false, and the code says so two lines above `activate`.** `activate()` (`:1204-1211`) deliberately spends its last 5 EN without shutting down, documented verbatim: *"Deliberately does not call `_syncDormancy`: a player who spends their last 5 EN waking the engine ends up awake with nothing, which is a worse position than dormant with nothing but is exactly what they asked for. Re-dormanting them would be the game quietly taking the decision back."* So `activate` is a **deliberate exception**, not a counterexample to a contract that does not exist in that form. **Ruling: reword the comment to scope the claim to settlements and name the exception** — the true statement is that no *settlement* leaves the tank at zero with the engine running, and `activate` is the one rule allowed to, by design. **Cost if wrong:** a comment asserting a universal invariant that the neighbouring method exists to violate is the exact defect shape this plan has produced twenty times; a future reader could "fix" `activate` to honour it and silently take the player's decision back.

Dispatch will carry all of the above, plus: the standing no-`dart format` ruling, the trailer, "run the whole suite", the no-subagents contract, the report path, and the requirement to keep the brief's `_repinLeg` comment (whose claim — that `_settleCruise` returns early when coasting and would otherwise leave a stale anchor — is load-bearing and must stay true).

### CORRECTION to my Task 12 ruling on the cockpit-label assertion — my own error, fifth instance

When I ruled against Step 9's `skip`, I wrote that the cockpit-label assertion, once moved to Task 14, "transitively pins the navigation as well". **That is wrong, and I should not have asserted it.** `home_shell.dart:35` is an `IndexedStack`, which **builds every tab**, so `_GalaxyMap3DPageState.build` runs and its `LayoutBuilder` calls `_maybeEnterRequestedCockpit` **whether or not the star map is the selected tab**. Since that handler only reads `_c.cockpitRequested` and the camera's mode, `find.text('星图 · 座舱视角')` will be satisfied after Task 14 **even if `ShellScope.go(context, 0)` navigated nowhere at all**.

So the true scope of the Task 14 assertion is: **the request is raised and consumed, and the camera reaches cockpit mode.** It pins nothing about which tab is showing.

**This is the fifth instance of my recurring error shape** — I verified two facts (`IndexedStack` builds all children; the cockpit label appears when the mode is cockpit) and then asserted a link between them (label ⇒ navigation) that I never checked. Same shape as the `exploredPlanetIds`/`stateOf` dispatch error in Task 11 and the `:1251` guard-citation error in Task 10. The lesson is unchanged and I clearly have not internalised it: **when a dispatch or a ruling claims that X implies Y, check the implication, not X and Y.**

**Ruling on the navigation gap — park it, with the reason and the cost stated.** `_steerFromCockpit` is a two-line method: `c.requestCockpit(); ShellScope.go(context, 0);`. Index `0` is verified to be the star map (`home_shell.dart:89`, tab label `'星图'`, first in the list at `:37-39`). The navigation is therefore unpinned by any assertion in Tasks 12–16. **Options I considered and rejected:** `Finder.hitTestable()` would work in principle, since `_RenderIndexedStack.hitTestChildren` only hit-tests the selected child — but it depends on the mode label being on screen and hit-testable in the star map's layout, which I have not verified, so requiring it risks a fix round over a one-line, verified-by-inspection constant. **Cost if wrong:** if a future edit changed the tab index or dropped the `ShellScope.go` call, no test would fail; the player would tap 点火巡航 and stay on the voyage tab, with the star map having silently entered cockpit mode behind an unselected tab. The final whole-branch review should be pointed at this gap by name.

---

### Task 14 pre-flight (extracted to `task-14-brief.md`, 244 lines)

Scope: the cockpit can be asked for and aimed exactly — a new top-level `aimCameraAt` in `camera3d.dart`, the page's `_aimCockpitAtOrigin` / `_recenter` / `_onScaleUpdate` / `_setMode` / `_SideControls` changes, and the `_maybeEnterRequestedCockpit` handler that consumes `cockpitRequested`. New test `camera_aim_test.dart`.

**Verified correct, so no later reviewer need re-derive them:**

- **`aimCameraAt` really is the exact inverse of `Camera3D.forward`, which is the load-bearing claim of the whole task.** `forward` (`camera3d.dart:83-87`) is `(cos p · sin y, sin p, cos p · cos y)`, so `atan2(x, z)` recovers `y` whenever `cos p > 0` — guaranteed, because `_maxPitch = π/2 − 0.05` (`:80`) keeps `|pitch| < π/2`. And `asin(y) = asin(sin p) = p` on that same range. So all seven of the brief's test directions round-trip exactly, including the pole-adjacent `Vec3(1, 0.001, 1)` and the `(0, 0, -1)` case where `yaw = π` and `forward.x` is 1.2e-16 (inside the 1e-9 tolerance). Had `forward` used a `-cos(yaw)` or `yaw`-from-`-Z` convention, `atan2(x, z)` would have needed a sign flip and test 1 would have failed for a reason the brief never mentions.
- **Test 2's clamp assertion holds with room to spare:** `asin(1) = π/2` → `clampPitch` (`:97-100`) → `π/2 − 0.05` = 1.5208 rad, which is `lessThan(π/2)` and gives `forward.y = sin(1.5208) = 0.99875 > 0.99`.
- **Test 4's zero-vector guard holds:** `Vec3.normalized` (`core/vec3.dart:22-25`) returns `const Vec3(0, 0, 0)` for a zero vector rather than NaN, so `d.length <= 0` fires and `yaw` is untouched. `forward` is a unit vector by construction, so `length ≈ 1` ✓.
- **Every field the test mutates is mutable:** `double yaw` `:65`, `double pitch` `:68`, `double fovDegrees` `:73`, `CameraMode mode` `:74`, `Vec3? eyeOverride` `:77` — all non-`final`. `camera3d.dart` imports only `dart:math`, `flutter/widgets.dart show Offset`, and `core/vec3.dart`, so the plain `test()` file needs no widget binding and has **no unused imports**.
- **Step 6's FOV comment is true, verified line by line.** `_onScaleUpdate`'s pinch branch (`galaxy_map_3d_page.dart:130-139`) gates the FOV change on `_camera.mode == CameraMode.cockpit` at `:133` and changes `distance` in the else branch, so `fovDegrees` only ever moves in cockpit mode; `_initCamera` sets it to 60 (`:108`), and `placeCamera` is passed the current value (`:74`, `:331`) rather than resetting it. Therefore the other two modes always see `fovDegrees == 60` and `k = 0.006 * (60/60) = 0.006` — unchanged, as the comment claims. The clamp is `30.0, 95.0` exactly as stated. `const k = 0.006;` is at **`:117`**, matching the brief.
- **`_c` is `late final GameController _c;` (`:33`)**, so Step 7's `_c.cockpitRequested` / `_c.acknowledgeCockpitRequest()` compile as written. `_setMode(CameraMode mode, Size2 vp)` at `:285` matches the call in the post-frame callback, and `_setMode` already `return`s early when the mode is unchanged — so the handler's own mode check at Step 7 is belt-and-braces, not a duplicate-work bug.
- **`Size2` is in `camera3d.dart:127`**, and `_setMode`'s body confirms it needs `vp` for the overview distance — the brief's reason for calling the handler from inside the `LayoutBuilder` is sound.
- **Anchors, find by name:** `_onScaleUpdate` **`:113`** ✓ (brief: 113), `const k` **`:117`** ✓ (brief: 117), `build` **`:417`** ✓ (brief: 417), `_aimCockpitAtOrigin` **`:300`** (brief: 298), `_recenter` **`:307`** (brief: 305), `_SideControls` **`:496`** (brief: 494), `onRecenter` field **`:505`**, `_RoundButton` **`:551`**.
- **Step 5's `build` change is a no-op as written** — `onRecenter: () => _recenter(vp)` is already there at `:427`. The real change is inside `_recenter` itself, dispatching on mode. Worth knowing so the implementer does not hunt for a diff that does not exist.

**Two brief defects, and one mild imprecision:**

1. **Step 8's "remove any `skip` you added in Task 12 Step 9" is now moot, and its replacement instruction is missing.** I ruled against `skip` in Task 12, so no `skip` exists. Task 14 must instead **add** the cockpit-label assertion to `cruise_ui_test.dart` — `expect(find.text('星图 · 座舱视角'), findsOneWidget)` after the tap, with a comment recording that it pins the request and the mode change but not the tab (see the correction above). Otherwise the assertion is lost entirely: dropped from Task 12 on my ruling and never added by Task 14.
2. **Step 9's `git add` omits `starward/test/cruise_ui_test.dart`**, which Task 14 now edits. The commit would leave the new assertion unstaged.
3. **Mild imprecision in Step 6's comment, parked rather than fixed.** The clause "which keeps a star that was under the finger under the finger" is exactly true only in the linear small-angle limit; the precise factor is `tan(15°)/tan(30°) = 0.464`, not `0.5`. The verifiable claims in the same comment (factor 1 at 60°, half the turn at 30°, only the cockpit changes FOV, 30–95 clamp) are all true. **Ruling: park.** It is a stated design intent with an 8%-at-the-extreme approximation, not a number the code contradicts, and a fix round over a rationale clause costs more than the clause. **Cost if wrong:** a reader could take the linear model as exact and be surprised by the residual at the clamp limits.

### Task 12 implemented (`3496cf5`), review dispatched — do NOT re-dispatch this task

`3496cf5`, 3 files, +237/−57: `journey_page.dart` (the bulk), `home_shell.dart`, new `test/cruise_ui_test.dart` (111 lines, 4 tests). Whole suite **281 passed / 0 failed** (up from 277); `flutter analyze` → `No issues found!`; `git status` clean; only the three intended files staged. Review package `review-65c7d37..3496cf5.diff` (24364 bytes) written from BASE `65c7d37`.

**The implementer corrected me three times, and all three are right. Recorded because two of them change what the plan's other tasks must know.**

1. **My correction-2 diagnosis was wrong, and the truth is broader. `StarfieldBackground` calls `..repeat()` unconditionally in `initState` (`starfield.dart:97`), so `pumpAndSettle` never settles on *any* screen carrying a starfield — parked tests 1–2 included, not just the moving tests 3–4.** I verified this myself: `_controller = AnimationController(...)..repeat();` with no guard on `scrollSpeed`. My instruction (bounded pumps) was right, but I attributed the hang to the `needsTimer` ticker and told the implementer tests 1–2 were unaffected by it. **This is the sixth instance of my recurring error shape** — I verified "braking_test warns against pumpAndSettle here" and "tests 3–4 have the ticker running", then asserted the ticker was the cause without checking. The real cause is a different and wider mechanism. **Consequence for the plan: any future task whose brief uses `pumpAndSettle` in a widget test over a screen with a starfield is broken regardless of whether the ship is moving** — Task 14's Step 8 re-runs `cruise_ui_test.dart` and is unaffected, but this belongs in the final review as a plan-level trap.
2. **My correction-3 prediction that test 4 "fails against the code as it stands" is only true of the brief's `findsOneWidget` version.** Once my own ruling mandates `findsNWidgets(2)`, test 4 passes unmodified, because both `滑行中` surfaces already existed for a coasting ship. So **test 4 is a regression guard, not a failing-first test** — tests 1–3 are the genuine TDD ones. My phrasing implied the corrected test would still fail; it does not.
3. **A third defect that neither the brief nor I caught: test 4 exhausts the tank, which queues a fuel-out drift report whose modal sheet absorbs the `航行` tap — so `滑行中` found 0 widgets, not 2.** Fixed with `await c.acknowledgeDriftReport();` before pumping, verified by probe. This is the `_pendingDriftReport` mechanism surfacing in a widget test for the first time, and it is the kind of thing only running the test finds.

**Carried forward:** per correction 4 the implementer dropped the `星图 · 座舱视角` assertion and narrowed test 2 to `'tapping it asks the star map for the cockpit'`, keeping `expect(c.cockpitRequested, isTrue)`. **Task 14's dispatch must add that assertion** (already recorded above). The implementer also kept `_steerFromCockpit`'s doc verbatim per the brief while flagging that it describes Phase 4 intent — I have asked the reviewer to assess whether its present-tense claims are true today.

Task 12 review dispatched on `sonnet` (agent `a9b03fd2bd45209bf`) with the package, the brief, the report, the global constraints, the five rulings above marked as do-not-report, and a list of six specific mutation probes to run — including whether `findsNWidgets(2)` pins agreement or merely a count, whether `acknowledgeDriftReport()` is load-bearing, whether `needsTimer`'s and `hasJourney`'s `isCoasting`→`hasMomentum` changes are pinned at all, and whether `_steerFromCockpit`'s present-tense doc claims are true today. Instructed to revert every probe and leave `git status` clean. **Do not touch repo files while it runs.** Tasks 15 and 16 briefs pre-extracted to `task-15-brief.md` and `task-16-brief.md` for pre-flight after this review closes.

### Task 12 review: spec COMPLIANT, quality ACCEPT, zero correctness defects — five findings

Review at `task-12-review.md` (160 lines). **`flutter test` → 281 passed / 0 failed; `flutter analyze` → `No issues found!` (3.7s)**, both re-run by the reviewer on a clean tree. No rule added to the controller; no unused import; all mandated strings and both mandated interfaces present verbatim; the only departures are my four dispatch corrections. Six mutation probes run, all reverted, `git diff` empty afterwards. A 16-row claim-by-claim truth table was produced — **14 of 16 claims true**, which is the highest rate any task on this plan has achieved.

**Confirmed by probe, so no later reviewer need re-derive them:** `findsNWidgets(2)` **does** pin agreement rather than a count (probe A: headline `巡航中` with subtitle `滑行中` → finds 1, fails — so my correction-3 ruling did what I intended); `await c.acknowledgeDriftReport()` **is** load-bearing (probe B: removed → 0 widgets + tap-miss warning, exactly as the implementer described); `_DriftDock`'s `onIgnite` wiring is pinned, not a no-op (probe E1); the `starfield.dart:164` "static offset" citation is true; the `0.07 EN/s` derivation is real; `_pumpVoyage`'s doc is accurate for the reason the implementer gave. Also resolved a worry of mine: `find.text('航行')` **does** resolve uniquely at tap time in `_pumpVoyage`, because at index 0 the `IndexedStack` hides the `JourneyPage` whose `_TopBar` also renders `航行` — and `widget_smoke_test.dart` taps `find.text('航行').last` for that same reason. **This also means the `IndexedStack`-hides-children reasoning I used in my Task 14 correction needs care: hidden children are excluded from hit-testing but their text is still findable, which is why the cockpit label will be findable from any tab.** That is consistent with the correction I recorded, not in conflict with it.

**Five findings, all inherited from the brief's design rather than implementer error:**

- **F1 (test-strength, most severe) — `needsTimer`'s `isCoasting` → `hasMomentum` is unpinned.** Reverting `journey_page.dart:104` leaves the suite green at 281 (probe C). It matters because `tick()` has **exactly one caller in all of `lib/`** — that timer — and `tick()` is the only `_reconcileCruise` caller. So the line is the sole driver of a cruise's fuel-out resolution. **Fixed in the round below.**
- **F2 (test-strength) — the tab badge's `isCoasting` → `hasMomentum` is unpinned.** Reverting `home_shell.dart:75` also leaves 281 green (probe D) — the exact bug Step 8 exists to fix. **Fixed in the round below.**
- **F3 (comment-only) — `_steerFromCockpit`'s doc is false at HEAD.** `igniteCruise` has no UI caller, `turnCostFor` has no caller anywhere in `lib/`, `cockpitRequested` is consumed nowhere, and the reticle is not drawn. **The reviewer guessed this becomes true in Task 14; I checked the extracted briefs and it is actually Task 16** (`task-16-brief.md:8` consumes `igniteCruise`, `correctHeading`, `turnCostTo`; Task 15 is the HUD painter and `headingLabel`). Brief mandated the text; brief is wrong; **fixed in the round below.**
- **F4 (test-strength, minor) — the `ShellScope.go(context, 0)` navigation is unpinned** (probe E2). Already ruled and deferred to Task 14. **Parked.**
- **F5 (comment-only, minor) — `_CoastDock`'s class doc is stale** (`journey_page.dart:737-739`, "while the ship is coasting … since the tank emptied") because the dock now also renders while cruising. Pre-existing text the diff did not touch. **Fixed in the round below.**

**A sixth item the reviewer listed as an observation, which I am ruling into scope.** `_brakeCoast` (`journey_page.dart:222-236`) opens a dialog titled `停止滑行` with the line `本次滑行 $summary` — reachable while **cruising**, since `_CoastDock` routes the 制动停下 button there from both states. **I verified the plan never mentions this copy and no later task fixes it** (`grep` for `停止滑行`/`本次滑行`/`停止巡航` across the whole plan returns nothing), so it would ship. This is the one place the 滑行/巡航 vocabulary split the task built everywhere else — `巡航中`/`滑行中`, `已巡航`/`已滑行`, `修正航向`/`改变航向` — was not extended, and it is user-visible. **Ruling: fix it, in this round.** `_brakeAndChangeCourse` (`:238`) is **not** affected: it is reachable only when not cruising, because `_CoastDock` routes `onPressed: cruising ? onSteer : (canBrake ? onChangeCourse : null)`. **Cost if wrong:** one extra string change in a UI file, against shipping a dialog that calls a cruise a coast in the one feature whose entire point is that distinction.

**Parked with a ruling: the reviewer's row-14 note that test 4's `reason: 'precondition: out of power'` is loose** — the tank actually holds the 100 EN braking reserve, and the ship is out of *spendable* power. The reviewer judged it defensible, and the in-game copy for that state is itself `燃料已尽`, so "out of power" matches the game's own fiction for an exhausted tank. **Cost if wrong:** one `reason:` string slightly overstates; no behaviour depends on it.

Fix round 1 dispatched to the same implementer (agent `ad59d395a15983b4e`), carrying F1, F2, F3, F5, F6 with the explicit instruction to re-run its own revert-probes for F1 and F2 and confirm both new tests fail without their line — a test that passes both ways is the defect F1 describes. F4 and the row-14 note are marked do-not-touch.

### SUPERSEDES the Task 12 correction above: the cockpit-label/navigation question is UNRESOLVED, and I am not ruling on it until a probe settles it

The correction I wrote above — "the cockpit label does not pin the navigation, because `IndexedStack` builds every tab" — **rested on an unchecked assumption about Flutter's finders, and the evidence now points the other way.** I am withdrawing the claim rather than replacing it with a second guess. **This is the seventh instance of my error shape on this plan, and the worst one: I "corrected" a claim that was probably right.**

What I established by reading the Flutter SDK (read-only, outside the repo):

- `IndexedStack` is a `StatelessWidget` (`indexed_stack.dart:41`) whose `build` wraps each child in `_VisibilityScope(isVisible: i == index, child: ExcludeFocus(...))` (`:103-110`) and returns a `_RawIndexedStack`.
- **`_VisibilityScope` (`:504-513`) is a plain `InheritedWidget` that overrides nothing — in particular not `debugVisitOnstageChildren`,** which is the hook `Finder`'s `skipOffstage` traversal uses. On that reading, non-selected children **are** visited by `find.text` and their text **is** findable from any tab, which is what I assumed.

What contradicts it:

- `_pumpVoyage` (`test/cruise_ui_test.dart:38`) taps a **bare** `find.text('航行')` while the shell is at index 0, and `_TopBar` renders a `Text('航行')` in every one of its three states (`journey_page.dart:~600`, the const title). `WidgetController.tap` throws `ambiguously found multiple matching widgets` on more than one match, so at that instant the finder resolves to exactly **one** — which is only possible if the hidden `JourneyPage` is skipped.
- `widget_smoke_test.dart:26` asserts `findsWidgets` (≥1, not exactly 1) for `航行`, and `:31` taps `find.text(label).last` for every tab. Both are *consistent* with a unique match, so they are defensive rather than decisive — I note them because they are the kind of loose assertion that would otherwise be read as evidence.

**So I have two readings that cannot both be right, and reading further will not settle it.** The question is decisive for Task 14: if hidden children are skipped, `expect(find.text('星图 · 座舱视角'), findsOneWidget)` after the tap pins **both** the request→mode change **and** the navigation, and my original Task 12 ruling was correct; if they are not skipped, it pins only the request→mode change and the navigation stays unpinned as I "corrected" it to say.

**Ruling: settle it empirically before Task 14 is dispatched, with a throwaway probe test that asserts the count of a string known to exist only inside a hidden tab.** The probe is cheap and decisive: `expect(find.text('航行'), findsNWidgets(2))` at index 0 vs `findsOneWidget`. It must run on a clean tree, so it is **deferred until the fix round below finishes** — the implementer is mutating `journey_page.dart`, `home_shell.dart`, and `cruise_ui_test.dart`, and an untracked probe file would appear in its `git status`. **Cost of deferring:** one probe, run in a few minutes. **Cost of guessing:** I would write an unpinnable assertion into Task 14's dispatch and tell the final reviewer a false thing about coverage, having already told it the opposite once.

### RESOLVED — the reviewer was right, my "correction" was wrong, and my ORIGINAL Task 12 ruling stands

Settled from Flutter's own test suite, which pins the behaviour outright rather than leaving it to inference. `packages/flutter/test/widgets/indexed_stack_test.dart:50-55`:

```dart
expect(find.text('$i', skipOffstage: false), findsOneWidget); // hidden child: found ONLY with skipOffstage:false
expect(find.text('$i'), findsOneWidget);                      // selected child
expect(find.text('$i'), findsNothing);                        // non-selected child — SKIPPED
```

and `:180-190`, where `find.byType(Text)` (default `skipOffstage: true`) finds only the visible child while `find.byType(Text, skipOffstage: false)` finds all five.

**So non-selected `IndexedStack` children are skipped by default finders.** Consequences, all of which now need recording because I got them backwards:

1. **My original Task 12 ruling was CORRECT and is restored:** once Task 14 lands the mode change, `expect(find.text('星图 · 座舱视角'), findsOneWidget)` after the tap requires the star map to be **onstage**. It therefore pins the request→mode change **and** the navigation together. The cockpit label only appears when the star map is both selected *and* in cockpit mode.
2. **My "correction" is WITHDRAWN as wrong.** I asserted the label would be findable from any tab because "`IndexedStack` builds every tab", and that was the basis for telling the reviewer not to count the navigation as pinned. It is not findable from another tab.
3. **F4 is therefore not a permanent gap — it is closed by Task 14's assertion, not parked.** Probe E2 (deleting `ShellScope.go(context, 0)`) leaves the suite green *today* only because Task 12 asserts just `cockpitRequested`; once Task 14 adds the label assertion, that same deletion makes the assertion fail, because the star map never becomes onstage. **Task 14's dispatch must state this**, and the final review must not be told the navigation is unpinned.
4. **The reviewer's reasoning was right and I overrode it.** It said "at index 0 the `IndexedStack` hides the `JourneyPage` (whose `_TopBar` also renders `航行`), so only the nav label matches" — a correct explanation of the unique tap. I replaced it with an SDK-source reading that was wrong.

**The lesson, and it is a new shape: I reasoned from Flutter's source (`_VisibilityScope` is a bare `InheritedWidget` with no `debugVisitOnstageChildren` override) and concluded a behaviour, when the framework's own tests state the behaviour directly.** Reading an implementation is not the same as checking its contract, and I did not look for the test that already pins it. **The cheap move — grep the framework's tests for the widget whose behaviour you are about to depend on — is the one I skipped.** This is also the second time in this task that I overrode a correct subagent finding; the first was the `starfield.dart:97` `repeat()`, where the implementer was right and I was wrong.

**Also corrected: the `find.text('航行')`-resolves-uniquely fact I recorded earlier is right for the right reason**, and the earlier worry I logged about it (that hidden children might be findable, which would make it ambiguous) is void. `widget_smoke_test.dart`'s `.last` is defensive, not required; its `findsWidgets` is loose but not wrong.

**No probe is now needed** — the framework's own tests are the probe. Task 13's dispatch is unaffected; Task 14's dispatch gains the requirement to add the cockpit-label assertion **and** the note that it closes F4.

### Task 12 — fix round 1 — dispatched, landed at `ce5f1e4`

Fix round 1 (resumed implementer, `sonnet`), carrying F1, F2, F3, F5, F6; F4 and the truth table's row 14 marked DO-NOT-TOUCH. Commit `ce5f1e4` — "fix(starward): pin the voyage ticker and the tab badge, and stop calling a cruise a coast". Report claims **285 passed / 0 failed** (281 + 4 new) and `No issues found!`.

**Two things in the fix report are worth the controller's attention:**

1. **The implementer wrote an extra test I did not ask for** — for F6's `停止巡航`/`本次巡航` copy — on the grounds that the copy is user-visible and otherwise uncovered, and probe-checked it falsifiable. That is the right call and I would have asked for it had I noticed; F6 was ruled into scope precisely because the copy would otherwise ship unobserved. Recording it as an accepted scope addition, not a departure.
2. **The implementer's claim that the new F1 test needs no `acknowledgeDriftReport()` appears to contradict Probe B**, which proved that call load-bearing for test 4. The implementer's explanation is that the new test's fuel-out sheet is queued *after* the `航行` tap while test 4's is queued *before* it. I have read both tests and the ordering difference is real and sufficient: test 4 calls `c.tick()` directly at `:95` and then pumps, so the modal is up when `_pumpVoyage` taps; the new test pumps first, then advances the clock and lets the on-screen ticker resolve the burn. **The two tests are consistent, but the distinction lives only in the code's ordering, not in any comment** — which is exactly the kind of unstated premise this plan keeps punishing. I have asked the re-reviewer to settle it independently rather than take my reading.

**Ruling: the fix round's re-review is scoped to the five findings plus these two doubts — no fresh full review.** The full review already ran and returned 14/16 claims true; re-running it would spend a review seat to re-derive what is on the record. — **Cost if wrong:** if the fix introduced breakage outside the five findings' blast radius, it is caught at the final whole-branch review instead of here.

### Task 13 pre-flight — "Turning a moving ship" (brief `task-13-brief.md`)

**Verified against HEAD `ce5f1e4`, so the implementer need not re-derive:**

- **All seven pinned turn prices are exact** against `energyCostFor`'s `.round()`: `turnCostFor(θ) = energyCostFor(80·sin(θ/2))`, so 5°→8.72→**9**, 10°→17.43→**17**, 30°→51.76→**52**, 60°→100→**100**, 90°→141.4→**141**, 120°→173.2→**173**, 180°→200→**200**. `brakingCost` = `energyCostFor(40)` = **100**. `turnCostFor(0) == 0` via the `radians <= 0` guard (`engine.dart:121`).
- **The crossover test's three-way boundary is right:** 59.5°→99.24→**99** `< 100`; 60°→**100** `== 100`; 60.5°→100.75→**101** `> 100`.
- **`energy` (`game_controller.dart:456`) is the *live* balance** — it subtracts the accrued-but-unbooked burn (`_cruiseBurnNow()`) and clamps at 0. That is what makes the guard `energy < cost` (brief `:306-309`) quote a budget the player still has, and what makes `expect(c.energy, 200)` at brief `:130` hold with no `tick()`. Confirmed by reading the getter, not inferred.
- **`_repinLeg({Vec3? velocity, DateTime? at})`** (`:345`) — the named `at:` argument the brief uses exists.
- **`driftPowered` round-trips through the save** (`player_state.dart:194` toJson, `:173` fromJson with a `false` fallback), so the reload test's `isCruising` claim holds.
- **`EnergyTxType.turn` exists** (`energy_transaction.dart:16`); `EnergyTransaction`'s ctor is `{id, type, amount, createdAt, relatedObjectId?}` — the brief's call matches.
- **No unused imports in the brief's test file** — every one of the nine is used. (Task 12's `dart:convert` was the counterexample; this file is clean.)
- **Step 4's "all fourteen" is correct:** 5 in `the turn price` + 9 in `correctHeading`.
- **`_cruising`'s `FuelPolicy.coast` doc is true and load-bearing:** `halt` zeroes the velocity at exhaustion, which would make `hasMomentum` false and every `correctHeading` in tests 7–9 refuse.

**THE TWENTIETH FINDING — and it is not Task 13's invention, it is a pre-existing false claim Task 13 is about to copy.**

Step 3's mandated comment (brief `:342-343`) reads *"`_syncDormancy`'s contract is that **no rule** can spend the last drop without the shutdown following."* That phrase is quoted from `_syncDormancy`'s own doc at `game_controller.dart:1182` — *"Called at the end of every settlement that moves energy, so **no rule** can spend the last drop without the shutdown following."* **Both are false.** `activate` (`:1212`) is a rule that spends, can spend the last drop (`energyBalance == 5`, `cost == 5` → 0), and deliberately does **not** call `_syncDormancy` — documented twenty lines below at `:1204-1211` as exactly what the user asked for. The true contract is about **settlements**, and the doc's own next sentence (`:1183-1186`) already talks in terms of settlements.

**Ruling: correct both comments, in the same file Task 13 already edits.** — **Why:** fixing only Task 13's new comment would leave it saying "no settlement" directly beside `_syncDormancy`'s doc saying "no rule", i.e. two adjacent comments contradicting each other, which is worse than either alone and will be copied again by the next task. The plan never mandated the `_syncDormancy` doc text, so this is a controller ruling, not a plan departure. — **Cost if wrong:** two comment-only edits in a file already in the diff; no behaviour change, trivially revertible. **Mandated wording is in the dispatch**, so the implementer transcribes rather than invents.

**Two corrections to my own earlier notes:**

1. **The `_nearby`-staleness observation does NOT apply to Task 13** and must not be carried in its dispatch. None of `turnAngleTo`, `turnCostTo`, or `correctHeading` reads `_nearby` — they read `driftVelocity`, `engine`, and the ledger. The staleness concern belongs to the cockpit consumer, **Task 16** (the task that draws a marker from `recommendedDestination`). My earlier note routed it to the wrong task; correcting it here so it lands in Task 16's dispatch instead.
2. **`igniteCruise` is at `:1295`, not `:1245`.** The brief anchors by *name* ("add after `igniteCruise`"), which is the right way to anchor; treat every line number in the brief as a hint to re-locate by name.

**One number I am deliberately NOT asserting a correction for:** the crossover test's comment claims *"59.5° is 99.23 EN"*. My hand derivation gives 99.24, and I cannot separate 99.23 from 99.24 without running it — so I am **not** telling the implementer it is wrong. The dispatch instead asks it to verify both illustrative numbers (99.23 and 100.75) against the code and correct any that are off, which puts the check where it can actually be run. **This is the discipline that stops a ninth instance of my error shape: I do not get to "correct" a number from arithmetic I cannot verify.**

### Task 12: COMPLETE — `3496cf5` + fix `ce5f1e4`

**Re-review of fix round 1 (`task-12-rereview.md`): all five findings ADDRESSED, no new Critical/Important breakage.** F1 pinned by a new test asserting `c.isCoasting` — the exact state `journey_page.dart:104` controls; F2 pinned by `Key('voyage-tab-badge')` (`home_shell.dart:156`) plus two tests; F3's doc reworded to intent; F5's `_CoastDock` doc now covers both states; F6's copy switches on `c.isCruising` (`journey_page.dart:231,233`) with a new test. **F4 (`ShellScope.go`, `journey_page.dart:211`) and test 4's loose `reason:` (`cruise_ui_test.dart:96`) confirmed untouched**, as the ruling required.

**Fix scope verified by the controller independently:** `git show --stat ce5f1e4` touches exactly `journey_page.dart`, `home_shell.dart`, `cruise_ui_test.dart` — no controller change, layer discipline intact.

**Doubt 1 resolved, and it corrects my own reading.** I had explained the two tests' difference as "the barrier absorbs the tap". The re-reviewer's account is the same story told one step further: the absorbed tap means the tab **never switches**, so `JourneyPage` stays offstage and the finders see 0 widgets. The new test taps first, so its sheet opens with the page already onstage — and `showModalBottomSheet` is a non-opaque `PopupRoute`, so the page below stays onstage. The two tests are consistent and the ordering difference is real and sufficient. **This also confirms the ledger entry above from the other direction: the `IndexedStack` offstage rule is what makes both the modal-barrier story and Task 14's cockpit-label assertion work.**

**Two minors parked for the final review — ruling: do not spend a second fix round on them.**
1. **The new F1 test never mentions the fuel-out sheet** that opens mid-test, so a future reader meets exactly the confusion this fix round was spent resolving (the re-reviewer's own words: "only a doc gap"). — **Ruling: park.** It is a missing explanation, not a false claim, so it is outside the defect class this plan keeps finding; and it lives in `cruise_ui_test.dart`, which Task 13 does not touch, so folding it into Task 13's commit would muddy that task's review surface. — **Cost if wrong:** one future reader re-derives the ordering distinction, once.
2. **F1's `reason:` tail, "the ship cruises on forever", is rhetorical.** — **Ruling: park, and not a defect.** It is *true*: without `tick()` the burn is never resolved and the ship does cruise indefinitely. Vivid is not false.

Both go to the final whole-branch review as deferred minors with these rulings, to be batched into the final fix dispatch if that review judges them worth it.

**Task 12 summary: 3 findings fixed, 1 ruled into scope and fixed, 2 minors parked, 1 deferral (F4) closed by Task 14. Test count 281 → 285.**

### Task 14 pre-flight — "The cockpit can be asked for, and can be aimed exactly"

Verified against HEAD `ce5f1e4`. Task 13 touches neither file, so these anchors hold for Task 14's dispatch.

**FINDING 1 (the one that matters): `Vec3` has no `operator ==`** (`lib/core/vec3.dart` — `+ - * dot cross length normalized` and `static const up`, nothing else). The brief's Step 1 test asserts `expect(camera.eyeOverride, const Vec3(5, 6, 7))`. That **passes**, but only because `Vec3`'s constructor is `const` and Dart canonicalises the two identical `const` expressions into one instance — so it is an *identity* comparison that reads like a value comparison. **Ruling: keep the test but make it say what it means** — bind `const eye = Vec3(5, 6, 7);`, assign that, and assert `identical(camera.eyeOverride, eye)`. Do **not** add `operator ==` to `Vec3`: it is a `core` model used elsewhere, and value equality could silently change `Set`/`Map` behaviour in code this task has no business touching. — **Cost if wrong:** one test line phrased more explicitly than the plan wrote it.

**FINDING 2: every page anchor in the brief's header is stale by exactly 2 lines, and `build` is stale by 52.** Actual: `_setMode` **:285** (brief :283), `_aimCockpitAtOrigin` **:300** (:298), `_recenter` **:307** (:305), `_SideControls` **:496** (:494), `build` **:365** (:417). `_onScaleUpdate` **:113** is correct. **Anchor by name, not by number.**

**FINDING 3: Step 5's `build` change is already in place.** `onRecenter: () => _recenter(vp)` is at **:427** exactly as the brief mandates. The only Step 5 edit with content is `_recenter`'s body and `_SideControls`'s `label:`/`onTap:`.

**FINDING 4: Step 8's "remove any `skip` you added in Task 12 Step 9" is moot** — `cruise_ui_test.dart` contains no `skip` (read in full; 8 tests, none skipped).

**FINDING 5: Step 9's `git add` omits `starward/test/cruise_ui_test.dart`.** Task 14 must add the cockpit-label assertion to that file (see FINDING 6), so the file has to be staged. Correcting the plan's command.

**FINDING 6: ADD the cockpit-label assertion, and it closes F4.** In `cruise_ui_test.dart`'s test `'tapping it asks the star map for the cockpit'`, after the tap, add `expect(find.text('星图 · 座舱视角'), findsOneWidget);`. Per the resolution recorded above, default finders **skip non-selected `IndexedStack` children**, so this label is findable only when the star map is both **onstage** (→ the `ShellScope.go` navigation happened) and **in cockpit mode** (→ the request was consumed). It therefore pins **both halves** of `_steerFromCockpit`, and F4 stops being an unpinned gap. **It needs at least one further bounded pump** before the assertion: `_maybeEnterRequestedCockpit` defers `_setMode` to a post-frame callback, whose `setState` only renders on the *next* frame — so a single `pump` shows the old label. Never `pumpAndSettle` (the starfield's `..repeat()` at `starfield.dart:97` means the tree never settles on any starfield screen).

**Checked and TRUE — no correction needed, superseding my own earlier "parked imprecision" note about Step 6:**

- **Step 6's comment is accurate.** `_onScaleUpdate` has `const k = 0.006` at `:117`; the pinch branch gates FOV on cockpit mode (`:133`) and distance otherwise (`:136-137`); `_initCamera` (`:100`) sets `..fovDegrees = 60` and starts in `CameraMode.orbit`; the clamp is `30.0–95.0` exactly as the comment says. So non-cockpit modes always get `k = 0.006 * (60/60) = 0.006`, and at 30° the drag turns half as far. My earlier note calling this imprecise was wrong; withdrawing it.
- `placeCameraForRoute` **:236** — Step 3's insertion anchor exists.
- `LayoutBuilder` **:374**, `final vp = Size2(size.width, size.height)` **:377** — Step 7's insertion point is real.
- `import 'dart:math' as math;` **:1** — Step 4's `math.atan2`/`math.asin` resolve.
- `_SideControls` declares `mode`, `onSelect`, `onRecenter` (`:496-506`) — Step 5's `mode == CameraMode.cockpit` compiles.
- `_RoundButton` takes `icon`, `label`, `onTap`, `selected` (`:552-557`) — Step 5's edit compiles.
- `cockpitRequested` getter **:1013**, `acknowledgeCockpitRequest` **:1028** — the brief's Consumes list is satisfied.
- `_maxPitch = π/2 − 0.05` (`camera3d.dart:80`), so Step 1's pole test holds: `forward.y = cos(0.05) = 0.99875 > 0.99`.
- Step 5's rationale is true: `placeCamera` only sets `eyeOverride` in cockpit mode, so a recenter there would be a button that visibly does nothing.

### CORRECTION — Task 13's `does not teleport` test, and the false claim in my own pre-flight above

**The implementer returned NEEDS_CONTEXT, correctly, and did not commit.** The brief's `correctHeading > does not teleport the ship` test asserts absolute coordinates — `expect(c.playerPosition3D.x, closeTo(40, 1e-6))`, `expect(c.playerPosition3D.z, closeTo(0, 1e-9))` — which silently assumes the ship spawns at the origin. **It does not.** `_boot` passes no `spawn:` override (brief `:34-42`), so the default spawn decides, and under `math.Random(3)` it lands at `(0.22204, −0.06797, 0.08828)`. The test fails at its **first** assertion (`x` reads `40.22204`, ~8× the `1e-6` tolerance) before `correctHeading` is even called. All six of its position expectations are off by the spawn offset.

**CORRECTING MY OWN PRE-FLIGHT ENTRY ABOVE.** It reads: *"**Test 2's geometry is right:** 1500 s at 1/37.5 ly/s = 40 ly east; 375 s = 10 ly along the new +Z heading; **x stays 40** because `_repinLeg` moves the anchor to the turn point."* **"x stays 40" is false** — x is `spawn.x + 40`. I confirmed the arithmetic (40 ly, 10 ly), confirmed the *mechanism* (`_repinLeg` re-pins the anchor), and then wrote "is right", lending the controller's authority to a claim whose baseline I never checked. **The distances were all correct; the starting point was not, and it is the one input the whole test rests on.**

**This is a new shape of my recurring error, and worth naming:** not asserting an unchecked link between two verified facts, but **verifying a computation's internal consistency while never examining its input.** Every number I checked was right, and every number I checked was *relative* — so the error could not surface from inside the arithmetic. And I had read the brief's `_boot` (no `spawn:` override) earlier in this same pre-flight without connecting it. **The check I owed was one line: what is `playerPosition3D` at boot?** Eighth instance on this plan.

**The implementer's diagnosis is sound and self-consistent**, and it proved the fix rather than asserting it: with the spawn pinned to the origin in a scratch copy, all fourteen brief tests pass; it then removed the scratch file. It also caught that the crossover comment's *"59.5° is 99.23 EN"* was wrong — verified 99.2433, so **99.24** is right. That vindicates the discipline recorded above: my hand derivation said 99.24 and I declined to assert it, asking the implementer to verify instead. The estimate matched; the point is that I did not get to write "wrong" on a number I could not compute.

**RULING: rewrite the test to measure displacements from the spawn.** Bind `final start = c.playerPosition3D;` **before** ignition, and assert `closeTo(start.x + 40, …)`, `closeTo(start.z, …)`, `closeTo(start.z + 10, …)`. This keeps **every** numeric claim the brief made — 40 ly east in 1500 s, no movement at the turn, 10 ly along the new +Z heading in 375 s, x frozen after the rotation — while removing the false premise, and it follows the repo's own idiom for exactly this (`cruise_test.dart:517,526` measures `(c.playerPosition3D - start).length`; `braking_test.dart:321,336` captures `parked` and compares components to it). — **Cost if wrong:** the test's absolute numbers become relative ones, which is strictly more robust; nothing else changes.

**Two alternatives considered and rejected:**
- **Pin the spawn to the origin** via `GameController`'s `SpawnStrategy? spawn` (`game_controller.dart:53`) — it works, the implementer proved it, but it would change `_boot` for **all fourteen** tests, widening the blast radius to tests with no spawn dependency and hiding any real spawn-dependent defect in them. A test file that overrides the spawn is also testing a different world from the one the game boots into.
- **Re-derive the absolute numbers** (`40.22204` …) — brittle: they come from a generated universe under a fixed seed and would break on any spawn change, buying nothing.

**The other thirteen tests are unaffected** — none asserts an absolute position — which is exactly what the implementer's `13 passed / 1 failed` shows. Full suite at that point: **298 passed / 1 failed** (285 + 14 = 299 ✓).

### Task 13 — implemented at `f6b555f` (BASE `ce5f1e4`), review in flight

`feat(starward): let a moving ship change course for the price of the turn`. Two files, 342 insertions / 5 deletions: `game_controller.dart` (the three new members plus the two mandated comment corrections) and the new `heading_test.dart` (fourteen tests). Report claims `heading_test.dart` 14 passed / 0 failed, **full suite 299 passed / 0 failed**, `No issues found!`.

**The implementer mutation-probed the assertion I added in the ruling** — replacing the velocity rotation with an addition makes the final `x` assertion fail (`x = 50.22`), so that assertion is falsifiable and pins "rotated, not added to". That is the one assertion the brief's version *could not* have made, because its `x == 40` was already failing for the spawn reason.

**One cosmetic departure, accepted:** the mandated `_syncDormancy` doc replacement re-wrapped the following paragraph to the file's ~78-column width, because the merged form would have produced a 99-character line. The text is verbatim; only the wrap differs. Not a defect — the mandate was about the claim, not the line breaks.

**Reviewer model: `opus`, deliberately above the plan's usual reviewer tier.** This is the rules engine — the file where `CLAUDE.md` says all rules live — and the semantics under review are the plan's subtlest: the guard reads the *live* balance, then `_settleCruise` runs, then the deduction, then `_syncDormancy`, with `energy == cost` deliberately permitted. A defect already slipped past both the brief's author and my own pre-flight on this task, so the review seat is worth the tier.

**Task 13 scope verified by the controller independently:** `git show --stat f6b555f` touches exactly `game_controller.dart` (83 insertions) and `heading_test.dart` (264 insertions); **no** file under `models/`, no repository, no save-key change. Layer discipline and the migrate-don't-bump rule both hold.

**In flight now:** the Task 13 task review (`opus`, mutation probes on the rules engine) and a read-only pre-flight of Task 15. The two are non-contending by construction: the reviewer may run `flutter test` and `flutter analyze`; the pre-flight was told to run neither and to stay out of `game_controller.dart` and `heading_test.dart`.

### Task 15 pre-flight — delegated read-only, 8 findings, and it was worth the seat

Brief `task-15-brief.md` creates `cockpit_hud.dart` + `cockpit_hud_test.dart`, touching no existing file, so its pre-flight needed no waiting on Task 13/14. Delegating it kept the 12 KB brief out of the controller's context; the findings file is `task-15-preflight.md`. **It caught two blocking defects that would otherwise have cost a full fix round**, which is the second pre-flight in a row to pay for itself.

**Controller verified both blocking findings independently, and widened one check the pre-flight under-scoped:**

1. **`Vec3` arithmetic in `Offset` space — BLOCKING, will not compile.** In the chevron branch, `u = dir / len` is an `Offset`, so `Vec3(-u.y, u.x, 0) * 7` is a `Vec3`, and `clamped + Vec3(...)` has no operator (`Offset.operator+` takes an `Offset`); the next lines then read `left.dx`/`left.dy`, which a `Vec3` does not have either. **Confirmed by reading the brief (`:250-256`).** Mandated fix: `Offset(-u.y, u.x) * 7` and `Offset(u.y, -u.x) * 7`. The geometry is unchanged — `Offset(-u.y, u.x)` is the same 90° rotation of `u` — so this is purely a type correction, not a redesign.
2. **Unused import in the test — BLOCKING, fails `flutter analyze`.** `import 'package:flutter/widgets.dart';` supplies nothing: `Size2` comes from `camera3d.dart`, `Vec3` from `vec3.dart`, the matchers from `flutter_test`, and `math` from `dart:math`. **The pre-flight checked only `flutter_test/lib/src/` for a `widgets.dart` re-export, so I checked the top-level `flutter_test.dart` exports myself — there is none — and confirmed the test block names no `Offset` or other widgets symbol.** This is the same class as Task 12's unused `dart:convert`. Mandated fix: delete the line.

**Rulings on the other six, all comment-text fixes in a file being written for the first time, so they cost nothing to apply at transcription:**

3. **FIX** — *"insets its window by 14 and its struts by 48 / 40"* is false. `galaxy_map_3d_page.dart:704` uses 48 / 40 as the window rect's **top and bottom** offsets; the struts are a separate thing (inset 20, length 34, `:723-729`). **Worse than misattributed: the clamp does not clear the struts at all** (26 < 34 and 74 < 82), so the sentence cannot be repaired by renumbering. Mandated wording: cite the window frame only — *"Keep clear of the cockpit window frame (`_CockpitPainter` insets it by 14, and 48 / 40 at top and bottom)…"* — and make no claim about struts.
4. **FIX** — *"and of the heading bar at the bottom"* is false at HEAD: no heading bar exists, and the bottom widget is `_BottomControls` (`:599`). Mandated wording: *"…and of the bottom controls panel."* The `h - 132` bound needs no justification in the comment, so the implementer is not sent measuring a layout.
5. **NOTE ONLY, not a code change** — the brief's Consumes list names `focalFor` and `Camera3D.eye`, which the new code never references (both exist; they are simply not used). The header is an artifact, not shipped code, so the operative instruction is: **do not add code to justify the list.** The brief's Produces list is accurate.
6. **FIX** — `dx = 130.72` / `dx = 269.28` are rounded (exact: `130.71797…`, `269.28203…`). They are illustrative, not asserted, so the fix is `≈`. A number written with `=` must be exact.
7. **FIX** — the `shouldRepaint` rationale's *"markers is rebuilt from live scene positions on every frame"* describes Task 16; nothing at HEAD builds a `CockpitHudPainter`. Keep the *"`Vec3` has no `==`"* half, which is true and sufficient on its own, and drop the frame-rebuild clause.
8. **LEAVE IT** — `at.dy.clamp(74.0, size.height - 132.0)` throws when the upper bound falls below the lower, i.e. on a canvas shorter than 206 px. Not reachable, and no test builds the painter. — **Ruling: leave it, deliberately.** `camera3d.dart:270-272` documents the identical hazard for the zoom clamp, so hardening only this one would break the codebase's own precedent for a case the cockpit cannot reach. — **Cost if wrong:** a latent crash if the painter is ever mounted in a box under 206 px tall.

**The pre-flight's "Checked and found correct — do not re-derive" section is unusually valuable and the implementer will be pointed at it**, saving it from re-deriving: all six Consumes symbols with matching signatures; that the new source file's single `package:flutter/widgets.dart` import genuinely does supply `CustomPainter`/`Canvas`/`Offset`/`TextPainter`/`PaintingStyle`/`TextDirection` (via `src/widgets/basic.dart:34-35` → `painting.dart` → `src/painting/basic_types.dart:14-58`); every pinned number and tolerance exact (bearings, elevations, the `(200, 400)` dead-ahead case, `focal = 692.820323`, the sign convention, the perspective divide within 2.8e-9 of a `1e-4` tolerance, the three culling cases, the π/2 turn); the U+2212 and U+2014 character claims by hexdump; the `forward`/`atan2(x, z)` premise; the `galaxy3d_projection_test.dart:44` claim; layer discipline (no `lib/data` or `lib/state` import, and the painter's hard-coded numbers are local visual constants like `_CockpitPainter`'s own); the `CustomPainter` contract; and that every test assertion is falsifiable.

**Ruling: do NOT dispatch Task 15's implementer yet — wait for the Task 13 review to finish.** The two would not collide on files (`cockpit_hud.dart` is new; the reviewer is read-only on `game_controller.dart`), but they *would* collide on the build: both run `flutter test`, and worse, the reviewer's mutation probes temporarily mutate `game_controller.dart`, so a suite run by the implementer in that window would fail for a reason that does not exist. This extends the skill's "never dispatch multiple implementation subagents in parallel" to an implementer plus a mutating reviewer. — **Cost if wrong:** wall-clock only.

## Task 13 — review verdict (agent a2f14e343b70f3378, opus)

**Spec compliance: COMPLIANT.** All three members with exact signatures, after
`igniteCruise`; fourteen tests; both mandated comment corrections applied; additive plus two
comment blocks; no `_saveKey` bump; price from `Engine.turnCostFor`.

**Task quality: FINDINGS** — F1 HIGH, F2 MEDIUM, F3 MEDIUM, F4 LOW.

- **F1 CORRECTNESS (HIGH)** `game_controller.dart:1360-1379` — a turn taken while *coasting*
  teleports the ship. Probed: coast 500 s → `activate()` → `correctHeading(30°)` moves it
  `6.901841202733883` ly (expected 0). Reachable via coast→activate→turn.
- **F2 COMMENT-ONLY (MEDIUM)** `:1375-1378` — the block implies the trailing `_repinLeg`
  prevents that teleport; it commits it. Removing the call leaves the delta byte-identical;
  its real effect is resetting `driftStartedAt` (43 EN with, 10 without). "the original
  ignition" is wrong — the anchor is the *exhaust* point.
- **F3 TEST-STRENGTH (MEDIUM)** removing `_repinLeg(at: _now())` keeps **14/14**: no test
  turns a coasting ship. The `does not teleport` test turns at 1500 s with 3000 s of budget
  left, so it is a cruising turn throughout and its name over-claims.
- **F4 COMMENT-ONLY (LOW)** `heading_test.dart:213` — "holds only the 100 EN reserve" while
  the same test asserts `95` two lines above.

### Controller verification (mine, independent of the reviewer)

Read `_repinLeg` (`:345-352`), `_cruiseBurnNow` (`:1040-1045`), `correctHeading`
(`:1350-1387`), and **every** `_repinLeg` call site (`:1069`, `:1318`, `:1379`).

- `_repinLeg` reads `playerPosition3D` — derived from the anchor *and the current velocity* —
  and then pins what it read. Called after the `copyWith` rotates `driftVelocity`, it pins the
  position the ship would have had if it had always flown the new heading. F1 mechanism
  confirmed.
- `_cruiseBurnNow` returns 0 when not cruising, so nothing accrues during the coast; the
  `driftStartedAt` reset is what restarts the burn clock. Reproduces the second probe number
  exactly: anchor = exhaust point (t=3000), turn at t=3500 → 500 s = 500/15 = 33 EN burned,
  95 − 52 − 33 = 10 ✓ vs 43 with the pin.
- The 6.9018 ly delta reproduces exactly as 500 s × (1/37.5 ly/s) × 2·sin(15°) = 6.9018 —
  which pins the anchor at the *exhaust* point, not the ignition, confirming F2's correction.
- `:1318` (`igniteCruise`) is **not** the same bug: it passes the new velocity *into*
  `_repinLeg`, which reads the position under the old velocity first. `:1069` is inside
  `_settleCruise`. So `:1379` is the only rotate-then-pin site in the file.

**Ruling: F1–F4 are all in scope for Task 13** — the defect is in this task's own mandated
deliverable, not a plan-level defect, so it is a fix round rather than a parked finding.

**Ruling: fix F1 by moving `_repinLeg(at: _now())` above the `copyWith`**, rejecting a
rewrite of `_settleCruise`'s early return — the anchor being "stale" is by design (it is a
reference point, and `playerPosition3D` derives the true position from it while the velocity
is unchanged); only the *ordering* is wrong. — Cost if wrong: the cruising path is provably
unchanged (there `_settleCruise` has already re-pinned at `now`, so the pre-rotation read is a
positional no-op), so the blast radius is the coasting path alone — the path that is broken
today.

**Ruling: F3's regression test asserts all three position components** against a
`before` snapshot taken after 500 s of unpowered drift, with `_cruising(clock, 3000)` +
`tick()` as the setup — reusing the file's existing coasting precondition rather than
building a second one. Cost if wrong: a tighter assertion than the reviewer proposed, but the
broken path moves 1.79 ly in x, 6.67 in y and 6.67 in z, so every component fails loudly
before the fix.

Fix round **1 of 5** — resuming implementer `ab62fea3d3d870807`. BASE `f6b555f`.

### Task 14 dispatch-prep — the last unchecked input in the cockpit-label assertion, now verified

FINDING 6's mandated assertion is `expect(find.text('星图 · 座舱视角'), findsOneWidget)`.
Nobody had checked the *literal* — the whole assertion rests on it, and a mis-worded string
would fail the test and burn a fix round. Verified at `f6b555f`:

- `galaxy_map_3d_page.dart:478-483` renders the label as `switch (mode) { overview =>
  '星图 · 寰宇', orbit => '星图 · 总览', cockpit => '星图 · 座舱视角' }`. It is **exhaustive on
  `mode`**, so exactly one of the three is present at any moment — stronger than "conditional",
  and it means the assertion is a faithful proxy for `mode == CameraMode.cockpit` given the
  page is onstage.
- **No false positive from the voyage tab.** `journey_page.dart:357` contains the similar
  `'在星图 · 座舱模式中可以用准星修正航向。'` and `:732` `'方向在星图 · 座舱模式中用准星选定。'`
  — both say 座舱**模式**, not 座舱**视角**, and `find.text` matches `Text.data` exactly, so
  neither can satisfy the assertion. (Had the brief used `textContaining`, both would have to
  be re-examined.)
- The only other 座舱 occurrence is the `_RoundButton` label `'座舱'` at `:533` — a different
  string, and a *button* rather than the mode readout.

**Ruling: Task 14's dispatch carries the literal verbatim and this verification, so the
implementer transcribes rather than re-derives.** — Cost if wrong: nil; the string is pinned
to a source line.

### Task 13 — fix round 1 (`9c127a4`) — the coasting-turn teleport is closed

Commit `9c127a4` "fix(starward): pin the course-change leg before rotating the velocity",
2 files, 47 insertions / 9 deletions (`lib/state/game_controller.dart`, `test/heading_test.dart`).
`heading_test.dart` 15 passed; full suite **300 passed / 0 failed** (299 + the new test ✓);
`flutter analyze` → `No issues found!`; tree clean; HEAD `9c127a4`.

All four findings confirmed against the code and fixed as ruled. The implementer verified
rather than transcribed, and reported one correction *of my message* — worth recording because
it is the distinction I got sloppy about:

- **The 6.9018 ly figure is the displacement *magnitude*.** The component that fires first in
  the new test is **x, off by 1.786** — exactly my own derivation (13.33 ly of drift ×
  (1 − cos 30°) = 1.786 in x, 13.33 × sin 30° = 6.667 in y and z, magnitude 6.9018). So the
  x assertion is the one that catches the defect first, and the test is not relying on the
  larger y/z components. Nothing was wrong; the number needed a label.
- F2's replacement comment was verified claim-by-claim, including the energy pair (43 EN with
  the `driftStartedAt` reset, 10 without) — the anchor is the exhaust point
  (`game_controller.dart:1166-1170`).
- F3: the new test was **watched failing before the fix** (x off by 1.786) and passing after,
  and `_cruising(clock, 3000)` was confirmed to ignite with `FuelPolicy.coast`.

### Concurrent-session contamination of `test/` — carried to the final review

`starward/test/zz_color_probe_test.dart` appeared in the tree **mid-round**, written by a
**different session** (not this plan's implementer, which left it alone and did not stage it).
Its owner removed it, and the tree is clean and the 300 count excludes it.

**Why this is recorded rather than shrugged off:** a stray test file in `test/` inflates any
full-suite count taken while it exists, and this plan's evidence standard is pinned numbers.
A future reviewer reading "300 passed" needs to know the count was taken on a tree with no
foreign files — verified here by `git status --porcelain` being empty and `ls` reporting the
file absent. If a later task's count looks off by one or two, check `test/` for a foreign file
before suspecting the change. Nothing to fix; a hazard to know about.

### Task 14 — the cockpit assertion's falsifiability, established on both halves

The mandated assertion (`expect(find.text('星图 · 座舱视角'), findsOneWidget)` in
`cruise_ui_test.dart`'s `'tapping it asks the star map for the cockpit'`) is the closure of
F4, and F4's whole complaint was an assertion that pinned less than it claimed. Verified both
halves are independently falsifiable, at `9c127a4`:

- **Producer half — exists and does both things.** `_steerFromCockpit`
  (`journey_page.dart:211-214`) is `c.requestCockpit(); ShellScope.go(context, 0);`, and its
  doc states the contract: *"This only raises the request — whichever screen consumes it
  decides what to do with it."* So the tap both raises the flag and switches the tab.
- **Consumer half — does not exist yet, and Task 14 creates it.** `grep` for
  `cockpitRequested` / `_maybeEnterRequestedCockpit` / `acknowledgeCockpitRequest` in
  `galaxy_map_3d_page.dart` returns **nothing at HEAD**. Task 14's Step 7 adds the handler.
  This is the "assertion depending on a symbol another task introduces" shape the ledger has
  been watching for — benign here, because Task 14 adds the consumer *and* the assertion in
  one task, so no later task can be the missing half.
- **Therefore the assertion fails at HEAD** (the map opens in `CameraMode.orbit` from
  `_initCamera`, so the label reads `'星图 · 总览'`) and passes only once Step 7 lands.
- **Both halves are falsifiable:** deleting `ShellScope.go` leaves the map offstage, where the
  default finder skips it → `findsNothing`; deleting the mode change leaves the label at
  `'星图 · 总览'` → `findsNothing`. Neither half can pass on the other's work.

**Ruling: Task 14's dispatch states this argument, not just the assertion** — so the
implementer knows the test is the point of the task's Step 7, not a formality appended after
it, and does not "simplify" the handler away when the assertion is the only thing watching it.
— Cost if wrong: nil; it is the same assertion the pre-flight mandated, with its justification
made explicit.

### Task 13: COMPLETE — `f6b555f` + fix `9c127a4`

Re-review (agent `a3ce4e1a69e5efb3b`, sonnet, scoped to F1–F4): **all four ADDRESSED, no new
findings.** `heading_test.dart` 15/15; full suite **300 passed / 0 failed**;
`flutter analyze` → `No issues found!`; `git status --porcelain` empty; HEAD `9c127a4`.

Evidence the re-review produced by probe, not by reading:

- **F1** — with the fix, the coast→activate→turn scenario leaves the ship exactly unchanged
  (`x=0 y=0 z=0`, magnitude `0.0`); reverting the fix reproduces `mag=6.901841202733883`,
  matching both the original review and my own derivation.
- **F2** — every claim reproduced: the anchor is the exhaust point (`_reconcileCruise`
  `:1166-1170`; 500 s of coast = 13.3333 ly from it), `_cruiseBurnNow` reads 0 while coasting
  (energy holds at 100 across the drift), and the clock reset is 43 vs 10 (a mutation keeping
  the stale clock makes the post-turn `energy` read `10`).
- **F3** — **the load-bearing probe:** reverting the fix leaves `heading_test.dart` at
  14 pass / 1 fail, the sole failure being the new coasting test
  (`Expected 93.5553770092386, Actual 91.76904905969779, differs by 1.786327949540805` at
  `:245`) — i.e. the 1.786 x-component I predicted, and the cruising test still passes, so the
  new test is the *only* guard on that path.
- **F4** — `:213` now reads "95 EN, the 100 EN reserve less the 5 EN activation fee", matching
  `expect(c.energy, 95)` at `:210`.
- **Probe 3, inertness of the reordering:** the `energy` check (`:1357`) precedes
  `_settleCruise()` (`:1359`); `_repinLeg` cannot touch `energyBalance`; `_syncDormancy()`
  (`:1401`) still follows the deduction. No behaviour outside the coasting path changed.

**Task 13 delivered:** `turnAngleTo`, `turnCostTo`, `correctHeading`, and 15 tests, with the
price read from `Engine.turnCostFor` — the 真实式 Δv formula the user locked in, with a
coasting turn now correctly priced and correctly positioned.

### Task 14 dispatched (BASE `9c127a4`, brief re-extracted, 244 lines)

Implementer agent `a763d43ab19158a54`, sonnet. Scope: a new top-level `aimCameraAt` in
`camera3d.dart`, the page's `_aimCockpitAtOrigin` / `_recenter` / `_onScaleUpdate` /
`_setMode` / `_SideControls` changes, the new `_maybeEnterRequestedCockpit` handler that
consumes `cockpitRequested`, a new `camera_aim_test.dart`, and the cockpit-label assertion
added to `cruise_ui_test.dart`.

The dispatch carries six corrections, all pre-flighted and all overriding the brief:
1. `Vec3` has no `==` → bind `const eye = Vec3(5, 6, 7)` and assert `identical`; do not add
   `operator ==` to `core/vec3.dart`.
2. Anchors stale — anchor by name. `_setMode` :285, `_aimCockpitAtOrigin` :300, `_recenter`
   :307, `_SideControls` :496, `build` :365 (brief said 417).
3. Step 5's `build` change is already in place at `:427`.
4. Step 8's "remove the `skip`" is moot; replaced by the cockpit-label assertion plus a
   further bounded pump, with the falsifiability argument.
5. Step 9's `git add` must include `test/cruise_ui_test.dart`.
6. Step 6's comment is true — do not "fix" it (my earlier note withdrawn).

Also carried: the consumer does not exist at HEAD (this task creates it), the producer already
does both halves (`journey_page.dart:211-214`), and `game_controller.dart` /
`test/heading_test.dart` are off-limits because Task 13 just landed a correctness fix there.

### Note for Task 15's dispatch — Task 14 shifts its citations but not its corrections

Task 15's pre-flight (recorded above) cites `galaxy_map_3d_page.dart:702,704,723-729` as the
*evidence* for its findings 3 and 4, and Task 14 is editing that file right now, so those line
numbers will move. **This does not invalidate any correction**, because Task 15's brief cites
no line anchors and the corrections I ruled are anchor-free:

- **Finding 3** — reword the claim about `_CockpitPainter`'s insets: the truth is a **window**
  inset of 14 with 48 top and 40 bottom (`Rect.fromLTRB(inset, inset + 48, w - inset,
  h - inset - 40)`); the "struts" are a separate thing (inset 20, length 34). The brief
  attributes the 48 / 40 to struts, which is false.
- **Finding 4** — drop the "heading bar at the bottom" justification: no heading bar exists at
  HEAD; the real bottom widget is `_BottomControls`. A heading readout is Task 16's.
- **The inset *numbers* are stable** across Task 14: it edits `_setMode`,
  `_aimCockpitAtOrigin`, `_recenter`, `_onScaleUpdate`, `_SideControls` and `build` — none of
  which is `_CockpitPainter`. So the corrections can be written without re-deriving anything.

### Task 14 implemented at `354aaf5` (BASE `9c127a4`), review dispatched — do NOT re-dispatch

DONE_WITH_CONCERNS, 4 files (`camera3d.dart`, `galaxy_map_3d_page.dart`, new
`camera_aim_test.dart`, `cruise_ui_test.dart`). `flutter analyze` → `No issues found!`;
`flutter test` → **304/304** (camera_aim 4/4, cruise_ui 8/8). Tree clean.

**MY ERROR, NINTH INSTANCE — correction #4 was wrong, in a new shape.** I mandated inserting
the cockpit-label assertion "after the existing `expect(c.cockpitRequested, isTrue);`" without
asking whether *this task's own change* invalidates that existing assertion. It does: the
handler this task adds consumes the request, and because `IndexedStack` builds **all** its
children, the star map's `AnimatedBuilder` is live while the voyage tab is shown — so
`requestCockpit()` rebuilds it in the same frame and the post-frame callback runs at the end of
the same `pump`, leaving the flag `false` where it used to stay `true`. Before this task
nothing consumed the request, so the assertion held; the task's deliverable is exactly what
breaks it. **The check I owed was one question: does the surrounding test still hold after this
change?** I verified the *new* assertion's falsifiability and its string literal, and never
looked at its neighbour. (Eighth instance was verifying a computation's internals while never
examining its input; this is verifying an assertion while never examining its context.)

The implementer caught it **empirically** (`Actual: <false>` at the old line) rather than by
reasoning, and fixed it correctly: read the request *before* the pump — the tap handler runs
synchronously, so it is genuinely `true` there — then assert the label after a **second**
bounded pump, since the post-frame callback's `setState` only renders on the next frame. Test
intent preserved, and the label assertion still pins both halves.

**Concern 2, confirmed by me — a false claim I wrote into the shipped comment.** My mandated
comment cites `galaxy_map_3d_page.dart:478-483`, but this task's own edits moved that
`switch (mode)` to **:523-527** (`_TopBar`, class at `:499`). So the comment is false as
shipped — the recurring defect class, authored by me. The implementer kept my text verbatim
*because I told it to transcribe verbatim*, and flagged the staleness instead of silently
diverging. **Ruling: fix it by naming the widget, not by renumbering** — `_TopBar` is stable,
a line range has already rotted once inside the very commit that introduced it, and the next
task to edit this page would rot it again.

**Concern 3 — ruled: note, do not fix.** `_maybeEnterRequestedCockpit` consumes a request even
while the star map is offstage, because `IndexedStack` builds all children. Benign today: the
only producer (`_steerFromCockpit`, `journey_page.dart:211-214`) switches to tab 0 in the same
handler, so the request is never consumed invisibly. Gating the consumer on visibility would
need the selected-tab index inside the map page — a shell concern outside this brief. Carried
to Task 16's dispatch and the final review. — Cost if wrong: a future producer that raises the
request without navigating would have it consumed unseen, and the mode would change where the
player is not looking.

**Minor, confirmed:** the redundant `import 'package:starward/core/vec3.dart';` in
`camera_aim_test.dart` was genuinely redundant — `camera3d.dart:7` is
`export '../../core/vec3.dart';` — so dropping it was required to reach `No issues found!`.

### Task 14 review: spec COMPLIANT, quality FINDINGS — a HIGH crash, and my pre-flight cleared it for the wrong reason

Reviewer agent `a42a5fa5a52d01f07`, opus. **Spec COMPLIANT** (all 9 steps, all 6 dispatch
corrections applied as ruled, scope exactly the 4 files, no `game_controller.dart` /
`heading_test.dart` / model / save-key edits). **Quality: FINDINGS** — F1 HIGH, F2 MEDIUM,
F3/F4/F5 LOW, F6 INFO. Suite 304/304, analyze clean, tree clean at `354aaf5`.

**F1 CORRECTNESS (HIGH) — verified by me, not accepted.** `galaxy_map_3d_page.dart:319-322`:
the already-in-cockpit branch of `_maybeEnterRequestedCockpit` calls
`_c.acknowledgeCockpitRequest()` **synchronously from inside the `LayoutBuilder` builder**.
`acknowledgeCockpitRequest` (`game_controller.dart:1026-1030`) is `_cockpitRequested = false;
notifyListeners();`, so the star map's `AnimatedBuilder` — which listens to the controller and
is live because `IndexedStack` builds all children — marks itself dirty during build:
`setState() or markNeedsBuild() called during build.`

**This is the same shape as Task 13's F1, and it is the shape this plan keeps producing: the
comment names the hazard and the code commits it.** The handler's own doc (`:311-315`) reads
*"The actual work is deferred to a post-frame callback because it calls `setState` and
`acknowledgeCockpitRequest`, which notifies listeners; doing either during a build is an
error"* — and the branch two lines below that doc does exactly the forbidden thing. Verified by
reading both the handler and `acknowledgeCockpitRequest`; the reviewer verified it by probe
(6 exceptions on a temporary widget test, which it did not keep).

Reachable, and on the feature's main path: enter the cockpit on the star map (tap 座舱), switch
to 航行, tap 点火巡航 or 修正航向. The **first** request is fine (mode is orbit → the deferred
path); the **second** crashes. No existing test covers it, which is why 304 stayed green.

**MY MISS — the pre-flight cleared this branch for the wrong reason.** My Task 14 pre-flight
recorded: *"`_setMode` already returns early when the mode is unchanged — so the handler's own
mode check at Step 7 is belt-and-braces, not a duplicate-work bug."* It examined the branch and
asked whether it was *duplicated work*; it never asked whether its *side effect* was safe in the
phase it runs in. The dimension it checked was not the dimension that mattered. Same family as
the eighth instance (verifying a computation's internals while never examining its input):
**the claim I verified was true, and irrelevant.** Tenth instance on this plan.

Other findings: **F2** (my `:478-483` citation is false; reviewer adds that renumbering is
wrong too — *any* number rots, so name `_TopBar` and cite nothing). **F3**
`camera3d.dart:254-257` + `camera_aim_test.dart:9-11` claim a heading bar quotes `forward` and
ignition flies along it — both false at HEAD (no heading bar; `igniteCruise` has no UI caller);
the Task-12-F3 shape of forward-referencing a consumer that does not exist. **F4**
`camera_aim_test.dart:59` `expect(camera.forward.length, closeTo(1, 1e-9))` is unfalsifiable —
`cos²p·sin²y + sin²p + cos²p·cos²y = 1` identically, so nothing can make it fail. **F5** the
cockpit-recenter rationale ("would re-place the eye exactly where it already is") is false while
the ship moves, since `eyeOverride` is set only at mode entry (`camera3d.dart:224`). **F6** a
`reason: '$d'` prints `Instance of 'Vec3'`.

**Probes that settled the earlier concerns:** tap alone leaves `cockpitRequested` true (the
shipped pre-pump assertion is right); the assertion after one pump reads `false` (same-pump
consumption confirmed); deleting the consumer → label `Found 0 widgets`; removing
`ShellScope.go` → `Found 0 widgets`; one pump instead of two → `Found 0 widgets`. So the label
assertion pins **both** the mode change and the navigation, and the second pump is
load-bearing. `aimCameraAt`'s inverse verified by mutation: `atan2(-x,z)`, `atan2(x,-z)` and
`asin(-y)` each fail the relevant test, so both conventions are genuinely pinned.

Fix round **1 of 5** — resuming implementer `a763d43ab19158a54`. BASE `354aaf5`.

### Task 14 — fix round 1 (`2510f9c`) — the build-phase crash is closed and now guarded

Commit `2510f9c` "fix(starward): defer the already-in-cockpit acknowledge out of the build
phase", 4 files, 88 insertions / 31 deletions. Full suite **305/305** (304 + the regression
test); `flutter analyze` → `No issues found!`; tree clean; HEAD `2510f9c`.

**All six findings confirmed correct against the code** — the implementer verified rather than
transcribed, and reported no disagreement with the review.

- **F1** — the implementer proved the mechanism one level deeper than I did: the `LayoutBuilder`
  builder runs inside `owner!.buildScope` (`layout_builder.dart:270`), so `_debugBuilding` is
  true and `markNeedsBuild` on the out-of-scope ancestor `AnimatedBuilder` throws. It wrote the
  regression test **first** and reproduced the exact exception before touching the fix, with the
  stack pointing at `_maybeEnterRequestedCockpit (galaxy_map_3d_page.dart:320)`. The branch now
  defers into an `addPostFrameCallback` guarded by `mounted` + a `cockpitRequested` re-check;
  two-branch structure kept.
- **F4's replacement is falsifiable by construction**, which the old line was not: it now
  asserts `camera.pitch`, and removing the guard makes it fail (`Expected: <1.2> Actual: <0.0>`).
- F3's claims verified from the tree: no heading bar exists anywhere in `lib/ui`, and
  `igniteCruise` has no UI caller (only its definition at `game_controller.dart:1298`). F5's
  verified: `placeCamera`'s cockpit branch sets only `eyeOverride` (`camera3d.dart:223-224`).

**A seventh defect the implementer found while verifying F4 — the plan's defect class again.**
The doc said a zero vector "would produce NaN" and the test said "rather than producing NaN".
**Both false:** `Vec3.normalized` returns the zero vector for zero input, and `atan2(0, 0) ==
0.0` / `asin(0) == 0.0`, so without the guard the camera snaps to yaw 0 / pitch 0 — a wrong
answer, not a NaN. The implementer confirmed the two Dart identities with a throwaway script,
removed the clause, and renamed the test `a zero vector is ignored`. **Ruling: accepted, in
scope.** It is the same file, the same guard and the same commit as F4, and the false claim was
*justifying* the guard F4 was about; leaving it would have shipped a comment that misstates why
the guard exists. This is the twenty-first instance of the class, and the second found by an
implementer rather than a reviewer.

**Concern raised, assessed as sound:** the already-in-cockpit branch queues a post-frame
callback on every build while a request is pending. Idempotent — the first acknowledges, the
rest short-circuit on the `cockpitRequested` re-check. And `_cockpitRequestScheduled` was
deliberately **not** shared: it exists to stop `_setMode` being scheduled twice, so sharing it
would block the branch that actually needs `_setMode`.

Scoped re-review dispatched (agent `a28f562b058c85266`, sonnet), carrying as its load-bearing
probe: revert the deferral and confirm the new regression test fails with the build-phase
exception. Also asked to verify the seventh change's two Dart identities independently.

## Task 14 — fix round 1 re-review verdict (agent `a28f562b058c85266`, sonnet)

**F1 ADDRESSED.** Reverting the deferral (restoring the synchronous acknowledge in the
already-in-cockpit branch) makes the new `cruise_ui_test.dart` regression test fail with
`setState() or markNeedsBuild() called during build.` at `acknowledgeCockpitRequest`, stack
pointing at `_maybeEnterRequestedCockpit:327`; with the fix it passes. "The test is genuinely
load-bearing." **F2 ADDRESSED** — now "this page's `_TopBar`", no number. **F3 ADDRESSED** —
reworded to the cockpit being built around `forward`; no "heading bar"/"ignition", no Task 16
reference; the surviving reticle-at-centre claim is true (`:802`). **F4 ADDRESSED** — guard
removal fails the replacement (`Expected: <0.4> / Actual: <0.0>`). **F5 ADDRESSED, with
residual N1.** **F6 ADDRESSED** — `reason: 'dir (${d.x}, ${d.y}, ${d.z})'`; no `toString` on
`Vec3` (`core/vec3.dart` untouched). **Seventh change CORRECT and in scope** — both Dart
identities probed independently (`atan2(0.0,0.0) == 0.0`, `asin(0.0) == 0.0`, neither NaN).
No line-number citation reintroduced (the only remaining one, `starfield.dart:97`, predates this
round and is accurate). Scope exactly the four files. `flutter analyze` → `No issues found!`;
`flutter test` → **305 passed / 0 failed**; `git status --porcelain` empty; HEAD `2510f9c`.

### N1 (LOW) — ACCEPTED as a fix, round 2

`galaxy_map_3d_page.dart:594-599`, the comment above the `_RoundButton` in `_SideControls`,
claims a plain recenter in cockpit mode "would leave the view pointing exactly where it already
points — a button that visibly does nothing". **False.** `placeCamera`'s cockpit branch is
`camera.eyeOverride = shipPosition` (`camera3d.dart:224`) read from the **live** ship position,
so a recenter moves the eye onto the ship — a visible change whenever the ship has moved since
mode entry. True only while parked, and a ship that moves is the entire subject of this feature.

**Ruling: fix it in this round rather than defer to the final review — because F5 corrected the
sibling `_recenter` comment in the same widget in this same round, and a corrected comment
shipped beside a false one is worse than either alone: the next reader trusts the wrong one.
Cost if wrong: one comment edit and one commit; the re-review is scoped and cheap.** This is
the plan's recurring defect class (false claim in a comment), instance twenty-two.

### N2 (INFO) — NO code change; the claim is in the report, not in shipped code

The implementer's *report* justified not sharing `_cockpitRequestScheduled` by saying sharing it
"would also block `_setMode` for the branch that needs it". The re-reviewer applied the shared
guard and all 13 tests still passed (the branches are mutually exclusive per frame; the flag
resets at frame end), so **that reason is unsupported**. But the **code** comment at `:323-326`
claims only that *this* branch does not need the guard — it does not call `_setMode`, and the
acknowledge is idempotent — which is accurate as worded, and the parenthetical "(which exists to
stop `_setMode` being queued twice)" matches `:333-336`. **Ruling: the code stays; the report
line gets corrected so the record is straight for the final reviewer. Cost if wrong: none —
nothing false ships either way.**

### My tenth error, and what it cost

My Task 14 pre-flight cleared the already-in-cockpit branch on the ground that "`_setMode`
already returns early when the mode is unchanged — so the handler's own mode check is
belt-and-braces, not a duplicate-work bug." That claim was true and **irrelevant**. I examined
whether the branch was *duplicated work* and never asked whether its *side effect* was safe in
the phase it runs in. The branch I cleared is the one that crashes. Shape of the error:
**verifying a claim on the dimension it was stated in, while never checking the dimension that
matters.** Nine prior instances are recorded above in their own shapes; this one is distinct
enough to name separately.

Fix round 2 dispatched — resumed implementer `a763d43ab19158a54` (round 2 of 5, rounds 1-3
resume the same implementer). BASE `2510f9c`. Carried: N1 to fix, and N2 as a report-only
correction, with an explicit instruction not to take my description of what a recenter does on
trust — verify it against `_recenter`'s cockpit branch and `placeCamera` first.

## Task 15 — pre-flight rulings (settled before dispatch, so the dispatch carries no open questions)

Pre-flight file: `task-15-preflight.md` (written against `ce5f1e4`). Every correction it proposes
is **anchor-free** — it rewords claims, it does not re-cite line numbers — so none of them rot
when Task 14 moves `galaxy_map_3d_page.dart`. Re-verified at HEAD `2510f9c` that the numbers the
corrections depend on still hold: `inset = 14.0` (`:764`), the `48 / 40` in
`Rect.fromLTRB(inset, inset + 48, w - inset, h - inset - 40)` (`:766`) are the window rect's
**top and bottom offsets**, the struts are `const s = 34.0` (`:789`) inset `20`
(`frameRect.left + 20`, `:790`), and `_BottomControls` exists (`:661`, placed at `:496`).

| # | Pre-flight finding | Ruling |
|---|---|---|
| 1 | `Offset + Vec3` does not compile (`Vec3` has `x/y/z`, not `dx/dy`; no `Offset + Vec3` operator exists in `lib/`) | **Fix as proposed** — build the chevron legs in `Offset` space: `clamped + Offset(-u.dy, u.dx) * 7`. `u` is already an `Offset` (`dir / len`), so the geometry is unchanged. |
| 2 | `import 'package:flutter/widgets.dart';` in the test is dead → `unused_import` → `No issues found!` unreachable | **Fix** — delete the import. |
| 3 | "insets its window by 14 and its struts by 48 / 40" misattributes the insets | **Fix** — the real numbers are 14 (window), 48 / 40 (top / bottom of the window rect), 20 / 34 (strut inset / length). |
| 4 | "the heading bar at the bottom" — no heading bar exists at HEAD | **Fix** — name `_BottomControls`, the widget actually there. A clamp justified by a widget Task 16 has not yet added is the "describing a later task's work as already in place" hazard. |
| 5 | `focalFor` and `Camera3D.eye` are listed as Consumed but never referenced | **Note only, no code change** — carried in the dispatch as an instruction *not* to manufacture a use for them. The plan's Interfaces block is an argument, not a product; false claims in shipped comments get fixed, overstatements in plan prose get corrected in the dispatch. |
| 6 | `dx = 130.72` / `dx = 269.28` quoted with `=` when the exact values are `130.7179676972449` / `269.2820323027551` | **Fix** — `≈`. It is a comment that ships inside the test file, so it is the plan's defect class, not plan prose. |
| 7 | `shouldRepaint`'s "`markers` is rebuilt from live scene positions on every frame" is unverifiable at HEAD (nothing builds a `CockpitHudPainter` yet) | **Fix** — keep the `Vec3 has no ==` half, which is true and sufficient on its own; drop the frame-rebuild clause until Task 16 lands. |
| 8 | clamp bounds throw when the viewport is shorter than 206 px / narrower than 52 px (`num.clamp` throws when upper < lower) | **Leave** — not reachable on any phone-sized canvas and no test mounts the painter. Recorded here as a deferred-minor for the final whole-branch review. |

Two things the pre-flight did **not** flag, checked here and found sound: `offScreen = clamped !=
at` is a genuine **value** comparison (`Offset` has `operator ==`, unlike `Vec3`), and the sign
convention in the test's comment is self-consistent with its own assertions — `right =
forward × up` is `(-1,0,0)` for `forward = +Z`, so world `−X` projects to `dx = 269.282` (right of
the 200 centre) and the test's `greaterThan(200)` is asserting exactly that.

## Task 14 — fix round 2 (commit `4ac3e67`) — re-review CLEAN → **Task 14: complete**

Implementer resumed (`a763d43ab19158a54`, round 2 of 5). Comment-only: `galaxy_map_3d_page.dart`,
6 insertions / 6 deletions, one hunk. It verified N1's premise itself rather than taking my
description on trust — `placeCamera`'s cockpit branch (`camera3d.dart:223-224`) is the only write
to `eyeOverride`, `_shipPos` is the live position, and `Camera3D.eye` returns `eyeOverride` in
cockpit mode, so a recenter re-pins the eye to the ship's current position. Both the "does
nothing" clause and the "pointing where it already points" phrasing are gone; the true half
stays.

Scoped re-review (agent `a95c653a504491904`, sonnet) — **N1 ADDRESSED**, verified clause by
clause against the code, not against the diff's prose: "only re-pins `eyeOverride`"
(`camera3d.dart:223-224`), "never touches the aim" (neither `yaw` nor `pitch` is written in that
branch), "the reticle at the centre *is* the heading" (reticle drawn at `Offset(w/2, h/2)`,
`:802-812`), and the re-aim path (`_recenter` → `_aimCockpitAtOrigin()`). **N2 ADDRESSED** —
`task-14-report.md:239-248` names the unsupported claim and retracts it in place, not softened.
**Sibling `_recenter` comment: leaving it was correct, not an oversight** — its claim is about the
*aim direction*, and `placeCamera`'s cockpit branch writes neither `yaw` nor `pitch`, so `forward`
is genuinely identical after a plain recenter; the eye moves, which is precisely why only the
`_SideControls` comment needed the fix. **Diff scope clean. No new findings.** `git status`
empty; HEAD `4ac3e67`; `flutter analyze` → `No issues found! (ran in 11.7s)`; `flutter test` →
`+305: All tests passed!`.

**Ruling (recorded because the implementer explicitly flagged it as a decision, not an
oversight): the sibling `_recenter` comment stays as round 1 left it — its clause is true, and
rewording a true comment to match a false one's fix would be the defect, not the fix. Cost if
wrong: none; the re-reviewer independently confirmed the clause is true.**

Non-finding observation, recorded for the final review: the round-1 report's F5 paragraph still
describes *both* comments as carrying the "visibly does nothing" reason, when only `_SideControls`
ever did. Historical report prose, superseded by this round; not shipped code.

**Task 14 = `354aaf5` + fix `2510f9c` + fix `4ac3e67`. COMPLETE.**

## Task 15 dispatch (implementer `a76e6c2fdfde23d90`, sonnet) — BASE `4ac3e67`

Brief re-extracted immediately before dispatch (310 lines, the standing ruling). Dispatch carried:
where the task fits (the pure HUD parts; Task 16 mounts them), the brief as the single source of
requirements, all eight pre-flight rulings (fix 1, 2, 3/4, 6, 7; note-only 5; leave 8), the
Interfaces block restated as a must-match contract because Task 16 consumes those exact
signatures, and the earlier-task facts the brief cannot know — `Vec3` has no `operator ==` (and
`operator ==` / `toString` were deliberately declined in Task 14), `camera3d.dart` exports
`vec3.dart` so the test's own `vec3.dart` import is redundant but not an error,
`Vec3.normalized` returns the zero vector rather than NaN, and `_CockpitPainter` / `_BottomControls`
must be cited by name because line numbers in that file have already rotted twice.

Model choice: sonnet, not the cheapest tier. The plan text contains the complete code, which
argues for transcription-tier, but the eight corrections are prose judgments about claims and the
task must not manufacture a use for `focalFor`/`Camera3D.eye`; turn count beats token price.

Task 16's pre-flight dispatched in parallel (agent `a8efdba0dc10669b9`, sonnet) — read-only, and
Task 15's implementer touches only the two new files, so there is no file overlap. Task 16's
pre-flight carries the two ledger items routed to it by name: the `_nearby` staleness
(`recommendedDestination` reads a working set rescanned only every 20 ly, verified
behaviour-preserving when lifted but newly *visible* if a marker is drawn from it — ledger
:630, :673, :871) and the offstage consumption of `cockpitRequested` (ledger :1225-1232).

## Task 15 — implementer report (`114bf84`), DONE_WITH_CONCERNS

2 files, 259 insertions: `starward/lib/ui/galaxy3d/cockpit_hud.dart` and
`starward/test/cockpit_hud_test.dart`, nothing else. `flutter test` → **314 passing** (305 on
entry + 9 new); `flutter analyze` → `No issues found!`; tree clean.

All eight rulings applied. Two things worth recording:

**MY ERROR, ELEVENTH INSTANCE — and the implementer overrode my dispatch with evidence.** I wrote
in the dispatch: "the test's own `vec3.dart` import is redundant but harmless and is *not* an
analyzer error. Leave it." **False.** `analysis_options.yaml` includes `flutter_lints`, which
enables `unnecessary_import`, so the lint fired on **both** new files — the lib file's
`'../../core/vec3.dart'` and the test's `'package:starward/core/vec3.dart'` — because
`camera3d.dart` re-exports `vec3.dart`, making `No issues found!` unreachable. The implementer
removed both, the symbols still resolve through the re-export, and it flagged the deviation
rather than silently diverging. **Shape of the error: I extended a true statement about one
import (`vec3.dart` is redundant) into a claim about a *different* property (`not an analyzer
error`) without reading the lint configuration.** Independent confirmation that the rule really
does bite: Task 14's pre-flight found the same `unnecessary_import` required dropping the same
redundant import from `camera_aim_test.dart` (ledger :1234-1236) — so this is established repo
behaviour, and the deviation matches precedent exactly.

**Ruling: the deviation is ACCEPTED as correct and in scope.** Both lines are in files this task
owns; the change is the minimum needed to reach the required `No issues found!`; and it is
demonstrably necessary rather than cosmetic. Carried to the reviewer as a *ruled* deviation so it
is not re-litigated — but with a probe, because my premise was the false one: re-add the import,
confirm analyze fails, revert.

Standing-note pass done by the implementer, and it found something: the one non-local claim in
its new comment — that a destination past sensor range "draws nothing at all" — was verified
against `galaxy3d_painter.dart`, which culls planets at `dist > sensorRange`. That claim is the
feature's whole justification, so verifying it was the right call. The two glyphs were
hexdump-confirmed again (U+2212 / U+2014).

**Minor, note only:** the brief's Step 2 predicts the failure message `Target of URI doesn't
exist`; the current analyzer prints `Error when reading … No such file or directory`. Same cause
(a missing target file), plan-prose inaccuracy, not a defect.

Review package `review-4ac3e67..114bf84.diff` generated; task reviewer dispatched.

## Task 16 — pre-flight rulings (settled now; dispatch waits only on Task 15 closing)

`task-16-preflight.md`, 8 findings, 3 blocking. Written against `4ac3e67`, before Task 15 landed.
**The one item it could not check is now closed:** Task 15's `cockpit_hud.dart` exists and its
public API matches the contract the pre-flight had to take from `task-15-brief.md` —
`({String bearing, String elevation}) headingLabel(Vec3)` (`:18`), `Offset? hudMarkerPoint({
required … })` (`:39`), `const HudMarker({required world, label, color})` (`:50`), and
`const CockpitHudPainter({required camera, required markers})` (`:69`). The chevron legs are in
`Offset` space (`:103-104`) as ruled.

| # | Finding | Ruling |
|---|---|---|
| 1 | **BLOCKING.** Both new test helpers call `pumpAndSettle()`, but the shell's starfield runs a repeating `AnimationController` (`starfield.dart:97`) inside the `IndexedStack`, so the tree never settles and every new test times out. | **Fix as proposed** — bounded `pump(const Duration(milliseconds: 100))`, the shape `_pumpVoyage` already uses. This is the plan-level trap carried in every dispatch, and it is the first time it has actually bitten. |
| 2 | **BLOCKING.** Test 4's `c.tick()` queues the fuel-out report; `JourneyPage` is an `IndexedStack` child so its post-frame callback shows a **modal** sheet whose barrier covers the tab bar — the 座舱 tap dismisses the sheet instead of entering the cockpit. | **Fix as proposed** — `await c.acknowledgeDriftReport();` after `c.tick()`, exactly as `cruise_ui_test.dart:155` does. **This also closes the Task 12 doc gap** I parked (a new test that runs dry without mentioning the sheet). |
| 3 | **BLOCKING.** The two helpers are indented local functions with leading underscores, so `no_leading_underscores_for_local_identifiers` (via `flutter_lints`) fires twice and `No issues found!` is unreachable. | **Fix — move both to the top level** beside `_pumpVoyage`, keeping the `_` prefix. That is the file's existing shape (`_boot`, `_pumpVoyage` are top-level and private) and the lint does not apply to top-level names. Dropping the underscores is an acceptable fallback if moving them proves awkward. |
| 4 | `expect(inCockpit('—'), findsNothing)` cannot fail: the readout is a single `Text` rendering `'—  —'`, and `find.text` matches whole strings, so nothing ever equals `'—'`. | **Fix as proposed** — `find.descendant(of: cockpit, matching: find.textContaining('—'))`. Verify no *other* cockpit text contains an em dash, or the assertion fails for the wrong reason. |
| 5 | All three `file.dart:NN` anchors have rotted (`build` 417→420; the `_CockpitOverlay` arm 415-420→473-478; the `else` arm 437-442→495-500). None overlaps the block it names. | **Fix as proposed — cite by name, no numbers.** A number rots again; that is why Task 14's F2 fix named `_TopBar` instead of citing a line. |
| 6 | The `_nearby` staleness routed to Task 16 by name is unacknowledged in the brief, and "always, even when it is far outside sensor range" is overstated: `_nearby` is normally ≤ 60 ly while the sensor slider spans 50–416 ly, so at the default range the recommendation is *inside* range. | **Fix both halves** — add the one-sentence staleness note to the `_hudMarkers` doc (the marker's *identity* can lag by up to 20 ly of drift; its *position* is read fresh from the scene), and soften the range claim to "beyond the sensor range if the player has lowered it". |
| 7 | Test 3's comment says the ship is at `(40, 0, 0)` and the turn is a 180° turn. False — the spawn is within 0.9 of the origin, so the turn is ≈ 178.7–180°. The pinned `200 EN` still re-derives (`round(200·sin(θ/2))` stays 200 down to θ ≈ 171.9°). | **Fix the comment only** — "≈ 180° from the spawn point, which rounds to 200 EN". The number is right; the reason given for it is not, and a reader re-deriving it would be misled. |
| 8 | `_worldScale` is in the Consumes list but no Task 16 code uses it. | **Note only, no code change** — same class as Task 15's `focalFor`/`Camera3D.eye`; carried as an instruction not to manufacture a use. |

**Carried observation B is CLOSED, not merely carried forward.** The offstage consumption of
`cockpitRequested` (ledger :1225-1232) stays benign: Task 16 adds **no** producer. The only
caller of `requestCockpit()` in `lib/` remains `journey_page.dart:210` (`_steerFromCockpit`),
which switches to tab 0 in the same handler; the cockpit's own 点火巡航 button calls
`_igniteFromCockpit`. Nothing further to do, and the final review needs only the note.

Also verified by the pre-flight and worth keeping: `_hudMarkers`' `scene.planetPositions
.containsKey(rec.id)` guard can never fall through to the origin, because `scene` is built from
`_c.planets` and `recommendedDestination` iterates that same list (`game_controller.dart:217`).

## Task 15 — review verdict (agent `a0a843073bc3fbf34`, opus)

**Spec: PASS.** All five steps met, all eight dispatch rulings applied exactly as ruled, and a
mechanical diff of the brief's two code blocks against the shipped files shows the only content
differences are the four comment/geometry rulings plus the two import removals — nothing else
dropped. Scope exactly the two new files (2 files, 259 insertions). Layer discipline and
entity-ownership both PASS; no `dart format` run; tree left clean.
**Quality: PASS WITH FINDINGS** — F1 MEDIUM, F2/F3/F4 LOW, F5/F6 INFO. No behavioural bug at any
reachable input; all pinned numbers exact.

**My eleventh error, now empirically confirmed.** The reviewer re-added `import
'../../core/vec3.dart';` and got exactly: `info • The import of '../../core/vec3.dart' is
unnecessary because all of the used elements are also provided by the import of 'camera3d.dart' •
lib/ui/galaxy3d/cockpit_hud.dart:5:8 • unnecessary_import` / `1 issue found. (ran in 9.1s)`;
reverted → tree clean, `No issues found! (ran in 9.2s)`. The implementer's override was right.

Probes all came back exact: `focal 692.8203230275511`; `(0,0,100) → (200,400)`;
`(10,0,100) → 130.7179676972449`; `(−10,0,100) → 269.2820323027551`; `200 + 69.2820323` within
2.8e-9; `yaw = π/2 → (200,400)`. `headingLabel`'s convention verified against `camera3d.dart`
(`yaw == atan2(x,z)`, `pitch == asin(y)`). Sign convention verified: `right = f × up` with
`f = +Z` is `(−1,0,0)`, so world −X is screen-right. Clamp comment geometry verified. Chevron
perpendicular verified identical to the brief's under `x→dx, y→dy`. `vec3.dart` defines no `==`
or `hashCode`. Glyphs hexdump-confirmed. `flutter test` → `+314: All tests passed!`;
`cockpit_hud_test.dart` alone → `+9`.

### Rulings on the six findings — all six fixed (fix round 1, resuming the same implementer)

- **F1 (MEDIUM) — FIX.** The `visible` check's stated rationale is false in both files: a point
  behind the eye would not be "mirrored to the wrong side of the screen" — `project` culls at
  `camZ <= _near` and returns `Projected.hidden`, whose `screen` is `Offset.zero`, so it would be
  drawn in the **top-left corner**. The guard is load-bearing; only its reason is wrong.
- **F2 (LOW) — FIX, and this one matters most.** The comment claims a destination past sensor
  range "draws nothing at all" without clamping. The clamp is irrelevant to sensor range, and
  `_drawRoute` draws the route line and gold marker for a far destination whenever a journey is
  active, independent of `sensorRange`. The report's supporting premise ("journey destinations are
  planets") is false — `game_controller.dart` carries star, coord and planet destinations. This is
  the feature's own justification, so it gets replaced with the reason clamping actually has
  (verified: `hudMarkerPoint` returns null *only* behind the camera, so an in-front-but-off-axis
  point projects outside the canvas and off-canvas drawing is invisible). The report line gets
  corrected too, on the N2 pattern.
- **F3 (LOW) — FIX.** A test that cannot fail: "does not care how long the vector is" passes with
  `.normalized` deleted and passes for a constant. Replaced with `Vec3(0, 3, 4)` → `'+37°'`.
- **F4 (LOW) — FIX.** A real rendering bug: the label is always offset `+14` in x, so a
  right-edge clamped marker's label is drawn from `width − 12` and clipped — the player cannot
  read it, which defeats the point of clamping. **Ruled: no test required for this one, and that
  is a ruling rather than an oversight** — nothing in this repo builds a `CockpitHudPainter`, a
  canvas-recording test would be disproportionate, and the painter is untested by design because
  Task 16 mounts it. Cost if wrong: a clipped label persists, or a label flips when it need not.
- **F5 (INFO) — FIX, with the test written first.** `headingLabel(const Vec3(-0.0, 0, 1)).bearing`
  reads `'-0°'` (`atan2(-0.0, 1.0)` is `-0.0`, `-0.0 < 0` is false, `(-0.0).toStringAsFixed(0)`
  is `'-0'`). Player-facing copy reading wrong, and the fix is one comparison against zero. I
  required the `-0.0` reachability be confirmed by execution rather than argument.
- **F6 (INFO) — FIX by making the name true, not by weakening it.** "projects through the real
  perspective divide, not a flat scale" asserts at a single depth, so a flat scale calibrated at
  depth 100 would pass. Add a second depth (`(−10, 0, 200)` → `200 + 400/tan(30°)·0.05 =
  234.6410161…`), which no depth-independent scale can produce.

Fix round 1 of 5 dispatched to the same implementer, with the mutation-check instruction: for F3
and F6 the replacements do not fail before the change (the implementation was already right), so
it must confirm the *mutation* falsifies them rather than assume.

## Task 15 — fix round 1 (`7a7b9a5`), DONE

Six findings fixed; `flutter test` → **315 passing** (314 on entry + the new F5 test; F3/F6
replaced or extended existing ones); `flutter analyze` → `No issues found!`.

**MY ERROR, TWELFTH INSTANCE — caught by the implementer, in my own fix dispatch.** I wrote that
`hudMarkerPoint` returns null "only for a point behind the camera", and told the implementer to
say that. **False.** `Camera3D.project` culls at `camZ <= _near (1.0)`, so a point up to 1 unit
*in front* of the eye is dropped too. The implementer wrote "at or behind the camera's near
plane" in both places and flagged the refinement. **Shape of the error: I wrote a
precision-sounding universal ("only") into a correction whose whole purpose was to replace a
false over-general claim — the same over-generalisation, one level down.** Note the pre-existing
test name `'drops anything level with or behind the camera'` is *true but incomplete* (it does not
claim exhaustiveness), so it is not a defect and is not being changed.

Mutation checks the implementer ran and reported, which is what I asked for in place of the
failing-first step: F3's replacement fails with `'+90°'` when `.normalized` is deleted; F6's
depth-200 assertion fails with `Actual: 269.2820323027551` when the divide is flattened, while the
depth-100 assertion still passes — so the added depth is exactly what makes that test name true.
F5's test was written first and watched fail by execution (`Actual: '-0°'`). F1's premise verified
by the implementer before rewording: `Projected.hidden.screen` is `Offset.zero`. F4 flips the
label when `clamped.dx + 14 + text.width > size.width`, minimal, no new API, no test per my ruling.

Scoped re-review dispatched over `114bf84..7a7b9a5`.

## Task 15 — fix round 1 re-review (agent `aea7295e6b38bbd83`, sonnet)

**All six ADDRESSED, every one by probe rather than argument.** F1: `project(Vec3(0,0,-100))` →
`visible=false, screen=Offset(0.0,0.0)`, `Projected.hidden` is literally `Projected(Offset.zero,…)`,
so the guard is load-bearing and the replacement true. F2: `hudMarkerPoint(Vec3(100,0,100))` →
`Offset(-492.8, 400.0)` — non-null and off-canvas, so the mechanism holds and the sensor-range
claim is gone. F3: `Expected '+37°' Actual '+90°'` with `.normalized` deleted. F5: `Expected '0°'
Actual '-0°'`. F6: flattened → depth-100 passes, depth-200 fails `Expected 234.6410162 Actual
269.2820323027551`. **My twelfth error's refinement confirmed**: camZ `0.5/1.0/2.0` →
`false/false/true`, so the cull is exactly `camZ <= 1.0` and "at or behind the camera's near plane"
is exact where my "only … behind the camera" was not. The false "journey destinations are planets"
line is correctly replaced (`game_controller.dart` encodes planet `:834`, star `:761/:883`, coord
`:770`, resolved `:493-497`). Scope exactly the two files. `git status` empty; HEAD `7a7b9a5`;
`flutter analyze` → `No issues found! (ran in 4.3s)`; `flutter test` → `+315: All tests passed!`.
All three source mutations reverted; the temp probe file deleted. Honest caveat recorded: F4 is
reading plus arithmetic, not a canvas render — no `CockpitHudPainter` was built.

### NEW-1 (LOW) — ACCEPTED, fix round 2

`cockpit_hud.dart:136-138`: the F4 comment says a right-edge marker "would **start** its label
past `size.width`". False — the right clamp is `size.width - 26` and the unflipped label starts at
`size.width - 12`, i.e. 12 px **inside**; it *runs* past. It is false precisely because the label
offset (14) is smaller than the clamp margin (26), so the sentence is backwards in a way that
hides the mechanism. The re-reviewer's sharpest observation: the implementer's own report computes
`size.width - 12` and then calls the comment true — **its arithmetic refutes its wording while
defending its conclusion.** One word to fix: s/start/run/.

**Ruling: fix it, in a second round, despite being one word.** F4 is the only fix in this task
with no test behind it, so that comment is the sole record of why the flip exists — its accuracy
is load-bearing rather than decorative. Cost if wrong: one commit and one scoped re-review.

### PARKED (deferred minor, for the final whole-branch review) — `'360°'`

A bearing in `[359.5, 360)` renders `'360°'` rather than `'0°'` — a rounding artifact of
`toStringAsFixed(0)`, **pre-existing in the brief's original code** and not caused by this round.
**Ruling: park, do not fix.** A compass showing 360° is defensible (360° ≡ 0°), the fix would be an
untested behaviour change with its own wrap-threshold judgment call, and opening a third round for
cosmetic polish on an otherwise-closed task is a worse trade than handing the final reviewer a
named item. Cost if wrong: the readout shows `360°` where `0°` would be tidier.

Fix round 2 of 5 dispatched to the same implementer, scoped to the one word, with the parked item
named explicitly so it is not spent on.

## Task 15 — fix round 2 (`880fc16`) re-review CLEAN → **Task 15: complete**

One word: s/start/run/ in the F4 label-overflow comment. The implementer also corrected the
report's restatement of the same false framing and added the parked `'360°'` item.

Re-review (agent `a6d296a443b10b058`, haiku — cheap tier, justified by a one-word diff): **PASS on
all four checks.** The sentence is true, with the three numbers re-derived independently — right
clamp bound `size.width - 26` (`:91`), label offset `+ 14`, so the unflipped label starts 12 px
*inside* while its right edge crosses `size.width`; the flip condition
`clamped.dx + 14 + text.width > size.width` (`:139`) confirms the end overflows. Diff is exactly
one insertion and one deletion. `git status` empty; HEAD `880fc16`; `flutter analyze` →
`No issues found! (ran in 3.8s)`; `flutter test` → `+315: All tests passed!`. `grep -n "start"
cockpit_hud.dart` returns nothing, so no other comment carries the same claim.

**Task 15 = `114bf84` + fix `7a7b9a5` + fix `880fc16`. COMPLETE.** Suite 315; analyze clean.

Task 16 brief re-extracted (488 lines). Dispatch carries all eight pre-flight rulings.

## Task 16 dispatch + implementer report (`3aa9b20`), DONE

Dispatch (implementer `a2feda16f31f76c3e`, sonnet) carried the brief as the single source of
requirements, all eight pre-flight rulings, and the verified Task 15 API shapes. BASE `880fc16`.
2 files, +386/−1: `lib/ui/galaxy3d/galaxy_map_3d_page.dart` (+250) and `test/cruise_ui_test.dart`
(+137). `flutter test` → **319 passing** (315 + 4 new); `flutter analyze` → `No issues found!`.

All eight rulings applied. Three things the implementer flagged, all worth having flagged:

1. **It added one assertion the brief lacked, for a real coverage hole.** The brief's machine
   tests never asserted the marker layer was mounted — Step 7's manual walkthrough was the only
   check — so **removing the `CockpitHudPainter` from the `Stack` would have passed all 319
   tests**. It added three lines to test 1 finding the single `CustomPaint` whose painter is a
   `CockpitHudPainter` and asserting its `markers` contain `银心`, and falsified it by emptying
   the marker list. **This is the deliverable's own subject matter left unasserted by the brief**,
   and it is exactly the class of gap the pre-flight exists to find but did not. Carried to the
   reviewer to adjudicate rather than accepted on the report's word.
2. **It reworded two brief-supplied comments that were false of the code**: the `cockpit` finder
   doc's "both have a button labelled 修正航向" (the voyage dock has it only *while cruising*) and
   the key comment's "Every cockpit assertion … scopes to this key" (test 1's `对准银心`
   assertion is unscoped). Both narrowed to the true claim. Instances twenty-three and
   twenty-four of the class — and both were **in the brief text**, which is why they reached the
   implementer at all.
3. **`_BottomControls`'s `CameraMode.cockpit` switch arm is now unreachable at runtime**, because
   cockpit mode renders `_HeadingBar` instead. Left in place on the reasoning that the enum switch
   must stay exhaustive and no comment claims reachability. Carried to the reviewer to verify that
   reasoning rather than take it.

End-to-end leg coverage, as the standing note asked: enter cockpit / heading / markers → test 1;
ignite → test 2; correct course → test 3; run dry + activate → test 4.

Review package `review-880fc16..3aa9b20.diff` generated; task reviewer dispatched on opus.

## Task 16 review (opus, `a18e2680980ad9631`) — spec PASS, quality PASS WITH TWO COMMENT DEFECTS

Reviewer wrote `task-16-review.md`. Verdicts:

- **Spec compliance — PASS.** All eight pre-flight rulings applied exactly as ruled; every brief
  step present; nothing silently dropped; scope exactly the two named files.
- **Code quality — PASS WITH TWO COMMENT DEFECTS.** No behavioural defect; both findings are
  comment-only and change no test outcome.

**MEDIUM — the "an unscoped `find.text` would match both" claim is false, in two places.**
`test/cruise_ui_test.dart:249-255` and `lib/ui/galaxy3d/galaxy_map_3d_page.dart:537-540`. Flutter
3.47.6's `_IndexedStackElement.debugVisitOnstageChildren` visits only the selected child, and
default finders walk `skipOffstage: true`. Probed: an unscoped `find.text('修正航向')` while
cruising returns **1**, not 2; `skipOffstage: false` returns 2. The scoping is **defensive, not
required**. "It survived the implementer's reword pass because it sits adjacent to the two
sentences it did fix."

**LOW — the drift-report comment names a mechanism that does not happen.**
`test/cruise_ui_test.dart:344-346` claims the 座舱 tap would be swallowed by the modal sheet's
barrier. The reviewer **removed `acknowledgeDriftReport` and the test still passed, 13/13** — with
a hit-test warning. The tap the barrier actually swallows is the earlier `find.text('星图')` inside
`_pumpStarMap`. Keep the call (it removes the hit-test warning and the timing reliance); fix the
comment.

**Adjudications, all in the implementer's favour:**

1. The **added marker-mount assertion is correct and non-vacuous** — well-formed, `hasLength(1)`,
   and both mutations bite (emptying the marker list fails at `:291`; dropping the painter fails).
   The implementer's catch stands; the brief's coverage hole was real.
2. Both **reworded comments are exactly true** — but a third false sentence sits adjacent to each,
   which is the two findings above.
3. Leaving **`_BottomControls`'s unreachable cockpit arm** is **right**: `_BottomControls` is
   instantiated once at `:577`, in the `else` of overview/cockpit, so `mode` is always `orbit`; the
   switch expression must stay exhaustive; no comment claims reachability.

**Probes the reviewer ran (all reverted; tree byte-identical, files unchanged):** unscoped-finder
count 1 vs 2 · empty markers → fail (`:291`) · drop painter → fail · placeholder `'—  —'` → fail
(`:277`) · mis-price the turn → fail (`:325`) · **remove `acknowledgeDriftReport` → still passes**
(13/13). Re-derived by running: angle **179.86°**, cost **200**, braking **100**, energy before
**200**, `forward.x = -0.999997`; test 4 energy **95**, `secondsForEnergy(200) = 3000.0`. Hexdump:
placeholder **U+2014**, elevation sign **U+2212**; no em dash in any bar `Text`.
HEAD `3aa9b20`; `flutter analyze` → `No issues found!`; `flutter test` → `+319: All tests passed!`;
`cruise_ui_test.dart` → 13 pass.

## My rulings on the Task 16 review

**Ruling: both findings get fixed; no behaviour changes.** — Both are the plan's recurring
false-comment class sitting in **shipped** code, which is the same ground on which Task 14's N1 and
Task 15's NEW-1 were fixed; the code a reader re-derives a claim from is the deliverable, not a
nicety. — Cost if wrong: one comment-only commit and a scoped re-review, ~10 minutes.

**Ruling: keep the scoped finder; correct the comment rather than the finder.** — The scoping is
defensive but genuinely more robust (if a future change ever puts the voyage dock onstage
simultaneously, the unscoped finder breaks); only the *justification* is false. — Cost if wrong:
none; the finder keeps working either way.

**Ruling: keep `await c.acknowledgeDriftReport();`, fix only its comment.** — It removes a hit-test
warning and the test's reliance on tap timing even though it is not load-bearing for pass/fail, and
removing it would re-introduce both for no gain. — Cost if wrong: a test that still passes but
warns, i.e. no functional cost.

**MY ERROR, THIRTEENTH INSTANCE.** The false mechanism in that LOW finding is **mine**: Task 16's
pre-flight (finding 2) asserted that the 座舱 tap "lands on the barrier (dismissing the sheet)
rather than the side control", I adopted it verbatim as a mandated fix, and the shipped comment
repeated my ruling faithfully. The shape is new and worth naming: **I adopted a plausible causal
mechanism from a subagent's report as the justification for a mandated change without requiring
the falsification probe that would have tested the mechanism itself** — I required a probe for the
*fix* ("confirm the call is there") but not for the *claim* ("confirm removing it breaks the
test"). What caught it was the reviewer's adversarial probe, which is the loop working as
designed; what would have prevented it is asking the pre-flight for the same falsification it
demands of every other claim. The pre-flight was otherwise right that the report is queued and its
sheet is modal — it got the *consequence* wrong (the barrier eats the earlier 星图 tap inside
`_pumpStarMap`, not the later 座舱 tap), which is the hardest kind of error to spot by reading,
since every clause of it is individually plausible.

**Carried forward, unchanged:** the two open comment findings are the last work before the final
whole-branch review. Task 16 fix round 1 dispatched by resuming implementer `a2feda16f31f76c3e`.

## Task 16 fix round 1 (`2778785`), DONE — comment-only, both defects fixed

Implementer `a2feda16f31f76c3e` resumed (round 1 of 5). 2 files, +16/−8, comments only: no test
bodies, no lib logic, no new tests. `flutter test` → **319 passing**; `flutter analyze` →
`No issues found!`. Tree clean.

**MEDIUM, both sites.** `test/cruise_ui_test.dart:249-255` and `galaxy_map_3d_page.dart`'s
`_HeadingBar` key comment no longer claim an unscoped `find.text` "would match both". Both now
state that default finders skip offstage children and an `IndexedStack` only visits its selected
one, so an unscoped finder still returns **one** — and both now describe the scoping as
**defensive** (robust to a later change in the finder or the shell) rather than required.

**LOW.** Test 4's comment no longer names the barrier swallowing the 座舱 tap. It now says the
queued report's modal sheet swallows `_pumpStarMap`'s **earlier** `星图` tap, that this is harmless
because the star map is already the default tab, and that acknowledging first removes the hit-test
warning and the dependence on that tap's timing. `await c.acknowledgeDriftReport();` is kept.

The implementer also grepped both files for a third instance and reports none, noting that
`test/cruise_ui_test.dart:105-106` (a pre-existing Task-14 comment) is already correct. **Carried to
the re-reviewer to verify rather than accepted** — the plan's recurring failure is exactly a
false claim surviving next to the sentences that were fixed.

Scoped re-review dispatched (sonnet) with the two findings verbatim, a demand that each new sentence
be *exactly true* rather than merely "not the old false claim", and a specific instruction to
verify the new "already the default tab" premise against `HomeShell` — since that premise is new
this round and no probe has tested it.

## Task 16 fix round 1 re-review (sonnet, `a8e6a57d0794d7f01`) — both ADDRESSED, no new findings

Report `task-16-rereview.md`.

- **MEDIUM — ADDRESSED.** `test/cruise_ui_test.dart:249-256` and
  `galaxy_map_3d_page.dart:1091-1096` now state the true mechanism and describe the scoping as
  *defensive* with a coherent reason. The re-reviewer **reproduced the mechanism from scratch
  rather than trusting the prior review**: while cruising in the cockpit, unscoped
  `find.text('修正航向')` returns **1**, `skipOffstage: false` returns **2**.
- **LOW — ADDRESSED.** `test/cruise_ui_test.dart:346-353` names the swallowed tap correctly. The
  re-reviewer **verified the new "already the default tab" premise against the shell and at
  runtime** — the premise I specifically asked it to test because it was new this round and no
  probe had covered it: initial `IndexedStack.index` is **0** (star map), `_goToTab` no-ops on the
  already-selected tab, and with the report left queued a nav-item tap under the barrier does
  **not** switch tabs (index stays 0). The `acknowledgeDriftReport` call is present and justified by
  what the comment now says.
- **The third-instance check — clean.** `test/cruise_ui_test.dart:105-106` states the true
  mechanism. The implementer's "the only other `IndexedStack` comment in the file" is **loose**:
  there are also mentions at `:56`, `:90`, `:121`, `:251`, `:254`, `:347`, plus
  `galaxy_map_3d_page.dart:377` and `journey_page.dart:31`. The re-reviewer read all of them; none
  makes the false claim.
- **Scope — comment-only**, exactly the two named files, 16 insertions / 8 deletions; no test body,
  no lib logic, no new test. **No new findings.**
- **Regression:** `flutter analyze` → `No issues found!`; `flutter test` → `+319: All tests passed!`;
  tree clean.

**Two INFO notes, ruled:**

**Ruling: park the `_HeadingBar` comment's "in the tree behind this bar".** — In an `IndexedStack`
the unselected child is offstage, not painted behind anything, so the spatial metaphor is loose;
but the very next sentence ("Default finders skip offstage children") removes the ambiguity, and a
reader cannot come away with a false belief about finder behaviour, which is the only thing the
comment is for. Same ground as Task 12's parked minor #2 — a loose metaphor immediately corrected
by its neighbour is not the defect class; the class is a claim that leads a reader to a false
belief. — Cost if wrong: one loose word in a comment that disambiguates itself one line later.

**Ruling: note only, no action — the review's citation `galaxy_map_3d_page.dart:537-540` was
wrong; the real site is `:1091-1096`.** — The finding's *substance* was right and the fix landed at
the right place; only the reviewer's line number was stale, and a stale citation in a scratch
artifact harms nothing. — Cost if wrong: none.

**Task 16 = `3aa9b20` + fix `2778785`. COMPLETE.** Suite **319**; analyze clean; tree clean.

**ALL SIXTEEN TASKS COMPLETE.** HEAD `2778785`. Final whole-branch review dispatched on opus
against `review-fddbc63..2778785.diff`, with `deferred-items.md` as its attention lens.

## FINAL REVIEW (opus, `a2f91176aa127c537`) — verdict: ship-with-fixes

Report `final-review.md`. **Spec compliance is NOT complete.** The review found **six player-facing
spec requirements that were never written into the plan and therefore never implemented**, none of
them among the plan's Six Spec Deviations:

| # | Spec | Requirement | Evidence |
|---|---|---|---|
| H1 | §4.2 | ignition pops `showFuelChoiceDialog` (halt/coast, no refuse) | `galaxy_map_3d_page.dart:214-216` hardcodes `FuelPolicy.coast`; the only `showFuelChoiceDialog` call in that file is the **voyage** path at `:285`; `fuel_choice_dialog.dart` untouched although the plan's own File Structure lists it as **Modify** |
| H2 | §5.3 | ▲ current-heading marker + 「偏离 37° · 63 EN」 readout on `_CockpitPainter` | `_CockpitOverlay` is `const` with no params (`:813`); `shouldRepaint => false` (`:897`); the bar shows the *reticle's* absolute bearing, never the deviation |
| H3 | §5.3 | turn confirmation dialog (paid + irreversible) | `_correctFromCockpit` (`:224-232`) spends immediately, snackbars after |
| M1 | §5.3 | disabled button states + 「前往训练补充能量」 | `_HudButton` (`:1179`) has no disabled state; `onActivate: () => _c.activate()` (`:571`) discards the `Future<bool>`, so a broke 激活 tap is a **silent no-op** |
| M2 | §5.3/§9.4 | entering the cockpit while cruising aims at the current heading | `_setMode` (`:366`) and `_recenter` (`:421`) both always `_aimCockpitAtOrigin()`; `aimCameraAt` has **no production caller** — built for exactly this, exercised only by its own test |
| M3 | §9.1/§9.3 | dormant `_DriftDock` panel; extracted `_EnginePanel` | `_EnginePanel` appears nowhere in `lib/` or `test/`; §9.3 calls the extraction 「本规格唯一的结构性整理」 |

**I verified every one of the six myself** rather than taking the review's word: `grep -rn
igniteCruise lib/` → one caller, `coast`; `grep -rn aimCameraAt lib/` → definition + one doc
reference only; `grep -rn _EnginePanel lib/ test/` → nothing; `_CockpitOverlay` `const` at `:813`;
`shouldRepaint => false` at `:897`; `onActivate` discards the result at `:571`; `_HudButton` has no
disabled state. **All six CONFIRMED.** I also confirmed `halt` and `coast` genuinely differ
(`game_controller.dart:1171` zeroes the velocity on halt), so the dialog would be asking a real
question rather than a distinction without a difference.

**The plan defect, named.** All sixteen tasks are individually well-executed. What the plan got
wrong is that it built the *infrastructure* for these six — the `cruisePolicy` field,
`HudMarker`, `CockpitHudPainter`, `headingLabel`, `aimCameraAt` (with its own test file) — and
never wrote the tasks that wire any of it into the UI. Its Self-Review nonetheless asserts "Every
numbered requirement in the spec maps to a task", which is false for all six, and that false claim
is why none of them surfaced during execution. `aimCameraAt` is the tell: a tested function with no
caller is a task that was planned and then lost.

**What the review confirmed IS right:** the engine, state machine, three invariants (all three
verified empirically with a throwaway probe), the primary player path, and the original defect —
which has a real, non-test UI entry point (§5 of the report names both the parked and the dormant
paths). Suite 319, analyze clean, count attributable to this plan alone, no stray file.

**Also noted:** the branch's remaining defect-class sweep came back clean — all probed claims true,
no `pumpAndSettle` survivor in any plan-added test, and neither of the two refuted premises from
deferred item 8 survives in shipped code. All eight `deferred-items.md` adjudications: **park was
right** in every case.

## Ruling: the six findings are in scope, and the user decides the shape

**Ruling: I stop and ask, rather than ruling alone — the only time I have done so on this plan.**
— **Why:** this is not a finding on implemented work, so the SDD "one fix dispatch" step does not
fit it; the remedy is *new plan text and a new task loop*, which is a phase change. More
decisively, **the user's approval of the plan rested on a false premise** — they said 没问题 to a
document that claimed full spec coverage. An approval obtained on a false claim is not a considered
scope decision, and both readings (the spec is binding → build it; the approved plan is the scope →
ship it) are defensible. Product-shaping choices about their own game are theirs to make; they have
overridden me on exactly this kind of call before (ignition pricing). — **Cost if wrong:** one
question's worth of their time, against ~3 tasks of unrequested UI work on `main`.

**Their answer: 补完六项，再收尾分支** — implement all six, then finish the branch.

**Their answer on the ignition dialog: 按 spec：弹选择框** — the dialog asks halt/coast, offering no
`refuse`. This **overrides the plan's own comment** at `galaxy_map_3d_page.dart:210-213`, which
argued for hardcoding `coast` on the reasoning that a destination-less cruise already expresses the
player's intent. That argument is not stupid, which is exactly why it was worth asking: it is now
formally superseded rather than silently wrong, and `halt` becomes reachable in play for the first
time — which is what deviation 5's entire reserve design was written for.

**Ruling: the remedy is new plan text (Phase 5, Tasks 17-21) executed through the same SDD loop**,
not a single oversized fix dispatch. — **Why:** the SDD fix-round step is for residuals of a
review; six unimplemented requirements with their own test cycles are tasks, and each deserves its
own review gate. — **Cost if wrong:** more dispatches than a single fix round would take.

---

## PHASE 5 — the six spec requirements the first sixteen tasks never reached

**Ruling: the remedy is new plan text (Phase 5, Tasks 17-22) executed through the same SDD loop**,
not a single oversized fix dispatch. — **Why:** the SDD fix-round step is for residuals of a review;
six unimplemented requirements with their own test cycles are tasks, and each deserves its own review
gate. — **Cost if wrong:** more dispatches than one fix round would take.

**User's two answers, which scope this phase:**
- 六项怎么处理 → **「补完六项，再收尾分支」**
- 点火巡航时要不要问玩家 → **「按 spec：弹选择框」** (overriding the plan's own code comment at
  `galaxy_map_3d_page.dart:210-213`, which had argued for hardcoding `coast`)

**Task order is load-bearing, and was decided by reading the code, not the plan's task numbering.**
M2 (aim at the current heading) changes where the cockpit opens, which changes what the *existing*
turn test sees; H1/H3 then change what tapping the buttons does. So: 17 aiming → 18 dialogs → 19
readout → 20 disabled states → 21 voyage dock → 22 the L3-L10 comment sweep.

**Ruling: Task 22 (the L3-L10 false-claim sweep) is in scope** even though the user's instruction
named the six findings. — **Why:** it is the same defect class the branch has fixed twenty-five times
already, and the alternative is knowingly shipping ten false claims in comments. — **Cost if wrong:**
one dispatch spent on comment edits.

**Ruling: two of §9.4's placements move, both for testability.** (1) The current-heading triangle goes
in the public `CockpitHudPainter`, not the private `_CockpitPainter` — the latter's real inputs are a
fixed frame and a centre reticle, so its `shouldRepaint => false` is *true*, and §9.4's instruction to
change it would replace a correct constant with a wasteful one; `CockpitHudPainter` already takes the
camera and already returns `true`. (2) The deviation readout is a real `Text` in the overlay, not a
canvas string, because a canvas string cannot be asserted by any widget test — and the repo's
convention is the opposite (`cruise_ui_test.dart` asserts the bar's `'200 EN'` via `find.text`). —
**Cost if wrong:** the triangle lives one painter over from where §9.4 put it; the readout is one
widget higher in the tree.

**Ruling: the heading marker is drawn only while cruising.** A coasting ship's bar offers a brake
rather than a turn (§5.3's own table), so a turn readout beside a brake button would offer something
the button cannot do. — **Cost if wrong:** a coasting ship shows no course marker.

**The three pre-existing tests Phase 5 rewrites, and why (verified by reading them):**
- `cruise_ui_test.dart` `'a parked ship is offered ignition from the cockpit'` — Task 18 breaks it:
  ignition now opens a dialog, so `isCruising` is not true after one pump.
- `cruise_ui_test.dart` `'a cruising ship is quoted the turn and can take it'` — Task 17 breaks it
  (the cockpit now opens *on* the heading, so the reticle starts at 0° deviation), then Task 18 breaks
  it again (the turn confirms). Replaced by three tests: aiming, a dragged real turn, and recentering.
- `cruise_ui_test.dart` `'the cockpit reads the heading the reticle is pointing at'` — **not** broken:
  it is parked, so its `'对准银心'` assertion still holds. Task 17 changes the label only while cruising.

**Facts verified from the code while writing the plan (do not re-derive):**
- `_ActionButton` (`journey_page.dart:1238`) already takes a nullable `onPressed` and already renders
  the disabled state — Task 21 needs no new flag.
- `canBrake` (`game_controller.dart:983`) is `!hasMomentum || energyBalance >= brakingCost`.
- `turnAngleTo` (`:1330`) is `acos(driftVelocity.normalized · heading.normalized)`, 0 when
  `!hasMomentum` — `headingDeviationDegrees` mirrors it exactly.
- `correctHeading`'s guard is `energy < cost` (`:1356`), so `energy == cost` is allowed; `activate()`
  requires `energyBalance > activationCost` **strictly** (§4.3). The buttons are gated on exactly these.
- `CockpitHudPainter` and `_CockpitOverlay` are **two** separate `Positioned.fill` + `IgnorePointer`
  siblings (`:536-548`), not one painter with a foregroundPainter.
- `ShellScope.go(context, 3)` (`shell_scope.dart:15`) reaches the training tab; `TrainingPage` is an
  `IndexedStack` child, so `find.byType(TrainingPage)` sees it only while its tab is selected.
- `_lookingForward()` / `_vp = Size2(400, 800)` already exist in `cockpit_hud_test.dart`; the viewport
  centre is `(200, 400)` and the HUD safe area is `dx ∈ [26, 374]`, `dy ∈ [74, 668]`.

**Plan committed as `6921705`. BASE for Task 17 = `6921705`.**

## PHASE 5 — correction issued to Task 17 mid-flight (ledger :~1720)

**Two pinned numbers in Task 17's brief were wrong. Both were mine, and both were caught by
re-deriving them against the source after dispatching — not by the implementer.**

**Correction 1 — the on-heading turn costs 0 EN, not 1 EN.**
The brief (and my dispatch note) asserted `inCockpit('1 EN')`, on the reasoning that
`Engine.energyCostFor(0)` floors at `minEnergyCost == 1`. That reasoning is wrong at the call site:
`Engine.turnCostFor` (`lib/data/models/engine.dart:120-124`) opens with `if (radians <= 0) return 0;`,
so the floor is never reached for a zero-angle turn. And the angle is **exactly** zero here, not
merely small: `aimCameraAt` sets `yaw = atan2(1.0, 0.0) == π/2` and `pitch = asin(0.0) == 0.0`, so
`Camera3D.forward` is `(1.0, 0.0, 6.123233995736766e-17)`; `driftVelocity.normalized` is
`(1.0, 0.0, 0.0)`; the dot product is exactly `1.0`; `acos(1.0) == 0.0`; the guard fires.
**The plan's own cost table (line 41) already said `turnCostFor(0°)` = 0 EN** — the brief
contradicted the plan's authority, and the plan was right.
→ All `inCockpit('1 EN')` in Task 17 became `inCockpit('0 EN')`; Task 19's `'0° · 1 EN'` became
`'0° · 0 EN'`; the `reason:` and the Step 6 failure expectation were rewritten to state the guard.

**Correction 2 — the dragged case pins the price, not the angle.**
Task 17's drag test and Task 18's dialog test asserted the literal `180°`. The **price** is safe:
`round(200·sin(θ/2))` stays 200 for every θ ≥ ~172°, so it survives any small error in the drag's
delivered displacement. The **angle** is not safe: whether `tester.dragFrom` delivers the full
523.6 px to `_onScaleUpdate` depends on how `ScaleGestureRecognizer` splits the 20 px touch slop
across its updates, and I have **not** verified it. I did not guess and did not tune the drag until
it printed 180.
→ Both assertions became shape matches — `RegExp(r'偏离 \d+° · 200 EN')` and
`RegExp(r'飞船将从当前航向偏转 \d+°，消耗 200 EN。')` — with the reason written into the plan. The
exact angles are pinned without a drag, in two places that cannot drift: `headingDeviationDegrees`'
own unit test, and the on-heading test (0°, exact, for the reason in Correction 1).

**Ruling: pin a number only where the test owns the input that produces it.** A widget test that
drags owns the *gesture*, not the *displacement* Flutter derives from it; asserting the derived
displacement pins Flutter's internals, and a future Flutter that splits the slop differently turns
a correct implementation red. — **Why:** the same defect class this branch has now fixed 25 times —
a pinned number that cannot be re-derived from the code under test. — **Cost if wrong:** one widget
test asserts the readout's shape rather than its exact degrees, and a bug that shifted the deviation
by a few degrees while leaving the price at 200 would pass it. That bug is caught by the unit test
and the on-heading test, which pin exact angles on inputs the test does own.

**Plan text corrected in place** (lines 41 area unchanged — it was already right; 4525-4600, 4760-4765,
5329-5337 rewritten). Task 17's brief (`task-17-brief.md`) is now stale against the plan; the
implementer was sent both corrections directly by message, and the plan is the authority for every
later brief.

## PHASE 5 — two more plan defects found by re-deriving, before Tasks 20/21 were dispatched

Both are in plan text no implementer has run yet, so both are cheap. Both are the same defect
class as the Task 17 corrections above: a claim in the plan that the code does not support.

**Defect A — Task 21's test 1 asserted a string the panel cannot render.**
Test 1 parks a dormant, empty ship (`energy == 0`) and asserted `find.text('需要 5 EN 激活')`.
But `_EnginePanel` renders `canActivate ? '需要 $cost EN 激活' : '需要 $cost EN（现有 $energy EN）'`,
and with `energy == 0, cost == 5` the gate is false, so the rendered string is
`'需要 5 EN（现有 0 EN）'`. The test would have failed on its own first assertion.
The test's own comment ("Short of the fee, so the button is off") already described the
`canActivate == false` branch, so the string was the only thing wrong.
→ Test 1 now asserts `'需要 5 EN（现有 0 EN）'`, and the `'需要 5 EN 激活'` string moved to test 2,
whose ship has `energy == 100` and therefore does render it. Both branches of the panel's detail
line are now pinned, one per test, instead of one branch pinned twice and the other never.

**Defect B — Tasks 20 and 21 claimed `activate()` is strict. It is lenient.**
Task 20's Interfaces said "`activate()` requires `energyBalance > activationCost` **strictly**", and
Task 21's `_EnginePanel` doc comment said "`activate()` refuses at `energy == activationCost`". Both
are false. `game_controller.dart:1218` is `if (_player.energyBalance < cost) return false;`, so
equality is **allowed** — and the plan specifies exactly that, in its own `activate()` body
(plan line ~2064) with a doc comment saying a player who spends their last 5 EN "ends up awake with
nothing … exactly what they asked for". This is deviation 6 under
`## Spec Deviations (read this before Task 1)`, recorded against §4.3's strict rule. So the plan
contradicted itself: its controller is lenient, its Phase 5 prose said strict.

The consequence was not cosmetic. Task 20 specified `canActivate = energy > activationCost` — a
button that is **disabled** at exactly 5 EN while its own detail line reads 「需要 5 EN（现有 5 EN）」.
A message contradicting its own disabled state is a defect regardless of which guard is right.

**Ruling: the button gate is `energy >= activationCost`, matching `activate()`.**
— **Why:** Task 20's stated principle is that the buttons are gated on *the controller's own
predicates*, or a button offers an action that then refuses. `>=` is the controller's predicate; `>`
was not. And the strict form is the one that produces the self-contradicting label.
— **Cost if wrong:** a player holding exactly 5 EN may wake the engine and sit awake with an empty
tank. §4.3 calls that a strange state. It is deviation 6's accepted cost, not a new one, and every
action is gated on energy, so it is a state they can see out of.

**Ruling: `activate()`'s own guard is NOT re-opened.** The SDD skill resolves plan-internal conflicts
against the spec, and §4.3 wants the strict rule — so there is a case for changing `:1218` to
`>`. I am not taking it: deviation 6 is a recorded, reasoned, *deliberate* deviation with its own
doc comment, it is built and reviewed across Tasks 1-16, the final whole-branch review did not raise
it, and the user's instruction was to close the six findings and wrap the branch. Re-opening a
settled controller rule inside a UI task is scope the user did not ask for.
— **Cost if wrong:** the deviation from §4.3 stands, and a player can be awake at 0 EN. It is
visible, bounded, and reversible in one line if the user wants §4.3 verbatim.

**Verified while checking (do not re-derive):**
- Tab index 3 is `TrainingPage` (`home_shell.dart:35-42`, children 星图/航行/播报/训练), so
  `ShellScope.go(context, 3)` is right.
- `panelDecoration({color, radius, border})` (`theme.dart:76`) accepts the plan's
  `panelDecoration(radius: 12, color: StarColors.panelLight)`.
- `StarColors.gold`/`.danger`/`.faint`/`.cyan`/`.offWhite`/`.panelLight` all exist (`theme.dart:19-34`).
- `StarPanel({child, padding, margin, color, radius})` (`common.dart:91-105`) accepts the plan's call.
- `ShellScope` is already imported in `journey_page.dart:12`.
- `'引擎休眠中 · 生命维持与照明已停止'`, `'_EnginePanel'` and `'EN 激活'` appear **nowhere** in
  `lib/` or `test/`, so there are no collisions.
- A parked deep-space ship renders `_DriftDock`, not `_CoastDock` (`journey_page.dart:371-381`
  selects on `coasting || cruising` / `drifting` / else). So Task 21 test 1's
  `find.text('前往训练补充能量')` cannot double-count against `_CoastDock`'s existing one at
  `journey_page.dart:875` — that one only renders when `!canBrake`, and it is in the other dock.
  Task 21 test 2's `findsNothing` holds because its ship has 100 EN, so `canBrake` is true and
  `canActivate` is true: neither shortcut renders.
- `correctHeading`'s guard is `if (energy < cost) return false;` (`:1356`) — the **live** `energy`,
  which is what Task 20's `canTurn = energy >= turnCost` uses. Exact match, no adjustment needed.

## PHASE 5 — two more plan defects, Task 18 (found by re-deriving, before dispatch)

**Defect C — Task 18's `c.cruisePolicy` would not compile.**
`GameController` has **no** `cruisePolicy` getter. The field is `PlayerState.cruisePolicy`
(`player_state.dart:78`), read internally as `_player.cruisePolicy` (`game_controller.dart:1165`,
`:1319`). Every existing test reaches it as `c.player.cruisePolicy` (`cruise_test.dart:232`) or on a
`PlayerState` directly. The plan's assertion `expect(c.cruisePolicy, FuelPolicy.halt, …)` was a
compile error, not a test failure.
→ Now `expect(c.player.cruisePolicy, FuelPolicy.halt, …)`.

**Defect D — the new cruise dialog hardcoded the braking reserve.**
Task 18's `showCruiseFuelChoiceDialog` takes `required int braking` and then rendered
`detail: '电量耗尽前引擎先制动停下，保留 100 EN 的制动储备'` — a literal `100` where `$braking` was
already in scope. The reserve is `Engine.brakingCostFor`, which is engine-derived, so a ship with a
different engine would be quoted a number that is not its own. That is precisely the failure
CLAUDE.md's first structural rule exists to prevent, and it is the same defect class as the
`_ActionButton`/`pinned number` family this branch has fixed 25 times. The pre-existing
`showFuelChoiceDialog` in the same file interpolates **every** number (`$afterBraking`, `$energy`,
`$reach`, `$distanceLy`), so the new copy was also inconsistent with its own file.
→ Now `'…保留 $braking EN 的制动储备'`.

**Verified while checking Task 18 (do not re-derive):**
- `fuel_choice_dialog.dart` is **already imported** at `galaxy_map_3d_page.dart:11`, and the file
  already calls `showFuelChoiceDialog` at `:285`. So Task 18's "add the import if it is not already
  present" is a no-op, and Step 4's call site does not collide with the voyage path.
- The cruise dialog deliberately offers the halt/coast pair **unconditionally**, unlike the voyage
  dialog's `if (energy > braking)` guard. That is right: a voyage's guard exists because the trip's
  range is the thing being decided, and a cruise has no trip — but `igniteCruise` still *requires* a
  policy, so the pair must always be offered. The plan's Step 3 comment says this.
- Task 18's confirm dialog interpolates (`$degrees`, `$cost`) with no literals, and its
  `find.text('修正航向'), findsNWidgets(2)` is sound: the bar's button and the dialog title are both
  onstage on the star map tab, while `_CoastDock`'s identically-labelled button is offstage
  (deferred-items confirms unscoped `find.text('修正航向')` returns 1 while cruising, 2 with
  `skipOffstage: false`).
- `StarColors.deepNavy` exists (`theme.dart:14`), so the `AlertDialog` background is fine.

## PHASE 5 — Task 17 complete: `3cfc492`

**Status: DONE_WITH_CONCERNS.** `flutter analyze` → `No issues found!`; `flutter test` → **322**
(319 + 3 net new). Four files, +163 −19. TDD followed (unit test red → green; three widget tests red
→ `_aimCockpit`/`recenterLabel` → green).

**Defect E — mine, in the plan text I edited mid-flight.** When I converted Task 17's drag test to
shape-match the degrees, I inserted `expect(find.textContaining(RegExp(r'偏离 \d+° · 200 EN')), …)`
into it. The `偏离 N°` readout is **Task 19's** deliverable (`_CockpitOverlay`'s `Text`); at Task 17
time the bar's detail is `'$turnCost EN'` and no `偏离` string exists anywhere
(`grep -rn 偏离 starward/lib starward/test` → nothing). So Task 17's Step 9 ("Expected: PASS") was
impossible as written, and the assertion also contradicted Task 19's Step 8, which says the regex
"still matches" — it cannot match before it is written.
The implementer omitted the line and said so, which is the correct call.
→ **Ruling: the implementer's omission stands and the plan is corrected, not the code.** The `偏离`
assertion is removed from Task 17's drag test and Task 19's Step 8 now **adds** it rather than
claiming it already matches. — **Why:** the readout is Task 19's product; asserting it a task early
is a forward dependency, and this is the second time I have written one into Phase 5 (the first was
my initial draft's Task 17/Task 19 inversion, which I caught before committing). — **Cost if wrong:**
none; the degrees are still pinned by `headingDeviationDegrees`' unit test and the on-heading test,
and Task 19 adds the readout assertion.

**Concern: the recenter label is not tappable at the 800×600 test viewport.** `tester.tap(find.text('对准当前航向'))`
misses — the side controls sit at the vertical centre and the heading bar's panel reaches up to
y ≈ 396, covering the label's centre at y ≈ 403, so the tap lands on the panel. The implementer taps
`find.byIcon(Icons.my_location_rounded)` (y ≈ 369, clear of the panel, and the same `_RoundButton`
gesture target) with a comment stating the measured geometry.
**Ruling: accept the icon tap, and park the occlusion itself as pre-existing.** — **Why:** the
overlap is between Task 16's heading bar and the pre-existing `_SideControls`, not something Task 17
created; Task 17 only renamed the label. It is not one of the six findings Phase 5 exists to close.
The icon tap still exercises the button's `onRecenter`, and the *label* is separately pinned by
`find.text('对准当前航向')`, so nothing is left unpinned. — **Cost if wrong:** a control whose label
is unclickable at some viewport sizes ships unremarked. Flagged in the ledger and for the final
report; worth the user's eye, but not a Task 17 fix.

**Confirmed: the drag delivers 173°, not 180°.** Measured by the implementer:
`ScaleGestureRecognizer` absorbs ~20 px of touch slop, so 503.6 px × 0.006 = 3.0216 rad = 173.1°.
This is exactly the uncertainty I refused to guess at, and it validates making the price — not the
angle — the assertion: `round(200·sin(86.5°))` = **200**, unaffected. Every drag-dependent price in
Tasks 18-20 is therefore still correct, and every exact-degree assertion was already moved off the
drag. Had I pinned `180°` in Task 17's test and Task 18's dialog copy, both would have failed.

**Confirmed: `0 EN` on the heading.** `energyCostFor(0)` is 1, but the bar calls `turnCostFor`,
whose `if (radians <= 0) return 0;` guard fires because the angle is exactly zero. Engine untouched.

**Verified while checking Task 19's pinned values (do not re-derive):** `_vp = Size2(400, 800)` gives
the safe area `dx ∈ [26, 374]`, `dy ∈ [74, 668]` — matching `clampHudPoint`'s assertions
(`26`, `374`, `74`, `668`) and `headingMarkerPoint`'s edge pins.

## PHASE 5 — Task 22's table verified against the code; three of its own rows were wrong

Task 22 is a comment-only sweep of ten false claims (L3-L10 + two INFO notes). I re-derived every
row before it can be dispatched, because a sweep whose *own* instructions are wrong sends an
implementer to "fix" a true comment — and would have produced three new false claims.

**Confirmed real, table correct (7 of 10):**
- **L3** `cruise_ui_test.dart:49` — `_enterCockpit`'s doc says "the regression test **above**"; the
  post-frame cockpit-request test it names is `:83`, below. ✅ false.
- **L4** `cruise_test.dart:117` — named "secondsForEnergy inverts the burn exactly" but never calls
  `burnForSeconds`, and the inversion fails at 0: `secondsForEnergy(0) == 0.0` while
  `burnForSeconds(0) == 1` (`energyCostFor`'s `minEnergyCost` floor). ✅ false.
- **L6** `cockpit_hud_test.dart:42` — "the true `asin(3/5) = +37°`". `asin(0.6) = 36.8699°`; the
  readout rounds it to `+37°`. ✅ false as an equation.
- **L8** `camera_aim_test.dart:42-45` — "the two `const` expressions canonicalise to one instance".
  There is **one** `const eye = Vec3(5, 6, 7)` declaration; `eyeOverride` is assigned that instance
  and compared against the same name, so it is an identity check on one object. ✅ false.
- **L9** `heading_test.dart:93-95` — see the correction below; real, but the table's figure was wrong.
- **L10** `cruise_test.dart:654` — "still the **nearest** candidate". `recommendedDestination`'s own
  doc (`game_controller.dart:986-990`) says "Nearest not-yet-explored planet, **preferring the
  hand-authored hero worlds**", so the winner need not be nearest. ✅ false.
- **INFO 1** plan `:4329` — the Self-Review's "Every numbered requirement in the spec maps to a task"
  is false: it maps §5.3 → T15/T16 and §9 → T12, and Phase 5 exists because neither reached the UI.
  ✅ false.
- **INFO 2** plan `:4353` — "Four deviations" against the top-of-plan section's **six** (items 1-6 at
  plan `:55-60`, confirmed by counting). ✅ false.

**Table rows corrected — the plan's own justification was wrong (3 of 10):**

- **L5** — the table said to reword the `reason:` as "the round-trip preserves each kind's wire name".
  **That is the next test's job** (`cruise_save_test.dart:30`, `'the new kinds survive a save round
  trip'`). The assertion actually compares a **7-member** set literal against
  `EnergyTxType.values.length`, so what it pins is that the enum is *exactly* those seven kinds.
  The row now says that, and says not to reuse the round-trip wording.
- **L7** — the table called the comment false ("it also asserts `visible` and `dy ≈ 300`"). It is not
  false, only ambiguous: the "only" is scoped to the **dx** assertion and is true — that test's dx
  assertion is `(p.screen.dx - 400).abs() > 1` (`galaxy3d_projection_test.dart:44`), which states the
  magnitude and not the sign, which is exactly the comment's point. The `visible` and `dy`
  assertions the table cited are in *that other file* (`:43`, `:45`), not in this comment's subject.
  **Had I dispatched this row as written, the implementer would have added two assertions to a
  comment about a different file — creating a new false claim while removing none.** The row now
  says "ambiguous, not false", prescribes the minimal disambiguation, and forbids listing
  `visible`/`dy`.
- **L9** — the table said "the real tightest half-step is ≈ 0.33°". Re-derived: `turnCostFor` is
  `round(200·sin(θ/2))`, so it reads exactly 100 for `θ ∈ [59.673°, 60.165°]` — that is **0.327°
  below 60° and 0.165° above it**. The plan's 0.33° is the *downward* half-width, which is the
  **widest** safe half-step, not the tightest; the tightest is **0.165°** upward. The row now states
  the band (`θ ∈ [59.67°, 60.17°]`) and the assertion's ±0.5° is justified against it, instead of
  substituting one wrong superlative for another.

**Ruling: Task 22's scope is unchanged — still ten comment-only edits, still in scope.**
— **Why:** the defect class is the branch's recurring one (a claim that cannot be re-derived from the
code it describes), Task 22 exists to clear the last ten of them, and the three row corrections make
the instructions true rather than widening them. No behaviour, no assertion, and no pinned number
changes. — **Cost if wrong:** one dispatch spent on comment edits, and L7's one-word clarification is
below the noise floor of a useful change.

## PHASE 5 — Task 18's brief pre-flighted against source, before dispatch

Task 18 is the ignition dialog (H1) and the turn confirmation (H3). I re-derived every claim in its
brief that a reviewer would otherwise have to take on faith. Verified **true**:

- `headingDeviationDegrees` is `int headingDeviationDegrees({required Vec3 current, required Vec3
  proposed})` at **`cockpit_hud.dart:48`** — whole degrees by design, so `$degrees°` renders `173°`
  and the brief's `RegExp(r'…偏转 \d+°，消耗 200 EN。')` matches. Had it returned `double`, the copy
  would render `173.0°` and that regex would not match — a silent failure the brief's own comment
  ("the angle is matched by shape") would have hidden.
- `galaxy_map_3d_page.dart` already imports **both** `cockpit_hud.dart` and
  `../journey/fuel_choice_dialog.dart` (lines 13 and 10), so Step 4's "add the import if it is not
  already present" is a no-op — harmless, and correct as written.
- `fuel_choice_dialog.dart` already imports `dart:math as math` (line 1), so the new function's
  `math.max` compiles without a new import.
- `_Choice`'s signature is exactly `{label, detail, icon, onTap}` (`:103-113`) — the brief's four
  call sites match it.
- `StarColors.offWhite`, `.muted`, `.faint`, `.cyan`, `.deepNavy` all exist (`theme.dart:15-30`).
  My own earlier verification note listed only some members; the list was incomplete, not wrong.
- `GameController.ship` (`:226`), `brakingCost` (`:303`), `energy` (`:456`), and
  `Engine.reachableLyFor(int) → double` (`engine.dart:73`) all match the brief's Interfaces block.
- **The `find.text('修正航向') == 2` assertion holds:** the cockpit heading bar's button is
  `galaxy_map_3d_page.dart:1166` and the dialog title is the second; the voyage dock's button
  (`journey_page.dart:853`) is an `IndexedStack` child that the default finder skips.
- **No collision on either new button literal:** `'取消点火'` appears in no file under `lib/`, and
  `'修正'` as an exact literal appears in none at all. `'取消'` as an exact literal appears only at
  `journey_page.dart:290`, inside the voyage page's `_confirm` — offstage in every test that opens
  the turn dialog.
- **The dialog's arithmetic is true under deviation 5.** The copy says both policies exhaust at the
  same place, and deviation 5 (plan `:59`) says exactly that: "both policies exhaust at
  `balance − 100` = 80 ly and end dormant with 100 EN". §4.2's own table disagrees (it has `coast`
  reaching 120 ly and ending at 0 EN) — but deviation 5 is the recorded, binding resolution and
  explicitly says it overrides §4.2. So the copy follows the plan, not the spec's arithmetic.
- **§5.3's dialog copy is reproduced verbatim:** spec `:288` reads 「飞船将从当前航向偏转 37°，消耗
  63 EN。」 with 「取消」/「修正」 buttons, which is character-for-character what the brief's
  `_correctFromCockpit` builds.

**Defect found and fixed in the plan — Step 2's failure expectation was not what happens.**
It read "no dialog appears … and the turn spends immediately, so `c.energy` is already 0 when the
confirm test checks `before`". Two things wrong: `before` is captured *before* the tap, so it is
200 EN, not 0; and the assertion that would notice is `expect(c.energy, before)`, which **never
runs**, because `expect(find.text('修正航向'), findsNWidgets(2))` fails first (the bar's button
exists, the title does not). The old text described a failure that cannot occur, in a task whose
whole point is that its tests fail first and pass after. Step 2 now names each test's actual first
failing surface, including that the two tap-based tests fail by the finder matching nothing.

**Ruling: Task 18 adds a second top-level function rather than calling `showFuelChoiceDialog`.**
— **Why:** §4.2's literal text says 「弹出与出发同一个 `showFuelChoiceDialog`」, but that function's
signature requires `cost` and `distanceLy` and its headline is `能量不足以飞完全程`; a cruise has no
全程, so reusing it means inventing a distance and printing a false headline above a true sheet. What
§4.2 asks to reuse is the 措辞与选项形状, and the new function reuses all of it: the same `_Choice`,
the same two labels verbatim, the same halt/coast pair, the same pop-with-null back-out, and no
`FuelPolicy.refuse`. — **Cost if wrong:** one function that could have been a parameter, and a
reviewer round spent on a disagreement that changes no behaviour. The plan now carries the argument
so the reviewer rules on it rather than rediscovering it.

## PHASE 5 — Task 17 COMPLETE (review: spec PASS, quality PASS)

Reviewer `aefe44db2e173fca4`, on `sonnet`, over `review-49ec1cf..3cfc492.diff`. Report at
`task-17-review.md`.

**Both verdicts PASS.** `flutter analyze` → `No issues found`; the two touched test files → 26
passed. The reviewer re-derived every pinned number in the diff and reports the branch's recurring
defect class clean on this task. It also confirmed the implementer's report where checkable — the
0 EN arithmetic, `aimCameraAt` having had no production caller before, the 173°/slop explanation,
and the measured recenter rectangles. **The working tree is clean and the probe file it wrote
(`zz_probe_rect_test.dart`) is gone** — deferred item 7's hazard, resolved.

The reviewer's own verification worth keeping:
- On-heading turn is **0 EN** exactly: `forward = (1.0, 0.0, 6.123e-17)`, dot `1.0`,
  `acos(1.0) == 0.0`, and `turnCostFor` opens with `if (radians <= 0) return 0` (`engine.dart:120`).
- Bearing **90°**, elevation **+0°**; the `90°` assertion is falsifiable — the pre-fix aim reads
  ~270°, so both rewritten tests genuinely pin the new behaviour.
- The price threshold is **171.88°** and the drag's ~173° clears it.
- The recenter-tap comment is accurate **to the pixel**: panel top y=397, label centre y=403
  (covered), icon centre y=369 (clear).

**Five nits, none blocking. Rulings:**

- **Nit 1 — `headingDeviationDegrees` has no production caller, and its doc speaks of "the
  readout", which does not exist yet. Ruling: park.** — **Why:** Task 19 is the very next dispatch
  and both of its readout sites call this function (Step 6's overlay and Step 7's button detail), so
  the window in which the doc is ahead of the code is one task long. — **Cost if wrong:** a
  forward-looking doc comment in shipped code, made true or false by whether Task 19 lands.
- **Nits 2, 3 and 4 — folded into Task 22 as rows L11, L12 and L13** rather than fixed as an
  unreviewed drive-by or spent on a Task 17 fix round. Task 22 exists to sweep exactly this class,
  is reviewed as a unit, and is the last task, so nothing ships in between. Each is verified below.

**Ruling: Task 17 is complete; its nits ride in Task 22 rather than reopening it.**
— **Why:** both verdicts passed and none of the five is load-bearing; the alternative is a fix round
plus a re-review for three comment corrections that a task already exists to make. — **Cost if
wrong:** the three comments stay false until Task 22, and if Task 22 is dropped they ship.

**The three folded nits, each re-derived from source before being written into Task 22:**
- **L11** `galaxy_map_3d_page.dart:407` — `_aimCockpit`'s doc claims the cruising aim is the heading
  "exactly". `aimCameraAt` ends with `camera.clampPitch()` (`camera3d.dart:268`), which pins the
  pitch to `±(π/2 − 0.05)` (`:80`), so it is the precise inverse only for a heading more than
  `0.05 rad = 2.865°` from a pole. **False as written**, unreachable in practice (the drag clamp is
  the same one, so `driftVelocity` cannot land there) — exactly the kind of claim this branch has
  been correcting all along.
- **L12** `galaxy_map_3d_page.dart:437-439` — `_recenter`'s comment says what the button means
  "depends on whether the ship is **under way**". A coasting ship is under way and gets the galactic
  centre; the predicate the code branches on is `isCruising`. **False as written**, and the same
  sentence's two-case enumeration is right, so only the name is wrong.
- **L13** `cockpit_hud.dart:37` — the doc link `[GameController.turnAngleTo]` cannot resolve:
  `cockpit_hud.dart` imports only `dart:math`, `flutter/widgets.dart` and `camera3d.dart`. Not a
  false claim, a dead link; `comment_references` is off so analyze stays clean.

## PHASE 5 — Task 19's brief pre-flighted; THREE defects found, two of them blocking

Task 19 is the HUD triangle and the 偏离 readout (H2). I derived its projection arithmetic by hand
rather than trusting the brief, and the brief was wrong about it in two places — plus one assertion
it explicitly told the implementer **not** to change, which would have failed.

**Defect 1 (blocking) — Step 5 writes `StarColors.cyan` in a file that cannot name `StarColors`.**
`cockpit_hud.dart` imports only `dart:math`, `package:flutter/widgets.dart` and `camera3d.dart`, and
contains no `StarColors` reference at all — marker colours arrive as `HudMarker.color`. The new
`this.headingColor = StarColors.cyan` default does not compile until `import
'../../core/theme.dart';` is added, and the brief never mentioned it. Step 5 now says so, with the
reason. **This one would have blocked the implementer at Step 5 and cost a round.**

**Defect 2 (blocking) — Step 8 said `inCockpit('200 EN')` needs no change, and it does.**
That assertion is a `find.text` **exact** match against the button's `detail`, and Step 7 is what
turns that detail from `'200 EN'` into `'173° · 200 EN'`. Left alone it matches nothing and Task 19's
own Step 9 fails. The brief could not simply pin `inCockpit('173° · 200 EN')` either — that is the
same over-tightening its own regex warning forbids. Step 8 now replaces it with a shape-matched
descendant finder, `find.textContaining('· 200 EN')` scoped to `cockpit-heading-bar`, and records why
that is unique there: the HUD readout carries the same `· 200 EN` but lives in `_CockpitOverlay`, a
sibling layer and not a descendant of the bar. **I checked every other `inCockpit(...)` assertion in
the file (there are eleven) and this is the only one Task 19 breaks.**

**Defect 3 — two false numbers in the nudge's own justification, both stated as fact.** Derived by
hand: `Camera3D.project` culls at `camZ <= 1.0` and the raw marker `camZ` at distance 400 is
`400·cos θ`.
- Without the nudge the cull boundary is `acos(1/400) = 89.86°`, so **every** course from abeam to
  dead astern loses its marker — the whole rear hemisphere. The brief claimed the boundary was a
  sliver: "an 89.9° course would pin to the side edge and a 90.0° one would vanish". Both halves are
  false: 89.9° is culled too, and a culled marker takes the bottom-edge fallback, not the side edge.
- With the nudge the boundary is **104.33°** (solving `(cos θ + 0.25)/√(1.0625 + 0.5cos θ) = 0.0025`),
  so the band still pinned to the bottom is **75.7°** around dead astern. The brief said "within ~15°
  of dead astern" — the 15° is the *improvement* the nudge buys (89.86° → 104.33° = 14.47°), not the
  size of the culled band.

Both comments are now correct, and the test's expectation `Offset(374, 400)` for an abeam course
still holds — I confirmed the raw point projects to `dx ≈ 2971` and clamps.

**Also corrected: three stale line references**, all drift from Task 17's own additions to
`galaxy_map_3d_page.dart`. The clamp is at `:114-116`, not `:90-93`; `_CockpitOverlay` is at `:836`,
not `:812`; the marker layer mounts at `:556-566`, not `:541-548`. An implementer sent to the wrong
line looks at the wrong widget.

**Verified true in Task 19's brief:** `_lookingForward()` (eye at origin, yaw 0, pitch 0, fov 60) and
`_vp = Size2(400, 800)` both exist in `cockpit_hud_test.dart`; the safe area `dx ∈ [26, 374]`,
`dy ∈ [74, 668]` follows from those; all four `headingMarkerPoint` expectations re-derive, including
the dead-astern fallback `Offset(200, 668)`; `_CockpitOverlay` is `const` today so Step 6's "stops
being `const`" is right; `shouldRepaint` is `true` at `:173` **with** the comment Step 5 cites; the
existing clamp is reproduced exactly; `_HeadingBar.build` already has both `heading` and `turnCost`
in scope so Step 7's `deviation` computes; `_HudButton` renders `detail` as its own `Text` (Task 17's
`inCockpit('0 EN')` passing is the proof); and no test constructs `CockpitHudPainter`, so the new
optional parameters break nothing.

## Task 18 — complete (implementer), review dispatched

- BASE `575cd98`, implementer `a339cd41b10636781` (sonnet), status DONE.
- Commit `6b9a842` — `feat(starward): ask how a cruise should end, and confirm the turn`
  (3 files: `fuel_choice_dialog.dart`, `galaxy_map_3d_page.dart`, `cruise_ui_test.dart`).
- Tests: `flutter test test/cruise_ui_test.dart` 17/17; full suite 324 pass (322 + 2 net);
  `flutter analyze` → No issues found.
- Review package: `review-575cd98..6b9a842.diff` (1 commit, 15073 bytes).
- Reviewer `ae3513dbf18bf82fb` (sonnet) dispatched with brief + report + package.
- Implementer's two concerns, both adjudicated:
  - *Brief said `findsNWidgets(2)` reads 1; it reads 0.* Confirmed by source, not just by its
    word: `correctHeading` calls `_syncDormancy()` at `game_controller.dart:1401`, so the 200 EN
    turn empties the tank and the ship goes dormant, and the bar drops its `修正航向` button.
    Plan corrected — see `0f3c098`.
  - *The `fuel_choice_dialog.dart` import was already present.* No action; the brief's
    conditional phrasing was satisfied.

## Task 20 — pre-flight (two defects fixed in the plan)

Ruling: **Task 20 Step 2's failure expectation was rewritten to name each test's actual first
failing surface.** It claimed the first test's tap "spends nothing only because the drag produced
a cost of 200 against 140 EN, so `correctHeading` refuses and the snackbar fires instead". That
was true before Task 18 and is false after it: the tap now opens a confirm dialog, so the test
stops on `expect(inCockpit('需要 200 EN（现有 140 EN）'), findsOneWidget)` — a surface that does
not exist yet. The rewrite also warns not to delete the tap-and-assert block as "already passing",
since without the `findsOneWidget` above it the block cannot tell the two behaviours apart.
— Cost if wrong: an implementer reads a failure mode that is not the one it sees, and may chase
the snackbar instead of the missing detail line.

Ruling: **Task 20 Step 4's `showBrakeHint` comment was replaced.** It claimed "a broke ship is
not told to brake instead when it cannot brake either". `canBrake` is
`!hasMomentum || _player.energyBalance >= brakingCost` (`:983`) and reads the *unburned* balance,
which while cruising sits at the pre-burn value and can never be at or below the reserve —
ignition requires `balance > braking`. So the conjunction is always true in the cockpit's cruise
state and the hint's visibility is still decided by `turningIsDearer` alone. The comment now says
that, and says the conjunction is there so a future change to `canBrake` moves the hint with it.
— Cost if wrong: a comment that teaches the next reader a guard does work it does not do.

## Task 21 — pre-flight (three defects fixed in the plan)

Ruling: **Task 21 Step 1's two `canActivate` comments corrected from `energy > cost` to
`energy >= cost`.** Step 3's own code is `final canActivate = energy >= cost;`. At `0` vs `5`
both read false, so the test passed either way — which is exactly why the false claim would have
survived. — Cost if wrong: none; the code is unchanged and the comment now matches it.

Ruling: **Task 21 Step 1's second test gained a note about a second guard on its `findsNothing`.**
`find.text('前往训练补充能量')` must find nothing on a *coasting* dormant ship, and `_CoastDock`
renders on that screen carrying its own button with that label (`journey_page.dart:875`). That one
is gated on `if (!canBrake)`, and the coasting ship's unburned balance is exactly the 100 EN
reserve, so `canBrake` is `100 >= 100` and its button is hidden too. Both guards happen to agree;
only the first is this task's. Named so a future failure is not misread. — Cost if wrong: none
today; it saves a debugging detour later.

Ruling: **Task 21 Step 4's `onActivate: () => _c.activate()` corrected to `() => c.activate()`.**
`journey_page.dart` contains no `_c` — that is `galaxy_map_3d_page.dart`'s field. The controller
local at both mount sites (`:372`, `:380`) is `c`. Left as written, this would not compile.
— Cost if wrong: none; it is the only name that resolves.

Plan corrections committed as `0f3c098` (five false claims across Tasks 18, 20, 21).

## Task 19 — pre-flight (three defects fixed in the plan, `a3d1805`)

Ruling: **the "pins to the side edge" test's expectation changed from `Offset(374, 400)` to
`Offset(26, 400)`.** `Camera3D.project` builds `right = forward × up`; for a forward of +Z that is
**−X**, so world −X is screen-right and a `+X` course lands left of centre. Derived, not guessed:
`nudged = normalize((1,0,0) + 0.25·(0,0,1)) = (0.97014, 0, 0.24254)`, so `rel = (388.06, 0, 97.01)`,
`camZ = 97.01`, `camX = rel·(−1,0,0) = −388.06`, and `sx = 200 + (−388.06/97.01)·692.82 = −2571.7`,
which clamps to 26. The repo already pins the convention — `cockpit_hud_test.dart:67-88`,
"Which world direction is 'screen right' … is not the one you would guess", with
`(−10,0,100) → dx ≈ 269.28`. The plan's other four marker tests all check out:
`(0,0,1) → (200,400)`, `(0,1,0) → (200,74)`, `(0,0,−1)` is culled and takes the bottom fallback
`(200,668)`, and `(0,0,0) → null`. — Cost if wrong: none now; left alone it would have cost the
implementer a debugging round on a function that was correct.

Ruling: **`clampHudPoint`'s doc stopped claiming `_BottomControls` "is pinned below 132".** There is
no `132` in `galaxy_map_3d_page.dart`; `_CockpitPainter` insets by `14` with `+48` / `+40`
(`:905-907`), and `_BottomControls` is bottom-aligned with 16 px padding and a content-sized panel.
The 132 is an empirical bottom margin. The doc now uses the existing comment's own wording —
"the panel pinned to the bottom of the screen" — which is all the source supports.
— Cost if wrong: none; it removes a claim nothing could verify.

Ruling: **`hasCourse` changed from `_c.isCruising` to `_c.hasMomentum && !_c.isDormant`, for both the
readout and the triangle, and two tests were added to pin it.** The plan justified `isCruising` with
"the bar offers a coasting ship a brake rather than a turn" — false.
`_HeadingBar.build` branches `if (dormant) … else if (!moving) … else` with
`moving = controller.hasMomentum` (`galaxy_map_3d_page.dart:1186-1206`), so a *coasting* ship takes
the same `else` branch as a cruising one and is offered a real, priced 修正航向 — `correctHeading`
sets `driftPowered: true`, re-lighting the engine as it burns. Gating on `isCruising` would have
withheld the triangle and the readout exactly when the bar offers the turn. The new predicate *is*
the bar's condition, which is the argument — it holds in every reachable state by construction, so
it needs no enumeration. The `!isDormant` half is load-bearing and reachable: a dormant ship that is
still coasting has a real velocity, and quoting a turn price beside a 激活引擎 button would offer
something that button cannot do. Pinned by a new test that reaches that state the same way Task 21's
test does. — Cost if wrong: a coasting player sees no course marker or deviation readout, and the
bar's turn offer is unpriced.

Also refreshed Task 19's stale line refs to post-Task-18 values (`_CockpitOverlay` `:836` → `:872`,
marker layer `:556-566` → `:590-603`), verified by reading the file at `6b9a842`.

Verified true, no change needed: `hudMarkerPoint`'s `world:` named param; `project`'s
`camZ <= _near` cull and `sy = h/2 − camY/camZ·focal`; `focalFor = (h/2)/tan(fov/2)` = 692.82 at
400×800/60°; `_vp = Size2(400,800)` and `_lookingForward()` in the test file; exactly one
`CockpitHudPainter` mount; `偏离` appears nowhere in `lib/` yet, so the new `findsNothing` is safe.

## Task 18 — review verdict and fix round 1 (COMPLETE, `6b9a842` + `37c6ada`)

**Spec: PASS. Quality: FAIL** — one blocking finding, two non-blocking.

**Finding 1 (BLOCKING) — the ignition sheet quoted a braking reserve of 0 EN.**
`galaxy_map_3d_page.dart` passed `braking: _c.brakingCost` to `showCruiseFuelChoiceDialog`.
`brakingCost` is `hasMomentum ? brakingCostFor(driftVelocity.length) : 0` (`:303`) and the
点火巡航 button renders only in `_HeadingBar`'s `else if (!moving)` branch with
`moving = controller.hasMomentum`, so the argument was **0 in every reachable state** — a
vacuously-false predicate passed at the one call site that could not observe it. On a full 300 EN
tank the sheet printed 「其中 0 EN 是制动储备，巡航可用 300 EN，可以飞 120.0 ly」. Fixed to
`_c.cruiseReserve` (100 EN / 200 EN / 80.0 ly).

**Finding 2 — the dialog's stated reason for existing was false, in two copies.** Both
`_igniteFromCockpit`'s doc and the twin comment on the ignition test said the choice cannot be
deferred because "by the time the tank is dry the ship has no energy to brake with". Under deviation
5 a cruise *keeps* its reserve, so at exhaustion `energyBalance == cruiseReserve` and `canBrake`
reads `100 >= 100` — true. Both now give the true reason: `cruisePolicy` is written in exactly one
place (`game_controller.dart:1319`, inside `igniteCruise`), so nothing in the UI changes it after
ignition.

**Finding 3 — the test could not tell "stored" from "defaulted".** It tapped 耗尽后停下 and asserted
`FuelPolicy.halt`, which is `PlayerState.cruisePolicy`'s own default (`player_state.dart:24`). Now
taps 耗尽后滑行 and asserts `FuelPolicy.coast`. This is the same defect class as the vacuous
predicate in Finding 1: an assertion that holds in the state it is meant to exclude.

**Finding 4 — the sheet's numbers were unpinned.** Two `find.textContaining` pins added
(「100 EN 是制动储备」 / 「可以飞 80.0 ly」). Verified to bite: a regression to `brakingCost` reads
0 EN / 120.0 ly and fails both. Neither substring collides with the `detail` line's
「保留 100 EN 的制动储备」, which uses 的 where the body uses 是.

**Finding 5 — the sheet's closing sentence was false.** 「区别只在耗尽的那一刻」 → both policies
exhaust at the same instant with the same budget, so it is the state *after* that differs.

**Fix round 1: all five ADDRESSED, no new breakage** (re-review of `a3d1805..37c6ada`, 7856 bytes,
1 commit). The re-reviewer corroborated the intent against the plan text rather than the report
alone, and confirmed no cross-contamination: the suites that also assert 耗尽后停下/耗尽后滑行
(`fuel_out_test.dart:407-422`, `braking_test.dart:585-594`) exercise the untouched *voyage* dialog.

**One out-of-scope observation, ledgered not fixed:** `fuel_choice_dialog.dart:162`'s halt `detail`
reads 「电量耗尽前引擎先制动停下」, which mildly overstates the automatic halt as a *paid* brake
preceding an empty tank. Under deviation 5 the halt is free and happens *at* exhaustion
(`game_controller.dart:1163-1174`), and the 「保留 100 EN 的制动储备」 half is true. The line is
unchanged by the fix and is retained verbatim in the plan, so it is not a Phase 5 finding — but it is
in the final review's range. **Cost if wrong:** a player reads the free automatic halt as a priced
action.

## Task 20 — a third defect found by pre-flight, and one deliberate non-fix

Ruling: **Task 20 gains a third gate, `canIgnite = energy > cruiseReserve`.** Its prose claimed the
two existing predicates were the whole story and left the `!moving` branch "unchanged (`点火巡航` is
free; the dormant case never reaches it)". Free is not unconditional: `igniteCruise`'s last guard is
`if (energy <= cruiseReserve) return LaunchResult.insufficientEnergy;` (`:1316`). Two reachable
states trip it, both manufactured by the deliberately lenient `activate()`: a dormant ship holding
exactly 5 EN wakes awake with 0 EN, and a ship that exhausted a cruise under `halt` wakes awake with
the reserve itself (100 EN, 95 after the fee). In both, `_HeadingBar`'s `else if (!moving)` branch
renders 点火巡航 and every tap ends in a refusal snackbar — a button offering an action that then
refuses, which is the exact defect Task 20's own stated principle forbids. Step 1 gains a fourth
test that reaches the second state (`halt` at 3000 s → dormant at 100 EN → `activate()` → 95 EN) and
pins the disabled copy 「需要 100 EN 巡航储备（现有 95 EN）」 plus the training link; Step 4's gate
and Step 5's `shortOfEnergy` both gained the branch. The reserve is read off the controller, not
hardcoded, so a different engine moves the gate and the guard together.
— **Cost if wrong:** one extra test and one extra `_HudButton` argument; no behaviour regresses,
since the button was already refused on every tap in those states.

Ruling: **`igniteCruise`'s `alreadyHere` and `alreadyTraveling` refusals are deliberately NOT
gated.** The same button is rendered while the ship is docked at a planet and possibly mid-voyage,
and both refuse. Gating them changes which buttons the cockpit *shows* — §5.3's table scopes its row
to 「静止（深空）」 and §1 scopes the whole feature to deep space, so hiding or disabling the button
elsewhere is a product decision the plan has no authority to make. Written into the plan as an
explicit non-goal with the reason, and carried to the final whole-branch review by name.
— **Cost if wrong:** a player docked at a planet sees a 点火巡航 button that answers with a
refusal snackbar instead of an explanation. The alternative costs a product decision nobody has made.

Also corrected: **Task 18 Step 4's `braking: _c.brakingCost` and its false `_igniteFromCockpit`
doc**, so the plan's snippet matches the shipped fix rather than contradicting it.

## Task 22 — L9's band re-derived by bisection

Ruling: **the 100 EN band is `[59.6695°, 60.3311°]`, not `[59.673°, 60.165°]`.** `turnCostFor` is
`round(200·sin(θ/2))`, so the band is where `sin(θ/2) ∈ [0.4975, 0.5025)`. Solving
`86.6025·δ − 12.5·δ² = ±0.5` about `θ = 60°` gives `δ = −0.0057687` and `+0.0057783` rad, i.e.
**0.3305° below 60° and 0.3311° above it**. The two sides differ because `sin` is not linear across
the band, and the row's own claim of a *tightest* half-step is therefore **0.331°**, not the 0.165°
it stated. The test's spot values (99.24 / 100.75 at ±0.5°) were already correct; only the
superlative was wrong. — **Cost if wrong:** none; the assertion is unchanged and its comment now
states the band instead of an unverifiable superlative.

Plan corrections committed as `5315395`.

## Task 19 — dispatched (implementer `ad4ae9ff5928fce79`, sonnet, BASE `5315395`)

Brief regenerated from the plan and confirmed **byte-identical** to the one the pre-flight corrected,
so the three `a3d1805` rulings (the `Offset(26, 400)` marker expectation, `clampHudPoint`'s dropped
132 claim, `hasCourse = hasMomentum && !isDormant`) are all in it. Task 20's brief regenerated too —
it now carries the third gate. Dispatch carried the two Task 18 consequences the brief cannot know:
修正航向 opens a confirm dialog before spending, and `_igniteFromCockpit` asks a fuel policy and
passes `cruiseReserve`.

## Task 21 and Task 22 — pre-flight (controller, while Task 19 runs)

**Task 22's L-row table: line numbers flagged as rotted, and L10 ruled on.**

Ruling: **the table's numbers are as of `6b9a842` and must be located by their quoted text, not
their line number.** Tasks 18-21 all insert lines into `galaxy_map_3d_page.dart` and the test files.
Checked each row against source: the test-file rows (L3-L10) still land exactly; L13
(`cockpit_hud.dart:37`) still lands; **L11 and L12 have moved** — `_aimCockpit`'s doc is now
`:443-453` (was `:407`) and `_recenter`'s comment `:475-480` (was `:437-439`). The Step 1 preamble
now says so and names the current numbers, so an implementer who edits without re-locating is
contradicting the brief rather than the plan.
— **Cost if wrong:** an implementer edits the wrong line in a 1200-line file. The quoted text is the
tiebreaker, and every row quotes its own text.

Ruling: **L10 stays, and its "make it true" is rewritten to state the rule rather than the
distance.** The row claimed `cruise_test.dart:655`'s "still the nearest candidate" is false because
`recommendedDestination` prefers hero worlds. Re-read `game_controller.dart:988-991`: the comparator
is `isBetter = best == null || (p.featured && !best.featured) || (p.featured == best.featured &&
distance < bestDistance)`, so distance decides only between equals in featuredness — confirmed, the
winner need not be nearest. But the comment's own claim is about `rec0`'s *candidacy*, and whether
`rec0` would win absent the guard depends on whether the fixture holds a featured candidate, which
the comment never establishes. So the comment is **unjustified rather than false**, and the fix is
to say what actually holds — and to report rather than invent a justification if the assertion turns
out to pin nothing.
— **Cost if wrong:** one comment reworded toward the weaker of two true statements. The assertion
itself is untouched.

**Task 21: verified against source, and one claim was unpinned.**

Verified and correct as written: mount sites `journey_page.dart:372` (`_CoastDock`) and `:380`
(`_DriftDock`); `_ActionButton` at `:1238` with a nullable `onPressed` and `final disabled =
onPressed == null;` at `:1257`; `StarPanel` at `lib/ui/widgets/common.dart:91` takes `child` and
`padding` as used; `activate()`'s guard is `if (_player.energyBalance < cost)` (`:1218`) with no
momentum guard, so a coasting ship can pay the fee; `引擎休眠中 · 生命维持与照明已停止` appears
nowhere in `lib/` or `test/`, so it is a new string. Test 2's two-guard comment is right:
`_CoastDock`'s own 前往训练补充能量 is gated on `!canBrake` and `canBrake` is `100 >= 100`.
Test 1's `findsOneWidget` on 前往训练补充能量 cannot collide — `_DriftDock` has no such string, the
star map's copy lives in `_HeadingBar` and the cockpit is not entered on the voyage tab, and the one
existing test that asserts that string (`braking_test.dart:510`) runs a **non-dormant** 50 EN
coaster, so `if (controller.isDormant)` does not mount the new panel and it still finds exactly one.
The parent `Column` is `crossAxisAlignment: stretch` (`journey_page.dart:333`), so `_EnginePanel`'s
own `stretch` column and `_ActionButton`'s `width: double.infinity` are both bounded.

Ruling: **Task 21's Step 1 gains an `InkWell.onTap, isNull` assertion.** Its comment claimed "the
button is off" and nothing pinned it. A plausible regression — gating the *text* on `canActivate`
but wiring `onPressed: onActivate` — leaves every existing assertion green, and a tap cannot expose
it either: `activate()` refuses on its own (`0 < 5`), so `isDormant` stays true either way. The
assertion reads `onTap` off the `InkWell` (`journey_page.dart:1270` renders `onTap: onPressed`),
mirroring `braking_test.dart:493`. Same defect class as the Task 18 pins: a claim in a comment that
no assertion can falsify.
— **Cost if wrong:** three lines in one test. Nothing in `lib/` changes.

Plan corrections for Tasks 21 and 22 are **uncommitted** at this point, deliberately: committing
while Task 19's implementer holds the index risks a lock race, and an uncommitted plan edit cannot
land in Task 19's review package. They are committed before that package is generated.

## Task 19 — report `4bc68f9`, DONE_WITH_CONCERNS; fix round 1 dispatched

Implementer `ad4ae9ff5928fce79` (sonnet), BASE `5315395`. Commit `4bc68f9`
`feat(starward): mark the current heading and read out the deviation`, four files exactly as the
brief lists. `flutter analyze` → `No issues found!`; `flutter test` → **334 passed**; focused
`cockpit_hud_test.dart` + `cruise_ui_test.dart` → 38 passed. Step 2's predicted failure mode was
observed verbatim (`Method not found: 'clampHudPoint'` ×6, `'headingMarkerPoint'` ×5).

Ruling: **the implementer's one deviation from the brief is accepted — `hasCourse` belongs inside
the `AnimatedBuilder`'s builder, not at the top of `build`.** Verified independently: the page's
subtree hangs off `AnimatedBuilder(animation: _c)` (`galaxy_map_3d_page.dart:542-544`), and an
`AnimatedBuilder` rebuild does not re-run the enclosing `build`; `JourneyPage._sync` computes
`needsTimer = status == JourneyStatus.inProgress || c.hasMomentum` (`journey_page.dart:104-107`), so
its one-second timer drives `tick()` from the star map's `IndexedStack` sibling and a cruise **can**
run dry with the cockpit on screen. With the brief's placement the readout and the triangle would
stay up beside a 激活引擎 bar — the disagreement the shared local exists to prevent, and the state
the brief's own comment says must not happen. The declaration, its comment and the added paragraph
are in `galaxy_map_3d_page.dart:545-560`. — **Cost if wrong:** none identified; the shipped
placement is strictly more current than the brief's, and the brief was amended to match.

Ruling: **the deviation needed a permanent test, so fix round 1 is a test-only round.** The
implementer proved the staleness with a throwaway probe and then **deleted it**, which leaves the
new paragraph's claim unpinned — moving the declaration back above the `AnimatedBuilder` would
silently reintroduce the defect with every assertion green. Step 8 now carries a third marker-layer
test (`'a burn that runs dry on screen takes the readout with it'`: cruise to 2900 s, enter the
cockpit, advance past the burn, `c.tick()`, pump, then assert `painter.heading` is null and 偏离 is
gone beside a 激活引擎 bar) and the dispatch requires the implementer to prove it bites by
temporarily moving the declaration and reporting both runs. Verified the finder is sound:
`textContaining('偏离')` is unique across `lib/` — the only other site is the confirm dialog at
`galaxy_map_3d_page.dart:249`, which says 「偏转」. — **Cost if wrong:** one test that would have
passed anyway; the state it pins is the feature's own stated must-not.

Ruling: **the implementer's two other concerns are plan defects, fixed in the plan, no code change.**
(a) The brief named a class that does not exist, `_JourneyMapPageState` — the real name is
`_GalaxyMap3DPageState`, which the plan itself uses at `:3344` and `:4015`, so the plan contradicted
itself. (b) Step 6's `galaxy_map_3d_page.dart:1193-1206` citation was **already wrong at `5315395`**,
where the `_HeadingBar` branches sit at 1190 / 1197 / 1206 — the range did not begin at the
`if (dormant)`. Both corrected, along with Step 6's `:535` → `:539` for `build`, and Step 6's
`_CockpitOverlay` / marker-`CustomPaint` numbers (`:872` / `:590-603` → `:876` / `:594-609` as of
`4bc68f9`), now marked as symbol-first with the numbers dated. — **Cost if wrong:** none; these are
citations in a document whose subject has already shipped.

Also ruled in: the stale Task 17 comment at `cruise_ui_test.dart:438-439` ("Task 19 adds a 偏离 N°
readout … it does not exist yet in Task 17") is reworded in the same fix round. It is not false, but
Task 19 is what made it read as a claim about an unverifiable past snapshot, and it sits directly
above the readout assertion this task added. — **Cost if wrong:** one comment sentence.

**Process note:** the plan amendments for Tasks 19, 21 and 22 are deliberately **uncommitted** until
the fix round commits, so that the Task 19 review package can be the clean range `5315395..<F>`
rather than one polluted by my docs commit.

## Task 19 — fix round 1 done, `310c173`; review dispatched

Fix round 1 returned **DONE, no concerns**: `310c173`
`test(starward): pin that a burn running dry on screen clears the HUD readout`. `flutter analyze` →
`No issues found!`; `flutter test` → **335 passed** (334 + 1). The test was proved to bite rather
than asserted to: with `hasCourse` temporarily moved back above the `AnimatedBuilder` it **FAILS** on
`expect(painter.heading, isNull)` at `cruise_ui_test.dart:595` (`Expected: null, Actual:
<Instance of 'Vec3'>`, "the marker went with the bar") with all four preconditions passing first;
restored, it **PASSES**. `git diff` on `galaxy_map_3d_page.dart` is empty, so the committed `lib/`
state is byte-identical to `4bc68f9` and this round touched tests only. The stale comment is
reworded; `grep -rn '偏离\|偏转' lib/` re-confirmed to hold only the readout at `:930` and the
dialog's 「偏转」 at `:249`, so the unscoped finder is sound.

Plan amendments committed as `540cbf4` (Tasks 19, 20, 21, 22 — see the entry above for each).

Review package generated for the clean task range: `scripts/review-package … 5315395 310c173` →
`review-5315395..310c173.diff`, **2 commits, 31933 bytes**. The docs commit `540cbf4` sits above
`310c173` and is deliberately outside the range. Task 19's brief was **regenerated from the amended
plan** before the review, so it carries the corrected Step 6 placement, `_GalaxyMap3DPageState`, and
the third test — the reviewer's dispatch says so explicitly and tells it to judge the shipped
placement on its merits rather than treat the amended brief as proof. Task reviewer dispatched on
`sonnet` (agent `aeb343654ef89ba3d`), with five named risks: the Step 3 clamp extraction's fidelity,
every comment/test number re-derived from the reference economy, whether the third test can
distinguish the two declaration sites, `hasCourse`'s predicate against the branch it mirrors, and
whether the unscoped `textContaining('偏离')` assertions can only match the readout.

## Task 20 — pre-flight complete (controller)

Ruling: **nothing to change; every citation and predicate in Task 20's text checks out against
source.** Verified: `ShellScope.go` at `shell_scope.dart:15`, `TrainingPage` at
`training_page.dart:18`, `igniteCruise`'s `if (energy <= cruiseReserve)` at `game_controller.dart:1316`
(the one figure Task 20 needed to be exact, and it is), and the `:1357` correction above.
`_HeadingBar.build` already holds every local Step 4's snippet reads — `dormant` (`:1202`), `moving`
(`:1203`), `turnCost = controller.turnCostTo(heading)` (`:1204`), `braking` (`:1209`),
`turningIsDearer` (`:1214`) — and Step 4's three new names (`energy`, `activationCost`, `canActivate`
/ `canTurn` / `canIgnite`) collide with none of them.

Ruling: **all four of Task 20's tests are reachable, including the three that enter the cockpit from
a parked ship.** `_SideControls` is mounted unconditionally at `galaxy_map_3d_page.dart:638` — the
座舱 button (`:761`) has no motion or dormancy gate — and `_HeadingBar` renders on
`_camera.mode == CameraMode.cockpit` (`:656-657`). So `_enterCockpit` works for the parked dormant
ship of tests 2-4 exactly as it does for the cruising ship of test 1, which was the one thing that
could have made three of the four tests unreachable. — **Cost if wrong:** none; this is a check that
passed, not a change.

Also noted, and it settles a question I had left open: the comment at `galaxy_map_3d_page.dart:1217-1222`
states the `IndexedStack` finder behaviour the tests rely on — "an `IndexedStack` only visits its
selected one, so an unscoped `find.text` in a widget test still finds one". That is now corroborated
by the code's own account as well as by the passing suite, so the offstage assumption behind Tasks
20 and 21's `findsOneWidget` assertions holds.

## Task 19 — task review returned; one Important finding, ruled and dispatched as fix round 2

Review of `5315395..310c173` (package: `review-5315395..310c173.diff`) returned **Approved on spec
compliance**, with 1 Important and 2 Minor. The reviewer independently re-derived the clamp
extraction as behaviour-preserving, every numeric claim (`acos(1/400) = 89.86°`, the 104.33° nudged
boundary, the 14.47° it buys, `180 − 104.33 = 75.67°`), that `hasCourse`'s predicate is exactly
`_HeadingBar`'s third branch, that the `1252-1272` citation covers the whole three-branch block, and
that the third test is non-vacuous and site-dependent. Its one ⚠️ item — it could not verify
`JourneyPage`'s timer from the diff alone — was already resolved: `journey_page.dart:104-107` reads
`final needsTimer = status == JourneyStatus.inProgress || c.hasMomentum;`, so the timer runs
whenever the ship has momentum, and `JourneyPage` is alive in the `IndexedStack` sibling while the
star map is selected. No action.

Ruling: **the Important finding is real and gets fixed, not parked.** `cockpit_hud.dart`'s triangle
block reads `final offScreen = clampHudPoint(at, vp).offScreen;` where `at` is
`headingMarkerPoint(...)`'s result — and that function clamps on **both** its return paths (`:134`
and `:136` as shipped), so the re-clamp always yields `clamped == at`, `offScreen` is `false` in
every reachable state, and `alpha: offScreen ? 0.45 : 0.9` (`:246`) never takes its `0.45` branch. I
confirmed this against source before ruling. The marker loop above it is *not* affected: it clamps
the raw `hudMarkerPoint` result, so it genuinely dims — which is the visible consequence, since a
heading 70° off the aim clamps to a side edge at full strength while a destination marker at the
same edge dims to 0.45. **This is the plan's defect, not the implementer's:** Step 5 specified the
line verbatim, so I amended the plan first (`50fd605`) and the fix round quotes the amended text.
— **Cost if wrong:** one `CustomPainter` ternary; if the dimming turns out to be the wrong
treatment for the current course, reverting is a one-line change in a file nothing else reads.

Ruling: **`headingMarkerPoint` returns `({Offset at, bool offScreen})?`, not a bare `Offset?`.** The
alternative — dropping the ternary and always drawing at 0.9 — was rejected because the clamp
genuinely means "this is a direction, not a position" and the markers already say so by dimming; the
triangle disagreeing with them is the inconsistency the finding names. Changing the signature is
also what makes the dimming **falsifiable for the first time**: before this, no assertion in the
suite could reach it. The four positional tests gain an `offScreen` assertion (three `isTrue`, one
`isFalse`), and I worked all four through from the projection maths so the implementer confirms
expected values rather than deriving them — with the explicit instruction to stop and report if any
comes out `false`, since that would mean the flag still does not report what it claims.
— **Cost if wrong:** the record shape is a small API change to a function with one production caller
and five test call sites; a revert is mechanical.

Ruling: **`hasCourse` does not become a `GameController` getter (Minor 1, parked).** It composes two
of the controller's own predicates (`hasMomentum`, `isDormant`); promoting it would put a single
widget's branch condition on the controller as a rule existing only to serve one `if`. Task 20's
Step 4 — one task away — already declines the analogous `canIgnite` getter and inlines
`energy > cruiseReserve` instead, so a getter here would contradict a decision already made. If a
third call site ever needs it, it becomes a getter then. — **Cost if wrong:** two encodings of a
two-term boolean drift apart; the third test in Step 8 is what would catch it.

Ruling: **`clampHudPoint`'s doc keeps naming `_CockpitPainter` / `_BottomControls` without the file
(Minor 2, parked).** The same two names appear in a second copy inside `paint` (`:186-187`), so the
fix is two comments plus the plan's copy of each, for a navigability gain that one grep already
delivers. Both copies are plan deliverables and stay verbatim. — **Cost if wrong:** a reader greps
instead of clicking; nothing else.

Dispatch: fix round 2, R=1, **resumed implementer `ad4ae9ff5928fce79`** (same agent as rounds 0-1).
BASE for the round's diff is `50fd605`. Scope is `cockpit_hud.dart` + `cockpit_hud_test.dart` only;
`galaxy_map_3d_page.dart`, `cruise_ui_test.dart` and the plan are out of bounds. The dispatch carries
one honest gap to state rather than test: nothing pins that `paint` *reads* `p.offScreen` —
`cockpit_hud_test.dart` has no rendering test at all (no `PictureRecorder`, no `toImage`; every test
in the file is a pure-function unit test), and introducing that technique for one ternary is
disproportionate. The unit tests pin the value; the read is one line.

## Task 20 — pre-flight addendum: test 1's tap block pinned nothing

Ruling: **Task 20's test 1 gains `expect(find.byType(AlertDialog), findsNothing)` after the tap, and
the Step 2 prose is corrected to say so (`6375042`).** The plan claimed the tap-and-assert block
"pin[s] the point: a disabled button must not fire `onPressed` at all, so `c.energy` stays 140 and the
ship stays on its old course" — and then, four lines later, admitted `c.energy` "would read 140
either way and the assertion alone cannot tell the two apart", leaning on the disabled-detail
`findsOneWidget` instead. Both halves cannot be true, and the second is the honest one. Worse, the
detail text does not close the gap either: a button that renders 「需要 200 EN（现有 140 EN）」 while
still wired to `onPressed` passes every assertion in the test. Verified against source:
`_correctFromCockpit` (`galaxy_map_3d_page.dart:236-272`) opens a confirm `AlertDialog` and returns
early unless confirmed, so a live tap spends nothing. The dialog's **presence** is the discriminator —
`findsNothing` when disabled, `findsOneWidget` when live, and `AlertDialog` is unambiguous here
because the button's own label is the dialog's title. `material.dart` is already imported by
`cruise_ui_test.dart:3`, so no import is needed. This is the same fix, for the same reason, as Task
21's test 1 (`InkWell.onTap, isNull`): pin the wiring, not the copy. — **Cost if wrong:** one
assertion; if `AlertDialog` proves ambiguous the failure is a `findsOneWidget`/`findsNothing`
mismatch the implementer will report rather than paper over.

Also ruled, and recorded in the plan: **test 2 deliberately has no tap block.** `onActivate` is
`() => _c.activate()` (`:660`), and `activate()` refuses on its own at 0 EN, so `isDormant` stays
true whether the button fired or not — there is nothing a tap there could distinguish, which is why
the plan never wrote one.

Verified while drafting Task 20's dispatch, so it need not re-derive them: `_HudButton` is at
`galaxy_map_3d_page.dart:1305` with the four fields Step 3 extends, its three call sites are the
three bullets of Step 4 (`:1253`, `:1260`, `:1267`), the brake hint it re-gates is at `:1273`, and
Step 3's snippet is a faithful extension of the shipped body (`GestureDetector` + `panelDecoration`,
with the two `TextStyle`s losing `const` because `on ? A : B` is not constant).

Cross-checked for damage from the Task 19 fix round: Task 22's table has exactly one
`cockpit_hud.dart` row — L13 at `:37`, inside `headingDeviationDegrees`, above everything the round
touches — and no row quotes the `offScreen` line, so the fix invalidates none of it. The new doc
paragraph the round adds uses plain backticks only, so it introduces no second dead
`[GameController.turnApi...]`-style doc link of L13's kind.

## Task 19: complete

Fix round 2 re-reviewed (`review-310c173..4d41d04.diff`, reviewer `afce2cf886d029d78`): **All findings
addressed, no new Critical/Important breakage.** The Important finding is ADDRESSED — `paint` reads
`p.offScreen` at `cockpit_hud.dart:254`, both of `headingMarkerPoint`'s return paths (`:139`, `:141`)
hand back the whole record so neither drops the flag, and the flag is two-valued on reachable inputs.

The re-reviewer re-derived all four positional expectations from `Camera3D.project` rather than
reading them off the output, and confirmed each: reticle raw `(200, 400)` inside the rect → `isFalse`;
abeam and straight-up both land with an off-axis ratio of **exactly 4.0** (nudged `camZ = 97.01`,
`camX`/`camY` exactly 0 where asserted) so they clamp to the exact bounds `(26, 400)` and `(200, 74)`;
dead astern is culled at `camZ = −400 ≤ 1.0` and takes the `(200, 800)` → `(200, 668)` fallback. All
four `isTrue`/`isFalse` as the plan predicted. It also confirmed both branches are now pinned — a
`headingMarkerPoint` hardcoding either value fails the suite — and that the only signature change has
exactly six call sites, all updated.

Ruling: **the report's `:250` vs the read's `:254` is not worth a round.** It is a line number in a
*report*, not in code or a comment the codebase carries; the read itself is one line and the
re-reviewer located it. No third round for a prose nit. — **Cost if wrong:** none.

Ruling: **the honest gap stands as the implementer stated it, and is carried to the final review.**
Nothing pins that `paint` *reads* `p.offScreen`: `cockpit_hud_test.dart` has no rendering test (the
re-reviewer grepped for `PictureRecorder`/`toImage`/`Picture`/`CustomPainter` and found none), so the
unit tests pin the value the flag carries and not the read. Introducing a recording-canvas technique
for one ternary is disproportionate. — **Cost if wrong:** a future edit could re-derive `offScreen`
in `paint` and silently reinstate the dead branch; the four unit tests would still pass, because they
pin `headingMarkerPoint`, not `paint`.

Task 19's deliverables: `4bc68f9` (triangle + readout + marker layer), `310c173` (the regression test
that pins `hasCourse`'s declaration site), `4d41d04` (the live `offScreen` flag). Four files:
`cockpit_hud.dart`, `galaxy_map_3d_page.dart`, `cockpit_hud_test.dart`, `cruise_ui_test.dart`.

BASE for Task 20: `4d41d04`. Task 20's brief regenerated at 356 lines (was 342) so it carries the
`AlertDialog` assertion and the corrected Step 2 — the pre-amendment copy is gone, not superseded.

## Controller work while Task 20 runs: the deferred list is pre-cleared, and Task 20 is dispatched

Task 20 dispatched to a fresh implementer (`a40c808865004f11d`, sonnet) at BASE `4d41d04`, brief
`task-20-brief.md` (356 lines, regenerated after `6375042` so it carries the `AlertDialog` assertion
and the corrected Step 2). Two ambiguities resolved in the dispatch so the implementer does not have
to guess: **Step 5's condition is written as the named local `shortOfEnergy`** (the brief offers both
forms; the local's comment is a deliverable and it mirrors the button switch above it), and **Step 5's
insertion point is between the brake-hint block (`:1284`) and the existing `const SizedBox(height: 8)`
at `:1285`** (the snippet carries its own gap, so the order is button, brake hint, gap, training
link, gap, hint text). The dispatch also carries the `git add` footgun — run Flutter from `starward/`,
`git add` from the repo root.

Ruling: **three of the nine deferred items are closed now rather than left for the final review, and
the list says so in its header.** Items 4 and 7 were written as open *questions* — "is any
`pumpAndSettle` left?", "is the probe file gone?" — and both are mechanical checks, not judgments; a
reviewer spending its seat on them buys nothing the controller could not settle in one grep. Item 5
needed only a location correction. The live items are 1, 2, 3, 6, 8 and 9, and the header now names
them so the review's attention lands there. — **Cost if wrong:** the final review inherits three
answers it did not verify itself; each is recorded with its evidence and a reviewer who doubts one
can re-run the check in a minute.

Item 4's answer, with the reasoning that took a little digging: **the hazard does not materialise, and
the premise behind it is correct rather than overstated.** Seven `pumpAndSettle` calls survive, in
four files, and **all four predate the plan** (`fuel_out_test.dart` 10-12 20:06, `braking_test.dart`
10-13 18:19, `drift_report_test.dart` 10-12 21:48, `details_launch_test.dart` 10-10 16:39, against a
plan that begins 10-14 11:47) — so none is in a file this plan created. They are safe because they
mount narrow trees rather than `HomeShell`: `braking_test.dart`'s `open()` helper wraps a bare
`MaterialApp(home: Scaffold(...))`, and the app-wide starfield is mounted at `lib/app.dart:65`, not in
`Scaffold`. `StarfieldBackground` does `repeat()` unconditionally in `initState`
(`starfield.dart:94-97`), so a tree that mounts it genuinely cannot settle — and that no survivor
mounts one is **proven by the suite being green in ~17 s**, not assumed. Item 7: the probe file is
gone (32 tracked files in `test/`, none matching `probe`/`zz_`, no untracked file), and the count is
335 — though the honest form of the attribution claim is "everything in the suite", since the plan
also edited pre-existing test files, not "this plan's tests".

Also fixed in the list while I was in it: it carried **two items numbered `## 8`** (the
premise-corrections item and the 点火巡航 item), which would have made the final review's citations
ambiguous; the second is now `## 9`.

---

## Controller ruling — Task 22 item 3 was false, and I wrote it

**Ruling: Task 22's item 3 said the six Phase 5 tasks "have no `## Phase 5` heading at all: they sit
under Phase 4's". That is false twice, and the item is rewritten to describe the real defect — the
heading exists but at h1 while Phases 1-4 are h2, and the Phase 5 block sits *after* the four closing
sections.** Checked against `git show 5be654e~1:docs/superpowers/plans/2026-10-14-starward-free-cruise.md`,
which produces the identical heading list, so `# Phase 5` predates my own `5be654e` amendment and I
cannot have been misled by a concurrent edit. The heading is at `:4381`; the four closing sections are
`## Self-Review` `:4325`, `## 已知取舍` `:4337`, `## 与 spec 的偏差汇总` `:4351`, `## Execution Handoff`
`:4364`. Task 22's Step 3 `git add` already names the plan doc, so this correction reaches the
implementer through the regenerated brief (10579 → 12318 bytes).

**Why it mattered:** left as written, the implementer's only faithful reading is to *add* a `## Phase 5`
heading above Task 17 — which would leave the plan with two Phase 5 headings, one h1 and one h2. The
item would have manufactured the defect it was written to remove.

**Second clause, same paragraph:** the Self-Review's "§11 (staging) → the four phases" (`:4329`) is
false for the same reason, so item 1 now names it alongside the "every requirement maps to a task"
claim it already covered.

**Cost if wrong:** Task 22's report will describe a heading level and a count rather than a missing
heading. If a reader expects a second `## Phase 5` heading to appear, they will not find one — that is
the point, not a shortfall.

---

## Task 20 — implementer DONE, review dispatched

**Commit:** `5676115` — `feat(starward): say why a cockpit button is disabled, and offer the training tab`.
**BASE** `4d41d04`. Files: `starward/lib/ui/galaxy3d/galaxy_map_3d_page.dart`,
`starward/test/cruise_ui_test.dart`. Report: `task-20-report.md` (135 lines, Status DONE, no blocking
concerns).
**Tests:** `flutter analyze` → `No issues found!`; `flutter test` → **339 passed** (335 at BASE + 4 new);
`test/cruise_ui_test.dart` alone → 24 passed. All four new tests failed on the first run at exactly the
surface the brief predicted, with every `reason: 'precondition'` assertion holding — so no expectation
was fitted to output. The brief's own stale citations (`journey_page.dart:822`, `correctHeading` at
`:1357`) were reported and changed no code.
**Review package:** `review-4d41d04..5676115.diff` (1 commit, 16626 bytes).
**Task reviewer dispatched:** sonnet, read-only, brief + report + package. Not yet returned.

**Plan correction committed first, as `c49e49e`** — the Task 22 item 3 rewrite (see the ruling above),
so Task 22's own commit carries only Task 22's plan edits. `task-22-brief.md` regenerated from the
amended plan (10579 → 12318 bytes) and contains the corrected instruction.

## Task 21 brief pre-flighted clean (by the controller, 2026-10-14)

Task 21 (航行页的休眠面板与 _EnginePanel, M3) has not been dispatched — it edits
`starward/test/cruise_ui_test.dart`, the same file a Task 20 fix round would touch, so it waits on
Task 20's review. Its brief was pre-flighted while waiting; every citation it makes checks out at
current HEAD:

- `_ActionButton` class at `journey_page.dart:1238`, `final disabled = onPressed == null;` at `:1257`,
  `onTap: onPressed` at `:1270` — all three exact.
- `_FlightPanel` at `:1030`; `_DriftDock` at `:674`; `_CoastDock` at `:745`.
- Mount sites `_CoastDock(` at `:372` and `_DriftDock(` at `:380` — exact.
- `activate()` at `game_controller.dart:1215` with its guard `if (_player.energyBalance < cost)` at
  `:1218` — exact, and lenient (`<`, not `<=`), so `energy >= cost` is the right gate.
- `StarPanel` does take `padding` (`lib/ui/widgets/common.dart:91-104`).
- `_CoastDock`'s 前往训练补充能量 is gated on `!canBrake` (`journey_page.dart:872-881`), which is what
  makes test 2's `findsNothing` on that string true rather than lucky: the ship is coasting, so
  `canBrake` is `100 >= 100`.
- `_DriftDock` has **no** 前往训练补充能量 of its own, so test 1's `findsOneWidget` on that string
  resolves to the panel's own button and nothing else.
- `_ActionButton`'s `InkWell` is wrapped in a `Material` and nothing else that is an `InkWell`, so
  test 1's `find.ancestor(…, matching: find.byType(InkWell))` matches exactly one widget and
  `tester.widget<InkWell>` will not throw.
- The cited precedent `braking_test.dart:493` is exactly `final brake = tester.widget<InkWell>(find.ancestor(`.

**Task 21's brief needs no correction.**

**One note to carry into the Task 22 dispatch:** the table's `was :NNN` refs for L11 and L12 are stale
by ~45 lines — `_aimCockpit`'s doc is now at `:444-451` and `_recenter`'s comment at `:474-478`, because
Tasks 17-19 inserted `_igniteFromCockpit` / `_correctFromCockpit` / `_brakeFromCockpit` above them. The
quoted text each item names ("the current heading, exactly"; "under way") is present verbatim at both
sites, so both targets are unambiguous — but the implementer should locate them by the quoted text, not
by the line number.

**Second plan correction, `21ccd9b`.** Task 22's table row L13 and the "locate each row by its quoted
text" paragraph both asserted that `cockpit_hud.dart:37` "is still correct". It is not: Task 19 added
`import '../../core/theme.dart';` at `:5`, which moved the `[GameController.turnAngleTo]` doc link to
`:38` **and** invalidated the row's supporting claim, which enumerated three imports when the file now
has four. The row's conclusion survives — `game_controller.dart` is still not imported, so the link is
still dead, and the fix ("drop the brackets to a plain code span") is unchanged. The paragraph now
names L13 as the one row whose *reason*, not just its line number, went stale, and tells the implementer
to re-derive it in full rather than renumbering it. `task-22-brief.md` regenerated again (12318 → 12460
bytes, 110 lines).

Ruling: fix it rather than leave it — Task 22's whole purpose is removing false claims, and a plan that
tells its implementer "this one has not moved" while it has is the same defect it is being sent to
remove. Cost if wrong: one extra paragraph in the brief, and a row the implementer re-derives that it
would otherwise have renumbered. Both are cheap; a plan-level false claim about the plan's own text is
not.

---

## Task 20 review — returned, 1 Important, fix round 1 dispatched

**Verdict:** ✅ spec compliant on the three gates and the four tests; **task quality: Needs fixes** —
one Important finding, one Minor.

The reviewer verified all three gates against the controller's own guards at their strict/lenient
boundaries (`canActivate` `>=` vs `activate()`'s `energyBalance < cost`; `canTurn` `>=` vs
`correctHeading`'s `energy < cost`; `canIgnite` `>` vs `igniteCruise`'s `energy <= cruiseReserve`), and
checked the `energy` getter against the guard's raw `_player.energyBalance` for the dormant case. It
also confirmed the two load-bearing assertions are real: an enabled 修正航向 tap reaches
`_correctFromCockpit`, which `showDialog`s an `AlertDialog`, and an enabled 点火巡航 tap reaches
`_igniteFromCockpit` → `showCruiseFuelChoiceDialog`, whose sheet contains the literal `耗尽后停下`. Both
`findsNothing` assertions therefore genuinely separate a dead tap from a live one. ⚠️ It could not
re-derive the analyze/test counts from the diff; it re-derived test 1's `160` / `140` / `200`, test 2's
`0` and test 4's `95` by hand and found them consistent.

### The Important finding, and my ruling

**Finding:** the `showBrakeHint` comment (`galaxy_map_3d_page.dart:1230-1237`) claims that while
cruising `controller.canBrake` "can never be at or below" the reserve, so the conjunct is always true
and "the hint's visibility is still decided by `turningIsDearer` alone". **False.** A 180° turn at
250 EN is allowed (`energy >= turnCost`), and `correctHeading` settles the leg's burn *and* books the
fee, landing on `energyBalance == 50` with `hasMomentum` true and not dormant — where `brakingCost` is
100, so `canBrake` is `50 >= 100` = false while `turningIsDearer` is true, and the hint is **hidden**.

**Ruling: the behaviour stands; the comment is what is wrong. Fix round 1 = correct the comment, pin
the state with a controller-level test, change no behaviour.** I verified the reviewer's mechanism
myself before ruling, and it is right on both counts:

- `canBrake` is a real guard, not an advisory: `game_controller.dart:1279` is
  `if (!canBrake) { await _persist(); notifyListeners(); return; }` — the brake path **settles the leg's
  burn and then returns without braking**. So a hint shown in that state is worse than a hidden one:
  tapping it spends the player's remaining energy and does nothing else.
- The hint's text is `'制动停下只需 $braking EN'` (`:1318`) with `braking = controller.brakingCost` = 100
  while cruising, so in that state it would quote a price the ship cannot pay.

The pre-Task-20 code (`if (turningIsDearer)`) offered exactly that dead offer; the new conjunct closes
it. The reviewer's finding is that the *comment* denied this, not that the code did it.

**Why a controller-level pin rather than a widget test:** I worked the widget version out and rejected
it. After the turn the deviation is 0, so `turningIsDearer` is false and the hint is hidden for the
wrong reason; a second drag fixes that, but then the assertion turns on whether a `pump` fired
`JourneyPage`'s one-second timer, and a `tick()` on an unmoved `FakeClock` exhausts a ship whose budget
is already negative — flipping it dormant and hiding the hint for a third wrong reason. So the fix round
pins the controller fact the old comment denied (`energy == 50`, `hasMomentum`, `!isDormant`,
`!canBrake` after a 180° turn at 250 EN) in `cruise_test.dart`, and is explicitly told **not** to write
the widget version. `cruise_test.dart` is a third file for this task; it is the honest home for a
controller fact, and Task 22 already lists it.

**Cost if wrong:** the comment would name a state and three numbers with no assertion behind them —
the "claim no assertion can falsify" class. The behaviour itself is unaffected either way, since the
ruling leaves `showBrakeHint` untouched.

### The Minor finding, parked

The disabled detail's `StarColors.danger` and the `faint` icon/label colours (`:1399-1401`) are
asserted nowhere. The brief supplies the colours and no test requires them, so this is coverage
breadth, not a defect. **Ruled: park.** It joins the deferred list's coverage-breadth items; the
colours are a copy choice, not a number the plan pins.

**Report correction required:** the report's item 5 claims the change "adds no new hiding … in any
reachable state", which the finding shows is false. The implementer is correcting it in the same round.

**Fix round 1 dispatched to the same implementer** (R=1 ≤ 3, so resume rather than replace), BASE
`21ccd9b`. **Task 21 stays blocked** until this round lands and is re-reviewed: the round may touch
`cruise_ui_test.dart`, which Task 21 also edits.

---

## Task 20 — COMPLETE

**Commits:** `5676115` (implementation) + `48247c2` (fix round 1). BASE `4d41d04`. Four files across the
two commits: `starward/lib/ui/galaxy3d/galaxy_map_3d_page.dart`, `starward/test/cruise_ui_test.dart`,
`starward/test/cruise_test.dart`, and the implementer's report.

**Round 1 re-review verdict:** *All findings addressed, no new Critical/Important breakage.* It
re-derived the rewritten comment clause by clause against source rather than accepting it — confirming
`stopShip`'s `_settleCruise()` then `if (!canBrake) { … return; }` at `game_controller.dart:1278-1283`,
that `braking` at `:1209` is `controller.brakingCost` and equals `brakingCostFor(cruiseSpeed)` =
`energyCostFor(40)` = 100, that `correctHeading` charges in two steps (`:1359` settle, `:1378` fee), that
`burnForSeconds(750) == 50` and `turnCostFor(π) == 200`, and that `_syncDormancy` returns while
`energyBalance > 0` (`:1201-1204`). It also confirmed the new test discriminates: had `correctHeading`
not booked the fee mid-cruise, `energy` would read 250 or 100 and `canBrake` would be true, failing two
assertions. No `always true` claim survives anywhere in the file. Out-of-scope observations: none.

**Final counts:** `flutter analyze` → `No issues found!`; `flutter test` → **340 passed** (335 at the
task's BASE, +4 from the implementation, +1 from the fix round).

**Ledger note for Task 21's report comparison:** the suite is at **340**, not 339 — Task 20's fix round
added one test after the implementation's 339.

### The round-1 ruling, restated for the record

The finding was a **false comment**, and the fix was the comment plus a pin — not the code. The
behaviour (`showBrakeHint = turningIsDearer && controller.canBrake`) was ruled correct because
`canBrake` is a real guard (`:1279` settles the burn and returns without braking), so the pre-Task-20
`if (turningIsDearer)` offered a tappable hint that would spend the player's energy and do nothing else,
while quoting a 100 EN price the ship could not pay in that state. The reviewer had framed the hiding as
"a behavior change … directly contradicting the comment"; the contradiction was real and the comment was
the side to change. **Recorded as deferred item 11** so the final whole-branch review sees that a
behaviour change happened, not merely that a comment was corrected.

The widget-level test I rejected is recorded in the ruling above and in the dispatch: it cannot isolate
`canBrake`, because after the turn the deviation is 0 (`turningIsDearer` false), and the fix for that
makes the assertion depend on `JourneyPage`'s timer firing against an unmoved `FakeClock`. The
controller-level pin in `cruise_test.dart:496-524` is deterministic and is what landed. The implementer
independently confirmed it could not find a clean widget formulation and reported that rather than
adding one.

**Task 21 dispatched** (BASE `48247c2`).

**Task 21 implementer reported DONE_WITH_CONCERNS** — `d224c54`, `feat(starward): give the voyage dock a dormant engine panel`.
BASE `48247c2` → HEAD `d224c54`. Two files: `starward/lib/ui/journey/journey_page.dart`,
`starward/test/cruise_ui_test.dart`. `flutter analyze` → `No issues found!`; `flutter test` → **342 passed**
(340 at BASE, +2). Review package written: `review-48247c2..d224c54.diff` (1 commit, 12778 bytes).
Working tree clean.

The concern it raised, and it was the right one to raise: the brief's Step 4 mounts `_EnginePanel` **below**
each dock's existing content, which on the 800×600 default test surface pushes the 激活引擎 button past the
bottom edge, so `tester.tap` misses and `isDormant` never flips. The implementer kept `lib/` **byte-for-byte
as the brief specifies** and added `await tester.ensureVisible(find.text('激活引擎'));` plus one `pump()`
before the tap in test 2, citing `details_launch_test.dart:46` as the precedent, and asked me to flag if I
would rather the layout moved.

**Ruling: keep the brief's placement; `ensureVisible` is the correct fix — because the button is reachable on
a real device and the miss is a test-surface artifact.** Verified rather than assumed:
`journey_page.dart:331` is `child: SingleChildScrollView(`, so the panel is below the fold but scrollable on
any real canvas, and a phone is taller than 600 logical pixels. The precedent at `details_launch_test.dart:46`
uses `ensureVisible` + `pumpAndSettle`, but the new call correctly uses a bounded `pump()` — `pumpAndSettle`
never settles on any screen carrying a starfield (deferred item 4), so copying the precedent verbatim would
have hung the test. Moving the panel to the top of the `_CoastDock` would have kept the test verbatim at the
cost of deviating from the plan's explicit placement, and would have put the activation panel above the
readout that explains why it is needed.

**Cost if the ruling is wrong:** if `SingleChildScrollView` at `:331` were ever removed or the panel moved
outside it, the button becomes genuinely unreachable and this test's `ensureVisible` would fail loudly rather
than silently pass — so the failure mode is a red test, not a false green.

**Task 21 task review dispatched** on sonnet (read-only), package `review-48247c2..d224c54.diff`, with two
things to check rather than accept: (a) that test 1's `activate.onTap, isNull` genuinely discriminates a
disabled button from a live one, given the brief's own argument that `activate()` self-refuses at 0 EN so no
tap could tell them apart; (b) that the added `ensureVisible` is the honest fix rather than masking an
unreachable button, i.e. that `:331`'s `SingleChildScrollView` is what makes it reachable.

### Task 22's brief pre-flighted again — two of its own claims were wrong

I re-derived every citation in `task-22-brief.md` against HEAD before dispatching it, the same pass that
caught L13. Two defects, both of them the class this task exists to clean — a claim in the plan's own text
about the plan's own structure that is false:

1. **L10's citation pointed at the wrong claim.** The row said `cruise_test.dart:655`; at HEAD that line is
   `reason: 'precondition: docked, so there is an own planet to exclude');`, and the claim it quotes —
   "The explored planet is still the nearest candidate…" — is at **`:685-686`**. Task 20's fix round inserted
   its 250 EN turn test at `:496-524`, i.e. *above* L10, which falsifies the paragraph's blanket sentence
   "The test-file numbers are still accurate (every insertion was below them)". **Both corrected**: the
   paragraph now names L10 as the one test-file row that moved and gives the cause, and the row is retargeted.
   The other seven test-file rows were checked too and hold to within two lines (L3's text is on `:50`, L7's
   comment opens on `:75`, L8's on `:43`, L9's on `:91`), so the paragraph says so and tells the implementer
   to expect them to hold rather than to re-verify blind.

   I also **sharpened the row's instruction, having verified the conclusion myself.** The brief's fallback was
   "if the fixture has a featured candidate, say what the assertion really pins instead". The sharper fact:
   in this test `rec0` is `c.recommendedDestination` *before* `_setExplored` (`:678`), so it is the planet the
   rule itself picked; exploring it changes only `stateOf`, which only the guard reads (`:998-999`), leaving
   its `featured` flag and distance untouched. So the comment's **conclusion** — absent the guard, `rec0` wins
   again — is true, and only its **reason** is false. The row now says to check the two separately and gives
   the reason to replace it with, rather than leaving the implementer to wonder whether the assertion pins
   anything at all.

2. **The count was stale by one, and the two INFO notes looked like missing rows.** The brief opened
   "L3–L10 plus its two INFO notes are ten claims … Task 17's reviewer added three more (L11–L13)" and titled
   itself 十三条, while its table enumerates **eleven** rows (L3–L13) and a separate 3-item plan list. An
   implementer reading that would hunt for two unlisted findings. They are not missing: the two INFO notes
   **are** items 1 and 2 of the plan list (INFO 1 = the Self-Review's coverage claim at plan `:4329`, INFO 2 =
   the 「Four deviations」 count at `:4353`) — recorded in this ledger at `:2230` and `:2233` when the table was
   pre-flighted. The total is **fourteen**: 11 table rows + 3 plan items, the third being the Execution Handoff
   item I added after the count was written. Brief title and commit message both now say fourteen, and the
   opening says explicitly where the two INFO notes live so no one goes looking for rows that do not exist.

**Cost if either correction is wrong:** L10's implementer edits a comment that is already correct at `:655`
(which would corrupt an unrelated `reason:` line), or spends the dispatch hunting two findings that are in the
plan list it was already given. Neither touches behaviour; both would have cost a fix round.

**Ruling: dispatch Task 22 after Task 21's review closes, not alongside it.** Task 22 edits
`cruise_ui_test.dart` (L3) and `galaxy_map_3d_page.dart` (L11, L12) — two of the three files Task 21 just
changed and whose diff the reviewer is currently reading — and Task 21's review may yet return a finding
requiring a fix round in the same files. Sequential is the only safe order here, and the skill forbids
parallel implementers in any case.

**Task 21 task review returned: ✅ spec compliant, Approved — no Critical, no Important, three Minor.**
Reviewer on sonnet, read-only, on `review-48247c2..d224c54.diff`. It verified all three of the brief's claims
rather than accepting them, and its verifications are the ones that matter:

- **The `>=` gate matches `activate()` on both sides.** Panel: `final energy = controller.energy; final
  canActivate = energy >= cost;` (`journey_page.dart:771-772`). Controller: `if (_player.energyBalance < cost)
  return false;` (`game_controller.dart:1218`), `cost = _ship.engine.activationCost` (`:1217`, `= 5` at
  `engine.dart:138`). Equality allowed both sides, so the 「需要 5 EN（现有 5 EN）」-on-a-disabled-button
  contradiction a `>` gate would produce is avoided.
- **Test 1's `activate.onTap, isNull` genuinely discriminates.** `activate()` refuses at 0 EN (`:1215-1218`),
  so a live button wired to `onActivate` leaves `isDormant` true and `energy` 0 exactly as the disabled one
  does — no tap-based assertion could have told them apart. The `find.ancestor(…, find.byType(InkWell))` read
  resolves to the panel's button: `_ActionButton` (`:1313`) has one `InkWell` (`:1343`, `onTap: onPressed`
  `:1345`), and `find.text('激活引擎')` is asserted `findsOneWidget` one line above.
- **Test 2's `前往训练补充能量, findsNothing` reason holds.** `_CoastDock` renders it under `if (!canBrake)`
  (`:942`); `canBrake` is `!hasMomentum || energyBalance >= brakingCost` (`game_controller.dart:983`), and
  coasting at 100 EN with `brakingCost = energyCostFor(40) = 100` gives `100 >= 100` = true → hidden.

It also confirmed the overflow risk I flagged is structurally impossible here (`:331`'s `SingleChildScrollView`
wraps the `Column` holding both docks at `:371-385`), and that the `ensureVisible` is not masking an
unreachable button — the paired `pump()` (not `pumpAndSettle`), the uniqueness of `激活引擎` in that test, and
`expect(c.isDormant, isFalse)` / `expect(c.energy, 95)` together prove the tap landed and fired. It checked the
`IndexedStack` finder-collision risk against the cockpit's own identical `激活引擎` and showed the default
finder skips the unselected child, citing the pre-existing `cruise_ui_test.dart:80` as evidence.

**Rulings on the three Minors:**

1. **Two stale line numbers in test 1's comment → folded into Task 22 as rows L14 and L15.** `:741` cites
   `journey_page.dart:1270` (now **`:1345`**) and `:742` cites `braking_test.dart:493` (now **`:497`**). I
   verified both myself: `journey_page.dart:1345` is `onTap: onPressed`, and `braking_test.dart:493` is
   `await tester.pump();` while the read it means is at `:497`. Both claims are true; only the numbers are
   wrong. **Ruling: fold rather than dispatch a fix round** — identical defect class, the file is already in
   Task 22's list, and a whole dispatch for two numbers in a comment is not worth it. **Cost if wrong:** Task
   22's diff touches two more comment lines than its original remit, and its report must show the count moved
   14 → 16 (which the brief now says).
2. **The duplicated three-line mount in both docks → deferred item 12.** Plan-mandated; presentation wiring,
   not a logic block; §9.3's "one component rather than the same entry written twice" is genuinely met
   (`_EnginePanel` is shared, and the two docks differ only in the controller and callback they hand it).
   Parked as Minor with the question the final review should answer (does this project extract mount sites as
   well as components?).
3. **`_EnginePanel`'s doc says its gate "matches" `activate()`'s guard while the two read different fields →
   deferred item 13, ruled under-justified rather than false.** The panel gates on `controller.energy`
   (live, burn-subtracted, floored at 0 — `game_controller.dart:456-464`); `activate()` gates on raw
   `_player.energyBalance` (`:1218`). I derived that the two **agree in every reachable state**: a dormant ship
   is never cruising (`halt` stops it, `coast` turns the engine off), so `_cruiseBurnNow()` is zero and the
   getter reduces to `max(0, energyBalance)`, and a dormant ship has no in-progress journey so the first
   branch is dead — hence both gates agree on both signs, including `energyBalance < 0` where both compare
   `0 >= 5`. The reviewer reached the same conclusion from the safety direction and also could not construct a
   counterexample. **Ruling: park, do not add to Task 22** — the sentence is true, so correcting it is a
   clarity improvement, and the same overstatement is inherited from Task 20's cockpit
   (`galaxy_map_3d_page.dart:1216-1220`), which makes it a whole-branch decision rather than a task fix.
   **Cost if wrong:** a doc reads "matching" where the code has a one-sided relationship that happens to be
   exact.

**Task 21 final state:** `flutter analyze` → `No issues found!`; `flutter test` → **342 passed**. Commit
`d224c54`, working tree clean. **Task 21 COMPLETE.**

### The `deferred-items.md` line numbers were re-verified while waiting

Every citation in the file the final reviewer will read was checked against HEAD, because Tasks 19-21 inserted
lines into most of the cited files and a wrong pointer in the last gate is expensive. Four had gone stale and
are marked in place: **item 1** (`:660`/`:659` → `:690`/`:689`, in `'is never a planet that has already been
explored'` at `:674` — Task 20's fix round shifted it), **item 10** (`:1399-1401`/`:1386` → the three colours
at `:1399`/`:1403`/`:1409` and the dead-tap line at `:1391`), **item 11** (`:1238` → `:1246`, twice, with
`turningIsDearer` at `:1214`), and **item 9**'s `game_controller.dart:1306-1308` → `:1305-1307`. Verified
correct as written: item 2's `fuel_out_test.dart:22`, item 4's `starfield.dart:97` (path is
`lib/ui/widgets/starfield.dart`, not `ui/shell/`) and `lib/app.dart:65`, item 5's `cockpit_hud.dart:105`,
item 11's `game_controller.dart:1279` and `:983`.

**Task 22 dispatched** (BASE `d224c54`) — see the dispatch note below.

**Task 22 implementer reported DONE** — `e945ede`, `docs(starward): correct sixteen false claims in the
free-cruise comments`. BASE `24b4129` → HEAD `e945ede`. Nine files: the six test files, the two `lib/` files
(L11–L13), and the plan doc. `flutter analyze` → `No issues found!`; `flutter test` → **342 passed**, the same
count as Task 21's run, which is the evidence that nothing but comments moved. Review package written:
`review-24b4129..e945ede.diff` (1 commit, 26370 bytes). Working tree clean.

Its own diff audit reports no changed assertion and no changed pinned number, the only two exceptions being
the ones the brief permits (L4's test name, L5's `reason:`). Three notes it raised rather than hid:

- **L9's arithmetic reproduced independently** — `[59.6695°, 60.3311°]`, 0.3305° below 60° and 0.3311° above,
  matching the brief. It also observed that the table cites `heading_test.dart:93-95` while the flagged
  sentence actually begins on `:94`, which matches my own pre-flight (the comment opens at `:91`, the
  load-bearing sentence at `:94-95`). Comment-only, so not retargeted.
- **L4's new test name is its own wording** — `'secondsForEnergy is 15 s per EN, with no floor of its own'` —
  and L8's rewrite likewise, since the brief left both open. Both are flagged in the report as choices rather
  than as brief-supplied text, which is the right way to report them.
- **L5's `reason:` is one logical string split across two adjacent literals** to keep lines short. Valid Dart
  and analyze-clean; I asked the reviewer to check the seam specifically, because a split string is where a
  character goes missing and no test catches it — a `reason:` only surfaces on failure.

**Task 22 task review dispatched** on sonnet (read-only), package `review-24b4129..e945ede.diff`, with four
things to check rather than accept: the "no assertion, no pinned number changed" claim across a nine-file
diff; L5's split-string seam; L9's band re-derived from `Engine.turnCostFor`'s formula rather than from either
document; and L10 plus plan item 2, the two rows the brief told the implementer to re-derive and report. The
prompt's central instruction is that the replacements must themselves be true — a corrected comment that is
still false is worse than the original, because it now looks checked.

**Task 22 task review returned: ✅ spec compliant, Approved — no Critical, no Important, no material Minor.**
Reviewer on sonnet, read-only, on `review-24b4129..e945ede.diff`. It re-derived every row independently rather
than trusting the report, and its verdict on the four things I asked it to check:

- **The contract holds.** Scanning every `+`/`-` line, the only non-comment, non-prose changes are L4's test
  name (`cruise_test.dart:311`) and L5's `reason:` (`cruise_save_test.dart:283-285`) — the two exceptions the
  brief permits. Every `expect(`/`closeTo`/`greaterThan`/`lessThan`/`isTrue` line appears as unchanged context,
  and no other test name moved.
- **L5's split string is intact.** The seam is `...needs its '` + `'own save migration'`, preserving the single
  space; it concatenates to the intended sentence, loses no character, and does not drift into the next test's
  job.
- **L9's band is right, and the reviewer noted one refinement without calling it a defect.** `turnCostFor(θ) =
  round(200·sin(θ/2))` from `engine.dart:120-123` gives the 100 EN band as `[59.6695°, 60.3311°)` — upper edge
  open, because `round(100.5) = 101`. The comment states the closed `[59.67°, 60.33°]`, whose rounded endpoints
  both read 100, so it is true as written and matches the brief's own "Make it true" column verbatim. Recorded
  here rather than fixed: the open/closed distinction is a real refinement of the true statement, not a false
  claim, and it is worth exactly one parenthesis if anyone ever revisits that comment.
- **L10 and plan item 2 survived re-derivation.** L10: `rec0` is read at `cruise_test.dart:678` *before*
  `_setExplored`, so it is the rule's own winner, and exploring it touches only `stateOf` — the conclusion is
  true and only the reason was replaced, with no invented justification. Plan item 2: the top-of-plan section
  says "Six places" and lists 1-6; deviation 5 is restated in invariant 2 (`plan:46`), invariant 3 (`plan:47`)
  and `_reconcileCruise`'s doc (`game_controller.dart:1134-1136`), and deviation 6 in `activate()`'s doc
  (`:1207-1214`) — so the "safe to omit because restated where an executor cannot miss them" account checks
  out, and the closing opener now says "Six deviations … The four rows below are a selection" without padding
  the table.
- It also confirmed the two citations this task *added* are correct at HEAD (`journey_page.dart:1345`,
  `braking_test.dart:497`) and that L13's supporting claim holds in full (`cockpit_hud.dart:1-6` imports no
  `game_controller.dart`).

**Task 22 final state:** `flutter analyze` → `No issues found!`; `flutter test` → **342 passed**. Commit
`e945ede`, working tree clean. **Task 22 COMPLETE.**

---

## ALL 22 TASKS COMPLETE — proceeding to the final whole-branch review

Phase 1 (词汇), Phase 2 (点火与耗电), Phase 3 (休眠、激活与入口), Phase 4 (座舱改向) and Phase 5 (the six
findings the first whole-branch review returned) have all shipped and been reviewed. The branch is
`fddbc63..e945ede`, 71 commits, suite at **342 passed**, `flutter analyze` clean.

The final review is dispatched on the most capable model over the whole range, with `deferred-items.md` (live
items 1, 2, 3, 6, 8, 9, 10, 11, 12, 13, every line number re-verified at HEAD) as its attention lens, the
plan's Global Constraints, reference economy and three invariants verbatim, and the instruction to judge each
parked ruling rather than accept it.

---

## The final whole-branch review's verdict (opus, agent `a0a94a4f0dc25315f`)

**No Critical. One Important. Two Minor.** The reviewer walked spec §3–§11 and found §6 **partial** (the
journey-destination marker source is not drawn), §9.5 **vacuous** (no `lib/ui` file references
`EnergyTxType`, so there is no type-label map to extend — no work owed, and I confirmed this by grep), and
§8.4 + §10.1 test #15 **absent**. It adjudicated all ten live deferred items: **"park was correct" on every
one**, with two caveats worth recording — item 6's `'360°'` is a genuinely wrong reading rather than merely
cosmetic (a bearing in `[359.5, 360)` renders `360°`, not `0°`), and item 10's park rests on there being
exactly one colour assertion in the project (`braking_test.dart:676`, a *selected*-chip decoration), so the
park holds but pinning the disabled detail colour would be defensible. It also confirmed item 11's ruling
(the brake hint withheld when `canBrake` is false) was right, and that item 8's two false premises are not
repeated in shipped code or comments.

### Ruling on the Important finding — keep the shipped guard, correct the record

The finding: spec §8.4 requires `correctHeading` to refuse a turn that would spend the braking reserve
(`energyBalance - cost < cruiseReserve`), §10.1's test #15 pins it (280 EN → 180° → false; 300 EN → 180° →
true), and the shipped guard is `if (energy < cost) return false;` (`game_controller.dart:1357`). No
deviation row records the dropped term, while invariant 2 (`plan:46`), `cruiseReserve`'s doc
(`game_controller.dart:1234-1238`) and `_reconcileCruise`'s doc (`:1127-1132`) all claim the protection
exists — and the branch's own `cruise_test.dart` test `a turn can leave a cruising ship unable to brake`
(250 EN → 180° turn → 50 EN, `canBrake` false) disproves it.

I derived this myself rather than taking the verdict, and **ruled the opposite way from the finding's
preferred fix**: the guard stays, the claims move to match it.

*Ruling:* keep `if (energy < cost) return false;` — the spec's floor is voided by deviation 5 and
contradicts the user's own decision. *Why, in four steps, each checked against code or spec text:*
1. The floor's stated reason is to protect `halt`'s braking reserve ("转向花的钱不能吃掉 `halt` 的制动储备").
   Deviation 5 made `halt`'s automatic stop **free** — `_reconcileCruise` books no `braking` entry — so
   there is no brake money for a turn to spend. The reason is void.
2. The spec's own rule sets the reserve to 0 under `coast` ("`coast` 策略下储备为 0，门槛就是普通的有钱"),
   where the floor collapses to ordinary affordability. The plan made `cruiseReserve` 100 for **both**
   policies (state-independent, `:1239`), which is *stronger* than the spec for `coast`.
3. Applied to both policies, the floor newly forbids a 90° turn below **241 EN** (141 + 100) — the last
   ~70% of a 3000 s cruise — against the user's decision that a heading may be corrected **at any time**,
   priced by the angle. And the alternative it would push a low-tank player to is closed: `igniteCruise`
   refuses at `energy <= cruiseReserve` (`:1316`), so braking at 150 EN leaves 50 EN and no relaunch.
4. 已知取舍 #2 rejects *"refusing a turn the ship cannot sustain"* — which is **not** this floor. The
   floor refuses a turn that would spend the **stop** money, a narrower refusal the plan never argues
   against. So the plan's tradeoff note does not reach the floor it silently dropped.
*Cost if wrong:* a `coast`-policy player who turns on a low tank can spend the reserve and must train to
recover — a state 已知取舍 #2 already documents and the `!canBrake` training gate (`journey_page.dart:942`)
exists to serve. Reversible in one commit. The alternative (restoring the floor) would have inverted or
re-fixtured **eight** tests in `heading_test.dart`, the `cruise_test.dart` trap test, and the cockpit
turn-dialog test — every one of them built on a partly-spent tank — and would have made the trailing
`_syncDormancy()` call in `correctHeading` provably dead (`raw_after >= 100 + burn`), a defect of exactly
the class this branch has been clearing.

Also ruled: **fold the §6 gap and the hardcoded fee into the same fix round.** The §6 journey marker is a
spec requirement the user's standing instruction ("补完六项" — finish the spec's requirements rather than
document them away) covers, it is cheap, and the marker machinery already exists. The two
`（5 EN）` literals are Task 22's own defect class. Three findings, **one** fix dispatch, three commits.

**Task 23 dispatched** (opus, agent `a0a2eb6be6f590828`) over BASE `e945ede`, brief
`.superpowers/sdd/2026-10-14-starward-free-cruise/task-23-brief.md`: Part A the four record edits
(invariant 2, deviation 2's `Why`, new deviation 7, both six→seven counts, plus three code doc comments),
Part B the §6 voyage marker with distances on both spec markers, Part C the two interpolations.

## Task 23 — my verification of the implementer's output, and the residual dispatch

BASE `e945ede`, HEAD `510eda6` (three commits: `653429e` Part A, `a31ba77` Part B, `510eda6` Part C).
`git diff --stat e945ede..HEAD` = 5 files, +107/−13. `flutter analyze` → `No issues found!`;
`flutter test` → **344 passed** (342 baseline + Part B's 2).

Verified true against the tree, one by one: the `_worldScale` units catch (my brief's Part B formula
`(_c.playerPosition3D - scene.positionOf(id)).length` mixed ly with world units; `_shipPos` is
`_c.playerPosition3D * _worldScale`, `_worldScale = 12` at `galaxy_map_3d_page.dart:37`, `:103`; the
implementer's `(_shipPos - scene.positionOf(id)).length / _worldScale` is algebraically
`c.distanceTo(planet)`, which is what the two new tests derive their expected strings from); the
`!canBrake` gate is at `journey_page.dart:943`, not the `:942` my brief cited — the implementer used the
accurate number; `game_controller.dart:1374` is `if (energy < cost) return false;`; `:1326` is the
`igniteCruise` refusal; `locationLabel` at `:467`; the 银心 marker is still the bare `'银心'` const, so
`cruise_ui_test.dart`'s exact `contains` still holds; deviation 2's corrected `Why` is true of the shipped
guard; deviation 7's arithmetic (241 = 141 + 100; 1 − 885/3000 = 70.5%); the three rewritten doc comments
(`cruiseReserve`, `_reconcileCruise`, `correctHeading`).

**Ruling: the implementer's concern 2 needs no change.** The residual `four`/`six` counts it flagged sit
inside the *appended Task 22 brief text* (`~:6170`–`:6272`), where they are quotations of the pre-Task-22
wording that the brief exists to correct — instructions, not claims about the current plan. The plan's
normative sections are consistent at seven, and the other instances are correct in context (`:4330` "the
six the first pass missed" = Phase 5's six findings; `:4354` "The four rows below" = the table's 4 rows).
*Cost if wrong:* a reader who takes an embedded task brief as a description of current state is misled
about a count that the normative sections state correctly three times.

**Two residuals found and dispatched, resuming the same implementer** (a continuation of the same fix
round, not a new one, so the skill's ONE-fix-dispatch rule holds):

- **R1 — invariant 2's headline is still a false universal, and it is the very defect A2 fixed.** As landed:
  "**A cruise's *burn* always leaves enough in the tank to buy the ship's own stop.** … so a ship that has
  just run dry can still afford the 100 EN brake." Post-turn at 50 EN the burn leaves 50 — not enough — and
  the ship cannot afford the brake. The paragraph's own third sentence names that exception, which makes the
  paragraph honest overall but leaves sentences 1–2 false universals followed by their own exception. The
  implementer scoped A2 correctly ("when the burn is the only thing that has spent"); invariant 2 needs the
  same treatment. I flagged one derivation hazard for them to check rather than inherit: `_settleCruise`
  bills the *raw* elapsed burn with no reserve cap, so a universal "the burn never spends the reserve" may
  itself be violable — scoping the invariant to the **exhaustion rule** (which is what deviation 5 is about)
  avoids that.
- **R2 — the Self-Review and deviation 7 now contradict each other.** The Self-Review's coverage sentence
  (`~:4330`) opens "Every numbered requirement in the spec maps to a task…" while deviation 7 records that
  §8.4's floor and §10.1's test #15 are deliberately **not** implemented. Two sections of one document
  disagreeing is this branch's defect class. One pointer added; the "five phases" and "the six the first
  pass missed" counts stay (both correct).

Both prose-only, one file, one commit expected on top of `510eda6`. Next: generate
`scripts/review-package PLAN_FILE e945ede HEAD` and dispatch **one** scoped re-review (mid tier — Part B
added behaviour), then adjudicate residuals.

### Residuals landed — `61b6110`

One commit on top of `510eda6`, prose-only, 2 hunks in the plan. `flutter analyze` → `No issues found!`;
`flutter test` → **344 passed**, unchanged as required. Tree clean.

**R1 ADDRESSED.** Invariant 2 now reads: "**Exhaustion keeps the braking reserve, and only the exhaustion
rule does.** The exhaustion rule bills at most `balance − cruiseReserve`, so for **both** policies a cruise
that runs out of budget stops with the reserve intact — a ship that has flown to exhaustion without turning
still holds the 100 EN brake. Other rules are not capped: `_settleCruise` bills the raw elapsed burn, and
`correctHeading` prices a turn against the whole tank and may spend into the reserve — so a ship that turns
below it and then runs dry ends dormant below the reserve, unable to brake. See deviation 7 and 已知取舍 #2.
The spec spends the reserve instead; see deviation 5." The hazard I flagged was real and the implementer
produced a concrete counterexample: `_settleCruise` (`:1054`) deducts the raw `burnForSeconds(elapsed)` with
only a `math.max(0, …)` floor, and `stopShip` (`:1288`) calls it with no `_reconcileCruise()` ahead — so
300 EN + a stop at t=3100 s bills 207 EN and lands the tank at **93**, below the reserve. (The exhaustion
path itself is safe: `tick()` reconciles at the exhaust instant, `:797-801`, before anything else settles.)

**R2 ADDRESSED.** The Self-Review now reads "Every numbered requirement in the spec maps to a task — the six
the first pass missed having been added as Phase 5 after the first whole-branch review — with one deliberate
exception, recorded as deviation 7 (§8.4's reserve floor and §10.1's required test #15 are **not**
implemented)". Both counts and every per-section mapping are untouched and correct.

**Ruling on the one residual nuance I am NOT dispatching a third round for.** Invariant 2's general clause
("a cruise that runs out of budget stops with the reserve intact") reads slightly broader than the mechanism
it describes: in the turn case the budget is ≤ 0, `_cruiseExhaustTime` returns `driftStartedAt`, and
`_reconcileCruise` books nothing — so the ship stops at 50 EN, *not* with the reserve intact. But the clause's
own first sentence defines the mechanism as the exhaustion rule's billing, under which reading it is exactly
true, and the sentence's illustration ("a ship that has flown to exhaustion **without turning**") carries the
real scope, with the turn case named in the next sentence. That is a scoping nuance, not a false universal:
compare what R1 replaced, which was false under *every* reading. — *Cost if wrong:* a reader who takes
"runs out of budget" to include the turn case expects the reserve to survive and is corrected by the very
next sentence. Recorded as **deferred item 14** so the record shows it was seen and judged, not missed.

## Scoped re-review over `e945ede..61b6110` (sonnet, agent `ab398ddf0e4ff6a0f`)

**Verdict: findings remain open — 1 and 4 NOT ADDRESSED; 2, 3 and 5 ADDRESSED; no new Critical/Important
breakage.** Package `review-e945ede..61b6110.diff` (4 commits, 31,768 bytes).

- **F2 (§6 marker + distances) ADDRESSED**, with the unit question settled independently: `_markerDistance`
  (`galaxy_map_3d_page.dart:317-318`) is `(_shipPos - scene.positionOf(id)).length / _worldScale` with
  `positionOf` = `planet.pos * worldScale` (`galaxy3d_scene.dart:69`), so the quotient is ly and equals
  `distanceTo` (`game_controller.dart:488-489`); the two tests derive their expected strings from
  `c.distanceTo(...)` + `StarLabels.distance`, so a dropped `/ _worldScale` renders `12·d` and fails.
- **F3 (hardcoded 5 EN) ADDRESSED** — both sites interpolate, no third `休眠状态` site, no test pins the
  literal. **F5 (Self-Review vs deviation 7) ADDRESSED** — rows = 7, both counts = 7, and every
  restatement site the closing summary names exists.

**F1 and F4 NOT ADDRESSED — and the reviewer is right.** The residual commit scoped the plan's *headline*
to the exhaustion rule but left the sentences that actually carry the guarantee still universal. Verified
all three myself:
- `cruiseReserve`'s doc (`:1240`) says "Held back by the *exhaustion rule* — **the burn never spends it** —
  not by every rule that spends", and names only `[correctHeading]` as an exception. False, and the
  exception list is incomplete: `_settleCruise` bills the burn uncapped.
- `_reconcileCruise`'s doc (`:1135-1137`) conditions the guarantee on "when the burn is the only thing that
  has spent" — a condition satisfied in the very state that refutes it, since `_settleCruise` bills the burn
  too and this method's `burned > 0` guard then skips the deduction.
- Invariant 2 (`plan:46`) still says a cruise that runs out of budget "stops with the reserve intact — a ship
  that has flown to exhaustion **without turning** still holds the 100 EN brake". The 300 EN / t=3100 s case
  did not turn and does not hold the brake; "without turning" scopes away the wrong variable.

So the same commit scoped one sentence and left its two subordinates asserting the opposite — the branch's
classic shape, and one notch worse than the original because it now looks checked.

**Ruling: the reviewer's reachability reasoning is WRONG and must not propagate.** It argued the cockpit has
no tick ("only the voyage screen calls `tick()`", `journey_page.dart:107`) so a cruise runs past its budget
while the cockpit is open. The tick is a `Timer.periodic(1 s)` in `JourneyPage`'s State, the shell is an
`IndexedStack` (`home_shell.dart:35`), and `_sync` keeps the timer alive while `hasMomentum` **on every
tab** — so the cockpit is not tick-less and `tick()` reconciles at the exhaust instant (`:797-801`) before
anything else settles. **My derivation, handed to the implementer to check:** the overspend needs a gap of
**≥ ~7.5 s** between the exhaust instant and the `_settleCruise` call, because the bill at t = exhaust + δ is
`round(200 + δ/15)` — so δ ≤ 7.5 s still rounds to the budget and lands the tank exactly on 100. That gap
opens when the app is killed or suspended across the exhaust instant and the player brakes before the first
post-resume tick, or when a tick runs ≥ 7.5 s late. Narrow but reachable, and `stopShip`'s own comment
(`:1285-1287`) already concedes the burn "is spent whether or not the brake goes ahead". — *Cost if wrong:*
the fix is prose either way, but the implementer would write the reviewer's false mechanism into a comment
and manufacture a fresh instance of the defect the round exists to remove.

**Ruling: fix round 2 is prose-only; no behaviour change.** `_settleCruise` must bill the energy the ship
actually burned — capping it there would make the ledger lie about energy spent and would move deviation 5's
premise (that the *exhaustion* rule holds the reserve). The state it opens is 已知取舍 #2's documented trap.
*Cost if wrong:* a player in that window has a brake declined and must train to recover. Dispatched by
resuming the Task 23 implementer (round 2 ≤ 3), three sites: `cruiseReserve`'s doc, `_reconcileCruise`'s doc,
invariant 2.

**New deferred item 15** from the re-review's out-of-scope observation, recorded in `deferred-items.md`:
`_brakeFromCockpit` (`galaxy_map_3d_page.dart:274-278`) shows the snackbar `已制动停下` unconditionally after
`await _c.stopShip()`, while `stopShip` settles first and then returns without braking when `canBrake` is
false (`:1288-1293`) — so in that same narrow window the message claims a stop that did not happen. Not
folded into fix round 2: it is a behaviour fix in a UI file, pre-existing and untouched by this diff, and
mixing it would muddy a prose-only review surface.

### Fix round 2 — `7d70418`

One commit on top of `61b6110`, prose-only (`game_controller.dart` + the plan, 3 hunks).
`flutter analyze` → `No issues found!`; `flutter test` → **344 passed**, unchanged. Tree clean.

Three sites, all scoped to the exhaustion rule's own billing: `cruiseReserve`'s doc now says the reserve is
held back by the exhaustion rule "which bills at most `balance - cruiseReserve` — and by that rule alone",
and names **both** uncapped spenders (`correctHeading`, `_settleCruise`); `_reconcileCruise`'s doc is now
about *this method's own deduction* ("bills `balance - cruiseReserve` when that is positive, which lands the
tank on the reserve whenever it was still above it") and names both ways the tank can already be below (a
turn, or an earlier `_settleCruise` billing a leg already past its budget); invariant 2 is retitled "**The
exhaustion rule's own billing keeps the braking reserve, and only it does**", carries the correct
precondition ("a cruise that reaches the exhaustion rule with the tank still above the reserve"), and states
the turn-free entrance. 已知取舍 #2 gained one sentence for that entrance so the trap record and invariant 2's
pointer agree. Deviation 7 untouched — its claims remain true.

**The implementer's derivation is sharper than mine and I accept it.** A merely *late* tick cannot overshoot,
because `_reconcileCruise` clamps — only `_settleCruise`'s raw bill can. So the trigger is a **skipped
reconcile**, not a late one: `init()` calls `_reconcileJourney()` only, and there is no
`WidgetsBindingObserver` / `didChangeAppLifecycleState` anywhere in `lib/`, so a suspension or kill across
the exhaust instant leaves the cruise unreconciled until the first post-resume tick, and a settlement in that
window bills the whole suspended span. This also refines R1: the 300 EN / t=3100 s example needs the
reconcile skipped (normally the t=3000 s tick lands the ship dormant at 100); R1's claim that `_settleCruise`
has no cap stands.

**I verified the round's load-bearing universals myself before dispatching the re-review, and all hold:**
"nothing reconciles a cruise on resume" — `init()` (`:114-128`) reconciles the journey only, and the
lifecycle-observer grep across `lib/` is empty; "only training recovers the ship" — `_addEnergy` has exactly
two call sites, training (`:1568`) and `completeExploration`'s one-time reward (`:1520`), and the exploration
route needs a planet the trap state is not at, while `activate` (5 EN) leaves 88, `igniteCruise` refuses at
`energy <= cruiseReserve` (`:1326`), `launchJourney` needs the 100 EN brake at departure, and `returnToOrigin`
requires an in-progress journey (`:1440`) that a cruise never has. The threshold: `burnForSeconds(s) =
round(s/15)`, so the bill at exhaust + δ is `round(budget + δ/15)` and δ = 7.5 s already overshoots by 1.

**Adjudicated: the implementer's concern about the bare 7.5 s figure needs no change.** The plan states every
other economy number as a bare fact under the reference tuning it pins verbatim in Global Constraints (100 EN
reserve, 241 EN, the 200 EN turn), and the parenthetical names the mechanism ("the gap the burn's whole-EN
rounding needs"). The durable form the implementer preferred (`0.5 / powerDrawPerSecond`) is the same fact
written differently; consistency with the plan's own convention wins.

Next: scoped re-review of `61b6110..7d70418` (sonnet), then the endgame.

## Scoped re-review over `61b6110..7d70418` (sonnet, agent `a121643b27dbd35e0`)

**Verdict: both assigned findings ADDRESSED; one new Important false universal + one Minor introduced by
round 2's own text.** Package `review-61b6110..7d70418.diff` (1 commit, 12,998 bytes).

Both findings ADDRESSED: `cruiseReserve`'s doc (`:1241-1246`) now scopes the reserve to the exhaustion rule
"and by that rule alone" and names both uncapped spenders; `_reconcileCruise`'s doc (`:1135-1141`) is about
its own deduction with both below-reserve entrances named; invariant 2 (`plan:46`) carries the correct
precondition. Clean on the checks I had asked for: "nothing reconciles a cruise on resume" TRUE (`init()`
`:114-128` reconciles the journey only; `_reconcileCruise` has exactly one caller, `tick()` `:799`; the
lifecycle-observer grep is empty across `lib/` **and** `test/`); the 7.5 s threshold TRUE and inclusive
(`burnForSeconds(s) = max(1, round(s/15))`, overshoot ⟺ δ/15 ≥ 0.5 ⟺ δ ≥ 7.5, verified in IEEE-754 with
`2.5*(1/37.5) == 1/15`); "for both policies" TRUE. Diff hygiene clean — no executable line moved.

**New Important — "The brake is then declined and only training recovers the ship" is false under `halt`.**
Verified myself, and this is a miss in my own round-2 check: `_reconcileCruise` zeroes the velocity for
`halt` and keeps it for `coast` (`:1169-1181`), so a stranded `halt` ship is **parked**, `brakingCost` is 0
without momentum (`:303-305`), and `_launchGate`'s lenient branch `available <= braking` (`:1614`) therefore
passes on any positive tank — so `activate()` (5 EN) plus a voyage home is open to it. Only `coast` is
genuinely stuck, because it is still drifting and its 100 EN brake is what blocks the gate. Reachable with no
suspension window: a `halt`-policy turn below the reserve suffices. My round-2 reasoning assumed the trap
state was adrift and never separated the two policies — the same class of error I have been ruling against,
made by me.

**New Minor — "bills at most `balance − cruiseReserve`" is false when `balance < cruiseReserve`**, where
`_reconcileCruise` bills 0 and `0 > balance − cruiseReserve`. True form: `max(0, balance − cruiseReserve)`.

### Ruling: stop narrating the consequences in invariant 2 — cut, don't patch

Three rounds have now landed on this one paragraph, each finding a narrower false claim, and the pattern is
structural: the paragraph does two jobs — state the guarantee, and narrate what happens to the player — and
every enumeration of consequences invites an incomplete list (round 2's "without turning" scoped the wrong
variable; round 3's "only training" scoped the wrong policy). The mechanism sentences have been stable and
correct across all three rounds; only the narration keeps breaking. So invariant 2 keeps the mechanism and
the pointers, and the player-facing consequence stays where it is already recorded and already true —
已知取舍 #2 (including round 2's `_settleCruise` sentence) and deviation 7 (coast-scoped). **The human partner
reviewed three candidate wordings with worked examples and chose this one**, so the text is mandated
verbatim rather than left to the implementer's judgment. *Cost if wrong:* invariant 2 no longer tells a
reader what a stranded ship can still do, so they follow its two pointers to learn it.

**Fix round 3 dispatched** by resuming the Task 23 implementer (round 3 ≤ 3), prose-only, one paragraph:
replace invariant 2 with the approved text, touch nothing else, sweep for other surviving "must train"
claims report-only, re-run analyze/test (expect 344 unchanged).

## Fix round 3 outcome — `053e721`, and its flagged defect

`053e721` `docs(starward): state invariant 2's mechanism without narrating the consequences` — the mandated
paragraph landed verbatim, one line of the plan, `game_controller.dart` untouched. analyze clean, **344
passed** (prose only). Implementer returned **DONE_WITH_CONCERNS** with one concern: a clause *inside the
text I mandated* is false under `halt`.

**The concern is right, and it is my error, not theirs.** Verified myself against the code:
`canBrake => !hasMomentum || _player.energyBalance >= brakingCost` (`:983`), `hasMomentum =>
driftVelocity.length > 0` (`:285`), `brakingCost` = 0 without momentum (`:303-305`), and `_reconcileCruise`
ends a `halt` cruise by zeroing the velocity in the same `copyWith` that sets `engineDormant`
(`:1175-1178`). So a `halt` ship whose tank is below the reserve when its cruise ends is **parked**, and a
parked ship can always brake — `brakingCost` is 0. The mandated clause "A ship whose tank is below the
reserve when its cruise ends cannot brake" is true for `coast` (momentum kept → 100 EN brake > tank) and
false for `halt`. The qualifier "when its cruise ends" is exactly what breaks it: at that instant the halt
rule has already parked the ship. Third round on this paragraph, third policy-asymmetric claim — and this
one I wrote, after writing the ruling that says not to.

### Ruling: the whole claim family is the spending, never the outcome

Three rounds have produced three false consequence claims and zero false mechanism claims. The mechanism
sentences — who bills what, and which rules are uncapped — have survived every review. Every defect has
been in a sentence that says what the state *costs the player*, because that is the one thing that depends
on the policy switch, the tick, and the order of settlement. So the rule for this branch is now: a claim
about the reserve states **what a rule does to the tank**, never what the ship can then do. Consequences
live in the plan's records (已知取舍 #2, deviation 7), which both the plan and the controller doc already
point at. *Cost if wrong:* a reader is told which rules can spend the reserve and must follow one pointer to
learn what that costs — the same trade the human partner chose when they picked "delete the consequence
sentence" over patching it.

Applied to every survivor the family sweep found (greps for `at most`, `unable to brake`, `cannot brake`,
`must train`, `only training` across `lib/`, the plan and the spec):

| Site | Claim | Verdict |
|---|---|---|
| `plan:46` | "A ship whose tank is below the reserve when its cruise ends cannot brake" | **false for `halt`** → cut |
| `game_controller.dart:1241` | the exhaustion rule "bills at most `balance - cruiseReserve`" | **false when `balance < cruiseReserve`** (it bills 0, and 0 > a negative bound) → `max(0, …)`, matching the plan's now-correct wording. This is the *same* defect the round-2 re-review found in the plan; the fix round 3 was scoped to the plan and this copy survived. |
| `game_controller.dart:1245` | the uncapped rules "leave the ship unable to brake" | true at the instant of spending under **both** policies (both spenders run while the ship has momentum, so `brakingCost` is 100), but it reads as the enduring state, which is `coast`-only — `halt` is parked by the next reconcile → cut the outcome clause, keep the spending |
| `plan:61` (deviation 7) | "a `coast`-policy player … must train to recover" | coast-scoped and true — no change |
| `已知取舍 #2` | "dormant again on the next tick, having bought a heading and nothing else"; the `_settleCruise` entrance "ends the same way, with no heading bought" | true for both policies — neither claims a brake outcome — no change |

**Ruling: the `halt`/`coast` severity difference is parked, not written.** A stranded `coast` ship cannot
brake *or* launch (`_launchGate`'s lenient branch needs `available > braking` = 100) and must train; a
stranded `halt` ship is parked, brakes free, and any tank above the 5 EN activation fee reopens the voyage
gate. That is a real player-facing asymmetry and the plan does not state it — but it is derivable from what
the plan *does* state (`_reconcileCruise`'s comment records the halt/coast velocity split, and `canBrake`'s
definition is one line), so it is a documentation gap, not a false claim. Writing it would mean another
policy enumeration in the very paragraph three rounds failed to stabilise. Parked as deferred item 16 with
the cheap fix noted. *Cost if wrong:* a reader who wants the trap's severity by policy derives it instead of
reading it.

**Fix round 4 dispatched** — fresh implementer (round 4 ≥ 4), three surgical replacements in two files, all
three verdicts above carried verbatim so the implementer does not have to re-derive them. Not escalated a
tier: nothing is stuck, the loop is converging (each round's defect is narrower), and the judgment this
round needs sits in the re-review, which I am putting on the most capable tier.

### Ruling: the family sweep was under-scoped, and the standard is "universals must be honoured"

Fix round 4's implementer reported one survivor outside its scope (`correctHeading`'s doc still said "leave
the ship unable to brake"). Chasing it, I found the earlier sweeps were **line-based**, and the phrase was
split across two lines (`...unable\n  /// to brake`), so `grep` never saw it. I re-ran the sweep
multi-line-aware, over `starward/lib`, `starward/test`, the plan and the spec, normalising comment leaders
so a phrase split by a line break still matches — and the family is larger than four rounds have assumed.

Standard I am applying from here, stated once so the remaining sites are not re-litigated one per round:
**a universal quantifier about the reserve must be honoured by the code, and a claim about what a ship can
do after its tank ends below the reserve must not be made at all.** Non-universal design-intent phrasing
("a cruise keeps it", "held back rather than spent") stays where the surrounding text scopes it in the same
breath — that is `cruiseReserve`'s first line, scoped by its own next paragraph, and the in-test comment at
`cruise_test.dart:337` next to the assertion that gives it meaning. Both were reviewed and accepted; I am
not reopening them.

Verdicts on every hit:

| Site | Claim | Verdict |
|---|---|---|
| `game_controller.dart:1364` | `correctHeading`'s doc: "can spend into the reserve and leave the ship unable to brake" | **fix** — the identical phrase cut from its sibling doc in round 4, same instant-vs-enduring reading, `coast`-only as the enduring state. Consistency, not a new rule. |
| `game_controller.dart:1137` | `_reconcileCruise`'s doc: "lands the tank on the reserve whenever it was still above it — so the ship can still afford its own stop" | **true, leave** — at the reserve the tank is exactly `brakingCost`, so `canBrake` holds for `coast`, and `halt` is parked. The precondition is stated in the same sentence. |
| `game_controller.dart:1239` | `cruiseReserve`'s first line: "Energy a cruise keeps in the tank so it can buy its own stop" | **leave** — scoped by its own next paragraph. |
| `game_controller.dart:431/520/603/981/1287` | `never`, `afford`, `canBrake`'s own doc | **true, leave** — none is a reserve guarantee; `:981` is `canBrake`'s definition restated. |
| `cruise_test.dart:333` | test name: "the reserve is what the cruise **must keep** to buy its own stop" | **fix** — a universal in a test name, and the exact wording Task 23 A1 removed from the doc. Rename to what the test asserts. |
| `cruise_test.dart:337` | "the reserve *is* the braking cost, held back rather than spent" | **leave** — design intent, scoped by the assertion beside it (the two quotes coincide *while cruising*). |
| `cruise_test.dart:441-444` | "Advancing further would burn the reserve too and leave nothing, which is a state the finished game **never reaches**" | **fix** — false. A settlement with no tick behind it bills the raw burn and floors the tank at 0 (`_settleCruise` → `math.max(0, balance - burned)`), which is the round-2 finding. Reachable across a suspension. |
| `cruise_test.dart:499` | test name: "a turn can leave a cruising ship unable to brake" | **true, leave** — `can` = possible, and the assertion pins it at that instant. |
| `braking_test.dart:371/399` | "a ship at rest is always stoppable"; "training is the way out of a drift that cannot afford to brake" | **true, leave** — no momentum means `brakingCost` 0; and for a drifting ship that cannot afford the brake, training is genuinely the way out. |
| `galaxy_map_3d_page.dart:216` | "the energy a cruise **always** holds back to buy its own stop" | **fix** — drop `always`; the scoping paragraph that saves `:1239` has no counterpart in a UI comment. |
| plan `:60`/`:61` | deviation 6's "not one they can be stuck in"; deviation 7's coast-scoped "must train" | **true, leave** |
| plan `:4342` | 已知取舍 #2's two sentences | **true, leave** |
| plan `:824`/`:928`/`:1096`/`:1165`/`:1304`/`:1675`/`:2571` | embedded task-brief prose and code blocks, incl. Task 8's original `_reconcileCruise` doc ("a cruise **always** keeps enough to buy its own stop") and the original `cruiseReserve` doc | **historical, excluded** — the twice-confirmed ruling. Task 23 A1/A2 rewrite both docs later in the sequence, so the plan is internally consistent as a sequence; editing a brief would rewrite the record of what was handed out. |
| spec | zero family hits | — |

**Ruling: the plan's embedded briefs stay historical even where the shipped file has since diverged.** A
brief records what was handed to an implementer; fix rounds are expected to supersede it (Task 23's Parts
A–C already do). Editing `:1096`/`:1165`/`:1304` to match the shipped files would make the plan claim its
own briefs said something they did not. *Cost if wrong:* a reader diffing a brief against the shipped file
sees a difference they must resolve in favour of the file — the same resolution Task 23 already requires.

**Round 5 = four edits in three files, and it is the last round.** Waiting for the in-flight re-review to
finish before dispatching it: it is reading `game_controller.dart`, and an implementer editing the same file
mid-read would shift its line numbers.

## Scoped re-review over `053e721..b3e1afd` (opus, agent `ab89ab972f736457b`)

**Verdict: all three findings ADDRESSED, every independent verification CONFIRMED, no new false claim in
either edited passage, and the diff is prose-only** (`5 insertions(+), 5 deletions(-)`, `///` lines plus one
plan line — no executable line, test or pinned number moved).

Confirmed independently, with the lines: `_reconcileCruise` bills `max(0, balance − cruiseReserve)`
(`:1157-1166`, deduction only `if (burned > 0)`); the billing block sits entirely *before* the policy read at
`:1170`, so it is policy-independent and only `:1176`'s `driftVelocity` differs; both spenders really can
leave the tank below the reserve (`correctHeading` prices against the whole tank at `:1376` and deducts at
`:1397`; `_settleCruise` bills the raw burn at `:1056` and floors only at zero at `:1060`, reachable because
`stopShip` settles before its gate at `:1290`); the 已知取舍 #2 / deviation 7 pointers both say what the
pointer claims; and neither edited passage makes any claim about what a ship can do once its tank ends below
the reserve. On the cuts: the reviewer judged each replacement true *and* adequate — the invariant still
gives a reader the guarantee plus the escape hatch.

**It also found the `correctHeading` survivor on its own** — `game_controller.dart:1364-1365`, the same
"unable to brake" wording, missed by a literal grep twice over (split across a line break, and the line
carrying `brake` also carries `canBrake`, so a `-v canBrake` filter drops it). It asked for a ruling on
whether the round's rule extends to method docs; my sweep table above already rules it in, and round 5
carries it. Its other sweep results agree with mine (`plan:61` coast-scoped and true, 已知取舍 #2 true for
both policies, spec zero hits). The ragged wrap at `:1245-1246` was acknowledged as a cosmetic artifact and
not raised.

## Scoped re-review over `b3e1afd..4947f11` (opus, agent `a4a80dfab4d1f464d`) — the loop closes

**Verdict: all four edits ADDRESSED, no new hard findings, prose-only, 344 tests intact.** Every claim
re-derived against the code with line numbers: the guard at `:1375` is a strict `<` so `energy == cost`
passes; `_settleCruise` at `:1377` re-pins before `:1395-1396` deducts, landing the tank on exactly 0, which
is what `_syncDormancy()` at `:1419` exists for (`:1206-1209`); the dropped clause was false as an enduring
claim because `halt` zeroes the velocity in the same `copyWith` that sets `engineDormant` (`:1171-1179`);
the renamed test's name states exactly the identity it asserts (`:336`, `:340`); the test comment's first
half holds because `tick` resolves at the exhaust instant and the reconcile bills up to it (`:797-800`,
`:1157-1159`), and its second half because `_settleCruise` has no reserve floor (`:1054-1060`); the cockpit's
button passes `braking: _c.cruiseReserve` (`:222`) for a ship that `igniteCruise` refuses while travelling
(`:1316`). It counted the declarations itself: 288 `test(` + 56 `testWidgets(` = 344. My own re-run agrees:
`No issues found!`, **344 passed, All tests passed!**

Two survivors it named and explicitly did not disagree with excluding, ruled here so neither is re-litigated:

- **`plan:~59` (deviation 5): "the reserve exists to guarantee a way out."** The loaded word, but teleological
  design intent with no quantifier, and its exceptions sit in the same block (deviation 7 three lines below,
  已知取舍 #2). *Ruling: leave.* Cost if wrong: a reader takes the reserve's purpose for its guarantee.
- **`plan:~5914`, inside Task 20's brief: "a cruising ship's balance can never be at or below it [the
  reserve]".** This one is **materially false** — a turn drops a still-cruising balance below the reserve, the
  250 → 50 state `cruise_test.dart:500` pins — and my own sweep's context filter missed it. *Ruling: exclude
  as embedded-brief text, not as a true claim.* It is the same species as Task 8's original doc comments: the
  brief records what was handed out, and the shipped file supersedes it — `galaxy_map_3d_page.dart:1265-1272`
  documents the 250 → 50 turn state explicitly, so the plan's sequence is consistent even though this brief
  paragraph is not. Editing the brief would make the plan claim it said something it did not. *Cost if wrong:*
  a reader of Task 20's brief meets one false universal and must resolve it against the shipped file, which
  the brief's own subject already requires.

**No open findings. The prose loop is closed at round 5** — five rounds, each narrower (a paragraph → three
sentences → one clause → one phrase → four universals), ending with a clean independent sweep over `lib/`,
`test/`, the plan and the spec. 16 items parked in `deferred-items.md`, none load-bearing.

Independent end-state verification by the controller: `flutter analyze` → `No issues found!`; `flutter test`
→ **344 passed, All tests passed!**; tree clean at `4947f11`.
