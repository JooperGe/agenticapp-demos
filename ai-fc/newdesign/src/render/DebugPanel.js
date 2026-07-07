// render/DebugPanel.js — 事件时间线 + 选中球员的效用打分 + 每帧决策时间线
// 见 03-player-agent.md §4 / 04-data-schemas.md §6

export class DebugPanel {
  constructor({ statusEl, eventsEl, traceEl, timelineEl = null, timelineCountEl = null, bus, maxTimelineRows = 800 }) {
    this.statusEl = statusEl;
    this.eventsEl = eventsEl;
    this.traceEl = traceEl;            // 最近一次决策的完整打分（柱状）
    this.timelineEl = timelineEl;      // 每帧决策时间线（完整保留）
    this.timelineCountEl = timelineCountEl;
    this.bus = bus;
    this.maxTimelineRows = maxTimelineRows; // 仅限制 DOM 渲染条数；数据在 agent.history 中完整保留
    this._lastLogLen = 0;
    this._timelinePlayer = null;
    this._timelineRendered = 0;
  }

  update(loop) {
    const { world, clock } = loop;

    // 状态栏
    if (this.statusEl) {
      const ph = world.phase;
      this.statusEl.textContent =
        `${clock.clockLabel}  |  阶段: ${ph.main}${ph.sub ? ':' + ph.sub : ''}` +
        `  |  比分 ${world.score.home}-${world.score.away}` +
        `  |  控球: ${world.possession.teamId ?? '-'}` +
        (ph.takerId ? `  |  发球者: ${ph.takerId}${ph.restartReady ? '(就位)' : ''}` : '');
    }

    // 事件时间线（增量追加）
    if (this.eventsEl && this.bus) {
      const log = this.bus.log;
      for (let i = this._lastLogLen; i < log.length; i++) {
        const e = log[i];
        const line = document.createElement('div');
        line.textContent = `[${fmt(e.timeMs)}] ${e.type} ${summarize(e)}`;
        this.eventsEl.appendChild(line);
      }
      this._lastLogLen = log.length;
      this.eventsEl.scrollTop = this.eventsEl.scrollHeight;
    }

    const agent = loop.selectedPlayerId ? loop.agentOf(loop.selectedPlayerId) : null;

    // 最近一次"真正决策"的完整打分（柱状）
    if (this.traceEl && agent && agent.lastTrace) {
      const t = agent.lastTrace;
      const rows = t.candidates
        .slice()
        .sort((a, b) => b.score - a.score)
        .map((c) => {
          const chosen = c.action === t.chosen.action ? '► ' : '  ';
          return `${chosen}${c.action.padEnd(16)} ${bar(c.score)} ${c.score.toFixed(2)}`;
        })
        .join('\n');
      this.traceEl.textContent =
        `球员 ${t.playerId}  帧 ${t.frame}  触发: ${t.triggeredBy}  阶段: ${t.phase || '-'}\n` +
        `选中: ${t.chosen.action}\n\n${rows}`;
    }

    // 每帧决策时间线（完整保留，增量渲染）
    if (this.timelineEl && agent) {
      if (this._timelinePlayer !== agent.id) {
        this._timelinePlayer = agent.id;
        this._timelineRendered = 0;
        this.timelineEl.innerHTML = '';
      }
      const hist = agent.history;
      for (let i = this._timelineRendered; i < hist.length; i++) {
        this.timelineEl.appendChild(renderTimelineRow(hist[i]));
        while (this.timelineEl.childElementCount > this.maxTimelineRows) {
          this.timelineEl.removeChild(this.timelineEl.firstChild);
        }
      }
      this._timelineRendered = hist.length;
      this.timelineEl.scrollTop = this.timelineEl.scrollHeight;
      if (this.timelineCountEl) {
        const shown = Math.min(hist.length, this.maxTimelineRows);
        this.timelineCountEl.textContent = `已保留 ${hist.length} 帧（显示最近 ${shown}）`;
      }
    }
  }
}

const TRIGGER_ABBR = { interrupt: 'INT', backgroundTick: 'bg', repeat: 'rep' };
const TRIGGER_COLOR = { interrupt: '#ff7043', backgroundTick: '#90caf9', repeat: '#616161' };

function renderTimelineRow(rec) {
  const div = document.createElement('div');
  div.style.color = TRIGGER_COLOR[rec.triggeredBy] || '#ccc';
  const tag = (TRIGGER_ABBR[rec.triggeredBy] || rec.triggeredBy).padEnd(3);
  let text = `f${String(rec.frame).padStart(5)} ${tag} ► ${rec.chosen.action}`;
  if (rec.candidates && rec.candidates.length > 0) {
    const top = rec.candidates
      .slice()
      .sort((a, b) => b.score - a.score)
      .slice(0, 5)
      .map((c) => `${c.action}:${c.score.toFixed(2)}`)
      .join('  ');
    text += `   [${top}]`;
  }
  div.textContent = text;
  return div;
}

function fmt(ms) {
  const s = Math.floor(ms / 1000);
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
}

function bar(score) {
  const n = Math.max(0, Math.min(20, Math.round(score * 10)));
  return '█'.repeat(n).padEnd(20, '·');
}

function summarize(e) {
  if (e.playerId) return `player=${e.playerId}${e.restartType ? ' ' + e.restartType : ''}`;
  if (e.teamId) return `team=${e.teamId}`;
  if (e.toTeamId !== undefined) return `→${e.toTeamId} (${e.playerId})`;
  return '';
}
