import 'package:flutter/material.dart';

/// Opens [builder] as:
/// - full-screen route on narrow viewports (below [breakpoint])
/// - right-side slide-in panel on wide screens with a draggable left edge to resize width
///
/// Drag the left edge horizontally to widen/narrow the panel; double-tap the edge to toggle
/// between max width and the initial width (same behavior as the leave filing form).
Future<T?> openResponsiveRightSidePanel<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double breakpoint = 1100,
  String barrierLabel = 'Close panel',
  double minWidth = 360,
  double initialWidthFraction = 0.52,
}) async {
  final viewportWidth = MediaQuery.of(context).size.width;
  final useDesktopPanel = viewportWidth >= breakpoint;
  if (!useDesktopPanel) {
    return Navigator.of(context).push<T>(MaterialPageRoute(builder: builder));
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: barrierLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, a1, a2) {
      final initialWidth = (viewportWidth * initialWidthFraction).clamp(
        minWidth,
        viewportWidth * 0.9,
      );
      final maxWidth = (viewportWidth - 16).clamp(minWidth, viewportWidth);
      return SafeArea(
        child: _ResizableRightPanel(
          initialWidth: initialWidth,
          minWidth: minWidth,
          maxWidth: maxWidth,
          child: builder(ctx),
        ),
      );
    },
    transitionBuilder: (ctx, anim, sec, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class _ResizableRightPanel extends StatefulWidget {
  const _ResizableRightPanel({
    required this.initialWidth,
    required this.minWidth,
    required this.maxWidth,
    required this.child,
  });

  final double initialWidth;
  final double minWidth;
  final double maxWidth;
  final Widget child;

  @override
  State<_ResizableRightPanel> createState() => _ResizableRightPanelState();
}

class _ResizableRightPanelState extends State<_ResizableRightPanel> {
  late double _width;

  @override
  void initState() {
    super.initState();
    _width = widget.initialWidth;
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.white,
        elevation: 12,
        child: SizedBox(
          width: _width,
          height: double.infinity,
          child: Stack(
            children: [
              Positioned.fill(child: widget.child),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        // Panel is right-aligned: dragging left expands width.
                        _width = (_width - details.delta.dx).clamp(
                          widget.minWidth,
                          widget.maxWidth,
                        );
                      });
                    },
                    onDoubleTap: () {
                      setState(() {
                        _width = _width >= widget.maxWidth - 1
                            ? widget.initialWidth
                            : widget.maxWidth;
                      });
                    },
                    child: Container(
                      width: 12,
                      color: Colors.transparent,
                      alignment: Alignment.center,
                      child: Container(
                        width: 3,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
