// sim/bootstrap.js — 初始化世界、22 名球员、裁判、物理，装配 MatchLoop
// 见 01-architecture.md §4

import { Rng } from '../core/Rng.js';
import { GameClock } from '../core/GameClock.js';
import { EventBus } from '../core/EventBus.js';
import { Field } from '../world/Field.js';
import { World } from '../world/World.js';
import { createBall, createPlayer } from '../world/entities.js';
import { PhysicsEngine } from '../physics/PhysicsEngine.js';
import { IntentResolver } from '../physics/IntentResolver.js';
import { Referee } from '../referee/Referee.js';
import { PlayerAgent } from '../agent/PlayerAgent.js';
import { MatchLoop } from './MatchLoop.js';
import { FIELD, RULES, buildRoster } from '../config/defaults.js';

export function bootstrap({ seed = 20260707, renderer = null, debug = null } = {}) {
  const rng = new Rng(seed);
  const clock = new GameClock({ fps: 60, speed: 1 });
  const bus = new EventBus();

  const field = new Field(FIELD);
  const roster = buildRoster();
  const players = roster.all.map((spec) => createPlayer(spec));
  const ball = createBall(field.center);

  const world = new World({ field, ball, players, config: RULES });

  const agents = players.map((p) => {
    bus.registerPlayer(p.id);
    return new PlayerAgent(p.id, rng);
  });

  const physics = new PhysicsEngine(rng);
  const resolver = new IntentResolver();
  const referee = new Referee();

  const loop = new MatchLoop({
    world, clock, bus, referee, agents, physics, resolver, renderer, debug,
  });

  return { world, clock, bus, agents, physics, resolver, referee, loop, rng };
}
