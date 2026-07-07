// referee/rules/restartTaker.js — "由哪个球员发球"的选定规则
// 纯函数：(world, {team, spot, restartType, config}) -> playerId
// 见 02-match-mechanics.md §4

import * as V from '../../core/Vec2.js';
import { Role, RestartType } from '../../core/enums.js';

export function selectRestartTaker(world, { team, spot, restartType, config }) {
  const players = world.team(team);
  if (players.length === 0) return null;

  // 球门球：默认门将
  if (restartType === RestartType.GOAL_KICK) {
    const gk = players.find((p) => p.role === Role.GK);
    if (gk) return gk.id;
  }

  // 开球：优先配置的开球手号码
  if (restartType === RestartType.KICKOFF && config.kickoffTakerNumber != null) {
    const pref = players.find((p) => p.number === config.kickoffTakerNumber);
    if (pref) return pref.id;
  }

  // 其余：发球方中距离 spot 最近的（默认排除门将）
  const excludeGK = restartType === RestartType.THROW_IN
    ? !!config.throwInTakerExcludeGK
    : restartType !== RestartType.GOAL_KICK;
  let pool = players.filter((p) => !(excludeGK && p.role === Role.GK));
  if (pool.length === 0) pool = players;

  let best = null; let bestD = Infinity;
  for (const p of pool) {
    const d = V.dist(p.pos, spot);
    if (d < bestD) { bestD = d; best = p; }
  }
  return best ? best.id : players[0].id;
}
