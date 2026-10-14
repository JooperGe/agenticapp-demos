# Starward 自由巡航设计规格

**日期：** 2026-10-14
**状态：** 待审阅
**范围：** 无目的地的自由巡航、座舱模式下的修正航向、巡航耗电、休眠与激活
**前置：**
- `2026-10-12-starward-voyage-energy-and-drift-design.md`（实时耗能、耗尽三选一、滑行）
- `2026-10-13-starward-braking-out-of-drift-design.md`（制动费、`_anchorHere` 唯一收费点）

## 1. 目标与边界

**缺陷：** 飞船在深空停下之后，没有任何入口能让它重新动起来。

现有的绕道是「推荐目的地 → 在星图中查看」，但它不通：推荐目的地来自 `_rebuildNearby()`，半径 60 ly 起、最多翻四倍到 960 ly（`game_controller.dart:71`、`:508`），而星图的传感器范围只画到 50–416 ly（`galaxy_map_3d_page.dart:641-644`，`_sensorRange` 600–5000 world units ÷ `_worldScale` 12）。两组数字从来没有对齐过，所以**推荐的那颗星多半根本不在星图上**——玩家被告知"去星图看"，到了星图却什么也看不到。

更深一层的缺失是：**游戏里没有"没有目的地也要飞"这件事**。`launchJourney` 与 `launchToStar` 都要求一个具体目标，而深空待泊的 `_DriftDock`（`journey_page.dart:663`）是纯读数面板，一个按钮都没有。

必须做到：

1. **有入口**：深空待泊时给出「点火巡航 · 选择方向」，让玩家自己选一个方向飞出去，不需要目的地。
2. **看得见要去哪**：座舱模式下，超出传感器范围的目的地也要有方向指示与距离读数。
3. **动着的船能改向**：座舱模式下提供「修正航向」，按转过的 Δv 收费。
4. **耗电是电，不是燃料**：能量代表飞船的生命维持与电气系统，只在引擎运转时消耗；停泊、停靠、训练、探索都不耗能。
5. **没电要说清楚**：电量耗尽时飞船进入休眠，需要花能量激活引擎——这既是状态名，也是那个缺失入口的动作与数字。

不做：

- **不做"从行星起飞但没有目的地"。** 从停靠行星点火巡航会牵出"离开星球是否要确认""未探索的 POI 怎么办"这一串独立问题。本规格只在深空（`currentPlanetId == null`）提供点火巡航；从行星出发仍然只能选目的地。
- **不做滑行中拖动星图改向。** 改向只在座舱模式里、通过「修正航向」按钮发生（§5）。
- **不做点火收费。** 点火是免费的（§4.1）。这条决定有一个直接后果，写在 §5.2。
- **不改滑行的物理模型**：巡航速度恒定、滑行不耗能、贴壳沿大圆滑行，全部沿用前置规格。
- **不改 `returnToOrigin`、`abortJourney`、`_settleBurn` 的语义。**

## 2. 现状（改动前）

### 2.1 深空待泊没有任何动作

`journey_page.dart` 的 `_buildStandby`（`:310`）按状态分三种 dock：

| 状态 | 组件 | 提供的动作 |
|---|---|---|
| 滑行中（`isCoasting`） | `_CoastDock`（`:716`） | 制动停下 / 改变航向 / 查看播报 |
| 深空待泊（`currentPlanet == null` 且速度为零） | `_DriftDock`（`:663`） | **无**（纯坐标读数） |
| 停靠行星 | `_CurrentDock`（`:622`） | 无 |

三种状态下方都渲染 `_RecommendCard`（`:866`），它唯一的动作是「在星图中查看」（`:917`）——只切 Tab。

### 2.2 推荐集与传感器范围从未对齐

`_recommendDestination`（`journey_page.dart:292`）从 `c.planets` 里挑最近的未探索行星。`c.planets` 是 `_rebuildNearby()` 的产物，半径可以一路扩到 960 ly（`game_controller.dart:508-515`），空的时候还会回落到全目录最近行星（`:521`）。

星图那边，`Galaxy3DPainter._drawPlanet` 在 `dist > sensorRange` 时**直接不画**（`galaxy3d_painter.dart:235`），`pickStarId` 也把范围外的恒星排除在拾取之外（`:431`）。传感器滑杆 600–5000 world units，即 **50–416 ly**。

960 与 416 之间那一段，就是"点了按钮看不到东西"的全部原因。

### 2.3 能量模型其实已经是按秒扣的

`Journey.burnedAt(now) = round(energyCost * progressAt(now))`（`journey.dart:85`），而 `energyCost = energyPerLy * D`、`progressAt = elapsed / (D / cruiseSpeed)`，所以

```
每秒燃烧 = energyPerLy * cruiseSpeedLyPerSec = 2.5 * (1/37.5) = 0.0666667 EN/s
```

**距离在式子里约掉了。** 现在这套"边航行边扣费"本来就不是"按里程烧推进剂"，而是"引擎开着就一直耗电"。本规格把这个已经成立的事实说清楚，而不是改变它。

### 2.4 一条已经成立的不变式

`driftVelocity != 0` ⟹ `_activeJourney == null`（前置规格 §2.4）。巡航沿用这条：`driftVelocity` 在此之前只有 `_applyFuelOut` 一个来源，巡航是第二个，而它与航程仍然互斥。

## 3. 核心模型：能量是电

> **能量是飞船的电。** 生命维持、照明、电气、以及引擎本身都吃它。它只在引擎运转时消耗；停泊、停靠、训练、探索都不消耗。

### 3.1 四种运动状态

| 状态 | 条件 | 耗电 | 能改向 | 能制动 |
|---|---|---|---|---|
| **停泊** | 速度为 0 | 否 | — | — |
| **巡航** | 速度 > 0 且引擎在线 | **0.0667 EN/s** | 是（按 Δv 收费） | 是（100 EN） |
| **滑行** | 速度 > 0 且引擎离线 | 否 | 否 | 是（100 EN） |
| **休眠** | `engineDormant` | 否 | 否 | **是**（见 §4.3） |

休眠与运动状态正交：一艘船可以在停泊时休眠，也可以在滑行时休眠。巡航中的船不会休眠（引擎开着就说明有电）。

**巡航与滑行是同一个运动的两种供电状态**，不是两种运动。两者的速度都是 `cruiseSpeedLyPerSec`，位置都由同一套 `DriftPath` 现算，区别只有"引擎在不在烧电"。

### 3.2 耗电率与不变式

```dart
/// Energy the engine draws in [seconds] of continuous running, in EN.
double get powerDrawPerSecond => energyPerLy * cruiseSpeedLyPerSec;
int burnForSeconds(double seconds) => energyCostFor(seconds * cruiseSpeedLyPerSec);
```

`Engine.standard` 的值：`2.5 × (1/37.5)` = **0.0666667 EN/s**。300 EN 可以巡航 **4500 秒 = 75 分钟 = 120 ly**。

**核心不变式（本规格的全部经济学建立在这一条上）：**

> **巡航 D 光年的电费，与出发到 D 光年的燃料费，逐位相等。**

因为两者都是 `energyCostFor(2.5 · D)`：巡航走 `burnForSeconds(seconds)`，而 `seconds * cruiseSpeedLyPerSec` 就是走过的距离。写成走同一个函数而不是各算一遍，是为了让这两条定价**在结构上不可能分叉**——将来改 `energyPerLy` 或 `cruiseSpeedLyPerSec`，两边一起动。

| 距离 | 巡航耗时 | 巡航电费 | 出发燃料费 |
|---|---|---|---|
| 1 ly | 37.5 s | 3 EN | 3 EN |
| 40 ly | 25 min | 100 EN | 100 EN |
| 120 ly | 75 min | 300 EN | 300 EN |
| 200 ly | 125 min | 500 EN | 500 EN |

（1 ly 那行是 `minEnergyCost` 的地板：`round(2.5) = 3`。地板同时是"每一次机动至少要花 1 EN 的电"这条规则的来源——见 §12 的边界说明。）

### 3.3 为什么巡航不能比出发便宜

如果巡航更便宜，玩家就再也不会用「出发」了。它不会，因为两边走的是同一个 `energyCostFor`：

- **巡航 120 ly 烧 300 EN**，与出发 120 ly 的燃料费完全一样。
- 巡航还要自己付制动费（100 EN），而出发的包干价里已经含了减速。所以同样的 300 EN：

| 方案 | 结果 |
|---|---|
| 出发到 120 ly | 300 EN，**到达并停泊** |
| 巡航（`coast` 策略） | 300 EN，走满 120 ly 后**永远滑行** |
| 巡航（`halt` 策略） | 300 EN，走 80 ly 后自动制动停下（预留的 100 EN 付了制动） |

**只要你知道要去哪，出发永远不差于巡航。** 巡航是"没地方可指"时的工具，这正是它存在的理由。

## 4. 自由巡航

### 4.1 点火免费，但只在静止时可用

```dart
Future<bool> igniteCruise(Vec3 heading, {FuelPolicy onEmpty = FuelPolicy.halt});
```

- **免费。** 不收点火费，只从点火那一刻开始按秒计电（§3.2）。
- **只在飞船静止时可用。** 动着的船（无论巡航还是滑行）不能点火。
- "静止"本身不区分深空待泊与停靠行星；本规格只在深空暴露入口（§1）。

**为什么必须限制在静止时点火。** 因为点火是免费的，而点火会**设定速度矢量**。如果滑行中的船可以点火，玩家就能：滑行（免费）→ 朝反方向点火（免费）——**得到一次免费的 180° 掉头**，把「修正航向」的收费整个绕过去。

把点火限制在静止时，洞就堵死了，而且规则更好讲：

> **动着的船想改向，只有一条路：修正航向，按 Δv 收费。**

从滑行改向的完整代价因此是 **制动 100 EN + 点火 0 EN = 100 EN**，与"制动停下再重新出发"逐位相同——这是有意的，两条路不该有价差。

### 4.2 耗尽：复用 halt / coast 的选择

巡航没有终点，所以"电量够不够飞完全程"这个问题不成立——但"电用完了怎么办"成立。**点火巡航时弹出与出发同一个 `showFuelChoiceDialog`**（`journey_page/fuel_choice_dialog.dart`），复用它的措辞与选项形状：

| 选项 | 巡航下的含义 |
|---|---|
| `halt` | 电量耗尽前引擎先制动停下：**保留 100 EN 的制动储备**，储备见底即自动制动 |
| `coast` | 电量耗尽后飞船以巡航速度继续滑行 |

**不提供 `refuse`。** 出发时的 `refuse` 问的是"你能不能付得起这整趟"，而巡航没有"整趟"，问题没有指称对象。对话框本来就会按情况裁剪选项（前置规格 §4.2：`energy == 0` 时不给后两项），这里只是换了裁剪条件。

`halt` 的储备规则与 `_launchGate` 的 `> braking` 是同一条：**巡航的可用预算 = `energyBalance - 制动储备`**，储备归零的那一刻自动制动。所以：

- 300 EN + `halt`：可巡航 `300 - 100 = 200 EN` = 80 ly，然后自动制动（100 EN），停在 0 EN。
- 300 EN + `coast`：可巡航 300 EN = 120 ly，然后滑行，停在 0 EN。

**两条路都在 0 EN 结束**，也都进入休眠（§4.3）。中途通过训练补充能量会把耗尽点往后推——与航程的"中途补给能把一趟注定失败的航行拉回来"是同一个机制，因为两者都是"在问的这一刻读余额"。

策略必须落盘（`PlayerState.cruisePolicy`）：耗尽时船已经没电了，付不起制动，所以这个选择**只能在点火时预先做出**，不能等到耗尽再问。

### 4.3 休眠与激活

**休眠**（`engineDormant`）：电量耗尽，生命维持与照明停止。

**为什么必须是一个落盘字段，而不是 `energy <= 0` 的派生量。** 因为玩家会在休眠后去训练拿能量。如果休眠是派生的，那么训练到 70 EN 的瞬间"休眠"就自动消失了——**玩家只要先去训练一次就能免掉激活费**。这个欠账必须被记下来。

**激活**（`Engine.activationCost = 5` EN）：

```dart
Future<bool> activate();
```

- 把引擎上电，`engineDormant` 置 false，扣 5 EN，记一条 `EnergyTxType.activation`。
- 已经醒着的船调用是 no-op（不扣钱、不记账）。
- 要求 `energyBalance > activationCost`（严格大于），所以激活之后余额至少剩 1 EN，不会停在"醒着但一滴电都没有"的怪状态。

**休眠挡住什么：** 点火巡航、修正航向、`launchJourney` / `launchToStar`。
**休眠不挡什么：** `activate()` 本身，以及 `stopShip()` / 制动。

**为什么制动不受休眠限制。** 制动是脱离滑行的唯一出口，也是本规格要修的那个缺陷的核心。把出口挂在收费门后面，等于把"没有入口"这个毛病换个地方重新造一遍。而且这样**既有测试的算术一位都不用改**：滑行 + 0 EN → 训练到 100 EN → 制动成功，这条路径的每个数字都保持原样。激活费收在**重新出发**这一刻，而不是收在**停下来**这一刻。

能量不足时的指引沿用 `journey_page.dart:822` 的既有做法：禁用按钮 + 「前往训练补充能量」（`ShellScope.go(context, 3)`）。

## 5. 修正航向

### 5.1 定价：真实式 Δv

转向的物理代价是把速度矢量转过 θ，其 Δv 是这段旋转的弦长 `2 v sin(θ/2)`。按引擎的制动距离定价：

```dart
/// Energy to swing the velocity vector by [angleRadians] while carrying
/// [speedLyPerSec], in EN.
///
/// The Δv of a turn is the chord of the rotation, `2 v sin(θ/2)` — priced
/// through [brakingCostFor] so a turn is billed exactly like the braking burn
/// that would have shed the same Δv. They are the same engine work.
int turnCostFor({required double speedLyPerSec, required double angleRadians}) {
  if (speedLyPerSec <= 0) return 0;
  // Turning 350° is turning 10° the other way.
  final a = angleRadians.abs() % (2 * math.pi);
  final turn = a > math.pi ? 2 * math.pi - a : a;
  if (turn == 0) return 0;
  return brakingCostFor(2 * speedLyPerSec * math.sin(turn / 2));
}
```

满速（`v = cruiseSpeed`）时化简为 `energyCostFor(80 · sin(θ/2))`：

| 转角 | 5° | 10° | 30° | **60°** | 90° | 120° | 180° |
|---|---|---|---|---|---|---|---|
| 价格 | 9 EN | 17 EN | 52 EN | **100 EN** | 141 EN | 173 EN | **200 EN** |

`turnCostFor` 是 `Engine` 的方法而不是 `GameController` 的：按 `CLAUDE.md` 的属性归属，"转多少度要多少功"是引擎的能力，换一台引擎就该跟着变。

### 5.2 已知后果：转角超过 60°，制动再点火更便宜

点火免费，所以：

- **转向 180°** = 200 EN
- **制动停下（100 EN）+ 重新点火（0 EN）** = **100 EN**

分界线正好在 **60°**（`80 · sin(θ/2) = 40` ⟹ `θ = 60°`）。**转角大于 60° 时，「制动停下」严格优于「修正航向」。**

这是"真实式 + 免费点火"两条决定的联合推论，不是实现缺陷，但它确实意味着**「修正航向」按钮在大于 60° 时会变成一个陷阱**——玩家按直觉点它，多付一倍的钱。

本规格的处置是**在按钮上把这个规则说出来**，而不是掩盖它：

```
修正航向 · 180° · 200 EN
制动停下只需 100 EN
```

即：当 `turnCost > brakingCost` 时，按钮下方追加一行提示，并把它做成可点（点它等于执行制动）。这样两条路都摆在台面上，玩家自己选。**另一条路是给点火定价**（点火收一次 Δv，则制动 100 + 点火 100 = 掉头 200，两条路打平），但那会让手动飞行整体再贵 100 EN，本次不采纳。

### 5.3 座舱交互

改向发生在星图页的**座舱模式**（`CameraMode.cockpit`），复用既有机械：中央准星、拖动环视、双指调视场（`galaxy_map_3d_page.dart:113-141`、`_CockpitPainter` `:676`）。

**进入时的朝向：**

| 飞船状态 | 座舱对准 |
|---|---|
| 巡航中 | **当前航向**（`driftVelocity` 的方向） |
| 静止 / 滑行 | 银心（沿用 `_aimCockpitAtOrigin` `:298`） |

**HUD（画在既有的 `_CockpitPainter` 图层上，`IgnorePointer` 不变）：**

```
        ┌─────┼─────┐             ← 中央准星 = 拟议的新航向（接管既有淡准星）
        │     ▲     │             ← ▲ = 当前航向标记
        └─────┼─────┘
          偏离 37° · 63 EN         ← 准星下方读数
```

- **中央准星**（既有）：拟议的新航向。
- **当前航向标记**：一个三角，由 `_camera.project(eye + 当前航向 * d, vp)` 得到屏幕位置；若在视野外，贴在屏幕边缘变成箭头。
- **读数**：当前航向与准星的夹角（度）与 `turnCostFor` 的价格。这是玩家唯一需要的两个数。

**微调：拖动灵敏度随视场缩放。**

```dart
final k = 0.006 * (_camera.fovDegrees / 60);
```

默认 60° 视场时与现状逐位相同（`k = 0.006`），双指缩到 30° 视场时灵敏度减半。**捏合同时是望远镜和微调旋钮**，不需要新增模式。

**「对准当前航向」**：`_recenter`（`:305`）在座舱模式下改为调用瞄准助手（巡航时对准当前航向，静止时对准银心）。现在 `_recenter` 在座舱模式下只重置 `eyeOverride`，不碰 yaw/pitch，等于什么都不做——这是一个顺带修掉的小毛病。

**一个按钮，按状态换脸：**

| 飞船状态 | 按钮 | 禁用时 |
|---|---|---|
| 巡航中 | `修正航向 · 37° · 63 EN` | 能量不够：`需要 63 EN（现有 20 EN）` + 「前往训练补充能量」 |
| 巡航中，`turnCost > brakingCost` | 追加一行 `制动停下只需 100 EN`（可点） | — |
| 静止（深空） | `点火巡航`（免费） | 休眠：`引擎离线 · 需要 5 EN 激活` |
| 滑行中（引擎离线） | `制动停下 · 100 EN` | 能量不够 / 休眠：同上 |
| 休眠（任意） | `激活引擎 · 5 EN` | `需要 5 EN（现有 3 EN）` + 「前往训练补充能量」 |

**确认对话框**（付费且不可逆，沿用 `journey_page.dart:213` 的形状）：

```
修正航向
飞船将从当前航向偏转 37°，消耗 63 EN。

  [ 取消 ]        [ 修正 ]
```

## 6. 超出传感器范围的目的地指示

这是对玩家最初报的那个缺陷的直接修复。

座舱模式下，在 `_CockpitPainter` 图层上（**不经过 `sensorRange` 门**）画出目的地方向标记：

```
        ↗ 推荐目的地 · 玄戈四 · 912 ly
```

- 数据来源：`_recommendDestination`（复用 `journey_page.dart:292` 的挑选逻辑，抽成 `GameController.recommendedDestination`）与 `activeJourney.destinationPlanetId`。
- 每个标记给出方向、名字、距离。方向由 `(target.pos - playerPosition3D).normalized` 得到，屏幕位置由 `_camera.project` 得到；视野外贴边显示箭头。
- **只读，不可点。** 目的地在传感器范围外，本来就不该被点选出发；标记的用途是"朝它飞过去，进入传感器范围之后再正式出发"。这正是缺陷描述里缺的那一步。

## 7. 模型变更

### 7.1 `Engine`（`lib/data/models/engine.dart`）

新增：

```dart
/// Energy to bring the engine back online after a dormancy, in EN.
///
/// A property of the engine, not a global: a refit with a cheaper cold start
/// should not have to edit a balance table.
final int activationCost;

/// Energy the engine draws per second while running, in EN/s.
double get powerDrawPerSecond => energyPerLy * cruiseSpeedLyPerSec;

/// Energy drawn by running the engine for [seconds].
///
/// Deliberately written through [energyCostFor] rather than as a flat rate, so
/// that a cruise of D ly costs bit-for-bit what a voyage to D ly costs — the
/// invariant that keeps free cruising from being an arbitrage on the voyage
/// price.
int burnForSeconds(double seconds) => energyCostFor(seconds * cruiseSpeedLyPerSec);

/// Energy to swing the velocity vector by [angleRadians] at [speedLyPerSec].
int turnCostFor({required double speedLyPerSec, required double angleRadians});
```

`Engine.standard` 增加 `activationCost: 5`。

**JSON 迁移：** 缺 `activationCost` 的 `ship.engine` 回落到 `Engine.standard.activationCost`（5），按 `CLAUDE.md` 的迁移优先约定，与既有的 `brakingDistanceLy` 回落同形。

### 7.2 `PlayerState`（`lib/data/models/player_state.dart`）

新增三个字段，**全部有安全默认值，`_saveKey` 不 bump**：

| 字段 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `driftPowered` | `bool` | `false` | 引擎在线并维持巡航速度 |
| `engineDormant` | `bool` | `false` | 电量耗尽，需要付费激活 |
| `cruisePolicy` | `FuelPolicy` | `FuelPolicy.halt` | 点火时预选的耗尽行为 |

**`driftPowered` 默认 `false` 是正确的迁移**：在本次改动之前，`driftVelocity != 0` 只有一个来源——`_applyFuelOut`，而那是燃料耗尽，引擎必然离线。所以旧存档里所有会动的船，载入后都恰好是滑行。这与 `coast_test.dart:71`（"没有 drift 键的旧存档载入为停泊"）是同一类断言。

**`driftStartedAt` 的语义被扩展，但不需要迁移。** 它现在是"当前这一段运动开始计费的时刻"：

- 滑行时：油箱见底的时刻（不变）。
- 巡航时：引擎点火的时刻。

### 7.3 一条新的三元组不变式

> **`(startX/Y/Z, driftStartedAt, driftVelocity)` 永远是一句完整的话："从这一刻、这个点、以这个速度"。**
> **任何改变其中一项的操作，必须同时把锚点钉到当前位置、把时钟设为当下。**

这条规则把既有的 `_anchorHere()`（`game_controller.dart:384`：钉锚点 + 清零速度）扩到时钟上。它保证两件事：

1. **位置连续**：新锚点 + 零位移 = 旧锚点 + 旧位移，所以重钉不产生跳变。
2. **不重复计费**：`energy` getter 从 `driftStartedAt` 现算电费，所以每次结算都必须把时钟推到当下，否则同一段时间会被计两次。

### 7.4 `EnergyTxType`（`lib/data/models/energy_transaction.dart`）

新增三个成员：

| 成员 | 记什么 |
|---|---|
| `cruiseCost` | 巡航按秒耗掉的电（`_settleCruise` 的产出） |
| `turn` | 修正航向的 Δv 费用 |
| `activation` | 激活引擎的 5 EN |

`energyTxTypeFromName` 已有 `orElse: () => travelCost` 兜底，旧存档读取安全。

**为什么不让转向复用 `braking`。** 两者都按 Δv 计价，但玩家在账本上要能区分"我刹车花了 100"和"我转向花了 141"——一个是停下，一个是改向，混在一起账本就读不懂了。

**为什么不复用 `travelCost`。** 前置规格 §11 里有一条取舍："制动不是退费，是一笔真实的新支出，所以它值得自己的类型。" 巡航电费与激活费同理，而且玩家需要能看出"我这 300 EN 是飞掉的还是巡航烧掉的"。`Journey.energyCost` 的账目继续是 `travelCost`，不动。

### 7.5 不动的部分

| 模型 | 结论 |
|---|---|
| `Journey` | **不动。** `energyCost` 继续只含航程燃料，`burnedAt` 语义不变 |
| `GameSave` | **不动。** 不新增顶层标记 |
| `_saveKey` | **不 bump**（`starward.save.v2` 不变） |

## 8. 控制器变更（`lib/state/game_controller.dart`）

### 8.1 `isCoasting` 被重新定义

现状：`bool get isCoasting => _player.driftVelocity.length > 0;`（`:272`）——它实际的意思是"有动量"。加了巡航之后，巡航的船也有动量，这个判据会把它误判成滑行。

```dart
/// Whether the ship is carrying its own momentum, as opposed to being parked,
/// docked, or on a voyage (whose position is derived from the route).
bool get hasMomentum => _player.driftVelocity.length > 0;

/// Moving without power: the engine is off and nothing is being burned.
bool get isCoasting => hasMomentum && !_player.driftPowered;

/// Moving under power: the engine is holding the ship at cruise speed, and
/// the tank is draining every second.
bool get isCruising => hasMomentum && _player.driftPowered;
```

**向后兼容：** 旧存档与所有既有测试里，有动量就意味着滑行（§7.2），所以 `isCoasting` 的取值逐位不变。

### 8.2 `brakingCost` 的判据换成 `hasMomentum`

```dart
/// What it costs to bring the ship out of its current motion, in EN.
///
/// Zero only for a ship at rest. A cruising ship carries the same cruise
/// speed a coasting one does, so shedding it costs the same 100 EN.
int get brakingCost =>
    hasMomentum ? _ship.engine.brakingCostFor(_player.driftVelocity.length) : 0;
```

现状读的是 `isCoasting`（`:278`）。换成 `hasMomentum` 之后，**巡航的船也被正确报价 100 EN**——这是必须的：`_anchorHere()` 在 `launchJourney` / `launchToStar` 里收费，如果巡航中出发不收这笔，玩家就能"免费巡航到目的地附近，再从那儿出发"，把巡航当免费摆渡。

`canBrake`（`:919`）同样换成 `!hasMomentum || _player.energyBalance >= brakingCost`，并追加休眠条件：

```dart
bool get canBrake => !hasMomentum || _player.energyBalance >= brakingCost;
```

（休眠不挡制动，见 §4.3。）

### 8.3 `energy` getter 增加巡航分支

```dart
int get energy {
  final j = _activeJourney;
  if (j != null && j.status == JourneyStatus.inProgress) {
    final left = _player.energyBalance - j.burnedAt(_now());
    return left < 0 ? 0 : left;
  }
  if (isCruising) {
    final burned = _ship.engine.burnForSeconds(_driftSecondsAt(_now()));
    final left = _player.energyBalance - burned;
    return left < 0 ? 0 : left;
  }
  return _player.energyBalance;
}
```

与航程分支同形：不预扣，从时间戳现算，所以杀掉进程再启动读数依然正确。

### 8.4 新增的公开 API

```dart
/// Whether the ship is out of power — lights, life support and engine all off.
bool get isDormant => _player.engineDormant;

/// Energy left before the engine's pre-committed exhaustion policy fires.
/// `halt` keeps the braking burn in hand; `coast` has promised nothing.
int get cruiseReserve =>
    _player.cruisePolicy == FuelPolicy.halt ? brakingCost : 0;

/// How long the current cruise can still run, or zero when not cruising.
/// `(energy - cruiseReserve) / powerDrawPerSecond`, floored at zero — the same
/// reading the dock shows as 「可维持」.
Duration get cruiseRemaining;

/// What a turn to [heading] would cost right now, in EN.
/// Zero when the ship is not cruising.
int turnCostTo(Vec3 heading);

/// The angle between the current heading and [heading], in radians.
double turnAngleTo(Vec3 heading);

/// Wakes the engine after a dormancy. No-op when already awake.
Future<bool> activate();

/// Lights the engine and sets a heading. Free, but only from rest (§4.1).
Future<bool> igniteCruise(Vec3 heading, {FuelPolicy onEmpty});
/// Swings the velocity vector to [heading], keeping the speed. Paid by Δv.
Future<bool> correctHeading(Vec3 heading);

/// Opens the star map in cockpit mode, ready to set a heading.
Future<void> requestCockpit();
bool get cockpitRequested;
void acknowledgeCockpitRequest();

/// Nearest not-yet-explored planet — the recommendation card's pick, lifted
/// out of the page so the cockpit HUD can draw a marker for it too.
Planet? get recommendedDestination;
```

### 8.5 结算点

> **`energyBalance` 只在四个事件上结算，其余时间由 `energy` 现算：点火、修正航向、制动、电量耗尽。**

```dart
/// Bills the power drawn since the engine came online, once, and re-pins the
/// leg's clock and anchor to now.
///
/// Mirrors `_settleBurn`: `burnForSeconds` reads only the elapsed time, so
/// settling before or after a state change books the same amount — it is the
/// single call site, not the ordering, that prevents double-booking. The
/// re-pin is what keeps it single: the next reading counts from here.
int _settleCruise() {
  if (!_player.driftPowered) return 0;
  final burned = _ship.engine.burnForSeconds(_driftSecondsAt(_now()));
  if (burned > 0) { /* 扣款 + 记一条 cruiseCost */ }
  _repinLeg();   // 锚点钉到当前位置，driftStartedAt = now
  return burned;
}
```

`_repinLeg()` 是 §7.3 那条不变式的实现，同时被点火、修正航向、制动、耗尽复用。

### 8.6 耗尽：`_reconcileCruise()`

`tick()`（`:730`）目前只调和航程。加一条平行的分支：

```dart
void tick() {
  if (_reconcileCruise()) { _persist(); notifyListeners(); return; }
  // …既有航程分支与 _maybeRescanNearby 不变
}
```

`_reconcileCruise()` 在 `isCruising` 且已烧到预算时：

1. `_settleCruise()` 结清这一段（`halt` 时预算 = `balance - reserve`；`coast` 时预算 = `balance`）。
2. 记一份 `DriftReport(kind: fuelOut)`——**复用既有的耗尽播报**，与 `_applyFuelOut`（`:583`）同形，只是这一段来自巡航而不是航程。
3. `halt`：`_anchorHere()`（收 100 EN 制动费，清零速度，重钉）。
   `coast`：`driftPowered = false`，保留速度，重钉。
4. `engineDormant = true`（两条路都走到 0 EN）。
5. `_rebuildNearby()`。

### 8.7 休眠的置位与清除

**置位：** 任何一次扣款把 `energyBalance` 打到 0 之后。收口成一个私有助手，在 `_settleBurn` / `_settleTank` / `_settleBraking` / `_settleCruise` 之后各调一次。这样"电量耗尽"只有一个定义。

**清除：** 只有 `activate()`。`_addEnergy`（`:1195`）**不清除**休眠——这正是 §4.3 那个字段存在的理由。

### 8.8 点火与改向的实现要点

```dart
Future<bool> igniteCruise(Vec3 heading, {FuelPolicy onEmpty = FuelPolicy.halt}) async {
  if (_activeJourney?.status == JourneyStatus.inProgress) return false; // 航程中
  if (hasMomentum) return false;        // §4.1：只在静止时点火
  if (isDormant) return false;
  if (heading.length <= 0) return false;
  if (_player.currentPlanetId != null) return false;  // §1：只在深空

  _player = _player.copyWith(
    driftVelocity: heading.normalized * _ship.engine.cruiseSpeedLyPerSec,
    driftPowered: true,
    cruisePolicy: onEmpty,
    driftStartedAt: _now(),
    startX: playerPosition3D.x, startY: playerPosition3D.y, startZ: playerPosition3D.z,
  );
  await _persist();
  notifyListeners();
  return true;
}

Future<bool> correctHeading(Vec3 heading) async {
  if (!isCruising || isDormant) return false;
  final cost = turnCostTo(heading);
  if (_player.energyBalance - cost < cruiseReserve) return false;  // 不能花掉储备
  _settleCruise();                       // 先结清这一段，再改向
  _player = _player.copyWith(
    energyBalance: _player.energyBalance - cost,
    driftVelocity: heading.normalized * _ship.engine.cruiseSpeedLyPerSec,
  );
  // _settleCruise 已经重钉过锚点与时钟；改向不改位置，所以锚点仍然正确
  // …记一条 turn（金额 -cost）
  await _persist();
  notifyListeners();
  return true;
}
```

`onEmpty` 的默认值与 `Journey.fuelPolicy` 一致取 `halt`。真正的入口永远由对话框显式传值，所以默认值只影响旧存档（永远读不到）与测试。

**`correctHeading` 的花费上限。** 转向花的钱不能吃掉 `halt` 的制动储备，否则"转向把自动制动的钱花掉了"会让 `halt` 的承诺落空。所以门槛是 `energyBalance - cost >= cruiseReserve`。`coast` 策略下储备为 0，门槛就是普通的有钱。

### 8.9 与既有路径的相互作用

| 既有路径 | 影响 |
|---|---|
| `_anchorHere()`（`:384`） | 加一行：`driftPowered: false`，`driftStartedAt: _now()`。收费逻辑不动，但巡航中出发现在会正确收 100 EN（§8.2） |
| `_applyFuelOut()`（`:583`） | 加两行：`driftPowered: false`、`engineDormant: true` |
| `launchJourney` / `launchToStar` | 加休眠门槛：`if (isDormant) return LaunchResult.engineDormant;`（`LaunchResult` 新增成员，`_launchMessage` 同步） |
| `stopShip()`（`:935`） | **顺序要紧：先 `_settleCruise()`，再检查 `canBrake`。** `canBrake` 读的是 `energyBalance`，而巡航那一段电费还没结算；先结算再判，才能保证"按钮亮着就真的停得下来"。之后再 `_anchorHere()`。`canBrake` 已含巡航 |
| `_applyArrival()` | 加 `engineDormant` 判定：到达时若余额为 0，船是休眠的 |

## 9. UI 变更

### 9.1 `_DriftDock` 变成可操作（`journey_page.dart:663`）

```
当前坐标 · 深空
X 1234.5  Y -88.0  Z 402.1 ly

[ 点火巡航 · 选择方向 ]                    ← 切到星图座舱模式
```

休眠时（`_EnginePanel`，见 §9.3）：

```
引擎休眠中 · 生命维持与照明已停止
需要 5 EN 激活

[ 激活引擎 · 5 EN ]                        ← 能量 <= 5 时禁用 + 「前往训练补充能量」
```

### 9.2 `_CoastDock` 增加巡航读数与重新点火（`:716`）

在既有的制动读数下追加：

```
巡航中 · 巡航速度
0.0267 ly/s
已巡航          12 分钟
本段距离        19.2 ly
当前坐标        X 1234.5  Y -88.0  Z 402.1
耗电            0.0667 EN/s（剩余 252 EN）
可维持          38 分钟（保留 100 EN 用于制动）   ← halt 策略才有括号里那句
```

（数字是自洽的：12 分钟 = 720 秒 → 19.2 ly → `energyCostFor(19.2) = 48 EN`，余额 300 − 48 = 252；`halt` 的可用预算是 252 − 100 = 152 EN，即 38 分钟。）

按钮区追加一行 `[ 修正航向 ]`（巡航时）或 `[ 重新点火 ]`（滑行且醒着时）→ 座舱模式。既有的「制动停下」「改变航向」「查看播报」全部保留，行为不变。

### 9.3 抽出 `_EnginePanel`

`_DriftDock` 与 `_CoastDock` 现在都要渲染同一块"休眠 / 激活"UI。抽一个 `_EnginePanel` 组件给两者共用，避免把激活入口写两遍。`journey_page.dart` 已经 1455 行，这是本规格唯一的结构性整理，不做更大的拆分。

### 9.4 星图页（`galaxy_map_3d_page.dart`）

| 位置 | 改动 |
|---|---|
| `build` | `cockpitRequested` 为真时，`addPostFrameCallback` 里 `_setMode(CameraMode.cockpit, vp)` + `acknowledgeCockpitRequest()`（不能在 build 里 setState） |
| `_setMode`（`:283`） | 进座舱时：巡航中 → 对准当前航向；否则 → `_aimCockpitAtOrigin()` |
| `_recenter`（`:305`） | 座舱模式下改为调用同一个瞄准助手（现在它什么都不做） |
| `_onScaleUpdate`（`:113`） | 座舱灵敏度改为 `0.006 * (fovDegrees / 60)` |
| `_CockpitOverlay`（`:667`） | 从 `const` 改为接收参数：拟议航向、当前航向、角度、价格、目的地标记列表 |
| `_CockpitPainter`（`:676`） | 画当前航向三角（视野外贴边）、读数、目的地标记；`shouldRepaint` 不能再恒为 false |
| 新增 `_HeadingBar` | 底部按钮 + 禁用文案 + 「制动停下只需 100 EN」提示行 |

### 9.5 新增 `EnergyTxType` 的显示

账本页若有类型标签映射，补 `cruiseCost`（"巡航耗电"）与 `activation`（"激活引擎"）两项。

## 10. 测试策略

沿用 `CLAUDE.md`：TDD 先行、`FakeClock` + 固定 seed、`MemoryStorage`、**钉住具体数字**。

### 10.1 必须覆盖

**定价**

1. `burnForSeconds` 钉死数字：37.5 s → **3**；1500 s → **100**；4500 s → **300**；0 s → **1**（地板，不是 0）。
2. **核心不变式**：对 `D ∈ {1, 5, 40, 120, 200}`，`burnForSeconds(D / cruiseSpeedLyPerSec) == energyCostFor(D)`。
3. `powerDrawPerSecond` == `0.0666667`（1e-6 精度）。
4. `turnCostFor` 钉死：5°→9、10°→17、30°→52、60°→**100**、90°→**141**、180°→**200**、0°→0、360°→0、**350°→17**（等于 10° 的另一边）。速度为 0 → 0。

**点火**

5. 深空静止点火 → `driftVelocity.length == cruiseSpeed`、`driftPowered == true`、锚点钉在原点、`driftStartedAt == now`；余额不变。
6. **有动量时点火返回 false**（§4.1 的洞）：滑行中点任意方向点火 → 状态一位不变。这条是免费点火不成为免费掉头的唯一保证，必须有。
7. 停靠行星时点火返回 false。
8. 休眠时点火返回 false。
9. 航程进行中点火返回 false。

**耗电**

10. 点火后 `advance(1500 s)` → `energy == balance - 100`，且 `energyBalance` **未变**（现算，未结算）。
11. 杀掉进程重启（用 `MemoryStorage` 重新 `_boot`）后读数一致。
12. 点火后 4500 s → `energy == 0`。

**耗尽**

13. `coast`：点火（300 EN）→ `advance(4500 s)` → `tick()` → `driftPowered == false`、`hasMomentum == true`、`isCoasting == true`、`energyBalance == 0`、`engineDormant == true`、账本一条 `cruiseCost` −300、一份 `DriftReport(kind: fuelOut)`。
14. `halt`：点火（300 EN）→ `advance(3000 s)` → `tick()` → 速度归零、位置 = 80 ly 处、账本 `cruiseCost` −200 与 `braking` −100、余额 0、休眠。
15. **`halt` 的储备不被转向吃掉**：300 EN + `halt` 点火 → `advance(300 s)`（耗 20 EN，余额 280）→ 转向 180°（200 EN）→ **false**（`280 − 200 = 80 < 100`）；转向 30°（52 EN）→ 成功，余额 228。边界那一侧：余额正好 300 时转 180°（`300 − 200 = 100 >= 100`）→ **成功**，因为储备恰好保住。
16. 中途补给推后耗尽点：`coast` 巡航中完成一组训练（+40 EN）→ 耗尽点从 4500 s 移到 **5100 s**（40 / 0.0666667 = 600 s）。

**休眠与激活**

17. 耗尽后 `isDormant == true`；`activate()` → 余额 −5、`isDormant == false`、账本一条 `activation`。
18. **训练不清除休眠**：耗尽后训练到 70 EN → `isDormant` 仍为 true，且 `launchJourney` 返回 `engineDormant`。
19. 已醒着时 `activate()` 是 no-op（不扣钱、不记账）。
20. 余额 <= 5 时 `activate()` 返回 false。
21. **制动不受休眠限制**：休眠 + 滑行 + 余额 100 → `stopShip()` 成功。这条钉住 §4.3 的决定。

**修正航向**

22. 巡航中转向 90° → `driftVelocity` 方向变了、**长度不变**（仍是巡航速度）、账本新增两条：一条 `cruiseCost`（这一段按秒耗的电，钉具体数）与一条 `turn` −141；余额 = 结算前余额 − 电费 − 141。
23. 结算不重复：转向后再 `advance` 一段再转向，账本金额 = 两段电费之和（各自钉数字），无重复。
24. 位置连续：转向前后同一时刻的 `playerPosition3D` 逐位相同。
25. 转向后锚点 = 转向时的位置，`driftStartedAt` = 转向时刻。
26. 非巡航时 `correctHeading` 返回 false。

**不变式**

27. `driftPowered ⟹ hasMomentum`；`engineDormant ⟹ !driftPowered`。
28. `driftVelocity != 0` ⟹ `_activeJourney == null`（既有不变式，巡航路径也要满足）。
29. **每个结算点恰好一条账目**：点火（0 条）→ 转向（2 条：`cruiseCost` + `turn`）→ 转向（2 条）→ 制动（2 条：`cruiseCost` + `braking`）= **6 条**，且**没有任何零额条目**（点火后立刻转向时电费可能为 0，`_settleCruise` 的 `burned > 0` 守卫要挡住它）。

**存档**

30. 三个新字段的 JSON 往返。
31. **旧存档缺三个键 → `driftPowered == false`、`engineDormant == false`、`cruisePolicy == FuelPolicy.halt`**。
32. **带速度但无 `driftPowered` 键的旧存档载入后是滑行**（`isCoasting == true`、`isCruising == false`）——这是本次迁移的核心断言。
33. `Engine.fromJson` 缺 `activationCost` → 5。

**回归**

34. 停泊 / 停靠 / 航程中三种状态下 `brakingCost == 0`、`energyCostTo` 与改动前逐位相同。
35. 既有 `coast_test.dart` / `braking_test.dart` / `fuel_out_test.dart` 全绿。

### 10.2 既有测试的影响（已核查）

| 测试 | 结论 |
|---|---|
| `coast_test.dart:71` "an old save with no drift keys loads as parked" | 不涉及新键，通过 ✓ |
| `coast_test.dart` 的 `_setDrift`（`:32`） | 只写 `driftVelocity*` 与 `driftStartedAt`，`driftPowered` 缺省为 false → 载入即滑行 ✓ **不需要改** |
| `coast_test.dart:259` "measures from the moment the tank emptied" | `isCoasting` 语义未变 ✓ |
| `braking_test.dart` 条目 8（0 EN 滑行 → 训练到 100 → 制动成功） | 制动不受休眠限制（§4.3），逐位不变 ✓ **这是选"休眠不挡制动"的直接原因** |
| `braking_test.dart` 其余条目 | 都在停泊 / 停靠状态，`hasMomentum == false` ✓ |
| `fuel_out_test.dart` | 只涉及航程耗尽，`_applyFuelOut` 仅新增两个字段赋值 ✓ |
| `energy_test.dart` / `real_time_energy_test.dart` | 不巡航、不点火，`energy` getter 的巡航分支不进入 ✓ |

**需要新增而非改写的测试文件：** `test/cruise_test.dart`（点火、耗电、耗尽、休眠、激活）、`test/heading_test.dart`（转向定价与结算）、`test/cruise_save_test.dart`（迁移）。

### 10.3 需要留意但预期不改

- `widget_smoke_test.dart` 会把 `HomeShell` 整个搭起来（四个 Tab 全在 `IndexedStack` 里），所以 `_DriftDock` 与 `_CoastDock` 的新按钮必须能无异常构建。它不断言 dock 内容，所以预期不用改——但它是唯一会碰这条路径的测试，执行时必须跑。
- `home_shell.dart:73` 的徽标条件 `activeJourney != null || isCoasting` 需要加上 `isCruising`，否则巡航中切到训练页徽标不亮——与前置规格 §7.3 是同一个毛病。**这一条要改。**

## 11. 实施顺序

四个阶段，每阶段独立可发布、可测试、不留半成品。

**阶段 1 — 能量模型的词汇。** `Engine.activationCost` / `powerDrawPerSecond` / `burnForSeconds` / `turnCostFor` + JSON 迁移 + `EnergyTxType` 两个新成员 + `PlayerState` 三个新字段 + `GameController` 的 `hasMomentum` / `isCoasting` / `isCruising` / `brakingCost` / `canBrake` / `isDormant` / `cruiseReserve`。**玩家可见变化：无。** 全部是新增，既有路径逐位不变。这一阶段必须单独发布以便验证"重构不改变行为"。

**阶段 2 — 点火与耗电。** `igniteCruise`、`energy` getter 的巡航分支、`_settleCruise`、`_repinLeg`、`_reconcileCruise`、`tick` 分支、`_anchorHere` 的三个新赋值。**玩家可见变化：无入口，但控制器已经能巡航。** 靠 `cruise_test.dart` 验证。

**阶段 3 — 休眠与激活。** `engineDormant` 的置位收口、`activate()`、`LaunchResult.engineDormant`、`launchJourney` / `launchToStar` 的门槛、`_EnginePanel`、`_DriftDock` 与 `_CoastDock` 的按钮（激活引擎 / 点火巡航 · 选择方向 / 修正航向）。**玩家可见变化：深空待泊终于有按钮了；耗尽后多一个 5 EN 的激活动作。**

**阶段 4 — 座舱改向。** `correctHeading`、`requestCockpit` 跨 Tab 机制、`_CockpitOverlay` 参数化、当前航向标记与读数、FOV 缩放灵敏度、`_recenter` 修好、`_HeadingBar`、超出范围的目的地标记。**玩家可见变化：星图座舱能改向，能看见远处的目的地。**

阶段 1 必须先做（其余全部依赖它的词汇）；阶段 2 与阶段 3 可以并行（3 只依赖 1，但它的 UI 要等 2 的 `_settleCruise` 才能跑通端到端）；阶段 4 依赖 2 与 3。

## 12. 已知取舍

- **转角超过 60°，「修正航向」比「制动停下」贵一倍**（§5.2）。这是"真实式 Δv + 免费点火"的联合推论。处置是在按钮上把这条规则说出来，而不是掩盖。要彻底消掉它，得给点火定价——那会让手动飞行整体再贵 100 EN，本次不采纳。
- **点火只在静止时可用**（§4.1）。这条限制是为了堵住"滑行 + 免费点火 = 免费掉头"的洞。代价是滑行中想改向必须先制动（100 EN），不能直接重新点火。
- **休眠不挡制动**（§4.3）。这条不对称是刻意的：制动是脱离滑行的唯一出口，把出口挂在收费门后面会重新制造"没有入口"的缺陷。副作用是"引擎休眠却能制动"在物理上说不通——用一个例外换掉一个软锁。
- **每次结算有最多 1 EN 的取整漂移**。`burnForSeconds` 走 `energyCostFor`，所以低于 37.5 秒的一段电费按 `minEnergyCost` 收 1 EN。频繁机动会比连续飞行多花一点。方向是安全的（多收而不是少收），量级有界（每次机动 ≤ 1 EN，而每次机动本身 ≥ 2 EN）。
- **`cruisePolicy` 必须预先选定**（§4.2）。耗尽时船已经没电，付不起制动，所以 `halt` 只能在点火时承诺。这是"巡航没有终点"的直接推论，不是实现选择。
- **巡航在经济学上永远不优于出发**（§3.3）。这是有意的：巡航是"没地方可指"时的工具，不是省钱的工具。300 EN 出发能到 120 ly 并停下，300 EN 巡航（`halt`）只能到 80 ly 并停下——因为它得自己付那 100 EN 的制动费，而出发的包干价里已经含了减速。
- **本规格只在深空提供点火巡航**（§1）。从停靠行星起飞但没有目的地，牵出的是另一串产品问题，不在本次范围内。
- **`_DriftDock` 与 `_CoastDock` 只做了 `_EnginePanel` 级别的抽取**（§9.3）。`journey_page.dart` 已经 1455 行，两个 dock 有更多可合并之处，但那是独立的重构，不夹带在本次改动里。
