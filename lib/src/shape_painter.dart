/// Arrows and circles, shared by the engine's painter and the chess board.
library;

import 'package:flutter/painting.dart';

import 'drawable.dart';

/// Paints one [shape] in [brush] (the shape's own colour wins when set).
///
/// [centerOf] maps a square key to the centre of that square in the
/// canvas; [cell] is the side of one square. A [live] shape (the one being
/// drawn) is fainter.
void paintBoardShape(
  Canvas canvas, {
  required Shape shape,
  required Brush brush,
  required Offset? Function(String square) centerOf,
  required double cell,
  bool live = false,
}) {
  final own = shape.color;
  final base = own ?? brush.color;
  final opacity = own == null ? brush.opacity : 1.0;
  final color = base.withValues(alpha: base.a * opacity * (live ? 0.55 : 1.0));
  final width = brush.width * shape.scale;
  if (shape is CircleShape) {
    final center = centerOf(shape.square);
    if (center == null) return;
    canvas.drawCircle(
      center,
      cell * 0.45,
      Paint()..color = base.withValues(alpha: base.a * 0.14 * opacity),
    );
    canvas.drawCircle(
      center,
      cell * 0.45,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.09 * width,
    );
    return;
  }
  if (shape is! ArrowShape) return;
  final from = centerOf(shape.from);
  final to = centerOf(shape.to);
  if (from == null || to == null) return;
  final delta = to - from;
  final length = delta.distance;
  if (length <= 0) return;
  final unit = delta / length;
  const head = 0.34; // arrowhead length in square units
  const half = 0.15; // arrowhead half width in square units
  final shaft = length - head * cell > 0.18 * cell ? length - head * cell : 0.18 * cell;
  canvas.drawLine(
    from,
    from + unit * shaft,
    Paint()
      ..color = color
      ..strokeWidth = cell * 0.18 * width
      ..strokeCap = StrokeCap.round,
  );
  final headBase = to - unit * head * cell;
  final side = Offset(-unit.dy, unit.dx) * (half * cell * (0.6 + 0.4 * width));
  final arrowHead = Path()
    ..moveTo(to.dx, to.dy)
    ..lineTo(headBase.dx + side.dx, headBase.dy + side.dy)
    ..lineTo(headBase.dx - side.dx, headBase.dy - side.dy)
    ..close();
  canvas.drawPath(arrowHead, Paint()..color = color);
}
