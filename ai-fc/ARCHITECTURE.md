# AI FC - 分层架构设计文档

## 架构概览

AI FC 采用**7层分层架构**，从下往上逐步构建足球模拟系统。每一层都是**完全配置化驱动**，支持编辑和演进。

```
┌─────────────────────────────────────────────────┐
│ 第8层：执行引擎层                                │  ← 新增
│ (运行比赛循环、协调各层、管理时序)              │
├─────────────────────────────────────────────────┤
│ 第7层：反馈分析层 (Analytics)                   │
│ 第6层：策略系统层 (Strategy)                    │
│ 第5层：状态管理层 (State)                       │
│ 第4层：决策引擎层 (Decision)                    │
│ 第3层：技能系统层 (Skill)                       │
│ 第2层：属性系统层 (Attribute)                   │
│ 第1层：规则引擎层 (Rules)                       │
│ 第0层：物理基础层 (Physics)                     │
└─────────────────────────────────────────────────┘
```

---

## 架构设计要点

### 核心原则：分布式智能体模型

**旧模式（已废弃）**：中央决策系统决定每个球员的动作
```
系统 → 计算所有决策 → 下达指令 → 球员执行
```

**新模式（正确）**：每个球员是独立智能体，规则系统是中立裁判
```
每个球员 → 基于局部信息自主决策 → 规则系统验证 → 执行合法结果
```

### 比赛循环的六个阶段

每一帧的比赛执行顺序：

1. **环境更新** → 同步球和所有球员的位置、速度、视野范围
2. **球员决策**（并行）→ 22个球员各自独立做决策，输出动作列表
3. **规则验证** → 验证所有动作是否合法（越位、犯规等）
4. **物理执行** → 执行所有合法动作，计算新的物理状态
5. **状态更新** → 更新每个球员的疲劳、心理、失误等状态
6. **反馈记录** → 记录事件日志和统计数据

---

## 分层详解

### 第0层：物理基础层 (Physics Foundation)

**职责**：定义比赛环境的物理模型

**配置文件**：`config/physics/base.json`

**核心要素**：
- 球场尺寸和坐标系
- 球的物理参数（质量、速度、摩擦、弹性）
- 碰撞检测模型
- 重力和风阻等环境因素

**示例**：
```json
{
  "field": {
    "length": 105,
    "width": 68,
    "centerCircleRadius": 9.15,
    "penaltyAreaLength": 16.5,
    "penaltyAreaWidth": 40.32
  },
  "ball": {
    "mass": 0.43,
    "radius": 0.22,
    "friction": 0.02,
    "elasticity": 0.8,
    "maxVelocity": 30
  }
}
```

---

### 第1层：规则引擎层 (Rules Engine)

**职责**：定义足球比赛的基本规则和判定逻辑

**配置文件**：`config/rules/base.json`

**核心要素**：
- 比赛时间和计时
- 进球判定
- 越位规则
- 犯规判定
- 禁区判定
- 出界判定

**示例**：
```json
{
  "match": {
    "duration": 90,
    "halfTime": 45,
    "extraTime": 0,
    "stoppage": true
  },
  "offside": {
    "enabled": true,
    "toleranceDistance": 0.1
  },
  "penaltyArea": {
    "length": 16.5,
    "width": 40.32
  },
  "goalScoring": {
    "ballCrossLineThreshold": 0.2
  }
}
```

---

### 第2层：属性系统层 (Attribute System)

**职责**：定义球员的属性维度、天赋值和成长模型

**配置文件**：`config/attributes/player-attributes.json`

**核心要素**：
- 属性维度定义（体能、技术、意识、决策、心理、身体等）
- 每个属性的范围和含义
- 天赋值对属性上限的制约
- 属性成长曲线

**示例**：
```json
{
  "dimensions": {
    "stamina": {
      "name": "体能",
      "range": [0, 100],
      "subcategories": {
        "endurance": "耐力",
        "explosion": "爆发力",
        "recovery": "恢复速度"
      }
    },
    "technique": {
      "name": "技术",
      "range": [0, 100],
      "subcategories": {
        "passing": "传球精度",
        "shooting": "射门精度",
        "dribbling": "盘带",
        "heading": "头球",
        "control": "停球"
      }
    }
  },
  "talentConstraint": {
    "formula": "attributeMax = 60 + talent * 0.4",
    "description": "属性上限 = 60 + 天赋值 × 0.4"
  },
  "growthCurve": {
    "type": "sigmoid",
    "description": "S形成长曲线，越接近上限增长越缓慢"
  }
}
```

---

### 第3层：技能系统层 (Skill System)

**职责**：定义球员的基础技能和技能效果

**配置文件**：`config/skills/player-skills/*.json`

**核心要素**：
- 技能定义（传球、盘带、跑位、防守、抢断等）
- 技能触发条件
- 技能效果公式
- 技能与属性的关联

**示例**：
```json
{
  "skillId": "pass",
  "name": "传球",
  "category": "offensive",
  "requirements": {
    "attributes": ["passing", "vision"]
  },
  "effect": {
    "successRate": "technique.passing * 0.8 + decision * 0.2",
    "range": "75-40",
    "accuracy": "determined by technique and receiver position"
  },
  "cooldown": 0,
  "energyCost": 5
}
```

---

### 第4层：决策引擎层 (Decision Engine)

**职责**：定义球员如何基于状态做出决策

**配置文件**：`config/decision/decision-rules.json`

**核心要素**：
- 决策优先级
- 决策规则库（if-then规则）
- 决策权重和参数
- 基于球员属性的决策调整

**示例**：
```json
{
  "decisionPriorities": [
    {
      "priority": 1,
      "type": "defense",
      "description": "防守优先"
    },
    {
      "priority": 2,
      "type": "counterAttack",
      "description": "快速反击"
    },
    {
      "priority": 3,
      "type": "buildUp",
      "description": "阵地进攻"
    }
  ],
  "ruleLibrary": [
    {
      "id": "long-pass-opportunity",
      "condition": "hasOpenTeammate && distanceGreaterThan(50)",
      "action": "attemptLongPass",
      "weights": {
        "visionAttribute": 0.6,
        "techniqueFactor": 0.3,
        "tacticalTendency": 0.1
      }
    }
  ]
}
```

---

### 第5层：状态管理层 (State Management)

**职责**：定义球员动态状态及其演变机制

**配置文件**：`config/state/player-state.json`

**核心要素**：
- 状态维度（疲劳度、心理值、受伤等）
- 状态变化的驱动因素
- 状态对性能的影响
- 状态恢复模型

**示例**：
```json
{
  "stateFactors": {
    "fatigue": {
      "name": "疲劳度",
      "range": [0, 100],
      "decayPerMinute": 1.5,
      "affectedAttributes": {
        "speed": "1 - fatigue * 0.008",
        "passing": "1 - fatigue * 0.005",
        "shooting": "1 - fatigue * 0.006"
      }
    },
    "mentalState": {
      "name": "心理值",
      "range": [0, 100],
      "factors": ["scoreStatus", "teamMorale", "pressureLevel"],
      "affectedAttributes": {
        "decision": "mental * 0.01",
        "errorRate": "1 - mental * 0.008"
      }
    },
    "injury": {
      "name": "受伤",
      "recoveryDaysPerLevel": 7,
      "affectedAttributes": {
        "speed": "1 - injuryLevel * 0.1",
        "acceleration": "1 - injuryLevel * 0.15"
      }
    }
  }
}
```

---

### 第6层：策略系统层 (Strategy System)

**职责**：定义用户可编辑的战术和策略

**配置文件**：`config/strategy/team-formations/*.json` 和 `config/strategy/player-tactics/*.json`

**核心要素**：
- 阵型定义（位置、跑位范围）
- 战术指令（进攻倾向、防守强度）
- 位置和球员的特殊规则
- 用户可编辑的行为参数

**示例**：
```json
{
  "formationId": "4-3-3",
  "name": "4-3-3阵型",
  "positions": {
    "goalkeeper": { "x": 0, "y": 34, "radius": 5 },
    "defender_left": { "x": 20, "y": 10, "radius": 15 },
    "defender_center_left": { "x": 20, "y": 25, "radius": 12 },
    "defender_center_right": { "x": 20, "y": 43, "radius": 12 },
    "defender_right": { "x": 20, "y": 58, "radius": 15 }
  },
  "tacticalSettings": {
    "aggression": 0.7,
    "defensiveDepth": 0.6,
    "offensiveWidth": 0.8
  },
  "editable": true
}
```

---

### 第7层：反馈分析层 (Feedback & Analytics)

**职责**：收集、统计和分析比赛数据

**配置文件**：`config/analytics/metrics.json`

**核心要素**：
- 关键性能指标（KPI）定义
- 数据收集点和频率
- 性能评估模型
- 优化建议规则

**示例**：
```json
{
  "matchMetrics": {
    "possession": {
      "description": "控球率",
      "formula": "teamABallTime / matchDuration"
    },
    "shotAccuracy": {
      "description": "射门准度",
      "formula": "goalsScored / shotsOnTarget"
    },
    "passingAccuracy": {
      "description": "传球成功率",
      "formula": "successfulPasses / totalPasses"
    }
  },
  "playerPerformance": {
    "ratingFormula": "technique * 0.2 + decision * 0.2 + state.mental * 0.15 + actions.successful * 0.45"
  }
}
```

---

## 配置文件组织结构

```
config/
├── 0-physics/
│   └── base.json                    # 物理基础配置
├── 1-rules/
│   ├── base.json                    # 基本规则
│   └── variants/                    # 规则变体（如五人足球）
├── 2-attributes/
│   ├── player-attributes.json       # 属性系统定义
│   └── talent-models/               # 不同天赋模型
├── 3-skills/
│   ├── offensive/                   # 进攻技能
│   ├── defensive/                   # 防守技能
│   └── movement/                    # 移动技能
├── 4-decision/
│   ├── decision-rules.json          # 决策规则库
│   ├── npc-profiles/                # NPC球员决策配置
│   └── position-behaviors/          # 位置特定行为
├── 5-state/
│   ├── player-state.json            # 状态系统定义
│   └── fatigue-models/              # 不同疲劳模型
├── 6-strategy/
│   ├── team-formations/             # 阵型配置
│   ├── player-tactics/              # 球员战术配置
│   └── tactical-instructions/       # 教练指令集
└── 7-analytics/
    ├── metrics.json                 # 性能指标定义
    └── analysis-rules/              # 分析规则
```

---

### 第8层：执行引擎层 (Execution Engine)

**职责**：管理比赛循环和时序，协调各层执行

**配置文件**：`config/8-execution/engine.json`

**核心要素**：
- 比赛循环的6个阶段定义
- 球员智能体的决策模型
- 时间管理（帧率、停表等）
- 阶段转移规则
- 并行处理模型

**关键特点**：
```
比赛循环（每一帧）：
  1. 环境更新 → 同步位置和视野
  2. 球员决策（并行）→ 22个球员各自决策
  3. 规则验证 → 验证动作合法性
  4. 物理执行 → 执行合法动作
  5. 状态更新 → 更新球员状态
  6. 反馈记录 → 记录数据
```

**示例**：
```json
{
  "executionModel": "distributed_agent_based",
  "matchLoop": {
    "frameRate": 60,
    "frameDuration": 16.67,
    "phases": [
      { "name": "环境更新", "duration_ms": 0 },
      { "name": "球员决策（并行）", "duration_ms": 10 },
      { "name": "规则验证", "duration_ms": 3 },
      { "name": "物理执行", "duration_ms": 2 },
      { "name": "状态更新", "duration_ms": 1 },
      { "name": "反馈记录", "duration_ms": 1 }
    ]
  }
}
```

---

## 推进计划

### 第一阶段：MVP（第0-4层）
- [ ] 第0层：物理基础
- [ ] 第1层：规则引擎
- [ ] 第2层：属性系统
- [ ] 第3层：技能系统
- [ ] 第4层：决策引擎
- **输出**：一场完整的基础比赛模拟

### 第二阶段：动态进化（第5层）
- [ ] 第5层：状态管理
- **输出**：支持疲劳、心理等动态因素的比赛

### 第三阶段：用户交互（第6-7层）
- [ ] 第6层：策略系统
- [ ] 第7层：反馈分析
- **输出**：支持用户编辑和优化的完整系统

---

## 配置文件的可演进性

每个配置文件都遵循以下原则：

1. **版本控制**：每个配置有 `version` 字段
2. **可编辑性**：生产环境中用户可直接编辑 JSON 配置
3. **热更新支持**：修改配置后无需重启即可生效
4. **依赖追踪**：配置间的依赖关系明确
5. **变更历史**：记录配置变更的时间和内容

---

## 下一步

现在可以开始逐层实现配置模板和核心业务逻辑。第一阶段从**第0层物理基础**开始。
