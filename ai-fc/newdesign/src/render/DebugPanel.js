// render/DebugPanel.js — 事件时间线 + 选中球员的效用打分可视化
// 见 03-player-agent.md §4 / 04-data-schemas.md §6

export class DebugPanel {
  constructor({ statusEl, eventsEl, traceEl, bus }) {
    this.statusEl = statusEl;
    this.eventsEl = eventsEl;
    this.traceEl = traceEl;
    this.bus = bus;
    this._lastLogLen = 0;
  }

  update(loop) {
    const { world, clock } = loop;

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

    // 选中球员的决策打分
    if (this.traceEl && loop.selectedPlayerId) {
      const agent = loop.agentOf(loop.selectedPlayerId);
      const t = agent && agent.lastTrace;
      if (t) {
        const rows = t.candidates
          .slice()
          .sort((a, b) => b.score - a.score)
          .map((c) => {
            const chosen = c.action === t.chosen.action ? '► ' : '  ';
            return `${chosen}${c.action.padEnd(16)} ${bar(c.score)} ${c.score.toFixed(2)}`;
          })
          .join('\n');
        this.traceEl.textContent =
          `球员 ${t.playerId}  帧 ${t.frame}  触发: ${t.triggeredBy}\n` +
          `选中: ${t.chosen.action}\n\n${rows}`;
      }
    }
  }
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
