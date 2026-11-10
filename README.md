# caissify_board (Flutter · Dart)

Headless **N×N board engine** with first-class game effects.

> The board renders and animates; the game decides.

The Flutter sister of the TypeScript `caissify_board` engine — same
vocabulary (square keys `a1`…`j10`, pieces as `{role, color}` tokens,
markers/reactions/sound moments) so a game feels identical on both
platforms. No code was copied from Chessground; the architecture lessons
(headless state, cached bounds, tween queue, transform-style motion) are
re-implemented natively.

## Features

- Any board size 2×2…26×26, including odd 9×9 boards and 10×10 with
  two-digit ranks (`j10`).
- Headless core: `BoardController` (a `ChangeNotifier`) owns state, config,
  effects and animation tweens — rules belong to the host game.
- `CaissifyBoard` widget: aspect-square `CustomPaint` renderer with
  exact-any-N checkerboard, square annotations, glyph piece tokens,
  markers behind/in front of pieces, and tap hit-testing.
- Effects vocabulary: `fx.addMarker('j10', '🎲')`,
  `fx.pieceReaction(...)`, sound moments via `controller.listenSound`.
- Injectable clock for deterministic animation tests.
- `ChessBoard`: a declarative, rule-agnostic chess board widget (below),
  with a touch layer built for phones.

## Quick start

```sh
flutter test     # 58 tests: geometry, state, controller, drawing, ChessBoard gestures
flutter analyze  # clean
```

## ChessBoard

```dart
ChessBoard(
  size: 360,
  pieces: {'e2': Piece(role: 'pawn', color: 'white'), ...},
  dests: {'e2': {'e3', 'e4'}, 'g1': {'f3', 'h3'}}, // who may move, and where
  onMove: (move) => game.play(move.from, move.to),   // the host checks rules
  pieceBuilder: (context, piece, size) => Image.asset('pieces/${piece.kind}.png'),
)
```

The host passes the pieces and, for each square whose piece may move now,
its destinations (`dests`; `premoveDests` for premoves); the board reports
a `BoardMove` and never checks rules. It also takes the last move, a king
in check, square tints, badges, arrows and circles (`shapes`), a promotion
picker (`PromotionPrompt`), coordinates (none / inside / outside), a
texture or flat colours (`ChessBoardStyle`), animation, and a set-up mode
(`BoardEditing`: drag pieces anywhere, or "paint" squares). The engine
ships no piece art: hosts pass a `pieceBuilder` (glyph tokens otherwise).

Moving: tap a piece, then a destination; or drag it. Touch handling:

- **One gesture-arena member** (`BoardGestureRecognizer`) tracks every
  pointer on the board. A pointer that goes down on a piece the user may
  move (or premove), or that completes a tap move, is claimed at once, so
  an enclosing `ListView`, `PageView` or back-swipe can't turn the drag
  into a scroll (iOS and Android). Other pointers are left to the page:
  a vertical swipe from an empty square or an opponent's piece scrolls,
  and a tap on a fixed board still reaches an enclosing `InkWell`.
- **Never stuck**: each pointer is tracked on its own and every pointer
  down starts afresh; a cancelled pointer ends its drag; a second finger
  during a drag is ignored (and doesn't swallow the next tap); a pointer
  whose up never arrived is replaced by the next touch (during a drag,
  once it has been silent for `kStaleDragPointer`). A position or
  orientation change mid-gesture drops a drag that no longer makes sense
  but keeps one that does, and rebuilding with the same position (a clock
  ticking) keeps the selection and the drag.
- **Drag feedback anchored to the grab point**: the dragged piece follows
  the finger with the point you grabbed staying under it (optional
  `dragScale` up to 1.5 grows it around that point). The square under the
  finger is highlighted and is the drop square.
- Drawing: right-button drag (mouse), or a finger held on an empty square
  while a second finger draws (touch).

## Usage

```dart
final controller = BoardController(config: const BoardConfig(size: 10));
controller.setPieces({'b1': const Piece(role: 'knight', color: 'white')});
controller.fx.addMarker('j10', '🎲');
controller.listenSound((moment) => audio.play(moment.moment));

CaissifyBoard(
  controller: controller,
  onSquareTap: (square) {
    // your rules live here
    controller.movePiece(selected, square);
  },
)
```

Piece moves tween with a ticker; `BoardConfig.animate: false` disables.

## Package layout

```
lib/src/
├─ geometry.dart       # the ONLY place square keys are spelled (a1…j10)
├─ state.dart          # pieces + square annotations (headless)
├─ config.dart         # size, colors, flip, interactive, animation
├─ effects.dart        # markers, reactions, sound moments
├─ controller.dart     # ChangeNotifier: state + tweens + fx
├─ board_painter.dart  # CustomPainter renderer
├─ board_widget.dart   # CaissifyBoard widget + gesture hit-testing
├─ shape_painter.dart  # arrows and circles, shared by both widgets
├─ chess_board.dart          # ChessBoard widget (pieces, highlights, drag)
├─ chess_board_gestures.dart # its gesture-arena recognizer
└─ chess_board_models.dart   # BoardMove, ChessBoardStyle, PromotionPrompt…
```

Sister package: **`caissify_board` for the web** (TypeScript).

## License

MIT — see [LICENSE](./LICENSE).
