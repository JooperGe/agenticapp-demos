// world/entities.js — Ball 与 Player 的工厂（纯数据对象）
// 见 04-data-schemas.md §1

import { SpeedMode } from '../core/enums.js';

export function createBall(pos = { x: 52.5, y: 34 }) {
  return {
    pos: { ...pos },
    prevPos: { ...pos }, // 上一帧位置，供裁判做越线插值
    vel: { x: 0, y: 0 },
    height: 0,
    ownerId: null,
    lastTouch: null, // { playerId, teamId, frame }
  };
}

export function createPlayer(spec) {
  return {
    id: spec.id,
    teamId: spec.teamId,
    number: spec.number,
    role: spec.role,
    pos: { ...spec.anchor },
    vel: { x: 0, y: 0 },
    facing: spec.teamId === 'home' ? 0 : Math.PI,
    speedMode: SpeedMode.STAND,
    stamina: 100,
    attributes: {
      pace: 70, passing: 70, shooting: 65, dribbling: 68,
      tackling: 68, vision: 70, decision: 70, strength: 70,
      ...(spec.attributes || {}),
    },
    formationAnchor: { ...spec.anchor },
  };
}
