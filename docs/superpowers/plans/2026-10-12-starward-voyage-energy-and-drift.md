# Starward 航行能量与滑行 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把"出发时一次性扣费"改成"随航程实时燃烧燃料"，并让燃料烧完的飞船可以停下或滑行，滑行永远被约束在恒星密度足够的球壳内。

**Architecture:** 能量消耗变成**纯派生值**——出发时不扣任何能量，`GameController.energy` 每次读取时用 `Journey.burnedAt(now)` 从时间戳算出烧了多少。账只在航程**终止**那一刻落库（一条 `travelCost` 账目）。漂流（drift）成为一等状态：`PlayerState` 存 `driftVelocity` / `driftStartedAt`，位置由 `core/drift.dart` 的闭式函数算出（直线段 + 贴壳大圆），零速度时逐位退化为今天的静止深空。

**Tech Stack:** Flutter 3.47+ / Dart 3.13+，`shared_preferences`，`flutter_test`。无新增依赖。

**Spec:** `docs/superpowers/specs/2026-10-12-starward-voyage-energy-and-drift-design.md`

## Global Constraints

- 分层依赖方向：`lib/core` → `lib/data` → `lib/state` → `lib/ui`。UI 不直接读写存储，全部经 `GameController`。`lib/core/drift.dart` 只依赖 `lib/core/vec3.dart`，**不得** import `lib/data/`。
- **属性归属于拥有它的实体**：新增可调数值前先找宿主实体；`Balance` 只放跨实体经济调参（`initialEnergy` / `explorationReward`）。派生计算写成该实体的方法，不写成读全局常量的顶层函数。
- 模型一律不可变（`final` 字段 + `const` 构造），变更返回新实例；每个模型自带 `toJson()` / `fromJson()`。
- **存档结构变更优先做迁移，不要 bump `_saveKey`**（`starward.save.v2` 保持不变）。
- TDD：先写失败测试再实现。测试用 `FakeClock` + 固定 `math.Random(seed)` + `MemoryStorage`，绝不碰真实 prefs。
- 涉及数值的迁移要**钉住具体数字**（如标准引擎 2.5 EN/ly、`universeRadius == 3066`）。
- `flutter analyze` 必须报 `No issues found`；`flutter test` 必须全量通过。
- 标准引擎数值（`Engine.standard`：`energyPerLy: 2.5`、`travelSecondsPerLy: 37.5`、`minEnergyCost: 1`、`minTravelSeconds: 15`）与 `Balance.initialEnergy: 300` 不改。
- 每个 task 结束提交一次，commit message 用 conventional commits，并以 `Co-Authored-By: Claude Code <noreply@anthropic.com>` 结尾。

## 阶段与检查点

Spec §10 把工作分成四阶段。计划沿用它的依赖顺序，但把**漂移地基**提前成一个独立阶段——否则"滑行"这个选项会先以"停下"的形态发布一次，再在下一个阶段改掉。这样每个阶段结束都是一个真正可发布、可测试、不留半成品的检查点：

| 阶段 | Task | 内容 | 结束时玩家能看到什么 |
|---|---|---|---|
| **A 实时能量** | 1–3 | `Journey.burnedAt`、派生 `energy`、终止结账、`GameSave` 迁移 | 航行中能量逐秒递减，抵达时账本落一条 |
| **B 漂移地基** | 4–7 | `core/drift.dart`、`PlayerState` 漂流字段、`playerPosition3D`、`universeRadius`、附近兜底 | 无变化——速度恒为 0，行为逐位不变。这是纯结构准备 |
| **C 三选一 + 停下 + 滑行** | 8–11 | `FuelPolicy`、`onEmpty`、耗尽结算、出发对话框、滑行页 | 能量不够也能出发；烧干后停在原地或继续滑行 |
| **D 播报** | 12–14 | `DriftPath`、途经星系、`DriftReport`、离线补算、播报弹层 | 离线一周回来，收到一份"你滑了多远、路过哪些星系" |

阶段 B 刻意"没有可见变化"：它只是把漂流做成一等状态，而默认速度是零向量，所以出生、`abortJourney`、抵达恒星、抵达坐标这四条既有深空路径全部逐位不变（`driftPositionAt` 在 `velocity == 0` 时原样返回 `start`）。正因为这一阶段不改变任何行为，它的测试全是**不变量断言**而不是新行为断言。

## File Structure

**新建：**

| 文件 | 职责 |
|---|---|
| `lib/core/drift.dart` | 恒速漂流的闭式几何：位置求值 + 路径描述 + 最近接近 + 途经星系值对象（`DriftPath` / `ClosestApproach` / `PassedSystem` / `PassedSystems`）。纯 `Vec3` 数学，零依赖。 |
| `lib/data/models/drift_report.dart` | `DriftReportKind` / `DriftReport` 不可变模型（`PassedSystem` 复用 `core/drift.dart` 的那个，见上）。 |
| `lib/ui/journey/fuel_choice_dialog.dart` | 出发前的三选一对话框（能量不足以飞完全程时）。 |
| `lib/ui/journey/drift_report_sheet.dart` | 播报底部弹层，按 `DriftReportKind` 分两种文案。 |
| `test/real_time_energy_test.dart` | 阶段 1：实时燃烧、结账、迁移。 |
| `test/fuel_out_test.dart` | 阶段 2：耗尽点闭式、`halt`、`refuse` 默认。 |
| `test/drift_test.dart` | 阶段 3：`driftPositionAt` 纯数学。 |
| `test/coast_test.dart` | 阶段 3：滑行状态、边界、附近兜底。 |
| `test/drift_report_test.dart` | 阶段 4：途经星系、离线播报、反面不误报。 |

**修改：**

| 文件 | 变更 |
|---|---|
| `lib/data/models/journey.dart` | `burnedAt`、`fuelPolicy` 字段 + JSON。 |
| `lib/data/models/player_state.dart` | `driftVelocity` / `driftStartedAt` 字段 + JSON + `copyWith`。 |
| `lib/data/game_repository.dart` | `GameSave` 顶层 `energyModel: 2` + v2 迁移。 |
| `lib/data/universe.dart` | `universeRadius`、`nearestPlanets`、`passedSystemsAlong`。 |
| `lib/state/game_controller.dart` | 派生 `energy`、`_settleBurn`、`_settleTank`、`FuelPolicy`、`halt`、漂移位置、`_rebuildNearby` 节流与兜底、`pendingDriftReport`。 |
| `lib/ui/galaxy/planet_details_sheet.dart` | 出发按钮接入三选一。 |
| `lib/ui/galaxy3d/galaxy_map_3d_page.dart` | `launchToStar` 接入三选一。 |
| `lib/ui/journey/journey_page.dart` | ticker 条件放宽、滑行变体、`p_exhaust` 警告、播报弹层。 |
| `test/energy_test.dart` | 改写两条"出发即扣费"的断言。 |
| `test/ship_test.dart` | 改写 `the launch actually deducts the refitted cost`。 |
| `starward/README.md` / `starward/CLAUDE.md` | 阶段 1 与阶段 3 结束时补一段模型说明。 |

---

## 阶段 1 — 实时能量

### Task 1: `Journey.burnedAt` —— 已烧掉的燃料

**Files:**
- Modify: `starward/lib/data/models/journey.dart`（在 `remainingAt` 之后插入，约 :50）
- Test: `starward/test/real_time_energy_test.dart`（新建）

**Interfaces:**
- Consumes: 现有的 `Journey.progressAt(DateTime) -> double`、`Journey.energyCost`。
- Produces: `int Journey.burnedAt(DateTime now)` —— 从出发到 `now` 烧掉的 EN，`[0, energyCost]` 闭区间。

- [ ] **Step 1: 写失败测试**

新建 `starward/test/real_time_energy_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/models/journey.dart';

/// A voyage that departs 12:00 and arrives 12:10, quoting 100 EN.
Journey _tenMinuteVoyage() => Journey(
      id: 'jny-1',
      originPlanetId: 'a',
      destinationPlanetId: 'b',
      departure: DateTime(2026, 1, 1, 12),
      arrival: DateTime(2026, 1, 1, 12, 10),
      energyCost: 100,
      status: JourneyStatus.inProgress,
    );

DateTime _at(int minute) => DateTime(2026, 1, 1, 12, minute);

void main() {
  group('Journey.burnedAt', () {
    test('burns in proportion to distance covered', () {
      final j = _tenMinuteVoyage();
      expect(j.burnedAt(_at(0)), 0);
      expect(j.burnedAt(_at(2)), 20);
      expect(j.burnedAt(_at(5)), 50);
      expect(j.burnedAt(_at(10)), 100);
    });

    test('never over-burns past arrival', () {
      final j = _tenMinuteVoyage();
      // A voyage reconciled an hour late must not bill more than it quoted.
      expect(j.burnedAt(_at(70)), 100);
    });

    test('never burns before departure', () {
      final j = _tenMinuteVoyage();
      expect(j.burnedAt(DateTime(2026, 1, 1, 11, 30)), 0);
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd starward && flutter test test/real_time_energy_test.dart`
Expected: FAIL — `The method 'burnedAt' isn't defined for the type 'Journey'`（编译错误即失败）。

- [ ] **Step 3: 最小实现**

在 `starward/lib/data/models/journey.dart` 的 `remainingAt` 之后插入：

```dart
  /// Energy burned by [now], in EN — proportional to the distance covered.
  ///
  /// This is the whole of "real-time consumption": nothing is deducted at
  /// launch, the burn is re-derived from the timestamps every time it is asked
  /// for, so it survives the app being backgrounded or killed exactly like
  /// [progressAt] does. `progressAt` is clamped to [0, 1], so the result is
  /// always within `[0, energyCost]`.
  int burnedAt(DateTime now) => (energyCost * progressAt(now)).round();
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd starward && flutter test test/real_time_energy_test.dart`
Expected: PASS（3 tests）。

- [ ] **Step 5: 提交**

```bash
cd starward && git add lib/data/models/journey.dart test/real_time_energy_test.dart
git commit -m "$(cat <<'EOF'
feat(starward): derive voyage fuel burn from the clock

Adds Journey.burnedAt, the timestamp-derived burn that replaces the
up-front deduction. Progress is already derived from departure/arrival,
so the burn is too — no running timer, no stored counter.

Co-Authored-By: Claude Code <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: 派生 `energy` + 终止时结账

把能量账从"出发时扣"整体搬到"终止时结"。改完 `GameController.energy` 在航行途中递减，抵达时才出现账目。

**Files:**
- Modify: `starward/lib/state/game_controller.dart`
  - `energy` getter：在 `playerPosition3D` 附近（约 :206）新增
  - `_settleBurn`：在 `// --- Energy helpers ---` 段（约 :661）新增
  - `_applyArrival`（:297）：顶部加一行结账
  - `abortJourney`（:492）：加一行结账
  - `returnToOrigin`（:519）：报价的付款判定改用结账后的余额，付得起才结账
  - `launchJourney`（:379）：删掉 `_spendEnergy(cost, ...)`
  - `launchToStar`（:416）：删掉 `_spendEnergy(cost, ...)`
- Modify: `starward/test/energy_test.dart`（改写 :33 与 :96 两条）
- Modify: `starward/test/ship_test.dart`（改写 :150 `the launch actually deducts the refitted cost`）
- Modify: `starward/test/return_to_origin_test.dart`（追加 3f-ii 的回归测试）
- Test: `starward/test/real_time_energy_test.dart`（追加）

**Interfaces:**
- Consumes: `Journey.burnedAt(DateTime) -> int`（Task 1）；现有 `EnergyTxType.travelCost`、`EnergyTransaction`、`_newId`、`_persist`。
- Produces:
  - `int GameController.energy` —— 实时能量。航程进行中 = `energyBalance - burnedAt(now)`（下限 0），否则 = `energyBalance`。
  - `int GameController._settleBurn(Journey j, DateTime now)` —— 私有，把 [j] 截至 [now] 的燃烧写进余额与账本，返回烧掉的量。

- [ ] **Step 1: 写失败测试**

在 `starward/test/real_time_energy_test.dart` 追加（保留 Task 1 的内容，补上这些 import 与 helper）：

```dart
// --- 追加到文件顶部的 import ---
// import 'dart:math' as math;
// import 'package:starward/data/game_repository.dart';
// import 'package:starward/data/models/planet.dart';
// import 'package:starward/data/storage/storage_backend.dart';
// import 'package:starward/state/game_controller.dart';

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
    random: math.Random(2),
  );
  await c.init();
  return c;
}

/// The closest planet we could launch to — the cheapest hop on offer.
Planet _nearest(GameController c) => c.planets
    .where((p) => p.id != c.currentPlanetId)
    .reduce((a, b) => c.distanceTo(a) <= c.distanceTo(b) ? a : b);

// --- 追加到 main() 里的新 group ---

  group('real-time energy', () {
    test('launch burns nothing; the burn accrues with progress', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final before = c.energy;
      final target = _nearest(c);
      final cost = c.energyCostTo(target);
      final total = c.travelDurationTo(target);

      await c.launchJourney(target);

      // Not a drop has burned at t=0.
      expect(c.energy, before);
      expect(c.energyLedger, isEmpty, reason: 'nothing is booked at launch');

      // Halfway: exactly half the quoted cost is gone.
      clock.advance(Duration(milliseconds: total.inMilliseconds ~/ 2));
      expect(c.energy, before - (cost * 0.5).round());

      // Arrival settles the whole quote.
      clock.advance(total);
      c.tick();
      expect(c.energy, before - cost);
      expect(c.energyLedger.single.amount, -cost);
      expect(c.energyLedger.single.type, EnergyTxType.travelCost);
    });

    test('an in-flight reading survives a kill and restart', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c1 = await _boot(clock, storage: storage);
      final target = _nearest(c1);
      final cost = c1.energyCostTo(target);
      final total = c1.travelDurationTo(target);
      final balance = c1.energy;
      await c1.launchJourney(target);

      clock.advance(Duration(milliseconds: total.inMilliseconds ~/ 4));
      final live = c1.energy;
      expect(live, closeTo(balance - cost * 0.25, 1),
          reason: 'a quarter of the way is a quarter of the fuel');

      // "Kill the process": a brand-new controller reads the same save.
      final c2 = await _boot(clock, storage: storage);
      expect(c2.energy, live,
          reason: 'the reading follows the clock, not the process uptime');
      expect(c2.activeJourney!.energyCost, cost, reason: 'the quote is stable');
      expect(c2.energyLedger, isEmpty,
          reason: 'nothing is booked until the voyage ends');
    });

    test('a top-up mid-voyage lands in the live reading', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final target = _nearest(c);
      final cost = c.energyCostTo(target);
      final total = c.travelDurationTo(target);
      final balance = c.energy;
      await c.launchJourney(target);

      clock.advance(Duration(milliseconds: total.inMilliseconds ~/ 2));
      final halfway = c.energy;
      expect(halfway, closeTo(balance - cost * 0.5, 1));

      // Training has no position or energy precondition, so a course can be
      // finished mid-flight. The reward goes straight onto the balance — which
      // is what makes a doomed voyage rescuable. Task 8 pins that consequence;
      // here we only pin that the live reading moves.
      final session = await c.startCourse('walk');
      await c.completeCourse(session.id, 40);
      expect(c.energy, halfway + 40,
          reason: 'a top-up lands straight in the live reading');

      clock.advance(total);
      c.tick();
      expect(c.currentPlanetId, target.id, reason: 'the trip still completes');
      expect(c.energy, balance + 40 - cost,
          reason: 'arrival books exactly the quote, top-up included');
    });

    test('aborting books only what was actually burned', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final before = c.energy;
      final target = _nearest(c);
      final cost = c.energyCostTo(target);
      final total = c.travelDurationTo(target);
      await c.launchJourney(target);

      clock.advance(Duration(milliseconds: total.inMilliseconds ~/ 4));
      await c.abortJourney();

      final burned = (cost * 0.25).round();
      expect(c.energy, before - burned, reason: 'unburned fuel never left');
      expect(c.energyLedger.single.amount, -burned);
      expect(c.inDeepSpace, isTrue);
    });

    test('turning back settles the outbound leg before quoting the return',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final before = c.energy;
      final target = _nearest(c);
      final cost = c.energyCostTo(target);
      final total = c.travelDurationTo(target);
      await c.launchJourney(target);

      clock.advance(Duration(milliseconds: total.inMilliseconds ~/ 2));
      await c.returnToOrigin();

      final burned = (cost * 0.5).round();
      final back = c.activeJourney!;
      // Exactly two ledger entries are possible at this point: the settled
      // outbound burn, and the return leg's own quote (settled on arrival).
      expect(c.energy, before - burned, reason: 'only the outbound leg burned');
      expect(c.energyLedger.map((t) => t.amount).toList(), <int>[-burned]);
      expect(back.energyCost, greaterThan(0));

      clock.advance(back.totalDuration + const Duration(seconds: 1));
      c.tick();
      expect(c.energy, before - burned - back.energyCost);
      expect(c.energyLedger.length, 2);
    });
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd starward && flutter test test/real_time_energy_test.dart`
Expected: FAIL — `launch burns nothing` 在 `expect(c.energy, before)` 处失败（现在是 `before - cost`），并且 `energyLedger` 非空。

- [ ] **Step 3: 实现**

**3a.** 在 `starward/lib/state/game_controller.dart` 的 `playerPosition3D` 之后（约 :206）插入：

```dart
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
```

**3b.** 在 `// --- Energy helpers ---` 段、`_spendEnergy` 之前（约 :661）插入：

```dart
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
```

**3c.** `_applyArrival(Journey journey)` 第一行加结账（此时 `journey.status` 仍是 `inProgress`）：

```dart
  void _applyArrival(Journey journey) {
    // The voyage ends here, so the whole quote lands now.
    _settleBurn(journey, _now());
    final dest = journey.destinationPlanetId;
```

**3d.** `launchJourney` 删掉 `_spendEnergy(cost, EnergyTxType.travelCost, journey.id);` 这一行（`_activeJourney = journey;` 之后那行）。`launchToStar` 同样删掉它。两处的 `if (_player.energyBalance < cost) return LaunchResult.insufficientEnergy;` 守卫**保留不变**。

**3e.** `abortJourney` 改为：

```dart
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
```

**3f.** `returnToOrigin` 在拿到 `currentPos` / `originPos` 之后、报价之前结账：

```dart
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
```

（`_settleBurn` 把余额夹在 `>= 0`，而 `cost >= minEnergyCost >= 1`，所以余额被烧穿时 `balance - burned < cost` 与 `max(0, balance - burned) < cost` 同真——这条守卫的行为与"先结账再判断"逐位相同，只是付不起时不再留下那笔孤儿账目。）

并把该方法末尾的 `_spendEnergy(cost, EnergyTxType.travelCost, ret.id);` 删掉——返程段是一条普通 `Journey`，抵达时由 `_applyArrival` 结账。

**3f-ii.** 给这条守卫钉一条回归测试。这个 bug 之所以能溜过去，正是因为既有测试里余额总是远大于报价；追加到 `starward/test/return_to_origin_test.dart` 末尾（并在文件顶部补 `import 'package:starward/data/models/engine.dart';`——测试体里的 `Engine(...)` 需要它；**不要**加 `energy_transaction.dart`，测试体只读 `EnergyTransaction` 的字段、从不写出类型名，加了就是 `unused_import`）：

```dart
  group('返航付不起时', () {
    test('does not book the outbound burn, and never books it twice', () async {
      final clock = FakeClock(DateTime(2026, 1, 1, 12));
      final c = await _boot(clock);
      final origin = await _dockAtPlanet(c, clock);

      final target = _farthestPlanet(c, origin.id);
      expect(await c.launchJourney(target), LaunchResult.success);
      final voyage = c.activeJourney!;
      final outbound = voyage.energyCost;

      clock.advance(voyage.totalDuration ~/ 2);

      // A greedy refit prices the way home far beyond the remaining balance.
      await c.installEngine(const Engine(
        id: 'test.greedy',
        name: '测试引擎',
        energyPerLy: 1000,
        travelSecondsPerLy: 37.5,
        minEnergyCost: 1,
        minTravelSeconds: 15,
      ));

      expect(await c.returnToOrigin(), LaunchResult.insufficientEnergy);

      // The refusal must leave the voyage exactly as it was.
      expect(c.activeJourney!.id, voyage.id, reason: 'still the outbound voyage');
      expect(c.activeJourney!.status, JourneyStatus.inProgress);
      expect(
        c.energyLedger.where((t) => t.relatedObjectId == voyage.id),
        isEmpty,
        reason: 'a refused return must not settle the outbound leg',
      );

      // …and flying it out books that leg once, not twice.
      clock.advance(voyage.totalDuration);
      c.tick();
      expect(c.currentPlanetId, target.id);
      final booked = c.energyLedger
          .where((t) => t.relatedObjectId == voyage.id)
          .toList();
      expect(booked.length, 1, reason: 'booked exactly once');
      expect(booked.single.amount, -outbound);
    });
  });
```

**3g.** 删掉 `_spendEnergy` 整个方法（`// --- Energy helpers ---` 段，约 :663）。

它原来只有三个调用点（`launchJourney` :398、`launchToStar` :438、`returnToOrigin` :556），全在 3d 和 3f 里删掉了。`_settleBurn` 自己写余额和账目，不复用它。留着会触发 `unused_element`，`flutter analyze` 就不再是 `No issues found`。

**3h.** 改写 `starward/test/energy_test.dart` 的两条测试：

第 33 行那条整体替换为：

```dart
    test('launch quotes from the engine; the burn settles on arrival', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final before = c.energy;
      final target = _nearest(c);
      final cost = c.energyCostTo(target);
      final total = c.travelDurationTo(target);

      await c.launchJourney(target);
      expect(c.energy, before, reason: 'nothing burns at t=0');
      // Cost scales linearly with distance, floored so a hop is never free —
      // and it comes off the ship's fitted engine, not a global table.
      expect(cost, c.ship.engine.energyCostFor(c.distanceTo(target)));

      clock.advance(total + const Duration(seconds: 1));
      c.tick();
      expect(c.energy, before - cost);
    });
```

第 96 行那条整体替换为：

```dart
    test('every balance change leaves a ledger entry', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final target = _nearest(c);
      final cost = c.energyCostTo(target);
      final total = c.travelDurationTo(target);
      await c.launchJourney(target);
      expect(c.energyLedger, isEmpty, reason: 'booked at the end, not the start');

      clock.advance(total + const Duration(seconds: 1));
      c.tick();
      expect(c.energyLedger.first.amount, -cost);
      expect(c.energyLedger.first.type, EnergyTxType.travelCost);
    });
```

（这条需要 `import 'package:starward/data/models/energy_transaction.dart';`，加到 `energy_test.dart` 顶部。）

**3i.** 改写 `starward/test/ship_test.dart` 的 `the launch actually deducts the refitted cost`：

```dart
    test('the voyage bills the refitted cost, settled on arrival', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await c.installEngine(_thrifty);
      final target = _nearest(c);
      final before = c.energy;
      final cost = c.energyCostTo(target);
      final total = c.travelDurationTo(target);

      await c.launchJourney(target);
      expect(c.energy, before, reason: 'nothing burns at t=0');

      clock.advance(total + const Duration(seconds: 1));
      c.tick();
      expect(c.energy, before - cost);
      expect(c.energyLedger.first.amount, -cost);
    });
```

- [ ] **Step 4: 跑全量测试确认通过**

Run: `cd starward && flutter analyze && flutter test`
Expected: `No issues found`；全部测试通过。特别确认 `test/flight_panel_test.dart`、`test/return_to_origin_test.dart`、`test/deep_space_start_test.dart` 仍然通过——它们现在**更容易**通过，因为出发不再预付全额。

- [ ] **Step 5: 更新 README 的模型说明**

`starward/README.md` 的「航行状态逻辑」一节，把"能量在校验全部通过后才原子扣除"改成：

```markdown
因此退出 App、进入后台、甚至被系统杀死后重启，航行都会继续并在重新打开时恢复正确状态（`GameController.init()` 会在加载存档后调用 `_reconcileJourney()` 补算抵达）。同一时间最多一条进行中的航行。

**能量随航程实时燃烧**：出发时不扣任何能量，`GameController.energy` 每次读取时用
`Journey.burnedAt(now)` 从时间戳算出已烧掉的部分（余额减掉它，下限 0）。账只在航程
**终止**那一刻落库——抵达结算全额，中途停止结算已烧部分。所以燃料没烧掉之前从未离开
玩家账户，也就不存在"退款"这个概念。
```

- [ ] **Step 6: 提交**

```bash
cd starward && git add lib/state/game_controller.dart test/energy_test.dart test/ship_test.dart test/return_to_origin_test.dart test/real_time_energy_test.dart README.md
git commit -m "$(cat <<'EOF'
feat(starward): burn voyage fuel in real time, settle on termination

Energy is no longer deducted at launch. GameController.energy derives
the live reading from Journey.burnedAt, and the ledger entry is written
when the voyage ends — full cost on arrival, burned-so-far on abort,
and the outbound leg settles before the return leg is quoted.

A one-shot deduction and a real-time burn cannot coexist: reconstructing
the live value from a pre-deducted balance forces a negative balance
whenever the ship cannot afford the whole trip, which is exactly the
case this model has to support.

Co-Authored-By: Claude Code <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `GameSave.energyModel` 迁移

v2 存档里正在进行的航程在出发时已经扣过 `energyCost`。新模型要求 `energyBalance` 表示"还没烧掉的总量"，所以加载时必须把那笔加回来，否则玩家被收两次费。

**Files:**
- Modify: `starward/lib/data/game_repository.dart:40-78`（`GameSave.toJson` / `fromJson`）
- Test: `starward/test/real_time_energy_test.dart`（追加）

**Interfaces:**
- Consumes: `Journey.burnedAt`（Task 1）、`GameController.energy`（Task 2）、`JourneyStatus.inProgress`。
- Produces: `GameSave.toJson()` 输出顶层 `'energyModel': 2`；`GameSave.fromJson` 在该键缺失且存在 `inProgress` 航程时把 `energyCost` 加回 `player.energyBalance`。`_saveKey` **不变**。

- [ ] **Step 1: 写失败测试**

在 `starward/test/real_time_energy_test.dart` 追加：

```dart
  group('v2 save migration', () {
    test('a pre-energy-model save gets its up-front deduction back', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _boot(clock, storage: storage);
      final target = _nearest(c);
      final cost = c.energyCostTo(target);
      final total = c.travelDurationTo(target);
      await c.launchJourney(target);
      clock.advance(Duration(milliseconds: total.inMilliseconds ~/ 2));
      final live = c.energy;
      final balanceBefore = c.player.energyBalance;

      // Rewrite the save the way v2 wrote it: the whole quote already
      // deducted, and no energyModel marker.
      final raw = await storage.read('starward.save.v2');
      final json = jsonDecode(raw!) as Map<String, dynamic>;
      final player = json['player'] as Map<String, dynamic>;
      player['energyBalance'] = (player['energyBalance'] as int) - cost;
      json.remove('energyModel');
      await storage.write('starward.save.v2', jsonEncode(json));

      // Loading migrates it: the deduction comes back, so the live reading is
      // exactly what it was before the round trip.
      final c2 = await _boot(clock, storage: storage);
      expect(c2.energy, live);
      expect(c2.player.energyBalance, balanceBefore,
          reason: 'the migration hands back exactly the quote v2 had taken');
    });

    test('a save with no voyage in flight is left alone', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _boot(clock, storage: storage);
      final before = c.energy;

      final raw = await storage.read('starward.save.v2');
      final json = jsonDecode(raw!) as Map<String, dynamic>;
      json.remove('energyModel');
      await storage.write('starward.save.v2', jsonEncode(json));

      final c2 = await _boot(clock, storage: storage);
      expect(c2.energy, before);
    });

    test('the marker survives a round trip', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      await _boot(clock, storage: storage);
      final raw = await storage.read('starward.save.v2');
      final json = jsonDecode(raw!) as Map<String, dynamic>;
      expect(json['energyModel'], 2);
    });
  });
```

在文件顶部补两个 import：

```dart
import 'dart:convert';
import 'package:starward/data/storage/storage_backend.dart';
```

（`MemoryStorage.read` / `.write` 是 `StorageBackend` 的公开方法——见 `lib/data/storage/storage_backend.dart`。）

- [ ] **Step 2: 跑测试确认失败**

Run: `cd starward && flutter test test/real_time_energy_test.dart`
Expected: FAIL — `the marker survives a round trip` 拿到 `null`；`a pre-energy-model save...` 拿到的能量比 `live` 少 `cost`。

- [ ] **Step 3: 实现**

把 `starward/lib/data/game_repository.dart` 的 `GameSave` 改成（新增 `energyModel` 常量、`toJson` 加键、`fromJson` 改成带迁移的块体）：

```dart
  /// The save schema generation. Saves written before real-time fuel burning
  /// lack the marker and are migrated on load.
  static const int energyModel = 2;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'energyModel': energyModel,
        'player': player.toJson(),
        'ship': ship.toJson(),
        'activeJourney': activeJourney?.toJson(),
        'discoveries': discoveries.map((e) => e.toJson()).toList(),
        'energyLedger': energyLedger.map((e) => e.toJson()).toList(),
        'trainingSessions':
            trainingSessions.map((e) => e.toJson()).toList(),
        'planetStates': planetStates,
      };

  factory GameSave.fromJson(Map<String, dynamic> json) {
    var player = PlayerState.fromJson(json['player'] as Map<String, dynamic>);
    final activeJourney = json['activeJourney'] == null
        ? null
        : Journey.fromJson(json['activeJourney'] as Map<String, dynamic>);

    // Saves written before real-time burning (no 'energyModel') had the whole
    // voyage cost taken at launch. `energyBalance` now means "fuel not yet
    // burned", so hand that deduction back — otherwise an in-flight save would
    // pay for the same trip twice. A lossless migration, so no key bump.
    if (json['energyModel'] == null &&
        activeJourney != null &&
        activeJourney.status == JourneyStatus.inProgress) {
      player = player.copyWith(
        energyBalance: player.energyBalance + activeJourney.energyCost,
      );
    }

    return GameSave(
      player: player,
      // Saves written before ships were modelled have no 'ship' key. Falling
      // back to the standard ship migrates them in place instead of
      // abandoning the player's progress — and because the standard engine
      // carries the numbers the game used before, such a save flies
      // identically to how it did.
      ship: json['ship'] == null
          ? Ship.standard
          : Ship.fromJson(json['ship'] as Map<String, dynamic>),
      activeJourney: activeJourney,
      discoveries: (json['discoveries'] as List<dynamic>)
          .map((e) => DiscoveryRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
      energyLedger: (json['energyLedger'] as List<dynamic>)
          .map((e) => EnergyTransaction.fromJson(e as Map<String, dynamic>))
          .toList(),
      trainingSessions: (json['trainingSessions'] as List<dynamic>)
          .map((e) => TrainingSession.fromJson(e as Map<String, dynamic>))
          .toList(),
      planetStates:
          (json['planetStates'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v as String),
      ),
    );
  }
```

- [ ] **Step 4: 跑全量测试确认通过**

Run: `cd starward && flutter analyze && flutter test`
Expected: `No issues found`；全部通过。

- [ ] **Step 5: 提交**

```bash
cd starward && git add lib/data/game_repository.dart test/real_time_energy_test.dart
git commit -m "$(cat <<'EOF'
feat(starward): migrate pre-burn saves instead of double-charging them

v2 saves deducted the whole voyage cost at launch. energyBalance now
means "fuel not yet burned", so loading such a save hands that
deduction back. Keyed on a top-level energyModel marker, so no save key
bump and no lost progress.

Co-Authored-By: Claude Code <noreply@anthropic.com>
EOF
)"
```

**阶段 1 检查点**：跑 `flutter run`，出发一段长航程，`_FlightPanel` 的能量读数应当逐秒递减，抵达时账本出现一条 `-cost`。

---

## 阶段 B — 漂移地基

这一阶段的产物在玩家眼里"什么都没变"：漂移速度恒为零向量，所以 `driftPositionAt` 原样返回起点，出生 / `abortJourney` / 抵达恒星 / 抵达坐标四条既有深空路径逐位不变。它的价值是把"飞船在深空的位置"从**常量**变成**时间的函数**，让阶段 C 的滑行只需要写一个非零速度进去。

### Task 4: `core/drift.dart` —— 有界无边的闭式几何

**Files:**
- Create: `starward/lib/core/drift.dart`
- Test: `starward/test/drift_test.dart`（新建）

**Interfaces:**
- Consumes: `lib/core/vec3.dart`（`Vec3` 的 `+ - *`、`dot`、`length`、`normalized`）。**不得** import `lib/data/`。
- Produces: `Vec3 driftPositionAt({required Vec3 start, required Vec3 velocity, required double elapsedSeconds, required double bound})` —— 恒速漂流的闭式位置，`|结果| <= bound` 恒成立。

- [ ] **Step 1: 写失败测试**

新建 `starward/test/drift_test.dart`：

```dart
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/drift.dart';
import 'package:starward/core/vec3.dart';

void expectVec(Vec3 actual, Vec3 expected, {double tol = 0.01}) {
  expect(actual.x, closeTo(expected.x, tol));
  expect(actual.y, closeTo(expected.y, tol));
  expect(actual.z, closeTo(expected.z, tol));
}

void main() {
  group('driftPositionAt', () {
    test('a parked ship never moves, however long it waits', () {
      const start = Vec3(10, 20, 30);
      final p = driftPositionAt(
        start: start,
        velocity: const Vec3(0, 0, 0),
        elapsedSeconds: 1e6,
        bound: 100,
      );
      expectVec(p, start);
    });

    test('inside the shell it just flies straight', () {
      final p = driftPositionAt(
        start: const Vec3(0, 0, 0),
        velocity: const Vec3(1, 0, 0),
        elapsedSeconds: 10,
        bound: 100,
      );
      expectVec(p, const Vec3(10, 0, 0));
    });

    test('it reaches the shell at the right moment and then slides', () {
      // From (50,0,0) heading +Y at 1 ly/s inside a 100 ly sphere: the shell is
      // hit when 50² + s² = 100², i.e. s = sqrt(7500) = 86.6025 s.
      const start = Vec3(50, 0, 0);
      const v = Vec3(0, 1, 0);

      final justBefore = driftPositionAt(
          start: start, velocity: v, elapsedSeconds: 86.6025, bound: 100);
      expectVec(justBefore, const Vec3(50, 86.6025, 0));

      // 13.3975 s later it has slid along the great circle, still on the shell.
      final after = driftPositionAt(
          start: start, velocity: v, elapsedSeconds: 100, bound: 100);
      expect(after.length, closeTo(100, 0.001));
      expectVec(after, const Vec3(44.0904, 89.7552, 0));
    });

    test('lapping the shell stays on it', () {
      // Two full laps' worth of arc after the impact.
      final p = driftPositionAt(
        start: const Vec3(50, 0, 0),
        velocity: const Vec3(0, 1, 0),
        elapsedSeconds: 86.6025 + 2 * 2 * math.pi * 100 / 0.5,
        bound: 100,
      );
      expect(p.length, closeTo(100, 0.001));
      // Back where it hit, having gone all the way round twice.
      expectVec(p, const Vec3(50, 86.6025, 0));
    });

    test('a purely radial impact sticks to one point on the shell', () {
      // Headed straight out from the centre: once it touches the shell the
      // tangential component is zero, so it stops there rather than sliding.
      // Degenerate, but correct — pinned so nobody "fixes" it later.
      final p = driftPositionAt(
        start: const Vec3(50, 0, 0),
        velocity: const Vec3(1, 0, 0),
        elapsedSeconds: 200,
        bound: 100,
      );
      expectVec(p, const Vec3(100, 0, 0));
    });

    test('a ship that starts outside the shell is never teleported inward', () {
      // bound is expected to be max(universeRadius, |start|) at the call site;
      // even handed a smaller one, the ship keeps its own radius.
      final p = driftPositionAt(
        start: const Vec3(0, 0, 300),
        velocity: const Vec3(1, 0, 0),
        elapsedSeconds: 100,
        bound: 100,
      );
      expect(p.length, closeTo(300, 0.001));
      // Radius 300, tangential speed 1 ly/s, 100 s of arc → θ = 100/300 rad,
      // so p = 300·(sin θ, 0, cos θ) = (98.158, 0, 283.487).
      expectVec(p, const Vec3(98.1584, 0, 283.4871));
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd starward && flutter test test/drift_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:starward/core/drift.dart'`。

- [ ] **Step 3: 实现**

新建 `starward/lib/core/drift.dart`：

```dart
import 'dart:math' as math;

import 'vec3.dart';

/// Constant-velocity drift through a universe that is bounded but edgeless.
///
/// A coasting ship flies in a straight line until it meets the shell of radius
/// [bound], then slides along that shell on a great circle. It therefore never
/// reaches anywhere emptier than the shell — which is the whole point: an
/// unconstrained drift ends up in a void with nothing left to visit.
///
/// Both legs are closed-form. The position after a week offline costs exactly
/// one evaluation, and there is no stored state to drift out of sync: the
/// answer is always just a function of (start, velocity, elapsed, bound).
Vec3 driftPositionAt({
  required Vec3 start,
  required Vec3 velocity, // light-years per second
  required double elapsedSeconds,
  required double bound,
}) {
  if (elapsedSeconds <= 0) return start;

  final a = velocity.dot(velocity);
  // Parked. This is what the game's deep-space hover has always been, so the
  // zero-velocity case reproduces the old static behaviour exactly.
  if (a == 0) return start;

  final startLen = start.length;

  // Already on (or beyond) the shell: slide from here, on the radius the ship
  // actually has. Never teleport it inward to `bound` — a player who spawned
  // outside the shell keeps their own radius, they just stop widening it.
  if (startLen >= bound) {
    return _slide(start, velocity, elapsedSeconds, startLen);
  }

  // |start + v·s|² = bound²  →  a·s² + b·s + c = 0
  final b = 2 * start.dot(velocity);
  final c = startLen * startLen - bound * bound;
  final disc = b * b - 4 * a * c;
  // c < 0 here (the ship starts inside), so disc > 0 always; this is belt and
  // braces against a NaN from a degenerate caller.
  if (disc <= 0) return start;
  final hitSeconds = (-b + math.sqrt(disc)) / (2 * a);

  if (elapsedSeconds <= hitSeconds) {
    return start + velocity * elapsedSeconds;
  }
  return _slide(
    start + velocity * hitSeconds,
    velocity,
    elapsedSeconds - hitSeconds,
    bound,
  );
}

/// Moves [point] along the great circle of radius [radius] defined by the
/// tangential part of [velocity], sweeping for [seconds].
Vec3 _slide(Vec3 point, Vec3 velocity, double seconds, double radius) {
  final n = point.normalized;
  final tangential = velocity - n * velocity.dot(n);
  final speed = tangential.length;
  // Purely radial impact — no tangential component to slide with, so the ship
  // sits at this point on the shell. Degenerate and intentional; see the test.
  if (speed < 1e-12) return point;
  final tangent = tangential.normalized;
  final theta = speed * seconds / radius;
  return (n * math.cos(theta) + tangent * math.sin(theta)) * radius;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd starward && flutter test test/drift_test.dart`
Expected: PASS（6 tests）。

- [ ] **Step 5: 提交**

```bash
cd starward && git add lib/core/drift.dart test/drift_test.dart
git commit -m "$(cat <<'EOF'
feat(starward): closed-form drift inside a bounded, edgeless universe

A coasting ship flies straight to a shell of radius `bound` and then
slides along it on a great circle. Both legs are analytic, so position
stays a pure function of (start, velocity, elapsed, bound) — no
accumulated state, and a week offline costs one evaluation.

Co-Authored-By: Claude Code <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: 漂流成为一等状态（行为零变化）

给 `PlayerState` 加两个字段，让 `playerPosition3D` 走 `driftPositionAt`。默认速度是零向量，所以这个 task 落地后游戏表现与改动前**逐位相同**——这正是它的可验证之处。

**Files:**
- Modify: `starward/lib/data/models/player_state.dart`（字段、`copyWith`、`deepSpaceStart`、`fromJson`、`toJson`）
- Modify: `starward/lib/state/game_controller.dart`
  - `playerPosition3D`（:206）
  - 新增 `_anchorHere()`（放在 `playerPosition3D` 附近）
  - `launchJourney`（:379）、`launchToStar`（:416）、`returnToOrigin`（:519）各接一行
- Test: `starward/test/coast_test.dart`（新建）

**Interfaces:**
- Consumes: `driftPositionAt`（Task 4）、`Universe.universeRadius`（**Task 6**——本 task 先不接边界，见 Step 3c）。
- Produces:
  - `PlayerState.driftVelocity`（`Vec3`，默认 `Vec3(0,0,0)`）、`PlayerState.driftStartedAt`（`DateTime`，默认 epoch）
  - `PlayerState.copyWith({..., Vec3? driftVelocity, DateTime? driftStartedAt})`
  - `void GameController._anchorHere()` —— 把深空锚点钉到当前位置并清零漂流

- [ ] **Step 1: 写失败测试**

新建 `starward/test/coast_test.dart`：

```dart
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/vec3.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/models/player_state.dart';
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

void main() {
  group('PlayerState drift fields', () {
    test('default to a parked ship and survive a JSON round trip', () {
      final s = PlayerState.deepSpaceStart(
        energy: 300,
        startCoordX: 0,
        startCoordY: 0,
        startX: 1,
        startY: 2,
        startZ: 3,
        createdAt: DateTime(2026),
      );
      expect(s.driftVelocity.length, 0);
      expect(s.driftStartedAt.millisecondsSinceEpoch, 0);

      final moved = s.copyWith(
        driftVelocity: const Vec3(0, 0.5, 0),
        driftStartedAt: DateTime(2026, 5, 1),
      );
      final back = PlayerState.fromJson(moved.toJson());
      expect(back.driftVelocity.y, 0.5);
      expect(back.driftStartedAt, DateTime(2026, 5, 1));
    });

    test('an old save with no drift keys loads as parked', () {
      final json = PlayerState.deepSpaceStart(
        energy: 300,
        startCoordX: 0,
        startCoordY: 0,
        startX: 1,
        startY: 2,
        startZ: 3,
        createdAt: DateTime(2026),
      ).toJson()
        ..remove('driftVelocityX')
        ..remove('driftVelocityY')
        ..remove('driftVelocityZ')
        ..remove('driftStartedAt');
      final back = PlayerState.fromJson(json);
      expect(back.driftVelocity.length, 0);
      expect(back.driftStartedAt.millisecondsSinceEpoch, 0);
    });
  });

  group('a parked ship does not move', () {
    test('position is stable no matter how much time passes', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final before = c.playerPosition3D;
      clock.advance(const Duration(days: 400));
      final after = c.playerPosition3D;
      expect(after.x, before.x);
      expect(after.y, before.y);
      expect(after.z, before.z);
    });

    test('aborting still parks the ship at the point it reached', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final target = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
      await c.launchJourney(target);
      final journey = c.activeJourney!;
      clock.advance(journey.totalDuration ~/ 2);
      await c.abortJourney();

      expect(c.inDeepSpace, isTrue);
      expect(c.driftVelocity.length, 0,
          reason: 'aborting stops the ship; it does not start a drift');
      final parked = c.playerPosition3D;
      clock.advance(const Duration(days: 10));
      expect(c.playerPosition3D.x, parked.x);
      expect(c.playerPosition3D.y, parked.y);
      expect(c.playerPosition3D.z, parked.z);
    });

    test('launching re-anchors the deep-space origin to where the ship is',
        () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final target = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
      await c.launchJourney(target);
      final journey = c.activeJourney!;
      clock.advance(journey.totalDuration ~/ 2);
      await c.abortJourney();
      final parked = c.playerPosition3D;

      // Fly again from the parked spot, then abort again: the new anchor must
      // be the second parking spot, not the first.
      await c.launchJourney(c.planets.firstWhere((p) => p.id != target.id));
      final second = c.activeJourney!;
      clock.advance(second.totalDuration ~/ 4);
      await c.abortJourney();
      final secondPark = c.playerPosition3D;
      expect((secondPark - parked).length, greaterThan(0.001),
          reason: 'the second abort parks somewhere new');
      expect(c.deepSpaceOrigin3D!.x, closeTo(secondPark.x, 0.001));
    });
  });
}
```

**注意**：测试里用了 `c.driftVelocity`。在 `GameController` 上加一个只读转发，放在 `deepSpaceOrigin3D` 之后：

```dart
  /// The ship's current drift velocity in ly/s. Zero whenever the ship is
  /// parked — which is every state the game had before coasting existed.
  Vec3 get driftVelocity => _player.driftVelocity;
```

（`_player` 是私有的，需要一个转发；滑行页 UI 也要读它，所以不加 `ForTest` 后缀。）

- [ ] **Step 2: 跑测试确认失败**

Run: `cd starward && flutter test test/coast_test.dart`
Expected: FAIL — `The getter 'driftVelocity' isn't defined for the type 'PlayerState'`（编译错误即失败）。

- [ ] **Step 3: 实现**

**3a.** `starward/lib/data/models/player_state.dart` 加字段（构造函数加两个 `required` 参数，放在 `startZ` 之后）：

```dart
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
```

`copyWith` 加两个可选参数：

```dart
    Vec3? driftVelocity,
    DateTime? driftStartedAt,
```

并在返回的 `PlayerState(...)` 里加：

```dart
      driftVelocity: driftVelocity ?? this.driftVelocity,
      driftStartedAt: driftStartedAt ?? this.driftStartedAt,
```

`deepSpaceStart` 里加：

```dart
      driftVelocity: const Vec3(0, 0, 0),
      driftStartedAt: DateTime.fromMillisecondsSinceEpoch(0),
```

`fromJson` 里加（旧存档缺键时回落到"停着"）：

```dart
        driftVelocity: Vec3(
          (json['driftVelocityX'] as num?)?.toDouble() ?? 0,
          (json['driftVelocityY'] as num?)?.toDouble() ?? 0,
          (json['driftVelocityZ'] as num?)?.toDouble() ?? 0,
        ),
        driftStartedAt: DateTime.fromMillisecondsSinceEpoch(
            (json['driftStartedAt'] as int?) ?? 0),
```

`toJson` 里加：

```dart
        'driftVelocityX': driftVelocity.x,
        'driftVelocityY': driftVelocity.y,
        'driftVelocityZ': driftVelocity.z,
        'driftStartedAt': driftStartedAt.millisecondsSinceEpoch,
```

文件顶部加 `import '../../core/vec3.dart';`。

**注意**：构造函数里的 `driftStartedAt` 保持 `required` 而不是给默认值——`DateTime` 不是 const 可构造的，const 构造函数没法写 `this.driftStartedAt = epoch`。所以三个调用点（`copyWith` / `deepSpaceStart` / `fromJson`）各自显式传默认值。

**3b.** `starward/lib/state/game_controller.dart` 把 `playerPosition3D` 换成：

```dart
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
      // No shell yet: `universeRadius` arrives in Task 6. With velocity still
      // pinned to zero until Task 9, the bound is unreachable either way, so
      // this is bit-identical to today's static deep space. Task 6 swaps this
      // line for `math.max(_universe.universeRadius, start.length)`.
      bound: start.length,
    );
  }
```

文件顶部加 `import '../core/drift.dart';`。

**3c.** 同时加 `driftVelocity` 转发（见 Step 1 的注意）。

**3d.** 加 `_anchorHere()`（放在 `playerPosition3D` 之后）：

```dart
  /// Pins the deep-space anchor to where the ship actually is right now, and
  /// stops any drift — the engine is taking over the motion.
  ///
  /// Every launch must do this: [_originPosOf] reads the anchor, so a coasting
  /// ship that launched without re-anchoring would plot its route from a stale
  /// coordinate and arrive somewhere it never was.
  void _anchorHere() {
    final pos = playerPosition3D;
    _player = _player.copyWith(
      startX: pos.x,
      startY: pos.y,
      startZ: pos.z,
      driftVelocity: const Vec3(0, 0, 0),
    );
  }
```

**3e.** 在 `launchJourney` 和 `launchToStar` 里，把 `_anchorHere();` 放在守卫之后、`final departure = _now();` 之前。

**3f.** `returnToOrigin` 里给 `_player.copyWith(...)` 那处补上 `driftVelocity: const Vec3(0, 0, 0),`（它已经自己写好了 `startX/Y/Z`，不需要 `_anchorHere`）。

- [ ] **Step 4: 跑全量测试确认通过**

Run: `cd starward && flutter analyze && flutter test`
Expected: `No issues found`；全部通过，**一条测试都不用改**。这就是"行为零变化"的证据：`test/deep_space_start_test.dart`、`test/return_to_origin_test.dart`、`test/flight_panel_test.dart` 全部原样通过。

- [ ] **Step 5: 提交**

```bash
cd starward && git add lib/data/models/player_state.dart lib/state/game_controller.dart test/coast_test.dart
git commit -m "$(cat <<'EOF'
refactor(starward): make deep-space drift a first-class ship state

PlayerState gains driftVelocity/driftStartedAt and playerPosition3D
advances the anchor by them. Zero velocity reproduces the old static
hover bit for bit, so no existing test changes — that is the point of
landing this separately from coasting itself.

Every launch now re-anchors the deep-space origin to the ship's live
position and clears the drift, because _originPosOf reads that anchor.

Co-Authored-By: Claude Code <noreply@anthropic.com>
EOF
)"
```

**注意**：本 task 的 `playerPosition3D` 用的是 `bound: start.length`，**不**读 `_universe.universeRadius`——那个 getter 到 Task 6 才存在，本 task 必须能独立通过 `flutter analyze`。Task 6 的 Step 4 会把这一行换成 `math.max(_universe.universeRadius, start.length)`。所以 Task 4–7 按序执行即可，不需要调换顺序。在 Task 9 之前没有任何代码把 `driftVelocity` 设成非零，所以这个 bound 根本走不到，本 task 的行为逐位不变。

---

### Task 6: `Universe.universeRadius` 与全星表兜底查询

**Files:**
- Modify: `starward/lib/data/universe.dart`
  - `universeRadius` getter + 缓存字段（放在 `starArrivalPoint` 之后，约 :181）
  - `nearestPlanets`（放在 `planetsNear` 之后，约 :208）
- Test: `starward/test/coast_test.dart`（追加）

**Interfaces:**
- Consumes: `HygStars`（`count`、`xyz`、`starId`、`positionOfIndex`）、`extraGalaxies`、`Vec3`。
- Produces:
  - `double Universe.universeRadius` —— 含 95% 恒星的半径，惰性算一次并缓存。实测 **3066 ly**。
  - `List<Planet> Universe.nearestPlanets(Vec3 posLy, {int starCount = 40, int cap = 90})` —— 全星表最近的若干恒星所带的行星，最近优先。永不为空（星表非空时）。

- [ ] **Step 1: 写失败测试**

在 `starward/test/coast_test.dart` 追加：

```dart
// --- 追加 import ---
// import 'package:starward/data/hyg_catalog.dart';
// import 'package:starward/data/synthetic_galaxy.dart';
// import 'package:starward/data/universe.dart';

  group('Universe.universeRadius', () {
    // The real catalogue is a bundled asset; loading it needs the binding.
    setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

    test('pins the measured 95th-percentile radius', () async {
      final hyg = await HygCatalog.load();
      expect(hyg, isNotNull);
      final u = Universe(hyg!, extraGalaxies: SyntheticGalaxy.all());
      // Measured 2026-10-12 over 120,601 stars (HYG + SG-1 + SG-2).
      // If this drifts, the star catalogue or the galaxy generator changed —
      // and the shell is no longer where the density study put it.
      expect(u.universeRadius, closeTo(3066, 30));
    });

    test('the shell is somewhere with stars to reach', () async {
      final hyg = await HygCatalog.load();
      final u = Universe(hyg!, extraGalaxies: SyntheticGalaxy.all());
      final r = u.universeRadius;
      // A point on the shell must still see a healthy neighbourhood: the
      // nearby search reaches 960 ly, and its target is 10 planets.
      final onShell = Vec3(r, 0, 0);
      expect(u.planetsNear(onShell, 960).length, greaterThanOrEqualTo(10));
    });

    test('nearestPlanets finds somewhere to go from the middle of nowhere',
        () async {
      final hyg = await HygCatalog.load();
      final u = Universe(hyg!, extraGalaxies: SyntheticGalaxy.all());
      final nowhere = Vec3(50000, 0, 0);
      final found = u.nearestPlanets(nowhere);
      expect(found, isNotEmpty,
          reason: 'a ship stranded outside the shell must still have a target');
      expect(found.length, greaterThanOrEqualTo(10));
      // Pinned against the real catalogue: the star nearest to (50000,0,0) sits
      // at (3187.739, 119.741, -220.695), 46812.9348 ly away, and a generated
      // planet orbits within 2.6 ly of its star (`_spherePoint(rng, 0.6, 2.6)`).
      // So a nearest-first full-catalogue scan must land in this window. If the
      // fallback only looked at the shell or the curated list, it would miss.
      expect((found.first.pos - nowhere).length, closeTo(46812.9, 5));
      expect(found.first.pos.length, closeTo(3197.6, 5),
          reason: 'the nearest planet is an outermost real star');
    });
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd starward && flutter test test/coast_test.dart`
Expected: FAIL — `The getter 'universeRadius' isn't defined for the type 'Universe'`。

- [ ] **Step 3: 实现**

在 `starward/lib/data/universe.dart` 的 `starArrivalPoint` 之后插入：

```dart
  double? _universeRadius;

  /// The radius of the bounded-but-edgeless universe: the smallest sphere that
  /// holds 95% of every star we know about, in light-years.
  ///
  /// Derived from the catalogue rather than hard-coded, so dropping in another
  /// galaxy widens the shell on its own and nobody has to remember a magic
  /// number. The *fraction* is the interesting choice: a coasting ship is
  /// confined to this shell, so the shell has to sit where the stars are.
  /// Measured 2026-10-12 over 120,601 stars: 3066 ly. Every point sampled on
  /// that shell has at least 35 stars within the 960 ly the nearby search
  /// reaches; putting the shell at the catalogue's true edge (3948 ly) instead
  /// leaves it in vacuum — the exact dead end the shell exists to prevent.
  /// See docs/superpowers/specs/2026-10-12-starward-voyage-energy-and-drift-design.md §5.
  ///
  /// Computed once on first use and cached; the scan is ~120k square roots.
  double get universeRadius {
    final cached = _universeRadius;
    if (cached != null) return cached;

    final distances = <double>[];
    void collect(HygStars set) {
      for (var i = 0; i < set.count; i++) {
        final x = set.xyz[i * 3];
        final y = set.xyz[i * 3 + 1];
        final z = set.xyz[i * 3 + 2];
        distances.add(math.sqrt(x * x + y * y + z * z));
      }
    }

    collect(stars);
    for (final g in extraGalaxies) {
      collect(g);
    }
    if (distances.isEmpty) return 0;

    distances.sort();
    final r = distances[((distances.length - 1) * 0.95).round()];
    _universeRadius = r;
    return r;
  }
```

在 `planetsNear` 之后插入：

```dart
  /// The planets around the [starCount] nearest stars to [posLy], nearest
  /// first, capped at [cap].
  ///
  /// Unlike [planetsNear] this ignores radius entirely, so it is the last-resort
  /// answer to "the ship is somewhere with nothing within reach". Never empty
  /// while the catalogue is: a stranded ship always has somewhere to fly, even
  /// if the trip is expensive. Keeps the best [starCount] stars in a small
  /// insertion-sorted array rather than sorting all ~120k distances.
  List<Planet> nearestPlanets(Vec3 posLy, {int starCount = 40, int cap = 90}) {
    final sets = <HygStars>[stars, ...extraGalaxies];
    final bestD2 = List<double>.filled(starCount, double.infinity);
    final bestSet = List<int>.filled(starCount, 0);
    final bestIdx = List<int>.filled(starCount, 0);
    var filled = 0;

    for (var si = 0; si < sets.length; si++) {
      final set = sets[si];
      for (var i = 0; i < set.count; i++) {
        final dx = set.xyz[i * 3] - posLy.x;
        final dy = set.xyz[i * 3 + 1] - posLy.y;
        final dz = set.xyz[i * 3 + 2] - posLy.z;
        final d2 = dx * dx + dy * dy + dz * dz;
        // Most candidates fail here, which is what keeps this O(n).
        if (filled == starCount && d2 >= bestD2[starCount - 1]) continue;
        var j = filled < starCount ? filled++ : starCount - 1;
        while (j > 0 && bestD2[j - 1] > d2) {
          bestD2[j] = bestD2[j - 1];
          bestSet[j] = bestSet[j - 1];
          bestIdx[j] = bestIdx[j - 1];
          j--;
        }
        bestD2[j] = d2;
        bestSet[j] = si;
        bestIdx[j] = i;
      }
    }

    final out = <Planet>[];
    for (var k = 0; k < filled; k++) {
      final set = sets[bestSet[k]];
      final i = bestIdx[k];
      out.addAll(_planetsForStar(set.starId[i], set.positionOfIndex(i)));
    }
    out.sort((a, b) => (a.pos - posLy).length.compareTo((b.pos - posLy).length));
    return out.length > cap ? out.sublist(0, cap) : out;
  }
```

- [ ] **Step 4: 把边界接进 `playerPosition3D`**

Task 5 留下的那一行现在是 `bound: start.length`。换成：

```dart
      // Never tighter than the ship's own radius: a player who spawned outside
      // the shell keeps their distance instead of being snapped inward.
      bound: math.max(_universe.universeRadius, start.length),
```

`game_controller.dart` 里 `math` 已经导入。这一步没有任何新测试——Task 5 的 `coast_test.dart` 里"停着的船不动"那组断言在换行前后都必须通过，它们就是这次改动的回归网。

- [ ] **Step 5: 跑测试确认通过**

Run: `cd starward && flutter analyze && flutter test test/coast_test.dart test/universe_test.dart`
Expected: `No issues found`；PASS。若 `universeRadius` 断言失败，把实测值记下来并**先确认星表与 `SyntheticGalaxy.all()` 没变**；只有确认它们是新的基线之后才更新那个数字，并在注释里写清新日期。

- [ ] **Step 6: 提交**

```bash
cd starward && git add lib/data/universe.dart lib/state/game_controller.dart test/coast_test.dart
git commit -m "$(cat <<'EOF'
feat(starward): derive the universe shell from star density

universeRadius is the 95th-percentile star distance (3066 ly), lazily
measured and cached. A quantile rather than a constant so a new galaxy
widens the shell by itself, and 95% rather than the true edge because
the outermost stars are exactly where a coasting ship would starve.

nearestPlanets is the no-radius fallback that guarantees a stranded
ship still has somewhere to fly, and playerPosition3D now clamps drift
to the shell.

Co-Authored-By: Claude Code <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: `_rebuildNearby` 位移节流 + 全星表兜底

滑行的船每天走 2304 ly。不节流的话每一帧都要扫 12 万颗星重建一个几乎没变的列表。

**Files:**
- Modify: `starward/lib/state/game_controller.dart`
  - 新增 `_nearbyScanPos` 字段与 `_nearbyRescanLy` 常量（放在 `_nearbyRadiusLy` 附近，约 :73）
  - `_rebuildNearby`（:265）：加兜底、记录扫描位置
  - 新增 `_maybeRescanNearby`（紧邻 `_rebuildNearby`）
  - `tick`（:365）：else 分支调用 `_maybeRescanNearby()`
- Test: `starward/test/coast_test.dart`（追加）

**Interfaces:**
- Consumes: `Universe.nearestPlanets`（Task 6）、`GameController.driftVelocity`（Task 5）、`playerPosition3D`（Task 5）。
- Produces:
  - `static const double GameController._nearbyRescanLy = 20`
  - `void GameController._maybeRescanNearby()` —— 漂流中位移超过 20 ly 才重建附近集合；停着时是 no-op。

- [ ] **Step 1: 写失败测试**

在 `starward/test/coast_test.dart` 追加：

```dart
// --- 追加 import ---
// import 'dart:convert';
// import 'package:starward/data/models/player_state.dart';  // 已有

/// Rewrites the saved drift so the ship is coasting from a known anchor.
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

  group('_rebuildNearby under drift', () {
    test('the nearby set is left alone until the ship has moved 20 ly',
        () async {
      final start = DateTime(2026, 1, 1);
      final clock = FakeClock(start);
      final storage = MemoryStorage();
      await _boot(clock, storage: storage);
      // 1 ly/s heading +X, anchored at the Solar-System spawn.
      await _setDrift(storage, const Vec3(1, 0, 0), start);
      final c = await _boot(clock, storage: storage);

      final before = c.planets;
      clock.advance(const Duration(seconds: 10)); // 10 ly — under the threshold
      c.tick();
      expect(identical(c.planets, before), isTrue,
          reason: 'a 10 ly nudge must not trigger a 120k-star rescan');

      clock.advance(const Duration(seconds: 15)); // 25 ly — over it
      c.tick();
      expect(identical(c.planets, before), isFalse);
    });

    test('a ship stranded far outside the shell still has destinations',
        () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      await _boot(clock, storage: storage);
      // 50,000 ly out: nothing within the 960 ly the radius search reaches.
      final raw = await storage.read('starward.save.v2');
      final json = jsonDecode(raw!) as Map<String, dynamic>;
      final player = json['player'] as Map<String, dynamic>;
      player['startX'] = 50000.0;
      player['startY'] = 0.0;
      player['startZ'] = 0.0;
      await storage.write('starward.save.v2', jsonEncode(json));

      final c = await _boot(clock, storage: storage);
      expect(c.planets, isNotEmpty,
          reason: 'no soft-lock: there is always somewhere to fly');
      // And they are the genuinely nearest ones, ~46,000 ly away.
      expect(c.planets.first.pos.length, lessThan(50000));
    });
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd starward && flutter test test/coast_test.dart`
Expected: FAIL — `a ship stranded far outside the shell` 拿到空 `planets`；`the nearby set is left alone` 拿到不同实例。

- [ ] **Step 3: 实现**

**3a.** 在 `_nearbyRadiusLy` 之后加：

```dart
  /// The position the nearby set was last built at, so a drifting ship can
  /// skip the scan when it has barely moved.
  Vec3? _nearbyScanPos;

  /// How far the ship must travel before the nearby set is rebuilt. A coasting
  /// ship covers 2304 ly/day, so rescanning every frame would walk 120k stars
  /// sixty times a second for a list that hardly changed.
  static const double _nearbyRescanLy = 20;
```

**3b.** `_rebuildNearby` 换成：

```dart
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
    // stars anywhere in the catalogue, so `planets` is never empty and the
    // player is never stuck with nowhere to go.
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
```

**3c.** `tick` 换成：

```dart
  void tick() {
    if (_activeJourney?.status == JourneyStatus.inProgress &&
        _activeJourney!.hasArrivedBy(_now())) {
      _reconcileJourney();
      _persist();
      notifyListeners();
      return;
    }
    // Still travelling, or coasting: repaint without persisting. A coasting
    // ship may also have crossed into a new neighbourhood.
    _maybeRescanNearby();
    notifyListeners();
  }
```

- [ ] **Step 4: 跑全量测试确认通过**

Run: `cd starward && flutter analyze && flutter test`
Expected: `No issues found`；全部通过。

- [ ] **Step 5: 提交**

```bash
cd starward && git add lib/state/game_controller.dart test/coast_test.dart
git commit -m "$(cat <<'EOF'
perf(starward): throttle the nearby scan while coasting

A coasting ship covers 2304 ly/day, so the nearby set now rebuilds on
20 ly of displacement instead of every tick. Also adds the last-resort
fallback to the nearest stars anywhere in the catalogue, so a ship
stranded outside the shell always has somewhere to fly.

Co-Authored-By: Claude Code <noreply@anthropic.com>
EOF
)"
```

**阶段 B 检查点**：`flutter run` 走一遍——出生、飞一段、停止、返航，表现应当与改动前完全一样。这一阶段不该有任何可见变化。

---

## 阶段 C — 三选一 + 停下 + 滑行

### Task 8: `FuelPolicy` 与出发门槛

**Files:**
- Modify: `starward/lib/data/models/journey.dart`（`FuelPolicy` 枚举 + `fuelPolicyFromName` + `Journey.fuelPolicy` 字段 + `copyWith` + JSON）
- Modify: `starward/lib/state/game_controller.dart`
  - 新增 `fuelExhaustProgressFor` / `fuelExhaustProgress` / `fuelExhaustTime`（放在 `travelDurationTo` 之后，约 :252）
  - 新增 `_launchGate`（放在 `// --- Energy helpers ---` 段）
  - `launchJourney`（:379）、`launchToStar`（:416）：加 `onEmpty` 具名参数、换掉守卫
- Test: `starward/test/fuel_out_test.dart`（新建）

**Interfaces:**
- Consumes: `GameController.energy`（Task 2）、`_player.energyBalance`、`Engine.minEnergyCost`。
- Produces:
  - `enum FuelPolicy { refuse, halt, coast }`（`lib/data/models/journey.dart`）
  - `Journey.fuelPolicy`（`FuelPolicy`，默认 `FuelPolicy.halt`）
  - `double GameController.fuelExhaustProgressFor(Journey j)` —— `energyBalance / energyCost`，封顶 1
  - `double? GameController.fuelExhaustProgress` —— 活动航程的上面那个值，停着时为 null
  - `DateTime GameController.fuelExhaustTime(Journey j)` —— 烧干的时刻，不晚于抵达
  - `Future<LaunchResult> launchJourney(Planet target, {FuelPolicy onEmpty})`
  - `Future<LaunchResult> launchToStar(int hygId, {FuelPolicy onEmpty})`

- [ ] **Step 1: 写失败测试**

新建 `starward/test/fuel_out_test.dart`：

```dart
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/game_repository.dart';
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

Future<GameController> _boot(FakeClock clock) async {
  final c = GameController(
    repository: GameRepository(MemoryStorage()),
    clock: clock.call,
    random: math.Random(3),
  );
  await c.init();
  return c;
}

/// Flies cheap hops until the balance drops to or below [target].
Future<void> _drainBelow(GameController c, FakeClock clock, int target) async {
  for (var i = 0; i < 200 && c.energy > target; i++) {
    final t = c.planets.firstWhere(
      (p) => p.id != c.currentPlanetId,
      orElse: () => c.planets.first,
    );
    if (await c.launchJourney(t) != LaunchResult.success) break;
    // Long enough for any hop inside the 960 ly search radius (10 h).
    clock.advance(const Duration(hours: 12));
    c.tick();
    await c.acknowledgeArrival();
  }
}

/// The farthest reachable target — the one most likely to be unaffordable.
Planet _farthest(GameController c) => c.planets
    .where((p) => p.id != c.currentPlanetId)
    .reduce((a, b) => c.distanceTo(a) > c.distanceTo(b) ? a : b);

void main() {
  group('FuelPolicy on a voyage', () {
    test('round-trips through JSON and defaults to halt', () {
      final j = Journey(
        id: 'j1',
        originPlanetId: 'a',
        destinationPlanetId: 'b',
        departure: DateTime(2026),
        arrival: DateTime(2026, 1, 2),
        energyCost: 100,
        status: JourneyStatus.inProgress,
      );
      expect(j.fuelPolicy, FuelPolicy.halt, reason: 'the safe default');
      expect(j.copyWith(status: JourneyStatus.arrived).fuelPolicy,
          FuelPolicy.halt, reason: 'copyWith must not drop the policy');

      final coast = Journey(
        id: 'j2',
        originPlanetId: 'a',
        destinationPlanetId: 'b',
        departure: DateTime(2026),
        arrival: DateTime(2026, 1, 2),
        energyCost: 100,
        status: JourneyStatus.inProgress,
        fuelPolicy: FuelPolicy.coast,
      );
      expect(Journey.fromJson(coast.toJson()).fuelPolicy, FuelPolicy.coast);
    });

    test('an old save with no fuelPolicy key loads as halt', () {
      final json = Journey(
        id: 'j1',
        originPlanetId: 'a',
        destinationPlanetId: 'b',
        departure: DateTime(2026),
        arrival: DateTime(2026, 1, 2),
        energyCost: 100,
        status: JourneyStatus.inProgress,
      ).toJson()
        ..remove('fuelPolicy');
      expect(Journey.fromJson(json).fuelPolicy, FuelPolicy.halt);
    });
  });

  group('the launch gate follows the policy', () {
    test('refuse is the default and rejects what it cannot afford', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await _drainBelow(c, clock, 30);
      final far = _farthest(c);
      expect(c.energyCostTo(far), greaterThan(c.energy),
          reason: 'precondition: this hop is out of reach');

      expect(await c.launchJourney(far), LaunchResult.insufficientEnergy);
      expect(c.activeJourney, isNull);
      expect(c.energy, greaterThan(0), reason: 'nothing was deducted');
    });

    test('halt and coast only need a drop of fuel', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await _drainBelow(c, clock, 30);
      final far = _farthest(c);
      expect(c.energyCostTo(far), greaterThan(c.energy));

      expect(await c.launchJourney(far, onEmpty: FuelPolicy.halt),
          LaunchResult.success);
      expect(c.activeJourney!.fuelPolicy, FuelPolicy.halt);
    });

    test('an empty tank moves nothing under any policy', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await _drainBelow(c, clock, 0);
      expect(c.energy, 0, reason: 'precondition: the tank is dry');

      final far = _farthest(c);
      expect(await c.launchJourney(far, onEmpty: FuelPolicy.halt),
          LaunchResult.insufficientEnergy);
      expect(await c.launchJourney(far, onEmpty: FuelPolicy.coast),
          LaunchResult.insufficientEnergy);
      expect(await c.launchJourney(far, onEmpty: FuelPolicy.refuse),
          LaunchResult.insufficientEnergy);
    });
  });

  group('the exhaust point is closed-form', () {
    test('progress, time and position all follow from the balance', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await _drainBelow(c, clock, 40);
      final far = _farthest(c);
      final cost = c.energyCostTo(far);
      final balance = c.energy;
      final origin = c.playerPosition3D;
      final departure = clock();

      expect(await c.launchJourney(far, onEmpty: FuelPolicy.halt),
          LaunchResult.success);
      final journey = c.activeJourney!;

      final p = balance / cost;
      expect(c.fuelExhaustProgress, closeTo(p, 1e-12));
      expect(c.fuelExhaustTime(journey),
          departure.add(Duration(
              milliseconds:
                  (journey.totalDuration.inMilliseconds * p).round())));

      // pos_exhaust = origin + (dest - origin) * p
      final expected = origin + (far.pos - origin) * p;
      final actual = origin +
          (far.pos - origin) *
              journey.progressAt(c.fuelExhaustTime(journey));
      expect((actual - expected).length, lessThan(1e-6));
    });

    test('a top-up mid-flight pushes the exhaust point past arrival', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      await _drainBelow(c, clock, 40);
      final far = _farthest(c);
      expect(c.energyCostTo(far), greaterThan(c.energy));
      await c.launchJourney(far, onEmpty: FuelPolicy.halt);
      expect(c.fuelExhaustProgress, lessThan(1));

      // Enough training to cover the rest of the quote.
      final session = await c.startCourse('walk');
      await c.completeCourse(session.id, 400);

      expect(c.fuelExhaustProgress, 1.0,
          reason: 'the tank now covers the whole trip');
      expect(c.fuelExhaustTime(c.activeJourney!),
          c.activeJourney!.arrival,
          reason: 'nothing to run out of before the destination');
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd starward && flutter test test/fuel_out_test.dart`
Expected: FAIL — `The getter 'fuelPolicy' isn't defined for the type 'Journey'`（编译错误即失败）。

- [ ] **Step 3: 实现**

**3a.** `starward/lib/data/models/journey.dart` 在 `JourneyStatus` 相关代码之后加：

```dart
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
```

`Journey` 构造函数加一个带默认值的参数（`const` 构造函数可以，枚举值是 const）：

```dart
    this.fuelPolicy = FuelPolicy.halt,
```

字段：

```dart
  /// What to do if the tank runs dry en route. Defaults to [FuelPolicy.halt] so
  /// saves written before this existed — whose voyages were paid for in full
  /// and therefore can never exhaust — load without a special case.
  final FuelPolicy fuelPolicy;
```

`copyWith` 加 `FuelPolicy? fuelPolicy` 参数并转发 `fuelPolicy: fuelPolicy ?? this.fuelPolicy`。

`fromJson` 加：

```dart
        fuelPolicy: json['fuelPolicy'] == null
            ? FuelPolicy.halt
            : fuelPolicyFromName(json['fuelPolicy'] as String),
```

`toJson` 加 `'fuelPolicy': fuelPolicy.name,`。

**3b.** `starward/lib/state/game_controller.dart` 在 `travelDurationTo` 之后加：

```dart
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
```

**3c.** 在 `// --- Energy helpers ---` 段加：

```dart
  /// Whether [cost] can be committed under [policy]. Null means yes.
  ///
  /// [FuelPolicy.refuse] demands the whole quote up front — the rule the game
  /// has always had. [FuelPolicy.halt] and [FuelPolicy.coast] only need a drop
  /// of fuel, because the ship is explicitly allowed to run dry en route. A
  /// completely empty tank moves nothing under any policy.
  LaunchResult? _launchGate(int cost, FuelPolicy policy) {
    if (policy == FuelPolicy.refuse) {
      return _player.energyBalance < cost
          ? LaunchResult.insufficientEnergy
          : null;
    }
    return _player.energyBalance <= 0 ? LaunchResult.insufficientEnergy : null;
  }
```

**3d.** `launchJourney` 换成：

```dart
  Future<LaunchResult> launchJourney(
    Planet target, {
    FuelPolicy onEmpty = FuelPolicy.refuse,
  }) async {
    if (target.id == _player.currentPlanetId) return LaunchResult.alreadyHere;
    if (isTraveling) return LaunchResult.alreadyTraveling;
    final cost = energyCostTo(target);
    final gate = _launchGate(cost, onEmpty);
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
      energyCost: cost,
      status: JourneyStatus.inProgress,
      fuelPolicy: onEmpty,
    );
    _activeJourney = journey;
    await _persist();
    notifyListeners();
    return LaunchResult.success;
  }
```

（`_spendEnergy` 那行在 Task 2 已经删掉；`_anchorHere()` 在 Task 5 已经加过，这里只是确认它在 `final departure` 之前。）

**3e.** `launchToStar` 同样处理：加 `{FuelPolicy onEmpty = FuelPolicy.refuse}` 参数，把 `if (_player.energyBalance < cost) return LaunchResult.insufficientEnergy;` 换成 `_launchGate(cost, onEmpty)` 的调用，`Journey(...)` 里加 `fuelPolicy: onEmpty`。

- [ ] **Step 4: 跑全量测试确认通过**

Run: `cd starward && flutter analyze && flutter test`
Expected: `No issues found`；全部通过。**默认参数是 `refuse`，所以既有的调用点行为完全不变**——`test/details_launch_test.dart`、`test/flight_panel_test.dart` 一条都不用改。

- [ ] **Step 5: 提交**

```bash
cd starward && git add lib/data/models/journey.dart lib/state/game_controller.dart test/fuel_out_test.dart
git commit -m "$(cat <<'EOF'
feat(starward): let an under-funded voyage depart on the player's terms

FuelPolicy is chosen per voyage and recorded on the Journey. refuse
keeps the old rule; halt and coast only need a drop of fuel, because
the ship is explicitly allowed to run dry en route. fuelExhaustProgress
is the closed-form exhaust point, read off the live balance so a
mid-flight top-up can push it past arrival.

Co-Authored-By: Claude Code <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: 燃料耗尽时结算并转入漂流

**Files:**
- Modify: `starward/lib/state/game_controller.dart`
  - 新增 `_voyageResolvesBy` / `_exhaustedBy` / `_applyFuelOut` / `_cruiseVelocityOf`（放在 `_reconcileJourney` 附近，约 :288）
  - 新增 `_settleTank`（放在 `_settleBurn` 之后）
  - `_reconcileJourney`（:288）：先判耗尽
  - `tick`（:365）：换成 `_voyageResolvesBy`
- Test: `starward/test/fuel_out_test.dart`（追加）

**Interfaces:**
- Consumes: `FuelPolicy` / `Journey.fuelPolicy` / `fuelExhaustProgressFor` / `fuelExhaustTime`（Task 8）、`_settleBurn`（Task 2）、`_positionAlong` / `_originPosOf` / `_destPosOf`（既有）、`PlayerState.driftVelocity` / `driftStartedAt`（Task 5）。
- Produces:
  - `bool GameController._voyageResolvesBy(Journey j, DateTime now)` —— 抵达**或**烧干
  - `bool GameController._exhaustedBy(Journey j, DateTime now)`
  - `void GameController._applyFuelOut(Journey journey, DateTime now)`
  - `Vec3 GameController._cruiseVelocityOf(Journey j)`
  - `void GameController._settleTank(Journey journey, DateTime now)`

- [ ] **Step 1: 写失败测试**

在 `starward/test/fuel_out_test.dart` 追加。分两处放：helper 放**顶层**（`void main()` 之前，紧跟 Task 8 的 `_boot` / `_drainBelow` / `_farthest` 之后），`group` 放 `main()` 里已有 group 的后面。

先补 import 与顶层 helper：

```dart
// --- 追加 import ---
// import 'package:starward/core/vec3.dart';

/// Docks at a planet, drains the tank, and launches an unaffordable voyage
/// under [policy]. Returns the controller and the target.
Future<(GameController, Planet)> _doomed(
  FakeClock clock,
  FuelPolicy policy,
) async {
  final c = await _boot(clock);
  final first = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
  await c.launchJourney(first);
  clock.advance(const Duration(hours: 12));
  c.tick();
  await c.acknowledgeArrival();

  await _drainBelow(c, clock, 30);
  final far = _farthest(c);
  expect(c.energyCostTo(far), greaterThan(c.energy));
  expect(await c.launchJourney(far, onEmpty: policy), LaunchResult.success);
  return (c, far);
}
```

然后在 `main()` 内追加测试：

```dart
  group('halt', () {
    test('stops at the exhaust point with an empty tank', () async {
      final clock = FakeClock(DateTime(2026));
      final (c, far) = await _doomed(clock, FuelPolicy.halt);
      final journey = c.activeJourney!;
      final origin = c.planetById(journey.originPlanetId)!.pos;
      final p = c.fuelExhaustProgress!;
      final balance = c.energy;
      final entriesBefore = c.energyLedger.length;

      // One second past the moment the tank runs dry.
      clock.advance(
          c.fuelExhaustTime(journey).difference(clock()) +
              const Duration(seconds: 1));
      c.tick();

      expect(c.activeJourney, isNull, reason: 'the voyage is over');
      expect(c.inDeepSpace, isTrue);
      expect(c.energy, 0, reason: 'the whole tank is gone');
      expect(c.driftVelocity.length, 0, reason: 'halt parks the ship');
      expect(c.energyLedger.length, entriesBefore + 1);
      expect(c.energyLedger.last.amount, -balance);

      final expected = origin + (far.pos - origin) * p;
      expect((c.playerPosition3D - expected).length, lessThan(0.001));
    });

    test('the ship does not creep forward afterwards', () async {
      final clock = FakeClock(DateTime(2026));
      final (c, _) = await _doomed(clock, FuelPolicy.halt);
      clock.advance(c.fuelExhaustTime(c.activeJourney!) - clock() +
          const Duration(seconds: 1));
      c.tick();
      final parked = c.playerPosition3D;
      clock.advance(const Duration(days: 30));
      expect(c.playerPosition3D.x, parked.x);
      expect(c.playerPosition3D.y, parked.y);
      expect(c.playerPosition3D.z, parked.z);
    });
  });

  group('coast', () {
    test('keeps moving at cruise speed and burns nothing more', () async {
      final clock = FakeClock(DateTime(2026));
      final (c, far) = await _doomed(clock, FuelPolicy.coast);
      final journey = c.activeJourney!;
      final origin = c.planetById(journey.originPlanetId)!.pos;
      final distance = (far.pos - origin).length;
      final seconds = journey.totalDuration.inMilliseconds / 1000;

      clock.advance(c.fuelExhaustTime(journey) - clock() +
          const Duration(seconds: 1));
      c.tick();

      expect(c.activeJourney, isNull);
      expect(c.inDeepSpace, isTrue);
      expect(c.energy, 0);
      final v = c.driftVelocity;
      expect(v.length, greaterThan(0));
      // Cruise speed is distance over duration — the same number the engine
      // would have flown at, so a coasting ship does not slow down.
      expect(v.length, closeTo(distance / seconds, 1e-6));

      final entries = c.energyLedger.length;
      final atStart = c.playerPosition3D;
      clock.advance(const Duration(seconds: 100));
      final later = c.playerPosition3D;
      expect((later - atStart).length, closeTo(v.length * 100, 0.01),
          reason: 'constant speed, no acceleration');

      clock.advance(const Duration(days: 3));
      c.tick();
      expect(c.energyLedger.length, entries,
          reason: 'coasting costs nothing to run');
    });

    test('a coasting ship ends up on the shell, never in a void', () async {
      final clock = FakeClock(DateTime(2026));
      final (c, _) = await _doomed(clock, FuelPolicy.coast);
      clock.advance(c.fuelExhaustTime(c.activeJourney!) - clock() +
          const Duration(seconds: 1));
      c.tick();

      // Fly the drift out to (and well past) the boundary.
      clock.advance(const Duration(days: 60));
      final r = c.playerPosition3D.length;
      final bound = math.max(c.universeRadius, r);
      expect(r, closeTo(bound, 1.0));
      expect(c.planets, isNotEmpty,
          reason: 'wherever it ends up, there is somewhere to go');
    });
  });

  group('refuse', () {
    test('an affordable voyage is untouched by any of this', () async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock);
      final target = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
      await c.launchJourney(target);
      final journey = c.activeJourney!;
      expect(journey.fuelPolicy, FuelPolicy.refuse);
      expect(c.fuelExhaustProgress, 1.0);

      clock.advance(journey.totalDuration + const Duration(seconds: 1));
      c.tick();
      expect(c.currentPlanetId, target.id, reason: 'it simply arrives');
      expect(c.driftVelocity.length, 0);
    });
  });
```

**注意**：`c.universeRadius` 需要 `GameController` 上一个转发（`_universe` 是私有的）。在 `deepSpaceOrigin3D` 附近加：

```dart
  /// The bounded-but-edgeless universe's radius in light-years. A drift is
  /// confined to this shell — see `Universe.universeRadius`.
  double get universeRadius => _universe.universeRadius;
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd starward && flutter test test/fuel_out_test.dart`
Expected: FAIL — `halt` 的 `expect(c.activeJourney, isNull)` 失败：飞船在空油箱上继续"飞"到了目的地。

- [ ] **Step 3: 实现**

**3a.** `_settleBurn` 之后加：

```dart
  /// Bills the entire tank.
  ///
  /// Used when fuel runs out, where "what is left" and "what burned" are the
  /// same number by definition — so this is exact, unlike re-deriving the burn
  /// from a rounded progress fraction.
  void _settleTank(Journey journey, DateTime now) {
    final drained = _player.energyBalance;
    if (drained <= 0) return;
    _player = _player.copyWith(energyBalance: 0);
    _energyLedger.add(EnergyTransaction(
      id: _newId('en'),
      type: EnergyTxType.travelCost,
      amount: -drained,
      createdAt: now,
      relatedObjectId: journey.id,
    ));
  }
```

**3b.** `_reconcileJourney` 换成（并加上三个新方法）：

```dart
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
      // The drift began when the tank emptied, not when the game noticed. A
      // player who was away for the whole coast gets the distance they missed.
      driftStartedAt: exhaustAt,
    );
    _rebuildNearby();
  }

  /// Cruise speed along a voyage's route, in ly/s. Constant — a coasting ship
  /// neither accelerates nor slows down.
  Vec3 _cruiseVelocityOf(Journey j) {
    final from = _originPosOf(j);
    final to = _destPosOf(j) ?? from;
    final seconds = j.totalDuration.inMilliseconds / 1000;
    if (seconds <= 0) return const Vec3(0, 0, 0);
    return (to - from) * (1 / seconds);
  }
```

**3c.** `tick` 换成：

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
    // Still travelling, or coasting: repaint without persisting. A coasting
    // ship may also have crossed into a new neighbourhood.
    _maybeRescanNearby();
    notifyListeners();
  }
```

**3d.** 加 `universeRadius` 转发（见 Step 1 的注意）。

- [ ] **Step 4: 跑全量测试确认通过**

Run: `cd starward && flutter analyze && flutter test`
Expected: `No issues found`；全部通过。

- [ ] **Step 5: 提交**

```bash
cd starward && git add lib/state/game_controller.dart test/fuel_out_test.dart
git commit -m "$(cat <<'EOF'
feat(starward): resolve a voyage when its tank runs dry

Reconciliation now checks exhaustion before arrival, so an under-funded
voyage ends at the exhaust point instead of flying on empty. halt parks
the ship there; coast hands it cruise velocity and a drift clock
anchored at the moment the tank emptied, so time spent away is not lost.

Co-Authored-By: Claude Code <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: 出发三选一对话框

**Files:**
- Create: `starward/lib/ui/journey/fuel_choice_dialog.dart`
- Modify: `starward/lib/data/models/engine.dart`（新增派生方法 `reachableLyFor`）
- Modify: `starward/lib/ui/galaxy/planet_details_sheet.dart:358-372`（能量不足分支）
- Modify: `starward/lib/ui/galaxy3d/galaxy_map_3d_page.dart:176`（`onGoToStar`）
- Test: `starward/test/fuel_out_test.dart`（追加）

**Interfaces:**
- Consumes: `FuelPolicy`（Task 8）、`GameController.energy`（Task 2）、`GameController.energyCostTo` / `distanceTo` / `energyCostToStar` / `distanceToStar` / `ship`（既有）、`launchJourney(target, onEmpty:)` / `launchToStar(id, onEmpty:)`（Task 8）。
- Produces:
  - `double Engine.reachableLyFor(int energy)` —— 这些能量能飞多远
  - `Future<FuelPolicy?> showFuelChoiceDialog(BuildContext context, {required int energy, required int cost, required double distanceLy, required Engine engine})` —— 返回选中的策略，玩家放弃时返回 null

- [ ] **Step 1: 写失败测试**

在 `starward/test/fuel_out_test.dart` 追加（文件顶部 import 区补 `package:flutter/material.dart`、`package:starward/data/models/engine.dart`、`package:starward/ui/journey/fuel_choice_dialog.dart`）：

```dart
  group('reachableLyFor', () {
    test('is the plain inverse of energyPerLy', () {
      expect(Engine.standard.reachableLyFor(100), 40.0);
      expect(Engine.standard.reachableLyFor(300), 120.0);
      expect(Engine.standard.reachableLyFor(0), 0.0);
    });
  });

  group('the fuel choice dialog', () {
    Future<FuelPolicy?> open(
      WidgetTester tester, {
      required int energy,
      required int cost,
    }) async {
      FuelPolicy? picked;
      var opened = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                opened = true;
                picked = await showFuelChoiceDialog(
                  context,
                  energy: energy,
                  cost: cost,
                  distanceLy: 100.0,
                  engine: Engine.standard,
                );
              },
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
      return picked;
    }

    testWidgets('spells out what the tank can and cannot reach',
        (tester) async {
      unawaited(open(tester, energy: 100, cost: 250));
      expect(find.textContaining('100 EN'), findsOneWidget);
      expect(find.textContaining('40.0 ly'), findsOneWidget);
      expect(find.textContaining('100.0 ly'), findsOneWidget);
      expect(find.text('放弃航行'), findsOneWidget);
      expect(find.text('耗尽后停下'), findsOneWidget);
      expect(find.text('耗尽后滑行'), findsOneWidget);
    });

    testWidgets('returns the policy the player tapped', (tester) async {
      final future = open(tester, energy: 100, cost: 250);
      await tester.tap(find.text('耗尽后滑行'));
      await tester.pumpAndSettle();
      expect(await future, FuelPolicy.coast);
    });

    testWidgets('an empty tank is only offered a way out', (tester) async {
      final future = open(tester, energy: 0, cost: 250);
      expect(find.text('耗尽后停下'), findsNothing,
          reason: 'no fuel means no voyage to run out of');
      expect(find.text('耗尽后滑行'), findsNothing);
      expect(find.text('放弃航行'), findsOneWidget);
      await tester.tap(find.text('放弃航行'));
      await tester.pumpAndSettle();
      expect(await future, isNull);
    });
  });
```

（`unawaited` 来自 `dart:async`，加进 import。）

- [ ] **Step 2: 跑测试确认失败**

Run: `cd starward && flutter test test/fuel_out_test.dart`
Expected: FAIL — `The method 'reachableLyFor' isn't defined for the type 'Engine'`（编译错误即失败）。

- [ ] **Step 3: 实现**

**3a.** `starward/lib/data/models/engine.dart`，在 `secondsFor` 之后加：

```dart
  /// How far [energy] will carry this engine, in light-years.
  ///
  /// The plain inverse of [energyPerLy]. This is the number the fuel-out dialog
  /// quotes back to the player ("you have 100 EN, that is 40.0 ly of the
  /// 100.0 ly trip"), so it lives on the engine rather than being recomputed
  /// wherever it is displayed.
  double reachableLyFor(int energy) => energy / energyPerLy;
```

**3b.** 新建 `starward/lib/ui/journey/fuel_choice_dialog.dart`：

```dart
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/engine.dart';
import '../../data/models/journey.dart';

/// Asks what to do about a voyage the ship cannot currently afford.
///
/// Returns the chosen [FuelPolicy], or null if the player backed out. Only
/// [FuelPolicy.halt] and [FuelPolicy.coast] are offered when there is fuel in
/// the tank: an empty ship has nothing to burn, so giving up (or going to
/// train) is the only honest answer.
Future<FuelPolicy?> showFuelChoiceDialog(
  BuildContext context, {
  required int energy,
  required int cost,
  required double distanceLy,
  required Engine engine,
}) {
  final reach = engine.reachableLyFor(energy);
  return showModalBottomSheet<FuelPolicy>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: StarPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                '能量不足以飞完全程',
                style: TextStyle(
                  color: StarColors.offWhite,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '你只有 $energy EN，可以飞 ${reach.toStringAsFixed(1)} ly，'
                '全程 ${distanceLy.toStringAsFixed(1)} ly。',
                style: const TextStyle(
                  color: StarColors.muted,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              _Choice(
                label: '放弃航行',
                detail: '不出发，回星图重新选目标',
                icon: Icons.close_rounded,
                onTap: () => Navigator.of(sheetContext).pop(),
              ),
              if (energy > 0) ...<Widget>[
                const SizedBox(height: 10),
                _Choice(
                  label: '耗尽后停下',
                  detail: '飞到燃料烧干的位置停下，漂浮于深空',
                  icon: Icons.anchor_rounded,
                  onTap: () =>
                      Navigator.of(sheetContext).pop(FuelPolicy.halt),
                ),
                const SizedBox(height: 10),
                _Choice(
                  label: '耗尽后滑行',
                  detail: '飞到燃料烧干后，以巡航速度继续滑行漫游',
                  icon: Icons.explore_rounded,
                  onTap: () =>
                      Navigator.of(sheetContext).pop(FuelPolicy.coast),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.detail,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String detail;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: StarColors.panelLight,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: <Widget>[
              Icon(icon, color: StarColors.cyan, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(label,
                        style: const TextStyle(
                          color: StarColors.offWhite,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        )),
                    const SizedBox(height: 2),
                    Text(detail,
                        style: const TextStyle(
                          color: StarColors.faint,
                          fontSize: 11,
                          height: 1.4,
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

**3c.** `planet_details_sheet.dart` 的能量不足分支换成（`_Button` 已支持 `onPressed: null` 的禁用态，但这里直接条件渲染更清楚）：

```dart
    // 4) Launch a new voyage.
    final cost = controller.energyCostTo(planet);
    final canAfford = controller.energy >= cost;
    if (!canAfford) {
      final hasFuel = controller.energy > 0;
      return Column(
        children: <Widget>[
          _Button(
            label: '能量不足（需 $cost EN · 现有 ${controller.energy} EN）',
            icon: Icons.bolt_rounded,
          ),
          const SizedBox(height: 10),
          // With fuel in the tank the player gets a say in how the voyage
          // ends; with none there is nothing to decide, so the only way
          // forward is training.
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

并在同一个 State 里加：

```dart
  /// Asks how an under-funded voyage should end, then launches with that
  /// policy. The quote is re-read after the dialog closes because a training
  /// reward could not have landed in between, but the balance is the same
  /// number the dialog quoted — reading it once keeps the copy and the gate in
  /// agreement.
  Future<void> _launchWithChoice(
    BuildContext context,
    GameController controller,
    Planet planet,
  ) async {
    final policy = await showFuelChoiceDialog(
      context,
      energy: controller.energy,
      cost: controller.energyCostTo(planet),
      distanceLy: controller.distanceTo(planet),
      engine: controller.ship.engine,
    );
    if (policy == null || !context.mounted) return;
    final result = await controller.launchJourney(planet, onEmpty: policy);
    if (!context.mounted) return;
    if (result == LaunchResult.success) {
      ShellScope.go(context, 1);
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageFor(result))),
      );
    }
  }
```

（该文件已 import `journey.dart` 吗？没有——`FuelPolicy` 经由 `fuel_choice_dialog.dart` 的返回值使用，需要显式 import 才能写 `final policy = ...` 的类型推导。实际上 `var` 推导即可，不需要 import；但 `onEmpty: policy` 要求 `FuelPolicy` 可见于参数类型检查——Dart 允许使用未 import 类型的值，只要不写出类型名。用 `final policy = await ...` 即可，无需新增 import。加 `import '../../ui/journey/fuel_choice_dialog.dart';`（按实际相对路径 `../journey/fuel_choice_dialog.dart`）是必须的，因为要调用 `showFuelChoiceDialog`。）

**3d.** `galaxy_map_3d_page.dart:176` 的 `onGoToStar` 换成：

```dart
            onGoToStar: (id) => _launchToStar(id),
```

并加：

```dart
  /// Launches to a star system, asking how the voyage should end when the
  /// ship cannot afford the whole trip.
  Future<void> _launchToStar(int hygId) async {
    final cost = _c.energyCostToStar(hygId);
    if (_c.energy < cost) {
      if (_c.energy <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('能量不足，先去做一组训练吧')),
        );
        return;
      }
      final policy = await showFuelChoiceDialog(
        context,
        energy: _c.energy,
        cost: cost,
        distanceLy: _c.distanceToStar(hygId),
        engine: _c.ship.engine,
      );
      if (policy == null || !mounted) return;
      final result = await _c.launchToStar(hygId, onEmpty: policy);
      if (!mounted) return;
      if (result == LaunchResult.success) {
        ShellScope.go(context, 1);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_launchMessage(result))),
        );
      }
      return;
    }
    final result = await _c.launchToStar(hygId);
    if (!mounted) return;
    if (result == LaunchResult.success) {
      ShellScope.go(context, 1);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_launchMessage(result))),
      );
    }
  }
```

（注意 `_openSystem` 里 `onGoToStar` 是 `Future<void> Function(int)`，返回 `_launchToStar(id)` 的 future 即可。`showFuelChoiceDialog` 需要 `import '../journey/fuel_choice_dialog.dart';`。）

- [ ] **Step 4: 跑全量测试确认通过**

Run: `cd starward && flutter analyze && flutter test`
Expected: `No issues found`；全部通过。

- [ ] **Step 5: 提交**

```bash
cd starward && git add lib/ui/journey/fuel_choice_dialog.dart lib/data/models/engine.dart lib/ui/galaxy/planet_details_sheet.dart lib/ui/galaxy3d/galaxy_map_3d_page.dart test/fuel_out_test.dart
git commit -m "$(cat <<'EOF'
feat(starward): ask how an under-funded voyage should end

Both launch entry points now open a three-way dialog instead of
dead-ending on "go train": give up, stop where the tank empties, or
coast on from there. Engine.reachableLyFor backs the distance the
dialog quotes, so the number the player reads comes from the same
engine that will fly the ship.

Co-Authored-By: Claude Code <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: 滑行状态页与 ticker

**Files:**
- Modify: `starward/lib/ui/journey/journey_page.dart`（`_sync` :57、`_buildStandby` :222、`_FlightPanel` :713、`_DriftDock` :553）
- Test: `starward/test/coast_test.dart`（追加）、`starward/test/flight_panel_test.dart`（追加）

**Interfaces:**
- Consumes: `GameController.driftVelocity` / `playerPosition3D` / `inDeepSpace`（Task 5）、`PlayerState.driftStartedAt`（Task 5）、`GameController.fuelExhaustProgressFor` / `fuelExhaustTime`（Task 8）、`GameController.installEngine`（既有）、`Engine`（既有）、`StarLabels.duration`（既有）。
- Produces:
  - `GameController.driftElapsed`（`Duration`，非滑行时为 `Duration.zero`）
  - `GameController.driftDistanceLy`（`double`，非滑行时为 0）
  - `bool GameController.isCoasting`（`driftVelocity.length > 0`）

- [ ] **Step 1: 写失败测试**

在 `starward/test/coast_test.dart` 追加：

```dart
  group('the coasting readout', () {
    test('measures from the moment the tank emptied', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _boot(clock, storage: storage);
      expect(c.isCoasting, isFalse);
      expect(c.driftElapsed, Duration.zero);
      expect(c.driftDistanceLy, 0);

      await _setDrift(storage, const Vec3(1, 0, 0), clock());
      final c2 = await _boot(clock, storage: storage);
      expect(c2.isCoasting, isTrue);
      expect(c2.driftElapsed, Duration.zero);

      clock.advance(const Duration(hours: 1));
      expect(c2.driftElapsed, const Duration(hours: 1));
      expect(c2.driftDistanceLy, closeTo(3600, 1e-9),
          reason: '1 ly/s for an hour');
    });
  });
```

（`_setDrift(MemoryStorage, Vec3, DateTime)` 是 Task 7 写的 helper，签名是 `Future<void> _setDrift(MemoryStorage storage, Vec3 velocity, DateTime startedAt)`——它改存档、再重新 boot，顺带证明漂流字段能过一遍 JSON。这里直接复用。）

再往 `starward/test/flight_panel_test.dart` 追加两个 widget test。飞行面板上的耗尽警告（§7）在这里测：它属于"航行中"这个状态，和 `coast_test.dart` 的滑行主题不是一回事；而这个文件里已经有现成的脚手架。

`test/flight_panel_test.dart` **已经存在**（它测的是返航时的飞行面板），文件里已经有 `_FakeClock`、`math.Random(3)` 的固定 seed、`StarLabels` 的 import 和"pump `HomeShell` → 点「航行」"这套脚手架。直接复用，只补两处 import：

```dart
// --- 追加 import ---
// import 'package:starward/data/models/engine.dart';
// import 'package:starward/data/models/journey.dart';   // FuelPolicy 在这里
```

顶层加一个 helper（放在 `_FakeClock` 旁边）：

```dart
/// A thousand energy per light-year makes any real hop unaffordable, which is
/// the cheapest way to reach a doomed voyage without draining the tank first.
const _greedy = Engine(
  id: 'test.greedy',
  name: '测试引擎',
  energyPerLy: 1000,
  travelSecondsPerLy: 37.5,
  minEnergyCost: 1,
  minTravelSeconds: 15,
);

Future<GameController> _bootAt(_FakeClock clock) async {
  final c = GameController(
    repository: GameRepository(MemoryStorage()),
    clock: clock.call,
    random: math.Random(3),
  );
  await c.init();
  return c;
}
```

然后在 `main()` 里追加两个 `testWidgets`：

```dart
  testWidgets('a doomed voyage warns on the flight panel', (tester) async {
    final clock = _FakeClock(DateTime(2026));
    final c = await _bootAt(clock);
    await c.installEngine(_greedy);

    // Seed 3: the nearest planet sits 2.5983 ly from the spawn, so the greedy
    // engine quotes 2598 EN against a 300 EN tank — p_exhaust ≈ 0.115.
    final target = c.planets
        .where((p) => p.id != c.currentPlanetId)
        .reduce((a, b) => c.distanceTo(a) < c.distanceTo(b) ? a : b);
    final cost = c.energyCostTo(target);
    expect(cost, 2598);
    expect(c.energy, 300);

    await c.launchJourney(target, onEmpty: FuelPolicy.coast);
    final journey = c.activeJourney!;

    await tester.pumpWidget(
      MaterialApp(home: GameScope(controller: c, child: const HomeShell())),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('航行').last);
    await tester.pump(const Duration(milliseconds: 100));

    // The warning counts down to the moment the tank runs dry, not the ETA.
    expect(find.textContaining('燃料将于'), findsOneWidget);
    expect(
      find.textContaining(
          StarLabels.duration(c.fuelExhaustTime(journey).difference(clock()))),
      findsOneWidget,
    );

    // And the bar carries a marker at p_exhaust.
    expect(find.byKey(const ValueKey('fuel-marker')), findsOneWidget);
  });

  testWidgets('an affordable voyage shows no warning', (tester) async {
    final clock = _FakeClock(DateTime(2026));
    final c = await _bootAt(clock);
    // Same target, standard engine: 2.5983 ly costs 6 EN out of 300.
    final target = c.planets
        .where((p) => p.id != c.currentPlanetId)
        .reduce((a, b) => c.distanceTo(a) < c.distanceTo(b) ? a : b);
    expect(c.energyCostTo(target), 6);

    await c.launchJourney(target);
    await tester.pumpWidget(
      MaterialApp(home: GameScope(controller: c, child: const HomeShell())),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('航行').last);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('燃料将于'), findsNothing);
    expect(find.byKey(const ValueKey('fuel-marker')), findsNothing);
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd starward && flutter test test/coast_test.dart test/flight_panel_test.dart`
Expected: `coast_test.dart` FAIL — `The getter 'isCoasting' isn't defined for the type 'GameController'`；`flight_panel_test.dart` 里新加的两个 FAIL — 找不到 `'燃料将于'` 文案与 `'fuel-marker'` key（`_FlightPanel` 还没加这两样），原有的返航测试仍然通过。

- [ ] **Step 3: 实现**

**3a.** `game_controller.dart`，在 `playerPosition3D` 之后加：

```dart
  /// Whether the ship is coasting — moving without burning anything.
  ///
  /// Zero velocity means parked in deep space, which is a different state: a
  /// parked ship has nowhere to be and nothing to report.
  bool get isCoasting => _player.driftVelocity.length > 0;

  /// How long the current drift has been running, or zero when parked.
  Duration get driftElapsed => isCoasting
      ? _now().difference(_player.driftStartedAt)
      : Duration.zero;

  /// How far the current drift has carried the ship, in light-years.
  double get driftDistanceLy =>
      isCoasting ? _player.driftVelocity.length * driftElapsed.inMilliseconds / 1000 : 0;
```

**3b.** `journey_page.dart` 的 `_sync` 换成：

```dart
  void _sync(GameController c) {
    final status = c.activeJourney?.status;
    // A coasting ship has no journey to resolve, but its marker still moves
    // and the drift readout still ticks — so the timer runs for both.
    final needsTimer =
        status == JourneyStatus.inProgress || c.isCoasting;
    if (needsTimer) {
      _tickTimer ??=
          Timer.periodic(const Duration(seconds: 1), (_) => c.tick());
    } else {
      _tickTimer?.cancel();
      _tickTimer = null;
    }
    if (status == JourneyStatus.inProgress || c.isCoasting) {
      if (!_flightTicker.isActive) _flightTicker.start();
    } else {
      if (_flightTicker.isActive) _flightTicker.stop();
    }
    if (status == JourneyStatus.arrived &&
        _lastStatus != JourneyStatus.arrived) {
      _reveal.forward(from: 0);
    }
    _lastStatus = status;
  }
```

**3c.** `_buildStandby` 里把 `drifting` 的定义与文案改成三态。把 `final drifting = current == null;` 换成：

```dart
    final coasting = c.isCoasting;
    final drifting = current == null;
```

星场那一段（`// No motion while idle`）换成：

```dart
        // Coasting keeps the star-stream moving; parked stays calm and static.
        Positioned.fill(
          child: StarfieldBackground(
            seed: 7,
            starCount: 150,
            scrollSpeed: coasting ? 0.35 : 0.0,
          ),
        ),
```

图标与标题：

```dart
                Icon(
                    coasting
                        ? Icons.explore_rounded
                        : (drifting
                            ? Icons.explore_rounded
                            : Icons.nightlight_round),
                    size: 44,
                    color: StarColors.cyanDim),
                const SizedBox(height: 16),
                Text(
                  coasting
                      ? '滑行中'
                      : (drifting ? '漂浮于深空' : '没有进行中的航行'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: StarColors.offWhite,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  coasting
                      ? '燃料已尽，飞船以巡航速度继续滑行。它不会减速，也不会再消耗能量。'
                      : (drifting
                          ? '你的飞船正静静悬停在星海之中，等待你选择第一个目的地。'
                          : '飞船正在 ${current.name} 停泊待命，等待下一段旅程。'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: StarColors.muted,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
```

停泊面板：

```dart
                if (coasting)
                  _CoastDock(controller: c)
                else if (drifting)
                  _DriftDock(controller: c)
                else
                  _CurrentDock(planet: current),
```

顶栏副标题：

```dart
          child: _TopBar(
              energy: c.energy, subtitle: coasting ? '滑行中' : (drifting ? '深空待命' : '待命')),
```

**3d.** 在 `_DriftDock` 之后新增 `_CoastDock`：

```dart
/// Shown in the standby state while the ship is coasting: where it is, how
/// fast it is going, and how far it has come since the tank emptied.
class _CoastDock extends StatelessWidget {
  const _CoastDock({required this.controller});

  final GameController controller;

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
              label: '当前坐标',
              value:
                  'X ${p.x.toStringAsFixed(1)}  Y ${p.y.toStringAsFixed(1)}  Z ${p.z.toStringAsFixed(1)}'),
        ],
      ),
    );
  }
}

class _CoastStat extends StatelessWidget {
  const _CoastStat({required this.label, required this.value});

  final String label;
  final String value;

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
              style: const TextStyle(
                color: StarColors.offWhite,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }
}
```

（`StarfieldBackground` 的 `scrollSpeed` 是既有参数，`_FlightPanel` 已用同样的方式驱动星场流动，见 `journey_page.dart` 里 `_buildFlight` 的 `StarfieldBackground`。）

**3e.** `_FlightPanel` 补上耗尽预警（§7）。在 `build` 开头、`final percent = ...` 旁边加三行：

```dart
    // `fuelExhaustProgressFor` is capped at 1, so anything below 1 means the
    // tank runs dry before arrival. Task 8 owns that number; the panel only
    // renders it — a warning line and a tick on the bar at the exhaust point.
    final exhaust = controller.fuelExhaustProgressFor(journey);
    final doomed = exhaust < 1;
    final exhaustAt = controller.fuelExhaustTime(journey);
```

把进度条那一整段 `ClipRRect(...)` 换成下面这段。`fit: StackFit.passthrough` 是必须的：默认的 `StackFit.loose` 会把松约束传给孩子，`LinearProgressIndicator` 在松约束下会缩成零宽；`passthrough` 让进度条照旧吃满 `_FlightPanel` 的整行宽度。`Clip.none` + `top/bottom: -2` 让标记上下各探出 2 px，读起来是一道刻度线而不是被裁掉的色块。

```dart
          LayoutBuilder(
            builder: (context, constraints) {
              final track = constraints.maxWidth;
              return Stack(
                fit: StackFit.passthrough,
                clipBehavior: Clip.none,
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: StarColors.panelLight,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          StarColors.cyan),
                    ),
                  ),
                  if (doomed)
                    Positioned(
                      left: (track * exhaust)
                          .clamp(0.0, math.max(track - 2, 0.0)),
                      top: -2,
                      bottom: -2,
                      child: Container(
                        key: const ValueKey('fuel-marker'),
                        width: 2,
                        color: StarColors.danger,
                      ),
                    ),
                ],
              );
            },
          ),
```

最后在 `Row`（`航程 ... / 能量 ...`）之后追加警告行：

```dart
          if (doomed) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                const Icon(Icons.warning_amber_rounded,
                    color: StarColors.danger, size: 13),
                const SizedBox(width: 6),
                Text(
                  '燃料将于 ${StarLabels.duration(exhaustAt.difference(now))} 后耗尽',
                  style: const TextStyle(
                      color: StarColors.danger, fontSize: 12),
                ),
              ],
            ),
          ],
```

（`math` 已经在 `journey_page.dart` 顶部以 `dart:math as math` 导入；`StarColors.danger` 是 `theme.dart` 既有色。能量读数本身不用动——`controller.energy` 是 Task 2 的派生 getter，`_sync` 的 ticker 每秒 `tick()` 一次，读数自动跟着掉。）

- [ ] **Step 4: 跑全量测试确认通过**

Run: `cd starward && flutter analyze && flutter test`
Expected: `No issues found`；全部通过。手动 `flutter run` 检查两件事：一次 `coast` 航程烧干后，航行页应当自动切到「滑行中」，星场开始流动，坐标与距离每秒递增；一次用 `installEngine` 之外的普通引擎飞一段"付不起"的航程（选「耗尽后滑行」），航行中面板应当出现橙红色「燃料将于 … 后耗尽」，进度条在 `p_exhaust` 处有一道竖线标记。

- [ ] **Step 4b: 给 README 补一段漂流模型说明**

阶段 3 结束时玩家已经能看见滑行了，模型值得写进 README。在 `starward/README.md` 的「航行状态逻辑」一节末尾追加：

```markdown
## 漂流（drift）

燃料烧完的飞船不再消失，也不再静止：`PlayerState` 存 `driftVelocity` 与
`driftStartedAt`，当前位置由 `lib/core/drift.dart` 的 `driftPositionAt` 从时间戳
闭式算出——先沿直线飞，撞上宇宙边界后贴着球面沿大圆滑行。所以离线一周回来，
位置依然只是 `(start, velocity, driftStartedAt, now)` 的函数，不需要常驻计时器，
也不需要任何"上次锚点"之类的额外存档状态。

`Universe.universeRadius` 取恒星距离的 p95（实测 3066 ly），而不是最外层恒星——
边界要落在恒星密度还够用的地方，否则漂到壳上的船会掉进空无一物的虚空。
边界只约束**漂流**，不约束动力航行：壳外那 5% 的恒星照样是合法目的地。

零速度时 `driftPositionAt` 原样返回 `start`，所以出生、停止航行、抵达恒星、
抵达坐标这四条既有的深空路径行为逐位不变。
```

（这一段是文档，不产生测试。写完直接进 Step 5 提交。）

- [ ] **Step 5: 提交**

```bash
cd starward && git add lib/state/game_controller.dart lib/ui/journey/journey_page.dart test/coast_test.dart test/flight_panel_test.dart README.md
git commit -m "$(cat <<'EOF'
feat(starward): give coasting its own standby screen

A drifting ship now reads as coasting rather than parked: the star
stream moves, the ticker keeps running, and the panel shows speed,
elapsed drift and distance travelled since the tank emptied. Parked
deep space is unchanged — zero velocity still means a still screen.

The flight panel also warns when the tank will not last the trip:
a countdown to the exhaust moment, and a tick on the progress bar
where the fuel runs out.

Co-Authored-By: Claude Code <noreply@anthropic.com>
EOF
)"
```

**阶段 C 检查点**：`flutter run` 手动走一遍三条路径——能量充足（行为不变）、能量不足选「耗尽后停下」（船停在半路，播报尚未接入，页面显示"漂浮于深空"）、能量不足选「耗尽后滑行」（页面切到"滑行中"，坐标每秒在变，去星图看飞船标记也在动）。

---

## 阶段 D — 播报

### Task 12: `DriftPath` 与途经星系

**Files:**
- Modify: `starward/lib/core/drift.dart`（新增 `DriftPath` / `ClosestApproach` / `PassedSystem` / `PassedSystems`；`driftPositionAt` 改为委托）
- Modify: `starward/lib/data/universe.dart`（新增 `passedSystemsAlong`）
- Test: `starward/test/drift_test.dart`（追加）

**Interfaces:**
- Consumes: `Vec3`、`HygStars`（`count` / `starId` / `positionOfIndex(i)`）、`Universe.stars` / `Universe.extraGalaxies`。
- Produces:
  - `class DriftPath { DriftPath({required Vec3 start, required Vec3 velocity, required double bound}); Vec3 positionAt(double elapsedSeconds); ClosestApproach closestApproach(Vec3 star, double upToSeconds, {double fromSeconds = 0}); double travelledBetween(double fromSeconds, double toSeconds); final double shellRadius; final double hitSeconds; }`
  - `class ClosestApproach { const ClosestApproach(this.distanceLy, this.seconds); }`
  - `class PassedSystem { const PassedSystem({required int hygId, required double distanceLy, required double seconds}); }`
  - `class PassedSystems { const PassedSystems({required int count, required List<PassedSystem> nearest}); static const PassedSystems none; }`
  - `PassedSystems Universe.passedSystemsAlong({required DriftPath path, required double upToSeconds, double fromSeconds = 0, double radiusLy = 20, int named = 8})`

- [ ] **Step 1: 写失败测试**

在 `starward/test/drift_test.dart` 追加（import 区补 `dart:typed_data`、`package:starward/data/hyg_catalog.dart`、`package:starward/data/universe.dart`、`package:starward/core/vec3.dart` 已有）：

```dart
/// A handful of stars at hand-picked positions — no catalogue, no assets, so
/// every distance below is exact.
HygStars _synthetic(List<Vec3> positions) {
  final n = positions.length;
  final xyz = Float32List(n * 3);
  final ids = Int32List(n);
  for (var i = 0; i < n; i++) {
    xyz[i * 3] = positions[i].x;
    xyz[i * 3 + 1] = positions[i].y;
    xyz[i * 3 + 2] = positions[i].z;
    ids[i] = 1000 + i;
  }
  return HygStars(
    count: n,
    starId: ids,
    xyz: xyz,
    mag: Float32List(n),
    color: Int32List(n),
    named: const <String, HygNamed>{},
    indexById: <int, int>{for (var i = 0; i < n; i++) 1000 + i: i},
  );
}

void main() {
  // ... 已有的 driftPositionAt group 保持不变 ...

  group('DriftPath', () {
    test('agrees with driftPositionAt on every leg', () {
      final path = DriftPath(
        start: const Vec3(50, 0, 0),
        velocity: const Vec3(0, 1, 0),
        bound: 100,
      );
      expect(path.hitSeconds, closeTo(86.6025, 0.0001));
      expect(path.shellRadius, 100);
      for (final s in <double>[0, 40, 86.6025, 100, 900]) {
        final a = path.positionAt(s);
        final b = driftPositionAt(
          start: const Vec3(50, 0, 0),
          velocity: const Vec3(0, 1, 0),
          elapsedSeconds: s,
          bound: 100,
        );
        expectVec(a, b, tol: 1e-9);
      }
    });

    test('closest approach on the straight leg, clamped to the leg', () {
      final path = DriftPath(
        start: const Vec3(0, 0, 0),
        velocity: const Vec3(1, 0, 0),
        // Huge shell: the whole window is straight-line flight.
        bound: 1e9,
      );
      // Star 10 ly off the track, level with s = 50.
      final near = path.closestApproach(const Vec3(50, 10, 0), 100);
      expect(near.distanceLy, closeTo(10, 1e-9));
      expect(near.seconds, closeTo(50, 1e-9));

      // Star behind the start: the nearest point is s = 0, not s = -20.
      final behind = path.closestApproach(const Vec3(-20, 5, 0), 100);
      expect(behind.distanceLy, closeTo(math.sqrt(425), 1e-9));
      expect(behind.seconds, 0);
    });

    test('closest approach on the arc, at the star\'s own bearing', () {
      // Same geometry as the driftPositionAt tests: shell hit at s = 86.6025
      // on (50, 86.6025, 0), sliding at 0.5 ly/s around a 100 ly circle.
      final path = DriftPath(
        start: const Vec3(50, 0, 0),
        velocity: const Vec3(0, 1, 0),
        bound: 100,
      );

      // A star sitting exactly on the arc, 90° round from the impact point.
      final onArc = path.closestApproach(const Vec3(-86.6025, 50, 0), 500);
      expect(onArc.distanceLy, closeTo(0, 0.001));
      // 86.6025 + 100·(π/2)/0.5
      expect(onArc.seconds, closeTo(400.7618, 0.001));

      // A star 30 ly off the arc's plane, at 30° round.
      final offArc = path.closestApproach(const Vec3(0, 100, 30), 500);
      expect(offArc.distanceLy, closeTo(30, 0.001));
      // 86.6025 + 100·(π/6)/0.5
      expect(offArc.seconds, closeTo(191.3223, 0.001));
    });

    test('a window that stops early clamps to the end of the arc', () {
      final path = DriftPath(
        start: const Vec3(50, 0, 0),
        velocity: const Vec3(0, 1, 0),
        bound: 100,
      );
      // The star's own bearing is at s ≈ 191.3, past this window.
      final cut = path.closestApproach(const Vec3(0, 100, 30), 150);
      expect(cut.distanceLy, closeTo(36.3968, 0.001));
      expect(cut.seconds, closeTo(150, 1e-9));
    });

    test('a window that starts late clamps to the start of the arc', () {
      final path = DriftPath(
        start: const Vec3(50, 0, 0),
        velocity: const Vec3(0, 1, 0),
        bound: 100,
      );
      // The star's own bearing is at s ≈ 191.3, before this window opens.
      final cut = path.closestApproach(const Vec3(0, 100, 30), 500,
          fromSeconds: 300);
      // Arc at s = 300 → θ = 0.5·(300-86.6025)/100 = 1.0669873 rad.
      expect(cut.seconds, closeTo(300, 1e-9));
      expect(cut.distanceLy, closeTo(61.4783, 0.001));
    });

    test('travelledBetween adds up both legs', () {
      final path = DriftPath(
        start: const Vec3(50, 0, 0),
        velocity: const Vec3(0, 1, 0),
        bound: 100,
      );
      // Wholly on the straight leg: 1 ly/s.
      expect(path.travelledBetween(0, 40), closeTo(40, 1e-9));
      // Straddling the shell hit: 86.6025 ly of line at 1 ly/s, then the rest
      // of the window as arc at 0.5 ly/s.
      expect(path.travelledBetween(0, 100), closeTo(93.3013, 1e-3));
      // A slice that starts exactly at the hit is arc only: 100 s at 0.5 ly/s.
      expect(path.travelledBetween(path.hitSeconds, path.hitSeconds + 100),
          closeTo(50, 1e-9));
      // A parked ship covers no ground.
      expect(
        DriftPath(
          start: const Vec3(50, 0, 0),
          velocity: const Vec3(0, 0, 0),
          bound: 100,
        ).travelledBetween(0, 1e6),
        0,
      );
    });
  });

  group('passedSystemsAlong', () {
    // One path, four stars: two essentially on it, one 30 ly off, one far away.
    final path = DriftPath(
      start: const Vec3(50, 0, 0),
      velocity: const Vec3(0, 1, 0),
      bound: 100,
    );
    final stars = _synthetic(<Vec3>[
      const Vec3(50, 10, 4), // 4 ly off the straight leg
      const Vec3(-86.6025, 50, 0), // on the arc, 90° round
      const Vec3(0, 100, 30), // 30 ly off the arc
      const Vec3(0, 0, 5000), // nowhere near
    ]);
    final universe = Universe(stars);

    test('counts every system inside the radius, closest first', () {
      final passed = universe.passedSystemsAlong(
        path: path,
        upToSeconds: 500,
        radiusLy: 35,
      );
      expect(passed.count, 3, reason: 'the far star is not passed');
      expect(passed.nearest.length, 3);
      expect(passed.nearest.map((p) => p.hygId).toList(), <int>[1001, 1000, 1002]);
      expect(passed.nearest[0].distanceLy, closeTo(0, 0.001));
      expect(passed.nearest[1].distanceLy, closeTo(4, 0.001));
      expect(passed.nearest[2].distanceLy, closeTo(30, 0.001));
      expect(passed.nearest[1].seconds, closeTo(10, 0.001));
    });

    test('a tighter radius drops the distant ones', () {
      final passed = universe.passedSystemsAlong(
        path: path,
        upToSeconds: 500,
        radiusLy: 20,
      );
      expect(passed.count, 2);
      expect(passed.nearest.map((p) => p.hygId).toList(), <int>[1001, 1000]);
    });

    test('the window bounds what counts as passed', () {
      // At 150 s the ship has only just started sliding, so the arc star 90°
      // round is still 117 ly away — but the 30 ly star is nearly in reach.
      final passed = universe.passedSystemsAlong(
        path: path,
        upToSeconds: 150,
        radiusLy: 40,
      );
      expect(passed.nearest.map((p) => p.hygId).toList(), <int>[1000, 1002]);
      expect(passed.count, 2);
    });

    test('a slice window excludes what an earlier report already covered', () {
      // The first report covered s ∈ [0, 200]; this one picks up from there,
      // so only the arc star at s ≈ 400.8 is still ahead.
      final passed = universe.passedSystemsAlong(
        path: path,
        upToSeconds: 500,
        fromSeconds: 200,
        radiusLy: 25,
      );
      expect(passed.count, 1);
      expect(passed.nearest.single.hygId, 1001);
      expect(passed.nearest.single.seconds, closeTo(400.7618, 0.001));
    });

    test('names at most `named`, but counts them all', () {
      final passed = universe.passedSystemsAlong(
        path: path,
        upToSeconds: 500,
        radiusLy: 35,
        named: 2,
      );
      expect(passed.count, 3);
      expect(passed.nearest.length, 2);
      expect(passed.nearest.map((p) => p.hygId).toList(), <int>[1001, 1000]);
    });
  });
}
```

（注意：新 `main()` 替换原有 `main()`，`driftPositionAt` 的 group 原样保留在同一个 `main()` 里。）

- [ ] **Step 2: 跑测试确认失败**

Run: `cd starward && flutter test test/drift_test.dart`
Expected: FAIL — `The method 'closestApproach' isn't defined for the type 'DriftPath'`（编译错误即失败）。

- [ ] **Step 3: 实现**

**3a.** 重写 `starward/lib/core/drift.dart` 为（`driftPositionAt` 的签名与语义完全不变，只是改为委托给 `DriftPath`，这样撞击时刻的二次方程只有一份）：

```dart
import 'dart:math' as math;

import 'vec3.dart';

/// Constant-velocity drift through a universe that is bounded but edgeless.
///
/// A coasting ship flies in a straight line until it meets the shell of radius
/// [bound], then slides along that shell on a great circle. It therefore never
/// reaches anywhere emptier than the shell — which is the whole point: an
/// unconstrained drift ends up in a void with nothing left to visit.
///
/// Thin wrapper over [DriftPath]; kept because "where is the ship now" is the
/// question callers ask most, and it reads better without the object.
Vec3 driftPositionAt({
  required Vec3 start,
  required Vec3 velocity, // light-years per second
  required double elapsedSeconds,
  required double bound,
}) =>
    DriftPath(start: start, velocity: velocity, bound: bound)
        .positionAt(elapsedSeconds);

/// A coasting ship's trajectory: a straight leg out to the shell, then a
/// great-circle slide along it.
///
/// Both legs are closed-form, which is what lets the game ask "where was the
/// ship at time t" and "which systems did it pass" without ever stepping
/// through the motion. Nothing is accumulated: the path is a pure function of
/// its three inputs, so a week offline costs one evaluation.
class DriftPath {
  DriftPath({
    required this.start,
    required this.velocity,
    required double bound,
  })  : _speed = velocity.length,
        // A ship that starts outside the shell keeps its own radius rather
        // than being teleported inward to `bound` — it simply stops widening.
        shellRadius = math.max(bound, start.length) {
    if (_speed == 0) {
      hitSeconds = 0;
      _tangentialSpeed = 0;
      _normal = const Vec3(0, 0, 0);
      _tangent = const Vec3(0, 0, 0);
      return;
    }
    final startLen = start.length;
    if (startLen >= bound) {
      // Already on (or beyond) the shell: there is no straight leg.
      hitSeconds = 0;
    } else {
      // |start + v·s|² = bound²  →  a·s² + b·s + c = 0, with c < 0 here (the
      // ship starts inside), so the positive root is always the exit.
      final a = _speed * _speed;
      final b = 2 * start.dot(velocity);
      final c = startLen * startLen - bound * bound;
      final disc = b * b - 4 * a * c;
      hitSeconds = disc <= 0 ? 0 : (-b + math.sqrt(disc)) / (2 * a);
    }
    final hit = start + velocity * hitSeconds;
    final n = hit.normalized;
    _normal = n;
    final tangential = velocity - n * velocity.dot(n);
    _tangentialSpeed = tangential.length;
    _tangent =
        _tangentialSpeed < 1e-12 ? const Vec3(0, 0, 0) : tangential.normalized;
  }

  final Vec3 start;
  final Vec3 velocity;

  /// The radius the ship is actually confined to: `max(bound, |start|)`.
  final double shellRadius;

  /// Seconds from the start of the drift until the shell is met. Zero when the
  /// ship already begins on the shell; the straight leg is empty then.
  late final double hitSeconds;

  final double _speed;
  late final double _tangentialSpeed;
  late final Vec3 _normal;
  late final Vec3 _tangent;

  /// Where the ship is [elapsedSeconds] into the drift.
  Vec3 positionAt(double elapsedSeconds) {
    if (elapsedSeconds <= 0 || _speed == 0) return start;
    if (elapsedSeconds <= hitSeconds) return start + velocity * elapsedSeconds;
    return _onShell(elapsedSeconds - hitSeconds);
  }

  /// Position after [seconds] of sliding along the shell.
  Vec3 _onShell(double seconds) {
    final hit = start + velocity * hitSeconds;
    // Purely radial impact — no tangential component to slide with, so the
    // ship sits at this point. Degenerate and intentional; see the test.
    if (_tangentialSpeed < 1e-12) return hit;
    final theta = _tangentialSpeed * seconds / shellRadius;
    return (_normal * math.cos(theta) + _tangent * math.sin(theta)) *
        shellRadius;
  }

  /// How close [star] comes to the path between [fromSeconds] and
  /// [upToSeconds] of it, and when.
  ///
  /// The window matters because reports cover a slice of a drift rather than
  /// the whole thing: a long coast that laps the shell would otherwise report
  /// the same system again on every report.
  ///
  /// One evaluation per star — no stepping — which is what makes it affordable
  /// to run over the whole catalogue.
  ClosestApproach closestApproach(
    Vec3 star,
    double upToSeconds, {
    double fromSeconds = 0,
  }) {
    final to = math.max(upToSeconds, 0.0);
    final from = fromSeconds.clamp(0.0, to);
    if (to <= 0 || _speed == 0) {
      return ClosestApproach((star - start).length, 0);
    }

    var bestSeconds = from;
    var bestDistance = double.infinity;

    // --- straight leg: s in [from, min(to, hitSeconds)] ---
    final straightEnd = math.min(to, hitSeconds);
    if (straightEnd > from) {
      final d0 = start - star;
      // |d0 + v·s|² is minimised at s* = -(d0·v)/|v|², clamped to the leg.
      final s = (-d0.dot(velocity) / (_speed * _speed)).clamp(from, straightEnd);
      bestSeconds = s;
      bestDistance = (d0 + velocity * s).length;
    } else {
      bestSeconds = from;
      bestDistance = (star - positionAt(from)).length;
    }

    // --- arc leg: s in (max(from, hitSeconds), to] ---
    if (to > hitSeconds && _tangentialSpeed >= 1e-12) {
      final fromArc = math.max(from, hitSeconds);
      final thetaFrom = _tangentialSpeed * (fromArc - hitSeconds) / shellRadius;
      final thetaTo = _tangentialSpeed * (to - hitSeconds) / shellRadius;
      final wn = star.dot(_normal);
      final wt = star.dot(_tangent);
      if (wn * wn + wt * wt > 0) {
        // The star's bearing in the great circle's plane. The distance to the
        // circle is minimised there, so the answer over a bounded arc is either
        // that bearing or one of the arc's two ends — evaluate both ends and
        // every equivalent bearing that lands inside, take the best.
        final bearing = math.atan2(wt, wn);
        final candidates = <double>[thetaFrom, thetaTo];
        for (var lap = -1; lap <= 2; lap++) {
          final t = bearing + 2 * math.pi * lap;
          if (t > thetaFrom && t < thetaTo) candidates.add(t);
        }
        for (final t in candidates) {
          final p = (_normal * math.cos(t) + _tangent * math.sin(t)) *
              shellRadius;
          final d = (p - star).length;
          if (d < bestDistance) {
            bestDistance = d;
            bestSeconds = hitSeconds + t * shellRadius / _tangentialSpeed;
          }
        }
      }
    }

    return ClosestApproach(bestDistance, bestSeconds);
  }

  /// How far the ship travels between [fromSeconds] and [toSeconds] of the
  /// drift, in light-years.
  ///
  /// Arc length, not the straight-line distance between the two points: on the
  /// shell those differ, and "how far did I fly" means the former.
  double travelledBetween(double fromSeconds, double toSeconds) {
    final to = math.max(toSeconds, 0.0);
    final from = fromSeconds.clamp(0.0, to);
    if (_speed == 0 || to <= from) return 0;
    final straight =
        math.max(math.min(to, hitSeconds) - math.min(from, hitSeconds), 0.0);
    final arc = math.max(to - math.max(from, hitSeconds), 0.0);
    return _speed * straight + _tangentialSpeed * arc;
  }
}

/// How close something came to a [DriftPath], and when.
class ClosestApproach {
  const ClosestApproach(this.distanceLy, this.seconds);

  final double distanceLy;

  /// Seconds from the start of the drift to the closest moment.
  final double seconds;
}

/// A star system a drift passed close to.
class PassedSystem {
  const PassedSystem({
    required this.hygId,
    required this.distanceLy,
    required this.seconds,
  });

  final int hygId;
  final double distanceLy;
  final double seconds;
}

/// What a drift passed.
class PassedSystems {
  const PassedSystems({required this.count, required this.nearest});

  /// Distinct systems that came within the pass radius. A lapping drift counts
  /// each system once no matter how many times it went by, because the distance
  /// used is the closest approach over the whole window.
  final int count;

  /// The closest few, ascending by distance.
  final List<PassedSystem> nearest;

  static const PassedSystems none =
      PassedSystems(count: 0, nearest: <PassedSystem>[]);
}
```

**3b.** `starward/lib/data/universe.dart` 在 `planetsNear` 之后加（`import '../core/drift.dart';` 需要补上——`lib/data` 依赖 `lib/core` 是允许的方向）：

```dart
  /// The star systems a drift passed within [radiusLy] of, between
  /// [fromSeconds] and [upToSeconds] of it.
  ///
  /// A full scan of the catalogue, one closed-form closest-approach per star —
  /// a few milliseconds, which is affordable because it only runs when a
  /// report is being written, not per frame.
  PassedSystems passedSystemsAlong({
    required DriftPath path,
    required double upToSeconds,
    double fromSeconds = 0,
    double radiusLy = 20,
    int named = 8,
  }) {
    var count = 0;
    final nearest = <PassedSystem>[];
    void scan(HygStars set) {
      for (var i = 0; i < set.count; i++) {
        final approach = path.closestApproach(
          set.positionOfIndex(i),
          upToSeconds,
          fromSeconds: fromSeconds,
        );
        if (approach.distanceLy > radiusLy) continue;
        count++;
        final hit = PassedSystem(
          hygId: set.starId[i],
          distanceLy: approach.distanceLy,
          seconds: approach.seconds,
        );
        // Insertion-sorted and capped: only the closest [named] are ever shown,
        // so there is no reason to sort 120k distances.
        var at = nearest.length;
        while (at > 0 && nearest[at - 1].distanceLy > hit.distanceLy) {
          at--;
        }
        if (at >= named) continue;
        nearest.insert(at, hit);
        if (nearest.length > named) nearest.removeLast();
      }
    }

    scan(stars);
    for (final g in extraGalaxies) {
      scan(g);
    }
    return PassedSystems(count: count, nearest: nearest);
  }
```

- [ ] **Step 4: 跑全量测试确认通过**

Run: `cd starward && flutter analyze && flutter test`
Expected: `No issues found`；全部通过。**`test/drift_test.dart` 里 Task 4 写的六个 `driftPositionAt` 测试必须仍然全绿**——它们是这次重构的回归网。

- [ ] **Step 5: 提交**

```bash
cd starward && git add lib/core/drift.dart lib/data/universe.dart test/drift_test.dart
git commit -m "$(cat <<'EOF'
feat(starward): ask a drift path which systems it passed

DriftPath wraps the same closed-form geometry as a queryable object, so
closestApproach answers "how near did this star come, and when" in one
evaluation per star. driftPositionAt now delegates to it rather than
keeping a second copy of the shell-hit quadratic.

Co-Authored-By: Claude Code <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: `DriftReport` 与离线补算

**Files:**
- Create: `starward/lib/data/models/drift_report.dart`
- Modify: `starward/lib/data/game_repository.dart`（`GameSave.pendingDriftReport` + JSON）
- Modify: `starward/lib/state/game_controller.dart`
  - 新增 `_pendingDriftReport` 字段（紧邻 `_activeJourney`）
  - 新增 `driftPath` / `_driftSecondsAt` / `buildDriftReport` / `pendingDriftReport` / `requestDriftReport` / `acknowledgeDriftReport` / `passedSystemsSoFar`（放在 `driftDistanceLy` 之后）
  - `_applyFuelOut`（Task 9）：生成 `fuelOut` 播报
  - `init()`：补算离线 `drift` 播报
  - `_persist` / `resetSave`：带上 `pendingDriftReport`
- Test: `starward/test/drift_report_test.dart`（新建）

**Interfaces:**
- Consumes: `DriftPath` / `PassedSystem` / `PassedSystems` / `Universe.passedSystemsAlong`（Task 12）、`GameController.isCoasting` / `driftElapsed` / `playerPosition3D` / `_universe`（Task 5/6）、`_applyFuelOut` / `_cruiseVelocityOf`（Task 9）、`_originPosOf` / `_destPosOf`（既有）。
- Produces:
  - `enum DriftReportKind { fuelOut, drift }`
  - `class DriftReport { const DriftReport({required DriftReportKind kind, required DateTime from, required DateTime to, required Duration elapsed, required double distanceLy, required Vec3 fromPos, required Vec3 toPos, required int passedCount, required List<PassedSystem> nearest, required bool hitBoundary}); }` + `toJson` / `fromJson`
  - `GameSave.pendingDriftReport`（`DriftReport?`）
  - `DriftPath? GameController.driftPath`
  - `DriftReport? GameController.buildDriftReport()`
  - `DriftReport? GameController.pendingDriftReport`
  - `Future<void> GameController.requestDriftReport()`
  - `Future<void> GameController.acknowledgeDriftReport()`
  - `PassedSystems GameController.passedSystemsSoFar`

- [ ] **Step 1: 写失败测试**

新建 `starward/test/drift_report_test.dart`：

```dart
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:starward/core/vec3.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/models/drift_report.dart';
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

Future<GameController> _boot(FakeClock clock, MemoryStorage storage) async {
  final c = GameController(
    repository: GameRepository(storage),
    clock: clock.call,
    random: math.Random(5),
  );
  await c.init();
  return c;
}

/// Rewrites the saved drift so the ship is coasting from a known anchor, then
/// reboots. Going through the save rather than a setter also proves the drift
/// fields round-trip through JSON.
Future<GameController> _drifting(
  FakeClock clock,
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
  return _boot(clock, storage);
}

/// A greedy engine makes even a short hop unaffordable on a full tank — a
/// cheaper route to a doomed voyage than draining 300 EN a hop at a time.
const _greedy = Engine(
  id: 'test.greedy',
  name: '测试引擎',
  energyPerLy: 1000,
  travelSecondsPerLy: 37.5,
  minEnergyCost: 1,
  minTravelSeconds: 15,
);

void main() {
  group('a parked ship is never reported on', () {
    test('a brand new player', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _boot(clock, storage);
      // Without this guard `driftStartedAt` defaults to the epoch and every new
      // player would be told they had been drifting for fifty-six years.
      expect(c.pendingDriftReport, isNull);
    });

    test('a player who comes back much later without moving', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      await _boot(clock, storage);
      clock.advance(const Duration(days: 30));
      final c2 = await _boot(clock, storage);
      expect(c2.pendingDriftReport, isNull);
    });

    test('after aborting a voyage', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _boot(clock, storage);
      final target = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
      await c.launchJourney(target);
      clock.advance(const Duration(minutes: 1));
      await c.abortJourney();
      expect(c.inDeepSpace, isTrue);
      expect(c.isCoasting, isFalse);
      clock.advance(const Duration(days: 7));
      final c2 = await _boot(clock, storage);
      expect(c2.pendingDriftReport, isNull);
    });
  });

  group('the offline drift report', () {
    test('measures the window the player could not watch', () async {
      final start = DateTime(2026, 3, 1, 9);
      final clock = FakeClock(start);
      final storage = MemoryStorage();
      await _boot(clock, storage);
      final c = await _drifting(clock, storage, const Vec3(1, 0, 0), start);
      expect(c.pendingDriftReport, isNull,
          reason: 'no time has passed yet');

      clock.advance(const Duration(minutes: 10));
      final c2 = await _boot(clock, storage);
      final r = c2.pendingDriftReport!;

      expect(r.kind, DriftReportKind.drift);
      expect(r.from, start);
      expect(r.to, clock());
      expect(r.elapsed, const Duration(minutes: 10));
      expect(r.distanceLy, closeTo(600, 1e-6));
      expect(r.fromPos.x, closeTo(c2.playerPosition3D.x - 600, 1e-6));
      expect(r.toPos.x, closeTo(c2.playerPosition3D.x, 1e-6));
      expect(r.hitBoundary, isFalse, reason: '600 ly, well inside the shell');
    });

    test('a drift that reached the shell says so', () async {
      final start = DateTime(2026, 3, 1);
      final clock = FakeClock(start);
      final storage = MemoryStorage();
      await _boot(clock, storage);
      // Anchored just inside the shell, heading straight out at 1 ly/s.
      final raw = await storage.read('starward.save.v2');
      final json = jsonDecode(raw!) as Map<String, dynamic>;
      final player = json['player'] as Map<String, dynamic>;
      player['startX'] = 3000.0;
      player['startY'] = 0.0;
      player['startZ'] = 0.0;
      player['driftVelocityX'] = 1.0;
      player['driftVelocityY'] = 0.0;
      player['driftVelocityZ'] = 0.0;
      player['driftStartedAt'] = start.millisecondsSinceEpoch;
      await storage.write('starward.save.v2', jsonEncode(json));

      clock.advance(const Duration(days: 1));
      final c = await _boot(clock, storage);
      final r = c.pendingDriftReport!;
      expect(r.hitBoundary, isTrue);
      expect(r.toPos.length, closeTo(c.universeRadius, 1.0));
      // Purely radial: it stops at the point where it met the shell rather
      // than sliding, so it travelled exactly the gap it had left.
      expect(r.distanceLy, closeTo(c.universeRadius - 3000, 1.0));
    });

    test('it is shown once and then never again', () async {
      final start = DateTime(2026, 3, 1);
      final clock = FakeClock(start);
      final storage = MemoryStorage();
      await _boot(clock, storage);
      await _drifting(clock, storage, const Vec3(1, 0, 0), start);
      clock.advance(const Duration(minutes: 5));
      final c = await _boot(clock, storage);
      expect(c.pendingDriftReport, isNotNull);

      await c.acknowledgeDriftReport();
      expect(c.pendingDriftReport, isNull);

      clock.advance(const Duration(minutes: 5));
      final c2 = await _boot(clock, storage);
      expect(c2.pendingDriftReport, isNull,
          reason: 'the same drift is not reported twice');
    });

    test('it survives a kill before the player ever read it', () async {
      final start = DateTime(2026, 3, 1);
      final clock = FakeClock(start);
      final storage = MemoryStorage();
      await _boot(clock, storage);
      await _drifting(clock, storage, const Vec3(1, 0, 0), start);
      clock.advance(const Duration(minutes: 30));

      // Booted once (which queued the report) but the app was killed before the
      // sheet was opened.
      final c = await _boot(clock, storage);
      expect(c.pendingDriftReport, isNotNull);
      final c2 = await _boot(clock, storage);
      expect(c2.pendingDriftReport, isNotNull,
          reason: 'queued reports are persisted, not rebuilt from scratch');
      expect(c2.pendingDriftReport!.elapsed, const Duration(minutes: 30));
    });

    test('the coasting screen can ask for one on demand', () async {
      final start = DateTime(2026, 3, 1);
      final clock = FakeClock(start);
      final storage = MemoryStorage();
      await _boot(clock, storage);
      await _drifting(clock, storage, const Vec3(1, 0, 0), start);
      clock.advance(const Duration(hours: 1));
      final c = await _boot(clock, storage);
      await c.acknowledgeDriftReport();
      expect(c.pendingDriftReport, isNull);

      clock.advance(const Duration(hours: 4));
      await c.requestDriftReport();
      expect(c.pendingDriftReport!.elapsed, const Duration(hours: 5),
          reason: 'the whole drift so far, not just since the last report');
    });
  });

  group('the fuel-out report', () {
    test('covers the powered leg, not the drift that follows', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _boot(clock, storage);
      await c.installEngine(_greedy);

      final target = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
      final origin = c.playerPosition3D;
      final distanceLy = c.distanceTo(target);
      final cost = c.energyCostTo(target);
      final balance = c.energy;
      expect(balance, 300);
      expect(cost, greaterThan(balance), reason: 'precondition: unaffordable');

      expect(await c.launchJourney(target, onEmpty: FuelPolicy.coast),
          LaunchResult.success);
      final journey = c.activeJourney!;
      final exhaustAt = c.fuelExhaustTime(journey);
      expect(c.fuelExhaustProgress, closeTo(balance / cost, 1e-12));

      clock.advance(exhaustAt.difference(clock()) + const Duration(seconds: 1));
      c.tick();
      expect(c.isCoasting, isTrue);

      final r = c.pendingDriftReport!;
      expect(r.kind, DriftReportKind.fuelOut);
      expect(r.from, journey.departure);
      expect(r.to, exhaustAt);
      expect(r.elapsed, exhaustAt.difference(journey.departure));
      expect(r.fromPos.x, closeTo(origin.x, 1e-6));
      expect(r.toPos.x, closeTo(c.playerPosition3D.x, 1e-6));
      expect(r.distanceLy, closeTo((r.toPos - r.fromPos).length, 1e-6),
          reason: 'the powered leg is a straight line');
      expect(r.distanceLy, closeTo(distanceLy * balance / cost, 0.01));
      expect(r.hitBoundary, isFalse);
    });

    test('a mid-flight top-up means there is nothing to report', () async {
      final clock = FakeClock(DateTime(2026));
      final storage = MemoryStorage();
      final c = await _boot(clock, storage);
      await c.installEngine(_greedy);
      final target = c.planets.firstWhere((p) => p.id != c.currentPlanetId);
      await c.launchJourney(target, onEmpty: FuelPolicy.coast);
      final journey = c.activeJourney!;

      // Enough training to cover the rest of the quote.
      final session = await c.startCourse('walk');
      await c.completeCourse(session.id, 400);
      expect(c.fuelExhaustProgress, 1.0);

      clock.advance(journey.totalDuration + const Duration(seconds: 1));
      c.tick();
      expect(c.currentPlanetId, target.id, reason: 'it simply arrives');
      expect(c.pendingDriftReport, isNull);
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd starward && flutter test test/drift_report_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:starward/data/models/drift_report.dart'`。

- [ ] **Step 3: 实现**

**3a.** 新建 `starward/lib/data/models/drift_report.dart`：

```dart
import '../../core/drift.dart';
import '../../core/vec3.dart';

/// What a drift report is about.
enum DriftReportKind {
  /// A voyage that ran out of fuel. The window is the *powered* leg — that is
  /// the part that just happened, and the part the player wants named.
  fuelOut,

  /// A stretch of coasting, either recomputed after the game was closed or
  /// asked for from the coasting screen.
  drift,
}

DriftReportKind driftReportKindFromName(String name) =>
    DriftReportKind.values.firstWhere(
      (k) => k.name == name,
      orElse: () => DriftReportKind.drift,
    );

/// What happened during one window of a ship's travels.
///
/// One class for both kinds: they differ only in which window they describe,
/// and the numbers a player cares about — how long, how far, where to, what it
/// went past — are the same numbers either way.
class DriftReport {
  const DriftReport({
    required this.kind,
    required this.from,
    required this.to,
    required this.elapsed,
    required this.distanceLy,
    required this.fromPos,
    required this.toPos,
    required this.passedCount,
    required this.nearest,
    required this.hitBoundary,
  });

  final DriftReportKind kind;
  final DateTime from;
  final DateTime to;
  final Duration elapsed;

  /// Distance actually flown, arc length included — not the straight-line gap
  /// between [fromPos] and [toPos].
  final double distanceLy;

  final Vec3 fromPos;
  final Vec3 toPos;

  /// Distinct systems that came within the pass radius during the window.
  final int passedCount;

  /// The closest few, ascending by distance, for naming.
  final List<PassedSystem> nearest;

  /// Whether the window includes the ship reaching and sliding along the shell.
  final bool hitBoundary;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind.name,
        'from': from.millisecondsSinceEpoch,
        'to': to.millisecondsSinceEpoch,
        'elapsedMs': elapsed.inMilliseconds,
        'distanceLy': distanceLy,
        'fromX': fromPos.x,
        'fromY': fromPos.y,
        'fromZ': fromPos.z,
        'toX': toPos.x,
        'toY': toPos.y,
        'toZ': toPos.z,
        'passedCount': passedCount,
        'nearest': nearest
            .map((p) => <String, dynamic>{
                  'hygId': p.hygId,
                  'distanceLy': p.distanceLy,
                  'seconds': p.seconds,
                })
            .toList(),
        'hitBoundary': hitBoundary,
      };

  factory DriftReport.fromJson(Map<String, dynamic> json) => DriftReport(
        kind: driftReportKindFromName(json['kind'] as String),
        from: DateTime.fromMillisecondsSinceEpoch(json['from'] as int),
        to: DateTime.fromMillisecondsSinceEpoch(json['to'] as int),
        elapsed: Duration(milliseconds: json['elapsedMs'] as int),
        distanceLy: (json['distanceLy'] as num).toDouble(),
        fromPos: Vec3(
          (json['fromX'] as num).toDouble(),
          (json['fromY'] as num).toDouble(),
          (json['fromZ'] as num).toDouble(),
        ),
        toPos: Vec3(
          (json['toX'] as num).toDouble(),
          (json['toY'] as num).toDouble(),
          (json['toZ'] as num).toDouble(),
        ),
        passedCount: json['passedCount'] as int,
        nearest: (json['nearest'] as List<dynamic>)
            .map((e) => e as Map<String, dynamic>)
            .map((e) => PassedSystem(
                  hygId: e['hygId'] as int,
                  distanceLy: (e['distanceLy'] as num).toDouble(),
                  seconds: (e['seconds'] as num).toDouble(),
                ))
            .toList(),
        hitBoundary: json['hitBoundary'] as bool,
      );
}
```

**3b.** `game_repository.dart`：`GameSave` 加 `final DriftReport? pendingDriftReport;`（构造参数 `required`，`toJson` 加 `'pendingDriftReport': pendingDriftReport?.toJson(),`，`fromJson` 加 `pendingDriftReport: json['pendingDriftReport'] == null ? null : DriftReport.fromJson(json['pendingDriftReport'] as Map<String, dynamic>),`，并 `import 'models/drift_report.dart';`）。**Task 3 已经给 `GameSave` 加过 `energyModel`**，这里照同样的方式加。

**3c.** `game_controller.dart` 在 `_activeJourney` 旁加：

```dart
  /// A report the player has not seen yet. Persisted, so being killed between
  /// the drift happening and the sheet being opened does not lose it.
  DriftReport? _pendingDriftReport;
```

在 `driftDistanceLy` 之后加：

```dart
  /// The path the current drift follows, or null when the ship is parked.
  ///
  /// `bound` is `max(universeRadius, |start|)` so a ship that spawned outside
  /// the shell keeps its own radius instead of being teleported inward.
  DriftPath? get driftPath {
    if (!isCoasting) return null;
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
  /// `driftStartedAt` defaults to the epoch — without this guard every new
  /// player would be told they had been drifting for fifty-six years.
  DriftReport? buildDriftReport() {
    final path = driftPath;
    if (path == null) return null;
    final now = _now();
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
```

`init()` 里在 `_reconcileJourney()` 之后加：

```dart
    // A drift that ran while the game was closed is the one thing the player
    // could not have watched happen. Recompute it once. A voyage that ran out
    // of fuel while away has already queued its own report, and that news
    // comes first — the drift window is not lost, it just waits its turn.
    _pendingDriftReport ??= buildDriftReport();
```

`_applyFuelOut`（Task 9 写的方法）在 `_rebuildNearby();` 之前插入：

```dart
    // Report the powered leg: that is the part that just happened, and the part
    // the player wants named. A powered leg is a straight line at constant
    // speed — the same velocity `_cruiseVelocityOf` already derives — with the
    // shell far enough out that it can never be reached.
    final legSeconds =
        exhaustAt.difference(journey.departure).inMilliseconds / 1000;
    final leg = DriftPath(
      start: _originPosOf(journey),
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
      distanceLy: leg.travelledBetween(0, legSeconds),
      fromPos: leg.positionAt(0),
      toPos: pos,
      passedCount: passed.count,
      nearest: passed.nearest,
      hitBoundary: false,
    );
```

`_persist` 里构造 `GameSave` 的地方加 `pendingDriftReport: _pendingDriftReport,`；`resetSave` 里把它置回 null。**注意**：`_persist()` 在 `_applyFuelOut` 之后被调用（`tick()` → `_persist()`），所以播报会被写进存档；`acknowledgeDriftReport` 自己也 `_persist()`。

- [ ] **Step 4: 跑全量测试确认通过**

Run: `cd starward && flutter analyze && flutter test`
Expected: `No issues found`；全部通过。

- [ ] **Step 5: 提交**

```bash
cd starward && git add lib/data/models/drift_report.dart lib/data/game_repository.dart lib/state/game_controller.dart test/drift_report_test.dart
git commit -m "$(cat <<'EOF'
feat(starward): recompute what a drift did while the game was closed

DriftReport describes one window of travel: how long, how far, where to,
and which systems it went past. A fuel-out report covers the powered
leg; a drift report covers coasting, recomputed once on launch when the
ship was moving, and only then — a parked ship has nothing to report,
and its epoch-default anchor would otherwise announce fifty-six years
of drifting to every new player.

Co-Authored-By: Claude Code <noreply@anthropic.com>
EOF
)"
```

---

### Task 14: 播报弹层

**Files:**
- Create: `starward/lib/ui/journey/drift_report_sheet.dart`
- Modify: `starward/lib/state/game_controller.dart`（新增 `starLabelFor` 转发）
- Modify: `starward/lib/ui/journey/journey_page.dart`（`_JourneyPageState` 弹出待读播报；`_CoastDock` 加途经星系与「查看播报」）
- Test: `starward/test/drift_report_test.dart`（追加）

**Interfaces:**
- Consumes: `DriftReport` / `DriftReportKind`（Task 13）、`GameController.pendingDriftReport` / `acknowledgeDriftReport` / `requestDriftReport` / `passedSystemsSoFar` / `isCoasting`（Task 11/13）、`StarPanel` / `StarColors`（`core/theme.dart`）。
- Produces:
  - `String GameController.starLabelFor(int hygId)`
  - `Future<void> showDriftReportSheet(BuildContext context, {required GameController controller, required DriftReport report})`

- [ ] **Step 1: 写失败测试**

在 `starward/test/drift_report_test.dart` 追加（import 区补 `package:flutter/material.dart`、`package:starward/core/drift.dart`、`package:starward/ui/journey/drift_report_sheet.dart`；`package:starward/core/vec3.dart` 已有。`core/drift.dart` 那一行不能省——`DriftReport.nearest` 的元素类型 `PassedSystem` 定义在那里，`drift_report.dart` 只是 import 它，不 re-export）：

```dart
  group('the report sheet', () {
    Future<void> open(WidgetTester tester, DriftReport report) async {
      final clock = FakeClock(DateTime(2026));
      final c = await _boot(clock, MemoryStorage());
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showDriftReportSheet(
                context,
                controller: c,
                report: report,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('a fuel-out report says how far it got', (tester) async {
      await open(
        tester,
        DriftReport(
          kind: DriftReportKind.fuelOut,
          from: DateTime(2026, 3, 1, 9),
          to: DateTime(2026, 3, 1, 11, 30),
          elapsed: const Duration(hours: 2, minutes: 30),
          distanceLy: 12.5,
          fromPos: const Vec3(0, 0, 0),
          toPos: const Vec3(12.5, 0, 0),
          passedCount: 0,
          nearest: const <PassedSystem>[],
          hitBoundary: false,
        ),
      );
      expect(find.text('燃料耗尽'), findsOneWidget);
      expect(find.textContaining('12.5 ly'), findsOneWidget);
      expect(find.textContaining('2 小时 30 分'), findsOneWidget);
      // An empty stretch of space is a legitimate outcome, and the copy has to
      // say so rather than showing an empty list.
      expect(find.textContaining('空旷的星际空间'), findsOneWidget);
    });

    testWidgets('a drift report names what it went past', (tester) async {
      await open(
        tester,
        DriftReport(
          kind: DriftReportKind.drift,
          from: DateTime(2026, 3, 1),
          to: DateTime(2026, 3, 3),
          elapsed: const Duration(days: 2),
          distanceLy: 4608,
          fromPos: const Vec3(0, 0, 0),
          toPos: const Vec3(4608, 0, 0),
          passedCount: 137,
          nearest: const <PassedSystem>[
            PassedSystem(hygId: 1001, distanceLy: 0.4, seconds: 10),
            PassedSystem(hygId: 1000, distanceLy: 3.1, seconds: 50),
          ],
          hitBoundary: true,
        ),
      );
      expect(find.text('滑行播报'), findsOneWidget);
      expect(find.textContaining('4608.0 ly'), findsOneWidget);
      expect(find.textContaining('2 天 0 小时'), findsOneWidget);
      expect(find.textContaining('途经 137 个恒星系'), findsOneWidget);
      expect(find.textContaining('0.4 ly'), findsOneWidget);
      expect(find.textContaining('3.1 ly'), findsOneWidget);
      expect(find.textContaining('贴着宇宙边界'), findsOneWidget);
    });

    testWidgets('dismissing it does not throw', (tester) async {
      await open(
        tester,
        DriftReport(
          kind: DriftReportKind.drift,
          from: DateTime(2026, 3, 1),
          to: DateTime(2026, 3, 1, 1),
          elapsed: const Duration(hours: 1),
          distanceLy: 100,
          fromPos: const Vec3(0, 0, 0),
          toPos: const Vec3(100, 0, 0),
          passedCount: 0,
          nearest: const <PassedSystem>[],
          hitBoundary: false,
        ),
      );
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(find.text('知道了'), findsNothing);
    });
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd starward && flutter test test/drift_report_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:starward/ui/journey/drift_report_sheet.dart'`。

- [ ] **Step 3: 实现**

**3a.** `game_controller.dart` 在 `starLabel` 附近（约 :213）加转发：

```dart
  /// The display name for a star system, for report copy.
  String starLabelFor(int hygId) => _universe.starLabel(hygId);
```

**3b.** 新建 `starward/lib/ui/journey/drift_report_sheet.dart`：

```dart
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/drift_report.dart';
import '../../state/game_controller.dart';

/// Shows a drift report. The caller marks it read; the sheet only displays it.
Future<void> showDriftReportSheet(
  BuildContext context, {
  required GameController controller,
  required DriftReport report,
}) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DriftReportSheet(controller: controller, report: report),
    );

/// "2 天 3 小时" / "5 小时 12 分" / "40 分 9 秒" — whichever unit reads best.
String _duration(Duration d) {
  if (d.inDays >= 1) return '${d.inDays} 天 ${d.inHours % 24} 小时';
  if (d.inHours >= 1) return '${d.inHours} 小时 ${d.inMinutes % 60} 分';
  return '${d.inMinutes} 分 ${d.inSeconds % 60} 秒';
}

class _DriftReportSheet extends StatelessWidget {
  const _DriftReportSheet({required this.controller, required this.report});

  final GameController controller;
  final DriftReport report;

  bool get _isFuelOut => report.kind == DriftReportKind.fuelOut;

  String get _headline => _isFuelOut
      ? '燃料烧尽前飞了 ${report.distanceLy.toStringAsFixed(1)} ly，'
          '用时 ${_duration(report.elapsed)}。'
      : '滑行了 ${_duration(report.elapsed)}，'
          '共 ${report.distanceLy.toStringAsFixed(1)} ly。';

  String get _whereabouts {
    final p = report.toPos;
    final coord = 'X ${p.x.toStringAsFixed(1)}  Y ${p.y.toStringAsFixed(1)}  '
        'Z ${p.z.toStringAsFixed(1)} ly';
    if (_isFuelOut) {
      return controller.isCoasting
          ? '现在位于 $coord，正以巡航速度继续滑行。'
          : '现在停在 $coord，漂浮于深空。';
    }
    return report.hitBoundary
        ? '现在位于 $coord，已贴着宇宙边界滑行。'
        : '现在位于 $coord。';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: StarPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    _isFuelOut
                        ? Icons.bolt_rounded
                        : Icons.explore_rounded,
                    color: StarColors.cyan,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _isFuelOut ? '燃料耗尽' : '滑行播报',
                    style: const TextStyle(
                      color: StarColors.offWhite,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _headline,
                style: const TextStyle(
                  color: StarColors.offWhite,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _whereabouts,
                style: const TextStyle(
                  color: StarColors.muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              if (report.passedCount > 0) ...<Widget>[
                Text(
                  '途经 ${report.passedCount} 个恒星系',
                  style: const TextStyle(
                    color: StarColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                for (final s in report.nearest)
                  _PassedRow(
                    name: controller.starLabelFor(s.hygId),
                    distanceLy: s.distanceLy,
                  ),
                if (report.passedCount > report.nearest.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '……以及其他 ${report.passedCount - report.nearest.length} 个',
                      style: const TextStyle(
                        color: StarColors.faint,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ] else
                const Text(
                  '这一段是空旷的星际空间，没有经过任何恒星系。',
                  style: TextStyle(
                    color: StarColors.faint,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              const SizedBox(height: 18),
              _DismissButton(
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PassedRow extends StatelessWidget {
  const _PassedRow({required this.name, required this.distanceLy});

  final String name;
  final double distanceLy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          const Icon(Icons.star_rounded, color: StarColors.cyanDim, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: StarColors.offWhite,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            '最近 ${distanceLy.toStringAsFixed(1)} ly',
            style: const TextStyle(color: StarColors.faint, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _DismissButton extends StatelessWidget {
  const _DismissButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: StarColors.cyan,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 15),
            child: Text(
              '知道了',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: StarColors.abyss,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

**3c.** `journey_page.dart` 的 `_JourneyPageState` 加：

```dart
  // Guards against queueing the same report twice while the sheet is opening.
  bool _reportScheduled = false;

  /// Shows a queued drift report, once. Scheduled from the build rather than
  /// awaited in it, because the sheet needs a frame that has already settled.
  void _maybeShowReport(GameController c) {
    final report = c.pendingDriftReport;
    if (report == null || _reportScheduled) return;
    _reportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _reportScheduled = false;
        return;
      }
      await showDriftReportSheet(context, controller: c, report: report);
      await c.acknowledgeDriftReport();
      _reportScheduled = false;
    });
  }
```

`build` 里 `_sync(c);` 之后加 `_maybeShowReport(c);`，并在 import 区加 `import 'drift_report_sheet.dart';`。

**3d.** `_CoastDock` 加一行途经星系与「查看播报」按钮。在 `_CoastStat` 的三行之后插入：

```dart
          _CoastStat(
            label: '途经恒星系',
            value: '${controller.passedSystemsSoFar.count}',
          ),
```

并把 `StarPanel` 的 `Column` 末尾加上：

```dart
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: StarColors.panelLight,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: controller.requestDriftReport,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 11),
                  child: Text(
                    '查看播报',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: StarColors.cyan,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
```

（`passedSystemsSoFar` 是一次全星表扫描。`_CoastDock` 每次 `notifyListeners` 重建一次，而 `tick()` 每秒一次——所以是每秒一次扫描，约 2–5 ms。**不要**把它挪到每帧重建的 widget 里。）

- [ ] **Step 4: 跑全量测试确认通过**

Run: `cd starward && flutter analyze && flutter test`
Expected: `No issues found`；全部通过。手动 `flutter run`：让一次 `coast` 航程烧干 → 播报弹层出现「燃料耗尽」→ 关掉后航行页显示「滑行中」与途经恒星系数 → 杀掉 App 等十分钟再启动 → 弹出「滑行播报」。

- [ ] **Step 5: 提交**

```bash
cd starward && git add lib/ui/journey/drift_report_sheet.dart lib/ui/journey/journey_page.dart lib/state/game_controller.dart test/drift_report_test.dart
git commit -m "$(cat <<'EOF'
feat(starward): tell the player what their drift did

One sheet for both report kinds: a fuel-out report says how far the
powered leg got before the tank emptied, a drift report says how long
and how far the coast ran, and both name the systems passed. The
coasting screen carries the live count and a way to ask for one.

Co-Authored-By: Claude Code <noreply@anthropic.com>
EOF
)"
```

**阶段 D 检查点**：四条播报路径都走一遍——在线烧干（`fuelOut`）、离线滑行（`drift`）、滑行页手动「查看播报」（`drift`）、以及**反面**：出生/停止/`halt`/抵达恒星四种零速度深空状态下，绝不弹任何东西。
