/// Paints the board: exact checkerboard for any N (even or odd), square
/// annotations, pieces with their glyph tokens, and fx markers.
library;

import 'package:flutter/material.dart';

import 'config.dart';
import 'controller.dart';
import 'geometry.dart';
import 'state.dart';

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
