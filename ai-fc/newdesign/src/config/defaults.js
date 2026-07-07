// config/defaults.js — M1 只读配置（球场/规则/阵容）
// 说明：M1 用 JS 模块承载配置（而非 fetch JSON），以避免浏览器 file:// 的 CORS/异步问题；
// 后续可无缝替换为从 *.json 加载。见 04-data-schemas.md §5

export const FIELD = {
  length: 105, width: 68,
  centerCircleRadius: 9.15,
  penaltyAreaLength: 16.5, penaltyAreaWidth: 40.32,
  goalWidth: 7.32, goalPostRadius: 0.06,
};

export const RULES = {
  lineTolerance: 0.11,
  kickoffKeepOutRadius: 9.15,
  restartReadyRadius: 0.8,
  restartReadySpeedMax: 0.4,
  throwInTakerExcludeGK: true,
  kickoffTakerNumber: 6,
};

// home 阵型（4-3-3），home 防守 x=0 / 进攻 +x；均在本方半场（x < 52.5）以符合开球布局
const HOME_ANCHORS = [
  { number: 1, role: 'GK', anchor: { x: 5, y: 34 } },
  { number: 2, role: 'RB', anchor: { x: 16, y: 58 } },
  { number: 3, role: 'LB', anchor: { x: 16, y: 10 } },
  { number: 4, role: 'CB', anchor: { x: 18, y: 46 } },
  { number: 5, role: 'CB', anchor: { x: 18, y: 22 } },
  { number: 6, role: 'CM', anchor: { x: 45, y: 34 } }, // 开球手：靠近中圈
  { number: 8, role: 'CM', anchor: { x: 34, y: 46 } },
  { number: 10, role: 'CM', anchor: { x: 34, y: 22 } },
  { number: 7, role: 'RW', anchor: { x: 44, y: 58 } },
  { number: 11, role: 'LW', anchor: { x: 44, y: 10 } },
  { number: 9, role: 'ST', anchor: { x: 49, y: 40 } },
];

// away 由 home 镜像：x' = length - x（away 防守 x=length / 进攻 -x）
function mirror(anchor) {
  return { x: FIELD.length - anchor.x, y: anchor.y };
}

export function buildRoster() {
  const home = HOME_ANCHORS.map((s) => ({
    id: `home-${s.number}`, teamId: 'home', number: s.number, role: s.role, anchor: { ...s.anchor },
  }));
  const away = HOME_ANCHORS.map((s) => ({
    id: `away-${s.number}`, teamId: 'away', number: s.number, role: s.role, anchor: mirror(s.anchor),
  }));
  return { home, away, all: [...home, ...away] };
}
