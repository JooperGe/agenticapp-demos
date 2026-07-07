# 04 · 数据契约（Event / Intent / World / LocalModel）

> 目的：把系统里流动的三类数据的**字段结构定死**，作为各模块之间的契约。编码前先对齐这里，避免接口漂移。所有结构用 JS 对象字面量描述（无 TS，但字段与类型注释清楚）。

## 0. 基础约定

### 坐标系与单位

- 球场坐标：`x ∈ [0, 105]`（长，米），`y ∈ [0, 68]`（宽，米）。原点在左下角。
- home 进攻方向 +x（攻右侧球门 x=105），away 进攻方向 -x。中圈 `(52.5, 34)`。
- 速度单位 m/s；角度用弧度，`0` 指向 +x，逆时针为正。
- 时间：`frame`（整数帧号，从 0 起）+ `timeMs`（比赛毫秒）。M1 帧率 60，`dt = 1/60 s`。

### Vec2

```js
{ x: Number, y: Number }   // 米
```

### 枚举（集中定义于 core/enums.js）

```js
TeamId       = 'home' | 'away'
SpeedMode    = 'stand' | 'walk' | 'jog' | 'run' | 'sprint'
Role         = 'GK' | 'CB' | 'LB' | 'RB' | 'CM' | 'LW' | 'RW' | 'ST'   // M1 用得到的子集即可
PhaseMain    = 'PreMatch' | 'Kickoff' | 'InPlay' | 'DeadBall' | 'HalfTime' | 'FullTime'
PhaseSub     = null | 'ThrowIn' | 'Corner' | 'GoalKick' | 'FreeKick' | 'Penalty' | 'KickoffAfterGoal'
RestartType  = 'kickoff' | 'throwIn' | 'corner' | 'goalKick' | 'freeKick' | 'penalty'
BoundarySide = 'touchTop' | 'touchBottom' | 'goalLineHome' | 'goalLineAway'
```

---

## 1. World（权威世界状态，world/World.js）

系统唯一的事实来源。裁判读它、感知读它、物理写它。

```js
World = {
  clock: {
    frame: Number,
    timeMs: Number,       // 比赛已进行毫秒
    half: 1 | 2,
    paused: Boolean,
    speed: Number,        // 倍速；M1 = 1
  },

  phase: {
    main: PhaseMain,
    sub: PhaseSub,               // main==='DeadBall' 时有效
    restartTeam: TeamId | null,  // 死球/定位球归属方
    restartType: RestartType | null,
    restartSpot: Vec2 | null,    // 发球位置
    takerId: String | null,      // 被指派的发球球员 id
    restartReady: Boolean,       // 发球者是否已就位可开球
  },

  ball: Ball,
  players: [Player],             // 22 个
  possession: {
    teamId: TeamId | null,       // 当前控球方（无主球时 null）
    playerId: String | null,     // 当前持球球员（松球时 null）
  },

  field: FieldConfig,            // 只读几何（见 §5）
  config: RulesConfig,           // 只读规则参数（见 §5）
}
```

### Ball（world/Ball.js）

```js
Ball = {
  pos: Vec2,
  vel: Vec2,
  height: Number,        // z，米；M1 可恒为 0（地面球）
  ownerId: String|null,  // 被控制时=持球者 id，否则 null
  lastTouch: {           // 最近一次触球，用于出界归属判定
    playerId: String,
    teamId: TeamId,
    frame: Number,
  } | null,
}
```

### Player（world/Player.js，物理/身份数据）

> 注意：Player 只存**客观物理与身份数据**；球员的"想法"（信念、目标）在 Blackboard，"决策逻辑"在 PlayerAgent。三者分离。

```js
Player = {
  id: String,                 // 'home-6'
  teamId: TeamId,
  number: Number,             // 球衣号
  role: Role,
  pos: Vec2,
  vel: Vec2,
  facing: Number,             // 朝向弧度
  speedMode: SpeedMode,
  stamina: Number,            // 0..100
  attributes: {               // 0..100，来自 config/roster.json，M1 可给统一默认
    pace: Number, passing: Number, shooting: Number,
    dribbling: Number, tackling: Number, vision: Number,
    decision: Number, strength: Number,
  },
  formationAnchor: Vec2,      // 阵型基准站位点（无球回归目标）
}
```

---

## 2. Event（裁判发布，core/EventBus.js 投递）

### 基础字段（所有事件都有）

```js
EventBase = {
  type: String,        // 事件类型名
  frame: Number,       // 发布帧
  timeMs: Number,
}
```

### 事件目录（M1 用 ★ 标注为必需）

```js
★ PhaseChanged      { ...base, from: {main,sub}, to: {main,sub} }
★ KickoffAwarded    { ...base, teamId: TeamId, spot: Vec2 }
★ BallOutOfPlay     { ...base, lastTouchPlayerId, lastTouchTeamId, exitPoint: Vec2, side: BoundarySide }
★ ThrowInAwarded    { ...base, teamId: TeamId, spot: Vec2 }
★ RestartAssigned   { ...base, playerId: String, restartType: RestartType, spot: Vec2 }
★ RestartReady      { ...base, playerId: String }
★ PossessionChanged { ...base, fromTeamId: TeamId|null, toTeamId: TeamId|null, playerId: String|null }
  MatchStarted      { ...base }
  HalfStarted       { ...base, half: 1|2 }
  HalfEnded         { ...base, half: 1|2 }
  FullTime          { ...base, score: {home:Number, away:Number} }
  CornerKickAwarded { ...base, teamId, corner: Vec2 }
  GoalKickAwarded   { ...base, teamId, spot: Vec2 }
  GoalScored        { ...base, teamId, scorerId: String }
  // 后续里程碑：FoulCommitted / FreeKickAwarded / PenaltyAwarded / OffsideCalled
```

### 投递语义（EventBus）

```js
EventBus.publish(event)                 // 裁判调用；进入本帧事件缓冲
EventBus.subscribe(playerId, handler)   // 球员注册中断处理
EventBus.flush()                        // 帧末：把事件投递到每个球员的 pendingEvents 队列
```

- 广播类事件（`PhaseChanged` 等）投递给**全体**球员。
- 定向事件（`RestartAssigned`、`RestartReady`）主要影响 `playerId`，但仍全体可见（他人据此判断"谁在发球"）。
- 事件在**下一帧**的球员感知阶段被消费（见 `01-architecture.md` §2 的因果节拍）。

---

## 3. Intent（球员产出，物理消费）

### 基础字段

```js
IntentBase = {
  type: String,
  playerId: String,
  frame: Number,
}
```

### 意图目录（M1 用 ★）

```js
★ MoveIntent   { ...base, target: Vec2, speedMode: SpeedMode }
★ KickIntent   { ...base,
                 kind: 'pass' | 'throwIn' | 'clear' | 'shoot',
                 targetPlayerId: String | null,   // 传球目标（可空）
                 targetPoint: Vec2 | null,         // 目标落点
                 power: Number,                    // 0..1
                 curve: Number,                    // -1..1，M1 可恒 0
               }
★ IdleIntent   { ...base }
  TackleIntent    { ...base, targetPlayerId: String }
  InterceptIntent { ...base, ballFuturePos: Vec2 }
```

> 一个球员**每帧最多产出一个 Intent**（移动与踢球互斥；盘带在物理层解释为"带球移动"）。IntentResolver 负责合法性预检与冲突仲裁。

### IntentResolver 输出

```js
ResolvedIntent = {
  intent: Intent,
  accepted: Boolean,
  reason: String|null,   // 被驳回原因，如 'dead-ball-not-taker'
}
```

---

## 4. LocalModel（感知输出，agent/Perception.js）

球员决策的唯一输入。M1 用全场可见填充；后续换视野模型时**只改填充逻辑，不改字段**。

```js
LocalModel = {
  self: {
    id, teamId, role, pos: Vec2, vel: Vec2, facing, stamina,
    hasBall: Boolean,
    formationAnchor: Vec2,
  },
  ball: {
    pos: Vec2, vel: Vec2, ownerId: String|null, distToMe: Number,
  },
  teammates: [ { id, pos: Vec2, openness: Number/*0..1*/, distToMe, isCalling: Boolean } ],
  opponents: [ { id, pos: Vec2, threat: Number/*0..1*/, distToMe } ],
  space: {                    // 空档网格（M1 可先给粗网格或省略）
    cell: Number,             // 网格边长(米)
    openness: [[Number]],     // 二维 openness map，0..1
  },
  phase: { main: PhaseMain, sub: PhaseSub, restartTeam, takerId, restartReady },
  assignment: {               // 来自黑板：裁判是否指派我发球
    isTaker: Boolean, restartType: RestartType|null, spot: Vec2|null,
  },
}
```

---

## 5. 只读配置（src/config/*.json，bootstrap 加载）

### field.json（几何）

```js
{
  length: 105, width: 68,
  centerCircleRadius: 9.15,
  penaltyAreaLength: 16.5, penaltyAreaWidth: 40.32,
  goalWidth: 7.32, goalPostRadius: 0.06,
  cornerPoints: [ {x:0,y:0},{x:0,y:68},{x:105,y:0},{x:105,y:68} ],
}
```

### rules.json（判定参数）

```js
{
  lineTolerance: 0.11,        // 出界/进球的球半径容差(米)
  kickoffKeepOutRadius: 9.15, // 开球时对方保持距离
  restartReadyRadius: 0.5,    // 发球者进入 spot 该半径内视为就位
  restartReadySpeedMax: 0.3,  // 且速度低于此值(m/s)
  throwInTakerExcludeGK: true,// 界外球不选门将
}
```

### roster.json（阵容与阵型，11v11）

```js
{
  formation: '4-3-3',
  home: [ { number, role, anchor: Vec2, attributes:{...} }, ... x11 ],
  away: [ ... x11 ],
  kickoffTakerNumber: 6,       // 中圈开球手
}
```

---

## 6. 决策可视化记录（DebugPanel 用）

UtilitySystem 每次决策时，附带产出一条可选的调试记录（生产可关）：

```js
DecisionTrace = {
  playerId, frame,
  candidates: [
    { action: String, target: String|Vec2, score: Number,
      considerations: [ { name: String, value: Number } ] },
  ],
  chosen: { action: String, score: Number },
  triggeredBy: 'interrupt' | 'backgroundTick',
}
```

调试面板据此画出"某球员因某事件被唤醒 → 各候选动作分数 → 选中项"，用于肉眼验证核心范式。

---

## 7. 契约稳定性原则

- **字段只增不改**：新增能力优先加字段，避免改已有字段语义。
- **感知接口冻结**：`LocalModel` 结构在 M1 冻结；感知实现从"全场可见"升级到"视野模型"时不得改字段。
- **事件/意图新增即扩展**：新增比赛机制 = 新增一个事件类型 + （如需）一个动作/意图类型，不动流水线。
