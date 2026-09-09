/// The board widget: aspect-square CustomPaint with tap hit-testing and a
/// ticker that animates piece tweens.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/gestures.dart' show kPrimaryButton, kSecondaryButton;
import 'package:flutter/services.dart' show HardwareKeyboard;

import 'board_painter.dart';
import 'controller.dart';

class CaissifyBoard extends StatefulWidget {
  const CaissifyBoard({
    super.key,
    required this.controller,
    this.onSquareTap,
  });

  final BoardController controller;
  final void Function(String square)? onSquareTap;

  @override
  State<CaissifyBoard> createState() => _CaissifyBoardState();
}

class _CaissifyBoardState extends State<CaissifyBoard>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  bool _ticking = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    widget.controller.addListener(_onControllerChanged);
    _maybeStartTicker();
  }

  void _onControllerChanged() {
    _maybeStartTicker();
    if (mounted) setState(() {});
  }

  void _maybeStartTicker() {
    if (widget.controller.tweens.isNotEmpty && !_ticking) {
      _ticker.start();
      _ticking = true;
    }
  }

  void _onTick(Duration elapsed) {
    final stillAnimating = widget.controller.pruneTweens();
    widget.controller.repaint();
    if (!stillAnimating) {
      _ticker.stop();
      _ticking = false;
    }
  }

  @override
  void didUpdateWidget(CaissifyBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AspectRatio(
      aspectRatio: 1,
      child: Listener(
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: (_) => widget.controller.endDraw(),
        child: CustomPaint(
          painter: BoardPainter(
            controller: controller,
            config: controller.config,
            geometry: controller.geometry,
            state: controller.state,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }

  String? _squareAt(Offset position) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return null;
    final local = renderBox.globalToLocal(position);
    final geometry = widget.controller.geometry;
    final pos = geometry.positionAtPoint(
      local.dx,
      local.dy,
      renderBox.size.width,
      flip: widget.controller.config.flip,
    );
    if (pos == null) return null;
    return geometry.formatKey(pos.$1, pos.$2);
  }

  void _handlePointerDown(PointerDownEvent event) {
    final controller = widget.controller;
    if (!controller.config.interactive) return;
    final square = _squareAt(event.position);
    if (square == null) return;

    // chessground parity: a drawing starts on the secondary (right) button
    // or on shift+drag with the primary one
    final drawable = controller.config.drawable;
    final wantsDraw = drawable.enabled &&
        (event.buttons & kSecondaryButton != 0 ||
            (event.buttons & kPrimaryButton != 0 && HardwareKeyboard.instance.isShiftPressed));
    if (wantsDraw) {
      controller.startDraw(square, HardwareKeyboard.instance.isShiftPressed);
      return;
    }
    if (event.buttons & kPrimaryButton == 0) return;
    if (drawable.enabled && drawable.clearOnTap && controller.clearShapes()) {
      // tap clears the board; the tap itself still flows to the host
    }
    widget.onSquareTap?.call(square);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final square = _squareAt(event.position);
    if (square != null) widget.controller.moveDraw(square);
  }
}

