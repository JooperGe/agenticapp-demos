// physics/PhysicsEngine.js — 执行意图、积分球与球员运动、处理控球
// 不含任何战术智慧。见 01-architecture.md §2 步骤⑤

import * as V from '../core/Vec2.js';
import { IntentType, SpeedMode, SPEED_MS, PhaseMain } from '../core/enums.js';

const CONTROL_RADIUS = 1.2;   // 控球半径 (m)
const CONTROL_SPEED = 10;     // 球速低于此值才可被接管 (m/s)
const CONTROL_AHEAD = 0.45;   // 持球时球在身前的距离
const FRICTION_DECEL = 7;     // 地面球减速度 (m/s^2)
const KICK_COOLDOWN_FRAMES = 18;
const STOP_DIST = 0.15;

const KICK_SPEED = {
  pass: (p) => 8 + p * 14,
  throwIn: (p) => 6 + p * 8,
  clear: (p) => 14 + p * 12,
  shoot: (p) => 16 + p * 14,
};

export class PhysicsEngine {
  constructor(rng) {
    this.rng = rng;
    this._cooldown = { playerId: null, untilFrame: -1 };
  }

  // resolved: [{intent, accepted, reason}]
  integrate(world, resolved, dt, frame) {
    const ball = world.ball;
    ball.prevPos = V.clone(ball.pos);

    // 按球员归集意图
    const moveByPlayer = new Map();
    let kick = null;
    for (const r of resolved) {
      if (!r.accepted) continue;
      const it = r.intent;
      if (it.type === IntentType.Move) moveByPlayer.set(it.playerId, it);
      else if (it.type === IntentType.Kick) kick = it; // M1 同帧至多一次踢球生效
    }

    // 1) 球员移动
    for (const p of world.players) {
      const it = moveByPlayer.get(p.id);
      if (it && it.type === IntentType.Move) {
        this._movePlayer(p, it, dt);
      } else {
        // 无移动意图：减速
        p.vel = V.scale(p.vel, 0.6);
        if (V.len(p.vel) < 0.05) p.vel = { x: 0, y: 0 };
        p.pos = V.add(p.pos, V.scale(p.vel, dt));
        p.speedMode = SpeedMode.STAND;
      }
      // 限制在场地内（允许略微贴线）
      p.pos = world.field.clampInside(p.pos, 0);
    }

    // 2) 踢球（释放球权）
    if (kick) this._applyKick(world, kick, frame);

    // 3) 球积分
    if (ball.ownerId) {
      const owner = world.getPlayer(ball.ownerId);
      if (owner) {
        const ahead = V.fromAngle(owner.facing, CONTROL_AHEAD);
        ball.pos = V.add(owner.pos, ahead);
        ball.vel = V.clone(owner.vel);
      }
    } else {
      ball.pos = V.add(ball.pos, V.scale(ball.vel, dt));
      const sp = V.len(ball.vel);
      if (sp > 0) {
        const ns = Math.max(0, sp - FRICTION_DECEL * dt);
        ball.vel = ns < 1e-6 ? { x: 0, y: 0 } : V.scale(V.norm(ball.vel), ns);
      }
    }

    // 4) 控球接管
    this._tryGainPossession(world, frame);
  }

  _movePlayer(p, it, dt) {
    const toTarget = V.sub(it.target, p.pos);
    const d = V.len(toTarget);
    if (d < STOP_DIST) {
      p.vel = { x: 0, y: 0 };
      p.speedMode = SpeedMode.STAND;
      return;
    }
    const mode = it.speedMode || SpeedMode.RUN;
    const base = SPEED_MS[mode] ?? SPEED_MS.run;
    const speed = base * (0.6 + 0.4 * (p.attributes.pace / 100));
    const step = Math.min(speed, d / dt); // 不越过目标
    const dir = V.norm(toTarget);
    p.vel = V.scale(dir, step);
    p.pos = V.add(p.pos, V.scale(p.vel, dt));
    p.facing = V.angle(dir);
    p.speedMode = mode;
  }

  _applyKick(world, kick, frame) {
    const ball = world.ball;
    const kicker = world.getPlayer(kick.playerId);
    if (!kicker) return;

    // 目标点
    let target = kick.targetPoint;
    if (!target && kick.targetPlayerId) {
      const t = world.getPlayer(kick.targetPlayerId);
      if (t) target = V.clone(t.pos);
    }
    if (!target) target = V.add(ball.pos, V.fromAngle(kicker.facing, 10));

    const from = ball.pos;
    let dir = V.norm(V.sub(target, from));
    // 执行噪声：技术越差/越累，偏差越大
    const attr = (kick.kind === 'shoot' ? kicker.attributes.shooting : kicker.attributes.passing);
    const std = (1 - attr / 100) * 0.16 + (1 - kicker.stamina / 100) * 0.05;
    const noisy = V.angle(dir) + this.rng.gaussian(0, std);
    dir = V.fromAngle(noisy, 1);

    const power = Math.max(0, Math.min(1, kick.power ?? 0.6));
    const speed = (KICK_SPEED[kick.kind] || KICK_SPEED.pass)(power);

    ball.ownerId = null;
    ball.vel = V.scale(dir, speed);
    ball.lastTouch = { playerId: kicker.id, teamId: kicker.teamId, frame };
    this._cooldown = { playerId: kicker.id, untilFrame: frame + KICK_COOLDOWN_FRAMES };
  }

  _tryGainPossession(world, frame) {
    const ball = world.ball;
    if (ball.ownerId) return;
    if (V.len(ball.vel) > CONTROL_SPEED) return;

    // 死球/开球/赛前：球是"死"的，只有被指派的发球者可控球
    const ph = world.phase.main;
    const deadish = ph === PhaseMain.PRE_MATCH || ph === PhaseMain.KICKOFF || ph === PhaseMain.DEAD_BALL;

    let best = null; let bestD = Infinity;
    for (const p of world.players) {
      if (deadish && p.id !== world.phase.takerId) continue;
      const d = V.dist(p.pos, ball.pos);
      if (d > CONTROL_RADIUS) continue;
      // 踢球者冷却期内且球仍近，暂不回收
      if (this._cooldown.playerId === p.id && frame < this._cooldown.untilFrame && d < 2) continue;
      if (d < bestD) { bestD = d; best = p; }
    }
    if (best) {
      ball.ownerId = best.id;
      ball.vel = { x: 0, y: 0 };
      ball.lastTouch = { playerId: best.id, teamId: best.teamId, frame };
    }
  }
}
