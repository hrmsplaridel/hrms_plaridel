import 'package:flutter/material.dart';

import 'package:hrms_plaridel/features/dtr/assistant/presentation/pages/employee_dtr_assistant_page.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/dtr_assistant_fab.dart';

/// Keeps the employee HRMS Assistant above modal filing surfaces.
///
/// The assistant route is pushed above the active form, so returning preserves
/// the employee's unfinished input.
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
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => const EmployeeDtrAssistantPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: child),
        DraggableDtrAssistantLauncher(
          onPressed: () => _openAssistant(context),
          initialRight: initialRight,
          initialBottom: initialBottom,
        ),
      ],
    );
  }
}
