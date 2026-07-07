// sim/MatchLoop.js — 帧流水线编排器（本身不含任何规则/策略）
// 见 01-architecture.md §2

export class MatchLoop {
  constructor({ world, clock, bus, referee, agents, physics, resolver, renderer = null, debug = null }) {
    this.world = world;
    this.clock = clock;
    this.bus = bus;
    this.referee = referee;
    this.agents = agents;
    this.physics = physics;
    this.resolver = resolver;
    this.renderer = renderer;
    this.debug = debug;
    this._raf = null;
    this.running = false;
    this.selectedPlayerId = null; // 调试：当前选中球员
  }

  // 单帧：严格顺序 ① 时钟 → ② 感知+决策 → ④ 仲裁 → ⑤ 物理 → ⑥ 裁判 → ⑦ 投递 → ⑧ 渲染
  step() {
    const dt = this.clock.advance();

    // ②③ 球员产出意图（感知在 agent.tick 内部完成）
    const intents = this.agents.map((a) => a.tick(this.world, this.bus, this.clock));

    // ④ 意图合法性预检 + 冲突仲裁
    const resolved = this.resolver.resolve(this.world, intents);

    // ⑤ 物理执行
    this.physics.integrate(this.world, resolved, dt, this.clock.frame);

    // ⑥ 裁判观察并发布事件
    this.referee.observe(this.world, this.bus, this.clock);

    // ⑦ 事件投递到各球员中断队列（下一帧生效）
    this.bus.flush();

    // ⑧ 渲染/调试（headless 时为 null）
    if (this.renderer) this.renderer.draw(this.world, this);
    if (this.debug) this.debug.update(this);
  }

  // headless：运行 n 帧
  run(maxFrames) {
    for (let i = 0; i < maxFrames; i++) this.step();
  }

  // 浏览器：requestAnimationFrame 驱动
  start() {
    if (this.running) return;
    this.running = true;
    const tick = () => {
      if (!this.running) return;
      this.step();
      this._raf = requestAnimationFrame(tick);
    };
    this._raf = requestAnimationFrame(tick);
  }

  stop() {
    this.running = false;
    if (this._raf != null) cancelAnimationFrame(this._raf);
  }

  agentOf(playerId) {
    return this.agents.find((a) => a.id === playerId) || null;
  }
}
