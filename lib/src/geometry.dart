/// Board geometry for any N×N board (4, 6, 8, 9, 10…).
///
/// Files are letters a…, ranks are numbers 1…N — including two-digit ranks
/// (a 10×10 board runs a1…j10). This library is the ONLY place that knows
/// how square keys are spelled.
library;

class BoardGeometry {
  const BoardGeometry(this.size);

  final int size;

  factory BoardGeometry.create(int size) {
    if (size < 2 || size > 26) {
      throw ArgumentError('board size must be between 2 and 26, got $size');
    }
    return BoardGeometry(size);
  }

  /// 'j10' → (file: 9, rank: 9); null when off-board or malformed.
  (int, int)? parseKey(String key) {
    if (!RegExp(r'^[a-z]([1-9]|1[0-9]|2[0-6])$').hasMatch(key)) return null;
    final file = key.codeUnitAt(0) - 97;
    final rank = int.parse(key.substring(1)) - 1;
    return contains(file, rank) ? (file, rank) : null;
  }

  /// (9, 9) → 'j10'.
  String formatKey(int file, int rank) {
    if (!contains(file, rank)) {
      throw ArgumentError('[$file,$rank] is outside a $size×$size board');
    }
    return String.fromCharCode(97 + file) + (rank + 1).toString();
  }

  bool isValidKey(String key) => parseKey(key) != null;

  bool contains(int file, int rank) =>
      file >= 0 && file < size && rank >= 0 && rank < size;

  /// Every key in reading order (rank N … 1, file a …).
  List<String> allKeys() {
    final keys = <String>[];
    for (var rank = size - 1; rank >= 0; rank--) {
      for (var file = 0; file < size; file++) {
        keys.add(formatKey(file, rank));
      }
    }
    return keys;
  }

  /// Convert a point in board-pixel space to (file, rank), or null outside.
  (int, int)? positionAtPoint(double x, double y, double pixels, {bool flip = false}) {
    if (pixels <= 0) return null;
    var fx = (size * x / pixels).floor();
    var ry = (size * y / pixels).floor();
    if (fx < 0 || fx >= size || ry < 0 || ry >= size) return null;
    final file = flip ? size - 1 - fx : fx;
    final rank = flip ? ry : size - 1 - ry;
    return (file, rank);
  }

  /// Top-left pixel of a square inside a board of `pixels`.
  (double, double) pointOfPosition(int file, int rank, double pixels, {bool flip = false}) {
    final fx = flip ? size - 1 - file : file;
    final ry = flip ? rank : size - 1 - rank;
    return (fx * pixels / size, ry * pixels / size);
  }
}

/// Standard chess parity: a1 and every (file+rank) even square is dark.
bool isLightSquare(int file, int rank) => (file + rank) % 2 == 1;
