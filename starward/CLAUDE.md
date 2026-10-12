# Starward — 项目约定

Flutter 星际探索游戏。分层：`lib/core`（视觉与跨实体调参）→ `lib/data`（领域模型 + 存储）→
`lib/state`（`GameController` 承载全部规则）→ `lib/ui`（页面层，不直接读写存储）。

常用命令：

```bash
flutter pub get
flutter analyze          # 必须 No issues found
flutter test             # 全量测试
flutter run
```

## 领域建模：属性归属于拥有它的实体

**这是本项目最重要的结构约定。**

一个数值如果描述的是某个具体实体，就必须作为那个实体的字段存在，不能放进全局常量表。
`Balance` 只放**跨实体**的经济调参（如 `initialEnergy`、`explorationReward`）。

判断方法：问"这个数字是谁的属性？"。如果答案是某个名词（船、引擎、星球、航线），
它就该在那个名词的模型上；只有当它不属于任何单一实体时，才留在 `Balance`。

反例（本项目已修正过一次）：能量消耗率与巡航速度曾经是 `Balance.energyPerLy` /
`Balance.travelSecondsPerLy` 两个全局常量，导致"换一台发动机"这件事在结构上无法表达。
现在它们是 `Engine` 的字段（`lib/data/models/engine.dart`），航线成本与耗时全部读
`ship.engine`，于是改造发动机 = 换掉 `ship.engine` 一个字段
（`GameController.installEngine`），船体、玩家状态、航行规则都不用动。

**为什么**：全局常量表会让实体的属性失去归属，任何"单独改造某个部件"的需求都会退化成
"再去改一次全局常量"，实体永远无法被独立调参、升级或替换。

**怎么做**：新增可调数值前先找它的宿主实体；没有宿主就先建模型。派生计算写成该实体的
方法（如 `Engine.energyCostFor(ly)`），不要写成读全局常量的顶层函数。

## 模型与持久化

- `lib/data/models/` 下的模型一律**不可变**（`final` 字段 + `const` 构造），
  变更返回新实例（`copyWith` / `withEngine` 这类具名方法），不做原地修改。
- 每个模型自带 `toJson()` / `fromJson()`。
- 存档是 `GameSave` 一份整体 JSON，经 `GameRepository` 整存整取。
- **存档结构变更时优先做迁移，不要直接 bump `_saveKey` 丢弃玩家进度。**
  新字段缺失时回落到合理默认值即可——例如 `GameSave.fromJson` 对没有 `ship` 键的
  旧存档回落到 `Ship.standard`。只有当旧存档确实无法安全续用（生成逻辑变了、
  坐标语义变了）才 bump key。

## 测试

- 用 TDD：先写失败测试再实现。
- `GameController` 可注入 `clock` 与 `random`，测试里用 `FakeClock` + 固定 seed 保证确定性。
- 存储用 `MemoryStorage`，不要碰真实 prefs。
- 涉及数值的迁移要**钉住具体数字**（见 `test/ship_test.dart` 里对标准引擎的断言），
  这样"重构不改变行为"才是可验证的，而不是靠嘴说。
