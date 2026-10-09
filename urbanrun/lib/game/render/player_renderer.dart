import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../model/geometry.dart';

class PlayerRenderer {
  const PlayerRenderer();

  /// Illustrated character height in pixels (foot-anchored on the ground).
  static const double _spriteHeight = 64;

  void render(
    Canvas canvas,
    Point2 screenPosition,
    Point2 facing,
    double animationTime,
    bool moving, {
    List<ui.Image> frames = const <ui.Image>[],
  }) {
    final center = Offset(screenPosition.x, screenPosition.y);
    if (frames.isNotEmpty) {
      // Cycle the walk frames while moving at ~8 fps; rest on the first frame.
      final index = moving
          ? (animationTime * 8).floor() % frames.length
          : 0;
      _renderSprite(canvas, center, facing, animationTime, moving, frames[index]);
      return;
    }
    final bob = moving ? math.sin(animationTime * 12) * 2.2 : 0.0;
    final swing = moving ? math.sin(animationTime * 12) * .25 : 0.0;
    final body = center.translate(0, -17 + bob);
    final legPaint = Paint()
      ..color = const Color(0xFF263B4D)
      ..strokeWidth = 4;
    canvas.drawLine(
      body.translate(-4, 11),
      body.translate(-5 + swing * 7, 23),
      legPaint,
    );
    canvas.drawLine(
      body.translate(4, 11),
      body.translate(5 - swing * 7, 23),
      legPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: center.translate(0, 28), width: 19, height: 7),
      Paint()..color = const Color(0xFF55D6E4).withValues(alpha: .3),
    );
    canvas.drawCircle(body, 9, Paint()..color = const Color(0xFFE3A07E));
    canvas.drawArc(
      Rect.fromCenter(center: body.translate(0, -4), width: 20, height: 12),
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = const Color(0xFF4D8ED0)
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke,
    );
    canvas.drawOval(
      Rect.fromCenter(center: body.translate(0, 12), width: 17, height: 20),
      Paint()..color = const Color(0xFF258F8B),
    );
    final direction = facing.length == 0
        ? const Point2(1, 0)
        : facing.normalized();
    final handOffset = Offset(direction.x * 8, direction.y * 4);
    canvas.drawCircle(
      body.translate(handOffset.dx, handOffset.dy + 5),
      3,
      Paint()..color = const Color(0xFFE3A07E),
    );
  }

  void _renderSprite(
    Canvas canvas,
    Offset center,
    Point2 facing,
    double animationTime,
    bool moving,
    ui.Image sprite,
  ) {
    // Teal ground ring under the player's feet.
    canvas.drawOval(
      Rect.fromCenter(center: center.translate(0, 3), width: 22, height: 8),
      Paint()..color = const Color(0xFF55D6E4).withValues(alpha: .35),
    );
    final bob = moving ? math.sin(animationTime * 12).abs() * 2.4 : 0.0;
    final scale = _spriteHeight / sprite.height;
    final w = sprite.width * scale;
    const h = _spriteHeight;
    // Face toward the on-screen horizontal of the movement; mirror the single
    // sprite for the opposite side.
    final faceLeft = (facing.x - facing.y) < 0;
    canvas.save();
    canvas.translate(center.dx, center.dy - bob);
    if (faceLeft) canvas.scale(-1, 1);
    canvas.drawImageRect(
      sprite,
      Rect.fromLTWH(0, 0, sprite.width.toDouble(), sprite.height.toDouble()),
      Rect.fromLTWH(-w / 2, -h + 4, w, h),
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }
}
