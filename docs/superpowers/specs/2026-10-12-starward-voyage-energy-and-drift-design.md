# Starward 航行能量与滑行设计规格

**日期：** 2026-10-12
**状态：** 待审阅
**范围：** `starward/` 的能量消耗模型、燃料耗尽行为、深空滑行与离线播报
**前置：** `Engine` / `Ship` 重构（属性归属于实体）已完成，本规格沿用该约定

## 1. 目标与边界

把"出发时一次性扣费"改成"随航程实时燃烧燃料"，并处理烧完之后会发生什么。

必须做到：

1. **能量实时消耗**：飞船按已飞过的距离连续烧燃料，而不是出发时一次性扣除。
2. **燃料耗尽三选一**：能量不足以飞完全程时，出发前给玩家三个选择——放弃航行 / 耗尽后停在原地 / 耗尽后继续滑行漫游。
3. **有界无边宇宙**：滑行的飞船抵达宇宙边界后贴着边界继续航行，永远不会漂进空无一物的虚空。
4. **滑行播报**：在线时实时显示位置/速度/航程/途经星系；离线再启动时，一次性算出期间经历了多久、飞了多远、路过哪些星系、现在在哪。

不做：

- 不改动力系统的物理模型（`Engine` 的 `energyPerLy` / `travelSecondsPerLy` 数值不动）。
- 不做燃料补给站、不引入"燃料"这个独立资源——**能量就是燃料**。
- 不做返航时的三选一（见 §4.5）。
- 不做跨存档的航行历史/统计页。

## 2. 现状（改动前）

- `Journey` 只存 `departure` / `arrival` / `energyCost`，进度由时间戳推导（`journey.dart:39`）。
- `launchJourney` 校验 `energyBalance >= cost`，通过后**一次性** `_spendEnergy(cost, ...)`（`game_controller.dart:383`）。
- 深空状态是**静止的**：`playerPosition3D` 直接返回 `startX/Y/Z`，不随时间变化（`game_controller.dart:206`）。
- 能量不足时 `launchJourney` 返回 `insufficientEnergy`，UI 显示"前往训练补充能量"，**无法出发**。
- `Engine.standard`：2.5 EN/ly，37.5 s/ly → 巡航速度 **0.02667 ly/s = 2304 ly/天**，燃烧率 **0.0667 EN/s**。

## 3. 核心模型：能量是随距离燃烧的燃料

### 3.1 实时燃烧

**出发时不扣任何能量。** 存档里的 `energyBalance` 在航行期间表示"船上还剩多少可用燃料总量"；玩家看到的是**派生值**：

```dart
// Journey — 已烧掉的燃料，正比于已飞过的距离
int burnedAt(DateTime now) => (energyCost * progressAt(now)).round();

// GameController — 实时能量（派生，不落库）
int get energy {
  final j = _activeJourney;
  if (j == null || j.status != JourneyStatus.inProgress) return _player.energyBalance;
  final left = _player.energyBalance - j.burnedAt(_now());
  return left < 0 ? 0 : left;
}
```

性质：

- 出发瞬间 `energy == energyBalance`（一滴没烧）；抵达时 `energy == energyBalance - energyCost`。
- 依然是**时间戳推导**，没有常驻计时器。App 被杀掉再启动，`progressAt(now)` 直接算出烧了多少（`journey.dart:14-16` 的不变量完好）。
- `burnedAt` 正比于进度、进度正比于距离，所以燃烧率就是引擎的 `energyPerLy` —— 燃料消耗仍然是引擎的属性。

### 3.2 为什么不在出发时扣除

一次性扣除与实时消耗在结构上不相容。若出发时先扣 `cost`，再用 `balance + cost*(1-p)` 还原实时值，则**能量不足以飞完全程时根本无法出发**——而这正是本规格要支持的情形。所以唯一自洽的做法是：**账只在真正烧掉的时候记**。

这同时消解了"退费"这个概念（用户 2026-10-12 已指出）：中途停下时，没烧掉的燃料**从来没有离开过玩家的账户**，不存在退款。

### 3.3 结账（settle）

燃烧只在**航程终止**时落库，写一条 `EnergyTxType.travelCost` 的账目，金额 `-burnedAt(t_end)`：

| 终止事件 | 结算金额 | 备注 |
|---|---|---|
| 抵达目的地 | `-energyCost` | 与旧行为一致 |
| 燃料耗尽停下 | `-energyBalance` | 全部烧光，余额归零 |
| 燃料耗尽转滑行 | `-energyBalance` | 同上，之后滑行不再耗能 |
| 中途停止（`abortJourney`） | `-burnedAt(now)` | 只结算已烧掉的部分，**没有退款条目** |
| 返航（`returnToOrigin`） | 先结算去程已烧部分，再为返程段报价 | 见 §4.5 |

`EnergyTxType` **不新增成员**，也不需要 refund 类型。

### 3.4 航行途中获得的能量

训练在航行途中依然可用（`startCourse` / `completeCourse` 没有位置与能量前置条件）。训练奖励直接加到 `energyBalance` 上，于是：

- 实时能量自动跟着涨；
- **航行途中补给可以救回一次注定失败的航程**——若补给后 `energyBalance >= energyCost`，耗尽点被推到航程之外，飞船正常抵达。

这是模型自然涌现的行为，不需要额外代码，但要在测试里钉住。

### 3.5 存档迁移

`Journey` **不新增字段**，`burnedAt` 由已有的 `energyCost` / `departure` / `arrival` 推导，所以第 1 阶段零结构变更。

唯一需要处理的是**旧存档里正在进行的航程**：v2 存档在出发时已扣过 `energyCost`，而新模型要求 `energyBalance` 表示"未燃烧的总量"。`GameSave` 增加顶层标记：

```dart
// toJson: 'energyModel': 2
// fromJson: 若 json['energyModel'] 缺失（v2 存档）且存在 inProgress 航程，
//           则 player.energyBalance += journey.energyCost，把已扣的那笔加回来。
```

迁移后语义立刻自洽，不需要 bump `_saveKey`，玩家进度不丢（遵循 `CLAUDE.md` 的迁移优先约定）。

## 4. 燃料耗尽：三选一

### 4.1 耗尽点

燃料在 `burned == energyBalance` 时烧完，即进度：

```
p_exhaust = energyBalance / energyCost
t_exhaust = departure + totalDuration * p_exhaust
pos_exhaust = origin + (dest - origin) * p_exhaust
```

- `p_exhaust >= 1`：飞得到，正常抵达。
- `p_exhaust < 1`：飞不到，`p_exhaust` 处烧干。

三个数都是闭式的，离线补算同样成立。`energyBalance` 取**判定时刻**的余额——航行途中补给会把它抬高，从而把耗尽点推到更远（§3.4）。

### 4.2 出发时的选择

```dart
enum FuelPolicy {
  /// 能量不够就拒绝出发（玩家还没选）。
  refuse,
  /// 烧干后停在原地，漂浮于深空。
  halt,
  /// 烧干后以巡航速度继续滑行。
  coast,
}

Future<LaunchResult> launchJourney(Planet target, {FuelPolicy onEmpty = FuelPolicy.refuse});
Future<LaunchResult> launchToStar(int hygId, {FuelPolicy onEmpty = FuelPolicy.refuse});
```

- 默认 `refuse` → 现有调用点行为完全不变（`insufficientEnergy`）。
- UI 在 `energy < energyCost` 时弹出三选一，玩家选定后带 policy 重新调用。

**出发门槛随 policy 变化**：`onEmpty == refuse` 时要求 `energyBalance >= energyCost`（同今天）；`onEmpty` 为 `halt` / `coast` 时门槛降为 `energyBalance > 0`。

**`energy == 0` 时不提供后两个选项**——没有燃料就动不了，只能放弃或去训练。

### 4.3 停下（`halt`）

在 `t_exhaust` 把飞船停在 `pos_exhaust`，结算全部余额，航程结束，飞船进入**零速度漂流**（即今天的深空待命状态）。玩家看到一次"燃料耗尽，飞船停在深空"的播报（§6.3），之后与 `abortJourney` 的结果无异。

### 4.4 滑行（`coast`）

在 `t_exhaust` 结算余额，航程结束，飞船从 `pos_exhaust` 起以**巡航速度**进入漂流：

```
velocity = (dest - origin) / totalDuration     // ly/s，恒速
```

之后不再耗能，也不再减速——`halt` 与 `coast` 唯一的区别就是这个速度矢量。

### 4.5 返航不做三选一

`returnToOrigin` 先结算去程已烧部分，然后**要求足额支付返程段**，付不起就返回 `insufficientEnergy`。

这是有意的简化：返航是一次救援机动，规则越简单越好；付不起时玩家可以"停止"（`abortJourney`）再回星图重新规划。返程段本身仍然按实时燃烧推进（它是一条普通 `Journey`）。

## 5. 有界无边的宇宙

### 5.1 实测（2026-10-12 用 `assets/stars/hyg.bin` + `SyntheticGalaxy.all()` 测得，共 120,601 颗星）

| 分位 | 半径 (ly) |
|---|---|
| p50 | 703 |
| p75 | 1299 |
| p90 | 2548 |
| **p95** | **3066** |
| p99 | 3631 |
| max | 3948 |

沿半径为 R 的球面取 256 个均匀采样点，统计每点 960 ly 内（`_rebuildNearby` 的最大搜索半径）的恒星数：

| R | 壳外星数 | 壳上 960 ly 内恒星 min / avg | 采样点中不足 25 颗星的 |
|---|---|---|---|
| 2548 | 10.1% | 121 / 532 | 0 / 256 |
| 2900 | 6.1% | 52 / 371 | 0 / 256 |
| **3066 (p95)** | **5.0%** | **35 / 315** | **0 / 256** |
| 3200 | 4.1% | 22 / 263 | 3 / 256 |
| 3631 | 1.0% | 4 / 123 | 188 / 256 |
| 3948 (max) | 0% | 0 / 9 | 256 / 256 |

结论：**把边界放在最外层（3948）等于把船放进真空**——这正是"无限滑行"方案 2.2 天就会撞上的死局。边界必须落在恒星密度还够用的地方。

### 5.2 边界半径

```dart
// Universe — 包含 95% 恒星的半径，惰性计算一次并缓存
double get universeRadius;
```

规则用**分位数而不是硬编码常数**：新增星系时边界自动外扩，不需要有人记得改魔法数字。实测值 **3066 ly**，在壳上任意采样点 960 ly 内至少 35 颗星（约 15 颗行星，`_rebuildNearby` 的目标是 10 颗），256 个采样点无一低于 25 颗。

**边界只约束滑行，不约束动力航行。** 壳外那 5% 的恒星照样是合法目的地（发动机推着去，不是漂着去）。边界是"漂流能到哪"，不是"宇宙有多大"。

在测试里钉住 3066 这个数——星表或星系生成逻辑变了会立刻暴露。

### 5.3 贴边航行的数学

纯函数放在 `lib/core/drift.dart`（只依赖 `Vec3`，不依赖 `data/`）：

```dart
/// 恒速漂流的闭式位置。飞船永远飞不出半径 [bound] 的球。
Vec3 driftPositionAt({
  required Vec3 start,
  required Vec3 velocity,     // ly/s
  required double elapsedSeconds,
  required double bound,
});
```

算法：

1. 解 `|start + v·s|² = bound²` 得撞击时刻 `sHit`（二次方程）。
2. `s <= sHit` → 直线：`start + v·s`。
3. `s > sHit` → 落在球面上，取切向速度 `vt = v - n̂(v·n̂)`，沿大圆滑行：
   `p = bound · (n̂·cos θ + t̂·sin θ)`，`θ = |vt|·(s - sHit)/bound`。

两段都是解析解，所以"一次性根据时间算出当前位置"依然成立。

**退化情况**：撞击瞬间速度几乎纯径向（`|vt| ≈ 0`）时船会卡在球面一点，退化为"贴边停下"。可接受，但要写测试钉住，免得后人当 bug 修。

### 5.4 边界外出发的船

新玩家可能出生在 3066 ly 之外（`randomUniverse` 出生点均匀取自恒星，约 5% 落在壳外）。**不传送。** 规则：

```
bound = max(universeRadius, |driftStart|)
```

即"飞船永远不会漂到比（出发点、宇宙边界）中更远的那个还远的地方"。壳内出发的船漂到 3066 就贴边；壳外出发的船从自己的半径开始贴边，不会被瞬移。

这是罕见角落（要求壳外出生 × 主动选择滑行 × 在壳外烧干），但为了不留下软锁，配套加一条兜底：**`_rebuildNearby` 在半径扩张后仍凑不满 10 颗行星时，退回到全星表最近的一批行星**，保证 `planets` 永远非空。代价是这趟旅程可能很贵，但训练随时可做（无前置条件，40/70/50 EN），能量总能攒出来。

## 6. 滑行状态与播报

### 6.1 漂流（Drift）成为一等状态

给 `PlayerState` 加两个字段，**默认值让今天的行为逐位不变**：

```dart
final Vec3 driftVelocity;      // 默认 Vec3(0,0,0)
final DateTime driftStartedAt; // 默认 epoch
```

```dart
Vec3 get playerPosition3D {
  if (currentPlanet != null) return currentPlanet!.pos;
  return driftPositionAt(
    start: Vec3(_player.startX, _player.startY, _player.startZ),
    velocity: _player.driftVelocity,
    elapsedSeconds: _now().difference(_player.driftStartedAt).inMilliseconds / 1000,
    bound: math.max(_universe.universeRadius, Vec3(startX, startY, startZ).length),
  );
}
```

速度为 0 时 `driftPositionAt` 原样返回 `start`——出生、`abortJourney`、抵达恒星/坐标这四条既有深空路径**行为零变化**。

**任何一次出发都清空漂流**（速度归零，并把 `startX/Y/Z` 重新锚定到当前实际位置），因为发动机接管了运动。这一步是必须的：`_originPosOf` 读的是 `startX/Y/Z`，不重新锚定会拿到漂移前的陈旧坐标。

### 6.2 在线播报

滑行时 `JourneyPage` 的 ticker 继续跑（条件从"有 inProgress 航程"放宽为"有 inProgress 航程 **或** `driftVelocity != 0`），于是星图上的飞船标记会动，滑行页实时刷新。

`_rebuildNearby` 按**位移节流**：自上次扫描以来飞船移动超过 20 ly 才重扫（2304 ly/天 → 约 12.5 分钟一次），避免每帧全表扫描 12 万颗星。

滑行页显示：已滑行时长、累计距离、当前位置坐标、当前速度、途经星系数量。

### 6.3 播报

```dart
enum DriftReportKind {
  /// 航程因燃料耗尽而中止：报"飞了多远、停/滑在哪"。
  fuelOut,
  /// 一段时间窗口内的滑行播报（在线滚动 / 离线补算）。
  drift,
}

class DriftReport {
  final DriftReportKind kind;
  final DateTime from, to;
  final Duration elapsed;
  final double distanceLy;
  final Vec3 fromPos, toPos;
  final int passedCount;            // 途经的**不同**恒星系数量
  final List<PassedSystem> nearest; // 最近接近的若干颗，用于点名
  final bool hitBoundary;           // 是否抵达并贴上了边界（仅 drift 有意义）
}
```

四类窗口，同一个类：

| 场景 | kind | 窗口 `[from, to]` | 生成时机 |
|---|---|---|---|
| 燃料耗尽停下 | `fuelOut` | `[departure, t_exhaust]`（动力段） | 中止那一刻 |
| 燃料耗尽转滑行 | `fuelOut` | `[departure, t_exhaust]`（动力段） | 中止那一刻 |
| 在线滚动播报 | `drift` | `[上次播报, now]` | 滑行页 ticker |
| 离线补算 | `drift` | `[driftStartedAt, now]` | `init()` |

`fuelOut` 的窗口取**动力段**而不是滑行段：那一段才是"刚发生的事"，也是玩家想知道的"我飞到了哪"。滑行段从 `t_exhaust` 起，由随后的 `drift` 播报覆盖。

**生成门槛（关键，避免误报）：只有 `driftVelocity != 0` 时才在 `init()` 里补算离线播报。** 零速度的深空待命（出生、`abortJourney`、`halt`、抵达恒星/坐标）不该弹任何东西——`driftStartedAt` 的缺省值是 epoch，不加这个门槛的话每个新玩家一进游戏就会收到一份"你已滑行 56 年"的播报。

待读播报存在 `pendingDriftReport`，滑行页首次构建时以底部弹层展示，读完清空（`acknowledgeDriftReport()`）。

**途经星系**的判定（`Universe.passedSystemsAlong(...)`，一次全表扫描，O(1)/星，约 2–5 ms）：

- 对每颗星求它到**整条路径**的最近接近距离与对应时刻。路径分两段：直线段用点到线段距离；球面段把星投影到大圆平面上求角度，落在弧范围内则取大圆上的点。
- 最近接近距离 ≤ **20 ly** 记为"途经"。
- 按**恒星 id 去重**（长时间滑行会绕壳多圈，同一颗星可能被反复经过）。
- 按最近接近距离升序取前 8 颗用于点名，其余只计入 `passedCount`。

20 ly 的取法：银心区平均星距 17 ly，边缘区约 300 ly。所以穿越银心时会报出几百个"途经"（合理——那是一片星海），而在边缘空旷区可能是 0（同样合理）。界面文案要能优雅地表达"你穿过了空旷的星际空间"。

### 6.4 长途漂移的数值稳定性

`elapsedSeconds` 会一直变大（离线一周 ≈ 6×10⁵ s）。大圆角 `θ = |vt|·(s - sHit)/bound` 在双精度下到几十年都没有精度问题，且不需要"重新锚定"这类额外存档状态。设计上刻意保持**无状态**：位置永远只是 `(start, velocity, driftStartedAt, now)` 的函数。

## 7. UI 变更

| 位置 | 变更 |
|---|---|
| `planet_details_sheet.dart:384` | 能量不足时不再只显示"前往训练"，改为弹出三选一对话框；对话框要给出具体数字——"你只有 X EN，能飞 Y ly（全程 Z ly）" |
| `galaxy_map_3d_page.dart:176` | `launchToStar` 同样接入三选一 |
| `journey_page.dart:713` `_FlightPanel` | 能量读数改为实时递减（getter 已自动生效，无需改代码）；当 `p_exhaust < 1` 时增加一行警告"燃料将于 Y 后耗尽"，进度条在 `p_exhaust` 处加一个标记 |
| `journey_page.dart:222` `_buildStandby` | 增加"滑行中"变体：星场滚动、实时坐标、已滑行距离/时长、途经星系入口 |
| `journey_page.dart:44` ticker | 滑行时也运行 |
| 新增 | 播报底部弹层，按 `DriftReportKind` 分两种文案（`fuelOut` / `drift`） |

三选一对话框文案（草案）：

```
能量不足以飞完全程
你只有 100 EN，可以飞 40.0 ly，全程 100.0 ly。

  [ 放弃航行 ]   不出发，回星图重新选目标
  [ 耗尽后停下 ] 飞到燃料烧干的位置停下，漂浮于深空
  [ 耗尽后滑行 ] 飞到燃料烧干后，以巡航速度继续滑行漫游
```

## 8. 数据模型变更汇总

| 模型 | 变更 | 迁移 |
|---|---|---|
| `Journey` | 新增 `fuelPolicy`（`halt`/`coast`）；`burnedAt` 是派生方法，无其他字段变更 | 缺省 `halt`；旧存档出发时已足额付费，`p_exhaust >= 1`，永不触发 |
| `PlayerState` | 新增 `driftVelocity` / `driftStartedAt` | 缺省零速度 / epoch → 行为不变 |
| `GameSave` | 新增顶层 `energyModel: 2` | 缺失且存在 inProgress 航程时，把 `energyCost` 加回余额 |
| `EnergyTxType` | 不变 | — |
| `_saveKey` | **不 bump** | — |

## 9. 测试策略

沿用 `CLAUDE.md`：TDD 先行、`FakeClock` + 固定 seed、`MemoryStorage`、**钉住具体数字**。

必须覆盖：

1. **实时燃烧**：出发瞬间余额不变；飞到一半时 `energy == B - round(cost*p)`；抵达后 `energy == B - cost`；账本在抵达时才出现一条 `-cost`（中途停止则是 `-burned`）。
2. **时间戳不变性**：航行中途"杀进程"（新建 controller 读同一份存档）后，能量与位置和连续运行的结果一致。
3. **中途训练救回**：`p_exhaust < 1` 的航程，途中补给使 `energyBalance >= cost`，最终正常抵达、不触发耗尽。
4. **耗尽点闭式**：`p_exhaust`、`t_exhaust`、`pos_exhaust` 三个数与手算一致（钉具体数字）。
5. **`halt`**：停在 `pos_exhaust`，余额为 0，`driftVelocity == 0`，账目 `-B`。
6. **`coast`**：从 `pos_exhaust` 起恒速，位置 = `pos_exhaust + v·(t - t_exhaust)`；余额为 0；之后不再产生账目。
7. **`refuse` 默认**：不传 policy 时行为与改动前逐位相同。
8. **边界**：直线撞壳后沿大圆滑行，`|p| == bound`（容差内）；绕行多圈后位置仍正确；**纯径向退化**卡在壳上一点。
9. **边界外出发**：`|start| > bound` 时不发生瞬移，`|p|` 恒等于 `|start|`。
10. **`universeRadius`**：钉住实测值 3066（容差 ±30），星表变化时报警。
11. **`_rebuildNearby` 兜底**：构造一个 960 ly 内空无一物的位置，断言 `planets` 非空。
12. **途经星系**：在一条已知路径上断言 `passedCount` 与最近接近距离；长时间滑行绕圈后**不重复计数**。
13. **播报**：`init()` 后 `pendingDriftReport` 的时长/距离/位置与手算一致。**反面同样要钉**：零速度的深空待命不得产生任何播报——出生、`abortJourney`、`halt`、抵达恒星、抵达坐标五种情况都断言 `pendingDriftReport == null`。
14. **存档迁移**：v2 存档（有 inProgress 航程、无 `energyModel`）加载后余额被加回 `energyCost`，航程继续正常抵达。

需要改写的既有测试：

- `energy_test.dart:33` "launch deducts exactly the distance-based cost" → 改为"出发不扣除；燃烧随进度累积；抵达时结算全额"。
- `energy_test.dart:96` "every balance change leaves a ledger entry" → 账目在终止时出现，金额相同。
- `return_to_origin_test.dart` 应保持通过（`energyCost` 是报价，仍然被钉住）。

## 10. 实施顺序

四个阶段，每阶段独立可发布、可测试、不留半成品。

**阶段 1 — 实时能量。** `Journey.burnedAt`、`GameController.energy` 派生、终止时结账、`GameSave` 迁移。零新字段（除 `energyModel` 标记）。改完玩家看到能量在航行中递减。

**阶段 2 — 三选一 + 停下。** `FuelPolicy`、`launchJourney`/`launchToStar` 的 `onEmpty`、出发对话框、`p_exhaust` 计算、`halt` 行为与播报。

**阶段 3 — 滑行 + 有界无边。** `PlayerState` 漂流字段、`core/drift.dart`、`Universe.universeRadius`、`_rebuildNearby` 节流与兜底、滑行页与 ticker。

**阶段 4 — 播报。** `DriftReport`、`Universe.passedSystemsAlong`、三种播报弹层。

阶段 3 依赖阶段 2（要先有"滑行"这个选择），阶段 4 依赖阶段 3（要有滑行才谈得上播报）。阶段 1 与 2 之间也是顺序依赖，但阶段 1 单独发布就已经是完整可用的改进。

## 11. 已知取舍

- **边界只约束滑行**：壳外 5% 的恒星动力可达但漂流不可达。这是刻意的——边界的作用是"漂流永远有地方可去"，不是给宇宙设围墙。
- **壳外出生是罕见角落**：不传送、不特殊处理，靠 `_rebuildNearby` 兜底保证不软锁，代价是那趟旅程可能很贵。
- **返航不做三选一**：见 §4.5，有意的简化。
- **20 ly 的"途经"半径在银心会报出几百颗**：这是密度差异的真实反映，不额外做区域自适应。
- **`_rebuildNearby` 在滑行时按位移节流**：12.5 分钟一次重扫，期间地图上的目的地列表可能滞后最多 20 ly。可接受。
