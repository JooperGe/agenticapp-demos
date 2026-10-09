import 'package:flutter/material.dart';

import '../model/geometry.dart';

class InteractionRenderer {
  const InteractionRenderer();

  void render(Canvas canvas, Point2 screenPosition, String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFF102127),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = Rect.fromLTWH(
      screenPosition.x - painter.width / 2 - 10,
      screenPosition.y - 62,
      painter.width + 20,
      painter.height + 10,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(7)),
      Paint()..color = const Color(0xFF65D5B3),
    );
    painter.paint(canvas, Offset(rect.left + 10, rect.top + 5));
  }
}
