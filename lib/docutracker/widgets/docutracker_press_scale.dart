import 'package:flutter/material.dart';

/// Subtle press-in scale feedback for buttons and chips.
class DocuTrackerPressScale extends StatefulWidget {
  const DocuTrackerPressScale({
    super.key,
    required this.child,
    this.pressedScale = 0.985,
  });

  final Widget child;
  final double pressedScale;

  @override
  State<DocuTrackerPressScale> createState() => _DocuTrackerPressScaleState();
}

class _DocuTrackerPressScaleState extends State<DocuTrackerPressScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        scale: _pressed ? widget.pressedScale : 1.0,
        child: widget.child,
      ),
    );
  }
}
