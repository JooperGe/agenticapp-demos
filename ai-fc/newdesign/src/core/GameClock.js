// core/GameClock.js — 比赛时钟：帧号、比赛毫秒、倍速、暂停

export class GameClock {
  constructor({ fps = 60, speed = 1 } = {}) {
    this.fps = fps;
    this.baseDt = 1 / fps;      // 秒/帧（真实时间）
    this.speed = speed;         // 倍速（M1 = 1）
    this.frame = 0;
    this.timeMs = 0;            // 比赛已进行毫秒
    this.half = 1;
    this.paused = false;
  }
  // 返回本帧的仿真 dt（秒）
  get dt() {
    return this.baseDt * this.speed;
  }
  advance() {
    if (this.paused) return 0;
    this.frame += 1;
    const dt = this.dt;
    this.timeMs += dt * 1000;
    return dt;
  }
  get clockLabel() {
    const totalSec = Math.floor(this.timeMs / 1000);
    const mm = String(Math.floor(totalSec / 60)).padStart(2, '0');
    const ss = String(totalSec % 60).padStart(2, '0');
    return `${mm}:${ss}`;
  }
}
