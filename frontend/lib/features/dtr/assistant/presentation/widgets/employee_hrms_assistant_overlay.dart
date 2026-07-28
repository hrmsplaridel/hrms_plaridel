import 'package:flutter/material.dart';

import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/dtr_assistant_fab.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/employee_hrms_assistant_controller.dart';

/// Keeps the employee HRMS Assistant available above modal filing surfaces.
///
/// The root floating panel does not replace the active form route, so unfinished
/// employee input remains visible and intact while they chat.
class EmployeeHrmsAssistantOverlay extends StatelessWidget {
  const EmployeeHrmsAssistantOverlay({
    super.key,
    required this.child,
    this.initialRight = 20,
    this.initialBottom = 28,
  });

  final Widget child;
  final double initialRight;
  final double initialBottom;

  void _openAssistant(BuildContext context) {
    EmployeeHrmsAssistantController.instance.openFullPage(context);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: child),
        ValueListenableBuilder<bool>(
          valueListenable:
              EmployeeHrmsAssistantController.instance.floatingVisible,
          builder: (context, assistantOpen, _) => assistantOpen
              ? const SizedBox.shrink()
              : DraggableDtrAssistantLauncher(
                  onPressed: () => _openAssistant(context),
                  initialRight: initialRight,
                  initialBottom: initialBottom,
                ),
        ),
      ],
    );
  }
}
