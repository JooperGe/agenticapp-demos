// referee/rules/outOfPlay.js — 出界检测 + 定位球类型/球权判定
// 纯函数：读 world.ball.prevPos→pos 的越线，返回判定结果或 null
// 见 02-match-mechanics.md §3

import * as V from '../../core/Vec2.js';
import { TeamId, BoundarySide, RestartType, opponentTeam } from '../../core/enums.js';

const clamp = (x, a, b) => Math.max(a, Math.min(b, x));

export function detectOutOfPlay(world) {
  const f = world.field;
  const b = world.ball;
  const p0 = b.prevPos;
  const p1 = b.pos;
  const tol = world.config.lineTolerance ?? 0.11;

  // 触边线（长边）：y=0（bottom）/ y=width（top） → 界外球
  let x = V.crossHorizontal(p0, p1, 0 - tol);
  if (x !== null && x >= -tol && x <= f.length + tol) {
    return throwInResult(world, { x: clamp(x, 0, f.length), y: 0 }, BoundarySide.TOUCH_BOTTOM);
  }
  x = V.crossHorizontal(p0, p1, f.width + tol);
  if (x !== null && x >= -tol && x <= f.length + tol) {
    return throwInResult(world, { x: clamp(x, 0, f.length), y: f.width }, BoundarySide.TOUCH_TOP);
  }

  // 底线（短边）：x=0（home 防守）/ x=length（away 防守）
  let y = V.crossVertical(p0, p1, 0 - tol);
  if (y !== null && y >= -tol && y <= f.width + tol) {
    return goalLineResult(world, { x: 0, y: clamp(y, 0, f.width) }, BoundarySide.GOAL_LINE_HOME);
  }
  y = V.crossVertical(p0, p1, f.length + tol);
  if (y !== null && y >= -tol && y <= f.width + tol) {
    return goalLineResult(world, { x: f.length, y: clamp(y, 0, f.width) }, BoundarySide.GOAL_LINE_AWAY);
  }

  return null;
}

function lastTeamOf(world) {
  return world.ball.lastTouch ? world.ball.lastTouch.teamId : TeamId.HOME;
}

function throwInResult(world, exitPoint, side) {
  const lastTeam = lastTeamOf(world);
  return {
    kind: RestartType.THROW_IN,
    side,
    exitPoint,
    awardTeam: opponentTeam(lastTeam),
    lastTouch: world.ball.lastTouch,
  };
}

function goalLineResult(world, exitPoint, side) {
  const f = world.field;
  const lastTeam = lastTeamOf(world);

  // 进球：完全越过门框之间
  if (f.isBetweenGoalPosts(exitPoint.y)) {
    const scoreTeam = side === BoundarySide.GOAL_LINE_AWAY ? TeamId.HOME : TeamId.AWAY;
    return { kind: 'goal', side, exitPoint, scoreTeam, lastTouch: world.ball.lastTouch };
  }

  const defTeam = side === BoundarySide.GOAL_LINE_HOME ? TeamId.HOME : TeamId.AWAY;
  if (lastTeam === defTeam) {
    // 防守方最后触球 → 角球给进攻方
    const corner = { x: exitPoint.x, y: exitPoint.y < f.width / 2 ? 0 : f.width };
    return { kind: RestartType.CORNER, side, exitPoint, corner, awardTeam: opponentTeam(defTeam), lastTouch: world.ball.lastTouch };
  }
  // 进攻方最后触球 → 球门球给防守方
  return { kind: RestartType.GOAL_KICK, side, exitPoint, awardTeam: defTeam, lastTouch: world.ball.lastTouch };
}
