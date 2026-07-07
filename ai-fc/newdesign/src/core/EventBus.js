// core/EventBus.js — 事件总线：裁判发布，帧末投递到各球员的中断队列
// 见 04-data-schemas.md §2

export class EventBus {
  constructor() {
    this.frameBuffer = []; // 本帧新发布、尚未投递的事件
    this.log = [];         // 全量事件日志（调试/回放/测试）
    this.queues = new Map(); // playerId -> 待该球员消费的事件数组
  }

  registerPlayer(playerId) {
    if (!this.queues.has(playerId)) this.queues.set(playerId, []);
  }

  // 裁判调用：发布一个事件（带上帧号/时间由调用方补齐）
  publish(event) {
    this.frameBuffer.push(event);
    this.log.push(event);
    return event;
  }

  // 帧末：把本帧事件广播投递到所有球员队列（M1 全体可见）
  flush() {
    if (this.frameBuffer.length === 0) return;
    for (const q of this.queues.values()) {
      for (const e of this.frameBuffer) q.push(e);
    }
    this.frameBuffer.length = 0;
  }

  // 球员消费自己的事件队列（取出并清空）
  drain(playerId) {
    const q = this.queues.get(playerId);
    if (!q || q.length === 0) return [];
    const out = q.slice();
    q.length = 0;
    return out;
  }

  // 便捷：按类型过滤日志
  find(type) {
    return this.log.filter((e) => e.type === type);
  }
}
