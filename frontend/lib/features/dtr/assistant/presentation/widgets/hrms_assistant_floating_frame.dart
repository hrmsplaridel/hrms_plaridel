import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

class HrmsAssistantFloatingFrame extends StatefulWidget {
  const HrmsAssistantFloatingFrame({super.key, required this.child});

  final Widget child;

  @override
  State<HrmsAssistantFloatingFrame> createState() =>
      _HrmsAssistantFloatingFrameState();
}

class _HrmsAssistantFloatingFrameState
    extends State<HrmsAssistantFloatingFrame> {
  static const double _desktopBreakpoint = 700;
  static const double _edgePadding = 16;
  static const double _mobileEdgePadding = 12;
  static const double _desktopPanelWidth = 440;
  static const double _desktopPanelMaxHeight = 720;
  static const double _mobilePanelMaxWidth = 360;
  static const double _mobilePanelMaxHeight = 560;

  Offset? _position;

  Offset _clampPosition(
    Offset value,
    Size viewport,
    Size panel, {
    double edgePadding = _edgePadding,
  }) {
    final maxX = math.max(
      edgePadding,
      viewport.width - panel.width - edgePadding,
    );
    final maxY = math.max(
      edgePadding,
      viewport.height - panel.height - edgePadding,
    );
    return Offset(
      value.dx.clamp(edgePadding, maxX).toDouble(),
      value.dy.clamp(edgePadding, maxY).toDouble(),
    );
  }

  void _movePanel(
    DragUpdateDetails details,
    Size viewport,
    Size panel, {
    double edgePadding = _edgePadding,
  }) {
    final current = _clampPosition(
      _position ??
          Offset(
            viewport.width - panel.width - edgePadding,
            math.min(72.0, viewport.height - panel.height - edgePadding),
          ),
      viewport,
      panel,
      edgePadding: edgePadding,
    );
    setState(() {
      _position = _clampPosition(
        current + details.delta,
        viewport,
        panel,
        edgePadding: edgePadding,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          final mobile = viewport.width < _desktopBreakpoint;
          final edgePadding = mobile ? _mobileEdgePadding : _edgePadding;
          final panel = mobile
              ? Size(
                  math.min(
                    _mobilePanelMaxWidth,
                    math.max(0.0, viewport.width - (edgePadding * 2)),
                  ),
                  math.min(
                    _mobilePanelMaxHeight,
                    math.min(
                      math.max(400.0, viewport.height * 0.62),
                      math.max(0.0, viewport.height - (edgePadding * 2)),
                    ),
                  ),
                )
              : Size(
                  math.min(
                    _desktopPanelWidth,
                    math.max(0.0, viewport.width - (_edgePadding * 2)),
                  ),
                  math.min(
                    _desktopPanelMaxHeight,
                    math.max(0.0, viewport.height - (_edgePadding * 2)),
                  ),
                );
          final position = _clampPosition(
            _position ??
                Offset(
                  viewport.width - panel.width - edgePadding,
                  mobile
                      ? viewport.height - panel.height - edgePadding
                      : math.min(
                          72.0,
                          viewport.height - panel.height - edgePadding,
                        ),
                ),
            viewport,
            panel,
            edgePadding: edgePadding,
          );

          return Stack(
            children: [
              Positioned(
                key: const ValueKey('hrms-assistant-floating-panel'),
                left: position.dx,
                top: position.dy,
                width: panel.width,
                height: panel.height,
                child: Material(
                  elevation: 14,
                  color: AppTheme.dashPanelOf(context),
                  shadowColor: Colors.black.withValues(alpha: 0.24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: AppTheme.dashHairlineOf(context)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: MediaQuery(
                          data: MediaQuery.of(context).copyWith(size: panel),
                          child: widget.child,
                        ),
                      ),
                      Positioned(
                        key: const ValueKey(
                          'hrms-assistant-floating-drag-handle',
                        ),
                        left: 0,
                        top: 0,
                        right: mobile ? 136 : 152,
                        height: 56,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.move,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onPanUpdate: (details) => _movePanel(
                              details,
                              viewport,
                              panel,
                              edgePadding: edgePadding,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
