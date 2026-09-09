/// First-class board effects: square markers, temporary piece reactions and
/// sound "moments" the host maps onto its audio system. Mirrors the web
/// engine's fx vocabulary so games feel identical on both platforms.
library;

import 'dart:async';

import 'state.dart';

class SoundMoment {
  const SoundMoment(this.moment, {this.detail});

  /// Vocabulary moment: 'move:start' | 'piece:land' | 'fx:marker' | …
  final String moment;
  final String? detail;
}

class Marker {
  Marker({
    required this.id,
    required this.square,
    required this.content,
    required this.front,
    this.className,
  });

  final int id;
  final String square;
  final String content;
  final bool front;
  final String? className;
}


class FxController {
  FxController({void Function(SoundMoment moment)? onSound})
      : _onSound = onSound;

  final void Function(SoundMoment moment)? _onSound;
  final Map<int, Marker> markers = {};
  final Map<String, String> activeReactions = {};

  int _nextId = 1;
  final List<Timer> _timers = [];

  int addMarker(String square, String content, {bool front = false, String? sound}) {
    final marker = Marker(id: _nextId++, square: square, content: content, front: front);
    markers[marker.id] = marker;
    if (sound != null) _onSound?.call(SoundMoment('fx:marker', detail: sound));
    return marker.id;
  }

  void removeMarker(int id) => markers.remove(id);

  void clearMarkers() => markers.clear();

  /// Attach a named reaction to the piece standing on `square` for a while.
  void pieceReaction(BoardState state, String square, String reaction, Duration duration) {
    if (state.pieceAt(square) == null) return;
    activeReactions[square] = reaction;
    Timer? timer;
    timer = Timer(duration, () {
      activeReactions.remove(square);
      _timers.remove(timer);
    });
    _timers.add(timer);
  }

  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    markers.clear();
    activeReactions.clear();
  }
}
