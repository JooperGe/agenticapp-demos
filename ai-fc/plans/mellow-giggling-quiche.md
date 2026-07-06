# AI FC Demo 底座重构计划：球员技能层先行

## Context

当前 `ai-fc/demo/index.html` 把所有逻辑塞进一个文件，AI 行为由全局 `DEFAULT_RULES` 定义：角色 × 情境 → 条件字符串 → 动作字符串。问题：

- 规则是全局共享的，不是每个球员自己的。
- 条件写成字符串用 `new Function` 执行，难以可视化编辑，也容易出错。
- 策略（什么时候做什么）和技能（做得怎么样）混在一起。
- 没有进化机制，只有数值属性变化。
- 单文件 690 行，物理/AI/渲染/UI 耦合严重。

用户期望：推倒重来，球场上所有人的技能和策略分层、可编辑、可进化，且**每个球员的行为由自己决定**。本阶段先聚焦**球员的技能层**设计与落地。

## Goals

1. 把 AI 决策拆成清晰三层：**策略层（Tactic）** → **技能层（Skill）** → **执行层（Executor）**。
2. 每个球员拥有**独立的 SkillSet 和 Tactic 实例**，行为由自己决定。
3. 技能可定义、可升级、可积累经验，为后续进化系统留好接口。
4. 策略可编辑（条件对象化，不再用字符串 eval），为后续 UI 编辑器打好基础。
5. 保持 demo 可运行，保留现有渲染、物理和比赛流程，只重构 AI 底座。

## Proposed Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  UI Layer (panel)                                           │
│  - 编辑球员技能 / 升级 / 解锁                               │
│  - 编辑策略节点（条件阈值、优先级、偏好技能）               │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  Strategy / Tactic Layer (每个球员独立)                     │
│  - 情境判断：持球 / 对方持球 / 无主球 / 队友持球            │
│  - 决策节点 TacticNode：{condition, priority, skills[]}     │
│  - 输出：本轮推荐使用的技能 ID 与目标                       │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  Skill Layer (每个球员独立，可升级)                         │
│  - Skill 实例：id / level / xp / params                     │
│  - Skill 模板：基础成功率、体力消耗、冷却、效果公式         │
│  - 输出：给定目标后计算实际效果（方向、力度、精度）         │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  Executor Layer                                             │
│  - 把技能输出转成物理指令：速度、加速度、球速/方向          │
│  - 处理碰撞、球权、射门/扑救等比赛事件                      │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  Physics & Render Layer (保留现有)                          │
│  - 球/球员位置更新、碰撞检测、Canvas 渲染                   │
└─────────────────────────────────────────────────────────────┘
```

## Skill Layer Design

### Skill 数据结构

```js
class Skill {
  constructor(def, level = 1) {
    this.id = def.id;           // 唯一标识
    this.name = def.name;       // 中文名
    this.type = def.type;       // movement | pass | shoot | defense | gk
    this.level = level;         // 1-5，可升级
    this.xp = 0;                // 当前经验
    this.params = { ...def.params }; // 技能参数副本，可被进化/训练修改
  }
  maxXp() { return 100 * this.level; }
  gainXp(n) { this.xp += n; if (this.xp >= this.maxXp() && this.level < 5) { this.level++; this.xp = 0; } }
}
```

### 技能目录（v1 先覆盖现有行为）

| id | name | type | 说明 |
|----|------|------|------|
| `moveTo` | 跑位 | movement | 移动到目标点，受 pace 和体力影响 |
| `sprint` | 冲刺 | movement | 短时间加速，消耗更多体力 |
| `dribble` | 盘带 | movement | 持球推进，可过人 |
| `shortPass` | 短传 | pass | 短距离地面传球 |
| `throughPass` | 直塞 | pass | 向前穿透传球 |
| `longPass` | 长传 | pass | 长距离转移 |
| `cross` | 传中 | pass | 边路向禁区传中 |
| `shoot` | 射门 | shoot | 普通射门 |
| `tackle` | 抢断 | defense | 抢脚下球 |
| `slideTackle` | 铲球 | defense | 高风险高收益 |
| `mark` | 盯人 | defense | 贴身防守指定对手 |
| `intercept` | 拦截 | defense | 预判传球路线 |
| `gkSave` | 扑救 | gk | 门将扑救 |
| `gkClaim` | 出击抱球 | gk | 门将冲出禁区接球 |
| `gkClear` | 大脚解围 | gk | 门将开大脚 |

每个技能模板定义：
- 基础精度 / 成功概率公式
- 体力消耗
- 冷却时间
- 适用情境
- 效果计算函数

### 技能执行效果

Skill 不直接改物理量，而是返回一个 `SkillResult`：

```js
{
  type: 'pass',
  target: { x, y },
  intendedPower: 3.5,
  intendedAngle: 1.2,
  accuracy: 0.82,      // 受技能等级、属性、疲劳影响
  staminaCost: 4,
  risk: 0.1            // 被拦截概率
}
```

Executor 拿到 result 后，加入高斯噪声生成实际球速/方向，再更新物理。

## Tactic Layer Design

### TacticNode

策略节点不再用字符串条件：

```js
class TacticNode {
  constructor({
    id,
    situation,        // 'hasBall' | 'oppHasBall' | 'looseBall' | 'myTeamHasBall' | 'default'
    condition,        // 结构化条件对象，见下文
    preferredSkills,  // ['throughPass', 'shortPass', 'dribble']
    priority = 1,
    targetPicker      // 如何选目标：bestTeammate / mostForward / nearestOpponent / selfGoal 等
  }) {}
  evaluate(player, worldState) { return { score, chosenSkill, target }; }
}
```

### 结构化条件对象（可安全编辑/序列化）

```js
{
  op: 'and',
  clauses: [
    { metric: 'distToBall', op: '<', value: 120 },
    { metric: 'isNearestTeammate', op: '==', value: true },
    { metric: 'aggressiveness', op: '>', value: 40 }  // 引用球员自身属性
  ]
}
```

评估器遍历 clauses，从 `worldState` 和 `player` 中取值，不需要 `new Function`。

### 每个球员独立持有 Tactic

```js
class Tactic {
  constructor(roleTemplate) {
    this.role = roleTemplate.role;
    this.nodes = roleTemplate.nodes.map(n => new TacticNode(n));
  }
  decide(player, world) {
    // 1. 判断当前情境
    // 2. 找出所有匹配的节点，按优先级 + 条件满足度评分
    // 3. 对每个 preferredSkill，结合 player.skillSet 的等级/可用性打分
    // 4. 返回最高分的 Skill + target
  }
}
```

角色模板只作为初始默认值；每个球员的 Tactic 是其独立副本，后续可被玩家编辑。

## Player Decision Flow

每帧/每几帧：

1. **感知 (Perception)**：球员基于 `awareness` 和视野半径构建局部世界模型。
2. **情境 (Situation)**：判断 `hasBall` / `oppHasBall` / `looseBall` / `myTeamHasBall`。
3. **策略选择 (Tactic.decide)**：从自己的 Tactic 节点中选出最高分的（skill, target）。
4. **技能执行 (Skill.use)**：根据自己的 Skill 等级和属性计算 `SkillResult`。
5. **执行 (Executor)**：把 result 转成物理指令。
6. **经验反馈 (Skill.gainXp)**：成功完成动作后给对应技能加经验。

## Evolution / Editability Hooks

- 技能升级：每次成功使用技能获得经验，升级后提升 params（精度、距离、冷却等）。
- 技能解锁：某些技能默认锁定，需要消耗进化点或达到条件解锁。
- 策略编辑：UI 直接改 `TacticNode.condition.clauses` 和 `preferredSkills`。
- 持久化：PlayerProfile 保存 `{ att, traits, skills: [{id, level, xp}], tactic: { nodes } }` 到 localStorage。

## File Changes

本次只改 `ai-fc/demo/index.html`，但内部按模块重组。关键新增/重写区域：

- `Skill` / `SkillCatalog`：技能定义与实例化。
- `TacticNode` / `Tactic` / `RoleTemplates`：策略层。
- `ConditionEvaluator`：替代 `evalCond` 的结构化条件评估。
- `Executor`：把 SkillResult 转成物理动作，替代现有 `resolveAction`/`execute`。
- `Player`：持有 `skillSet` 和 `tactic`，新增 `decide()` 方法。
- 保留：球场几何常量、物理更新、渲染、比赛流程（开球/角球/界外球/进球）、UI 面板框架。

## Implementation Phases

### Phase 1：技能层骨架
- 创建 `Skill`、`SkillCatalog`、基础技能模板。
- 给每个球员初始化 `skillSet`（基于角色）。
- 把现有动作映射到技能：传球 → shortPass/longPass，射门 → shoot，抢断 → tackle，等等。
- 验证：demo 仍能跑，行为与原来大致一致。

### Phase 2：策略层替换
- 创建 `TacticNode`、`Tactic`、`RoleTemplates`。
- 用结构化条件替代字符串条件。
- 重写 `Player.decide()`，让球员基于自己的 Tactic 选择技能。
- 移除 `DEFAULT_RULES.roles` 字符串规则。

### Phase 3：可编辑 UI
- 球员面板扩展：显示技能列表、等级、经验条。
- 可拖动升级技能（消耗进化点/训练点）。
- 策略面板：编辑节点的条件阈值和偏好技能。

### Phase 4：进化与持久化
- 比赛中使用技能获得经验并自动升级。
- PlayerProfile 保存技能和策略状态。
- 重置时保留/重置进化进度按需求处理。

## Verification

- 打开 `ai-fc/demo/index.html`，比赛能正常进行，红蓝两队能进球、传球、抢断。
- 点击球员打开面板，能看到该球员的技能列表和策略节点（ editable 字段至少能显示）。
- 修改某个球员的传球技能等级后，其传球精度和成功率应有可感知变化。
- 修改策略节点条件（如前锋逼抢距离）后，该球员行为应有变化。
- 刷新页面后，通过 localStorage 持久化的球员档案和规则仍然有效。
