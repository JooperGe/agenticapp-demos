// agent/decision/actions.js — 候选动作目录：生成实例 + 打分 + 转 Intent
// 见 03-player-agent.md §4.3 / §4.4
// 每个 action 提供 applicable(ctx) -> [candidate]，candidate.score 已算好，
// candidate.toIntent(frame) -> Intent

import * as V from '../../core/Vec2.js';
import {
  IntentType, SpeedMode, RestartType, PhaseMain, attackDir,
} from '../../core/enums.js';
import * as C from './considerations.js';

// ctx = { self, model, blackboard, oppGoalPos }
// model: LocalModel (见 04 §4)

const mkMove = (self, target, speedMode) => (frame) => ({
  type: IntentType.Move, playerId: self.id, target, speedMode, frame,
});
const mkIdle = (self) => (frame) => ({ type: IntentType.Idle, playerId: self.id, frame });
const mkKick = (self, kind, targetPlayerId, targetPoint, power) => (frame) => ({
  type: IntentType.Kick, playerId: self.id, kind,
  targetPlayerId: targetPlayerId ?? null,
  targetPoint: targetPoint ?? null,
  power, curve: 0, frame,
});

function cand(action, score, considerations, toIntent, meta = {}) {
  return { action, score, considerations, toIntent, meta };
}

// ---------- 死球/开球期：发球者 ----------

function goToRestartSpot(ctx) {
  const { self, model } = ctx;
  if (!model.assignment.isTaker) return [];
  if (model.phase.restartReady) return []; // 已就位，交给发球动作
  const spot = model.assignment.spot;
  const d = V.dist(self.pos, spot);
  if (d < 0.3) return [cand('GoToRestartSpot', 0.9, [], mkIdle(self))];
  return [cand('GoToRestartSpot', 2.0, [{ name: 'dist', value: d }],
    mkMove(self, spot, d > 6 ? SpeedMode.run : SpeedMode.jog))];
}

function takeRestart(ctx) {
  const { self, model } = ctx;
  if (!model.assignment.isTaker || !model.phase.restartReady) return [];
  const kind = model.assignment.restartType === RestartType.THROW_IN ? 'throwIn'
    : (model.assignment.restartType === RestartType.GOAL_KICK ? 'clear' : 'pass');
  // 选最佳接球队友（复用传球评分）
  const passes = buildPassCandidates(ctx, kind, 3.0);
  if (passes.length > 0) return passes;
  // 无队友则向前开大脚
  const dir = attackDir(self.teamId);
  const target = { x: self.pos.x + dir * 20, y: self.pos.y };
  return [cand('TakeRestart', 2.0, [], mkKick(self, kind === 'throwIn' ? 'throwIn' : 'clear', null, target, 0.6))];
}

// ---------- 持球期 ----------

function buildPassCandidates(ctx, kind = 'pass', baseP = 1.0) {
  const { self, model, oppGoalPos } = ctx;
  const dir = attackDir(self.teamId);
  const out = [];
  for (const t of model.teammates) {
    const open = C.openness(t.pos, model.opponents);
    const fwd = C.forwardProgress(dir, self.pos, t.pos);
    const dist = V.dist(self.pos, t.pos);
    const risk = C.interceptRisk(self.pos, t.pos, model.opponents);
    const reach = C.distanceFactor(dist, self.attributes.passing);
    if (reach < 0.05) continue;
    const decisionBias = 0.6 + 0.4 * (self.attributes.decision / 100);
    const score = baseP * (0.25 + open * 0.9) * (0.4 + fwd * 0.9)
      * (1 - risk * 0.85 * decisionBias) * (0.3 + reach * 0.7);
    const power = Math.min(1, 0.35 + dist / 45);
    out.push(cand(`Pass→${t.id}`, score,
      [{ name: 'openness', value: open }, { name: 'forward', value: fwd },
       { name: 'interceptRisk', value: risk }, { name: 'reach', value: reach }],
      mkKick(self, kind === 'throwIn' ? 'throwIn' : 'pass', t.id, null, power),
      { target: t.id }));
  }
  return out;
}

function shoot(ctx) {
  const { self, model, oppGoalPos } = ctx;
  const close = C.goalCloseness(self.pos, oppGoalPos, 30);
  if (close < 0.15) return [];
  const risk = C.interceptRisk(self.pos, oppGoalPos, model.opponents);
  const shootAttr = self.attributes.shooting / 100;
  const decisionBias = self.attributes.decision / 100; // 决策差→更爱盲射
  const score = (0.6 + (1 - decisionBias) * 0.6) * (0.2 + close * 1.4) * shootAttr * (1 - risk * 0.5);
  return [cand('Shoot', score, [{ name: 'goalCloseness', value: close }, { name: 'risk', value: risk }],
    mkKick(self, 'shoot', null, oppGoalPos, 0.9))];
}

function dribble(ctx) {
  const { self, model, oppGoalPos } = ctx;
  const dir = attackDir(self.teamId);
  const ahead = { x: self.pos.x + dir * 6, y: self.pos.y };
  const openAhead = C.openness(ahead, model.opponents);
  const press = C.pressure(self.pos, model.opponents);
  const dribbleAttr = self.attributes.dribbling / 100;
  const score = (0.3 + openAhead * 0.8) * (1 - press * 0.6) * (0.5 + dribbleAttr * 0.6) * 0.9;
  return [cand('Dribble', score, [{ name: 'openAhead', value: openAhead }, { name: 'pressure', value: press }],
    mkMove(self, ahead, SpeedMode.run))];
}

function shield(ctx) {
  const { self, model } = ctx;
  const press = C.pressure(self.pos, model.opponents);
  if (press < 0.4) return [];
  // 背身护球：朝远离最近对手方向小步移动
  let nearest = null; let nd = Infinity;
  for (const o of model.opponents) { const d = V.dist(self.pos, o.pos); if (d < nd) { nd = d; nearest = o; } }
  const away = nearest ? V.add(self.pos, V.scale(V.norm(V.sub(self.pos, nearest.pos)), 2)) : self.pos;
  const score = press * (0.6 + self.attributes.strength / 100 * 0.5);
  return [cand('Shield', score, [{ name: 'pressure', value: press }],
    mkMove(self, away, SpeedMode.jog))];
}

// ---------- 无球期 ----------

function moveToSpace(ctx) {
  const { self, model } = ctx;
  const dir = attackDir(self.teamId);
  // 从阵型基准点向前拉出一点，制造接球空间
  const target = { x: self.formationAnchor.x + dir * 6, y: self.formationAnchor.y };
  const open = C.openness(target, model.opponents);
  const score = 0.8 * (0.4 + open * 0.8);
  return [cand('MoveToSpace', score, [{ name: 'openness', value: open }],
    mkMove(self, target, SpeedMode.jog))];
}

function support(ctx) {
  const { self, model } = ctx;
  if (!model.ball.ownerId) return [];
  const dir = attackDir(self.teamId);
  // 跑到持球点前方侧翼接应
  const bp = model.ball.pos;
  const target = { x: bp.x + dir * 8, y: self.formationAnchor.y };
  const open = C.openness(target, model.opponents);
  const score = 0.9 * (0.4 + open * 0.8);
  return [cand('Support', score, [{ name: 'openness', value: open }],
    mkMove(self, target, SpeedMode.run))];
}

function chaseBall(ctx) {
  const { self, model } = ctx;
  // 松球（无主）且我最近 → 去抢
  if (model.ball.ownerId) return [];
  const d = model.ball.distToMe;
  const score = 1.2 * C.clamp01(1 - d / 40);
  return [cand('ChaseBall', score, [{ name: 'distToBall', value: d }],
    mkMove(self, model.ball.pos, d > 8 ? SpeedMode.sprint : SpeedMode.run))];
}

function markOpponent(ctx) {
  const { self, model, ownGoalPos } = ctx;
  // 对方控球：盯最近的对手，站在其与本方球门之间
  let nearest = null; let nd = Infinity;
  for (const o of model.opponents) { const d = V.dist(self.pos, o.pos); if (d < nd) { nd = d; nearest = o; } }
  if (!nearest) return [];
  const between = V.add(nearest.pos, V.scale(V.norm(V.sub(ownGoalPos, nearest.pos)), 1.5));
  const score = 0.85 * C.clamp01(1 - nd / 30);
  return [cand('MarkOpponent', score, [{ name: 'oppDist', value: nd }],
    mkMove(self, between, SpeedMode.run))];
}

function returnToFormation(ctx) {
  const { self } = ctx;
  const d = V.dist(self.pos, self.formationAnchor);
  const score = 0.5 * C.clamp01(d / 20) + 0.15;
  return [cand('ReturnToFormation', score, [{ name: 'dist', value: d }],
    mkMove(self, self.formationAnchor, d > 10 ? SpeedMode.run : SpeedMode.jog))];
}

function idle(ctx) {
  return [cand('Idle', 0.1, [], mkIdle(ctx.self))];
}

// ---------- 上下文过滤：按情境返回适用的动作生成器 ----------

export function collectCandidates(ctx) {
  const { model } = ctx;
  const ph = model.phase.main;
  const list = [];
  const push = (fn) => { for (const c of fn(ctx)) list.push(c); };

  if (ph === PhaseMain.DEAD_BALL || ph === PhaseMain.KICKOFF || ph === PhaseMain.PRE_MATCH) {
    if (model.assignment.isTaker) {
      push(goToRestartSpot);
      push(takeRestart);
    } else {
      // 非发球者：本方球权→拉开接应；对方球权→退防盯人；否则回阵型
      push(returnToFormation);
      if (model.phase.restartTeam === model.self.teamId) push(moveToSpace);
      else push(markOpponent);
    }
    push(idle);
    return list;
  }

  // InPlay
  if (model.self.hasBall) {
    for (const c of buildPassCandidates(ctx, 'pass', 1.0)) list.push(c);
    push(shoot); push(dribble); push(shield);
  } else if (model.ball.ownerId == null) {
    push(chaseBall); push(moveToSpace); push(returnToFormation);
  } else if (model.ball.ownerId && isTeammate(model, model.ball.ownerId)) {
    push(support); push(moveToSpace); push(returnToFormation);
  } else {
    push(markOpponent); push(chaseBall); push(returnToFormation);
  }
  push(idle);
  return list;
}

function isTeammate(model, id) {
  return model.teammates.some((t) => t.id === id);
}
