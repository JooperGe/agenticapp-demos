# PLAN · 落地计划

> 本计划服务于**首个里程碑：最小垂直切片**——用最短闭环证明核心范式（球员是动作起源 + 事件驱动 + 健全裁判）。文档先行，代码后随；下面既是里程碑规划，也是逐步实施清单。

## 里程碑 M1：垂直切片（本轮目标）

**验收场景**：开球 → #6 就位并传球 → 进入 InPlay → 球被推向边线出界 → 裁判判界外球并指派最近球员发球 → 该球员感知事件、走到出界点、就位、掷球 → 恢复 InPlay。全程无脚本特判，全部由事件+球员决策驱动。

### 实施步骤（建议顺序，每步可独立验证）

- **S0 脚手架**：`index.html` + `src/main.js` + `sim/MatchLoop.js` 空跑循环，Canvas 画出球场（`render/Renderer.js` + `world/Field.js`）。验证：60fps 空场渲染。
- **S1 世界与物理**：`world/World.js`、`Ball.js`、`Player.js`、`physics/PhysicsEngine.js`。放一个球+一名球员，球能被踢动、摩擦减速。验证：球运动物理正确。
- **S2 事件总线与时钟**：`core/EventBus.js`、`GameClock.js`、`Rng.js`。验证：可发布/订阅/定向投递事件，随机可复现。
- **S3 裁判骨架 + 出界规则**：`referee/Referee.js`（FSM：PreMatch/Kickoff/InPlay/DeadBall:ThrowIn）+ `rules/outOfPlay.js`（边线出界）+ `rules/restartTaker.js`（最近非门将）。验证：手动把球推出边线，控制台打印出正确事件序列（`BallOutOfPlay`→`PhaseChanged`→`ThrowInAwarded`→`RestartAssigned`）。
- **S4 球员智能体最小闭环**：`agent/PlayerAgent.js` + `Blackboard.js` + 简化 `Perception.js`（先全场可见）+ `decision/UtilitySystem.js` + 最小动作集（`GoToBall`、`TakeThrowIn`、`ReturnToFormation`、`MoveToSpace`、`Pass`、`Idle`）。验证：被指派的球员会自己走到球位并发球。
- **S5 编排全流程**：`sim/bootstrap.js` 布置 **22 人（11v11 完整两队）** + 阵型，串起 MatchLoop 全流水线，跑通完整验收场景。
- **S6 调试面板**：`render/DebugPanel.js`——事件时间线 + 点击球员看其 Utility 打分。验证：可肉眼确认"球员因某事件被唤醒、因某分数最高而行动"。

### M1 完成定义（DoD）

- 验收场景端到端跑通，无脚本特判。
- 事件序列与 `01-architecture.md` 流 A、流 C 一致。
- 点击任意球员，调试面板能展示其当前候选动作与分数。
- 随机种子固定时，比赛过程可复现。

## 后续里程碑（不阻塞 M1，仅登记方向）

- **M2 完整死球机制**：角球、球门球、进球后开球；`rules/goal.js` 完整化。
- **M3 对抗深化**：面对阻击的护球/过人（流 B 完整化）、抢断/拦截仲裁、感知不完美性（视野扇形+衰减）。
- **M4 完整比赛**：11v11、上下半场、越位、犯规/牌、任意球/点球。
- **M5 可编辑性**：Utility 曲线 + 阵型 + 发球主罚者的可视化编辑（策略编辑器雏形）。

## 工作方式约定

- 所有代码落在 `newdesign/`（`index.html` 与 `src/`），不触碰旧 `demo/`、`js/`、`config/`、`docs/`、`ARCHITECTURE.md`。
- 每完成一步先自测（浏览器打开或 node 跑纯逻辑单测），再进入下一步。
- 设计文档随对话持续细化；如实现中发现设计需调整，先改文档再改码。

## 已确认的决策（M1）

- **规模**：**11v11** 完整两队（22 人全部为智能体）。
- **感知**：M1 用**全场可见**占位（`Perception` 做成可替换接口），M3 再上视野扇形+距离衰减。
- **时间尺度**：M1 用 **1 倍速真实节奏**验证机制，倍速后置。
- **数据契约**：编码前先产出 `04-data-schemas.md`，把 Event / Intent / World / LocalModel 字段结构定死（本轮已补）。

## 下一步

`04-data-schemas.md` 已就绪、决策已敲定。确认无误后即可从 **S0 脚手架**开始编码，逐步跑通 M1 验收场景。
