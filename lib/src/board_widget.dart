/// The board widget: aspect-square CustomPaint with tap hit-testing and a
/// ticker that animates piece tweens.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
        onPointerDown: _handleTap,
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

  void _handleTap(PointerDownEvent event) {
    if (!widget.controller.config.interactive) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;
    final local = renderBox.globalToLocal(event.position);
    final geometry = widget.controller.geometry;
    final pos = geometry.positionAtPoint(
      local.dx,
      local.dy,
      renderBox.size.width,
      flip: widget.controller.config.flip,
    );
    if (pos == null) return;
    final key = geometry.formatKey(pos.$1, pos.$2);
    widget.onSquareTap?.call(key);
  }
}
