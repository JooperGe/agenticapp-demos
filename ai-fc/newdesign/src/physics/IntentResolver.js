// physics/IntentResolver.js — 意图合法性预检 + 冲突仲裁
// 规则边界由裁判状态(World.phase)定义；物理层据此放行/驳回意图
// 见 01-architecture.md §5、02-match-mechanics.md §5

import { IntentType, PhaseMain } from '../core/enums.js';

export class IntentResolver {
  // intents: [Intent|null]  → 返回 [{ intent, accepted, reason }]
  resolve(world, intents) {
    const out = [];
    for (const intent of intents) {
      if (!intent) continue;
      out.push(this._check(world, intent));
    }
    return out;
  }

  _check(world, intent) {
    const accept = (reason = null) => ({ intent, accepted: true, reason });
    const reject = (reason) => ({ intent, accepted: false, reason });

    // 移动/静止永远合法
    if (intent.type === IntentType.Move || intent.type === IntentType.Idle) return accept();

    if (intent.type === IntentType.Kick) {
      const ph = world.phase;
      // 死球阶段：只有被指派且已就位的发球者可以踢球
      if (ph.main === PhaseMain.DEAD_BALL) {
        if (intent.playerId !== ph.takerId) return reject('dead-ball-not-taker');
        if (!ph.restartReady) return reject('dead-ball-not-ready');
        return accept();
      }
      // 开球阶段：只有开球手可踢，且需就位
      if (ph.main === PhaseMain.KICKOFF) {
        if (intent.playerId !== ph.takerId) return reject('kickoff-not-taker');
        if (!ph.restartReady) return reject('kickoff-not-ready');
        return accept();
      }
      // InPlay：必须是持球者才能踢
      if (ph.main === PhaseMain.IN_PLAY) {
        if (world.ball.ownerId !== intent.playerId) return reject('not-ball-owner');
        return accept();
      }
      return reject('phase-not-kickable');
    }

    // 抢断/拦截等（M1 直接放行，后续加仲裁）
    return accept();
  }
}
