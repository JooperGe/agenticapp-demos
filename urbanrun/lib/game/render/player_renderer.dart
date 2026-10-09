import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/geometry.dart';

class PlayerRenderer {
  const PlayerRenderer();

  void render(
    Canvas canvas,
    Point2 screenPosition,
    Point2 facing,
    double animationTime,
    bool moving,
  ) {
    final center = Offset(screenPosition.x, screenPosition.y);
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
}
