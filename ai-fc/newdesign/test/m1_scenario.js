// test/m1_scenario.js — M1 垂直切片的 headless 验收
// 运行：node test/m1_scenario.js  (或 npm test)
//
// 验证核心范式闭环：
//   开球(裁判判定→#6感知→就位→开球) → InPlay
//   → 球出边线(裁判判定界外球归属) → 指派最近 away 球员发球
//   → 该球员感知事件、走到球位、就位 → 掷界外球 → 恢复 InPlay
// 全程无脚本特判；下面仅在 InPlay 后"人为把球推向边线"以确定性地触发死球路径。

import { bootstrap } from '../src/sim/bootstrap.js';

const boot = bootstrap({ seed: 20260707 });
const { world, loop, bus, clock } = boot;

function runUntil(pred, maxFrames) {
  for (let i = 0; i < maxFrames; i++) {
    loop.step();
    if (pred()) return true;
  }
  return false;
}

// —— 阶段1：等待开球完成进入 InPlay ——
const kickoffDone = runUntil(() => world.phase.main === 'InPlay', 3000);

// —— 阶段2：制造边线出界（最后触球=home → 界外球判给 away）——
if (kickoffDone) {
  world.ball.ownerId = null;
  world.ball.pos = { x: 52, y: 6 };
  world.ball.prevPos = { x: 52, y: 6 };
  world.ball.vel = { x: 0, y: -30 }; // 朝 y=0 之外
  world.ball.lastTouch = { playerId: 'home-8', teamId: 'home', frame: clock.frame };
}

// —— 阶段3：跑完整个界外球流程，直到再次 InPlay ——
let outSeen = false;
let backInPlay = false;
runUntil(() => {
  const hasOut = bus.find('BallOutOfPlay').length > 0;
  if (hasOut) outSeen = true;
  // 出界之后再次回到 InPlay
  if (outSeen && world.phase.main === 'InPlay') { backInPlay = true; return true; }
  return false;
}, 8000);

// ——— 断言 ———
const log = bus.log;

function assertSubsequence(steps) {
  let i = 0;
  const matched = [];
  for (const e of log) {
    const step = steps[i];
    if (!step) break;
    if (e.type === step.type && (!step.p || step.p(e))) {
      matched.push(e);
      i += 1;
    }
  }
  if (i < steps.length) {
    console.error('\n✗ 事件子序列未按顺序全部匹配。已匹配:', i, '/', steps.length);
    console.error('  下一个期望:', JSON.stringify(steps[i].type));
    return false;
  }
  return true;
}

const steps = [
  { type: 'MatchStarted' },
  { type: 'KickoffAwarded', p: (e) => e.teamId === 'home' },
  { type: 'RestartAssigned', p: (e) => e.restartType === 'kickoff' && e.playerId === 'home-6' },
  { type: 'RestartReady', p: (e) => e.playerId === 'home-6' },
  { type: 'PhaseChanged', p: (e) => e.to && e.to.main === 'InPlay' },
  { type: 'BallOutOfPlay', p: (e) => e.lastTouchTeamId === 'home' },
  { type: 'ThrowInAwarded', p: (e) => e.teamId === 'away' },
  { type: 'RestartAssigned', p: (e) => e.restartType === 'throwIn' && String(e.playerId).startsWith('away-') },
  { type: 'RestartReady', p: (e) => String(e.playerId).startsWith('away-') },
  { type: 'PhaseChanged', p: (e) => e.to && e.to.main === 'InPlay' },
];

const checks = [];
checks.push(['开球在 3000 帧内完成并进入 InPlay', kickoffDone]);
checks.push(['检测到界外球', outSeen]);
checks.push(['界外球流程后恢复 InPlay', backInPlay]);
checks.push(['出现过控球权变更(→home)', bus.find('PossessionChanged').some((e) => e.toTeamId === 'home')]);
checks.push(['完整事件子序列按顺序成立', assertSubsequence(steps)]);

// 每帧决策数据完整保留校验：任取一名球员，其 history 应逐帧连续、无缺帧
const sample = boot.agents.find((a) => a.id === 'home-6');
const h = sample ? sample.history : [];
const contiguous = h.length > 0 && h.every((r, i) => i === 0 || r.frame === h[i - 1].frame + 1);
checks.push([`每帧决策数据逐帧保留(home-6 共 ${h.length} 帧, =总帧数 ${clock.frame})`,
  h.length === clock.frame && contiguous]);
checks.push(['决策记录含触发来源与选中动作',
  h.length > 0 && h[0].triggeredBy != null && h[0].chosen != null]);

let ok = true;
console.log('\n=== M1 垂直切片验收 ===');
for (const [name, pass] of checks) {
  console.log(`${pass ? '✓' : '✗'} ${name}`);
  if (!pass) ok = false;
}

// 事件日志摘要
console.log('\n--- 事件日志（关键类型）---');
const keyTypes = new Set([
  'MatchStarted', 'KickoffAwarded', 'RestartAssigned', 'RestartReady',
  'PhaseChanged', 'PossessionChanged', 'BallOutOfPlay', 'ThrowInAwarded',
]);
for (const e of log) {
  if (!keyTypes.has(e.type)) continue;
  const extra = e.playerId ? `player=${e.playerId}` : (e.teamId ? `team=${e.teamId}` : (e.to ? `→${e.to.main}${e.to.sub ? ':' + e.to.sub : ''}` : ''));
  console.log(`  [${(e.timeMs / 1000).toFixed(1)}s f${e.frame}] ${e.type} ${extra}${e.restartType ? ' ' + e.restartType : ''}`);
}

console.log(ok ? '\n✅ M1 验收通过' : '\n❌ M1 验收未通过');
process.exit(ok ? 0 : 1);
