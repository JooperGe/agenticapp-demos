# 03 · 球员智能体（Player Agent）

> 每个球员是一个**独立**的智能体，持有自己的感知、记忆和决策器。球员是系统里**唯一**产出动作意图的角色。

## 1. 智能体的一次心跳

```
PlayerAgent.tick(world, incomingEvents):
  ① 处理事件      handleEvents(incomingEvents)   // 更新黑板：新目标/角色/发球指派
  ② 感知          model = Perception.build(this, world)   // 受视野限制的局部世界模型
  ③ 判断是否决策   if (interrupted || backgroundTick) then decide
  ④ 决策          intent = UtilitySystem.choose(this, model, blackboard)
  ⑤ 返回意图      return intent
```

- **中断（interrupt）**：收到高优先级事件（`RestartAssigned` 指向自己、`PhaseChanged`、`PossessionChanged`）→ **本帧立即重新决策**，不等背景节拍。
- **背景节拍（background tick）**：无事件时按分频决策（持球者每帧、球附近每 3 帧、其余每 10 帧），节省算力（呼应 docs/03 的双层，但真正实现）。

## 2. 感知层（Perception.js）——球员"看到了什么"

感知把**权威世界**转成**该球员的局部世界模型**。核心是"球员不是全知的"：

```
LocalModel {
  self:      { pos, vel, stamina, role, ... }
  ball:      { pos, vel, ownerId, distToMe }
  teammates: [{ id, pos(估计), openness, isCalling }]   // 仅视野内；视野外为估计/缺失
  opponents: [{ id, pos(估计), threat, distToMe }]
  space:     网格化的"空档度"（openness map）
  phase:     当前比赛阶段（来自最近的 PhaseChanged 事件）
}
```

感知的"不完美性"（可分阶段引入，见 README 开放问题 1）：
- **视野扇形 + 距离衰减**：朝向前方扇角内清晰，外围模糊，超距离不可见。
- **估计误差**：视野边缘/远处的对象位置带高斯误差；这是"低视野球员错过传球线路"的来源。

> 垂直切片阶段可先用"简化全场可见"，把感知做成一个**可替换的接口**，后续再换成扇形+衰减实现，不影响上层决策。

## 3. 黑板（Blackboard.js）——球员的记忆/信念

存放跨帧的持久信念，避免决策"失忆"：

- `role`：位置角色（GK/CB/CM/ST…）与阵型基准点。
- `currentGoal`：当前宏观目标（如"作为发球者去 spot"）。
- `assignment`：裁判指派（`RestartAssigned` 写入；发完球清除）。
- `markTarget`：盯防对象。
- `pendingEvents`：本帧待处理的中断事件。

黑板让"我是这次界外球的发球者"这种状态**稳定持续**，直到任务完成——这是流 C 能闭环的关键。

## 4. 决策层：Utility AI（UtilitySystem.js）

### 4.1 为什么用效用系统

你要的"实时结合形势作出具体判断"本质是：**在每个决策节拍，对当前所有可行动作按当前形势打分，选最优**。这正是 Utility AI 的定义。相比 if-else 规则树，它：
- 用连续分数替代硬编码分支，形势平滑变化 → 选择平滑变化；
- 新增动作 = 新增一个打分器，不改动已有逻辑；
- 每个 consideration 曲线可调参，为后续"策略编辑器"和"球员个性"留口。

### 4.2 结构

```
UtilitySystem.choose(agent, model, blackboard):
  1. 收集候选动作 candidates = ActionCatalog.applicable(model, blackboard)
     // 上下文过滤：持球者才有 Pass/Shoot/Dribble；
     //             被指派发球者才有 TakeThrowIn；
     //             死球非发球者只有 MoveTo 类动作（合法性由此天然收敛）
  2. 对每个候选生成具体实例（如 Pass 对每个可见队友各生成一个实例）
  3. 对每个实例打分：
        score = basePriority(action)
              × Π considerations_i(response_curve(metric_i))
              × (1 + smallNoise)      // 轻微噪声制造"人味"
  4. 取 argmax → 转成 Intent 返回
```

### 4.3 候选动作目录（ActionCatalog）

| 动作 | 适用情境 | 产出意图 |
|------|----------|----------|
| `Pass(target)` | 持球 | KickIntent(pass) |
| `Dribble(dir)` | 持球 | KickIntent + MoveIntent |
| `Shoot` | 持球且在射程 | KickIntent(shoot) |
| `Shield` | 持球被逼抢 | MoveIntent(护球) |
| `GoToBall` | 被指派/最近松球 | MoveIntent(球位) |
| `TakeThrowIn` | 被指派为发球者且就位 | KickIntent(throwIn) |
| `MoveToSpace` / `Support` | 本方控球、无球 | MoveIntent |
| `MarkOpponent` / `Intercept` / `Tackle` | 对方控球 | MoveIntent / Tackle/Intercept Intent |
| `ReturnToFormation` | 死球/阶段切换 | MoveIntent(阵型点) |
| `Idle` | 兜底 | IdleIntent |

### 4.4 Consideration（评分曲线）示例

每个 consideration 是 `metric → [0,1]` 的响应曲线（`considerations.js`）：

- `openness(target)`：目标周围对手越少越高。
- `forwardProgress(target)`：越靠近对方球门收益越高。
- `interceptRisk(passLine)`：传球线路上有对手 → 分数越低（作为 `1 - risk` 乘入）。
- `distance(target)`：越远成功率越低（结合球员传球属性）。
- `skillFit(action)`：动作与球员属性/技能等级的匹配度。
- `pressure(self)`：自身被逼抢程度（影响 Shield/回传权重）。
- `tacticalWeight(pos)`：战术网格对该位置的偏好（无球跑位的"吸引力"）。

**决策力属性**的体现（呼应 docs/02）：决策力高的球员，consideration 权重更"理性"（更看重 openness/forwardProgress）；决策力低的球员，`basePriority(Shoot)` 被抬高、对队友 openness 感知钝化 → 表现为"该传不传、盲目射门"。这通过**按属性调制权重**实现，而非另写一套逻辑。

### 4.5 用流 B 复盘

持球者 #8 每个节拍重算：`Pass→#11` 的分 = `basePriority(Pass) × openness(0.8) × forwardProgress(0.9) × (1-interceptRisk(0.3)) × skillFit`。当 #3 贴身使 `interceptRisk` 升到 0.7，该分数骤降，`Shield`/回传反超 → 球员"改主意"。**没有一行 if 处理"面对阻击"这个具体局面**，它是评分的自然结果。

## 5. 行动的随机偏差（人味）

意图交给物理层执行时，`IntentResolver`/`Physics` 对力度与方向加**高斯噪声**，σ 由 `f(技术属性, 疲劳, 心理)` 决定（呼应 docs/02 的"实际执行 = 指令 + 噪声"）。这保证：满级球员也会偶尔失误，失误率永不为 0。

## 6. 与"球员是核心"的呼应总结

- 动作**只**从球员的 Utility 决策产出（Intent）。
- 球员**自己**订阅事件、自己维护信念（黑板）、自己权衡形势（considerations）。
- 裁判/物理/循环都**不产出动作**，只提供世界、判定与执行。

这就是"球员是一切动作的核心和起源"在代码结构上的落地形态。
