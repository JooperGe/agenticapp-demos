// core/Vec2.js — 二维向量工具（纯函数，向量为 {x, y} 字面量）

export const v = (x = 0, y = 0) => ({ x, y });
export const clone = (a) => ({ x: a.x, y: a.y });
export const add = (a, b) => ({ x: a.x + b.x, y: a.y + b.y });
export const sub = (a, b) => ({ x: a.x - b.x, y: a.y - b.y });
export const scale = (a, s) => ({ x: a.x * s, y: a.y * s });
export const len = (a) => Math.hypot(a.x, a.y);
export const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
export const dist2 = (a, b) => (a.x - b.x) ** 2 + (a.y - b.y) ** 2;

export function norm(a) {
  const l = len(a);
  return l < 1e-9 ? { x: 0, y: 0 } : { x: a.x / l, y: a.y / l };
}
export const angle = (a) => Math.atan2(a.y, a.x);
export const fromAngle = (rad, l = 1) => ({ x: Math.cos(rad) * l, y: Math.sin(rad) * l });

// 点 p 到线段 ab 的最近距离
export function pointToSegment(p, a, b) {
  const abx = b.x - a.x, aby = b.y - a.y;
  const apx = p.x - a.x, apy = p.y - a.y;
  const ab2 = abx * abx + aby * aby;
  let t = ab2 < 1e-9 ? 0 : (apx * abx + apy * aby) / ab2;
  t = Math.max(0, Math.min(1, t));
  const cx = a.x + abx * t, cy = a.y + aby * t;
  return Math.hypot(p.x - cx, p.y - cy);
}

// 线段 (p0->p1) 与水平线 y=Y 的交点 x（若跨越），否则 null
export function crossHorizontal(p0, p1, Y) {
  if ((p0.y - Y) * (p1.y - Y) > 0) return null; // 同侧
  if (Math.abs(p1.y - p0.y) < 1e-9) return null;
  const t = (Y - p0.y) / (p1.y - p0.y);
  if (t < 0 || t > 1) return null;
  return p0.x + (p1.x - p0.x) * t;
}

// 线段 (p0->p1) 与竖直线 x=X 的交点 y（若跨越），否则 null
export function crossVertical(p0, p1, X) {
  if ((p0.x - X) * (p1.x - X) > 0) return null;
  if (Math.abs(p1.x - p0.x) < 1e-9) return null;
  const t = (X - p0.x) / (p1.x - p0.x);
  if (t < 0 || t > 1) return null;
  return p0.y + (p1.y - p0.y) * t;
}
