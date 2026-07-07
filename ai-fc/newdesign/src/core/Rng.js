// core/Rng.js — 种子化随机数（mulberry32），保证仿真可复现

export class Rng {
  constructor(seed = 0x9e3779b9) {
    this.state = seed >>> 0;
  }
  // [0, 1)
  next() {
    this.state |= 0;
    this.state = (this.state + 0x6d2b79f5) | 0;
    let t = Math.imul(this.state ^ (this.state >>> 15), 1 | this.state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }
  // [min, max)
  range(min, max) {
    return min + (max - min) * this.next();
  }
  // 近似标准正态（Box-Muller）
  gaussian(mean = 0, std = 1) {
    const u = Math.max(1e-9, this.next());
    const vv = this.next();
    return mean + std * Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * vv);
  }
}
