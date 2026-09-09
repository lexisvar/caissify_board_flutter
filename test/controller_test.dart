import 'package:caissify_board/caissify_board.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('board state', () {
    test('manages pieces by key, including two-digit keys', () {
      final state = BoardState();
      state.setPiece('j10', const Piece(role: 'queen', color: 'purple'));
      expect(state.pieceAt('j10')?.role, 'queen');
      expect(state.movePiece('j10', 'a1'), isTrue);
      expect(state.pieceAt('a1')?.role, 'queen');
      expect(state.movePiece('j10', 'b2'), isFalse);
      state.setPiece('a1', null);
      expect(state.pieces, isEmpty);
    });

    test('tracks square annotations', () {
      final state = BoardState();
      state.setSquareClasses('c4', ['selected', 'dice']);
      expect(state.squareClasses('c4'), containsAll(['selected', 'dice']));
      state.setSquareClasses('c4', []);
      expect(state.squareClasses('c4'), isEmpty);
    });
  });

  group('board controller', () {
    test('moves pieces and emits sound moments', () {
      final controller = BoardController(config: const BoardConfig(size: 10, animate: false));
      final moments = <String>[];
      controller.listenSound((moment) => moments.add(moment.moment));
      controller.setPieces({'j1': const Piece(role: 'knight', color: 'white')});
      expect(controller.movePiece('j1', 'h2'), isTrue);
      expect(controller.state.pieceAt('h2')?.role, 'knight');
      expect(moments, contains('move:start'));
      // off-board squares are rejected
      expect(controller.movePiece('h2', 'z9'), isFalse);
    });

    test('reconfiguring size drops off-board pieces and markers', () {
      final controller = BoardController(config: const BoardConfig(size: 10));
      controller.setPieces({'j10': const Piece(role: 'rook', color: 'black')});
      controller.fx.addMarker('j10', '🎲');
      controller.configure(const BoardConfig(size: 8));
      expect(controller.state.pieces, isEmpty);
      expect(controller.fx.markers, isEmpty);
      expect(controller.geometry.size, 8);
    });

    test('tweens progress with the injected clock and report landing', () {
      final controller = BoardController(
        config: const BoardConfig(size: 8, animate: true, animationDuration: Duration(milliseconds: 100)),
      );
      var now = 0.0;
      controller.clock = () => now;
      final landed = <String>[];
      controller.listenSound((moment) {
        if (moment.moment == 'piece:land') landed.add(moment.moment);
      });
      controller.setPieces({'b1': const Piece(role: 'knight', color: 'white')});
      expect(controller.movePiece('b1', 'c3'), isTrue);
      expect(controller.tweens, isNotEmpty);

      now = 0.05;
      final mid = controller.pieceOffset('c3', flip: false);
      expect(mid.$1, greaterThan(1.0)); // between b (1) and c (2)
      expect(mid.$1, lessThan(2.0));

      now = 0.2;
      expect(controller.pruneTweens(), isFalse); // finished
      expect(landed, isNotEmpty);
      final end = controller.pieceOffset('c3', flip: false);
      expect((end.$1, end.$2), (2.0, 5.0)); // c3 = column 2, row 5
    });
  });

  group('fx controller', () {
    test('markers and reactions', () {
      final controller = BoardController(config: const BoardConfig(size: 8));
      final state = controller.state;
      state.setPiece('e4', const Piece(role: 'knight', color: 'white'));
      final id = controller.fx.addMarker('e4', '🎲', front: true);
      expect(controller.fx.markers[id]?.square, 'e4');
      controller.fx.removeMarker(id);
      expect(controller.fx.markers, isEmpty);
      controller.fx.pieceReaction(state, 'e4', 'hop', const Duration(milliseconds: 5));
      expect(controller.fx.activeReactions['e4'], 'hop');
    });
  });
}
