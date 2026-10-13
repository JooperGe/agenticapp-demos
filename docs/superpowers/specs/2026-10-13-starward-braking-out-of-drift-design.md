# Starward 滑行制动设计规格

**日期：** 2026-10-13
**状态：** 待审阅
**范围：** 脱离滑行（coast）的出口、制动能量代价、滑行页的操作入口
**前置：** `2026-10-12-starward-voyage-energy-and-drift-design.md`（滑行与漂流已成为一等状态）

## 1. 目标与边界

滑行中的飞船没有"停下"这个动作。玩家燃料耗尽转滑行后，通过训练拿到能量，回到航行页却发现滑行面板上只有「查看播报」——没有任何能改变状态的入口。

必须做到：

1. **滑行有出口**：滑行页提供「制动停下」与「改变航向」两个动作，与航行页的「停止航行 / 改变航向 / 返航」对齐。
2. **制动要付能量**：制动是引擎对抗自身巡航速度的燃烧，按引擎的制动距离收费。
3. **收费点唯一**：制动费记在"漂移速度从非零变零"这一刻，且**每条脱离滑行的路径都收**——否则"从星图出发"会成为免费逃逸口，两个按钮做同一件事却标价不同。
4. **滑行状态可见**：导航栏航行 Tab 在滑行时也亮徽标（现在只有 `activeJourney != null` 才亮）。

不做：

- 不做"停下时补一份滑行总结播报"（见 §11：改为在确认对话框里念一遍数字）。
- 不做"直接飞向附近某颗星"的快捷入口。
- 不改 `returnToOrigin`（滑行时它本来就返回 `noSelection`）。
- 不改滑行的物理模型：巡航速度恒定、滑行本身不耗能、贴壳沿大圆滑行，全部沿用前置规格。

## 2. 现状（改动前）

### 2.1 滑行态的入口是空的

`journey_page.dart` 的 `_buildStandby`（`:254`）按状态分三种 dock：

| 状态 | 组件 | 提供的动作 |
|---|---|---|
| 滑行中（`isCoasting`） | `_CoastDock`（`:655`） | **只有「查看播报」**（`:722`） |
| 深空待泊（`currentPlanet == null` 且速度为零） | `_DriftDock`（`:603`） | 无（纯坐标读数） |
| 停靠行星 | `_CurrentDock` | 无 |

三种状态下方都会渲染推荐目的地卡片 `_RecommendCard`（`:779`），它唯一的动作是「在星图中查看」（`:827`）——只切 Tab，不停滑行、不出发。

### 2.2 航行页的三个按钮在滑行态全部失效，而且是控制器层面没有能力

- `abortJourney()`（`game_controller.dart:834`）首行是 `if (journey == null || journey.status != JourneyStatus.inProgress) return;`。滑行时 `_activeJourney == null`，**直接 no-op**——不结算、不落盘、不通知。
- `returnToOrigin()`（`:867`）在同样条件下返回 `LaunchResult.noSelection`。

所以「停止航行 / 改变航向 / 返航」这套语义在滑行态是空的。玩家看到的"没入口"，底下是"没实现"。

### 2.3 唯一的停船路径是隐式的

`_anchorHere()`（`:371`）是全项目唯一的"引擎接管运动"收口：把锚点 `startX/Y/Z` 钉到当前实际坐标，并把 `driftVelocity` 清零。它只被两处调用——`launchJourney`（`:720`）与 `launchToStar`（`:765`）。

**所以这不是硬锁**：玩家训练拿到能量后，去星图随便选个目标出发，滑行就被顺手停掉了。但这条路径叫"出发"，不叫"停下"；滑行面板上唯一指向它的是「在星图中查看」——文案是"查看"，不是"行动"。

### 2.4 一条已经成立的不变式

`driftVelocity != 0` ⟹ `_activeJourney == null`。

因为每次出发都先 `_anchorHere()` 清零速度再设 `_activeJourney`，而 `_applyFuelOut` 是唯一设置非零速度的地方，它同时把 `_activeJourney` 置空。所以"滑行"与"有进行中的航程"互斥。本规格的收费点建立在这条不变式上。

### 2.5 导航栏徽标

`home_shell.dart:71`：`hasJourney = controller.activeJourney != null`。滑行时没有 active journey，徽标不亮——切到训练页后界面上没有任何信号提示船还在漂。

## 3. 核心规则：制动是脱离滑行的唯一出口

> 滑行中的船有动量。要脱离滑行，先制动。

**收费点唯一：`_anchorHere()`。** 把制动费挂在这个既有收口上，就自动覆盖了"从星图出发"这条免费逃逸路径，不需要在 `launchJourney` / `launchToStar` 里各写一遍。

**唯一的不变式：`driftVelocity` 从非零变零的那一刻，记一笔 `braking` 账。**

为什么必须挂在 `_anchorHere()` 而不是只挂在「制动停下」按钮上：如果只有停止收费、出发免费，玩家会看到并排两个按钮做同一件事却不同价，并且会立刻学会绕开收费的那个（点星图 Tab 直接出发）。收费点必须在所有出口的共同上游。

**为什么制动不能并进 `Journey.energyCost`。** `Journey.burnedAt(now) = round(energyCost * progressAt(now))`（前置规格 §3.1），把制动费并进去会把 100 EN 摊到整条航线上，耗尽点 `p_exhaust` 就算错了。所以：

- `Journey.energyCost` 保持"只含航程燃料"，语义不变。
- 制动费是一笔**出发瞬间**的独立账目，不参与燃烧曲线。

这也让制动成为本项目第一条"在出发时扣能量"的路径。前置规格 §3.1 的"出发时不扣任何能量"依然成立——它说的是**航程燃料**；制动不是航程的一部分，是航程的前置步骤。

## 4. 定价

**`Engine.standard` 的制动距离 = 40 ly → 制动费 = `energyCostFor(40)` = 100 EN。**

参照系（均为既有数值，不改）：

| 数值 | 值 |
|---|---|
| `Balance.initialEnergy` | 300 EN |
| 训练奖励（三组） | 40 / 70 / 50 EN |
| `Balance.explorationReward` | 15 EN |
| 标准引擎 `energyPerLy` | 2.5 EN/ly |
| 标准引擎 `travelSecondsPerLy` | 37.5 s/ly |
| 巡航速度 | 1 / 37.5 = 0.0266667 ly/s |

也就是"一组训练基本够制动一次"。

**为什么是 40 ly：**

- 要显著低于一次典型航程（几十到几百 EN）。玩家是因为"飞不起"才滑行的，不能再因为"停不起"被罚第二次。
- 要远高于 `minEnergyCost`（1 EN），否则规则在界面上看不见。
- 100 EN 低于初始能量 300，所以新玩家第一次遇到滑行时停得下来。

**为什么写成距离而不是固定 EN。** 按 `CLAUDE.md` 的属性归属："引擎抵消一个巡航速度需要多远"是引擎的能力。将来换一台制动更利落的引擎 = 改这一个字段。写成固定 EN 则换引擎时制动费不会跟着变。

**为什么写成速度的比值而不是直接用制动距离。** `|driftVelocity|` 在当前模型里恒等于 `cruiseSpeed`（`_cruiseVelocityOf` = 距离 / 时长，而 `时长 = secondsFor(距离)`），所以标准引擎的制动费恒为 100 EN。按比值写（`brakingDistanceLy * speed / cruiseSpeed`）是为了将来速度真会变时规则仍然成立，且部分速度自动按比例便宜。

## 5. 模型变更

### 5.1 `Engine`（`lib/data/models/engine.dart`）

新增字段与方法：

```dart
/// Distance the engine needs to shed one cruise speed's worth of velocity.
/// Braking from a full cruise burn costs what flying this far costs.
final double brakingDistanceLy;

/// The speed a voyage settles at, in ly/s.
double get cruiseSpeedLyPerSec => 1 / travelSecondsPerLy;

/// Energy to shed [speedLyPerSec], in EN.
///
/// Zero for a ship already at rest — `energyCostFor` floors at
/// `minEnergyCost`, so without this guard a stationary ship would be quoted
/// 1 EN to not move.
int brakingCostFor(double speedLyPerSec) {
  if (speedLyPerSec <= 0) return 0;
  return energyCostFor(brakingDistanceLy * speedLyPerSec / cruiseSpeedLyPerSec);
}
```

`Engine.standard` 增加 `brakingDistanceLy: 40`。

**JSON 迁移：** 引擎被重构之后写出的存档都带 `ship` 键，其中的 `engine` 对象**没有** `brakingDistanceLy`。`Engine.fromJson` 直接 `as double` 会抛。按 `CLAUDE.md` 的迁移优先约定，缺字段回落到 `Engine.standard.brakingDistanceLy`：

```dart
brakingDistanceLy:
    (json['brakingDistanceLy'] as num?)?.toDouble() ??
        Engine.standard.brakingDistanceLy,
```

**已知局限：** 如果将来存在第二台引擎，这条回落会给旧存档里的那台引擎装上标准引擎的制动距离。今天只有一台引擎，所以是死代码；将来加引擎时应当把 `brakingDistanceLy` 视为必填并重新审视这条回落。

### 5.2 `EnergyTxType`（`lib/data/models/energy_transaction.dart`）

新增成员 `braking`：`{ travelCost, trainingReward, explorationReward, braking }`。

`energyTxTypeFromName` 已有 `orElse: () => travelCost` 兜底，所以旧存档（只含三个旧名字）读取安全。枚举成员追加不改变任何既有名字，所以反向（新存档被旧代码读）不在本规格的兼容范围内。

### 5.3 不动的部分

| 模型 | 结论 |
|---|---|
| `Journey` | **不动。** `energyCost` 继续只含航程燃料（§3） |
| `PlayerState` | **不动。** 制动只改 `driftVelocity` 与锚点，不新增字段 |
| `GameSave` | **不动。** 不新增顶层标记 |
| `_saveKey` | **不 bump**（`starward.save.v2` 不变） |

## 6. 控制器变更（`lib/state/game_controller.dart`）

### 6.1 新增 `brakingCost`

```dart
/// What it costs to bring the ship out of its current motion, in EN.
/// Zero for a ship at rest — docked, parked in deep space, or under power.
int get brakingCost => isCoasting
    ? _ship.engine.brakingCostFor(_player.driftVelocity.length)
    : 0;
```

### 6.2 `_anchorHere()` 增加收费

```dart
void _anchorHere() {
  final braking = brakingCost;   // 必须在清零之前读
  final pos = playerPosition3D;
  _player = _player.copyWith(
    startX: pos.x, startY: pos.y, startZ: pos.z,
    driftVelocity: const Vec3(0, 0, 0),
  );
  if (braking > 0) _settleBraking(braking);   // 记一笔 -braking，类型 braking
}
```

- `braking > 0` 的守卫保证停靠 / 待泊 / 航行中调用 `_anchorHere()` 不写零额账目。
- 保持同步：`_anchorHere` 目前是 `void`，账本在内存里，后续 `_persist()` 会落盘。
- 新增私有 `_settleBraking(int amount)`，仿 `_settleBurn`（`:1045`）的形状：扣 `energyBalance`、追加一条 `EnergyTransaction(type: braking, amount: -amount)`。

### 6.3 `_launchGate` 改为分别接收航程燃料与制动费

```dart
LaunchResult? _launchGate(int voyageFuel, int braking, FuelPolicy policy) {
  if (policy == FuelPolicy.refuse) {
    return _player.energyBalance < voyageFuel + braking
        ? LaunchResult.insufficientEnergy : null;
  }
  // halt / coast 只要求一滴燃料，但那滴燃料是制动之后剩下的
  return _player.energyBalance <= braking
      ? LaunchResult.insufficientEnergy : null;
}
```

### 6.4 `launchJourney` / `launchToStar` 的报价拆分

顺序是硬性的：**先读 `brakingCost`，再 `_anchorHere()`**——`_anchorHere` 会把速度清零，读晚了就永远是 0。

```dart
final voyageFuel = _ship.engine.energyCostFor(distanceTo(target));
final braking = brakingCost;
final gate = _launchGate(voyageFuel, braking, onEmpty);
if (gate != null) return gate;

_anchorHere();          // 记 -braking，清零速度，重锚
...
final journey = Journey(..., energyCost: voyageFuel, ...);   // 不含制动
```

注意 `launchJourney`（`:716`）现在用 `energyCostTo(target)` 取 cost，必须改成直接算 `_ship.engine.energyCostFor(distanceTo(target))`（§6.5 改了 `energyCostTo` 的语义，复用它会把这笔制动费也写进 `Journey.energyCost`）。`launchToStar`（`:761`）已经在直接算 `_ship.engine.energyCostFor(dist)`，所以它只有 `_launchGate` 的调用需要改。

### 6.5 `energyCostTo` / `energyCostToStar` 改为玩家实际会付的总额

```dart
int energyCostTo(Planet target) =>
    _ship.engine.energyCostFor(distanceTo(target)) + brakingCost;
```

这样 8 个 UI 引用点（`star_system_sheet.dart:30`、`:176`，`planet_details_sheet.dart:185`、`:357`、`:426`，`galaxy_map_3d_page.dart:198`，`journey_page.dart:788`）自动报出正确总额，不需要逐个改。

**停靠行星、深空待泊、航行中时 `brakingCost == 0`，所以这些引用点与既有测试的语义逐位不变。**

### 6.6 新增 `stopShip()`

统一的"让船停下"这个动作。按 `CLAUDE.md` 的归属原则，这个行为属于**船**，不属于某一条航程，所以它应该有一个统一入口，让 UI 不必知道船内部处于哪种运动状态。

```dart
/// Brings the ship to rest where it is, whatever is moving it.
///
/// A voyage in progress is billed for the fuel it has burned and the ship
/// parks at the point it had reached. A coasting ship must first shed its
/// cruise velocity: that braking burn is billed and the ship then parks at
/// the point the drift had carried it to. A parked ship is left alone.
Future<void> stopShip() async {
  final journey = _activeJourney;
  if (journey != null && journey.status == JourneyStatus.inProgress) {
    return abortJourney();
  }
  if (!isCoasting) return;
  if (_player.energyBalance < brakingCost) return;   // 停不下来
  _anchorHere();
  await _persist();
  notifyListeners();
}
```

- **不调 `_rebuildNearby()`**：制动只冻结位置，不移动船，附近集仍然有效。（对比 `abortJourney` 会移动船，所以它要重建。）
- `abortJourney()` 保留原名原语义，它的 8 个测试调用点不动。
- 新增 `bool get canBrake => !isCoasting || _player.energyBalance >= brakingCost;` 给 UI 判断按钮可用性。

### 6.7 UI 调用点的统一

`journey_page.dart` 的 `_abortFlight`（`:164`）与 `_changeCourse`（`:175`）目前直接调 `abortJourney()`。改为调 `stopShip()`——航程进行中时 `stopShip()` 就是委托给 `abortJourney()`，行为逐位相同，但 UI 从此只有一个动作名。

## 7. UI 变更

### 7.1 `_CoastDock`（`journey_page.dart:655`）

在统计行下加一行制动读数，再加两个按钮：

```
滑行中 · 巡航速度
0.0267 ly/s
已滑行          3.2 天
累计距离        7,370.0 ly
途经恒星系      128
当前坐标        X 1234.5  Y -88.0  Z 402.1
制动需要        100 EN（现有 150 EN）      ← 低于 100 时用 StarColors.danger 并把两个按钮禁用

[ 制动停下 ]   [ 改变航向 ]
[ 查看播报 ]                              ← 保留
```

- **「制动停下」** → 确认对话框 → `stopShip()`。
- **「改变航向」** → **同一个确认对话框** → `stopShip()` 然后 `ShellScope.go(context, 0)`。它刻意不是一条免费路径：制动费在同一个地方收，只是顺带切 Tab。
- 能量不足时两个按钮 `onPressed: null`（禁用），并给出「前往训练补充能量」的指引（`ShellScope.go(context, 3)`），沿用 `planet_details_sheet.dart:380` 的既有做法。

### 7.2 确认对话框

```
停止滑行
飞船将制动停下，漂浮于深空。

本次滑行 3.2 天 · 7,370.0 ly · 途经 128 个恒星系
制动消耗 100 EN，制动后剩余 50 EN。

  [ 取消 ]        [ 停止 ]
```

第三行是刻意加的：制动之后 `driftPath == null`，`buildDriftReport()` 返回 null，**这段滑行的数字就永久拿不到了**。把统计念在对话框里，不新增任何播报管线，也不违背"不做停下总结播报"的选择（§11）。

### 7.3 导航栏徽标（`home_shell.dart:71`）

```dart
final hasJourney = controller.activeJourney != null || controller.isCoasting;
```

现在滑行时切到训练页，界面上没有任何信号提示船还在漂。

### 7.4 `showFuelChoiceDialog` 增加 `braking` 参数（`journey_page/fuel_choice_dialog.dart`）

对话框现在用 `engine.reachableLyFor(energy)` 算"可以飞 Y ly"（`:21`），并用 `energy > 0` 决定是否给出 `halt`/`coast` 两个选项（`:58`）。加了制动之后这两个都是错的：

- 能飞的里程要从**制动之后**剩下的燃料算：`engine.reachableLyFor(energy - braking)`。
- 给出 `halt`/`coast` 的门槛是 `energy > braking`（制动后还剩一滴）。

所以签名加一个 `required int braking`，文案相应改为报出总额。以"航程 100 ly（250 EN 燃料）+ 制动 100 EN，玩家有 150 EN"为例：

```
能量不足以飞完全程
你只有 150 EN，其中 100 EN 要先用于制动。制动后剩 50 EN，
可以飞 20.0 ly，全程 100.0 ly。
```

（`reachableLyFor(150 - 100) = 20.0 ly`；`energyCostTo = 250 + 100 = 350 > 150`，所以对话框确实会弹出。）

### 7.5 出发按钮的文案（`planet_details_sheet.dart:357`）

`cost` 来自 `energyCostTo`（§6.5），已经含制动费，所以「开始航行 · $cost EN」自动正确。但能量不足时的提示（`:360`、`:364`）需要区分"差的是航程燃料"还是"差的是制动费"，否则玩家会困惑于"我要去的地方很近，为什么说能量不足"：

```
if (braking > 0) 额外一行：『先制动需要 $braking EN』
```

## 8. 数据模型变更汇总

| 模型 | 变更 | 迁移 |
|---|---|---|
| `Engine` | 新增 `brakingDistanceLy` + `cruiseSpeedLyPerSec` + `brakingCostFor` | `fromJson` 缺字段回落 `Engine.standard.brakingDistanceLy` |
| `EnergyTxType` | 新增 `braking` | `energyTxTypeFromName` 已有 `orElse` 兜底 |
| `Journey` | 不变 | — |
| `PlayerState` | 不变 | — |
| `GameSave` | 不变 | — |
| `_saveKey` | **不 bump** | — |

## 9. 测试策略

沿用 `CLAUDE.md`：TDD 先行、`FakeClock` + 固定 seed、`MemoryStorage`、**钉住具体数字**。

### 9.1 必须覆盖

1. **`brakingCostFor` 钉死数字**：速度 = 巡航速度（1/37.5）→ **100**；速度 = 半巡航 → **50**；速度 = 0 → **0**（不是 `minEnergyCost` 的 1，见 §5.1 的零速守卫）；负速度 → 0。
2. **制动停下**：滑行中 `stopShip()` → `driftVelocity` 归零、锚点 = 制动前的位置、余额 −100、账本多一条 `braking` 且金额 −100；再 `advance` 任意久，位置不变。
3. **制动只收一次**：连调两次 `stopShip()`，账本只有一条。
4. **出发也收制动**：滑行中 `launchJourney(target)` → 账本一条 `braking` −100，且 `Journey.energyCost` 仍是纯航程燃料（钉具体数），总扣款 = 100 + 航程燃料。
5. **门槛**：滑行中余额 50（< 100）→ `stopShip()` 是 no-op（不动速度、不记账）；`launchJourney` 返回 `insufficientEnergy`。
6. **零影响回归**：停靠行星 / 深空待泊 / 航行中三种状态下 `brakingCost == 0`、`energyCostTo` 与改动前逐位相同、`abortJourney` 行为不变。
7. **不变式**：`driftVelocity != 0` ⟹ `_activeJourney == null`；且速度从非零变零的每条路径恰好一条 `braking` 账目（`stopShip` 与两条 launch 路径）。
8. **0 能量不软锁**：滑行 + 余额 0 → `stopShip()` no-op，但训练可用（`startCourse` 无前置条件），训练到 100 EN 后制动成功。
9. **贴壳滑行时制动费不变**：船撞上包围球沿大圆滑行后，`driftVelocity` 未被改写，制动费仍是 100。
10. **存档往返**：制动后的存档重启，速度仍为 0、账本仍在、`energyBalance` 一致。
11. **引擎迁移**：不含 `brakingDistanceLy` 的 `ship.engine` JSON 加载后该字段 = 40，且 `brakingCostFor(cruiseSpeed) == 100`。

### 9.2 既有测试的影响（已核查）

**没有既有测试在 `isCoasting == true` 的状态下发起航行**，所以"出发也收制动"不会打破现有断言。逐条核查过的高危点：

| 测试 | 结论 |
|---|---|
| `coast_test.dart:122` "launching re-anchors…" | 先 `abortJourney()` 再出发，此时速度已为 0，`braking == 0` ✓ |
| `fuel_out_test.dart:155` "halt and coast only need a drop of fuel" | 船停靠在行星（`braking == 0`），`1 > 0` 仍通过 ✓ |
| `fuel_out_test.dart:166` "an empty tank moves nothing" | `0 <= 0` 仍被拒 ✓ |
| `fuel_out_test.dart:283` "keeps moving at cruise speed…" | 只断言 `energy == 0` 与账本条数，不涉及 `energyCostTo` ✓ |
| `flight_panel_test.dart` 的 `coast` 用例 | 都在停靠/待泊状态出发，`braking == 0` ✓ |

**需要新增而非改写的测试文件：** `test/braking_test.dart`（§9.1 全部条目）。

### 9.3 需要留意但预期不改

- `energy_test.dart`、`real_time_energy_test.dart` 大量使用 `energyCostTo` 预测燃烧量。这些用例都不滑行，`brakingCost == 0`，断言不变——但这是"预期"，执行时必须全量跑一遍确认。

## 10. 实施顺序

三个阶段，每阶段独立可发布、可测试、不留半成品。

**阶段 1 — 制动地基。** `Engine.brakingDistanceLy` / `cruiseSpeedLyPerSec` / `brakingCostFor` + JSON 迁移 + `EnergyTxType.braking` + `GameController.brakingCost` / `_settleBraking` / `_anchorHere` 收费 / `_launchGate` 签名 / `launchJourney`、`launchToStar` 报价拆分 / `energyCostTo`、`energyCostToStar` 语义。**玩家可见变化：滑行中从星图出发会多扣一笔制动费。** 这是本规格唯一改既有路径行为的一步，必须单独发布以便回退。

**阶段 2 — 滑行出口。** `stopShip()`、`canBrake`、`_CoastDock` 的两个按钮与确认对话框、`journey_page.dart` 的 UI 调用点统一到 `stopShip()`。**玩家可见变化：滑行页终于有动作了。**

**阶段 3 — 报价与可见性。** `showFuelChoiceDialog` 的 `braking` 参数、`planet_details_sheet.dart` 的制动提示行、`home_shell.dart` 徽标条件。**玩家可见变化：能量不足时能看懂差的是哪一笔；切到别的 Tab 也知道船还在漂。**

阶段 1 必须先做（阶段 2 的 `stopShip()` 依赖 `brakingCost`）；阶段 3 依赖阶段 1 的语义，与阶段 2 无依赖，可并行。

## 11. 已知取舍

- **代价：出发被重新计价。** 滑行中从星图出发要多付 100 EN。这是唯一能堵住免费逃逸口的做法（§3），但它确实改了一条既有路径的行为，所以单独作为阶段 1 发布。
- **制动之后这段滑行的数字就没了。** 制动后 `driftPath == null`，`buildDriftReport()` 返回 null，滑行面板上的统计也随之消失。缓解办法是在确认对话框里念一遍（§7.2），但**不**排队一份总结播报——那是被明确排除的选项。
- **`EnergyTxType` 新增成员**与前一份规格"不新增成员"的表述冲突。那条约束的语境是航程模型（不要为"退费"造类型）；制动不是退费，是一笔真实的新支出，所以它值得自己的类型。
- **制动费是常数。** 因为速度恒定，滑行 1 小时和滑行 1 年的制动费一样。这是"速度恒定"这个既有模型的直接推论，不是新引入的简化。
- **制动只解决"停"，不解决"去哪"。** 「改变航向」是制动 + 切 Tab，不是一条独立的免费路径；滑行中想直接飞向附近某颗星，仍然要走星图。
- **`Engine.fromJson` 的回落会在将来加引擎时变成隐患**（§5.1），今天无害。
