/// The value types the [ChessBoard] widget takes and reports.
library;

import 'package:flutter/widgets.dart';

import 'drawable.dart';
import 'state.dart';

/// A move the user asked for: the board never checks rules, the host does.
@immutable
class BoardMove {
  const BoardMove({
    required this.from,
    required this.to,
    this.premove = false,
    this.dragged = false,
  });

  final String from;
  final String to;

  /// Made from the host's `premoveDests` (not the side to move yet).
  final bool premove;

  /// Made by dragging the piece (false: tap, then tap the destination).
  final bool dragged;

  @override
  bool operator ==(Object other) =>
      other is BoardMove &&
      other.from == from &&
      other.to == to &&
      other.premove == premove &&
      other.dragged == dragged;

  @override
  int get hashCode => Object.hash(from, to, premove, dragged);

  @override
  String toString() => 'BoardMove($from$to${premove ? ' premove' : ''}${dragged ? ' dragged' : ''})';
}

/// A small numbered or lettered badge in the top-right corner of a square
/// (e.g. the order of queued premoves).
@immutable
class SquareBadge {
  const SquareBadge(this.text, {required this.color, this.textColor = const Color(0xFFFFFFFF)});

  final String text;
  final Color color;
  final Color textColor;

  @override
  bool operator ==(Object other) =>
      other is SquareBadge && other.text == text && other.color == color && other.textColor == textColor;

  @override
  int get hashCode => Object.hash(text, color, textColor);
}

/// Asks the user which piece a move turns into: the [choices] stack from
/// [square] towards the middle of the board; a tap on one calls
/// [onSelected] with it, a tap anywhere else with null.
@immutable
class PromotionPrompt {
  const PromotionPrompt({
    required this.square,
    required this.choices,
    required this.onSelected,
  });

  final String square;
  final List<Piece> choices;
  final void Function(Piece? piece) onSelected;
}

/// Board editing (set-up screens): every piece can be dragged anywhere,
/// or every touched square is "painted".
enum BoardEditMode {
  /// Drag any piece to any square ([BoardEditing.onPieceDropped]); dropped
  /// off the board it is removed ([BoardEditing.onPieceRemoved]).
  drag,

  /// Every square a finger touches or slides over goes to
  /// [BoardEditing.onSquareEdited] (place or erase, the host decides).
  paint,
}

@immutable
class BoardEditing {
  const BoardEditing({
    this.mode = BoardEditMode.drag,
    this.onPieceDropped,
    this.onPieceRemoved,
    this.onSquareEdited,
  });

  final BoardEditMode mode;
  final void Function(String from, String to)? onPieceDropped;
  final void Function(String square)? onPieceRemoved;
  final void Function(String square)? onSquareEdited;
}

/// User drawing on the board: with a mouse, a right-button drag (or click)
/// draws an arrow (or circle); on touch, a finger held on an empty square
/// lets a second finger draw. The board reports finished shapes; the host
/// keeps them and passes them back through `shapes`.
@immutable
class DrawingOptions {
  const DrawingOptions({
    this.enabled = false,
    this.brushes = defaultBrushes,
    this.brushForNewShape,
    this.onShapeDrawn,
    this.onClear,
  });

  final bool enabled;

  /// The palette `Shape.brush` names refer to.
  final List<Brush> brushes;

  /// The brush of a shape being started now (e.g. from held modifier keys);
  /// the first brush when null.
  final String Function()? brushForNewShape;

  final void Function(Shape shape)? onShapeDrawn;

  /// A plain click (mouse) or a lone tap (touch): hosts usually clear the
  /// user's shapes.
  final VoidCallback? onClear;
}

/// Colours of a [ChessBoard]. Squares are flat [lightSquare]/[darkSquare]
/// unless a [texture] image covers the board.
@immutable
class ChessBoardStyle {
  const ChessBoardStyle({
    this.lightSquare = const Color(0xFFF0D9B5),
    this.darkSquare = const Color(0xFFB58863),
    this.texture,
    this.lastMove = const Color(0x699BC700),
    this.selected = const Color(0x8014551E),
    this.moveDest = const Color(0x8014551E),
    this.premoveDest = const Color(0x80141E55),
    this.check = const Color(0xFFFF0000),
    this.dragTarget = const Color(0x33000000),
    this.promotionScrim = const Color(0x99000000),
    this.promotionChoice = const Color(0xFFF2F2F2),
    this.coordinateOnLight,
    this.coordinateOnDark,
    this.coordinateOutside = const Color(0x8C1E143C),
  });

  final Color lightSquare;
  final Color darkSquare;

  /// A board image drawn instead of the flat squares.
  final ImageProvider? texture;

  final Color lastMove;
  final Color selected;
  final Color moveDest;
  final Color premoveDest;

  /// The glow under a king in check.
  final Color check;

  /// Where a dragged piece would land.
  final Color dragTarget;
  final Color promotionScrim;
  final Color promotionChoice;

  /// Inside coordinates: the label colour on light / dark squares (by
  /// default the other square colour).
  final Color? coordinateOnLight;
  final Color? coordinateOnDark;

  /// Outside coordinates (in the margin).
  final Color coordinateOutside;

  @override
  bool operator ==(Object other) =>
      other is ChessBoardStyle &&
      other.lightSquare == lightSquare &&
      other.darkSquare == darkSquare &&
      other.texture == texture &&
      other.lastMove == lastMove &&
      other.selected == selected &&
      other.moveDest == moveDest &&
      other.premoveDest == premoveDest &&
      other.check == check &&
      other.dragTarget == dragTarget &&
      other.promotionScrim == promotionScrim &&
      other.promotionChoice == promotionChoice &&
      other.coordinateOnLight == coordinateOnLight &&
      other.coordinateOnDark == coordinateOnDark &&
      other.coordinateOutside == coordinateOutside;

  @override
  int get hashCode => Object.hash(lightSquare, darkSquare, texture, lastMove, selected, moveDest, premoveDest, check,
      dragTarget, promotionScrim, promotionChoice, coordinateOnLight, coordinateOnDark, coordinateOutside);
}

/// Draws one piece filling a [size]×[size] box (the host's art).
typedef PieceBuilder = Widget Function(BuildContext context, Piece piece, double size);
