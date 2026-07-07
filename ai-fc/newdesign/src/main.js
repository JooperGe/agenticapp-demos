// main.js — 浏览器入口：装配渲染 + 调试面板 + 交互
import { bootstrap } from './sim/bootstrap.js';
import { Renderer } from './render/Renderer.js';
import { DebugPanel } from './render/DebugPanel.js';

const canvas = document.getElementById('pitch');

// 先建裁判/世界，再把 renderer/debug 注入 loop
const boot = bootstrap({ seed: 20260707 });
const renderer = new Renderer(canvas, boot.world.field);
const debug = new DebugPanel({
  statusEl: document.getElementById('status'),
  eventsEl: document.getElementById('events'),
  traceEl: document.getElementById('trace'),
  bus: boot.bus,
});
boot.loop.renderer = renderer;
boot.loop.debug = debug;

// 首帧绘制
renderer.draw(boot.world);

// 交互：开始/暂停
document.getElementById('btnStart').addEventListener('click', () => boot.loop.start());
document.getElementById('btnPause').addEventListener('click', () => boot.loop.stop());
document.getElementById('btnStep').addEventListener('click', () => boot.loop.step());

// 点击球员选中，查看其决策打分
canvas.addEventListener('click', (ev) => {
  const rect = canvas.getBoundingClientRect();
  const mx = ev.clientX - rect.left;
  const my = ev.clientY - rect.top;
  let best = null; let bd = Infinity;
  for (const p of boot.world.players) {
    const px = renderer.toPx(p.pos);
    const d = Math.hypot(px.x - mx, px.y - my);
    if (d < bd) { bd = d; best = p; }
  }
  if (best && bd < 20) {
    boot.loop.selectedPlayerId = best.id;
    document.getElementById('selected').textContent = `已选中: ${best.id} (#${best.number} ${best.role})`;
  }
});

window.__aifc = boot; // 便于控制台调试
