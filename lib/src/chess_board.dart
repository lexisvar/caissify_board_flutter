/// A declarative, rule-agnostic chess board widget with a robust touch
/// layer: tap a piece then its destination, or drag it.
///
/// The host passes the pieces, which squares may move and where to
/// ([ChessBoard.dests], [ChessBoard.premoveDests]); the board reports what
/// the user asked for ([ChessBoard.onMove]). Rules stay in the host.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'board_painter.dart' show coordLayout;
import 'chess_board_gestures.dart';
import 'chess_board_models.dart';
import 'config.dart';
import 'drawable.dart';
import 'geometry.dart';
import 'shape_painter.dart';
import 'state.dart';

/// The square under [local] (a point in the board widget's own box), or
/// null off the playing area.
String? squareAtOffset(
  Offset local, {
  required double size,
  int dimension = 8,
  bool flipped = false,
  CoordinatesMode coordinates = CoordinatesMode.none,
}) {
  final (origin, extent) = coordLayout(Size(size, size), coordinates);
  final geometry = BoardGeometry(dimension);
  final pos = geometry.positionAtPoint(local.dx - origin.dx, local.dy - origin.dy, extent, flip: flipped);
  return pos == null ? null : geometry.formatKey(pos.$1, pos.$2);
}

/// How long a pointer may stay silent mid-drag before a new finger is
/// taken as a fresh touch rather than an extra one (its up was lost).
const kStaleDragPointer = Duration(seconds: 1);

/// A chess (or any N×N) board: renders [pieces], lets the user move the
/// movable ones, and reports moves. See the library docs for the model.
class ChessBoard extends StatefulWidget {
  const ChessBoard({
    super.key,
    required this.pieces,
    this.size,
    this.dimension = 8,
    this.flipped = false,
    this.style = const ChessBoardStyle(),
    this.pieceBuilder,
    this.interactive = true,
    this.dests = const {},
    this.premoveDests = const {},
    this.premove,
    this.onMove,
    this.onPremoveCancel,
    this.onSquareTouched,
    this.editing,
    this.lastMove,
    this.check,
    this.highlights = const {},
    this.badges = const {},
    this.shapes = const [],
    this.drawing = const DrawingOptions(),
    this.promotion,
    this.showDests = true,
    this.showLastMove = true,
    this.animate = true,
    this.animationDuration = const Duration(milliseconds: 200),
    this.coordinates = CoordinatesMode.none,
    this.borderRadius = BorderRadius.zero,
    this.boxShadow = const [],
    this.dragScale = 1.0,
  }) : assert(dragScale >= 1.0 && dragScale <= 1.5, 'keep the dragged piece close to its size');

  /// Square key → piece.
  final Map<String, Piece> pieces;

  /// Side length; null fills the width available (square).
  final double? size;

  /// Squares per side (8 for chess).
  final int dimension;

  /// True draws the board from the top side's view (black at the bottom).
  final bool flipped;

  final ChessBoardStyle style;

  /// The pieces' art; plain glyph tokens when null.
  final PieceBuilder? pieceBuilder;

  /// False: nothing can be selected or moved.
  final bool interactive;

  /// Squares whose piece may move now → where it may go. A key with an
  /// empty set is a movable piece without moves (it can be picked up).
  final Map<String, Set<String>> dests;

  /// Squares whose piece may be premoved → where (shown in the premove
  /// colour; the move comes back with [BoardMove.premove] set).
  final Map<String, Set<String>> premoveDests;

  /// The premove waiting now: tinted, and a tap on its origin cancels it.
  final BoardMove? premove;

  final void Function(BoardMove move)? onMove;

  /// The user cancelled the premove: a tap on an empty square or an
  /// unselectable piece, a drag dropped off the board or on a square it
  /// can't premove to, or a tap on the premove's origin.
  final VoidCallback? onPremoveCancel;

  /// Every square a primary pointer goes down on (also on fixed boards).
  final void Function(String square)? onSquareTouched;

  /// Set-up mode: replaces moving by [dests].
  final BoardEditing? editing;

  final ({String from, String to})? lastMove;

  /// The square of a king in check.
  final String? check;

  /// Extra square tints (painted under the pieces).
  final Map<String, Color> highlights;

  final Map<String, SquareBadge> badges;
  final List<Shape> shapes;
  final DrawingOptions drawing;

  /// Shows the promotion picker; the board takes no other input meanwhile.
  final PromotionPrompt? promotion;

  final bool showDests;
  final bool showLastMove;
  final bool animate;
  final Duration animationDuration;
  final CoordinatesMode coordinates;
  final BorderRadius borderRadius;
  final List<BoxShadow> boxShadow;

  /// The dragged piece's size relative to a square (1 = same size); it
  /// grows around the point where the finger holds it.
  final double dragScale;

  @override
  State<ChessBoard> createState() => ChessBoardState();
}

class _Press {
  _Press({
    required this.pointer,
    required this.kind,
    required this.downLocal,
    required this.square,
    required this.lastEvent,
  });

  final int pointer;
  final PointerDeviceKind kind;
  final Offset downLocal;
  final String square;
  Duration lastEvent;

  /// Moved past the slop: no longer a tap.
  bool moved = false;

  /// The piece this press may pick up.
  String? dragFrom;

  bool deselectOnUp = false;
  bool cancelPremoveOnUp = false;

  /// Part of a two-finger gesture: its up is no tap.
  bool noTap = false;

  /// Paint mode: the last square edited.
  String? painted;

  bool get mouse => kind == PointerDeviceKind.mouse;
}

class _Drag {
  _Drag({
    required this.pointer,
    required this.from,
    required this.piece,
    required this.grab,
    required this.global,
    required this.target,
    required this.mouse,
  });

  final int pointer;
  final String from;
  final Piece piece;

  /// Where the finger holds the piece, from the square's top-left corner.
  final Offset grab;
  Offset global;
  String? target;
  final bool mouse;
}

class _Draw {
  _Draw({required this.pointer, required this.origin, required this.brush, required this.lastEvent});

  final int pointer;
  final String origin;
  final String brush;
  String? to;
  Duration lastEvent;

  Shape shape({double scale = 1.0}) => to == null || to == origin
      ? CircleShape(square: origin, brush: brush, scale: scale)
      : ArrowShape(from: origin, to: to!, brush: brush, scale: scale);
}

/// The board's state. Its read-only getters describe the gesture in
/// progress (handy in tests).
class ChessBoardState extends State<ChessBoard> with SingleTickerProviderStateMixin implements BoardPointerSink {
  String? _selected;
  _Press? _press;
  _Drag? _drag;
  _Draw? _draw;
  OverlayEntry? _feedback;

  /// A move just dropped by drag: the piece is already where it lands, so
  /// the new position doesn't slide it there again.
  ({String from, String to})? _lastDrop;

  late final AnimationController _motion = AnimationController(vsync: this, value: 1);
  Map<String, String> _translations = const {};
  Map<String, Piece> _fading = const {};

  final Map<(Piece, double), Widget> _pieceCache = {};

  /// The selected square, if any.
  String? get selected => _selected;

  /// The square a piece is being dragged from, if any.
  String? get dragging => _drag?.from;

  /// The square under the dragged piece's pointer, if any.
  String? get dragTarget => _drag?.target;

  /// The shape being drawn, if any.
  Shape? get liveShape => _draw?.shape();

  BoardGeometry get _geometry => BoardGeometry(widget.dimension);

  double _sizeOf(BoxConstraints constraints) {
    final size = widget.size;
    if (size != null) return size;
    final w = constraints.maxWidth.isFinite ? constraints.maxWidth : constraints.maxHeight;
    return w.isFinite ? w : 320;
  }

  double _boardSize = 0;

  (Offset, double) get _layout => coordLayout(Size(_boardSize, _boardSize), widget.coordinates);

  double get _cell => _layout.$2 / widget.dimension;

  String? _squareAt(Offset local) => squareAtOffset(
        local,
        size: _boardSize,
        dimension: widget.dimension,
        flipped: widget.flipped,
        coordinates: widget.coordinates,
      );

  /// Top-left of [square] in the widget's box.
  Offset _topLeft(String square) {
    final pos = _geometry.parseKey(square);
    if (pos == null) return Offset.zero;
    final (origin, extent) = _layout;
    final (x, y) = _geometry.pointOfPosition(pos.$1, pos.$2, extent, flip: widget.flipped);
    return origin + Offset(x, y);
  }

  bool _selectable(String square) =>
      widget.pieces[square] != null &&
      (widget.dests.containsKey(square) || widget.premoveDests.containsKey(square));

  bool get _listening =>
      widget.interactive ||
      widget.editing != null ||
      widget.onSquareTouched != null ||
      widget.drawing.enabled ||
      widget.promotion != null;

  // ── lifecycle ─────────────────────────────────────────────────────────────

  @override
  void didUpdateWidget(ChessBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (old.pieceBuilder != widget.pieceBuilder) _pieceCache.clear();

    final reoriented = old.flipped != widget.flipped ||
        old.dimension != widget.dimension ||
        old.coordinates != widget.coordinates ||
        old.size != widget.size;
    final stopped = !widget.interactive && old.interactive || (widget.editing == null) != (old.editing == null);
    if (reoriented || stopped) {
      // what the gesture was about no longer holds: start clean
      _resetGestures();
      _selected = null;
    } else {
      // keep a gesture or a selection that still makes sense (a clock
      // rebuilding the board every 100 ms must not drop them)
      final drag = _drag;
      if (drag != null &&
          (widget.pieces[drag.from] != drag.piece ||
              widget.promotion != null ||
              (widget.editing == null && !_selectable(drag.from)))) {
        _endDrag();
        _press = null;
      }
      final selected = _selected;
      if (selected != null && (widget.editing != null || !_selectable(selected))) {
        _selected = null;
      }
    }
    if (!widget.drawing.enabled) _draw = null;

    if (!_samePieces(old.pieces, widget.pieces)) {
      _animate(old.pieces, widget.pieces);
      _lastDrop = null;
    }
  }

  static bool _samePieces(Map<String, Piece> a, Map<String, Piece> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _removeFeedback();
    _motion.dispose();
    super.dispose();
  }

  // ── animation ─────────────────────────────────────────────────────────────

  void _animate(Map<String, Piece> before, Map<String, Piece> after) {
    if (!widget.animate || widget.animationDuration <= Duration.zero) {
      _translations = const {};
      _fading = const {};
      _motion.value = 1;
      return;
    }
    final vacated = [
      for (final e in before.entries)
        if (after[e.key] != e.value) e.key,
    ];
    final used = <String>{};
    final translations = <String, String>{};
    final drop = _lastDrop;
    for (final e in after.entries) {
      if (before[e.key] == e.value) continue;
      if (drop != null && drop.to == e.key && before[drop.from] == e.value) {
        used.add(drop.from); // dropped there by hand: no slide
        continue;
      }
      String? best;
      var bestDistance = 1 << 30;
      for (final from in vacated) {
        if (used.contains(from) || before[from] != e.value) continue;
        final d = _distance(from, e.key);
        if (d < bestDistance) {
          best = from;
          bestDistance = d;
        }
      }
      if (best != null) {
        used.add(best);
        translations[e.key] = best;
      }
    }
    _translations = translations;
    _fading = {
      for (final from in vacated)
        if (!used.contains(from)) from: before[from]!,
    };
    if (_translations.isEmpty && _fading.isEmpty) return;
    _motion.duration = widget.animationDuration;
    _motion.forward(from: 0);
  }

  int _distance(String a, String b) {
    final pa = _geometry.parseKey(a);
    final pb = _geometry.parseKey(b);
    if (pa == null || pb == null) return 1 << 20;
    final df = pa.$1 - pb.$1;
    final dr = pa.$2 - pb.$2;
    return df * df + dr * dr;
  }

  // ── pointer handling ──────────────────────────────────────────────────────

  @override
  bool pointerDown(PointerDownEvent event) {
    if (!mounted) return false;
    final local = event.localPosition;
    final square = _squareAt(local);
    final mouse = event.kind == PointerDeviceKind.mouse;

    // right button: drawing
    if (mouse && event.buttons & kSecondaryMouseButton != 0) {
      if (!widget.drawing.enabled || square == null || widget.promotion != null) return false;
      if (_draw != null && !_stale(_draw!.lastEvent, event.timeStamp)) return false;
      _startDraw(event.pointer, square, event.timeStamp);
      return true;
    }
    if (event.buttons & kPrimaryButton == 0) return false;

    final press = _press;
    final draw = _draw;
    if (_drag != null) {
      // an extra finger while a piece is held: ignore it, unless the held
      // pointer has gone silent (its up was lost): then start afresh
      if (!_stale(press?.lastEvent ?? Duration.zero, event.timeStamp)) return false;
      _cancelDrag();
      _press = null;
    } else if (draw != null && draw.pointer != event.pointer) {
      if (!_stale(draw.lastEvent, event.timeStamp)) return false;
      setState(() => _draw = null);
    } else if (press != null) {
      if (widget.drawing.enabled &&
          !press.mouse &&
          !mouse &&
          widget.pieces[press.square] == null &&
          square != null &&
          widget.promotion == null) {
        // a finger held on an empty square: this one draws
        press.noTap = true;
        _startDraw(event.pointer, square, event.timeStamp);
        return true;
      }
      // a new touch while the board still holds an older one (a second
      // finger, or a pointer whose up never came): the new one wins, so a
      // tap is never swallowed
      _press = null;
    }

    if (square == null) return false;

    final promotion = widget.promotion;
    if (promotion != null) {
      _pickPromotion(promotion, local);
      return true;
    }

    if (mouse) widget.drawing.onClear?.call();
    widget.onSquareTouched?.call(square);

    final next = _Press(
      pointer: event.pointer,
      kind: event.kind,
      downLocal: local,
      square: square,
      lastEvent: event.timeStamp,
    );
    _press = next;

    final editing = widget.editing;
    if (editing != null) {
      if (editing.mode == BoardEditMode.paint) {
        next.painted = square;
        editing.onSquareEdited?.call(square);
        return true;
      }
      if (widget.pieces[square] != null) {
        next.dragFrom = square;
        return true;
      }
      return false;
    }

    if (!widget.interactive) return false;
    return _pressSquare(next, square);
  }

  /// A primary press on [square]: select, move, or cancel. Returns whether
  /// the board claims the pointer.
  bool _pressSquare(_Press press, String square) {
    final selected = _selected;
    final premove = widget.premove;
    var claim = false;
    var moved = false;
    if (selected != null && square != selected) {
      if (_tryMove(selected, square, dragged: false)) {
        claim = true;
        moved = true;
        _select(null);
      } else if (_selectable(square)) {
        _select(square);
        press.dragFrom = square;
        claim = true;
      } else {
        _select(null);
      }
    } else if (selected == square) {
      press.deselectOnUp = true;
      press.dragFrom = square;
      claim = true;
    } else if (_selectable(square)) {
      _select(square);
      press.dragFrom = square;
      claim = true;
    } else if (premove != null) {
      widget.onPremoveCancel?.call();
      _select(null);
    }
    // a tap on the premove's origin cancels it on up (not the tap that
    // just made a new premove there: the host may not have rebuilt yet)
    if (!moved && premove?.from == square) press.cancelPremoveOnUp = true;
    return claim;
  }

  bool _tryMove(String from, String to, {required bool dragged}) {
    if (from == to) return false;
    if (widget.dests[from]?.contains(to) ?? false) {
      widget.onMove?.call(BoardMove(from: from, to: to, dragged: dragged));
      return true;
    }
    if (widget.premoveDests[from]?.contains(to) ?? false) {
      widget.onMove?.call(BoardMove(from: from, to: to, premove: true, dragged: dragged));
      return true;
    }
    return false;
  }

  void _select(String? square) {
    if (_selected == square) return;
    setState(() => _selected = square);
  }

  bool _stale(Duration last, Duration now) => now - last > kStaleDragPointer;

  @override
  void pointerMove(PointerMoveEvent event) {
    if (!mounted) return;
    final draw = _draw;
    if (draw != null && draw.pointer == event.pointer) {
      draw.lastEvent = event.timeStamp;
      final square = _squareAt(event.localPosition);
      if (square != null && square != (draw.to ?? draw.origin)) {
        setState(() => draw.to = square);
      }
      return;
    }
    final press = _press;
    if (press == null || press.pointer != event.pointer) return;
    press.lastEvent = event.timeStamp;

    final editing = widget.editing;
    if (editing != null && editing.mode == BoardEditMode.paint) {
      final square = _squareAt(event.localPosition);
      if (square != null && square != press.painted) {
        press.painted = square;
        editing.onSquareEdited?.call(square);
      }
      return;
    }

    final drag = _drag;
    if (drag != null && drag.pointer == event.pointer) {
      drag.global = event.position;
      _feedback?.markNeedsBuild();
      final target = _squareAt(event.localPosition);
      if (target != drag.target) setState(() => drag.target = target);
      return;
    }
    if (!press.moved) {
      final slop = press.mouse ? kPrecisePointerHitSlop : kTouchSlop;
      if ((event.localPosition - press.downLocal).distance <= slop) return;
      press.moved = true;
    }
    final from = press.dragFrom;
    if (from != null && _drag == null) _startDrag(press, from, event);
  }

  void _startDrag(_Press press, String from, PointerMoveEvent event) {
    final piece = widget.pieces[from];
    if (piece == null) return;
    if (widget.editing == null && !_selectable(from)) return;
    final target = _squareAt(event.localPosition);
    setState(() {
      if (widget.editing == null) _selected = from;
      _drag = _Drag(
        pointer: press.pointer,
        from: from,
        piece: piece,
        grab: press.downLocal - _topLeft(from),
        global: event.position,
        target: target,
        mouse: press.mouse,
      );
    });
    _showFeedback();
  }

  @override
  void pointerUp(PointerUpEvent event) {
    if (!mounted) return;
    final draw = _draw;
    if (draw != null && draw.pointer == event.pointer) {
      final square = _squareAt(event.localPosition);
      if (square != null) draw.to = square;
      final shape = draw.shape();
      setState(() => _draw = null);
      widget.drawing.onShapeDrawn?.call(shape);
      return;
    }
    final press = _press;
    if (press == null || press.pointer != event.pointer) return;
    _press = null;
    final square = _squareAt(event.localPosition);

    final drag = _drag;
    if (drag != null && drag.pointer == event.pointer) {
      _drop(drag, square);
      return;
    }
    if (press.moved) return;

    // a tap
    if (press.deselectOnUp && square == _selected) _select(null);
    if (press.cancelPremoveOnUp && square != null && widget.premove?.from == square) {
      widget.onPremoveCancel?.call();
    }
    if (!press.noTap && !press.mouse) widget.drawing.onClear?.call();
  }

  void _drop(_Drag drag, String? square) {
    final from = drag.from;
    _endDrag();
    final editing = widget.editing;
    if (editing != null) {
      if (square == null) {
        editing.onPieceRemoved?.call(from);
      } else if (square != from) {
        _lastDrop = (from: from, to: square);
        editing.onPieceDropped?.call(from, square);
      }
      return;
    }
    if (square == null) {
      if (widget.premove != null) widget.onPremoveCancel?.call();
      _select(null);
      return;
    }
    if (square == from) return; // put back: stays selected
    _select(null);
    if (_tryMove(from, square, dragged: true)) {
      _lastDrop = (from: from, to: square);
    } else if (widget.premove != null) {
      widget.onPremoveCancel?.call();
    }
  }

  @override
  void pointerCancel(PointerCancelEvent event) => pointerLost(event.pointer);

  @override
  void pointerLost(int pointer) {
    if (!mounted) return;
    if (_draw?.pointer == pointer) {
      setState(() => _draw = null);
      return;
    }
    if (_press?.pointer != pointer) return;
    _press = null;
    if (_drag?.pointer == pointer) _cancelDrag();
  }

  @override
  void pointersReset() {
    // may run while the tree builds: no setState
    _press = null;
    _draw = null;
    _endDrag();
  }

  void _resetGestures() {
    _press = null;
    _draw = null;
    _endDrag();
  }

  void _cancelDrag() {
    if (_drag == null) return;
    setState(_endDrag);
  }

  void _endDrag() {
    _drag = null;
    _removeFeedback();
  }

  void _startDraw(int pointer, String square, Duration time) {
    final brushes = widget.drawing.brushes;
    final brush = widget.drawing.brushForNewShape?.call() ?? (brushes.isEmpty ? 'green' : brushes.first.key);
    setState(() => _draw = _Draw(pointer: pointer, origin: square, brush: brush, lastEvent: time));
  }

  void _pickPromotion(PromotionPrompt promotion, Offset local) {
    final square = _squareAt(local);
    final cells = _promotionCells(promotion);
    for (final (i, cell) in cells.indexed) {
      if (cell == square) {
        promotion.onSelected(promotion.choices[i]);
        return;
      }
    }
    promotion.onSelected(null);
  }

  /// The squares the promotion choices cover, from the target towards the
  /// middle of the board.
  List<String> _promotionCells(PromotionPrompt promotion) {
    final pos = _geometry.parseKey(promotion.square);
    if (pos == null) return const [];
    final n = widget.dimension;
    // display row of the target (0 = top)
    final row = widget.flipped ? pos.$2 : n - 1 - pos.$2;
    final down = row < n / 2;
    return [
      for (var i = 0; i < promotion.choices.length; i++)
        if (row + (down ? i : -i) >= 0 && row + (down ? i : -i) < n)
          _geometry.formatKey(
            pos.$1,
            widget.flipped ? row + (down ? i : -i) : n - 1 - (row + (down ? i : -i)),
          ),
    ];
  }

  // ── drag feedback ─────────────────────────────────────────────────────────

  void _showFeedback() {
    _removeFeedback();
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return; // drawn inside the board instead
    final entry = OverlayEntry(builder: (_) => _buildOverlayFeedback(overlay));
    _feedback = entry;
    overlay.insert(entry);
  }

  void _removeFeedback() {
    final entry = _feedback;
    _feedback = null;
    if (entry == null) return;
    entry.remove();
    entry.dispose();
  }

  Widget _buildOverlayFeedback(OverlayState overlay) {
    final drag = _drag;
    if (drag == null || !mounted || !overlay.mounted) return const SizedBox.shrink();
    final box = overlay.context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize ? box.globalToLocal(drag.global) : drag.global;
    return _feedbackAt(origin, drag);
  }

  /// The dragged piece with the grabbed point at [pointer].
  Widget _feedbackAt(Offset pointer, _Drag drag) {
    final scale = drag.mouse ? 1.0 : widget.dragScale;
    final side = _cell * scale;
    final topLeft = pointer - drag.grab * scale;
    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      width: side,
      height: side,
      child: IgnorePointer(
        child: KeyedSubtree(
          key: const ValueKey('chess-board-drag-feedback'),
          child: _pieceWidget(context, drag.piece, side),
        ),
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────

  Widget _pieceWidget(BuildContext context, Piece piece, double size) {
    final builder = widget.pieceBuilder;
    if (builder == null) return _GlyphPiece(piece: piece, size: size);
    return _pieceCache.putIfAbsent((piece, size), () => builder(context, piece, size));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _boardSize = _sizeOf(constraints);
      return SizedBox.square(
        dimension: _boardSize,
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: widget.borderRadius, boxShadow: widget.boxShadow),
          child: ClipRRect(
            borderRadius: widget.borderRadius,
            child: RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              gestures: _listening
                  ? {
                      BoardGestureRecognizer: GestureRecognizerFactoryWithHandlers<BoardGestureRecognizer>(
                        () => BoardGestureRecognizer(debugOwner: this),
                        (recognizer) => recognizer.sink = this,
                      ),
                    }
                  : const {},
              child: _layers(context),
            ),
          ),
        ),
      );
    });
  }

  Widget _layers(BuildContext context) {
    final (origin, extent) = _layout;
    final cell = extent / widget.dimension;
    final style = widget.style;
    final texture = style.texture;
    final selected = _selected;
    final drag = _drag;
    final promotion = widget.promotion;
    final draw = _draw;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (texture != null)
          Positioned(
            left: origin.dx,
            top: origin.dy,
            width: extent,
            height: extent,
            child: Image(image: texture, fit: BoxFit.cover, gaplessPlayback: true),
          ),
        Positioned.fill(
          child: CustomPaint(
            painter: _SquaresPainter(
              geometry: _geometry,
              flipped: widget.flipped,
              coordinates: widget.coordinates,
              style: style,
              flat: texture == null,
              lastMove: widget.showLastMove ? widget.lastMove : null,
              check: widget.check,
              selected: selected,
              highlights: widget.highlights,
              premove: widget.premove,
              dests: !widget.showDests || selected == null
                  ? const {}
                  : (widget.dests[selected] ?? widget.premoveDests[selected] ?? const {}),
              premoveDests: selected != null && !widget.dests.containsKey(selected),
              pieces: widget.pieces,
              dragTarget: drag?.target,
              dragTargetCircle: drag != null && !drag.mouse,
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _motion,
          builder: (context, _) => Stack(
            clipBehavior: Clip.none,
            children: _pieces(context, cell),
          ),
        ),
        for (final e in widget.badges.entries)
          if (_geometry.isValidKey(e.key)) _badge(e.key, e.value, cell),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _ShapesPainter(
                shapes: widget.shapes,
                live: draw?.shape(scale: 0.8),
                brushes: widget.drawing.brushes,
                centerOf: (square) => _geometry.isValidKey(square) ? _topLeft(square) + Offset(cell / 2, cell / 2) : null,
                cell: cell,
                layout: (widget.flipped, origin, widget.dimension),
              ),
            ),
          ),
        ),
        if (promotion != null) ..._promotionLayer(context, promotion, cell),
        if (drag != null && _feedback == null) _feedbackAt(_globalToLocal(drag.global), drag),
      ],
    );
  }

  Offset _globalToLocal(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    return box != null && box.hasSize ? box.globalToLocal(global) : global;
  }

  List<Widget> _pieces(BuildContext context, double cell) {
    final t = Curves.easeInOutCubic.transform(_motion.value);
    final animating = _motion.isAnimating;
    final drag = _drag;
    final out = <Widget>[];
    if (animating) {
      for (final e in _fading.entries) {
        final at = _topLeft(e.key);
        out.add(Positioned(
          key: ValueKey('fading-${e.key}'),
          left: at.dx,
          top: at.dy,
          width: cell,
          height: cell,
          child: IgnorePointer(child: Opacity(opacity: 1 - t, child: _pieceWidget(context, e.value, cell))),
        ));
      }
    }
    for (final e in widget.pieces.entries) {
      if (!_geometry.isValidKey(e.key)) continue;
      var at = _topLeft(e.key);
      final from = animating ? _translations[e.key] : null;
      if (from != null) at = Offset.lerp(_topLeft(from), at, t)!;
      final ghost = drag != null && drag.from == e.key;
      out.add(Positioned(
        key: ValueKey('piece-${e.key}'),
        left: at.dx,
        top: at.dy,
        width: cell,
        height: cell,
        child: IgnorePointer(
          child: Opacity(opacity: ghost ? 0.3 : 1, child: _pieceWidget(context, e.value, cell)),
        ),
      ));
    }
    return out;
  }

  Widget _badge(String square, SquareBadge badge, double cell) {
    final at = _topLeft(square);
    final d = cell * 0.42;
    return Positioned(
      left: at.dx + cell - d - cell * 0.03,
      top: at.dy + cell * 0.03,
      width: d,
      height: d,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(color: badge.color, shape: BoxShape.circle),
          child: Center(
            child: Text(
              badge.text,
              textAlign: TextAlign.center,
              textScaler: TextScaler.noScaling,
              style: TextStyle(color: badge.textColor, fontSize: d * 0.62, fontWeight: FontWeight.w700, height: 1),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _promotionLayer(BuildContext context, PromotionPrompt promotion, double cell) {
    final (origin, extent) = _layout;
    final cells = _promotionCells(promotion);
    return [
      Positioned(
        left: origin.dx,
        top: origin.dy,
        width: extent,
        height: extent,
        child: IgnorePointer(child: ColoredBox(color: widget.style.promotionScrim)),
      ),
      for (final (i, square) in cells.indexed)
        Positioned(
          key: ValueKey('promotion-$square'),
          left: _topLeft(square).dx,
          top: _topLeft(square).dy,
          width: cell,
          height: cell,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(color: widget.style.promotionChoice, shape: BoxShape.circle),
              child: Padding(
                padding: EdgeInsets.all(cell * 0.06),
                child: _pieceWidget(context, promotion.choices[i], cell * 0.88),
              ),
            ),
          ),
        ),
    ];
  }
}

/// Built-in piece token when the host gives no art.
class _GlyphPiece extends StatelessWidget {
  const _GlyphPiece({required this.piece, required this.size});

  final Piece piece;
  final double size;

  static const _glyphs = {'king': '♚', 'queen': '♛', 'rook': '♜', 'bishop': '♝', 'knight': '♞', 'pawn': '♟'};

  @override
  Widget build(BuildContext context) {
    final dark = piece.color == 'black';
    return Center(
      child: Text(
        _glyphs[piece.role] ?? (piece.role.isEmpty ? '?' : piece.role[0].toUpperCase()),
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: size * 0.78,
          height: 1,
          color: dark ? const Color(0xFF1E1A2E) : const Color(0xFFFFFDF6),
          shadows: [Shadow(color: dark ? const Color(0x66FFFFFF) : const Color(0xCC000000), blurRadius: size * 0.04)],
        ),
      ),
    );
  }
}

class _SquaresPainter extends CustomPainter {
  _SquaresPainter({
    required this.geometry,
    required this.flipped,
    required this.coordinates,
    required this.style,
    required this.flat,
    required this.lastMove,
    required this.check,
    required this.selected,
    required this.highlights,
    required this.premove,
    required this.dests,
    required this.premoveDests,
    required this.pieces,
    required this.dragTarget,
    required this.dragTargetCircle,
  });

  final BoardGeometry geometry;
  final bool flipped;
  final CoordinatesMode coordinates;
  final ChessBoardStyle style;
  final bool flat;
  final ({String from, String to})? lastMove;
  final String? check;
  final String? selected;
  final Map<String, Color> highlights;
  final BoardMove? premove;
  final Set<String> dests;
  final bool premoveDests;
  final Map<String, Piece> pieces;
  final String? dragTarget;
  final bool dragTargetCircle;

  @override
  void paint(Canvas canvas, Size size) {
    final (origin, extent) = coordLayout(size, coordinates);
    final n = geometry.size;
    final cell = extent / n;
    Rect rectOf(String square) {
      final pos = geometry.parseKey(square)!;
      final (x, y) = geometry.pointOfPosition(pos.$1, pos.$2, extent, flip: flipped);
      return Rect.fromLTWH(origin.dx + x, origin.dy + y, cell, cell);
    }

    final paint = Paint();
    if (flat) {
      for (var rank = 0; rank < n; rank++) {
        for (var file = 0; file < n; file++) {
          paint.color = isLightSquare(file, rank) ? style.lightSquare : style.darkSquare;
          final (x, y) = geometry.pointOfPosition(file, rank, extent, flip: flipped);
          // a hair wider so no seams show between squares
          canvas.drawRect(Rect.fromLTWH(origin.dx + x, origin.dy + y, cell + 0.5, cell + 0.5), paint);
        }
      }
    }

    void tint(String? square, Color color) {
      if (square == null || !geometry.isValidKey(square)) return;
      canvas.drawRect(rectOf(square), Paint()..color = color);
    }

    final last = lastMove;
    if (last != null) {
      tint(last.from, style.lastMove);
      tint(last.to, style.lastMove);
    }
    final pre = premove;
    if (pre != null) {
      tint(pre.from, style.premoveDest);
      tint(pre.to, style.premoveDest);
    }
    for (final e in highlights.entries) {
      tint(e.key, e.value);
    }
    tint(selected, style.selected);

    final king = check;
    if (king != null && geometry.isValidKey(king)) {
      final rect = rectOf(king);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(colors: [
            style.check,
            style.check.withValues(alpha: style.check.a * 0.6),
            style.check.withValues(alpha: 0),
          ], stops: const [0, 0.25, 0.9])
              .createShader(rect),
      );
    }

    final destColor = premoveDests ? style.premoveDest : style.moveDest;
    for (final square in dests) {
      if (!geometry.isValidKey(square)) continue;
      final rect = rectOf(square);
      if (pieces[square] == null) {
        canvas.drawCircle(rect.center, cell * 0.17, Paint()..color = destColor);
      } else {
        // a capture: a ring hugging the square's edge
        canvas.drawCircle(
          rect.center,
          cell * 0.46,
          Paint()
            ..color = destColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * 0.08,
        );
      }
    }

    final target = dragTarget;
    if (target != null && geometry.isValidKey(target)) {
      final rect = rectOf(target);
      if (dragTargetCircle) {
        // bigger than the finger, so it shows around it
        canvas.drawCircle(rect.center, cell, Paint()..color = style.dragTarget);
      } else {
        canvas.drawRect(rect, Paint()..color = style.dragTarget);
      }
    }

    if (coordinates == CoordinatesMode.inside) _insideCoordinates(canvas, origin, cell);
    if (coordinates == CoordinatesMode.outside) _outsideCoordinates(canvas, size, origin, cell);
  }

  void _label(Canvas canvas, String text, Rect rect, double fontSize, Color color, {Alignment align = Alignment.center}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: color, height: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    final free = Offset(rect.width - tp.width, rect.height - tp.height);
    tp.paint(canvas, rect.topLeft + Offset(free.dx * (align.x + 1) / 2, free.dy * (align.y + 1) / 2));
  }

  Color _onSquare(bool light) => light
      ? (style.coordinateOnLight ?? style.darkSquare)
      : (style.coordinateOnDark ?? style.lightSquare);

  void _insideCoordinates(Canvas canvas, Offset origin, double cell) {
    final n = geometry.size;
    final font = math.max(7.0, math.min(14.0, cell * 0.24));
    final pad = cell * 0.06;
    for (var row = 0; row < n; row++) {
      final rank = flipped ? row : n - 1 - row;
      final file = flipped ? n - 1 : 0;
      _label(canvas, '${rank + 1}', Rect.fromLTWH(origin.dx + pad, origin.dy + row * cell + pad, cell / 2, cell / 2),
          font, _onSquare(isLightSquare(file, rank)),
          align: Alignment.topLeft);
    }
    for (var column = 0; column < n; column++) {
      final file = flipped ? n - 1 - column : column;
      final rank = flipped ? n - 1 : 0;
      _label(
        canvas,
        String.fromCharCode(97 + file),
        Rect.fromLTWH(origin.dx + column * cell + cell / 2 - pad, origin.dy + n * cell - cell / 2 - pad, cell / 2, cell / 2),
        font,
        _onSquare(isLightSquare(file, rank)),
        align: Alignment.bottomRight,
      );
    }
  }

  void _outsideCoordinates(Canvas canvas, Size size, Offset origin, double cell) {
    final n = geometry.size;
    final pad = origin.dx;
    final font = math.max(8.0, math.min(15.0, pad * 0.62));
    for (var row = 0; row < n; row++) {
      final rank = flipped ? row + 1 : n - row;
      _label(canvas, '$rank', Rect.fromLTWH(0, origin.dy + row * cell, pad, cell), font, style.coordinateOutside);
    }
    for (var column = 0; column < n; column++) {
      final file = flipped ? n - 1 - column : column;
      _label(canvas, String.fromCharCode(97 + file), Rect.fromLTWH(origin.dx + column * cell, size.height - pad, cell, pad),
          font, style.coordinateOutside);
    }
  }

  @override
  bool shouldRepaint(_SquaresPainter old) =>
      old.flipped != flipped ||
      old.coordinates != coordinates ||
      old.style != style ||
      old.flat != flat ||
      old.lastMove != lastMove ||
      old.check != check ||
      old.selected != selected ||
      old.premove != premove ||
      old.premoveDests != premoveDests ||
      old.dragTarget != dragTarget ||
      old.dragTargetCircle != dragTargetCircle ||
      old.geometry.size != geometry.size ||
      !_sameMap(old.highlights, highlights) ||
      !_sameSet(old.dests, dests) ||
      (dests.isNotEmpty && !identical(old.pieces, pieces));

  static bool _sameMap(Map<String, Color> a, Map<String, Color> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  static bool _sameSet(Set<String> a, Set<String> b) =>
      identical(a, b) || (a.length == b.length && a.containsAll(b));
}

class _ShapesPainter extends CustomPainter {
  _ShapesPainter({
    required this.shapes,
    required this.live,
    required this.brushes,
    required this.centerOf,
    required this.cell,
    required this.layout,
  });

  /// What [centerOf] depends on.
  final (bool, Offset, int) layout;
  final List<Shape> shapes;
  final Shape? live;
  final List<Brush> brushes;
  final Offset? Function(String square) centerOf;
  final double cell;

  Brush _brush(String key) =>
      brushes.firstWhere((b) => b.key == key, orElse: () => brushes.isEmpty ? defaultBrushes.first : brushes.first);

  @override
  void paint(Canvas canvas, Size size) {
    for (final shape in shapes) {
      paintBoardShape(canvas, shape: shape, brush: _brush(shape.brush), centerOf: centerOf, cell: cell);
    }
    final shape = live;
    if (shape != null) {
      paintBoardShape(canvas, shape: shape, brush: _brush(shape.brush), centerOf: centerOf, cell: cell, live: true);
    }
  }

  @override
  bool shouldRepaint(_ShapesPainter old) =>
      old.live != live || old.cell != cell || old.layout != layout || old.brushes != brushes || !_sameList(old.shapes, shapes);

  static bool _sameList(List<Shape> a, List<Shape> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
