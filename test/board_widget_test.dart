import 'package:caissify_board/caissify_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders any size and maps taps to squares', (tester) async {
    final controller = BoardController(config: const BoardConfig(size: 10));
    controller.setPieces({'b1': const Piece(role: 'knight', color: 'white')});
    controller.fx.addMarker('j10', '🎲');

    final taps = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: CaissifyBoard(controller: controller, onSquareTap: taps.add),
            ),
          ),
        ),
      ),
    );

    // board painted
    expect(find.byType(CaissifyBoard), findsOneWidget);

    // tap the four corners of the 200px board (20px squares)
    final topLeft = tester.getTopLeft(find.byType(CaissifyBoard));
    await tester.tapAt(topLeft + const Offset(10, 10)); // a10
    await tester.tapAt(topLeft + const Offset(190, 10)); // j10
    await tester.tapAt(topLeft + const Offset(10, 190)); // a1
    await tester.tapAt(topLeft + const Offset(190, 190)); // j1
    expect(taps, ['a10', 'j10', 'a1', 'j1']);
  });

  testWidgets('taps are ignored while not interactive', (tester) async {
    final controller = BoardController(
      config: const BoardConfig(size: 4, interactive: false),
    );
    final taps = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 100,
            height: 100,
            child: CaissifyBoard(controller: controller, onSquareTap: taps.add),
          ),
        ),
      ),
    );
    await tester.tapAt(tester.getCenter(find.byType(CaissifyBoard)));
    expect(taps, isEmpty);
  });
}
