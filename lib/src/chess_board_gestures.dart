/// The chess board's pointer layer: one gesture-arena member for every
/// pointer that lands on the board.
library;

import 'package:flutter/gestures.dart';

/// What the board does with the pointers the recognizer reports.
abstract interface class BoardPointerSink {
  /// A pointer went down on the board. Return true to claim it at once
  /// (it starts on a piece the user may drag, or it already made a move),
  /// so an enclosing scrollable or page gesture can't take the drag.
  bool pointerDown(PointerDownEvent event);

  void pointerMove(PointerMoveEvent event);

  void pointerUp(PointerUpEvent event);

  /// The platform or the framework cancelled the pointer.
  void pointerCancel(PointerCancelEvent event);

  /// Another gesture (a scroll, a long press...) won this pointer.
  void pointerLost(int pointer);

  /// The recognizer is going away: forget every pointer.
  void pointersReset();
}

/// Tracks every pointer that goes down on the board, in the gesture arena.
///
/// Unlike a raw `Listener`, it takes part in the arena: a pointer that the
/// board claims on down (see [BoardPointerSink.pointerDown]) is won
/// immediately, so a `ListView` or a page's back-swipe never turns a piece
/// drag into a scroll. Pointers the board doesn't claim stay open to other
/// gestures (scrolling from an empty square works) and are given up on
/// pointer up, so a tap still reaches an enclosing `InkWell`.
///
/// Every pointer is tracked on its own: a lost pointer never blocks the
/// next one, and up/cancel always end the pointer's tracking.
class BoardGestureRecognizer extends OneSequenceGestureRecognizer {
  BoardGestureRecognizer({super.debugOwner}) : super(allowedButtonsFilter: _anyButton);

  static bool _anyButton(int buttons) => true;

  BoardPointerSink? sink;

  final Set<int> _claimed = {};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    final sink = this.sink;
    if (sink == null) return;
    startTrackingPointer(event.pointer, event.transform);
    if (sink.pointerDown(event)) {
      _claimed.add(event.pointer);
      resolvePointer(event.pointer, GestureDisposition.accepted);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    final sink = this.sink;
    if (event is PointerMoveEvent) {
      sink?.pointerMove(event);
    } else if (event is PointerUpEvent) {
      sink?.pointerUp(event);
      _finish(event.pointer);
    } else if (event is PointerCancelEvent) {
      sink?.pointerCancel(event);
      _finish(event.pointer);
    }
  }

  /// Ends [pointer]: unclaimed ones are given up before the arena sweeps,
  /// so another recognizer (a tap on a list row) may still win them.
  void _finish(int pointer) {
    if (!_claimed.remove(pointer)) {
      resolvePointer(pointer, GestureDisposition.rejected);
    }
    stopTrackingPointer(pointer);
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    _claimed.remove(pointer);
    sink?.pointerLost(pointer);
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  void dispose() {
    sink?.pointersReset();
    sink = null;
    super.dispose();
  }

  @override
  String get debugDescription => 'chess board';
}
