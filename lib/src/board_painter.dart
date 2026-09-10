/// Paints the board: exact checkerboard for any N (even or odd), square
/// annotations, pieces with their glyph tokens, and fx markers.
library;

import 'package:flutter/material.dart';

import 'config.dart';
import 'controller.dart';
import 'drawable.dart';
import 'geometry.dart';
import 'state.dart';

/// Layout of the playing area inside the canvas when coordinates render in
/// an outer margin: the board's top-left offset and its side length.
/// Shared by the painter and the widget's hit-testing.
(Offset, double) coordLayout(Size canvas, CoordinatesMode mode) {
  if (mode != CoordinatesMode.outside) return (Offset.zero, canvas.width);
  final pad = canvas.width * 0.06; // scales with the board, not the cell count
  return (Offset(pad, pad), canvas.width - pad);
}

const _roleGlyphs = <String, String>{
  'king': '♔',
  'queen': '♕',
  'rook': '♖',
  'bishop': '♗',
  'knight': '♘',
  'pawn': '♙',
};


class BoardPainter extends CustomPainter {
  BoardPainter({
    required this.controller,
    required this.config,
    required this.geometry,
    required this.state,
  });

  final BoardController controller;
  final BoardConfig config;
  final BoardGeometry geometry;
  final BoardState state;

  @override
  void paint(Canvas canvas, Size size) {
    final (origin, extent) = coordLayout(size, config.coordinates);
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    _paintBoard(canvas, Size(extent, extent));
    canvas.restore();
    _paintCoordinates(canvas, size, extent);
  }

  void _paintBoard(Canvas canvas, Size size) {
    final cell = size.width / geometry.size;

    // exact checkerboard — parity computed per square, any N
    final boardPaint = Paint();
    for (var rank = 0; rank < geometry.size; rank++) {
      for (var file = 0; file < geometry.size; file++) {
        final light = isLightSquare(file, rank);
        boardPaint.color = light ? config.light : config.dark;
        final (x, y) = geometry.pointOfPosition(file, rank, size.width, flip: config.flip);
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), boardPaint);
      }
    }

    // square annotations (host styles map class names to decorations)
    for (final entry in state.squares.entries) {
      final pos = geometry.parseKey(entry.key);
      if (pos == null) continue;
      final (x, y) = geometry.pointOfPosition(pos.$1, pos.$2, size.width, flip: config.flip);
      _paintSquareClasses(canvas, entry.value, Rect.fromLTWH(x, y, cell, cell));
    }

    // back-layer markers
    _paintMarkers(canvas, size, cell, front: false);

    // pieces
    for (final entry in state.pieces.entries) {
      final (fx, fy) = controller.pieceOffset(entry.key, flip: config.flip);
      _paintPiece(canvas, entry.value, Offset(fx * cell, fy * cell), cell);
    }

    // front-layer markers
    _paintMarkers(canvas, size, cell, front: true);

    // drawings float above everything, like the web engine's svg layer
    for (final shape in controller.drawable.shapes) {
      _paintShape(canvas, cell, shape, live: false);
    }
    final live = controller.drawable.current;
    if (live != null) _paintShape(canvas, cell, live, live: true);

    if (config.coordinates == CoordinatesMode.inside) {
      _paintInsideCoordinates(canvas, size);
    }
  }

  /// One text label, centered in [rect].
  void _paintLabel(Canvas canvas, String text, Rect rect, double fontSize, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: color,
          fontFamily: config.pieceFontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
  }

  Color _coordColor(bool onLight) => onLight
      ? const Color(0x9E1E143C) // dark ink on light squares
      : const Color(0xB8FFFDF6); // cream on dark squares

  /// Rank labels down the left squares, file labels along the bottom ones —
  /// each colored against the parity of the square it sits on (board-local
  /// coordinates; call inside the translated board pass).
  void _paintInsideCoordinates(Canvas canvas, Size board) {
    final n = geometry.size;
    final cell = board.width / n;
    final font = (cell * 0.32).clamp(8.0, 15.0);
    for (var row = 0; row < n; row++) {
      final rank = config.flip ? row + 1 : n - row;
      final file = config.flip ? n - 1 : 0;
      final rect = Rect.fromLTWH(0, row * cell, cell * 0.5, cell * 0.5);
      _paintLabel(canvas, '$rank', rect, font, _coordColor(isLightSquare(file, rank - 1)));
    }
    for (var column = 0; column < n; column++) {
      final file = config.flip ? n - 1 - column : column;
      final rank1 = config.flip ? n : 1;
      final rect = Rect.fromLTWH(
        column * cell + cell * 0.5,
        board.height - cell * 0.5,
        cell * 0.5,
        cell * 0.5,
      );
      _paintLabel(
        canvas,
        String.fromCharCode(97 + file),
        rect,
        font,
        _coordColor(isLightSquare(file, rank1 - 1)),
      );
    }
  }

  /// Outside labels in the margin: ranks down the left strip, files along
  /// the bottom strip (absolute canvas coordinates).
  void _paintCoordinates(Canvas canvas, Size canvasSize, double extent) {
    if (config.coordinates != CoordinatesMode.outside) return;
    final n = geometry.size;
    final (origin, boardExtent) = coordLayout(canvasSize, config.coordinates);
    final cell = boardExtent / n;
    final pad = origin.dx; // the margin width
    final font = (cell * 0.4).clamp(9.0, 16.0);
    final color = const Color(0x8C1E143C);
    for (var row = 0; row < n; row++) {
      final rank = config.flip ? row + 1 : n - row;
      _paintLabel(
        canvas,
        '$rank',
        Rect.fromLTWH(0, origin.dy + row * cell, pad, cell),
        font,
        color,
      );
    }
    for (var column = 0; column < n; column++) {
      final file = config.flip ? n - 1 - column : column;
      _paintLabel(
        canvas,
        String.fromCharCode(97 + file),
        Rect.fromLTWH(origin.dx + column * cell, canvasSize.height - pad, cell, pad),
        font,
        color,
      );
    }
  }

  /// Top-left of a square in pixels, matching geometry + flip.
  Offset _squareTopLeft(String key, double pixels) {
    final pos = geometry.parseKey(key);
    if (pos == null) return Offset.zero;
    final (x, y) = geometry.pointOfPosition(pos.$1, pos.$2, pixels, flip: config.flip);
    return Offset(x, y);
  }

  void _paintShape(Canvas canvas, double cell, Shape shape, {required bool live}) {
    final brush = controller.drawable.brushOf(shape.brush);
    final color = brush.color.withValues(alpha: brush.opacity * (live ? 0.55 : 1.0));
    if (shape is CircleShape) {
      final center = _squareTopLeft(shape.square, cell * geometry.size) + Offset(cell / 2, cell / 2);
      canvas.drawCircle(
        center,
        cell * 0.45,
        Paint()..color = brush.color.withValues(alpha: 0.14 * brush.opacity),
      );
      canvas.drawCircle(
        center,
        cell * 0.45,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.09 * brush.width,
      );
      return;
    }
    if (shape is! ArrowShape) return;
    final cellPixels = cell * geometry.size;
    final from = _squareTopLeft(shape.from, cellPixels) + Offset(cell / 2, cell / 2);
    final to = _squareTopLeft(shape.to, cellPixels) + Offset(cell / 2, cell / 2);
    final delta = to - from;
    final length = delta.distance;
    if (length <= 0) return;
    final unit = delta / length;
    const head = 0.34; // arrowhead length in square units
    const half = 0.15; // arrowhead half width in square units
    final shaftEnd = from + unit * (length - head * cell > 0.18 * cell ? length - head * cell : 0.18 * cell);
    canvas.drawLine(
      from,
      shaftEnd,
      Paint()
        ..color = color
        ..strokeWidth = cell * 0.18 * brush.width
        ..strokeCap = StrokeCap.round,
    );
    final headBase = to - unit * head * cell;
    final perpendicular = Offset(-unit.dy, unit.dx);
    final arrowHead = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(headBase.dx + perpendicular.dx * half * cell, headBase.dy + perpendicular.dy * half * cell)
      ..lineTo(headBase.dx - perpendicular.dx * half * cell, headBase.dy - perpendicular.dy * half * cell)
      ..close();
    canvas.drawPath(arrowHead, Paint()..color = color);
  }

  void _paintSquareClasses(Canvas canvas, Set<String> classes, Rect rect) {
    final paint = Paint();
    for (final cls in classes) {
      switch (cls) {
        case 'selected':
          paint.color = Colors.amber.withValues(alpha: 0.45);
          canvas.drawRect(rect.deflate(1), paint);
        case 'last-move':
          paint.color = Colors.amber.withValues(alpha: 0.25);
          canvas.drawRect(rect, paint);
        case 'dest':
        case 'dice':
          paint.color = Colors.amber.withValues(alpha: 0.9);
          canvas.drawCircle(rect.center, rect.width * 0.16, paint);
      }
    }
  }

  void _paintPiece(Canvas canvas, Piece piece, Offset topLeft, double cell) {
    // Host-injected raster art wins; glyph tokens are the fallback.
    final art = config.pieceArt?['${piece.color}-${piece.role}'];
    if (art != null) {
      final dst = Rect.fromLTWH(topLeft.dx, topLeft.dy, cell, cell);
      canvas.drawImageRect(
        art,
        Rect.fromLTWH(0, 0, art.width.toDouble(), art.height.toDouble()),
        dst,
        Paint()..filterQuality = FilterQuality.medium,
      );
      return;
    }
    final rect = Rect.fromLTWH(topLeft.dx + cell * 0.08, topLeft.dy + cell * 0.08, cell * 0.84, cell * 0.84);
    final darkPiece = piece.color.toLowerCase() == 'black';
    final fill = Paint()..color = darkPiece ? const Color(0xFF33234F) : const Color(0xFFFFFDF6);
    final stroke = Paint()
      ..color = darkPiece ? const Color(0xFFFFFDF6) : const Color(0xFF33234F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.04;
    canvas.drawCircle(rect.center, rect.width * 0.46, fill);
    canvas.drawCircle(rect.center, rect.width * 0.46, stroke);

    final glyph = _roleGlyphs[piece.role] ??
        (piece.role.isEmpty ? '?' : piece.role.substring(0, 1).toUpperCase());
    final tp = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(
          fontSize: cell * 0.5,
          color: darkPiece ? const Color(0xFFFFFDF6) : const Color(0xFF33234F),
          fontFamily: config.pieceFontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
  }

  void _paintMarkers(Canvas canvas, Size size, double cell, {required bool front}) {
    final markers = controller.fx.markers.values.where((m) => m.front == front);
    for (final marker in markers) {
      final pos = geometry.parseKey(marker.square);
      if (pos == null) continue;
      final (x, y) = geometry.pointOfPosition(pos.$1, pos.$2, size.width, flip: config.flip);
      final tp = TextPainter(
        text: TextSpan(
          text: marker.content,
          style: TextStyle(fontSize: cell * 0.55),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + (cell - tp.width) / 2, y + (cell - tp.height) / 2));
    }
  }

  @override
  bool shouldRepaint(BoardPainter oldDelegate) => true;
}
