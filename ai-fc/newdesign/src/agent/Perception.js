// agent/Perception.js — 从权威世界构建球员的"局部世界模型"
// M1：全场可见占位实现；LocalModel 字段冻结（见 04 §4），
// 后续换视野扇形+距离衰减时只改本文件填充逻辑，不改字段。

import * as V from '../core/Vec2.js';
import { openness as opennessOf } from './decision/considerations.js';
import { attackDir } from '../core/enums.js';

export class Perception {
  static build(world, player, blackboard) {
    const ball = world.ball;
    const opponents = world.opponents(player).map((o) => ({
      id: o.id,
      pos: { ...o.pos },
      distToMe: V.dist(player.pos, o.pos),
      threat: clamp01(1 - V.dist(o.pos, ball.pos) / 30),
    }));
    const oppPositions = opponents; // 已含 pos
    const teammates = world.teammates(player).map((t) => ({
      id: t.id,
      pos: { ...t.pos },
      distToMe: V.dist(player.pos, t.pos),
      openness: opennessOf(t.pos, oppPositions),
      isCalling: false,
    }));

    const ownerTeam = ball.ownerId ? (world.getPlayer(ball.ownerId)?.teamId ?? null) : null;
    const dir = attackDir(player.teamId);
    const L = world.field.length;
    const Wy = world.field.width / 2;

    return {
      self: {
        id: player.id,
        teamId: player.teamId,
        role: player.role,
        pos: { ...player.pos },
        vel: { ...player.vel },
        facing: player.facing,
        stamina: player.stamina,
        hasBall: ball.ownerId === player.id,
        formationAnchor: { ...player.formationAnchor },
      },
      ball: {
        pos: { ...ball.pos },
        vel: { ...ball.vel },
        ownerId: ball.ownerId,
        ownerTeam,
        distToMe: V.dist(player.pos, ball.pos),
      },
      teammates,
      opponents,
      space: null, // M1 省略空档网格
      phase: {
        main: world.phase.main,
        sub: world.phase.sub,
        restartTeam: world.phase.restartTeam,
        restartType: world.phase.restartType,
        takerId: world.phase.takerId,
        restartReady: world.phase.restartReady,
      },
      assignment: {
        isTaker: blackboard.assignment.isTaker,
        restartType: blackboard.assignment.restartType,
        spot: blackboard.assignment.spot,
      },
      geom: {
        fieldLength: L,
        fieldWidth: world.field.width,
        attackGoal: { x: dir > 0 ? L : 0, y: Wy },
        ownGoal: { x: dir > 0 ? 0 : L, y: Wy },
      },
    };
  }
}

const clamp01 = (x) => Math.max(0, Math.min(1, x));
