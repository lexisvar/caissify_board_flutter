import 'package:caissify_board/caissify_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('coordinate config', () {
    test('defaults to none and copies through', () {
      expect(const BoardConfig().coordinates, CoordinatesMode.none);
      const cfg = BoardConfig(coordinates: CoordinatesMode.outside);
      expect(cfg.copyWith().coordinates, CoordinatesMode.outside);
      expect(
        cfg.copyWith(coordinates: CoordinatesMode.inside).coordinates,
        CoordinatesMode.inside,
      );
    });
  });

  group('coordinate layout', () {
    test('outside mode reserves an even band on all four sides', () {
      final (origin, extent) =
          coordLayout(const Size(400, 400), CoordinatesMode.outside);
      expect(origin.dx, 24.0); // 6% of 400
      expect(extent, 352.0); // 400 - 2*24: symmetric frame
      final (zero, full) =
          coordLayout(const Size(400, 400), CoordinatesMode.inside);
      expect(zero, Offset.zero);
      expect(full, 400.0);
    });
  });

  testWidgets('taps still map to squares with outside coordinates',
      (tester) async {
    final controller = BoardController(
      config: const BoardConfig(coordinates: CoordinatesMode.outside),
    );
    final taps = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: CaissifyBoard(controller: controller, onSquareTap: taps.add),
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(CaissifyBoard));
    // a1 center inside the even 24px frame: board = 352px, cell = 35.2
    await tester.tapAt(rect.topLeft + const Offset(24 + 17.6, 24 + 9.5 * 35.2));
    await tester.pump();
    expect(taps, ['a1']);
  });

  testWidgets('painting with inside coordinates on a 10x10 does not throw',
      (tester) async {
    final controller = BoardController(
      config: const BoardConfig(
        size: 10,
        coordinates: CoordinatesMode.inside,
      ),
    );
    controller.setPieces({'j10': const Piece(role: 'knight', color: 'white')});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: CaissifyBoard(controller: controller),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CaissifyBoard), findsOneWidget);
  });
}
