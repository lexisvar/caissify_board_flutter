import 'package:caissify_board/caissify_board.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('brush palette', () {
    test('keeps the standard families but not the chessground tones', () {
      // chessground's default brush hexes (incl. the translucent paleBlue)
      const chessground = [0xFF15781B, 0xFF882020, 0xFF003088, 0xFFE68F00];
      for (final brush in defaultBrushes) {
        expect(chessground, isNot(contains(brush.color.toARGB32())));
      }
      expect(
        defaultBrushes.map((b) => b.key).toList(),
        ['green', 'red', 'blue', 'yellow', 'orange', 'paleBlue'],
      );
      final paleBlue = defaultBrushes.firstWhere((b) => b.key == 'paleBlue');
      expect(paleBlue.opacity, lessThan(0.6));
      expect(paleBlue.width, greaterThan(1));
    });
  });

  group('DrawableController semantics (web parity)', () {
    DrawableController drawable() =>
        DrawableController(config: const DrawableSettings(enabled: true));

    test('a drag between squares commits an arrow; the same arrow toggles off', () {
      final d = drawable();
      d.startDrag('a1', false);
      d.moveDrag('c2');
      final first = d.endDrag();
      expect(first?.added, isA<ArrowShape>());
      expect(d.shapes, hasLength(1));

      d.startDrag('a1', false);
      d.moveDrag('c2');
      final second = d.endDrag();
      expect(second?.added, isNull);
      expect(second?.removed, hasLength(1));
      expect(d.shapes, isEmpty);
    });

    test('redrawing an arrow with another brush recolors it', () {
      final d = drawable();
      d.startDrag('a1', false);
      d.moveDrag('c2');
      d.endDrag();
      d.startDrag('a1', true); // shift advances: red
      d.moveDrag('c2');
      final result = d.endDrag();
      expect(result?.changed, isA<ArrowShape>());
      expect(d.shapes, hasLength(1));
      expect((d.shapes.single as ArrowShape).brush, 'red');
    });

    test('opposite directions stay distinct', () {
      final d = drawable();
      d.startDrag('a1', false);
      d.moveDrag('c2');
      d.endDrag();
      d.startDrag('c2', false);
      d.moveDrag('a1');
      d.endDrag();
      expect(d.shapes, hasLength(2));
    });

    test('a circle on an arrow target coexists; the origin click erases the arrow', () {
      final d = drawable();
      d.startDrag('a1', false);
      d.moveDrag('c2');
      d.endDrag();
      // circle on the target square
      d.startDrag('c2', false);
      d.endDrag();
      expect(d.shapes, hasLength(2)); // arrow + circle
      // right-click the ORIGIN: the arrow goes, the circle stays
      d.startDrag('a1', false);
      final result = d.endDrag();
      expect(result?.removed, hasLength(1));
      expect(d.shapes.single, isA<CircleShape>());
    });

    test('shift-draws walk the whole palette from the active brush', () {
      final d = drawable();
      // three advances from green land on yellow — impossible if cycling
      // restarted at the default every time
      for (final target in ['c2', 'd3', 'e4']) {
        d.startDrag('a1', true);
        d.moveDrag(target);
        d.endDrag();
      }
      expect(
        d.shapes.map((s) => s.brush).toList(),
        ['red', 'blue', 'yellow'],
      );
    });

    test('setShapes/clearShapes drive the overlay for hosts', () {
      final d = drawable();
      d.setShapes(const [
        ArrowShape(from: 'a1', to: 'h8', brush: 'blue'),
        CircleShape(square: 'd4', brush: 'yellow'),
      ]);
      expect(d.shapes, hasLength(2));
      expect(d.clearShapes(), isTrue);
      expect(d.shapes, isEmpty);
      expect(d.clearShapes(), isFalse);
    });
  });

  group('board integration', () {
    test('controller exposes shapes and lifecycle hooks', () {
      final controller = BoardController(
        config: const BoardConfig(
          drawable: DrawableSettings(enabled: true),
        ),
      );
      final added = <Shape>[];
      final removed = <List<Shape>>[];
      controller.onShapeAdd = added.add;
      controller.onShapeRemove = removed.add;

      controller.startDraw('a1', false);
      controller.moveDraw('c2');
      controller.endDraw();
      expect(added, hasLength(1));

      controller.startDraw('a1', false);
      controller.moveDraw('c2');
      controller.endDraw();
      expect(removed, hasLength(1));
      expect(controller.drawable.shapes, isEmpty);
    });

    testWidgets('a secondary-button drag paints an arrow on the board',
        (tester) async {
      final controller = BoardController(
        config: const BoardConfig(
          drawable: DrawableSettings(enabled: true),
        ),
      );
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

      final rect = tester.getRect(find.byType(CaissifyBoard));
      final gesture = await tester.startGesture(
        rect.topLeft + const Offset(25, 375), // a1 on an 8x8 of 400px
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await gesture.moveTo(rect.topLeft + const Offset(125, 325)); // c2
      await gesture.up();
      await tester.pump();

      expect(controller.drawable.shapes, hasLength(1));
      final arrow = controller.drawable.shapes.single;
      expect(arrow, isA<ArrowShape>());
      expect((arrow as ArrowShape).from, 'a1');
      expect(arrow.to, 'c2');
      expect(arrow.brush, 'green');
    });

    testWidgets('a plain tap clears shapes and still fires onSquareTap',
        (tester) async {
      final controller = BoardController(
        config: const BoardConfig(
          drawable: DrawableSettings(enabled: true),
        ),
      );
      final taps = <String>[];
      controller.setShapes(const [CircleShape(square: 'd4', brush: 'green')]);

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
      await tester.tapAt(rect.topLeft + const Offset(225, 225)); // ~e5
      await tester.pump();

      expect(controller.drawable.shapes, isEmpty);
      expect(taps, isNotEmpty);
    });
  });
}
