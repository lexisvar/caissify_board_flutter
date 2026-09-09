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

## Quick start

```sh
flutter test     # 14 tests: geometry, state, controller, widget taps
flutter analyze  # clean
```

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
└─ board_widget.dart   # CaissifyBoard widget + gesture hit-testing
```

Sister package: **`caissify_board` for the web** (TypeScript).

## License

MIT — see [LICENSE](./LICENSE).
