# 01 · 运行时架构

> 本文定义"谁在什么时刻、感知到什么、如何决策、如何驱动下一步"。这是整个重构的骨架。

## 1. 三类角色（职责严格隔离）

```
        ┌──────────────────────────────────────────────────────┐
        │                      Event Bus                        │
        │   （比赛事件的广播总线：裁判发布，球员订阅）            │
        └───────▲───────────────────────────────────┬──────────┘
                │ 发布事件                            │ 投递事件
                │                                     ▼
   ┌────────────┴───────────┐          ┌─────────────────────────────┐
   │        Referee         │          │   Player Agent × 22          │
   │   （裁判 / 比赛状态机）  │          │  感知 → 决策(Utility) → 意图  │
   │  观察世界·判定·广播事件  │          │  订阅事件(中断) + 背景轮询    │
   │  从不指挥球员           │          │  唯一的 Intent 产出方         │
   └────────────▲───────────┘          └───────────────┬─────────────┘
                │ 读世界                                 │ 产出 Intent
                │                                        ▼
        ┌───────┴────────────────────────────────────────────────────┐
        │                    Physics / World                         │
        │  仲裁冲突意图 · 积分球与球员运动 · 碰撞 · 维护权威世界状态     │
        │  不含任何战术智慧                                            │
        └────────────────────────────────────────────────────────────┘
```

**铁律**：
- **裁判**产出**事件（Event）**，不产出动作。
- **球员**产出**意图（Intent）**，不直接改物理量。
- **物理**执行意图、更新世界，不做任何决策。
- **MatchLoop**（下面的帧循环）只按固定顺序调用上述子系统，**它自己不含任何规则或策略**。

> 关于"帧循环 vs 事件驱动"的澄清：仿真和渲染必然需要一个帧循环作为**调度器**。它与"球员是动作起源"并不矛盾——关键在**因果作者权**：所有动作的作者是球员，所有比赛判定的作者是裁判，循环只负责按顺序推进时间。事件让球员**在正确的时刻被唤醒去决策**，而不是被动地被塞入一个动作。

## 2. 一帧的流水线（Tick Pipeline）

MatchLoop 每帧严格按此顺序执行（`sim/MatchLoop.js`）：

```
① Clock.advance(dt)                    时钟推进
② Perception.update(agents, world)     每个球员构建"局部世界模型"（受视野限制）
③ Agents.decide()                      被事件唤醒的球员立即重决策；其余按背景节拍决策
                                        → 产出 Intent 列表
④ IntentResolver.resolve(intents)      仲裁冲突（两人抢同一球）+ 合法性预检
⑤ Physics.integrate(dt)                执行意图：积分球/球员运动、碰撞
⑥ Referee.observe(world)               裁判观察新世界 → 更新 FSM → 判定 → 发布事件
⑦ EventBus.flush()                     把事件投递到各球员的中断队列（下一帧③生效）
⑧ Renderer.draw() + DebugPanel.update()渲染与调试
```

**注意顺序②③在⑥之前**：球员先基于"当前世界 + 上一帧收到的事件"决策，物理执行后裁判才判定并发新事件。这形成清晰的因果节拍：
`世界变化 → 裁判判定并广播 → 球员下一帧感知到并决策 → 产生新动作 → 世界再变化`。

## 3. 三种数据类型（贯穿全系统的词汇表）

| 类型 | 谁产出 | 谁消费 | 例子 |
|------|--------|--------|------|
| **Event（事件）** | Referee | Player Agents | `KickoffAwarded`、`BallOutOfPlay`、`ThrowInAwarded`、`RestartAssigned`、`GoalScored` |
| **Intent（意图）** | Player Agent | IntentResolver / Physics | `MoveIntent`、`KickIntent(pass/shoot/clear/throwIn)`、`TackleIntent` |
| **World Signal（连续信号）** | World | Perception（球员轮询） | 球位置/速度、球员位置/速度、球权、距离 |

事件是**离散、有主语、会打断决策**的；世界信号是**连续、需主动感知**的。二者对应 docs/03 的"事件驱动 + 定时轮询"双层，但这次真正落地。

### 事件目录（首批，Referee 发布）

- `MatchStarted` / `HalfStarted` / `HalfEnded` / `FullTime`
- `PhaseChanged{from, to}`（比赛阶段切换，全体球员据此重新站位）
- `KickoffAwarded{teamId, spot}`
- `BallOutOfPlay{lastTouchPlayerId, lastTouchTeamId, exitPoint, side}`
- `ThrowInAwarded{teamId, spot}` / `CornerKickAwarded{teamId, corner}` / `GoalKickAwarded{teamId}`
- `RestartAssigned{playerId, restartType, spot}`  ← **规则选定的发球球员**
- `RestartReady{playerId}`（发球者就位，可以发球）
- `GoalScored{teamId, scorerId}`
- `PossessionChanged{fromTeamId, toTeamId, playerId}`
- （后续）`FoulCommitted` / `FreeKickAwarded` / `PenaltyAwarded` / `OffsideCalled`

### 意图目录（首批，球员产出）

- `MoveIntent{targetPos, speedMode: walk|jog|run|sprint}`
- `KickIntent{kind: pass|throwIn|clear|shoot, target|dir, power, curve}`
- `TackleIntent{targetPlayerId}` / `InterceptIntent{ballFuturePos}`
- `IdleIntent`（保持/观察）

## 4. 模块划分（ES Modules）

```
newdesign/                 （本设计文档目录）
index.html                 （挂载 canvas + 调试面板，import ./src/main.js）
src/
  core/
    EventBus.js            发布/订阅；支持定向投递到某球员的中断队列
    GameClock.js           比赛时间、dt、倍速、暂停
    Rng.js                 种子化随机数（决定论/可复现）
    Vec2.js                二维向量工具
  world/
    World.js               权威世界状态：ball、players[]、phase、possession
    Field.js               球场几何：边线/底线/球门/角球点/中圈/禁区/分区网格
    Ball.js                球的物理状态与 lastTouch 记录
    Player.js              球员的物理/身份数据（位置、速度、队伍、角色、属性）
  referee/
    Referee.js             比赛状态机（FSM）主控：观察→判定→发布事件
    rules/
      outOfPlay.js         出界检测 + 界外球/角球/球门球归属判定
      restartTaker.js      "由哪个球员发球"的选定规则
      goal.js              进球判定（球完全越过门线且在门框内）
      (later) offside.js foul.js
  agent/
    PlayerAgent.js         球员智能体：编排 感知→决策→意图；订阅事件
    Perception.js          从 World 构建受限的"局部世界模型"
    Blackboard.js          球员的记忆/信念（当前目标、角色、盯防对象、待处理事件）
    decision/
      UtilitySystem.js     效用系统：收集候选动作→打分→取最优
      considerations.js    评分曲线库（openness/distance/forwardProgress/risk/...）
      actions/             候选动作定义（Pass/Dribble/Shoot/MoveToSpace/Support/
                           MarkOpponent/GoToBall/TakeThrowIn/ReturnToFormation）
  physics/
    PhysicsEngine.js       积分球与球员运动
    Collision.js           碰撞检测/响应（球员-球、球员-球员、球-边界）
    IntentResolver.js      冲突仲裁（同球争抢）+ 合法性预检（如死球时禁止踢动）
  render/
    Renderer.js            Canvas 绘制球场/球/球员/意图箭头
    DebugPanel.js          事件时间线 + 选中球员的效用打分可视化
  sim/
    MatchLoop.js           帧流水线编排器
    bootstrap.js           初始化世界、22 名球员、阵型、裁判
  config/
    field.json rules.json roster.json  （旧 config 里可复用的数值降级为纯数据）
  main.js                  入口：创建 MatchLoop 并启动
```

## 5. 三个端到端时序流（对应你的三个例子）

> 记法：`[主语] 动作 → 产出`。粗体是**事件**，斜体是*意图*。

### 流 A：开球（球员是动作起源）

```
t0  [Referee] PreMatch 阶段，检测到 22 人已到位
       → 发布 PhaseChanged{PreMatch→Kickoff} + KickoffAwarded{teamId=home, spot=中圈}
       → 规则 restartTaker 选定中场#6 为开球手
       → 发布 RestartAssigned{playerId=#6, restartType=kickoff, spot=中圈}
t0+1  [EventBus] 把两个事件投递到全体球员的中断队列
t1  [#6 感知阶段] 读取中断队列：发现 RestartAssigned 指向自己
       [#6 决策] Utility 只放行合法动作：GoToBall（球在中圈，我在附近）
       → 产出 *MoveIntent{target=中圈}*
    [其他 home 球员 决策] 收到 PhaseChanged=Kickoff
       → Utility 选 ReturnToFormation（跑向本方阵型站位）→ *MoveIntent*
    [away 球员 决策] 收到 Kickoff → 保持 ≥9.15m，选 ReturnToFormation → *MoveIntent*
t1..tn [Physics] 执行移动意图，#6 逐帧接近球
t_k [#6 感知] 我已到球边 & 我是开球手
       [#6 决策] Utility 评估 Pass vs Dribble：
         - Pass→#8：openness 高、forwardProgress 中 → 分数 0.72
         - Dribble：前方对手密度低 → 分数 0.55
       → 选 Pass → 产出 *KickIntent{pass, target=#8, power=..}*
    [Referee] 观察到球被踢动且离开中圈
       → 发布 PhaseChanged{Kickoff→InPlay} + PossessionChanged{→home,#8 即将接球}
```

**关键**：没有任何"开球脚本"。#6 之所以开球，是因为**他感知到 RestartAssigned 指向自己**，然后**自己决定**先就位、再传球。

### 流 B：持球者面对阻击（实时结合形势）

```
每个决策节拍（持球者高频，如每帧或每2帧）：
[持球者#8 感知] 构建局部世界模型：
   - 对手#3 距我 3.2m，正面封堵，逼近速度 4m/s
   - 队友#11 在右路，openness 0.8，前插中
   - 队友#6 在身后，openness 0.9，安全回传
   - 我正前方 2m 内被封堵，左侧有 1.5m 缝隙
[#8 决策 Utility] 对每个候选动作实时算分（考虑当前形势）：
   - Pass→#11(直塞)：forwardProgress 0.9 × openness 0.8 × (1-interceptRisk 0.3) → 0.63
   - Pass→#6(回传)：安全但 forwardProgress 0.1 → 0.30
   - Dribble(向左缝隙)：盘带属性 0.7 × 缝隙可行 0.6 × (1-被抢风险 0.5) → 0.34
   - Shield(护球等支援)：压力高 0.7 × 支援距离 → 0.40
   → 选直塞#11 → *KickIntent{pass, target=#11}*
下一节拍如果#3 已贴身 (<1m)、传球线路被封：
   → 同样的 Utility 重新算分，直塞分数因 interceptRisk↑ 降到 0.25
   → 护球/回传分数反超 → 球员"改变主意"
```

**关键**：所谓"实时判断"就是 Utility 每个节拍都基于**最新的局部世界模型**重新评分；形势变了，分数就变，选择随之改变——无需为每种局面写 if-else。

### 流 C：出界 → 界外球判罚 → 就位 → 恢复（你的核心例子）

```
t0 [Physics] 积分后球心越过右侧边线；Ball.lastTouch = away#4
t0 [Referee.observe] rules/outOfPlay 判定：
      - 越过的是边线（touchline）→ 界外球
      - 最后触球方 away → 球权判给 home
      → 发布 BallOutOfPlay{lastTouch=away#4, exitPoint=(x,边线), side=touch}
      → 发布 PhaseChanged{InPlay→DeadBall:ThrowIn}
      → 发布 ThrowInAwarded{teamId=home, spot=exitPoint}
      → rules/restartTaker 选定 home 中距离 spot 最近的非门将球员 = home#5
      → 发布 RestartAssigned{playerId=home#5, restartType=throwIn, spot}
t1 [EventBus] 事件投递到全体中断队列
t1 [home#5 感知] 中断队列含 RestartAssigned 指向我
      [home#5 决策] Utility 放行 GoToBall/TakeThrowIn 动作族
      → *MoveIntent{target=spot}*（去球出界的位置）
   [其余 home 球员 决策] 收到 PhaseChanged=DeadBall:ThrowIn
      → Utility 选 OfferForThrowIn（跑到可接球的位置拉开角度）→ *MoveIntent*
   [away 球员 决策] 收到 PhaseChanged=DeadBall:ThrowIn（对方球权）
      → Utility 选 MarkNearestOpponent / 收缩防守 → *MoveIntent*
t1..tk [Physics] 各球员按各自意图移动；#5 到达 spot
tk [home#5 感知] 我已到 spot & 我是发球者
      [Referee] 检测到发球者就位 → 发布 RestartReady{home#5}
tk [home#5 决策] Utility 放行 TakeThrowIn；评估传给谁（同流 B 的评分）
      → *KickIntent{throwIn, target=最佳接球点}*
tk [Referee.observe] 球进入场内且被合法掷出
      → 发布 PhaseChanged{DeadBall→InPlay} + PossessionChanged{→home}
比赛恢复。
```

**关键**：整条链路里裁判**只判定与广播**（谁的球、谁来发、就位了没、恢复了没），**由谁去发球、怎么走过去、发给谁**全部是 home#5 **自己感知事件后的自主决策**；其他 9 名 home 球员和 11 名 away 球员也各自**根据阶段与形势**决定自己的下一步。这正是你要的"球员是一切动作的核心和起源"。

## 6. 与旧 config 的关系

旧的 `config/*` 数值（球场尺寸、球物理参数、球员属性、阵型）**不是被丢弃，而是降级为 `src/config/*.json` 纯数据**，在 `sim/bootstrap.js` 里加载，喂给 World / Player / 感知 / Utility。它们不再充当"架构层"。
