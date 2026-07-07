// world/Field.js — 球场几何与边界工具（只读）
// 坐标：x ∈ [0, length]（长），y ∈ [0, width]（宽），原点左下角
// 触边线(touchline)：y=0 / y=width；底线(goal line)：x=0 / x=length

import { BoundarySide, TeamId } from '../core/enums.js';

export class Field {
  constructor(cfg = {}) {
    this.length = cfg.length ?? 105;
    this.width = cfg.width ?? 68;
    this.centerCircleRadius = cfg.centerCircleRadius ?? 9.15;
    this.penaltyAreaLength = cfg.penaltyAreaLength ?? 16.5;
    this.penaltyAreaWidth = cfg.penaltyAreaWidth ?? 40.32;
    this.goalWidth = cfg.goalWidth ?? 7.32;
    this.goalPostRadius = cfg.goalPostRadius ?? 0.06;
    this.center = { x: this.length / 2, y: this.width / 2 };
  }

  get goalYMin() { return this.width / 2 - this.goalWidth / 2; }
  get goalYMax() { return this.width / 2 + this.goalWidth / 2; }

  corners() {
    return [
      { x: 0, y: 0 }, { x: 0, y: this.width },
      { x: this.length, y: 0 }, { x: this.length, y: this.width },
    ];
  }

  nearestCorner(p) {
    return this.corners().reduce((best, c) =>
      (Math.hypot(p.x - c.x, p.y - c.y) < Math.hypot(p.x - best.x, p.y - best.y) ? c : best));
  }

  // away 防守 x=length 的底线；home 防守 x=0 的底线
  defendingGoalLineX(teamId) {
    return teamId === TeamId.HOME ? 0 : this.length;
  }

  // 小禁区/球门球发球点（防守方）
  goalKickSpot(teamId) {
    const x = teamId === TeamId.HOME ? this.penaltyAreaLength : this.length - this.penaltyAreaLength;
    return { x, y: this.width / 2 };
  }

  clampInside(p, margin = 0) {
    return {
      x: Math.max(margin, Math.min(this.length - margin, p.x)),
      y: Math.max(margin, Math.min(this.width - margin, p.y)),
    };
  }

  // 给定越线信息，返回是否越过门框之间（用于进球判定）
  isBetweenGoalPosts(y) {
    return y >= this.goalYMin && y <= this.goalYMax;
  }
}

export { BoundarySide };
