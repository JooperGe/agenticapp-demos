// agent/decision/UtilitySystem.js — 效用系统：收集候选→打分→取最优
// 见 03-player-agent.md §4

import { collectCandidates } from './actions.js';
import { IntentType } from '../../core/enums.js';

export class UtilitySystem {
  constructor(rng) {
    this.rng = rng;
  }

  // player: 世界中的 Player（含 attributes/pos/formationAnchor）
  // model: LocalModel
  // 返回 { intent, trace }
  choose(player, model, blackboard, frame, triggeredBy) {
    const ctx = {
      self: player,
      model,
      oppGoalPos: model.geom.attackGoal,
      ownGoalPos: model.geom.ownGoal,
    };

    const candidates = collectCandidates(ctx);

    // 打分 + 轻微噪声（人味），取最高
    let best = null;
    const traceCands = [];
    for (const c of candidates) {
      const noisy = c.score * (1 + this.rng.gaussian(0, 0.04));
      traceCands.push({
        action: c.action,
        score: Number(c.score.toFixed(3)),
        considerations: c.considerations,
      });
      if (!best || noisy > best._noisy) best = { ...c, _noisy: noisy };
    }

    let intent;
    if (best) intent = best.toIntent(frame);
    else intent = { type: IntentType.Idle, playerId: player.id, frame };

    const trace = {
      playerId: player.id,
      frame,
      triggeredBy,
      candidates: traceCands,
      chosen: best ? { action: best.action, score: Number(best.score.toFixed(3)) } : { action: 'Idle', score: 0 },
    };
    return { intent, trace };
  }
}
