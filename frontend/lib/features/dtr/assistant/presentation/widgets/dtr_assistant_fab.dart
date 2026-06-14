import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class DraggableDtrAssistantLauncher extends StatefulWidget {
  const DraggableDtrAssistantLauncher({
    super.key,
    required this.onPressed,
    this.initialRight = 16,
    this.initialBottom = 16,
  });

  final VoidCallback onPressed;
  final double initialRight;
  final double initialBottom;

  @override
  State<DraggableDtrAssistantLauncher> createState() =>
      _DraggableDtrAssistantLauncherState();
}

class _DraggableDtrAssistantLauncherState
    extends State<DraggableDtrAssistantLauncher> {
  static const double _edgePadding = 10;

  final ValueNotifier<Offset?> _position = ValueNotifier<Offset?>(null);
  final ValueNotifier<bool> _dragging = ValueNotifier<bool>(false);
  Offset _dragStartLocalPosition = Offset.zero;
  Offset _dragStartWidgetPosition = Offset.zero;

  @override
  void dispose() {
    _position.dispose();
    _dragging.dispose();
    super.dispose();
  }

  double _buttonSizeForWidth(double width) {
    if (width >= 900) return 124;
    if (width >= 600) return 108;
    return 88;
  }

  Offset _initialPosition(Size size) {
    final buttonSize = _buttonSizeForWidth(size.width);
    return Offset(
      size.width - widget.initialRight - buttonSize,
      size.height - widget.initialBottom - buttonSize,
    );
  }

  Offset _clamp(Offset value, Size size) {
    final buttonSize = _buttonSizeForWidth(size.width);
    final maxX = (size.width - buttonSize - _edgePadding).clamp(
      _edgePadding,
      double.infinity,
    );
    final maxY = (size.height - buttonSize - _edgePadding).clamp(
      _edgePadding,
      double.infinity,
    );
    return Offset(
      value.dx.clamp(_edgePadding, maxX).toDouble(),
      value.dy.clamp(_edgePadding, maxY).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final buttonSize = _buttonSizeForWidth(size.width);

          return ValueListenableBuilder<Offset?>(
            valueListenable: _position,
            builder: (context, position, child) {
              final effectivePosition = _clamp(
                position ?? _initialPosition(size),
                size,
              );

              return Stack(
                children: [
                  Transform.translate(
                    offset: effectivePosition,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (event) {
                          _dragStartLocalPosition = event.localPosition;
                          _dragStartWidgetPosition = effectivePosition;
                        },
                        onPointerMove: (event) {
                          final delta =
                              event.localPosition - _dragStartLocalPosition;
                          if (!_dragging.value &&
                              delta.distance >= 4.0) {
                            _dragging.value = true;
                          }
                          if (_dragging.value) {
                            _position.value = _clamp(
                              _dragStartWidgetPosition + delta,
                              size,
                            );
                          }
                        },
                        onPointerUp: (event) {
                          final delta =
                              event.localPosition - _dragStartLocalPosition;
                          _dragging.value = false;
                          if (delta.distance < 4.0) {
                            widget.onPressed();
                          }
                        },
                        onPointerCancel: (_) => _dragging.value = false,
                        child: child,
                      ),
                    ),
                  ),
                ],
              );
            },
            child: RepaintBoundary(
              child: ValueListenableBuilder<bool>(
                valueListenable: _dragging,
                builder: (context, dragging, _) {
                  return DtrAssistantFab(
                    size: buttonSize,
                    animate: !dragging,
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class DtrAssistantFab extends StatelessWidget {
  const DtrAssistantFab({super.key, this.size = 88, this.animate = true});

  final double size;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final animationSize = size * 0.94;
    final icon = SizedBox(
      width: animationSize,
      height: animationSize,
      child: Lottie.asset(
        'assets/animations/chatbot_assistant.json',
        animate: animate,
        repeat: true,
        renderCache: RenderCache.raster,
      ),
    );

    return Tooltip(
      message: 'Ask DTR Assistant',
      child: SizedBox(
        width: size,
        height: size,
        child: Center(child: icon),
      ),
    );
  }
}
