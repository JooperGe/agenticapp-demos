// agent/PlayerAgent.js — 球员智能体：编排 感知→决策→意图；订阅事件
// 球员是系统里唯一产出动作意图的角色。见 03-player-agent.md §1

import { Blackboard } from './Blackboard.js';
import { Perception } from './Perception.js';
import { UtilitySystem } from './decision/UtilitySystem.js';
import { IntentType } from '../core/enums.js';

export class PlayerAgent {
  constructor(playerId, rng, { maxHistory = 0 } = {}) {
    this.id = playerId;
    this.blackboard = new Blackboard(playerId);
    this.util = new UtilitySystem(rng);
    this.currentIntent = null;     // 上次决策的意图（移动/静止会跨帧重复执行）
    this._lastDecisionFrame = -999;
    this.lastTrace = null;         // 最近一次"真正决策"的完整打分（供面板画柱状图）
    // 每一帧的决策记录（含重复执行帧），完整保留。maxHistory=0 表示不丢弃
    this.history = [];
    this.maxHistory = maxHistory;
  }

  // 每帧心跳：返回本帧要执行的 Intent，并记录本帧决策数据
  tick(world, bus, clock) {
    const frame = clock.frame;
    const player = world.getPlayer(this.id);

    // ① 处理事件（更新黑板信念，判断是否需要中断式决策）
    const events = bus.drain(this.id);
    const interrupted = this.blackboard.handleEvents(events);

    // ② 感知：构建局部世界模型
    const model = Perception.build(world, player, this.blackboard);

    // ③ 是否本帧决策
    const shouldDecide = interrupted || this._dueForBackground(model, frame);

    if (!shouldDecide) {
      // 未决策：沿用上次意图；仍记录本帧（标记为 repeat）以保留完整时间线
      const intent = this._repeat(frame);
      this._record({
        playerId: this.id,
        frame,
        timeMs: clock.timeMs,
        triggeredBy: 'repeat',
        candidates: [],
        chosen: { action: labelOfIntent(intent), score: 0 },
        hasBall: model.self.hasBall,
        phase: `${model.phase.main}${model.phase.sub ? ':' + model.phase.sub : ''}`,
      });
      return intent;
    }

    // ④ 决策
    const triggeredBy = interrupted ? 'interrupt' : 'backgroundTick';
    const { intent, trace } = this.util.choose(player, model, this.blackboard, frame, triggeredBy);
    trace.timeMs = clock.timeMs;
    trace.hasBall = model.self.hasBall;
    trace.phase = `${model.phase.main}${model.phase.sub ? ':' + model.phase.sub : ''}`;
    this.lastTrace = trace;
    this._lastDecisionFrame = frame;
    this.blackboard.clearAssignmentIfKicked(intent);
    this._record(trace);

    // 踢球是一次性动作，执行后转为静止直到下次决策
    if (intent.type === IntentType.Kick) {
      this.currentIntent = { type: IntentType.Idle, playerId: this.id };
      return intent;
    }
    this.currentIntent = intent;
    return intent;
  }

  _record(rec) {
    this.history.push(rec);
    if (this.maxHistory > 0 && this.history.length > this.maxHistory) {
      this.history.splice(0, this.history.length - this.maxHistory);
    }
  }

  _repeat(frame) {
    if (!this.currentIntent) return { type: IntentType.Idle, playerId: this.id, frame };
    return { ...this.currentIntent, frame };
  }

  _dueForBackground(model, frame) {
    if (model.self.hasBall) return true;          // 持球者每帧决策
    if (model.assignment.isTaker) return true;    // 发球者每帧决策（尽快就位/开球）
    const cadence = model.ball.distToMe < 12 ? 3 : 10; // 球近每3帧，否则每10帧
    return (frame - this._lastDecisionFrame) >= cadence;
  }
}

// 把意图转成简短可读标签（用于 repeat 帧的时间线展示）
function labelOfIntent(intent) {
  if (!intent) return 'Idle';
  if (intent.type === IntentType.Kick) return `Kick:${intent.kind}`;
  if (intent.type === IntentType.Move) {
    const t = intent.target;
    return t ? `Move→(${t.x.toFixed(0)},${t.y.toFixed(0)})` : 'Move';
  }
  return 'Idle';
}
