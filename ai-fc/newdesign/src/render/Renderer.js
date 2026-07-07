// render/Renderer.js — Canvas 绘制球场/球员/球/意图（纯呈现，无决策）

export class Renderer {
  constructor(canvas, field) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.field = field;
    this.margin = 24;
    this._resize();
  }

  _resize() {
    const { field, canvas, margin } = this;
    this.scale = Math.min(
      (canvas.width - margin * 2) / field.length,
      (canvas.height - margin * 2) / field.width,
    );
  }

  toPx(p) {
    return { x: this.margin + p.x * this.scale, y: this.margin + p.y * this.scale };
  }

  draw(world) {
    const { ctx, canvas, field, scale, margin } = this;
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    // 草坪
    ctx.fillStyle = '#2e7d32';
    ctx.fillRect(margin, margin, field.length * scale, field.width * scale);

    // 线
    ctx.strokeStyle = 'rgba(255,255,255,0.8)';
    ctx.lineWidth = 2;
    ctx.strokeRect(margin, margin, field.length * scale, field.width * scale);
    // 中线
    const midX = margin + (field.length / 2) * scale;
    ctx.beginPath();
    ctx.moveTo(midX, margin);
    ctx.lineTo(midX, margin + field.width * scale);
    ctx.stroke();
    // 中圈
    const c = this.toPx(field.center);
    ctx.beginPath();
    ctx.arc(c.x, c.y, field.centerCircleRadius * scale, 0, Math.PI * 2);
    ctx.stroke();

    // 球员
    for (const p of world.players) {
      const px = this.toPx(p.pos);
      ctx.beginPath();
      ctx.arc(px.x, px.y, 7, 0, Math.PI * 2);
      ctx.fillStyle = p.teamId === 'home' ? '#e53935' : '#1e88e5';
      ctx.fill();
      if (p.id === world.phase.takerId) {
        ctx.strokeStyle = '#ffeb3b'; ctx.lineWidth = 3; ctx.stroke();
      }
      ctx.fillStyle = '#fff';
      ctx.font = '9px sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText(String(p.number), px.x, px.y + 3);
    }

    // 球
    const b = this.toPx(world.ball.pos);
    ctx.beginPath();
    ctx.arc(b.x, b.y, 4, 0, Math.PI * 2);
    ctx.fillStyle = '#fafafa';
    ctx.fill();
    ctx.strokeStyle = '#000'; ctx.lineWidth = 1; ctx.stroke();
  }
}
