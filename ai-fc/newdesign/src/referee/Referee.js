// referee/Referee.js — 比赛状态机主控：观察世界 → 判定 → 发布事件
// 从不指挥球员的具体动作。见 02-match-mechanics.md

import * as V from '../core/Vec2.js';
import {
  PhaseMain, PhaseSub, RestartType, EventType, TeamId, opponentTeam,
} from '../core/enums.js';
import { detectOutOfPlay } from './rules/outOfPlay.js';
import { selectRestartTaker } from './rules/restartTaker.js';

export class Referee {
  constructor() {
    this._matchStarted = false;
    this._readyFrame = -1;
    this._prevPhaseKey = 'PreMatch:-';
    this._prevPossTeam = null;
    this._prevOwnerId = null;
  }

  observe(world, bus, clock) {
    const pub = (type, extra = {}) =>
      bus.publish({ type, frame: clock.frame, timeMs: clock.timeMs, ...extra });

    if (!this._matchStarted) {
      this._matchStarted = true;
      pub(EventType.MatchStarted, {});
    }

    switch (world.phase.main) {
      case PhaseMain.PRE_MATCH:
        this._setupKickoff(world, pub, TeamId.HOME);
        break;
      case PhaseMain.KICKOFF:
        this._updateReady(world, pub, clock);
        this._checkRestartKicked(world, pub);
        break;
      case PhaseMain.IN_PLAY: {
        const out = detectOutOfPlay(world);
        if (out) this._handleOut(world, pub, out);
        break;
      }
      case PhaseMain.DEAD_BALL:
        this._updateReady(world, pub, clock);
        this._checkRestartKicked(world, pub);
        break;
      default:
        break;
    }

    // 阶段变化事件
    const key = world.phaseKey();
    if (this._prevPhaseKey !== null && this._prevPhaseKey !== key) {
      pub(EventType.PhaseChanged, {
        from: this._parseKey(this._prevPhaseKey),
        to: { main: world.phase.main, sub: world.phase.sub },
      });
    }
    this._prevPhaseKey = key;

    // 球权变化事件
    this._checkPossession(world, pub);
  }

  _parseKey(key) {
    const [main, sub] = key.split(':');
    return { main, sub: sub === '-' ? null : sub };
  }

  _setPhase(world, main, sub) {
    world.phase.main = main;
    world.phase.sub = sub;
  }

  _setupKickoff(world, pub, team) {
    const spot = { ...world.field.center };
    const b = world.ball;
    b.pos = { ...spot }; b.prevPos = { ...spot }; b.vel = { x: 0, y: 0 };
    b.ownerId = null; b.lastTouch = null;

    this._setPhase(world, PhaseMain.KICKOFF, null);
    world.phase.restartTeam = team;
    world.phase.restartType = RestartType.KICKOFF;
    world.phase.restartSpot = { ...spot };
    world.phase.takerId = null;
    world.phase.restartReady = false;

    pub(EventType.KickoffAwarded, { teamId: team, spot: { ...spot } });

    const takerId = selectRestartTaker(world, {
      team, spot, restartType: RestartType.KICKOFF, config: world.config,
    });
    world.phase.takerId = takerId;
    pub(EventType.RestartAssigned, { playerId: takerId, restartType: RestartType.KICKOFF, spot: { ...spot } });
  }

  _handleOut(world, pub, out) {
    const b = world.ball;

    if (out.kind === 'goal') {
      if (out.scoreTeam === TeamId.HOME) world.score.home += 1; else world.score.away += 1;
      pub(EventType.GoalScored, {
        teamId: out.scoreTeam,
        scorerId: out.lastTouch ? out.lastTouch.playerId : null,
      });
      // 失球方中圈开球
      this._setupKickoff(world, pub, opponentTeam(out.scoreTeam));
      return;
    }

    // 计算发球位置
    let spot;
    if (out.kind === RestartType.CORNER) spot = { ...out.corner };
    else if (out.kind === RestartType.GOAL_KICK) spot = world.field.goalKickSpot(out.awardTeam);
    else spot = { ...out.exitPoint }; // throwIn

    // 事件序列：BallOutOfPlay → PhaseChanged(隐式) → *Awarded → RestartAssigned
    pub(EventType.BallOutOfPlay, {
      lastTouchPlayerId: out.lastTouch ? out.lastTouch.playerId : null,
      lastTouchTeamId: out.lastTouch ? out.lastTouch.teamId : null,
      exitPoint: { ...out.exitPoint },
      side: out.side,
    });

    const subMap = {
      [RestartType.THROW_IN]: PhaseSub.THROW_IN,
      [RestartType.CORNER]: PhaseSub.CORNER,
      [RestartType.GOAL_KICK]: PhaseSub.GOAL_KICK,
    };
    this._setPhase(world, PhaseMain.DEAD_BALL, subMap[out.kind] || PhaseSub.THROW_IN);
    world.phase.restartTeam = out.awardTeam;
    world.phase.restartType = out.kind;
    world.phase.restartSpot = { ...spot };
    world.phase.takerId = null;
    world.phase.restartReady = false;

    // 把球停在发球点
    b.pos = { ...spot }; b.prevPos = { ...spot }; b.vel = { x: 0, y: 0 }; b.ownerId = null;

    if (out.kind === RestartType.THROW_IN) {
      pub(EventType.ThrowInAwarded, { teamId: out.awardTeam, spot: { ...spot } });
    } else if (out.kind === RestartType.CORNER) {
      pub(EventType.CornerKickAwarded, { teamId: out.awardTeam, corner: { ...spot } });
    } else if (out.kind === RestartType.GOAL_KICK) {
      pub(EventType.GoalKickAwarded, { teamId: out.awardTeam, spot: { ...spot } });
    }

    const takerId = selectRestartTaker(world, {
      team: out.awardTeam, spot, restartType: out.kind, config: world.config,
    });
    world.phase.takerId = takerId;
    pub(EventType.RestartAssigned, { playerId: takerId, restartType: out.kind, spot: { ...spot } });
  }

  _updateReady(world, pub, clock) {
    if (world.phase.restartReady) return;
    const taker = world.getPlayer(world.phase.takerId);
    if (!taker) return;
    const spot = world.phase.restartSpot;
    const r = world.config.restartReadyRadius ?? 0.8;
    const vmax = world.config.restartReadySpeedMax ?? 0.4;
    if (V.dist(taker.pos, spot) <= r && V.len(taker.vel) <= vmax) {
      world.phase.restartReady = true;
      this._readyFrame = clock.frame;
      pub(EventType.RestartReady, { playerId: taker.id });
    }
  }

  // 发球者已就位并踢出 → 进入 InPlay
  _checkRestartKicked(world, pub) {
    if (!world.phase.restartReady) return;
    const b = world.ball;
    const lt = b.lastTouch;
    const kicked = b.ownerId === null
      && V.len(b.vel) > 1
      && lt && lt.playerId === world.phase.takerId
      && lt.frame >= this._readyFrame;
    if (!kicked) return;

    this._setPhase(world, PhaseMain.IN_PLAY, null);
    world.phase.restartTeam = null;
    world.phase.restartType = null;
    world.phase.restartSpot = null;
    world.phase.takerId = null;
    world.phase.restartReady = false;
    this._readyFrame = -1;
  }

  _checkPossession(world, pub) {
    const ownerId = world.ball.ownerId;
    if (ownerId === this._prevOwnerId) return;
    this._prevOwnerId = ownerId;
    if (!ownerId) return;
    const owner = world.getPlayer(ownerId);
    if (!owner) return;
    if (owner.teamId !== this._prevPossTeam) {
      pub(EventType.PossessionChanged, {
        fromTeamId: this._prevPossTeam,
        toTeamId: owner.teamId,
        playerId: owner.id,
      });
      this._prevPossTeam = owner.teamId;
      world.possession.teamId = owner.teamId;
    }
    world.possession.playerId = owner.id;
  }
}
