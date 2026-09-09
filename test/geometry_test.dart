import 'package:caissify_board/caissify_board.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('geometry across board sizes', () {
    test('rejects invalid sizes', () {
      expect(() => BoardGeometry.create(1), throwsArgumentError);
      expect(() => BoardGeometry.create(27), throwsArgumentError);
    });

    test('parses and formats keys, including two-digit ranks', () {
      final ten = BoardGeometry.create(10);
      expect(ten.parseKey('j10'), (9, 9));
      expect(ten.parseKey('a1'), (0, 0));
      expect(ten.formatKey(9, 9), 'j10');
      expect(ten.isValidKey('j10'), isTrue);
      expect(ten.isValidKey('k5'), isFalse);
      expect(ten.isValidKey('a0'), isFalse);
      expect(ten.isValidKey('a11'), isFalse);

      final nine = BoardGeometry.create(9);
      expect(nine.isValidKey('i9'), isTrue);
      expect(nine.isValidKey('j9'), isFalse);
      expect(nine.isValidKey('i10'), isFalse);
    });

    test('enumerates every square once, in reading order', () {
      for (final size in [4, 6, 8, 9, 10]) {
        final geometry = BoardGeometry.create(size);
        final keys = geometry.allKeys();
        expect(keys.length, size * size);
        expect(keys.toSet().length, size * size);
        expect(keys.first, 'a$size');
        expect(keys.last, '${String.fromCharCode(96 + size)}1');
      }
      expect(BoardGeometry.create(10).allKeys()[9], 'j10');
    });

    test('maps points to squares and back (hit-testing core)', () {
      final ten = BoardGeometry.create(10);
      expect(ten.positionAtPoint(225, 275, 500), (4, 4));
      expect(ten.positionAtPoint(-1, 10, 500), isNull);
      expect(ten.pointOfPosition(9, 9, 500), (450.0, 0.0));

      final four = BoardGeometry.create(4);
      expect(four.positionAtPoint(99, 99, 100), (3, 0));
      expect(four.pointOfPosition(0, 0, 100), (0.0, 75.0));
    });

    test('supports flipped orientation', () {
      final nine = BoardGeometry.create(9);
      expect(nine.positionAtPoint(5, 85, 90, flip: true), (8, 8));
      expect(nine.pointOfPosition(8, 8, 90, flip: true), (0.0, 80.0));
    });

    test('knows standard square parity (a1 dark, h1 light)', () {
      expect(isLightSquare(0, 0), isFalse);
      expect(isLightSquare(7, 0), isTrue);
      expect(isLightSquare(0, 7), isTrue);
    });
  });
}
