import 'dart:async';

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
  static const double _bubbleGap = 8;
  static const double _bubbleHeight = 40;

  final ValueNotifier<Offset?> _position = ValueNotifier<Offset?>(null);
  final ValueNotifier<bool> _dragging = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _showGreeting = ValueNotifier<bool>(false);
  Timer? _showGreetingTimer;
  Timer? _hideGreetingTimer;
  Offset _dragStartLocalPosition = Offset.zero;
  Offset _dragStartWidgetPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _showGreetingTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted || _dragging.value) return;
      _showGreeting.value = true;
      _hideGreetingTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) _showGreeting.value = false;
      });
    });
  }

  @override
  void dispose() {
    _showGreetingTimer?.cancel();
    _hideGreetingTimer?.cancel();
    _position.dispose();
    _dragging.dispose();
    _showGreeting.dispose();
    super.dispose();
  }

  void _hideGreeting() {
    _hideGreetingTimer?.cancel();
    _showGreeting.value = false;
  }

  double _buttonSizeForWidth(double width) {
    if (width >= 900) return 124;
    if (width >= 600) return 108;
    return 88;
  }

  double _bubbleWidthForButton(double buttonSize) {
    if (buttonSize >= 108) return 214;
    return 188;
  }

  bool _shouldShowBubbleOnLeft(
    Offset position,
    Size size,
    double buttonSize,
    double bubbleWidth,
  ) {
    final rightRoom = size.width - (position.dx + buttonSize) - _edgePadding;
    final leftRoom = position.dx - _edgePadding;
    final requiredRoom = bubbleWidth + _bubbleGap;

    if (rightRoom >= requiredRoom && leftRoom < requiredRoom) return false;
    if (leftRoom >= requiredRoom && rightRoom < requiredRoom) return true;
    if (rightRoom >= requiredRoom && leftRoom >= requiredRoom) {
      return position.dx + (buttonSize / 2) > size.width / 2;
    }
    return position.dx + (buttonSize / 2) > size.width / 2;
  }

  Offset _bubblePosition({
    required Offset buttonPosition,
    required Size size,
    required double buttonSize,
    required double bubbleWidth,
    required bool onLeft,
  }) {
    final preferredLeft = onLeft
        ? buttonPosition.dx - bubbleWidth - _bubbleGap
        : buttonPosition.dx + buttonSize + _bubbleGap;
    final maxLeft = (size.width - bubbleWidth - _edgePadding).clamp(
      _edgePadding,
      double.infinity,
    );
    final maxTop = (size.height - _bubbleHeight - _edgePadding).clamp(
      _edgePadding,
      double.infinity,
    );

    return Offset(
      preferredLeft.clamp(_edgePadding, maxLeft).toDouble(),
      (buttonPosition.dy + ((buttonSize - _bubbleHeight) / 2))
          .clamp(_edgePadding, maxTop)
          .toDouble(),
    );
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
              final bubbleWidth = _bubbleWidthForButton(buttonSize);
              final bubbleOnLeft = _shouldShowBubbleOnLeft(
                effectivePosition,
                size,
                buttonSize,
                bubbleWidth,
              );
              final bubblePosition = _bubblePosition(
                buttonPosition: effectivePosition,
                size: size,
                buttonSize: buttonSize,
                bubbleWidth: bubbleWidth,
                onLeft: bubbleOnLeft,
              );

              return Stack(
                children: [
                  Positioned(
                    left: bubblePosition.dx,
                    top: bubblePosition.dy,
                    child: IgnorePointer(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _dragging,
                        builder: (context, dragging, _) {
                          return ValueListenableBuilder<bool>(
                            valueListenable: _showGreeting,
                            builder: (context, showGreeting, _) {
                              final visible = showGreeting && !dragging;
                              return AnimatedOpacity(
                                opacity: visible ? 1 : 0,
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                                child: AnimatedSlide(
                                  offset: visible
                                      ? Offset.zero
                                      : Offset(bubbleOnLeft ? -0.04 : 0.04, 0),
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOut,
                                  child: _AssistantGreetingBubble(
                                    width: bubbleWidth,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
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
                          if (!_dragging.value && delta.distance >= 4.0) {
                            _dragging.value = true;
                            _hideGreeting();
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
                            _hideGreeting();
                            widget.onPressed();
                          }
                        },
                        onPointerCancel: (_) {
                          _dragging.value = false;
                          _hideGreeting();
                        },
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
                  return DtrAssistantFab(size: buttonSize, animate: !dragging);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AssistantGreetingBubble extends StatelessWidget {
  const _AssistantGreetingBubble({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF1F2937) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: dark
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.black.withValues(alpha: 0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.24 : 0.12),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Text(
            'Hi, need help with DTR?',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: dark ? Colors.white : const Color(0xFF111827),
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
        ),
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
