import 'package:caissify_board/caissify_board.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = 400.0;
const _cell = _size / 8;

const _wp = Piece(role: 'pawn', color: 'white');
const _bp = Piece(role: 'pawn', color: 'black');
const _wn = Piece(role: 'knight', color: 'white');
const _wq = Piece(role: 'queen', color: 'white');
const _wr = Piece(role: 'rook', color: 'white');
const _wb = Piece(role: 'bishop', color: 'white');

/// Top-left of [square] relative to the board (white at the bottom).
Offset _corner(String square, {bool flipped = false}) {
  var file = square.codeUnitAt(0) - 97;
  var row = 8 - int.parse(square.substring(1));
  if (flipped) {
    file = 7 - file;
    row = 7 - row;
  }
  return Offset(file * _cell, row * _cell);
}

/// A tiny host: white pawns go one or two squares up, the knight jumps
/// anywhere empty; it applies each move and keeps them.
class _Host extends StatefulWidget {
  const _Host({
    required this.pieces,
    this.premoves = false,
    this.flipped = false,
    this.promotion,
    this.wrap,
  });

  final Map<String, Piece> pieces;
  final bool premoves;
  final bool flipped;
  final PromotionPrompt? promotion;
  final Widget Function(Widget board)? wrap;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late Map<String, Piece> pieces = Map.of(widget.pieces);
  final moves = <BoardMove>[];
  int ticks = 0;
  BoardMove? premove;
  int premoveCancels = 0;

  Map<String, Set<String>> get dests => widget.premoves ? const {} : _dests;

  Map<String, Set<String>> get _dests => {
        for (final e in pieces.entries)
          if (e.value.color == 'white')
            e.key: {
              for (var f = 0; f < 8; f++)
                for (var r = 1; r <= 8; r++)
                  if (pieces['${String.fromCharCode(97 + f)}$r'] == null) '${String.fromCharCode(97 + f)}$r',
            },
      };

  void apply(BoardMove move) {
    setState(() {
      moves.add(move);
      if (move.premove) {
        premove = move;
        return;
      }
      final piece = pieces.remove(move.from)!;
      pieces[move.to] = piece;
    });
  }

  void tick() => setState(() => ticks++);

  void remove(String square) => setState(() => pieces.remove(square));

  @override
  Widget build(BuildContext context) {
    final board = ChessBoard(
      size: _size,
      pieces: Map.of(pieces),
      flipped: widget.flipped,
      dests: dests,
      premoveDests: widget.premoves ? _dests : const {},
      premove: premove,
      onPremoveCancel: () => setState(() {
        premove = null;
        premoveCancels++;
      }),
      onMove: apply,
      promotion: widget.promotion,
      animate: false,
    );
    return MaterialApp(
      home: Scaffold(
        body: widget.wrap?.call(board) ?? Align(alignment: Alignment.topLeft, child: Column(children: [board, Text('t$ticks')])),
      ),
    );
  }
}

_HostState _host(WidgetTester tester) => tester.state<_HostState>(find.byType(_Host));
ChessBoardState _board(WidgetTester tester) => tester.state<ChessBoardState>(find.byType(ChessBoard));

Offset _boardOrigin(WidgetTester tester) => tester.getTopLeft(find.byType(ChessBoard));
Offset _center(WidgetTester tester, String square, {bool flipped = false}) =>
    _boardOrigin(tester) + _corner(square, flipped: flipped) + const Offset(_cell / 2, _cell / 2);

Future<void> _tap(WidgetTester tester, String square, {int? pointer}) async {
  await tester.tapAt(_center(tester, square), pointer: pointer);
  await tester.pump();
}

const _start = {'e2': _wp, 'd2': _wp, 'g1': _wn, 'e7': _bp};

void main() {
  testWidgets('tap a piece, then its destination: the move goes to the host', (tester) async {
    await tester.pumpWidget(const _Host(pieces: _start));
    await _tap(tester, 'e2');
    expect(_board(tester).selected, 'e2');
    await _tap(tester, 'e4');
    expect(_host(tester).moves, [const BoardMove(from: 'e2', to: 'e4')]);
    expect(_board(tester).selected, isNull);
    expect(tester.widget<ChessBoard>(find.byType(ChessBoard)).pieces['e4'], _wp);
  });

  testWidgets('tap the selected piece again to deselect; another own piece switches', (tester) async {
    await tester.pumpWidget(const _Host(pieces: _start));
    await _tap(tester, 'e2');
    await _tap(tester, 'e2');
    expect(_board(tester).selected, isNull);
    await _tap(tester, 'e2');
    await _tap(tester, 'g1');
    expect(_board(tester).selected, 'g1');
    await _tap(tester, 'e7'); // not movable: deselects, no move
    expect(_board(tester).selected, isNull);
    expect(_host(tester).moves, isEmpty);
  });

  group('drag', () {
    testWidgets('the drop square is the one under the finger, and the piece stays where it was grabbed', (tester) async {
      await tester.pumpWidget(const _Host(pieces: _start));
      // grab the pawn low on its square: its picture then sits above the finger
      const grab = Offset(_cell / 2 + 9, _cell - 4);
      final down = _boardOrigin(tester) + _corner('e2') + grab;
      final gesture = await tester.startGesture(down);
      await tester.pump();
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      final pointer = _center(tester, 'e4') + const Offset(5, 3);
      await gesture.moveTo(pointer);
      await tester.pump();

      expect(_board(tester).dragging, 'e2');
      expect(_board(tester).dragTarget, 'e4', reason: 'the square under the finger, not under the piece');
      final feedback = tester.getRect(find.byKey(const ValueKey('chess-board-drag-feedback')));
      expect(feedback.size, const Size(_cell, _cell));
      expect(feedback.topLeft + grab, offsetMoreOrLessEquals(pointer), reason: 'the grabbed point follows the finger');
      // most of the piece is over e5, yet the finger is on e4
      expect(feedback.center.dy, lessThan(_center(tester, 'e4').dy - _cell / 3));

      await gesture.up();
      await tester.pump();
      expect(_host(tester).moves, [const BoardMove(from: 'e2', to: 'e4', dragged: true)]);
      expect(find.byKey(const ValueKey('chess-board-drag-feedback')), findsNothing);
    });

    testWidgets('a drag scale grows the piece around the grabbed point', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: ChessBoard(size: _size, pieces: const {'e2': _wp}, dests: const {'e2': {'e4'}}, dragScale: 1.2),
        ),
      ));
      const grab = Offset(10, 40);
      final gesture = await tester.startGesture(_corner('e2') + grab);
      await gesture.moveTo(_corner('e5'));
      await tester.pump();
      final feedback = tester.getRect(find.byKey(const ValueKey('chess-board-drag-feedback')));
      expect(feedback.width, closeTo(_cell * 1.2, 0.01));
      expect(feedback.topLeft + grab * 1.2, offsetMoreOrLessEquals(_corner('e5')));
      await gesture.up();
    });

    testWidgets('dropped off the board or on its own square nothing moves', (tester) async {
      await tester.pumpWidget(const _Host(pieces: _start));
      final gesture = await tester.startGesture(_center(tester, 'e2'));
      await gesture.moveTo(_center(tester, 'e2') + const Offset(0, 300));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(_host(tester).moves, isEmpty);
      expect(_board(tester).selected, isNull);

      final back = await tester.startGesture(_center(tester, 'e2'));
      await back.moveTo(_center(tester, 'e3'));
      await tester.pump();
      await back.moveTo(_center(tester, 'e2'));
      await tester.pump();
      await back.up();
      await tester.pump();
      expect(_host(tester).moves, isEmpty);
      expect(_board(tester).selected, 'e2', reason: 'put back: still selected');
    });
  });

  group('never stuck (lost pointers)', () {
    testWidgets('a pointer whose up never comes does not swallow the next tap', (tester) async {
      await tester.pumpWidget(const _Host(pieces: _start));
      final lost = await tester.startGesture(_center(tester, 'e2'), pointer: 1);
      await tester.pump();
      expect(_board(tester).selected, 'e2');
      // ... its up is lost; the next touch is a new pointer
      await _tap(tester, 'e4', pointer: 2);
      expect(_host(tester).moves.single, const BoardMove(from: 'e2', to: 'e4'));
      // and again, nothing left over
      await _tap(tester, 'g1', pointer: 3);
      await _tap(tester, 'f3', pointer: 4);
      expect(_host(tester).moves.last, const BoardMove(from: 'g1', to: 'f3'));
      await lost.cancel();
    });

    testWidgets('a drag whose up never comes is dropped by the next touch', (tester) async {
      await tester.pumpWidget(const _Host(pieces: _start));
      final lost = await tester.createGesture(pointer: 1);
      await lost.down(_center(tester, 'e2'), timeStamp: const Duration(seconds: 10));
      await lost.moveTo(_center(tester, 'e3'), timeStamp: const Duration(seconds: 10, milliseconds: 50));
      await tester.pump();
      expect(_board(tester).dragging, 'e2');
      // two seconds later a new tap: the held pointer is long silent
      final next = await tester.createGesture(pointer: 2);
      await next.down(_center(tester, 'g1'), timeStamp: const Duration(seconds: 12));
      await next.up(timeStamp: const Duration(seconds: 12, milliseconds: 80));
      await tester.pump();
      expect(_board(tester).dragging, isNull);
      expect(find.byKey(const ValueKey('chess-board-drag-feedback')), findsNothing);
      expect(_board(tester).selected, 'g1');
      await _tap(tester, 'f3', pointer: 3);
      expect(_host(tester).moves.single, const BoardMove(from: 'g1', to: 'f3'));
      await lost.cancel();
    });

    testWidgets('a cancelled pointer ends its drag and the next taps work', (tester) async {
      await tester.pumpWidget(const _Host(pieces: _start));
      final gesture = await tester.startGesture(_center(tester, 'e2'));
      await gesture.moveTo(_center(tester, 'e4'));
      await tester.pump();
      expect(_board(tester).dragging, 'e2');
      await gesture.cancel();
      await tester.pump();
      expect(_board(tester).dragging, isNull);
      expect(_host(tester).moves, isEmpty);
      expect(find.byKey(const ValueKey('chess-board-drag-feedback')), findsNothing);
      // still selected after the cancel: one tap finishes the move
      await _tap(tester, 'e4');
      expect(_host(tester).moves.single, const BoardMove(from: 'e2', to: 'e4'));
      await _tap(tester, 'd2');
      await _tap(tester, 'd4');
      expect(_host(tester).moves.last, const BoardMove(from: 'd2', to: 'd4'));
    });

    testWidgets('a second finger during a drag is ignored, and the next tap still works', (tester) async {
      await tester.pumpWidget(const _Host(pieces: _start));
      final drag = await tester.startGesture(_center(tester, 'e2'), pointer: 1);
      await drag.moveTo(_center(tester, 'e3'));
      await tester.pump();
      final extra = await tester.startGesture(_center(tester, 'h5'), pointer: 2);
      await tester.pump();
      await extra.up();
      await tester.pump();
      expect(_board(tester).dragging, 'e2');
      await drag.moveTo(_center(tester, 'e4'));
      await drag.up();
      await tester.pump();
      expect(_host(tester).moves.single, const BoardMove(from: 'e2', to: 'e4', dragged: true));
      await _tap(tester, 'g1', pointer: 3);
      await _tap(tester, 'f3', pointer: 4);
      expect(_host(tester).moves.last, const BoardMove(from: 'g1', to: 'f3'));
    });

    testWidgets('a second finger while one is pressed: the newest touch counts', (tester) async {
      await tester.pumpWidget(const _Host(pieces: _start));
      final first = await tester.startGesture(_center(tester, 'g1'), pointer: 1);
      await tester.pump();
      await _tap(tester, 'h3', pointer: 2);
      expect(_host(tester).moves.single, const BoardMove(from: 'g1', to: 'h3'));
      await first.up(); // its late up changes nothing
      await tester.pump();
      await _tap(tester, 'e2', pointer: 3);
      await _tap(tester, 'e4', pointer: 4);
      expect(_host(tester).moves.last, const BoardMove(from: 'e2', to: 'e4'));
    });

    testWidgets('a position change mid-drag that removes the piece ends the drag', (tester) async {
      await tester.pumpWidget(const _Host(pieces: _start));
      final drag = await tester.startGesture(_center(tester, 'e2'));
      await drag.moveTo(_center(tester, 'e3'));
      await tester.pump();
      final host = _host(tester);
      host.remove('e2');
      await tester.pump();
      await tester.pump(); // the overlay drops the feedback on the next frame
      expect(_board(tester).dragging, isNull);
      expect(find.byKey(const ValueKey('chess-board-drag-feedback')), findsNothing);
      await drag.up();
      await tester.pump();
      expect(host.moves, isEmpty);
      await _tap(tester, 'g1');
      await _tap(tester, 'f3');
      expect(host.moves.single, const BoardMove(from: 'g1', to: 'f3'));
    });
  });

  testWidgets('rebuilding every 100 ms (a clock) keeps the selection and a drag', (tester) async {
    await tester.pumpWidget(const _Host(pieces: _start));
    await _tap(tester, 'e2');
    for (var i = 0; i < 10; i++) {
      _host(tester).tick();
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('t10'), findsOneWidget);
    expect(_board(tester).selected, 'e2');
    await _tap(tester, 'e4');
    expect(_host(tester).moves.single, const BoardMove(from: 'e2', to: 'e4'));

    final drag = await tester.startGesture(_center(tester, 'g1'));
    await drag.moveTo(_center(tester, 'g2'));
    for (var i = 0; i < 5; i++) {
      _host(tester).tick();
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_board(tester).dragging, 'g1');
    await drag.moveTo(_center(tester, 'f3'));
    await drag.up();
    await tester.pump();
    expect(_host(tester).moves.last, const BoardMove(from: 'g1', to: 'f3', dragged: true));
  });

  group('inside a scrolling page', () {
    late ScrollController scroll;
    setUp(() => scroll = ScrollController(initialScrollOffset: 60));
    tearDown(() => scroll.dispose());

    Widget page(Widget board) => ListView(
          controller: scroll,
          children: [const SizedBox(height: 200), Align(alignment: Alignment.topLeft, child: board), const SizedBox(height: 1500)],
        );

    testWidgets('dragging my piece moves it and does not scroll', (tester) async {
      await tester.pumpWidget(_Host(pieces: _start, wrap: page));
      final gesture = await tester.startGesture(_center(tester, 'e2'));
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(_center(tester, 'e2') - Offset(0, i * 10.0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(scroll.offset, 60);
      expect(_host(tester).moves.single, const BoardMove(from: 'e2', to: 'e4', dragged: true));
    }, variant: const TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}));

    testWidgets('a vertical drag from an empty square or a piece I cannot move still scrolls', (tester) async {
      await tester.pumpWidget(_Host(pieces: _start, wrap: page));
      for (final square in ['e4', 'e7']) {
        final before = scroll.offset;
        await tester.dragFrom(_center(tester, square), const Offset(0, -120));
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(before + 50), reason: 'from $square');
      }
      expect(_host(tester).moves, isEmpty);
    }, variant: const TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}));

    testWidgets('tap-tap still moves inside the list', (tester) async {
      await tester.pumpWidget(_Host(pieces: _start, wrap: page));
      await _tap(tester, 'e2');
      await _tap(tester, 'e4');
      expect(_host(tester).moves.single, const BoardMove(from: 'e2', to: 'e4'));
    }, variant: const TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}));
  });

  testWidgets('a fixed board leaves taps to an enclosing InkWell', (tester) async {
    var taps = 0;
    final touched = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: Align(
          alignment: Alignment.topLeft,
          child: InkWell(
            onTap: () => taps++,
            child: ChessBoard(size: _size, pieces: _start, interactive: false, onSquareTouched: touched.add),
          ),
        ),
      ),
    ));
    await tester.tapAt(_corner('e2') + const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(touched, ['e2']);
  });

  group('premoves', () {
    testWidgets('a premove is reported as such; tapping an empty square cancels it', (tester) async {
      await tester.pumpWidget(const _Host(pieces: _start, premoves: true));
      await _tap(tester, 'e2');
      await _tap(tester, 'e4');
      expect(_host(tester).moves.single, const BoardMove(from: 'e2', to: 'e4', premove: true));
      expect(_host(tester).premove, isNotNull);
      await _tap(tester, 'a5');
      expect(_host(tester).premove, isNull);
      expect(_host(tester).premoveCancels, 1);
    });

    testWidgets('a premove dragged off the board is cancelled', (tester) async {
      await tester.pumpWidget(const _Host(pieces: _start, premoves: true));
      await _tap(tester, 'e2');
      await _tap(tester, 'e4');
      final gesture = await tester.startGesture(_center(tester, 'd2'));
      await gesture.moveTo(_center(tester, 'd2') + const Offset(0, 200));
      await gesture.up();
      await tester.pump();
      expect(_host(tester).premove, isNull);
    });
  });

  testWidgets('promotion: the choices stack from the target; a tap picks one, elsewhere cancels', (tester) async {
    final picked = <Piece?>[];
    final prompt = PromotionPrompt(square: 'a8', choices: const [_wq, _wn, _wr, _wb], onSelected: picked.add);
    await tester.pumpWidget(_Host(pieces: const {'a7': _wp}, promotion: prompt));
    for (final square in ['a8', 'a7', 'a6', 'a5']) {
      expect(find.byKey(ValueKey('promotion-$square')), findsOneWidget);
    }
    await _tap(tester, 'a7');
    await _tap(tester, 'h1');
    expect(picked, [_wn, null]);

    // flipped: a8 is at the bottom, so the stack goes up
    await tester.pumpWidget(_Host(pieces: const {'a7': _wp}, promotion: prompt, flipped: true));
    expect(find.byKey(const ValueKey('promotion-a5')), findsOneWidget);
    await tester.tapAt(_center(tester, 'a6', flipped: true));
    expect(picked.last, _wr);
    expect(_host(tester).moves, isEmpty);
  });

  testWidgets('flipped: squares follow the orientation', (tester) async {
    await tester.pumpWidget(const _Host(pieces: _start, flipped: true));
    await tester.tapAt(_center(tester, 'g1', flipped: true));
    await tester.pump();
    await tester.tapAt(_center(tester, 'f3', flipped: true));
    await tester.pump();
    expect(_host(tester).moves.single, const BoardMove(from: 'g1', to: 'f3'));
  });

  group('drawing', () {
    Widget board(List<Shape> shapes, List<Shape> drawn, {VoidCallback? onClear, bool interactive = false}) => MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: ChessBoard(
              size: _size,
              pieces: _start,
              interactive: interactive,
              dests: interactive ? const {'e2': {'e3', 'e4'}} : const {},
              shapes: shapes,
              drawing: DrawingOptions(enabled: true, onShapeDrawn: drawn.add, onClear: onClear, brushForNewShape: () => 'red'),
            ),
          ),
        );

    testWidgets('a right-click drag draws an arrow, a right-click a circle', (tester) async {
      final drawn = <Shape>[];
      await tester.pumpWidget(board(const [], drawn));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await mouse.down(_corner('e2') + const Offset(20, 20));
      await tester.pump();
      expect(_board(tester).liveShape, const CircleShape(square: 'e2', brush: 'red'));
      await mouse.moveTo(_corner('e4') + const Offset(20, 20));
      await tester.pump();
      expect(_board(tester).liveShape, const ArrowShape(from: 'e2', to: 'e4', brush: 'red'));
      await mouse.up();
      await mouse.down(_corner('d5') + const Offset(20, 20));
      await mouse.up();
      await mouse.removePointer();
      expect(drawn, const [ArrowShape(from: 'e2', to: 'e4', brush: 'red'), CircleShape(square: 'd5', brush: 'red')]);
    });

    testWidgets('touch: a finger held on an empty square lets a second finger draw; a lone tap clears', (tester) async {
      final drawn = <Shape>[];
      var clears = 0;
      await tester.pumpWidget(board(const [], drawn, onClear: () => clears++, interactive: true));
      final hold = await tester.startGesture(_corner('a4') + const Offset(25, 25), pointer: 1);
      await tester.pump();
      final pen = await tester.startGesture(_corner('d2') + const Offset(25, 25), pointer: 2);
      await pen.moveTo(_corner('d3') + const Offset(25, 25));
      await pen.moveTo(_corner('d4') + const Offset(25, 25));
      await pen.up();
      await hold.up();
      await tester.pump();
      expect(drawn, const [ArrowShape(from: 'd2', to: 'd4', brush: 'red')]);
      expect(clears, 0, reason: 'the held finger was no tap');
      await tester.tapAt(_corner('a5') + const Offset(25, 25));
      await tester.pump();
      expect(clears, 1);
    });
  });

  group('editing', () {
    testWidgets('drag mode: any piece to any square; off the board removes it', (tester) async {
      final dropped = <(String, String)>[];
      final removed = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: ChessBoard(
            size: _size,
            pieces: _start,
            editing: BoardEditing(onPieceDropped: (a, b) => dropped.add((a, b)), onPieceRemoved: removed.add),
          ),
        ),
      ));
      await tester.dragFrom(_corner('e7') + const Offset(25, 25), const Offset(0, 150));
      await tester.dragFrom(_corner('g1') + const Offset(25, 25), const Offset(0, 300));
      expect(dropped, [('e7', 'e4')]);
      expect(removed, ['g1']);
    });

    testWidgets('paint mode: every square touched or slid over', (tester) async {
      final edited = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: ChessBoard(
            size: _size,
            pieces: const {},
            editing: BoardEditing(mode: BoardEditMode.paint, onSquareEdited: edited.add),
          ),
        ),
      ));
      final gesture = await tester.startGesture(_corner('a1') + const Offset(25, 25));
      await gesture.moveTo(_corner('b1') + const Offset(25, 25));
      await gesture.moveTo(_corner('c1') + const Offset(25, 25));
      await gesture.up();
      expect(edited, ['a1', 'b1', 'c1']);
    });
  });

  testWidgets('moves animate: the piece slides from its square, with animate false it jumps', (tester) async {
    Widget board(Map<String, Piece> pieces, {bool animate = true}) => MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: ChessBoard(size: _size, pieces: pieces, animate: animate, animationDuration: const Duration(milliseconds: 200)),
          ),
        );
    await tester.pumpWidget(board(const {'e2': _wp, 'd5': _bp}));
    await tester.pumpWidget(board(const {'e4': _wp, 'd5': _bp}));
    await tester.pump(const Duration(milliseconds: 100));
    final mid = tester.getTopLeft(find.byKey(const ValueKey('piece-e4')));
    expect(mid.dy, lessThan(_corner('e2').dy));
    expect(mid.dy, greaterThan(_corner('e4').dy));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey('piece-e4'))), _corner('e4'));

    // a capture: the taken piece fades out
    await tester.pumpWidget(board(const {'d5': _wp}));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('fading-d5')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fading-d5')), findsNothing);

    await tester.pumpWidget(board(const {'d6': _wp}, animate: false));
    expect(tester.getTopLeft(find.byKey(const ValueKey('piece-d6'))), _corner('d6'));
  });

  testWidgets('badges show their text', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ChessBoard(size: _size, pieces: {}, badges: {'e4': SquareBadge('1', color: Colors.indigo), 'e5': SquareBadge('2', color: Colors.indigo)}),
    ));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  test('squareAtOffset follows orientation and the outside margin', () {
    expect(squareAtOffset(const Offset(5, 5), size: _size), 'a8');
    expect(squareAtOffset(const Offset(5, 5), size: _size, flipped: true), 'h1');
    expect(squareAtOffset(const Offset(5, 5), size: _size, coordinates: CoordinatesMode.outside), isNull);
    expect(squareAtOffset(const Offset(399, 399), size: _size), 'h1');
  });
}
