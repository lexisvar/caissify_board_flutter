/// Headless board state: pieces and per-square annotations.
library;

class Piece {
  const Piece({required this.role, required this.color, this.data});

  final String role;
  final String color;
  final Map<String, Object>? data;

  /// `'<color>-<role>'`, e.g. `white-knight` (the [BoardConfig.pieceArt]
  /// key and a handy asset name).
  String get kind => '$color-$role';

  @override
  bool operator ==(Object other) =>
      other is Piece && other.role == role && other.color == color && identical(other.data, data);

  @override
  int get hashCode => Object.hash(role, color, data);

  @override
  String toString() => 'Piece($kind)';
}


class BoardState {
  final Map<String, Piece> pieces = {};
  final Map<String, Set<String>> squares = {};
  String? selected;

  Piece? pieceAt(String key) => pieces[key];

  void setPiece(String key, Piece? piece) {
    if (piece == null) {
      pieces.remove(key);
    } else {
      pieces[key] = piece;
    }
  }

  bool movePiece(String from, String to) {
    final piece = pieces[from];
    if (piece == null) return false;
    pieces.remove(from);
    pieces[to] = piece;
    return true;
  }

  List<String> squareClasses(String key) =>
      (squares[key] ?? const {}).toList(growable: false);

  void setSquareClasses(String key, List<String> classes) {
    if (classes.isEmpty) {
      squares.remove(key);
    } else {
      squares[key] = classes.toSet();
    }
  }

  String? findPiece(bool Function(Piece piece, String key) predicate) {
    for (final entry in pieces.entries) {
      if (predicate(entry.value, entry.key)) return entry.key;
    }
    return null;
  }
}
