// agent/decision/considerations.js — 效用评分曲线库（metric → [0,1]）
// 见 03-player-agent.md §4.4

import * as V from '../../core/Vec2.js';

const clamp01 = (x) => Math.max(0, Math.min(1, x));

const OPEN_REF = 12;   // 空档参考距离(m)
const INTERCEPT_REF = 3; // 传球线路被封参考距离(m)
const PRESSURE_REF = 6;

// 目标点周围对手越少越"空"
export function openness(pos, opponents) {
  let nearest = Infinity;
  for (const o of opponents) {
    const d = V.dist(pos, o.pos);
    if (d < nearest) nearest = d;
  }
  if (nearest === Infinity) return 1;
  return clamp01(nearest / OPEN_REF);
}

// 向对方球门推进的收益（0.5 为原地，越前越高）
export function forwardProgress(attackDirX, fromPos, toPos) {
  const adv = (toPos.x - fromPos.x) * attackDirX;
  return clamp01(0.5 + adv / 50 * 0.5);
}

// 传球线路被拦截的风险（0..1，越高越危险）
export function interceptRisk(from, to, opponents) {
  let risk = 0;
  for (const o of opponents) {
    const d = V.pointToSegment(o.pos, from, to);
    risk = Math.max(risk, clamp01(1 - d / INTERCEPT_REF));
  }
  return risk;
}

// 传球距离越远、越吃传球属性
export function distanceFactor(dist, passing) {
  const reach = 18 + (passing / 100) * 55;
  return clamp01(1 - dist / reach);
}

// 距对方球门的接近度（越近越高）
export function goalCloseness(pos, goalPos, ref = 28) {
  const d = V.dist(pos, goalPos);
  return clamp01(1 - d / ref);
}

// 自身被逼抢程度（最近对手越近越高）
export function pressure(pos, opponents) {
  let nearest = Infinity;
  for (const o of opponents) {
    const d = V.dist(pos, o.pos);
    if (d < nearest) nearest = d;
  }
  if (nearest === Infinity) return 0;
  return clamp01(1 - nearest / PRESSURE_REF);
}

export { clamp01 };
