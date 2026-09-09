/// Lichess-style board drawing: arrows and circles drawn with a secondary
/// (right) button drag or shift+drag, erased from their origin, toggled by
/// redrawing. Mirrors the web engine's drawable vocabulary one-for-one so
/// games behave identically on both platforms.
library;

import 'dart:ui' show Color;

/// A drawing color: same families as chessground's defaults, in our own
/// tones (deliberately different hex values from the known lichess brushes).
class Brush {
  const Brush({
    required this.key,
    required this.color,
    this.opacity = 0.85,
    this.width = 1.0,
  });

  final String key;
  final Color color;

  /// Stroke opacity for shapes drawn with this brush.
  final double opacity;

  /// Stroke width multiplier (paleBlue draws wider, like chessground's).
  final double width;
}

const defaultBrushes = <Brush>[
  Brush(key: 'green', color: Color(0xFF2B8A3E)),
  Brush(key: 'red', color: Color(0xFFD64545)),
  Brush(key: 'blue', color: Color(0xFF2D6CDF)),
  Brush(key: 'yellow', color: Color(0xFFF5C518), opacity: 0.9),
  Brush(key: 'orange', color: Color(0xFFE8770E)),
  Brush(key: 'paleBlue', color: Color(0xFF6F9CEB), opacity: 0.45, width: 1.5),
];

/// A committed or in-progress drawing.
sealed class Shape {
  const Shape({required this.brush});

  final String brush;
}

class ArrowShape extends Shape {
  const ArrowShape({required this.from, required this.to, required super.brush});

  final String from;
  final String to;
}

class CircleShape extends Shape {
  const CircleShape({required this.square, required super.brush});

  final String square;
}

/// What a finished drag did: added, toggled off (removed) or recolored.
class DrawResult {
  const DrawResult({this.added, this.removed, this.changed});

  final Shape? added;
  final List<Shape>? removed;
  final Shape? changed;
}

/// Next brush in the cycle (shift while starting a draw rotates the color).
String nextBrush(List<Brush> brushes, String key) {
  final index = brushes.indexWhere((b) => b.key == key);
  return brushes[(index + 1) % brushes.length].key;
}

/// Shape bookkeeping: the committed list, the live drag, and the toggle /
/// erase semantics. The controller repaints after every mutation.
class DrawableController {
  DrawableController({required this.config});

  /// Live view of the drawable settings (the board controller owns it).
  DrawableSettings config;

  final List<Shape> shapes = [];

  /// Brush used by the last draw; shift-draws advance from here so the
  /// whole palette is reachable by cycling.
  String? _activeBrush;

  /// The shape growing under the pointer, or null.
  Shape? current;

  /// The brush the next plain draw will use.
  String get currentBrush => _activeBrush ?? config.defaultBrush;

  Brush brushOf(String key) =>
      config.brushes.firstWhere((b) => b.key == key, orElse: () => config.brushes.first);

  void setShapes(List<Shape> next) {
    shapes
      ..clear()
      ..addAll(next);
    current = null;
  }

  bool clearShapes() {
    if (shapes.isEmpty) return false;
    shapes.clear();
    return true;
  }

  /// Shapes a tap on `square` erases: circles standing there and arrows
  /// ORIGINATING there (the arrow's handle). Arrows that merely point at
  /// the square coexist with a circle drawn on it.
  List<Shape> erasableAt(String square) => shapes
      .where((s) =>
          s is CircleShape && s.square == square || s is ArrowShape && s.from == square)
      .toList();

  bool removeShapesAt(String square) {
    final erasable = erasableAt(square);
    if (erasable.isEmpty) return false;
    shapes.removeWhere(erasable.contains);
    return true;
  }

  /// Begin a drag on a square (shift rotates the brush color).
  void startDrag(String square, bool shiftKey) {
    final from = _activeBrush ?? config.defaultBrush;
    _activeBrush = shiftKey ? nextBrush(config.brushes, from) : from;
    current = CircleShape(square: square, brush: _activeBrush!);
  }

  /// Drag moved onto a (possibly different) square — arrow or circle grows.
  void moveDrag(String square) {
    final live = current;
    if (live == null) return;
    final String origin;
    if (live is CircleShape) {
      origin = live.square;
    } else if (live is ArrowShape) {
      origin = live.from;
    } else {
      return;
    }
    current = origin == square
        ? CircleShape(square: square, brush: live.brush)
        : ArrowShape(from: origin, to: square, brush: live.brush);
  }

  /// Finish the drag: an arrow between different squares (redrawing an
  /// existing arrow toggles it off — same brush — or recolors it); on the
  /// same square, the interaction erases existing shapes there or draws a
  /// circle.
  DrawResult? endDrag() {
    final shape = current;
    current = null;
    if (shape == null) return null;

    if (shape is CircleShape) {
      final present = erasableAt(shape.square);
      if (present.isNotEmpty) {
        shapes.removeWhere(present.contains);
        return DrawResult(removed: present);
      }
      shapes.add(shape);
      return DrawResult(added: shape);
    }
    if (shape is! ArrowShape) return null;

    final twin = shapes
        .whereType<ArrowShape>()
        .where((s) => s.from == shape.from && s.to == shape.to)
        .firstOrNull;
    if (twin != null) {
      if (twin.brush == shape.brush) {
        shapes.remove(twin);
        return DrawResult(removed: [twin]);
      }
      final index = shapes.indexOf(twin);
      shapes[index] = ArrowShape(from: twin.from, to: twin.to, brush: shape.brush);
      return DrawResult(changed: shapes[index]);
    }
    shapes.add(shape);
    return DrawResult(added: shape);
  }

  void cancelDrag() => current = null;
}

/// Drawable settings block of [BoardConfig].
class DrawableSettings {
  const DrawableSettings({
    this.enabled = false,
    this.brushes = defaultBrushes,
    this.defaultBrush = 'green',
    this.clearOnTap = true,
  });

  final bool enabled;
  final List<Brush> brushes;
  final String defaultBrush;
  final bool clearOnTap;

  DrawableSettings copyWith({
    bool? enabled,
    List<Brush>? brushes,
    String? defaultBrush,
    bool? clearOnTap,
  }) =>
      DrawableSettings(
        enabled: enabled ?? this.enabled,
        brushes: brushes ?? this.brushes,
        defaultBrush: defaultBrush ?? this.defaultBrush,
        clearOnTap: clearOnTap ?? this.clearOnTap,
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
