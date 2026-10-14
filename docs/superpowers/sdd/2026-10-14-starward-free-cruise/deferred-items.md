# Deferred items — for the final whole-branch review

These are the findings every earlier task review raised and the controller **deliberately parked**
rather than fixing, each with the ruling that parked it. None is known to be a live behavioural
defect. The final reviewer's job is to decide, for each, whether the ruling was right — and to say
so either way. A "park was correct" verdict is as useful as a finding.

Do not re-derive anything in the "already verified" list at the end.

**Three of these were closed by the controller on 2026-10-14, before this review** — items 4, 5 and 7,
each marked in place with the evidence. Items 4 and 7 had been written as open *questions*; both are
now answered and need no work. Item 5's claim is unchanged but the function it names was renamed by
Task 19, so the item carries a location correction. **The live items are 1, 2, 3, 6, 8, 9, 10, 11, 12 and
13.** Item 14 postdates the final whole-branch review — it was raised by the controller while adjudicating
that review's fix round — so it was never in that review's lens; it is recorded here because this file is
the branch's register of seen-and-judged findings. Item 11 is the only one that records a **behaviour** change rather than a coverage gap or a parked
question: read it even if you skim the rest, because it is the one item where the ruling changed what the
game does rather than what the tests assert. Items 10-13 all come from Task 20's and Task 21's reviews and
all four are Minor, so the default verdict on each is "park was correct" unless you find otherwise.
**Every line number in this file was re-verified against HEAD on 2026-10-14**, after Tasks 19-21 inserted
lines into most of the cited files — several items had gone stale and are marked in place. Treat the numbers
as current, not as written-at-the-time.

---

## 1. `test/cruise_test.dart:690` is entailed by `:689` plus the fixture

Parked during Task 11's fix round 1 (ledger :667). Ruled: park, do not fix.

**Line numbers re-verified at Task 22's pre-flight.** This item was written as `:660`/`:659`; Task 20's
fix round inserted a 250 EN turn test at `:496-524`, i.e. above both, so at HEAD the pair is
`expect(rec1!.id, isNot(rec0.id));` at **`:689`** and
`expect(reloaded.stateOf(rec1.id), isNot(DiscoveryState.explored));` at **`:690`**, in the test
`'is never a planet that has already been explored'` (`:674`). The claim is unchanged.

It is a **redundant** assertion, not a **vacuous** one — `:689` genuinely pins the explored guard,
so the test pins what its name claims; `:690` merely restates a consequence of it. It cannot
produce a false pass or a false failure.

**Cost if the ruling is wrong:** one assertion that would never fail on its own, in a test that is
otherwise correctly pinned.

## 2. Duplicated test boot helpers

Task 9, Minor #4 (ledger :453). `_boot` / `_setEnergy` / `_setDormant` in the new test file
duplicate `test/fuel_out_test.dart:22-42`. Parked: Flutter tests in this repo each carry their own
boot helpers; sharing them would need a test-support library the project does not have, and
introducing one is out of scope for this plan.

**Cost if the ruling is wrong:** three nine-line helpers drift between two files.

## 3. `launchToStar`'s ordering is unpinned — parked permanently

Task 9, F5 (ledger :582, :602). Nothing pins that the dormancy guard precedes the `dist < 0.5` →
`alreadyHere` branch. Pinning it needs a fixture that parks the ship within 0.5 ly of a star —
more machinery than the ordering is worth. The placement stands on determinism: it keeps
`'a star launch is refused the same way'` independent of where the exhausted drift ends.

**Cost if the ruling is wrong:** a future reorder of the two guards goes unnoticed by tests.

## 4. `pumpAndSettle` never settles on any screen carrying a starfield

Task 11 (ledger :767). `starfield.dart:97` is `)..repeat();` with no guard on `scrollSpeed`, and
`HomeShell` mounts all four pages in an `IndexedStack`, so the animation is live on every screen.
This is a **plan-level** trap: several tasks' brief-supplied test helpers used `pumpAndSettle` and
each had to be replaced with bounded pumps. Task 16's pre-flight caught the last two instances.

**Question for the final reviewer:** is any `pumpAndSettle` left in any test the plan added, or in
any helper those tests call? A single survivor is a test that times out.

**Answered by the controller, 2026-10-14 — the hazard does not materialise, and the premise stands.**
`grep -rn pumpAndSettle starward/test/` finds seven calls, in four files: `fuel_out_test.dart`
(`:396`, `:414`, `:425`), `braking_test.dart` (`:574`), `drift_report_test.dart` (`:452`, `:524`) and
`details_launch_test.dart` (`:47`). **Every one of those four files predates this plan** — added
10-10 16:39, 10-12 20:06, 10-12 21:48 and 10-13 18:19, against a plan that begins 10-14 11:47 — so no
`pumpAndSettle` survives in any file this plan created. The pre-existing ones are safe for a reason
worth naming: they mount narrow trees, not `HomeShell`. `braking_test.dart`'s `open()` helper wraps a
bare `MaterialApp(home: Scaffold(...))`, and the app-wide starfield is mounted at `lib/app.dart:65`,
not in `Scaffold` — which is also why the premise in this item is correct rather than overstated:
`StarfieldBackground` does call `repeat()` unconditionally in `initState`
(`starfield.dart:94-97`), so any tree that does mount it cannot settle. That no survivor mounts one
is **proven, not assumed**: a single `pumpAndSettle` over a live starfield never settles, and the
suite is green in ~17 s. Treat this item as closed; the remaining call sites are outside this plan's
files and outside its remit.

## 5. Task 15 pre-flight #8 — clamp bounds throw on a tiny viewport

Ledger :1416. The clamp is `at.dy.clamp(74.0, size.height - 132.0)` and
`at.dx.clamp(26.0, size.width - 26.0)`, which throw when the upper bound is below the lower one, i.e.
when `size.height < 206` or `size.width < 52` — the same hazard `camera3d.dart:270-272` documents for
the zoom clamp. Ruled: **leave** — not reachable on any phone-sized canvas and no test mounts the
painter.

*Location corrected 2026-10-14:* this item originally named `hudMarkerPoint` for that clamp. Task 19
extracted it into `clampHudPoint` (`cockpit_hud.dart:105-111`), which `hudMarkerPoint`'s callers and
the triangle both go through. The claim is unchanged and still true; only the function name moved.

**Cost if the ruling is wrong:** a crash in a layout the game never produces.

## 6. `'360°'` rounding artifact

Task 15 (ledger :1669). A bearing in `[359.5, 360)` renders `'360°'` rather than `'0°'` — a
rounding artifact of `toStringAsFixed(0)`, **pre-existing in the brief's original code** and not
caused by any fix round.

**Question for the final reviewer:** does the project's copy conventions make `'360°'` wrong
enough to matter, or is it a cosmetic edge the heading readout can carry?

## 7. The concurrent-session `test/` contamination hazard

Earlier in the plan, `starward/test/zz_color_probe_test.dart` appeared mid-round, written by a
different Claude session working in the same checkout. It was recorded as a hazard because a stray
file in `test/` inflates any full-suite count, which is the evidence every task review relies on.

**Question for the final reviewer:** confirm the file is gone and that the final suite count is
attributable entirely to this plan's work.

**Answered by the controller, 2026-10-14.** Gone: `git ls-files starward/test/` lists 32 files and
none matching `probe` or `zz_`, and `git status --porcelain starward/test/` shows no untracked file.
On attribution, the honest form of the claim: the count is **335** with the suite green, and no
untracked file exists in `test/` to inflate it. What this does *not* establish is that every one of
the 335 belongs to this plan — the plan also edited pre-existing files (`braking_test.dart`,
`fuel_out_test.dart` and others), so the count is "everything in the suite", not "this plan's tests".
Every task's report states the count it saw, so a regression in the total would have been visible
task-by-task. Treat the file as gone and the count as clean; do not re-derive the total.

## 8. Two premise-corrections the plan's own text still carries

Both were caught by reviewers **probing** a premise rather than reading it. Neither has been
corrected in the plan document, because the plan is the record of what was argued, not what
shipped — but the final reviewer should confirm nothing in **shipped code or comments** repeats
either false premise.

- **Task 16 pre-flight #2 (ledger :1534):** the claim that test 4's 座舱 tap is swallowed by the
  fuel-out sheet's barrier is **false**. The reviewer removed `await c.acknowledgeDriftReport()`
  and the test still passed, 13/13 (with a hit-test warning). The barrier swallows the *earlier*
  `find.text('星图')` tap inside `_pumpStarMap`. The call was kept for the warning and the timing
  reliance; the comment was corrected in Task 16's fix round 1.
- **Task 16 pre-flight #7 (ledger, same table):** test 3's "`(40, 0, 0)` … a 180° turn" is only
  approximately true — the spawn is within 0.9 ly of the origin and `_aimCockpitAtOrigin` flattens
  the pitch, so the turn is **179.86°**. The pinned `200 EN` still holds (`round(200·sin(θ/2))`
  stays 200 down to θ ≈ 171.9°).

---

## Already verified — do not re-derive

- Task 15's removal of the two `vec3.dart` imports was **required**, not cosmetic:
  `unnecessary_import` is live via `analysis_options.yaml` → `flutter_lints` →
  `lints/recommended.yaml`. Confirmed empirically both ways by the reviewer.
- Task 15's pinned projection numbers: `focal 692.8203230275511`; `(0,0,100) → (200,400)`;
  `(10,0,100) → 130.7179676972449`; `(−10,0,100) → 269.2820323027551`; depth-200 →
  `234.64101615137756`.
- Task 16's probes: unscoped `find.text('修正航向')` while cruising returns **1**, not 2
  (`skipOffstage: false` returns 2); empty marker list → fail at `:291`; dropping the painter →
  fail; placeholder `'—  —'` → fail at `:277`; mis-priced turn → fail at `:325`; angle **179.86°**,
  cost **200**, braking **100**, test 4 energy **95**.
- Character claims: placeholder is **U+2014 EM DASH**, elevation sign is **U+2212 MINUS SIGN**, and
  no bar `Text` contains an em dash.
- `Vec3` has **no `operator ==`**, so any equality assertion on it is an identity check — its
  constructor is `const`, so two identical `const Vec3(...)` expressions canonicalise to one
  instance. This is why `shouldRepaint` compares fields rather than the vector.
- `Camera3D.project` culls at `camZ <= _near (1.0)` and returns a hidden point whose `screen` is
  `Offset.zero` — so an unguarded hidden marker would be drawn in the **top-left corner**, not
  mirrored to the wrong side.
- Carried observation B (offstage consumption of `cockpitRequested`) is **CLOSED**: Task 16 adds no
  producer; the only caller remains `journey_page.dart:210`, which switches to tab 0 in the same
  handler.
- The `_steerFromCockpit` navigation gap is **CLOSED** by Task 14's cockpit-label assertion.

## 9. The cockpit's 点火巡航 button is rendered where ignition refuses for two more reasons

`_HeadingBar` renders 点火巡航 whenever the ship is not dormant and has no momentum, but
`igniteCruise` also refuses with `alreadyHere` when `!_player.inDeepSpace` and with
`alreadyTraveling` when `isTraveling` (`game_controller.dart:1306-1308`). So the button is offered
while docked at a planet, and possibly mid-voyage, and answers with a refusal snackbar.

**Why it is not fixed:** the third refusal — `insufficientEnergy` — *is* fixed in Task 20, because
the state that trips it is reachable through the deliberately lenient `activate()` and because an
energy gate is what Task 20 is about. These two are different: gating them changes which buttons the
cockpit *shows*, not just which are disabled. §5.3's table scopes its row to 「静止（深空）」 and §1
scopes the whole feature to deep space, so whether the button should be hidden, disabled, or
replaced by 「停靠中」 elsewhere is a product decision the plan has no authority to make.

**Where to point the final review:** `galaxy_map_3d_page.dart`, `_HeadingBar`'s `!moving` branch,
against `igniteCruise`'s full guard list. Note that `journey_page.dart`'s `_DriftDock` 点火巡航 is
*not* affected — its `onPressed` is `_steerFromCockpit`, which only navigates to the cockpit, so the
refusal site is the cockpit button this item is about.

## 10. The cockpit buttons' disabled colours are asserted nowhere

Task 20's review, Minor. `_HudButton` renders the disabled detail in `StarColors.danger` and the icon
and label in `StarColors.faint`. **Line numbers re-verified at Task 22's pre-flight; Tasks 19-21 all
inserted lines above this class, so the numbers this item was written with are stale.** At HEAD the
class opens at `galaxy_map_3d_page.dart:1363`, the three colours are at `:1399` (icon), `:1403` (label)
and `:1409` (detail), and the dead-tap line is `onTap: on ? onPressed : null` at `:1391`. The brief
supplies those colours and no test requires any of them, so a later change to any of the three would go
unnoticed.

**Why it is parked:** this is coverage breadth, not a defect — the colours are a copy choice, and the
plan pins *numbers and behaviour*, not palettes. The one thing Task 20 does pin is that a disabled
button does not fire: `onTap: on ? onPressed : null` (`:1391`) with test 1's
`find.byType(AlertDialog), findsNothing` and test 4's `find.text('耗尽后停下'), findsNothing` as the
discriminating assertions. That is the behaviour; the shades are taste.

**Where to point the final review:** whether the project's existing tests assert any colour at all. If
they do, this is an inconsistency worth a line; if they do not, the park is right and no further work
is owed.

## 11. The brake hint is now withheld in one state it used to be shown in

Task 20's review, Important — **fixed in round 1 (`48247c2`), listed here because the *behaviour
change* is the part a whole-branch reviewer should see, not the comment.**

`showBrakeHint` is now `turningIsDearer && controller.canBrake` (`galaxy_map_3d_page.dart:1246`, with
`turningIsDearer` at `:1214` — re-verified at Task 22's pre-flight, since Tasks 19-21 inserted lines
above both), where before Task 20 it was `turningIsDearer` alone. The state that distinguishes them: a
cruising ship at 250 EN that takes a 180° turn lands on `energyBalance == 50` while still cruising and
not dormant, so `canBrake` is `50 >= 100` = false and the hint is withheld. Pinned by a controller-level
test in `cruise_test.dart`.

**The ruling, for the final reviewer to judge:** withholding is right, because `canBrake` is a real
guard (`game_controller.dart:1279` settles the leg's burn and returns *without* braking), so the old
code offered a tappable hint that would spend the player's remaining energy and do nothing else — and
the hint's text quotes the brake's price, which in that state the ship cannot pay. **Cost if the ruling
is wrong:** the player loses the hint that tells them stopping is cheaper than a >60° turn, in the one
state where they cannot afford to stop anyway.

**Where to point the final review:** `galaxy_map_3d_page.dart:1246` against
`game_controller.dart:1279` and `:983`, and the new test in `cruise_test.dart`. The comment above the
line (`:1230-1245`) was rewritten in round 1 after the original version was found to claim the conjunct
was "always true while cruising" — which the 250 EN turn falsifies.

## 12. `_EnginePanel`'s mount snippet is duplicated verbatim in both docks

Task 21's review, Minor. `journey_page.dart:742-745` and `:953-956` are the same three lines —
`if (controller.isDormant) ...<Widget>[SizedBox(height: 14), _EnginePanel(...)]` — once in `_DriftDock`,
once in `_CoastDock`. **Plan-mandated:** the brief prescribes that exact snippet for both mount sites.

**Why it is parked:** it is presentation wiring, not a logic block — three lines naming a widget and a
constant — and the thing §9.3 asks for (one activation *component*, not the same entry written twice) is
genuinely achieved: `_EnginePanel` is shared, and the two docks differ only in which `controller` and
callback they hand it. The pattern this file uses for "shared by two callers" is a widget, and the
duplication is the *call*, not the component. Extracting a three-line mount into a fourth widget would add
a layer to save two lines.

**Where to point the final review:** whether the project's convention is to extract mount sites as well as
components. If it is, this is a real inconsistency; if it is not, the park is right.

## 13. `_EnginePanel`'s doc says its gate "matches" `activate()`'s guard — the two read different fields

Task 21's review, Minor. The doc (`journey_page.dart:759-761`) reads: *"The gate is `energy >=
activationCost`, matching `activate()`'s own guard (`game_controller.dart:1218` is `if
(_player.energyBalance < cost)`), so the panel is never short of a fee the controller would have
accepted."* The panel gates on **`controller.energy`** (`:771`, the live getter, which subtracts the
unbooked burn and floors at 0 — `game_controller.dart:456-464`); the controller gates on the **raw**
`_player.energyBalance` (`:1218`). The sentence names one field and then quotes a guard on the other.

**Ruled: the claim is true in every reachable state, so the sentence is under-justified rather than
false — park it, and do not add it to Task 22.** Derivation: a dormant ship is never cruising (dormancy
is reached by `halt`, which stops the ship, or by `coast`, which turns the engine off and keeps the
momentum), so `_cruiseBurnNow()` is zero and the getter's second branch reduces to
`max(0, energyBalance)`; a dormant ship also has no in-progress journey, so the first branch is dead.
Hence `energy == max(0, energyBalance)` while dormant, and the two gates agree on both signs of
`energyBalance` — including the `energyBalance < 0` case, where both compare `0 >= 5` = false. The
reviewer reached the same conclusion from the safety direction (`live <= raw`, so panel-enabled ⟹
controller-accepts) and could not construct a counterexample either.

**Cost if the ruling is wrong:** the doc's word "matching" is read as a guarantee it does not derive, and a
future change that made a dormant ship cruise would break the equality silently. The fix, if the final
reviewer wants it, is comment-only: say the gate is *conservative against* `activate()`'s guard and give
the reason (a dormant ship is not cruising, so no burn is unbooked), not that it matches.

**Where to point the final review:** `journey_page.dart:759-761` against `game_controller.dart:456-464`
and `:1218`. **The same overstatement is inherited from Task 20's cockpit** (`galaxy_map_3d_page.dart`
around `:1216-1220`), which the brief supplied — so if this is judged worth a sentence, it is worth one in
both places, and that makes it a whole-branch decision rather than a Task 21 or Task 22 fix.

---

## 14. Invariant 2's general clause is one notch broader than the mechanism it describes

**Where:** `docs/superpowers/plans/2026-10-14-starward-free-cruise.md`, invariant 2 in "The three
invariants, verbatim" (near `:46`), as rewritten by the final fix round's residual commit `61b6110`.

**What it says:** "The exhaustion rule bills at most `balance − cruiseReserve`, so for **both** policies a
cruise that runs out of budget stops with the reserve intact — a ship that has flown to exhaustion without
turning still holds the 100 EN brake."

**The nuance.** Read "runs out of budget" as *the burn consumes the allowance*, and the clause is exactly
true: `_reconcileCruise` (`game_controller.dart:1141`) books `balance − cruiseReserve` when positive, so the
tank lands on the reserve. Read it as *the budget is ≤ 0*, and the turn case falsifies it — after
`correctHeading` spends into the reserve, `_cruiseExhaustTime` (`:1087`) takes its `budget <= 0` branch and
returns `driftStartedAt`, `_reconcileCruise` books nothing (`burned <= 0`), and the ship stops at 50 EN, not
with the reserve intact. The sentence's own illustration carries the narrower, correct scope ("without
turning") and the following sentence names the turn case outright.

**Ruled: park, no further dispatch — the sentence is adequately scoped, not a false universal.** The clause's
own first sentence fixes the mechanism it is describing, and unlike the wording `61b6110` replaced — which
was false under *every* reading — this one is false only under a strained reading that the next two clauses
correct. The branch's standard is that a claim must be re-derivable and true; it does not require every
sentence to survive every parse. A third dispatch for a four-word prose polish would be exactly the churn
the one-fix-dispatch rule exists to prevent, and the reviewer's seat was already spent on the diff that
contains it.

**Cost if the ruling is wrong:** a reader takes "runs out of budget" to include the turn case and expects the
reserve to survive; the very next sentence corrects them. The cheap fix, if anyone wants it: "a cruise that
runs out of budget **by burning** stops with the reserve intact".

---

## 15. The cockpit's brake snackbar can claim a stop that did not happen

**Raised by:** the scoped re-review over `e945ede..61b6110`, as an out-of-scope observation (it is
pre-existing and untouched by that diff).

**What I verified:** `_brakeFromCockpit` (`galaxy_map_3d_page.dart:274-279`) is

```dart
Future<void> _brakeFromCockpit() async {
  await _c.stopShip();
  if (!mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('已制动停下')));
}
```

It shows `已制动停下` unconditionally. `stopShip` (`game_controller.dart:1279-1297`) settles the leg's burn
**first** and only then gates on `canBrake` (`:1289`), returning without braking when the settled tank is
below 100 — and it returns `Future<void>`, so no caller *can* branch on the outcome. The sibling handler one
screen up does exactly that for the turn: `final turned = await _c.correctHeading(heading);` then
`turned ? '航向已修正（$cost EN）' : '能量不足，无法修正航向'` (`:267-271`). So the asymmetry is in the
cockpit's own code, and the brake path is the one that cannot express its failure.

**Reachability — the same narrow window as deferred item 14's neighbour, and no wider as far as I checked.**
The snackbar lies when `canBrake` is true at render and false after the settle, which needs the burn to have
carried the tank past the reserve before a tick reconciled — the ≥ ~7.5 s gap derived for fix round 2. I did
**not** verify whether the cockpit's brake button is gated on `hasMomentum` / `canBrake`; if it is not, the
parked and already-dormant cases reach the lying snackbar too and this item is materially bigger than the
window suggests. That check is the first thing to do if anyone picks this up.

**Ruled: park, and do not fold it into fix round 2.** Fix round 2 is prose-only (three comment/plan sites),
while this is a behaviour change in a UI file — folding it in would put an untested behaviour edit behind a
documentation review surface, and the review seat for that round is scoped to the prose. *Cost if wrong:* in
a narrow state a player is told the ship stopped when it did not, and the ship keeps cruising until the next
tick leaves it dormant; the fix is one `bool` return on `stopShip` plus a branch, or a `canBrake` re-read in
the handler.

---

## 16. The plan never states that the trap's severity depends on the fuel policy

`已知取舍 #2` records the trap and invariant 2 points at it, but neither says what the trap *costs*, and that
depends entirely on the policy:

- **`coast`:** the ship keeps its momentum, so `brakingCost` is 100 (`game_controller.dart:303-305`) and a
  tank below 100 fails `canBrake` (`:983`) **and** fails `_launchGate`'s lenient branch, which needs
  `available > braking` (`:1614`). The ship is stranded until it trains.
- **`halt`:** the exhaustion rule zeroes the velocity in the same `copyWith` that sets `engineDormant`
  (`:1175-1178`), so the ship is parked, `brakingCost` is 0, the brake is free, and any tank above the
  engine's 5 EN activation fee reopens the voyage gate.

Nothing false is written anywhere — that is why this is parked and not fixed. The mechanism is recorded
(`_reconcileCruise`'s own comment names the halt/coast velocity split) and the severity follows from
`canBrake`'s one-line definition, so a reader can derive it. What is missing is the derivation.

**Ruled: park, do not write it.** The obvious home is invariant 2, which has now been rewritten three times
because each of its sentences about what a stranded ship *can do* was true under one branch of this exact
switch and false under the other. Adding a fourth enumeration there — even a complete two-branch one — is
what the human partner ruled against when they chose "delete the consequence sentence" over patching it. The
cheap fix, if anyone wants it: one sentence in `已知取舍 #2`, e.g. "`halt` softens this — the exhaustion rule
parks the ship, so its brake costs nothing and the voyage gate reopens above the activation fee" — which is
true, and belongs with the trap rather than with the invariant. *Cost if wrong:* a reader who wants to know
whether a stranded ship is stuck reads one comment and one getter instead of one sentence.
