// world/World.js — 权威世界状态（系统唯一事实来源）
// 见 04-data-schemas.md §1

import { PhaseMain, TeamId } from '../core/enums.js';

export class World {
  constructor({ field, ball, players, config }) {
    this.field = field;
    this.ball = ball;
    this.players = players; // [Player]
    this.config = config;   // RulesConfig
    this.score = { home: 0, away: 0 };

    this.phase = {
      main: PhaseMain.PRE_MATCH,
      sub: null,
      restartTeam: null,
      restartType: null,
      restartSpot: null,
      takerId: null,
      restartReady: false,
    };
    this.possession = { teamId: null, playerId: null };

    this._byId = new Map(players.map((p) => [p.id, p]));
  }

  getPlayer(id) { return this._byId.get(id) || null; }
  team(teamId) { return this.players.filter((p) => p.teamId === teamId); }
  teammates(player) { return this.players.filter((p) => p.teamId === player.teamId && p.id !== player.id); }
  opponents(player) { return this.players.filter((p) => p.teamId !== player.teamId); }

  get ballOwner() { return this.ball.ownerId ? this.getPlayer(this.ball.ownerId) : null; }

  // 阶段快照 key（用于检测阶段变化）
  phaseKey() { return `${this.phase.main}:${this.phase.sub || '-'}`; }
}

export { TeamId };
