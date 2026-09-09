/// Board configuration — one validated object.
library;

import 'dart:ui' show Color;

import 'drawable.dart';

class BoardConfig {
  const BoardConfig({
    this.size = 8,
    this.light = const Color(0xFFF0D9B5),
    this.dark = const Color(0xFFB58863),
    this.flip = false,
    this.interactive = true,
    this.animate = true,
    this.animationDuration = const Duration(milliseconds: 180),
    this.pieceFontFamily,
    this.drawable = const DrawableSettings(),
  });

  final int size;
  final Color light;
  final Color dark;
  final bool flip;
  final bool interactive;
  final bool animate;
  final Duration animationDuration;
  final String? pieceFontFamily;
  final DrawableSettings drawable;

  BoardConfig copyWith({
    int? size,
    Color? light,
    Color? dark,
    bool? flip,
    bool? interactive,
    bool? animate,
    Duration? animationDuration,
    String? pieceFontFamily,
    DrawableSettings? drawable,
  }) {
    final next = BoardConfig(
      size: size ?? this.size,
      light: light ?? this.light,
      dark: dark ?? this.dark,
      flip: flip ?? this.flip,
      interactive: interactive ?? this.interactive,
      animate: animate ?? this.animate,
      animationDuration: animationDuration ?? this.animationDuration,
      pieceFontFamily: pieceFontFamily ?? this.pieceFontFamily,
      drawable: drawable ?? this.drawable,
    );
    if (next.size < 2 || next.size > 26) {
      throw ArgumentError('board size must be between 2 and 26, got ${next.size}');
    }
    return next;
  }
}
