/// The board controller: state + config + effects + animation tweens in one
/// ChangeNotifier. The board renders and animates; the game decides.
library;

import 'package:flutter/foundation.dart';

import 'config.dart';
import 'drawable.dart';
import 'effects.dart';
import 'geometry.dart';
import 'state.dart';

class BoardController extends ChangeNotifier {
  BoardController({BoardConfig config = const BoardConfig()})
      : _config = _validated(config) {
    geometry = BoardGeometry(_config.size);
  }

  static BoardConfig _validated(BoardConfig config) {
    // force validation on construction (copyWith validates too)
    return config.copyWith();
  }

  final BoardState state = BoardState();
  late BoardGeometry geometry;
  BoardConfig _config;

  late final FxController fx = FxController(onSound: _emitSound);

  late final DrawableController drawable = DrawableController(config: _config.drawable);

  /// Drawing lifecycle hooks, mirroring the web engine's shape:add /
  /// shape:remove / shape:change / shapes:clear events.
  void Function(Shape shape)? onShapeAdd;
  void Function(List<Shape> shapes)? onShapeRemove;
  void Function(Shape shape)? onShapeChange;
  void Function()? onShapesClear;

  final List<void Function(SoundMoment)> _soundListeners = [];

  /// Injectable clock for tests (defaults to the wall clock).
  ///
  /// The default deliberately avoids SchedulerBinding.currentFrameTimeStamp:
  /// that value is only valid WHILE a frame is being built, and hosts
  /// legitimately mutate the board from pointer callbacks, which fire
  /// between frames — reading it there asserts
  /// (_currentFrameTimeStamp != null) and kills the event handler.
  /// Wall-clock microseconds keep tween math monotonic in every context.
  double Function() clock = () => DateTime.now().microsecondsSinceEpoch / 1e6;

  final List<BoardTween> tweens = [];

  BoardConfig get config => _config;

  void listenSound(void Function(SoundMoment moment) listener) {
    _soundListeners.add(listener);
  }

  void _emitSound(SoundMoment moment) {
    for (final listener in _soundListeners) {
      listener(moment);
    }
  }

  /// Replace the whole position (no animation).
  void setPieces(Map<String, Piece> pieces) {
    state.pieces
      ..clear()
      ..addAll(pieces);
    notifyListeners();
  }

  /// Move a piece, animated when enabled. Returns false when impossible.
  bool movePiece(String from, String to) {
    if (geometry.parseKey(from) == null || geometry.parseKey(to) == null) {
      return false;
    }
    final piece = state.pieceAt(from);
    if (piece == null) return false;
    if (!state.movePiece(from, to)) return false;
    _emitSound(const SoundMoment('move:start'));
    if (_config.animate) {
      tweens.add(BoardTween(
        piece: to,
        from: from,
        to: to,
        startedAt: _now(),
        duration: _config.animationDuration,
      ));
    }
    notifyListeners();
    return true;
  }

  /// Replace the drawing overlay (arrows/circles) from the host.
  void setShapes(List<Shape> next) {
    drawable.setShapes(next);
    notifyListeners();
  }

  /// Clear every drawing; returns true when there was anything to clear.
  bool clearShapes() {
    final cleared = drawable.clearShapes();
    if (cleared) {
      onShapesClear?.call();
      notifyListeners();
    }
    return cleared;
  }

  /// Begin a right/shift drag on a square (renderer input plumbing).
  void startDraw(String square, bool shiftKey) {
    if (!_config.drawable.enabled) return;
    drawable.config = _config.drawable;
    drawable.startDrag(square, shiftKey);
    notifyListeners();
  }

  void moveDraw(String square) {
    if (drawable.current == null) return;
    drawable.moveDrag(square);
    notifyListeners();
  }

  /// Finish a drag and fire the matching lifecycle hook.
  void endDraw() {
    final result = drawable.endDrag();
    if (result == null) {
      notifyListeners();
      return;
    }
    final added = result.added;
    if (added != null) onShapeAdd?.call(added);
    final removed = result.removed;
    if (removed != null) onShapeRemove?.call(removed);
    final changed = result.changed;
    if (changed != null) onShapeChange?.call(changed);
    notifyListeners();
  }

  void setSquareClasses(String square, List<String> classes) {
    if (geometry.parseKey(square) == null) return;
    state.setSquareClasses(square, classes);
    notifyListeners();
  }

  void selectSquare(String? square) {
    state.selected = square;
    notifyListeners();
  }

  void configure(BoardConfig config) {
    final next = config.copyWith();
    if (next.size != _config.size) {
      geometry = BoardGeometry.create(next.size);
      state.pieces.removeWhere((key, _) => !geometry.isValidKey(key));
      state.squares.removeWhere((key, _) => !geometry.isValidKey(key));
      fx.clearMarkers();
      tweens.clear();
      drawable.setShapes(const []);
      drawable.cancelDrag();
    }
    _config = next;
    drawable.config = next.drawable;
    notifyListeners();
  }

  /// Render offset for a piece: its square, or its tween interpolation.
  /// Returns pixel factors (0..size) that the painter scales by cell size.
  (double, double) pieceOffset(String key, {required bool flip}) {
    final tween = tweens.where((t) => t.piece == key).firstOrNull;
    if (tween == null) return _squareOffset(key, flip: flip);
    final t = _easeOutCubic(tween.progressAt(_now()));
    final from = _squareOffsetRaw(tween.from, flip: flip);
    final to = _squareOffsetRaw(tween.to, flip: flip);
    return (from.$1 + (to.$1 - from.$1) * t, from.$2 + (to.$2 - from.$2) * t);
  }

  (double, double) _squareOffset(String key, {required bool flip}) =>
      _squareOffsetRaw(key, flip: flip);

  (double, double) _squareOffsetRaw(String key, {required bool flip}) {
    final pos = geometry.parseKey(key);
    if (pos == null) return (0, 0);
    final (file, rank) = pos;
    final fx0 = flip ? geometry.size - 1 - file : file;
    final ry = flip ? rank : geometry.size - 1 - rank;
    return (fx0.toDouble(), ry.toDouble());
  }

  double _easeOutCubic(double t) => 1 - (1 - t) * (1 - t) * (1 - t);

  /// Drop finished tweens; returns true when any animation is still active
  /// (the widget keeps its ticker running while true).
  bool pruneTweens() {
    if (tweens.isEmpty) return false;
    final now = _now();
    tweens.removeWhere((tween) {
      if (tween.progressAt(now) >= 1) {
        _emitSound(const SoundMoment('piece:land'));
        return true;
      }
      return false;
    });
    return tweens.isNotEmpty;
  }

  double _now() => clock();

  /// Public repaint trigger for renderers ticking animations.
  void repaint() => notifyListeners();

  @override
  void dispose() {
    fx.dispose();
    _soundListeners.clear();
    super.dispose();
  }
}

class BoardTween {
  BoardTween({
    required this.piece,
    required this.from,
    required this.to,
    required this.startedAt,
    required this.duration,
  });

  final String piece;
  final String from;
  final String to;
  final double startedAt;
  final Duration duration;

  double progressAt(double now) {
    final seconds = duration.inMicroseconds / 1e6;
    if (seconds <= 0) return 1;
    return ((now - startedAt) / seconds).clamp(0.0, 1.0);
  }
}


extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
