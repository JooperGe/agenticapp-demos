// agent/Blackboard.js — 球员的记忆/信念（跨帧持久）
// 见 03-player-agent.md §3

import { EventType, PhaseMain, RestartType } from '../core/enums.js';

export class Blackboard {
  constructor(playerId) {
    this.playerId = playerId;
    this.assignment = { isTaker: false, restartType: null, spot: null };
    this.markTarget = null;
    this.lastEventType = null;
    this.interrupted = false; // 本帧是否收到需立即重决策的事件
  }

  // 处理本帧到达的事件，更新信念；返回是否需要中断式立即决策
  handleEvents(events) {
    this.interrupted = false;
    for (const e of events) {
      this.lastEventType = e.type;
      switch (e.type) {
        case EventType.RestartAssigned:
          if (e.playerId === this.playerId) {
            this.assignment = { isTaker: true, restartType: e.restartType, spot: { ...e.spot } };
          } else if (this.assignment.isTaker) {
            this.assignment = { isTaker: false, restartType: null, spot: null };
          }
          this.interrupted = true;
          break;
        case EventType.PhaseChanged:
          if (e.to && e.to.main === PhaseMain.IN_PLAY) {
            this.assignment = { isTaker: false, restartType: null, spot: null };
          }
          this.interrupted = true;
          break;
        case EventType.RestartReady:
        case EventType.PossessionChanged:
        case EventType.BallOutOfPlay:
        case EventType.KickoffAwarded:
        case EventType.GoalScored:
          this.interrupted = true;
          break;
        default:
          break;
      }
    }
    return this.interrupted;
  }

  // 发球者完成踢球后清空指派
  clearAssignmentIfKicked(intent) {
    if (this.assignment.isTaker && intent && intent.type === 'KickIntent') {
      this.assignment = { isTaker: false, restartType: null, spot: null };
    }
  }
}
